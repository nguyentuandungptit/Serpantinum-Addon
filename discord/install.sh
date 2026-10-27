#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SOURCE_TEMPLATE="$SCRIPT_DIR/templates/discord-theme.css.template"
SOURCE_SYNC_SCRIPT="$SCRIPT_DIR/scripts/discord_sync.sh"

TARGET_DIR=""
CHECK_DEPS=false
NON_INTERACTIVE=false
SKIP_DEPS=false
SKIP_VENCORD_CONFIG=false
FORCE=false

print_usage() {
    cat << 'EOF'
Usage: install.sh [OPTIONS]

Serpantinum Discord Addon Installer.
Integrates Serpantinum dynamic themes with Discord/Vesktop via Vencord.

Options:
  --check-deps            Only check for dependencies and exit (0 if met, 1 if missing)
  --target-dir <DIR>      Serpantinum target directory to install templates and scripts
  --non-interactive       Run non-interactively without user prompts
  --skip-deps             Skip dependency checks
  --skip-vencord-config   Skip configuring ~/.config/Vencord settings and themes
  --force                 Proceed with installation even if dependencies are missing
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
        --check-deps)
            CHECK_DEPS=true
            shift
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
        --skip-deps)
            SKIP_DEPS=true
            shift
            ;;
        --skip-vencord-config)
            SKIP_VENCORD_CONFIG=true
            shift
            ;;
        --force)
            FORCE=true
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

