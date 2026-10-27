#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${ADDON_BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color formatting
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_GREEN="\033[1;32m"
    C_YELLOW="\033[1;33m"
    C_CYAN="\033[1;36m"
    C_RED="\033[1;31m"
    C_DIM="\033[2m"
else
    C_RESET=""
    C_BOLD=""
    C_GREEN=""
    C_YELLOW=""
    C_CYAN=""
    C_RED=""
    C_DIM=""
fi

resolve_serpantinum_dir() {
    if [[ -z "${SERPANTINUM_DIR:-}" ]]; then
        if [[ -d "$REPO_ROOT/src/assets/matugen" ]]; then
            SERPANTINUM_DIR="$REPO_ROOT"
        elif [[ -d "$HOME/.local/share/serpantinum" ]]; then
            SERPANTINUM_DIR="$HOME/.local/share/serpantinum"
        else
            SERPANTINUM_DIR="$REPO_ROOT"
        fi
    fi
    SERPANTINUM_DIR="${SERPANTINUM_DIR%/src}"
    SERPANTINUM_DIR="${SERPANTINUM_DIR%/}"
    export SERPANTINUM_DIR
}

discover_addons() {
    ADDON_IDS=()
    for dir in "$SCRIPT_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local json_file="$dir/addon.json"
        if [[ -f "$json_file" ]]; then
            local fallback_id
            fallback_id="$(basename "$dir")"
            local id
            id="$(python3 -c "
import json, sys
f_path, fb_id = sys.argv[1], sys.argv[2]
try:
    with open(f_path, 'r', encoding='utf-8') as f:
        print(json.load(f).get('id', fb_id))
except Exception:
    print(fb_id)
" "$json_file" "$fallback_id" 2>/dev/null || echo "$fallback_id")"
            if [[ -n "$id" ]]; then
                ADDON_IDS+=("$id")
            fi
        fi
    done

    # Sort addon IDs
    if [[ ${#ADDON_IDS[@]} -gt 1 ]]; then
        mapfile -t ADDON_IDS < <(printf '%s\n' "${ADDON_IDS[@]}" | sort)
    fi
}

addon_exists() {
    local addon_id="$1"
    [[ -n "$addon_id" && -f "$SCRIPT_DIR/$addon_id/addon.json" ]]
}

get_addon_field() {
    local addon_id="$1"
    local field="$2"
    local json_file="$SCRIPT_DIR/$addon_id/addon.json"
    if [[ ! -f "$json_file" ]]; then
        return 1
    fi
    python3 -c "
import json, sys
f_path, f_name = sys.argv[1], sys.argv[2]
try:
    with open(f_path, 'r', encoding='utf-8') as f:
        d = json.load(f)
    val = d.get(f_name, '')
    if isinstance(val, list):
        print(', '.join(str(x) for x in val))
    elif isinstance(val, bool):
        print('true' if val else 'false')
    elif val is not None:
        print(val)
except Exception:
    sys.exit(1)
" "$json_file" "$field"
}

is_addon_installed() {
    local addon_id="$1"
    if ! addon_exists "$addon_id"; then
        return 1
    fi
    resolve_serpantinum_dir

    local check_cmd
    check_cmd="$(get_addon_field "$addon_id" "installed_check")"
    if [[ -n "$check_cmd" ]]; then
        bash -c "$check_cmd" >/dev/null 2>&1
        return $?
    fi

    # Fallback heuristic
    if [[ -f "$SERPANTINUM_DIR/src/scripts/${addon_id}_sync.sh" ]] || \
       [[ -f "$SERPANTINUM_DIR/src/assets/matugen/templates/${addon_id}-theme.css.template" ]]; then
        return 0
    fi
    return 1
}

get_addon_status_tag() {
    local addon_id="$1"
    if is_addon_installed "$addon_id"; then
        echo -e "${C_GREEN}[INSTALLED]${C_RESET}"
    else
        echo -e "${C_YELLOW}[NOT INSTALLED]${C_RESET}"
    fi
}

print_banner() {
    echo -e "${C_CYAN}=======================================================${C_RESET}"
    echo -e "${C_BOLD}             SERPANTINUM ADDON MANAGER${C_RESET}"
    echo -e "${C_CYAN}=======================================================${C_RESET}"
}

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [COMMAND] [ARGS...]

Interactive and dynamic Addon Manager for the Serpantinum dotfile suite.

Commands:
  list                     List all discovered addons and their current installation status
  install <id> [opts...]   Install the specified addon (forwards options to addon installer)
  uninstall <id> [opts...] Uninstall the specified addon (forwards options to addon uninstaller)
  status <id>              Check installation status (exits 0 if installed, 1 if not)
  info <id>                Show metadata and detailed configuration for an addon
  check-deps <id>          Verify system dependencies for an addon
  help, -h, --help         Show this help message

Options:
  --target-dir <DIR>       Specify target Serpantinum root directory

Interactive Mode:
  Run without arguments in an interactive terminal to launch the menu interface:
    ./addon/install.sh
EOF
}

cmd_list() {
    resolve_serpantinum_dir
    discover_addons
    if [[ ${#ADDON_IDS[@]} -eq 0 ]]; then
        echo "No addons found in $SCRIPT_DIR"
        return 0
    fi

    echo -e "${C_BOLD}Discovered Addons:${C_RESET}"
    for id in "${ADDON_IDS[@]}"; do
        local name version desc status_tag
        name="$(get_addon_field "$id" "name")"
        version="$(get_addon_field "$id" "version")"
        desc="$(get_addon_field "$id" "description")"
        status_tag="$(get_addon_status_tag "$id")"

        printf "  %-18b %-20s (v%s)\n" "$status_tag" "$id" "$version"
        if [[ -n "$name" && "$name" != "$id" ]]; then
            printf "                     ${C_DIM}%s${C_RESET}\n" "$name"
        fi
        if [[ -n "$desc" ]]; then
            printf "                     ${C_DIM}%s${C_RESET}\n" "$desc"
        fi
    done
}

cmd_info() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo "Error: Missing addon id. Usage: $(basename "$0") info <id>" >&2
        return 1
    fi
    if ! addon_exists "$id"; then
        echo "Error: Unknown addon '$id'" >&2
        return 1
    fi

    local name version author deps desc status_tag home
    name="$(get_addon_field "$id" "name")"
    version="$(get_addon_field "$id" "version")"
    author="$(get_addon_field "$id" "author")"
    deps="$(get_addon_field "$id" "dependencies")"
    desc="$(get_addon_field "$id" "description")"
    home="$(get_addon_field "$id" "homepage")"
    status_tag="$(get_addon_status_tag "$id")"

    echo "-------------------------------------------------------"
    echo -e "${C_BOLD}Addon:${C_RESET}        $name ($id)"
    echo -e "${C_BOLD}Version:${C_RESET}      $version"
    [[ -n "$author" ]] && echo -e "${C_BOLD}Author:${C_RESET}       $author"
    echo -e "${C_BOLD}Status:${C_RESET}       $status_tag"
    [[ -n "$deps" ]] && echo -e "${C_BOLD}Dependencies:${C_RESET} $deps"
    [[ -n "$home" ]] && echo -e "${C_BOLD}Homepage:${C_RESET}     $home"
    echo -e "${C_BOLD}Description:${C_RESET}  $desc"
    echo "-------------------------------------------------------"
}

cmd_status() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo "Error: Missing addon id. Usage: $(basename "$0") status <id>" >&2
        return 1
    fi
    if ! addon_exists "$id"; then
        echo "Error: Unknown addon '$id'" >&2
        return 1
    fi

    if is_addon_installed "$id"; then
        echo -e "Status of $id: ${C_GREEN}[INSTALLED]${C_RESET}"
        return 0
    else
        echo -e "Status of $id: ${C_YELLOW}[NOT INSTALLED]${C_RESET}"
        return 1
    fi
}

cmd_install() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo "Error: Missing addon id. Usage: $(basename "$0") install <id> [options...]" >&2
        return 1
    fi
    if ! addon_exists "$id"; then
        echo "Error: Unknown addon '$id'" >&2
        return 1
    fi
    shift
    local installer="$SCRIPT_DIR/$id/install.sh"
    if [[ ! -f "$installer" ]]; then
        echo "Error: Installer script not found: $installer" >&2
        return 1
    fi
    bash "$installer" "$@"
}

cmd_uninstall() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo "Error: Missing addon id. Usage: $(basename "$0") uninstall <id> [options...]" >&2
        return 1
    fi
    if ! addon_exists "$id"; then
        echo "Error: Unknown addon '$id'" >&2
        return 1
    fi
    shift
    local uninstaller="$SCRIPT_DIR/$id/uninstall.sh"
    if [[ ! -f "$uninstaller" ]]; then
        echo "Error: Uninstaller script not found: $uninstaller" >&2
        return 1
    fi
    bash "$uninstaller" "$@"
}

cmd_check_deps() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo "Error: Missing addon id. Usage: $(basename "$0") check-deps <id>" >&2
        return 1
    fi
    if ! addon_exists "$id"; then
        echo "Error: Unknown addon '$id'" >&2
        return 1
    fi
    local installer="$SCRIPT_DIR/$id/install.sh"
    if [[ -f "$installer" ]] && grep -q -- "--check-deps" "$installer"; then
        bash "$installer" --check-deps
    else
        local deps
        deps="$(get_addon_field "$id" "dependencies")"
        echo "Declared dependencies for $id: ${deps:-none}"
    fi
}

