# MoonDock

A small macOS menu-bar companion for [Moonlight](https://github.com/moonlight-stream/moonlight-qt). MoonDock opens and raises the Moonlight window, can end a running stream without quitting Moonlight, and offers a menu to switch an external 4K/120-Hz display between native 4K and HiDPI modes.

MoonDock does not bundle, patch, or configure Moonlight or Sunshine. No host names, credentials, or pairing data are stored in the source.

The interface is available in English and German and follows the macOS system language. Other languages fall back to English.

## Features

- **Open Moonlight / Show Stream**. Opens or raises Moonlight's main window. During a stream it raises the stream instead, without disconnecting.
- **End Stream**. Enabled only while a stream is running. It closes the local stream and reopens Moonlight's main window.
- **Mac Resolution**. Lists 120-Hz modes of the main display: 2560 × 1440 HiDPI, native 3840 × 2160, and several 16:9 HiDPI scales. The current mode is checked. Moonlight is closed before the mode changes and reopened afterwards.
- **Quit MoonDock**. Closes Moonlight and MoonDock and restores the display mode that was active when MoonDock started, but only if you changed it from the menu.
- **⌥⌘Tab** hides Moonlight and returns to the previously active Mac app, even while a stream captures the keyboard.

Closing Moonlight itself (window close button or ⌘Q) leaves MoonDock in the menu bar, so you can reopen Moonlight from there. Starting MoonDock never changes the display mode. Display changes are made with `kCGConfigureForAppOnly`, so macOS reverts them if MoonDock crashes.

## Requirements

- macOS 13 or later (developed and tested on Apple Silicon).
- Xcode Command Line Tools (`xcode-select --install`) for building.
- Moonlight installed at `/Applications/Moonlight.app`.
- For the resolution menu: an external main display with 4K modes at 120 Hz. Without one, MoonDock still works, and the menu shows no modes. The built-in MacBook display is never reconfigured.

## Build and install

```sh
./scripts/build.sh
./scripts/install.sh
open /Applications/MoonDock.app
```

`build.sh` compiles the app into a temporary directory, renders the icon, and writes `build/MoonDock.zip`. Quit MoonDock before running `install.sh` again for an update.

### Code signing

macOS ties the Accessibility permission to the app's signature. Without further setup the build is ad-hoc signed, which changes with every build, so ⌥⌘Tab stops working after each update until you re-grant the permission.

To keep the permission across updates, sign with a stable identity from your keychain, for example an Apple Development certificate or a self-signed code-signing certificate:

```sh
security find-identity -v -p codesigning
echo "YOUR_IDENTITY_HASH_OR_NAME" > signing-identity.local
```

`build.sh` reads `signing-identity.local` (ignored by Git), or the `CODE_SIGN_IDENTITY` environment variable, which takes precedence. After the first install with a new identity, grant the permission once more; later updates keep it.

To start a desktop stream directly instead of the main window:

```sh
/Applications/MoonDock.app/Contents/MacOS/MoonDock --desktop YOUR_HOST
```

## Permissions

The ⌥⌘Tab shortcut needs **System Settings → Privacy & Security → Accessibility → MoonDock**. MoonDock uses this permission to watch for the Tab key while Moonlight is in front. Other keys are passed through untouched, and nothing is recorded or logged. With an ad-hoc signed build you need to turn the permission off and on again after each update; see [Code signing](#code-signing).

## Translations

UI strings use their English text as the key, wrapped in `L("…")` in `Sources/MoonDock.swift`. Translations live in `Resources/<language>.lproj/Localizable.strings`. To add a language, copy `Resources/de.lproj`, translate the values, and add the language code to `CFBundleLocalizations` in `Resources/Info.plist`. `build.sh` copies every `.lproj` folder into the app.

## Optional: Logitech Options+ helper

`./scripts/install-mouse-helper.sh` installs a per-user LaunchAgent that pauses Logi Options+ while Moonlight runs and restarts it afterwards. This frees mouse side buttons for the stream, but also pauses all other Options+ features during that time. The helper only checks whether Moonlight is running; it does not read any input. Install it only if you want this behavior.

## How it works and limits

- MoonDock detects an active stream by inspecting Moonlight's UDP sockets and its log file. Moonlight has no public control API, so future Moonlight versions may need adjustments. If the state is unclear, MoonDock raises the existing window rather than closing anything.
- The offered resolutions are tuned for a 4K/120-Hz monitor and are hard-coded in `resolutionChoices(for:)`. Other monitors may show fewer or no modes.
- Display changes happen only after the Moonlight process has exited, with a short settling delay.
- The bundle identifier `de.mlemors.Moonlight4K` comes from the project's earlier name and is kept so existing Accessibility permissions keep working.

## License

[MIT](LICENSE)
