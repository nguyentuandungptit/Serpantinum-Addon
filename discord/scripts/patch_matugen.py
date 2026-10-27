#!/usr/bin/env python3
"""Patch Serpantinum's theme singletons so the Discord theme stays in sync.

The Discord addon needs a few surgical fixes in the shell. They all live in
``src/quickshell/singletons`` and are applied in place, anchored on the upstream
source:

``theme/Matugen.qml``
    1. ``matugenBaseDir``: ``SERPANTINUM_DIR`` already ends in ``/src``
       (``scripts/caching.sh`` derives it from ``<root>/src/scripts``), but the
       binding appends another ``/src``. matugen then gets a config path of
       ``<root>/src/src/assets/matugen/config.toml`` and dies immediately with
       "Could not find the provided config file". Because the old code ran
       matugen through ``Process`` and ignored stderr, the failure was silent:
       blur tokens kept syncing (they are substituted by ``discord_sync.sh``)
       while the colours never changed.
    2. ``toMd3()``: ``discord-theme.css.template`` references
       ``{{colors.outline_variant}}``. Static palettes never provided that role,
       so matugen aborted with "ResolveError at discord:NN:NN".
    3. ``syncDiscord()``: ``ThemeBackend`` forces ``blurBackground`` off inside
       the standalone settings window. Without a fallback to the saved setting,
       picking a colour in that window rewrites the Discord theme with
       ``--serp-backdrop-blur: none`` even though blur is enabled.

``theme/ThemeBackend.qml`` (optional, when present)
    The same blur fallback for its own ``syncDiscord()`` helper.

``system/Config.qml`` (optional)
    ``settings.json`` is shared by the shell and the standalone settings window.
    Two races let one process resurrect stale values (for example turning blur
    back off): the file watcher drops external changes that arrive while a write
    is in flight, and ``Component.onDestruction`` writes ``rawSettings``
    unconditionally on quit. Both are closed here.

Every edit is idempotent, so re-running the installer after a shell update
re-applies the patches on top of whatever upstream looks like. Each original
file is kept next to it as ``<name>.pre-discord-addon`` for ``--revert``.

Usage:
    patch_matugen.py <Matugen.qml>            apply
    patch_matugen.py --revert <Matugen.qml>   restore the backups

Exit codes:
    0  applied, already applied, or reverted
    2  file not found
    3  upstream Matugen.qml changed and the patch no longer applies
"""

import os
import re
import shutil
import sys

BACKUP_SUFFIX = ".pre-discord-addon"

BASE_DIR_MARKER = 'serpDir.endsWith("/src")'
OUTLINE_MARKER = "outline_variant:"
BLUR_FALLBACK_MARKER = "let savedTheme ="
CONFIG_DESTRUCTION_MARKER = "Only flush a write that is still queued"
CONFIG_RELOAD_MARKER = "onLoaded ignores file changes that arrive while a write"
THEME_TAB_MARKER = "Re-render the Discord theme immediately"

BASE_DIR_ANCHOR = re.compile(
    r'(?P<indent>[ \t]*)if \(serpDir !== ""\) \{\n'
    r'[ \t]*return serpDir \+ "/src/assets/matugen";\n'
    r'[ \t]*\}'
)

OUTLINE_ANCHOR = re.compile(
    r'^(?P<indent>[ \t]*)outline:[ \t]+colorsObj\.subtext1,[ \t]*$',
    re.MULTILINE,
)

MATUGEN_BLUR_ANCHOR = re.compile(
    r'^(?P<indent>[ \t]*)let blurBg = \(typeof ThemeBackend !== "undefined" '
    r'&& ThemeBackend\.blurBackground\) \? "true" : "false";[ \t]*$',
    re.MULTILINE,
)

THEME_BLUR_ANCHOR = re.compile(
    r'^(?P<indent>[ \t]*)let blurBg = root\.blurBackground \? "true" : "false";[ \t]*$',
    re.MULTILINE,
)

