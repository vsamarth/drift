> [!WARNING]
> Drift is still rough around the edges. If something breaks, feels confusing, or does not work on your device, please open an issue:
> https://github.com/vsamarth/drift/issues/new

<p align="center">
  <img src="flutter/assets/logo_rounded.png" width="96" alt="Drift Logo">
</p>

<h1 align="center">Drift</h1>

<p align="center">
  <strong>AirDrop-like file sharing for any device, anywhere.</strong>
</p>

<p align="center">
  <img src="flutter/assets/demo.png" width="600" alt="Drift Demo">
</p>

Drift is a free and open-source app for sending files directly between devices.

It is designed to feel as simple as AirDrop, but without being limited to Apple devices or nearby-only transfers. Pick files, connect to another device, and send.

## Features

- **Send files between devices, near or far**  
  Discover nearby devices on your local network, or connect using a 6-character pairing code.

- **Resumable transfers**  
  Connection died mid-transfer? Send the same files again and Drift will resume from where the transfer stopped instead of starting over.

- **Cross-platform**  
  Drift currently provides builds for macOS, Windows, Linux, and Android. iOS support is planned.

- **End-to-end encrypted connections**  
  Files are sent over an end-to-end encrypted peer-to-peer connection. Files are never stored in the cloud, and only the sender and receiver can read them.

- **Free and open source**  
  Drift is MIT-licensed and open to contributions. No ads, accounts, or limits on what you send.

## Installation

| Platform | Download |
| --- | --- |
| macOS | [drift-macos-v0.3.4.dmg](https://github.com/vsamarth/drift/releases/download/v0.3.4/drift-macos-v0.3.4.dmg) |
| Windows | [drift-windows-setup-v0.3.4.exe](https://github.com/vsamarth/drift/releases/download/v0.3.4/drift-windows-setup-v0.3.4.exe) |
| Linux | [drift-linux-v0.3.4.deb](https://github.com/vsamarth/drift/releases/download/v0.3.4/drift-linux-v0.3.4.deb) |
| Android | [drift-android-v0.3.4.apk](https://github.com/vsamarth/drift/releases/download/v0.3.4/drift-android-v0.3.4.apk) |
| iOS | Coming soon |

> [!TIP]
> **macOS:** Drift is currently unsigned. If Gatekeeper blocks the app, you can remove the quarantine flag:
>
> ```sh
> xattr -rd com.apple.quarantine /Applications/Drift.app
> ```

### Build from source

The Flutter app lives in [`flutter/`](flutter/).

See [`flutter/README.md`](flutter/README.md) for build instructions.

## Getting started

1. Choose or drop the files you want to send.
2. Select a nearby device, or connect using the 6-character pairing code shown on the receiving device.
3. The receiver reviews the files and accepts the transfer.
4. Drift sends the files directly to the other device.

## Contributing

Drift is usable, but still early. Contributions, testing, bug reports, and UX feedback are welcome.

Some of the things planned next:

- [x] Resumable transfers for interrupted sessions
- [ ] Remember trusted devices for faster repeat transfers
- [ ] Keep Drift listening in the background
- [ ] Set up app distribution through app stores and package managers
- [ ] Add iOS support

## License

Drift is licensed under the MIT License. See [`LICENSE`](LICENSE).