interactive_addon_menu() {
    local id="$1"
    local name
    name="$(get_addon_field "$id" "name")"

    while true; do
        local status_tag
        status_tag="$(get_addon_status_tag "$id")"

        echo ""
        echo "-------------------------------------------------------"
        echo -e "${C_BOLD}Managing Addon:${C_RESET} $name ($id)"
        echo -e "${C_BOLD}Current Status:${C_RESET} $status_tag"
        echo "-------------------------------------------------------"
        echo "  [1] Install / Reinstall"
        echo "  [2] Uninstall"
        echo "  [3] Check Dependencies"
        echo "  [4] View Details"
        echo "  [0] Back to Main Menu"
        echo "-------------------------------------------------------"
        read -r -p "Select action [0-4]: " action_choice || return 0

        case "$action_choice" in
            1)
                echo ""
                echo -e "${C_BOLD}>>> Installing $id...${C_RESET}"
                cmd_install "$id" || true
                read -r -p "Press [Enter] to continue..." _ || true
                ;;
            2)
                echo ""
                echo -e "${C_BOLD}>>> Uninstalling $id...${C_RESET}"
                cmd_uninstall "$id" || true
                read -r -p "Press [Enter] to continue..." _ || true
                ;;
            3)
                echo ""
                echo -e "${C_BOLD}>>> Checking dependencies for $id...${C_RESET}"
                cmd_check_deps "$id" || true
                read -r -p "Press [Enter] to continue..." _ || true
                ;;
            4)
                echo ""
                cmd_info "$id"
                read -r -p "Press [Enter] to continue..." _ || true
                ;;
            0|b|B|back|Back)
                return 0
                ;;
            *)
                echo -e "${C_RED}Invalid choice: $action_choice${C_RESET}"
                sleep 1
                ;;
        esac
    done
}

