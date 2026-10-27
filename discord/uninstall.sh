#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TARGET_DIR=""
NON_INTERACTIVE=false
SKIP_VENCORD_CONFIG=false

print_usage() {
    cat << 'EOF'
Usage: uninstall.sh [OPTIONS]

Serpantinum Discord Addon Uninstaller.
Cleanly uninstalls Serpantinum Discord theme templates, sync scripts,
Matugen configuration entries, and Vencord theme settings.

Options:
  --target-dir <DIR>      Serpantinum target directory to remove addon files from
  --non-interactive       Run non-interactively without user prompts
  --skip-vencord-config   Skip modifying ~/.config/Vencord settings and themes
  -h, --help              Show this help message and exit
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            print_usage
            exit 0
            ;;
        --target-dir)
            if [[ $# -lt 2 ]]; then
                echo "Error: --target-dir requires a directory argument" >&2
                exit 1
            fi
            TARGET_DIR="$2"
            shift 2
            ;;
        --target-dir=*)
            TARGET_DIR="${1#*=}"
            shift
            ;;
        --non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        --skip-vencord-config)
            SKIP_VENCORD_CONFIG=true
            shift
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            print_usage >&2
            exit 1
            ;;
    esac
done

# Resolve TARGET_DIR if not explicitly provided
if [[ -z "$TARGET_DIR" ]]; then
    if [[ -n "${SERPANTINUM_DIR:-}" ]]; then
        TARGET_DIR="$SERPANTINUM_DIR"
    elif [[ -d "$REPO_ROOT/src/assets/matugen" ]]; then
        TARGET_DIR="$REPO_ROOT"
    elif [[ -d "$HOME/.local/share/serpantinum" ]]; then
        TARGET_DIR="$HOME/.local/share/serpantinum"
    else
        TARGET_DIR="$REPO_ROOT"
    fi
fi
TARGET_DIR="${TARGET_DIR%/src}"
TARGET_DIR="${TARGET_DIR%/}"

prompt_user() {
    local prompt="$1"
    local resp=""
    if [[ -t 0 ]]; then
        read -r -p "$prompt" resp
    elif [[ -r /dev/tty ]]; then
        read -r -p "$prompt" resp < /dev/tty
    else
        resp=""
    fi
    echo "$resp"
}

# Prompt user in interactive mode
if [[ "$NON_INTERACTIVE" != "true" ]]; then
    echo "=== Serpantinum Discord Addon Uninstaller ==="
    echo "Target directory: $TARGET_DIR"
    echo "This will remove Discord templates, sync scripts, and Matugen configurations."
    choice="$(prompt_user "Are you sure you want to uninstall the Discord addon? [y/N]: ")"
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
        echo "Uninstallation cancelled."
        exit 0
    fi
fi

echo "Uninstalling Discord addon from: $TARGET_DIR"

# 1. Remove deployed files from target directory
MATUGEN_TPL="$TARGET_DIR/src/assets/matugen/templates/discord-theme.css.template"
SYNC_SCRIPT="$TARGET_DIR/src/scripts/discord_sync.sh"

if [[ -f "$MATUGEN_TPL" ]]; then
    rm -f "$MATUGEN_TPL"
    echo "Removed template: $MATUGEN_TPL"
fi

if [[ -f "$SYNC_SCRIPT" ]]; then
    rm -f "$SYNC_SCRIPT"
    echo "Removed script: $SYNC_SCRIPT"
fi

# 2. Cleanly remove [templates.discord] from Matugen configs
remove_matugen_config() {
    local toml_path="$1"
    if [[ ! -f "$toml_path" ]]; then
        return 0
    fi

    python3 - "$toml_path" << 'PYEOF'
import sys
import os
import re

toml_path = sys.argv[1]
if not os.path.isfile(toml_path):
    sys.exit(0)

with open(toml_path, "r", encoding="utf-8") as f:
    lines = f.readlines()

new_lines = []
in_discord_section = False
removed = False

for line in lines:
    stripped = line.strip()
    if re.match(r'^\[\s*templates\.discord\s*\](?:\s*#.*)?$', stripped):
        in_discord_section = True
        removed = True
        continue
    elif stripped.startswith("["):
        in_discord_section = False

    if not in_discord_section:
        new_lines.append(line)

if removed:
    content = "".join(new_lines)
    content = re.sub(r'\n{3,}', '\n\n', content)
    if content and not content.endswith('\n'):
        content += '\n'
    with open(toml_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"Removed [templates.discord] from: {toml_path}")
PYEOF
}

remove_matugen_config "$TARGET_DIR/src/assets/matugen/config.toml"
remove_matugen_config "$TARGET_DIR/src/assets/matugen/config-static.toml"

# 3. Clean Vencord configuration if not skipped
if [[ "$SKIP_VENCORD_CONFIG" != "true" ]]; then
    echo "Updating Vencord configuration..."

    vencord_dirs=()
    [[ -d "$HOME/.config/Vencord" ]] && vencord_dirs+=("$HOME/.config/Vencord")
    [[ -d "$HOME/.config/vesktop" ]] && vencord_dirs+=("$HOME/.config/vesktop")
    [[ -d "$HOME/.var/app/dev.vencord.Vesktop/config/vesktop" ]] && vencord_dirs+=("$HOME/.var/app/dev.vencord.Vesktop/config/vesktop")

    for vdir in "${vencord_dirs[@]}"; do
        # Remove theme file
        theme_file="$vdir/themes/serpantinum.theme.css"
        if [[ -f "$theme_file" ]]; then
            rm -f "$theme_file"
            echo "Removed theme file: $theme_file"
        fi

        # Remove serpantinum.theme.css from settings.json
        for sfile in "$vdir/settings/settings.json" "$vdir/settings.json"; do
            if [[ -f "$sfile" ]]; then
                python3 - "$sfile" << 'PYEOF'
import sys
import json

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.exit(0)

themes = data.get("enabledThemes", [])
if isinstance(themes, list) and "serpantinum.theme.css" in themes:
    data["enabledThemes"] = [t for t in themes if t != "serpantinum.theme.css"]
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    print(f"Updated Vencord settings: {path}")
PYEOF
            fi
        done

        # Clean quickCss.css if it contains Serpantinum snippet
        for qfile in "$vdir/settings/quickCss.css" "$vdir/quickCss.css"; do
            if [[ -f "$qfile" ]]; then
                python3 - "$qfile" << 'PYEOF'
import sys, re
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    cleaned = re.sub(r'/\* === SERPANTINUM THEME START === \*/.*?/\* === SERPANTINUM THEME END === \*/\s*', '', content, flags=re.DOTALL)
    if cleaned != content:
        with open(path, "w", encoding="utf-8") as f:
            f.write(cleaned)
        print(f"Cleaned quickCss.css: {path}")
except Exception:
    pass
PYEOF
            fi
        done
    done

    # Remove state directory
    state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/serpantinum/discord"
    if [[ -d "$state_dir" ]]; then
        rm -rf "$state_dir"
        echo "Removed state directory: $state_dir"
    fi
fi

echo "Serpantinum Discord addon uninstallation complete!"