CONFIG_DESTRUCTION_ANCHOR = re.compile(
    r'(?P<indent>[ \t]*)Component\.onDestruction: \{\n'
    r'[ \t]*let targetObj = pendingPayload !== null \? pendingPayload : rawSettings;\n'
    r'[ \t]*let str = JSON\.stringify\(targetObj, null, 2\);\n'
    r'[ \t]*lastWrittenContent = str;\n'
    r'[ \t]*Quickshell\.execDetached\(\["bash", "-c", writerScript, "_", '
    r'settingsJsonPath, str \+ "\\n"\]\);\n'
    r'[ \t]*\}'
)

CONFIG_EXITED_ANCHOR = re.compile(
    r'(?P<indent>[ \t]*)\} else \{\n'
    r'[ \t]*config\.settingsLoaded\(\);\n'
    r'(?P=indent)\}'
)


def function_anchor(name):
    """Match a QML function body so a hunk can be appended before its closing brace."""
    return re.compile(
        r'(?P<indent>[ \t]*)function ' + name + r'\((?P<args>[^)]*)\) \{\n'
        r'(?P<body>(?:[ \t]*[^\n]*\n)*?)'
        r'(?P=indent)\}'
    )


THEME_TAB_BLUR_ANCHOR = function_anchor("updateBlurBackgroundSetting")
THEME_TAB_STYLE_ANCHOR = function_anchor("updateBlurStyleSetting")


def base_dir_replacement(match):
    indent = match.group("indent")
    return (
        f'{indent}// SERPANTINUM_DIR is "<root>/src"; some launchers export "<root>".\n'
        f'{indent}if (serpDir.endsWith("/src")) {{\n'
        f'{indent}    serpDir = serpDir.substring(0, serpDir.length - 4);\n'
        f'{indent}}}\n'
        f'{indent}if (serpDir !== "" && serpDir !== "/") {{\n'
        f'{indent}    return serpDir + "/src/assets/matugen";\n'
        f'{indent}}}'
    )


def blur_fallback_replacement(expression, match):
    indent = match.group("indent")
    return (
        f'{indent}// ThemeBackend forces blurBackground off inside the standalone\n'
        f'{indent}// settings window. Fall back to the saved setting so picking a\n'
        f'{indent}// colour there does not strip the blur/glass from Discord.\n'
        f'{indent}let savedTheme = (typeof Config !== "undefined") '
        f'? Config.getSetting("theme", {{}}) : {{}};\n'
        f'{indent}let blurBg = ({expression}\n'
        f'{indent}    || (savedTheme && savedTheme.blurBackground === true)) '
        f'? "true" : "false";'
    )


def config_destruction_replacement(match):
    indent = match.group("indent")
    return (
        f'{indent}Component.onDestruction: {{\n'
        f'{indent}    // Only flush a write that is still queued or in flight.\n'
        f'{indent}    // settings.json is shared with the other Quickshell process, so\n'
        f'{indent}    // writing rawSettings on every quit would resurrect stale values\n'
        f'{indent}    // (for example turning blur back off after a colour was picked).\n'
        f'{indent}    if (pendingPayload === null && !isWriting) return;\n'
        f'{indent}    let targetObj = pendingPayload !== null ? pendingPayload : rawSettings;\n'
        f'{indent}    let str = JSON.stringify(targetObj, null, 2);\n'
        f'{indent}    lastWrittenContent = str;\n'
        f'{indent}    Quickshell.execDetached(["bash", "-c", writerScript, "_", '
        f'settingsJsonPath, str + "\\n"]);\n'
        f'{indent}}}'
    )


def config_exited_replacement(match):
    indent = match.group("indent")
    inner = indent + "    "
    return (
        f'{indent}}} else {{\n'
        f'{inner}config.settingsLoaded();\n'
        f'{inner}// onLoaded ignores file changes that arrive while a write is in\n'
        f'{inner}// flight. Re-read once the writer is idle so changes made by the\n'
        f'{inner}// other Quickshell process are not lost.\n'
        f'{inner}settingsWatcher.reload();\n'
        f'{indent}}}'
    )


