# Chinese Ink Quickshell Topbar

A Chinese ink-inspired Quickshell topbar for Sway. This repository also keeps
the previous Waybar configuration for reference.

## Features

- Persistent Sway workspaces with occupied, focused, empty, and urgent states
- MPRIS media title with a continuous marquee
- PipeWire volume control with click-to-mute and mouse-wheel adjustment
- Wi-Fi, wired network, and Bluetooth status
- Native Wi-Fi, Bluetooth, calendar, power, and system tray menus
- Battery, memory, clock, and system tray indicators
- Cached Chinese poetry with a cinnabar accent
- Multi-monitor support and automatically closing popups

## Requirements

The topbar expects the following components:

- Quickshell 0.3 or newer
- Sway
- PipeWire
- NetworkManager
- BlueZ for Bluetooth support
- UPower for battery information
- A Nerd Font, preferably `JetBrainsMono Nerd Font Propo`
- `LXGW WenKai` for the poetry text

Optional commands used by menu actions are `alacritty`, `btop`, and
`swaylock`.

## Installation

Clone the repository and run:

```sh
./install.sh
```

The script installs the topbar to:

```text
${XDG_CONFIG_HOME:-~/.config}/quickshell/topbar
```

An existing installation is moved to a timestamped backup before the new
configuration is copied.

Install and immediately start the topbar with:

```sh
./install.sh --start
```

## Manual installation

Copy the configuration directory and launch it:

```sh
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
cp -a quickshell/topbar "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/topbar"
qs -c topbar
```

Depending on the package, the executable may be named `quickshell` instead of
`qs`.

## Sway autostart

After confirming the topbar works, add this to the Sway configuration:

```text
exec_always --no-startup-id qs -c topbar --no-duplicate
```

Use `quickshell` in place of `qs` when that is the installed executable. Disable
the old Waybar autostart entry to avoid showing both bars.

## Development

Run directly from the repository:

```sh
qs -p quickshell/topbar
```

Quickshell automatically reloads the configuration after QML files change.
Validate changes with:

```sh
qmllint quickshell/topbar/*.qml
```

The original Waybar theme remains under `waybar/`.