interactive_main_menu() {
    while true; do
        clear 2>/dev/null || true
        print_banner
        echo ""
        resolve_serpantinum_dir
        discover_addons

        if [[ ${#ADDON_IDS[@]} -eq 0 ]]; then
            echo "No addons found in $SCRIPT_DIR"
            echo ""
            echo "Options:"
            echo "  [Q] Quit"
            echo ""
            read -r -p "Choose an option: " choice || break
            case "$choice" in
                q|Q|exit) break ;;
                *) echo "Invalid option." ;;
            esac
            continue
        fi

        echo -e "${C_BOLD}Available Addons:${C_RESET}"
        local i=1
        for id in "${ADDON_IDS[@]}"; do
            local name version status_tag
            name="$(get_addon_field "$id" "name")"
            version="$(get_addon_field "$id" "version")"
            status_tag="$(get_addon_status_tag "$id")"

            printf "  [%d] %-18b %-15s (v%s)\n" "$i" "$status_tag" "$id" "$version"
            if [[ -n "$name" && "$name" != "$id" ]]; then
                printf "                         ${C_DIM}%s${C_RESET}\n" "$name"
            fi
            ((i++))
        done

        echo ""
        echo "Actions:"
        echo "  [1-${#ADDON_IDS[@]}] Manage addon"
        echo "  [A]   Install All addons"
        echo "  [U]   Uninstall All addons"
        echo "  [Q]   Quit"
        echo ""
        read -r -p "Choose an option: " choice || break

        case "$choice" in
            q|Q|exit)
                echo "Exiting Addon Manager."
                break
                ;;
            a|A)
                echo ""
                echo -e "${C_BOLD}>>> Installing All Addons...${C_RESET}"
                for id in "${ADDON_IDS[@]}"; do
                    echo ""
                    echo -e "${C_CYAN}--- Installing: $id ---${C_RESET}"
                    cmd_install "$id" || true
                done
                echo ""
                read -r -p "All done. Press [Enter] to continue..." _ || true
                ;;
            u|U)
                echo ""
                echo -e "${C_BOLD}>>> Uninstalling All Addons...${C_RESET}"
                for id in "${ADDON_IDS[@]}"; do
                    echo ""
                    echo -e "${C_CYAN}--- Uninstalling: $id ---${C_RESET}"
                    cmd_uninstall "$id" || true
                done
                echo ""
                read -r -p "All done. Press [Enter] to continue..." _ || true
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ADDON_IDS[@]} )); then
                    local selected_id="${ADDON_IDS[$((choice-1))]}"
                    interactive_addon_menu "$selected_id"
                else
                    echo -e "${C_RED}Invalid option: $choice${C_RESET}"
                    sleep 1
                fi
                ;;
        esac
    done
}