def theme_tab_replacement(match):
    indent = match.group("indent")
    inner = indent + "    "
    addition = (
        f'{inner}// Re-render the Discord theme immediately so toggling blur\n'
        f'{inner}// does not wait for the next wallpaper or colour change.\n'
        f'{inner}if (typeof ThemeBackend !== "undefined" '
        f'&& typeof ThemeBackend.syncElementOpacity === "function") {{\n'
        f'{inner}    ThemeBackend.syncElementOpacity();\n'
        f'{inner}}}\n'
        f'{inner}if (typeof Matugen !== "undefined" '
        f'&& typeof Matugen.syncDiscord === "function") {{\n'
        f'{inner}    Matugen.syncDiscord();\n'
        f'{inner}}}\n'
    )
    body = match.group(0)
    return body[: -len(indent) - 1] + addition + indent + "}"


def patch_theme_tab(text):
    anchors = (
        (THEME_TAB_BLUR_ANCHOR, "updateBlurBackgroundSetting(): sync Discord now"),
        (THEME_TAB_STYLE_ANCHOR, "updateBlurStyleSetting(): sync Discord now"),
    )

    present = False
    changed = []
    for anchor, label in anchors:
        match = anchor.search(text)
        if match is None:
            continue
        present = True
        if THEME_TAB_MARKER in match.group(0):
            continue
        text = anchor.sub(theme_tab_replacement, text, count=1)
        changed.append(label)

    if not present:
        return None
    return text, changed


