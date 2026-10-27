#!/usr/bin/env python3
"""Patch Serpantinum's Matugen.qml so the Discord theme receives colours.

The Discord addon needs two surgical fixes in the shell singleton
``src/quickshell/singletons/theme/Matugen.qml``:

1. ``matugenBaseDir``: ``SERPANTINUM_DIR`` already ends in ``/src``
   (``scripts/caching.sh`` derives it from ``<root>/src/scripts``), but the
   binding appends another ``/src``. matugen then gets a config path of
   ``<root>/src/src/assets/matugen/config.toml`` and dies immediately with
   "Could not find the provided config file". Because the old code ran matugen
   through ``Process`` and ignored stderr, the failure was silent: blur tokens
   kept syncing (they are substituted by ``discord_sync.sh``) while the colours
   never changed.

2. ``toMd3()``: ``discord-theme.css.template`` references
   ``{{colors.outline_variant}}``. Static palettes never provided that role, so
   matugen aborted with "ResolveError at discord:NN:NN".

Both edits are idempotent and anchor on the upstream source instead of copying
a whole file, so re-running the installer after a shell update re-applies them
on top of whatever upstream looks like. The original file is kept next to it as
``Matugen.qml.pre-discord-addon`` for ``--revert``.

Usage:
    patch_matugen.py <Matugen.qml>            apply
    patch_matugen.py --revert <Matugen.qml>   restore the backup

Exit codes:
    0  applied, already applied, or reverted
    2  file not found
    3  upstream source changed and the patch no longer applies
"""

import os
import re
import shutil
import sys

BACKUP_SUFFIX = ".pre-discord-addon"

BASE_DIR_MARKER = 'serpDir.endsWith("/src")'
OUTLINE_MARKER = "outline_variant:"

BASE_DIR_ANCHOR = re.compile(
    r'(?P<indent>[ \t]*)if \(serpDir !== ""\) \{\n'
    r'[ \t]*return serpDir \+ "/src/assets/matugen";\n'
    r'[ \t]*\}'
)

OUTLINE_ANCHOR = re.compile(
    r'^(?P<indent>[ \t]*)outline:[ \t]+colorsObj\.subtext1,[ \t]*$',
    re.MULTILINE,
)


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


def apply_patch(path):
    text = read(path)

    if "matugenBaseDir" not in text or "function toMd3" not in text:
        print(
            f"Error: {path} does not look like the Matugen.qml this addon patches.",
            file=sys.stderr,
        )
        return 3

    changed = []

    if BASE_DIR_MARKER not in text:
        text, count = BASE_DIR_ANCHOR.subn(base_dir_replacement, text, count=1)
        if count != 1:
            print(
                "Error: could not find the matugenBaseDir block. Upstream changed it;\n"
                "       the addon patch needs updating (the Discord theme will keep the\n"
                "       blur but colours will not follow the wallpaper).",
                file=sys.stderr,
            )
            return 3
        changed.append("matugenBaseDir: normalized trailing /src")

    if OUTLINE_MARKER not in text:
        match = OUTLINE_ANCHOR.search(text)
        if match is None:
            print(
                "Error: could not find the 'outline: colorsObj.subtext1' line in toMd3().\n"
                "       Upstream changed it; the addon patch needs updating (static\n"
                "       palettes will fail with a ResolveError for outline_variant).",
                file=sys.stderr,
            )
            return 3
        indent = match.group("indent")
        insertion = f"\n{indent}outline_variant:          colorsObj.surface2,"
        text = text[: match.end()] + insertion + text[match.end():]
        changed.append("toMd3(): added outline_variant role")

    if not changed:
        print(f"Shell already patched: {path}")
        return 0

    backup_once(path)
    write(path, text)
    for item in changed:
        print(f"Patched: {item}")
    print(f"Patched file: {path}")
    return 0


def revert_patch(path):
    backup = path + BACKUP_SUFFIX
    if not os.path.isfile(path):
        print(f"Error: {path} not found.", file=sys.stderr)
        return 2
    if not os.path.isfile(backup):
        print(f"No addon backup for {path}; nothing to restore.")
        return 0

    text = read(path)
    if BASE_DIR_MARKER not in text and OUTLINE_MARKER not in text:
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

    path = os.path.abspath(args[0])
    if not os.path.isfile(path):
        print(f"Error: {path} not found.", file=sys.stderr)
        return 2

    return revert_patch(path) if revert else apply_patch(path)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