# Main entry point
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-dir)
            if [[ $# -lt 2 ]]; then
                echo "Error: --target-dir requires a directory argument" >&2
                exit 1
            fi
            SERPANTINUM_DIR="$2"
            export SERPANTINUM_DIR
            shift 2
            ;;
        --target-dir=*)
            SERPANTINUM_DIR="${1#*=}"
            export SERPANTINUM_DIR
            shift
            ;;
        -h|--help|help)
            print_usage
            exit 0
            ;;
        list)
            shift
            cmd_list "$@"
            exit $?
            ;;
        info)
            shift
            cmd_info "$@"
            exit $?
            ;;
        status)
            shift
            cmd_status "$@"
            exit $?
            ;;
        install)
            shift
            cmd_install "$@"
            exit $?
            ;;
        uninstall)
            shift
            cmd_uninstall "$@"
            exit $?
            ;;
        check-deps)
            shift
            cmd_check_deps "$@"
            exit $?
            ;;
        *)
            echo "Error: Unknown command or option '$1'" >&2
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1
            ;;
    esac
done

# Non-interactive fallback when stdin is not a terminal
if [[ ! -t 0 ]]; then
    print_banner
    echo ""
    cmd_list
    echo ""
    echo "Tip: Run interactively in a terminal to use the interactive menu,"
    echo "     or use CLI commands: install <id>, uninstall <id>, info <id>, status <id>."
    exit 0
fi

# Launch interactive menu
interactive_main_menu
