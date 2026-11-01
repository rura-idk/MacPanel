# MacPanel

A native macOS menu-bar utility with expandable sections for system monitoring, clipboard history, app shortcuts and shell commands. No standalone main window or Dock icon. The interface is currently Russian.

[Русский](README.md) · [Downloads](https://github.com/rura-idk/MacPanel/releases) · [Installation](docs/INSTALLATION.md) · [Usage](docs/USAGE.md)

## Status and requirements

Version **0.9.3 is a pre-release**, built and tested on an Apple Silicon Mac, with user confirmation of the panel and command launching. The downloadable DMG requires **Apple Silicon and macOS 14+**. It is **ad-hoc signed, without Developer ID signing or Apple notarization**. Other hardware and OS versions have not been comprehensively tested. Gatekeeper may block first launch; consult [Apple's instructions](https://support.apple.com/en-us/102445) if you trust the source. Do not disable system-wide protections.

## Features

- System: CPU, memory/swap, network and disk rates, storage, uptime, thermal state, and available GPU/temperature/fan readings. Sensors are read-only and may be unavailable on some Macs.
- Clipboard: up to 15 recent copy operations, including images and file references, persisted locally. Click an entry to copy it back; pause and clear history in Settings.
- Apps and commands: pinned applications and user-authored shell commands. Commands open in Terminal, allowing interactive tools such as `ollama run gemma4:12b` to accept input. Ollama and models are installed separately.
- Keep Awake: native IOKit assertions inhibit idle sleep while enabled. Closing a MacBook lid can still cause sleep. The feature resets when MacPanel exits.
- Launch at Login: registration is attempted on first launch from Applications; macOS may require approval.

Click the menu-bar icon and a section heading to expand its contents directly beneath that heading. Click again to collapse. Long content scrolls; only one section is expanded at a time.

## Install

Download `MacPanel-v0.9.3-arm64.dmg` from Releases, open it and drag MacPanel into Applications. Open the app once. Quit any previous version before replacing it. No Xcode is needed for the downloaded app. Compare published hashes using `shasum -a 256 -c SHA256SUMS.txt` from the download directory.

## Build

Requires a Mac, macOS 14+, Xcode and Swift 5.9+. There are no external Swift package dependencies.

```bash
git clone https://github.com/rura-idk/MacPanel.git
cd MacPanel
bash build.sh
open dist/MacPanel.app
bash scripts/make-dmg.sh
```

Outputs are `dist/MacPanel.app` and `dist/MacPanel.dmg`. Default signing is ad-hoc; the host architecture is used unless `MACPANEL_ARCH` is set. Intel builds are not included or verified in this release. See [development](docs/DEVELOPMENT.md), [release setup](docs/PUBLISHING.md) and [changelog](CHANGELOG.md).

## Privacy and limitations

Clipboard history is stored under `~/Library/Application Support/MacPanel/Clipboard/`. There is no app-specific encryption, analytics or clipboard upload service. Confidential pasteboard markers are respected where available, but passwords can still enter history. Fast copies may be missed. User commands run with your normal account permissions in Terminal and can perform network or filesystem operations according to their content. Sensor helpers use some undocumented macOS interfaces and availability varies.

See [privacy](PRIVACY.md), [security](SECURITY.md) and [troubleshooting](docs/TROUBLESHOOTING.md). Documentation beyond this README is primarily Russian.

## License

[MIT](LICENSE); preserve bundled [third-party notices](ThirdParty/). Not affiliated with Apple or Ollama. No donation destination is configured.