def read(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()

def write(path, text):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def backup_once(path):
    backup = path + BACKUP_SUFFIX
    if not os.path.isfile(backup):
        shutil.copy2(path, backup)
        print(f"Backed up original to: {backup}")


def patch_matugen(text):
    if "matugenBaseDir" not in text or "function toMd3" not in text or "function syncDiscord" not in text:
        raise ValueError(
            "does not look like the Matugen.qml this addon patches"
        )

    changed = []

    if BASE_DIR_MARKER not in text:
        text, count = BASE_DIR_ANCHOR.subn(base_dir_replacement, text, count=1)
        if count != 1:
            raise ValueError(
                "could not find the matugenBaseDir block; the Discord theme will\n"
                "       keep the blur but colours will not follow the wallpaper"
            )
        changed.append("matugenBaseDir: normalized trailing /src")

    if OUTLINE_MARKER not in text:
        match = OUTLINE_ANCHOR.search(text)
        if match is None:
            raise ValueError(
                "could not find the 'outline: colorsObj.subtext1' line in toMd3();\n"
                "       static palettes will fail with a ResolveError"
            )
        indent = match.group("indent")
        insertion = f"\n{indent}outline_variant:          colorsObj.surface2,"
        text = text[: match.end()] + insertion + text[match.end():]
        changed.append("toMd3(): added outline_variant role")

    if BLUR_FALLBACK_MARKER not in text:
        text, count = MATUGEN_BLUR_ANCHOR.subn(
            lambda m: blur_fallback_replacement(
                '(typeof ThemeBackend !== "undefined" && ThemeBackend.blurBackground)',
                m,
            ),
            text,
            count=1,
        )
        if count != 1:
            raise ValueError(
                "could not find the blurBg line in syncDiscord(); colour picks\n"
                "       from the standalone settings window will drop the blur"
            )
        changed.append("syncDiscord(): fall back to the saved blur setting")

    return text, changed


def patch_theme_backend(text):
    if BLUR_FALLBACK_MARKER in text:
        return text, []
    if THEME_BLUR_ANCHOR.search(text) is None:
        return None

    text = THEME_BLUR_ANCHOR.sub(
        lambda m: blur_fallback_replacement("root.blurBackground", m),
        text,
        count=1,
    )
    return text, ["syncDiscord(): fall back to the saved blur setting"]


def patch_config(text):
    changed = []

    if CONFIG_DESTRUCTION_MARKER not in text:
        text, count = CONFIG_DESTRUCTION_ANCHOR.subn(
            config_destruction_replacement, text, count=1
        )
        if count != 1:
            raise ValueError("could not find Component.onDestruction")
        changed.append("onDestruction: stop clobbering settings.json on quit")

    if CONFIG_RELOAD_MARKER not in text:
        text, count = CONFIG_EXITED_ANCHOR.subn(config_exited_replacement, text, count=1)
        if count != 1:
            raise ValueError("could not find the writer's onExited handler")
        changed.append("onExited: re-read settings.json after each write")

    return text, changed


def apply_file(path, patcher, required):
    if not os.path.isfile(path):
        if required:
            print(f"Error: {path} not found.", file=sys.stderr)
            return 2
        print(f"Skipped (not present): {path}")
        return 0

    try:
        result = patcher(read(path))
    except ValueError as error:
        if required:
            print(f"Error: {path} {error}.", file=sys.stderr)
            return 3
        print(f"Warning: {path} {error}; skipping.", file=sys.stderr)
        return 0

    if result is None:
        print(f"Not applicable in this shell version: {path}")
        return 0

    text, changed = result

    if not changed:
        print(f"Already patched: {path}")
        return 0

    backup_once(path)
    write(path, text)
    for item in changed:
        print(f"Patched: {item}")
    print(f"Patched file: {path}")
    return 0


def revert_file(path, markers, required):
    if not os.path.isfile(path):
        if required:
            print(f"Error: {path} not found.", file=sys.stderr)
            return 2
        print(f"Skipped (not present): {path}")
        return 0

    backup = path + BACKUP_SUFFIX
    if not os.path.isfile(backup):
        print(f"No addon backup for {path}; nothing to restore.")
        return 0

    text = read(path)
    if not any(marker in text for marker in markers):
        os.remove(backup)
        print(f"Shell is not patched; removed stale backup: {backup}")
        return 0

    shutil.move(backup, path)
    print(f"Restored original shell file: {path}")
    return 0


def main(argv):
    args = [arg for arg in argv[1:] if arg not in ("--revert", "-r")]
    revert = len(args) != len(argv) - 1

    if len(args) != 1:
        print("Usage: patch_matugen.py [--revert] <Matugen.qml>", file=sys.stderr)
        return 2

    matugen_path = os.path.abspath(args[0])
    if not os.path.isfile(matugen_path):
        print(f"Error: {matugen_path} not found.", file=sys.stderr)
        return 2

    theme_dir = os.path.dirname(matugen_path)
    singletons_dir = os.path.dirname(theme_dir)
    quickshell_dir = os.path.dirname(singletons_dir)
    theme_backend_path = os.path.join(theme_dir, "ThemeBackend.qml")
    config_path = os.path.join(singletons_dir, "system", "Config.qml")
    theme_tab_path = os.path.join(quickshell_dir, "guide", "theme", "ThemeTabState.qml")

    if revert:
        status = revert_file(matugen_path, (BASE_DIR_MARKER, OUTLINE_MARKER, BLUR_FALLBACK_MARKER), required=True)
        status = revert_file(theme_backend_path, (BLUR_FALLBACK_MARKER,), required=False) or status
        status = revert_file(config_path, (CONFIG_DESTRUCTION_MARKER, CONFIG_RELOAD_MARKER), required=False) or status
        status = revert_file(theme_tab_path, (THEME_TAB_MARKER,), required=False) or status
        return status

    status = apply_file(matugen_path, patch_matugen, required=True)
    if status != 0:
        return status
    apply_file(theme_backend_path, patch_theme_backend, required=False)
    apply_file(config_path, patch_config, required=False)
    apply_file(theme_tab_path, patch_theme_tab, required=False)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
