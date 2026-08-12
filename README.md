# Privacy Pulse

Omarchy Quattro bar widget that shows when something is using your **microphone**, **camera**, or **screen capture** — and which app holds it.

Built for the gap in the [Omarchy plugin marketplace](https://omarchyplugins.com/): lots of remotes, AI meters, and system stats, but no macOS-style privacy indicator for live sensor use on Hyprland.

## Features

- Compact bar badge (shield when clear; mic / camera / screen icons when active, tinted urgent)
- Popup lists each capture with app name, detail, and pid when available
- Local-only: PipeWire `pw-dump` + `/proc` fd inspection of `/dev/video*`
- No accounts, tokens, or network calls
- Polls every ~2.5s (faster while the panel is open)

## Requirements

- [Omarchy Quattro](https://omarchy.org/) shell (`omarchy-shell` / Quickshell)
- `python3`
- `pw-dump` (PipeWire; ships with Omarchy’s default audio stack)

## Install

```bash
omarchy plugin add https://github.com/Esegnorelli/omarchy-privacy-pulse.git --enable
```

Or from a local checkout:

```bash
omarchy plugin validate .
omarchy plugin add "$PWD" --enable
```

Place or move the widget if needed:

```bash
omarchy bar move esegnorelli.privacy-pulse --section right
```

## Usage

- **Left-click** the badge: open / close the detail panel
- **Middle-click** or **right-click**: force a refresh
- Badge stays quiet when nothing is capturing; turns urgent and swaps icons when something is

Summon via shell IPC:

```bash
omarchy-shell shell toggle esegnorelli.privacy-pulse
```

## Remove

```bash
omarchy plugin disable esegnorelli.privacy-pulse
omarchy plugin remove esegnorelli.privacy-pulse --yes
```

## How it works

`privacy_scan.py` prints one JSON object:

| Field | Meaning |
|-------|---------|
| `mic` | PipeWire `Stream/Input/Audio` nodes that are live |
| `camera` | Processes with `/dev/video*` open, plus PipeWire video input streams |
| `screen` | Capture streams that look like screencast / screen share |
| `active` | Any of the above non-empty |

The QML bar widget polls that script and renders the badge + panel. Detection is best-effort: some apps may hold devices in ways PipeWire does not expose, and portal screencasts vary by compositor.

## Manual scanner

```bash
python3 privacy_scan.py | jq .
```

## License

MIT
