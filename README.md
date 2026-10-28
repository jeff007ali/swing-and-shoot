# Swing and Shoot

Zero-g grapple brawler for phones, made with Godot 4.7. Tap to fire your rope, swing and slingshot
around the arena, hook enemies and punch them as they fly past. Offline bots, LAN party play for up
to 4 phones, 7 arenas, 8 modes, 19 weapons and 4 pickups.

## Download (Android)

**[Download the latest APK](https://github.com/<owner>/<repo>/releases/latest/download/swing-and-shoot.apk)**
· [all releases](https://github.com/<owner>/<repo>/releases)

Open the link on your Android phone and allow *Install unknown apps* for your browser when asked.

## Build and test

- Open the folder in Godot 4.7.2, or run it: `godot --path .`
- Tests: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
- Debug APK: `godot --headless --path . --export-debug "Android" export/android/swing-and-shoot.apk`
- Releases: push a `v*` tag; see [docs/release.md](docs/release.md)

Design and decisions: [docs/implementation.md](docs/implementation.md). Requirements:
[docs/requirements.md](docs/requirements.md). Asset credits: [assets/CREDITS.md](assets/CREDITS.md).
