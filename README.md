# SetTop Remote for macOS

A lightweight, native macOS menu-bar remote for Android TV and Google TV boxes on the same local network. Built with Objective-C++ (C++17 + AppKit). No Electron, JavaScript runtime, or bundled browser.

## Use

1. Install Android Platform Tools (`brew install android-platform-tools`). The app uses your installed `adb` command.
2. Enable **Developer options → Wireless debugging** on the TV, where supported. Approve the computer when prompted. Some older boxes instead need an already enabled ADB TCP endpoint on port 5555.
3. Open `SetTop Remote.app`. The first screen scans the active LAN for ADB port 5555 and listens for TV/ADB Bonjour announcements.
4. Choose **Connect** on a discovered device. When a TV announces an ADB pairing endpoint, choose **Pair** and enter the code displayed on its Wireless debugging screen. You can also enter an IPv4 address, optionally with a port (`192.168.1.100:5555`).
5. After ADB confirms the connection, the remote appears. Use **Trackpad** to swipe between TV items, click to select, or scroll with two fingers. This works with D-pad-only Android TV launchers.
6. Choose **Pointer** for apps that respond to pointer/touch input. Moving the Mac pointer inside the touch area sends mouse movement; click for a TV-screen tap and drag for a touchscreen swipe. The touch area scales to the TV's reported display resolution. Some TV firmwares have no visible pointer or reject touch input; switch back to Trackpad in those apps.
7. Use Back, Home, **Mute**, Menu, volume, playback and power buttons for quick actions. **⌘M** mutes/unmutes the TV. With the remote window focused, physical arrow keys navigate, Return selects, Escape goes back, Delete backspaces, Tab advances focus, and Space plays/pauses.
8. To type on the TV, focus a text field on the TV and type on the laptop with the remote window focused. For longer text, type or paste into the input box and press **Send** (or Return). **⌘⇧V** pastes clipboard text directly to the TV. ADB's built-in keyboard input handles basic ASCII text; use the TV's own keyboard for unsupported languages/symbols.

Closing the window leaves the **TV** menu-bar item running. Click it to reopen the remote. **Devices** returns to discovery. The **Quit** button in the top-right corner of either screen exits the app completely. Remote commands use a reusable ADB shell to reduce command latency, with a standalone ADB fallback if the shell exits.

## Compatibility and privacy

This app supports Android/Google TV boxes that expose a reachable, authorized **ADB over Wi-Fi** endpoint. TV discovery alone does not grant control: many Google Cast devices announce themselves but do not expose ADB. Some manufacturers disable wireless ADB. Pointer/touch simulation and text injection vary by TV firmware. The app does not implement Google's separate TV Remote pairing protocol or vendor-specific remotes.

Local LAN scanning probes only TCP port 5555 across up to 254 addresses on the active IPv4 subnet. Bonjour also discovers ADB Wireless debugging ports, including pairing services. All ADB traffic is direct between the Mac and TV; no cloud service. ADB authorizations and pairing credentials are managed by the installed `adb` tool. Last connected IP/port is stored in macOS user preferences. Do not expose ADB to the public internet.

## Build

Clone this repository and run `zsh build.sh` from its root (requires Apple Command Line Tools and macOS 13 or newer). The ad-hoc signed app is produced at `outputs/SetTop Remote.app`; `adb` must be installed separately.

```sh
git clone https://github.com/ranjan-apu/settop-remote.git
cd settop-remote
brew install android-platform-tools
zsh build.sh
open 'outputs/SetTop Remote.app'
```

The app is built natively for the Mac running the build. The executable is approximately 160 KB. This project is not notarized with an Apple Developer ID.

## Contributing

Issues and pull requests are welcome. Keep the app native and lightweight; test changes against a supported Android/Google TV device when possible. Report the Android version and connection method when filing device-specific issues. Never include ADB keys or private IP addresses in issue attachments.

## License

[MIT](LICENSE).
