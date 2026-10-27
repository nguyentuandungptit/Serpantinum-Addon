# Serpantinum Modular Addon System

[![Serpantinum](https://img.shields.io/badge/Serpantinum-v2-blue?style=flat-square)](https://github.com/ilyamiro/serpantinum)
[![Addon Architecture](https://img.shields.io/badge/Architecture-Modular-green?style=flat-square)](#️-developer-guide)
[![License](https://img.shields.io/badge/License-GPLv3-orange?style=flat-square)](LICENSE)

*Read this document in [English](README.md) or [Tiếng Việt](README_vi.md).*

---

## Table of Contents

- [🌟 Introduction](#-introduction)
- [🚀 User Guide](#-user-guide)
  - [Interactive Addon Manager](#interactive-addon-manager)
  - [CLI Subcommands](#cli-subcommands)
- [🛠️ Developer Guide](#️-developer-guide)
  - [Directory Layout](#directory-layout)
  - [Manifest Specification (`addon.json`)](#manifest-specification-addonjson)
  - [`install.sh` Contract](#installsh-contract)
  - [`uninstall.sh` Contract](#uninstallsh-contract)
  - [Integrating with Matugen & Theming Pipeline](#integrating-with-matugen--theming-pipeline)
- [🧩 Included Addons](#-included-addons)
  - [Discord Mod (`discord/`)](#discord-mod-discord)

---

## 🌟 Introduction

**Serpantinum** is an ultra-fluid, modern desktop shell for Linux compositors (Hyprland, Niri, Sway, Mango) powered by dynamic **Material You** theming (`matugen`).

The **Modular Addon System** completely decouples third-party application customization (such as Discord via Vencord, Spotify via Spicetify, Steam, Browsers, etc.) from the core dotfiles:
- **Zero Base Bloat:** Out of the box, core Serpantinum template files (`config.toml`, `config-static.toml`) and scripts contain zero external application baggage.
- **Dynamic Auto-Discovery:** Addons reside in their own standalone directories (`<id>/`). The unified manager dynamically detects, inspects, and manages all available modules via standard metadata manifests (`addon.json`).
- **Strict Idempotency & Clean Uninstallation:** Every addon conforms to a standard installer/uninstaller contract, ensuring changes are fully reversible and repeatable without leaving orphaned configuration entries behind.

---

## 🚀 User Guide

### Interactive Addon Manager

To launch the interactive terminal user interface (TUI), simply run:

```bash
./install.sh
```

The interactive menu lets you:
1. View all discovered addons and current status (`[INSTALLED]` vs `[NOT INSTALLED]`).
2. Toggle installation or uninstallation with simple numeric options.
3. Automatically perform dependency preflight checks before running installers.

### CLI Subcommands

For headless automation or scripting, the addon manager provides comprehensive subcommands:

#### 1. List Available Addons
Discover all available addons, versions, descriptions, and current install status:
```bash
./install.sh list
```

#### 2. Check Install Status
Check whether an addon is currently installed. Exits with code `0` if installed, `1` otherwise:
```bash
./install.sh status <addon_id>
# Example:
./install.sh status discord
```

#### 3. View Addon Info
Display detailed manifest metadata including name, author, version, dependencies, homepage, and description:
```bash
./install.sh info <addon_id>
# Example:
./install.sh info discord
```

#### 4. Install an Addon
Install a specific addon. Any extra flags are passed directly to the addon's `install.sh`:
```bash
./install.sh install <addon_id> [OPTIONS...]

# Example:
./install.sh install discord
./install.sh install discord --force --non-interactive
```

#### 5. Uninstall an Addon
Cleanly remove an addon and revert configurations:
```bash
./install.sh uninstall <addon_id> [OPTIONS...]

# Example:
./install.sh uninstall discord
./install.sh uninstall discord --non-interactive
```

#### 6. Check Dependencies
Run dependency preflight validation without installing:
```bash
./install.sh check-deps <addon_id>
# Example:
./install.sh check-deps discord
```

#### Global Flags:
- `--target-dir <DIR>`: Explicitly specify target Serpantinum root directory (defaults to current repository root or `~/.local/share/serpantinum`).

---

## 🛠️ Developer Guide

Creating a new addon is modular and standardized. You can easily add theming for **Spotify** (`spicetify`), **Steam**, **Firefox/Zen Browser**, or any application by following this structure:

### Directory Layout

Create a new directory at `<addon_id>/`:

```
<addon_id>/
├── addon.json                  # Manifest metadata (Required)
├── install.sh                  # Installer script (Required, chmod +x)
├── uninstall.sh                # Uninstaller script (Required, chmod +x)
├── templates/                  # Matugen templates (Optional)
│   └── <addon_id>-theme.css.template
├── scripts/                    # Runtime sync / helper scripts (Optional)
│   └── <addon_id>_sync.sh
└── assets/                     # Extra static assets, icons, patches (Optional)
```

### Manifest Specification (`addon.json`)

The `addon.json` manifest describes the addon metadata to the manager:

```json
{
  "id": "spotify",
  "name": "Spotify Spicetify Mod",
  "version": "1.0.0",
  "description": "Adaptive Material You styling for Spotify using Spicetify-cli.",
  "author": "YourName",
  "dependencies": ["spotify|spotify-launcher", "spicetify"],
  "homepage": "https://spicetify.app",
  "installed_check": "[ -f \"$SERPANTINUM_DIR/src/scripts/spotify_sync.sh\" ]"
}
```

#### Manifest Fields:
| Field | Type | Required | Description |
|---|---|---|---|
| `id` | `string` | **Yes** | Unique identifier matching directory name (`[a-z0-9_-]+`). |
| `name` | `string` | **Yes** | Human-readable name displayed in the TUI/CLI. |
| `version` | `string` | **Yes** | Semantic version string (e.g., `1.0.0`). |
| `description` | `string` | **Yes** | Short summary of what the addon does. |
| `author` | `string` | No | Author or maintainer name. |
| `dependencies` | `array` | No | List of required binaries/packages. Use `|` for alternative dependencies. |
| `homepage` | `string` | No | Project URL or upstream repository. |
| `installed_check` | `string` | No | Bash command evaluating whether addon is installed (exit 0 = installed). |

### `install.sh` Contract

The installer must be executable (`chmod +x install.sh`) and support the following arguments:

| Flag | Purpose |
|---|---|
| `--target-dir <DIR>` | Target Serpantinum base directory. |
| `--non-interactive` | Run without user confirmation prompts. |
| `--check-deps` | Perform only dependency checks (exit 0 if met, 1 if missing). |
| `--force` | Force installation even if dependencies are missing. |
| `--skip-deps` | Skip dependency checks entirely. |
| `-h`, `--help` | Show usage documentation. |

#### Installer Responsibilities:
1. **Preflight Dependency Checks:** Validate required applications.
2. **Deploy Files:** Copy templates to `<TARGET_DIR>/src/assets/matugen/templates/` and runtime scripts to `<TARGET_DIR>/src/scripts/`.
3. **Inject Matugen Config:** Append `[templates.<addon_id>]` into `<TARGET_DIR>/src/assets/matugen/config.toml` and `config-static.toml` idempotently.
4. **Configure Target App:** Point the target app to the generated theme (e.g. `~/.config/Vencord/settings/settings.json`).
5. **Patch The Shell When Required:** If the addon depends on a shell bug being fixed, ship a small anchored patcher, apply it idempotently, keep a `.pre-<addon_id>` backup, and restore it on uninstall.

### `uninstall.sh` Contract

The uninstaller must be executable (`chmod +x uninstall.sh`) and support:

| Flag | Purpose |
|---|---|
| `--target-dir <DIR>` | Target Serpantinum base directory to clean. |
| `--non-interactive` | Run without confirmation prompts. |
| `-h`, `--help` | Show usage documentation. |

#### Uninstaller Responsibilities:
1. **Remove Deployed Files:** Delete installed templates and scripts from `<TARGET_DIR>`.
2. **Revert Matugen Config:** Remove `[templates.<addon_id>]` cleanly from `config.toml` and `config-static.toml` without touching other sections.
3. **Revert Target App:** Disable or reset external app theme configuration.
4. **Restore Patched Shell Files:** Put back any `.pre-<addon_id>` backup the installer created.
5. **Idempotency:** Must exit with code `0` even if files were already removed.

### Integrating with Matugen & Theming Pipeline

When wallpapers or color modes change, Serpantinum triggers `matugen`:

1. **Matugen Template:** Place your template at `<id>/templates/<id>-theme.css.template`. Reference standard Material You tokens:
   ```css
   :root {
     --surface: {{colors.surface.default.hex}};
     --primary: {{colors.primary.default.hex}};
     --on-primary: {{colors.on_primary.default.hex}};
     --outline: {{colors.outline.default.hex}};
   }
   ```
2. **Matugen Entry:**
   ```toml
   [templates.<addon_id>]
   input_path = "templates/<addon_id>-theme.css.template"
   output_path = "~/.config/<app>/themes/serpantinum.theme.css"
   ```
3. **Live Reload Hook:** If the application requires a reload signal when colors change, implement it in `src/scripts/<addon_id>_sync.sh` and dispatch via event pipeline.

---

## 🧩 Included Addons

### Discord Mod (`discord/`)

Integrates real-time dynamic Material You styling with **Discord** and **Vesktop** via **Vencord**.

#### Key Features:
- 🎨 **Adaptive Color Sync:** Generates a custom CSS theme on every wallpaper update using Matugen color tokens.
- 🏝️ **Floating Island & Liquid Glass:** Translucent backdrop blur (`backdrop-filter: blur(16px)`), modern layered surface elevations, and sleek transparency.
- 📐 **Sharp 2px Borders:** Consistent 2px accent outline styling across navigation bars, member lists, and chat panels.
- 👤 **Avatar Padding Fix:** Eliminates misalignment and clipping issues in Discord member lists and status rings.
- ⚡ **Zero Hassle:** Automatically detects native Discord, Vesktop, Flatpak Discord, and standalone Vencord installations.

```bash
# Install Discord Mod
./install.sh install discord

# Uninstall Discord Mod
./install.sh uninstall discord
```

#### Shell Patch (required for colour sync)

Blur and layout are substituted by `scripts/discord_sync.sh`, but colours only
come from the CSS that matugen renders. Two defects in the shell make matugen
fail silently:

- `matugenBaseDir` appends a second `/src` (`SERPANTINUM_DIR` already ends in
  `/src`), so matugen is handed a config path that does not exist and exits
  immediately. The old code discarded stderr, so the failure was invisible.
- `toMd3()` never emits `outline_variant`, so static palettes abort with
  `ResolveError at discord:NN:NN`.

`scripts/patch_matugen.py` fixes both in
`<TARGET_DIR>/src/quickshell/singletons/theme/Matugen.qml`. It anchors on the
upstream source instead of copying the whole file, is safe to run repeatedly,
keeps the original as `Matugen.qml.pre-discord-addon`, and `uninstall.sh`
restores it.

Re-run the installer after every Serpantinum update, because an update replaces
the entire `src/` tree:

```bash
./install.sh install discord
```

Use `--skip-qml-patch` to install the theme without touching the shell (blur
keeps syncing, colours stay stale).
