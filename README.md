# MoonDock

A macOS menu-bar companion for [Moonlight](https://github.com/moonlight-stream/moonlight-qt). MoonDock manages the local Moonlight window and offers manual native-4K/HiDPI display modes. It does not bundle or modify Moonlight or Sunshine.

## Menu

The menu bar uses a compact monochrome rectangle-and-crescent icon, without a monitor stand or a text label. macOS adapts its template tint to light/dark menu bars; the tooltip and accessibility label remain MoonDock.

- **Moonlight öffnen** opens or raises the main window when no stream is active. During a stream the same item reads **Stream anzeigen** and raises that live stream without disconnecting it.
- **Stream beenden** is enabled only while streaming. It disconnects the local stream and opens Moonlight's main window, keeping MoonDock and the selected Mac display mode alive.
- **Mac-Auflösung** lists Standard (2560 × 1440 HiDPI), native 3840 × 2160, and supported HiDPI modes at 120 Hz. The current mode is checked. Standard is the preferred working scale for this setup, not a universal macOS factory default. A mode change closes the local client before reconfiguring the display.
- **MoonDock beenden** is the bottom item and closes Moonlight and MoonDock, restoring a display mode changed in the companion. Closing Moonlight itself, including the window close button or Command-Q, leaves MoonDock in the menu bar so it can reopen Moonlight.

Starting MoonDock does not change the display mode. A manual mode selection ends the local Moonlight process before switching, then opens its main window. If a display mode was changed in MoonDock, explicitly quitting via **MoonDock beenden** restores the mode from startup. Closing Moonlight alone keeps the selected display mode while MoonDock remains running. Without a manual change, display settings are left alone. Temporary changes are also reverted by macOS if MoonDock crashes. Windows applications are not intentionally terminated.

Option–Command–Tab hides Moonlight and returns to the previous Mac app. This requires **System Settings → Privacy & Security → Accessibility → MoonDock**. The legacy bundle identifier is retained for compatibility with previous Moonlight 4K installations. Ad-hoc signed updates may require toggling this permission off and on. No input history is recorded.

MoonDock stays in the menu bar when Moonlight exits or its window is closed. Only the companion's **MoonDock beenden** action ends both apps and restores a manually changed display mode. That explicit stop still reacts directly to process termination without the old extra two-second delay. Intentional stream/main-window and display-mode transitions also keep MoonDock running.

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

## Optional mouse helper

`./scripts/install-mouse-helper.sh` installs a separate per-user helper that pauses Logi Options+ and SaneSideButtons while Moonlight is running and restores the tools it paused afterward. This can free mouse side buttons for streaming, but also pauses other Options+ features and SaneSideButtons navigation gestures for that duration. A manually restarted mouse tool is paused again even if the helper already has a pause marker. Install it only if that behavior is wanted. It does not read input. The existing legacy service name/path is retained to avoid duplicate helpers. The helper does not edit mouse-button mappings or third-party preferences. Other mouse tools are not managed.

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

### Mouse-helper maintenance

Live checked: stopping the helper restores both previously paused mouse tools; starting it during Moonlight pauses both; a deliberately restarted Logitech service is paused again despite an existing marker. The Moonlight stream process stays unchanged throughout. The original input failure was reported while Logitech was already paused and SaneSideButtons was still running; stopping both removes those interception paths, but physical in-game side-button delivery after this repair has not yet been confirmed.

- Pause SaneSideButtons as well as Logi Options+ while Moonlight is running, restoring only tools paused by this helper.
- Recheck actual Logitech service state even when a pause marker exists, so an unexpected restart is caught.
- This helper-only change does not replace the signed MoonDock application.

### 1.14.0

Live checked: showing an active stream preserves the same client process; ending it opens the main window without changing the display or MoonDock process; stopping with no stream is a no-op; reopening an existing main window preserves it; Moonlight close/reopen keeps MoonDock alive; explicit companion exit closes both.

- Separate opening/showing Moonlight from deliberately disconnecting a stream.
- Use the contextual **Stream anzeigen** label during a live stream.
- Enable **Stream beenden** only for active streams; rename the bottom exit action to **MoonDock beenden**.

### 1.13.0

Live checked: closing Moonlight leaves the same MoonDock process and the selected display mode intact; the menu reopens Moonlight; explicitly exiting MoonDock while Moonlight is already closed restores the original display mode and quits the companion.

- Keep MoonDock running after Moonlight closes, including Command-Q and window-close exits.
- Reopen Moonlight from the menu, now labeled **Moonlight öffnen**.
- Restore manual display changes only when explicitly exiting MoonDock; keep the no-delay stop behavior.

### 1.12.1

- Add the matching rectangle-and-crescent application icon for Finder and Dock, without a monitor stand.
- Generate the complete Retina ICNS icon set from vector artwork during the build.

### 1.12.0

- Replace the menu-bar text with the selected rectangle-and-crescent symbol, without a monitor stand.
- Draw it as a resolution-independent template image and retain the MoonDock accessibility label.

### 1.11.0

- Renamed the custom launcher to MoonDock.
- React directly to Moonlight termination and remove the unconditional post-exit delay.
- Preserve intentional main-window and resolution transitions.
- Extract a standalone, reproducible source/build project; no Sunshine settings, pairing data, SSH keys, or diagnostic exports are included.
