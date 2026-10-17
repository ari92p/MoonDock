# MoonDock

A macOS menu-bar companion for [Moonlight](https://github.com/moonlight-stream/moonlight-qt). MoonDock manages the local Moonlight window and offers manual native-4K/HiDPI display modes. It does not bundle or modify Moonlight or Sunshine.

## Menu

- **Hauptfenster öffnen** raises an existing main window, including a hidden window. It only disconnects/reopens the local client when a stream is active. With Accessibility permission, minimized windows are restored as well.
- **Mac-Auflösung** lists Standard (2560 × 1440 HiDPI), native 3840 × 2160, and supported HiDPI modes at 120 Hz. The current mode is checked. Standard is the preferred working scale for this setup, not a universal macOS factory default.
- **Moonlight beenden** closes Moonlight and MoonDock.

Starting MoonDock does not change the display mode. A manual mode selection ends the local Moonlight process before switching, then opens its main window. If a display mode was changed in MoonDock, fully quitting restores the mode from startup. Otherwise quitting leaves the display alone. Temporary changes are also reverted by macOS if MoonDock crashes. Windows applications are not intentionally terminated.

Option–Command–Tab hides Moonlight and returns to the previous Mac app. This requires **System Settings → Privacy & Security → Accessibility → MoonDock**. The legacy bundle identifier is retained for compatibility with previous Moonlight 4K installations. Ad-hoc signed updates may require toggling this permission off and on. No input history is recorded.

MoonDock reacts directly to macOS's Moonlight-process termination event, including normal Quit/Command-Q, without the old extra two-second delay. A polling fallback handles missed events. Intentional stream/main-window and display-mode transitions keep MoonDock running.

## Requirements

- macOS 13 or later; build and live checks currently performed on Apple Silicon/macOS 27.
- Xcode Command Line Tools for building.
- Moonlight installed at `/Applications/Moonlight.app`.
- An external main display offering native 3840 × 2160 at 120 Hz. Only available modes are shown.

## Build and install

```sh
./scripts/build.sh
./scripts/install.sh
open /Applications/MoonDock.app
```

The build creates an ad-hoc signed application in a temporary directory and `build/MoonDock.zip`. Set `CODE_SIGN_IDENTITY` when building with your own signing identity. Build output is not committed. A source archive alone is not an installed app. Quit MoonDock before updating it.

The previous custom launcher was named **Moonlight 4K**. Stop that launcher before opening MoonDock; do not run both together. Both use the same internal bundle identity/notifications for migration compatibility.

An optional direct Desktop connection can be started with:

```sh
/Applications/MoonDock.app/Contents/MacOS/MoonDock --desktop WINDOWS_HOSTNAME
```

The normal launch opens Moonlight's main window; no host names or credentials are embedded in the source.

## Optional Logitech helper

`./scripts/install-mouse-helper.sh` installs a separate per-user helper that pauses Logi Options+ while Moonlight is running and restarts it afterward. This can free mouse side buttons for streaming, but also pauses other Options+ features for that duration. Install it only if that behavior is wanted. It does not read input. The existing legacy service name/path is retained to avoid duplicate helpers. Third-party mouse-gesture tools may also need their own Moonlight exception; MoonDock does not edit their settings.

## Validation and limits

The original custom launcher was tested with existing/hidden main windows, active Desktop streams, native 4K and representative HiDPI modes, and conditional display restoration. Live checks of MoonDock 1.11.0 on 17 October 2026 also confirmed:

- Normal Moonlight Quit (the same application-quit path used by Command-Q) closes MoonDock about 0.01 seconds after the Moonlight process exits, versus 2.95 seconds in the previous launcher.
- With a manually changed display mode, normal Quit restores the original mode and closes MoonDock; the measured additional time including restoration was 0.335 seconds.
- An intentional active-stream → main-window transition keeps the same MoonDock process alive.
- Starting and quitting without a manual mode selection does not change the display.

These are observations on the tested machine, not timing guarantees for every Mac. Games are not automatically launched by these checks.

Streaming is identified from local process transport sockets and Moonlight's process-owned log; this is not a public Moonlight control API. If no active stream is established by that inspection, MoonDock favors raising the existing app. Future Moonlight changes may require adapting detection.

A prior WindowServer hang during display experimentation was not conclusively diagnosed. Display changes therefore take place only after the Moonlight process has exited, with a settling interval. These checks do not establish long-term stability.

## Change history

### 1.11.0

- Renamed the custom launcher to MoonDock.
- React directly to Moonlight termination and remove the unconditional post-exit delay.
- Preserve intentional main-window and resolution transitions.
- Extract a standalone, reproducible source/build project; no Sunshine settings, pairing data, SSH keys, or diagnostic exports are included.