check_discord() {
    if command -v discord >/dev/null 2>&1 || command -v vesktop >/dev/null 2>&1; then
        return 0
    fi
    if command -v flatpak >/dev/null 2>&1; then
        if flatpak list 2>/dev/null | grep -q 'com.discordapp.Discord'; then
            return 0
        fi
        if flatpak list 2>/dev/null | grep -q 'dev.vencord.Vesktop'; then
            return 0
        fi
        if flatpak info com.discordapp.Discord >/dev/null 2>&1 || flatpak info dev.vencord.Vesktop >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

check_vencord() {
    if [[ -d "$HOME/.config/Vencord" ]] || [[ -d "$HOME/.config/vesktop" ]] || [[ -d "$HOME/.var/app/dev.vencord.Vesktop" ]]; then
        return 0
    fi
    if command -v vencord-installer >/dev/null 2>&1; then
        return 0
    fi
    if command -v flatpak >/dev/null 2>&1; then
        if flatpak list 2>/dev/null | grep -q 'dev.vencord.Vesktop'; then
            return 0
        fi
        if flatpak info dev.vencord.Vesktop >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

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

# Handle --check-deps mode
if [[ "$CHECK_DEPS" == "true" ]]; then
    has_discord=true
    has_vencord=true

    if ! check_discord; then
        has_discord=false
    fi
    if ! check_vencord; then
        has_vencord=false
    fi

    if [[ "$has_discord" == "true" && "$has_vencord" == "true" ]]; then
        echo "All Discord addon dependencies are met."
        exit 0
    else
        echo "Missing dependencies for Discord addon:"
        [[ "$has_discord" == "false" ]] && echo "  - Discord or Vesktop is not installed"
        [[ "$has_vencord" == "false" ]] && echo "  - Vencord is not installed"
        exit 1
    fi
fi

# Dependency verification in install mode
if [[ "$SKIP_DEPS" != "true" ]]; then
    has_discord=true
    has_vencord=true

    if ! check_discord; then
        has_discord=false
    fi
    if ! check_vencord; then
        has_vencord=false
    fi

    if [[ "$has_discord" != "true" || "$has_vencord" != "true" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            echo "Warning: Missing dependencies, but continuing due to --force flag."
        elif [[ "$NON_INTERACTIVE" == "true" ]]; then
            echo "Error: Missing dependencies for Discord addon." >&2
            [[ "$has_discord" == "false" ]] && echo "  - Discord or Vesktop is not installed." >&2
            [[ "$has_vencord" == "false" ]] && echo "  - Vencord is not installed." >&2
            echo "Install the missing dependencies, or run with --force / --skip-deps to continue anyway." >&2
            exit 1
        else
            echo "=== Discord Addon: Missing Dependencies ==="
            [[ "$has_discord" == "false" ]] && echo "- Discord / Vesktop is missing."
            [[ "$has_vencord" == "false" ]] && echo "- Vencord is missing."
            echo ""

            aur_helper="yay"
            if command -v paru >/dev/null 2>&1; then
                aur_helper="paru"
            elif ! command -v yay >/dev/null 2>&1; then
                aur_helper=""
            fi

            if [[ "$has_discord" == "false" && -x "$(command -v pacman 2>/dev/null || true)" ]]; then
                echo "How would you like to install Discord / Vesktop?"
                echo "  1) sudo pacman -S --needed discord"
                if [[ -n "$aur_helper" ]]; then
                    echo "  2) $aur_helper -S vesktop-bin"
                else
                    echo "  2) yay -S vesktop-bin"
                fi
                echo "  3) flatpak install flathub com.discordapp.Discord"
                echo "  4) Skip / Manual"
                choice="$(prompt_user "Select option [1-4]: ")"
                case "$choice" in
                    1) sudo pacman -S --needed discord || true ;;
                    2)
                        if [[ -n "$aur_helper" ]]; then
                            "$aur_helper" -S vesktop-bin || true
                        else
                            echo "Neither yay nor paru found. Please install manually."
                        fi
                        ;;
                    3) flatpak install flathub com.discordapp.Discord || true ;;
                    *) echo "Skipping Discord installation." ;;
                esac
            fi

            if [[ "$has_vencord" == "false" && -x "$(command -v pacman 2>/dev/null || true)" ]]; then
                echo ""
                echo "How would you like to install Vencord?"
                echo "  1) Run official Vencord installer script"
                if [[ -n "$aur_helper" ]]; then
                    echo "  2) $aur_helper -S vencord-installer-bin"
                else
                    echo "  2) yay -S vencord-installer-bin"
                fi
                echo "  3) Skip / Manual"
                choice="$(prompt_user "Select option [1-3]: ")"
                case "$choice" in
                    1) sh -c "$(curl -sS https://raw.githubusercontent.com/Vendicated/VencordInstaller/main/install.sh)" || true ;;
                    2)
                        if [[ -n "$aur_helper" ]]; then
                            "$aur_helper" -S vencord-installer-bin || true
                        else
                            echo "Neither yay nor paru found. Please install manually."
                        fi
                        ;;
                    *) echo "Skipping Vencord installation." ;;
                esac
            fi

            # Re-check
            if ! check_discord || ! check_vencord; then
                echo ""
                echo "Some dependencies are still not detected."
                cont="$(prompt_user "Do you want to proceed with addon installation anyway? [y/N]: ")"
                if [[ "$cont" != "y" && "$cont" != "Y" ]]; then
                    echo "Installation cancelled."
                    exit 1
                fi
            fi
        fi
    fi
fi

# Deploy files to Serpantinum target directory
echo "Deploying Discord addon to: $TARGET_DIR"

MATUGEN_TPL_DIR="$TARGET_DIR/src/assets/matugen/templates"
SCRIPTS_DIR="$TARGET_DIR/src/scripts"

mkdir -p "$MATUGEN_TPL_DIR"
mkdir -p "$SCRIPTS_DIR"

if [[ -f "$SOURCE_TEMPLATE" ]]; then
    cp -f "$SOURCE_TEMPLATE" "$MATUGEN_TPL_DIR/discord-theme.css.template"
    echo "Installed template: $MATUGEN_TPL_DIR/discord-theme.css.template"
else
    echo "Warning: Source template $SOURCE_TEMPLATE not found!" >&2
fi

if [[ -f "$SOURCE_SYNC_SCRIPT" ]]; then
    cp -f "$SOURCE_SYNC_SCRIPT" "$SCRIPTS_DIR/discord_sync.sh"
    chmod +x "$SCRIPTS_DIR/discord_sync.sh"
    echo "Installed script: $SCRIPTS_DIR/discord_sync.sh"
else
    echo "Warning: Source sync script $SOURCE_SYNC_SCRIPT not found!" >&2
fi

# Inject [templates.discord] into Matugen configs
inject_matugen_config() {
    local toml_path="$1"
    if [[ ! -f "$toml_path" ]]; then
        mkdir -p "$(dirname "$toml_path")"
        cat << 'EOF' > "$toml_path"
[config]
reload_apps = false
EOF
    fi

    if ! grep -q '\[templates\.discord\]' "$toml_path"; then
        cat << 'EOF' >> "$toml_path"

[templates.discord]
input_path = "templates/discord-theme.css.template"
output_path = "~/.local/state/serpantinum/discord/serpantinum.theme.css"
EOF
        echo "Injected [templates.discord] into $toml_path"
    else
        echo "Matugen config already has [templates.discord]: $toml_path"
    fi
}

inject_matugen_config "$TARGET_DIR/src/assets/matugen/config.toml"
inject_matugen_config "$TARGET_DIR/src/assets/matugen/config-static.toml"

# Configure Vencord settings and theme if not skipped
if [[ "$SKIP_VENCORD_CONFIG" != "true" ]]; then
    echo "Configuring Vencord theme settings..."

    vencord_dirs=()
    [[ -d "$HOME/.config/Vencord" ]] && vencord_dirs+=("$HOME/.config/Vencord")
    [[ -d "$HOME/.config/vesktop" ]] && vencord_dirs+=("$HOME/.config/vesktop")
    [[ -d "$HOME/.var/app/dev.vencord.Vesktop/config/vesktop" ]] && vencord_dirs+=("$HOME/.var/app/dev.vencord.Vesktop/config/vesktop")

    # If no existing directory was detected, default to standard ~/.config/Vencord
    if [[ ${#vencord_dirs[@]} -eq 0 ]]; then
        vencord_dirs+=("$HOME/.config/Vencord")
    fi

    for vdir in "${vencord_dirs[@]}"; do
        mkdir -p "$vdir/themes"
        mkdir -p "$vdir/settings"

        theme_file="$vdir/themes/serpantinum.theme.css"
        if [[ ! -f "$theme_file" ]]; then
            if [[ -f "$SOURCE_TEMPLATE" ]]; then
                cp -f "$SOURCE_TEMPLATE" "$theme_file"
            else
                touch "$theme_file"
            fi
            echo "Created initial theme at: $theme_file"
        fi

        # Update settings.json to enable theme and transparent flag
        for sfile in "$vdir/settings/settings.json" "$vdir/settings.json"; do
            if [[ -f "$sfile" ]] || [[ "$sfile" == "$vdir/settings/settings.json" ]]; then
                python3 - "$sfile" << 'PYEOF'
import sys
import os
import json

path = sys.argv[1]
data = {}
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        data = {}

data["transparent"] = True
themes = data.get("enabledThemes", [])
if not isinstance(themes, list):
    themes = []
if "serpantinum.theme.css" not in themes:
    themes.append("serpantinum.theme.css")
data["enabledThemes"] = themes

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
PYEOF
                echo "Patched Vencord settings: $sfile"
            fi
        done
    done

    # Run initial sync if discord_sync.sh exists
    if [[ -x "$SCRIPTS_DIR/discord_sync.sh" ]]; then
        echo "Running initial discord_sync.sh..."
        bash "$SCRIPTS_DIR/discord_sync.sh" || true
    elif [[ -x "$SOURCE_SYNC_SCRIPT" ]]; then
        echo "Running initial discord_sync.sh..."
        bash "$SOURCE_SYNC_SCRIPT" || true
    fi
fi

echo "Serpantinum Discord addon installation complete!"
