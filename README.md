# drift

`drift` is a lightweight file transfer tool built on `iroh`, with a Flutter app UI and Rust CLI/server binaries.

## Features

- **Send files to anyone, anywhere in the world.** Just like AirDrop, but even more magical.
- Use **Drift** across **macOS, Linux, Windows, Android, and iOS**.
- **Simple and fast:** pick your files, connect, and send directly to the other device, with no uploads and no extra steps.
- **End-to-end encrypted:** only you and the recipient can read your files; no one else can.
- **Free & open source:** **no ads**, **no limits** on what you send, and **no account** required.

## Installation

| Platform | Download |
| --- | --- |
| macOS | [drift-macos.dmg](https://github.com/vsamarth/drift/releases/latest/download/drift-macos.dmg) |
| Windows | [drift-windows.zip](https://github.com/vsamarth/drift/releases/latest/download/drift-windows.zip) |
| Linux | *Coming soon* |
| Android | [drift-android.apk](https://github.com/vsamarth/drift/releases/latest/download/drift-android.apk) |
| iOS | [drift-ios.ipa](https://github.com/vsamarth/drift/releases/latest/download/drift-ios.ipa) |

**From source:** Build the app in [`flutter/`](flutter/); see [`flutter/README.md`](flutter/README.md). A concise guide here is coming soon.

## Getting Started

1. Install Drift on both devices (see [Installation](#installation) above).
2. On the device that will receive files, open Drift and start receiving. You’ll get a pairing code, or you can use nearby discovery on the same network.
3. On the device that will send, open Drift, connect using that code or pick a nearby receiver, choose your files, and send.
4. On the receiver, review what’s incoming and accept to save the files.

## How It Works

1. The receiving device registers for pairing through a **discovery server** (short code) and may use **LAN discovery** on the same network.
2. The sending device looks up the receiver; we open a direct peer-to-peer session between them.
3. The sending device shares a file manifest; the receiving device explicitly accepts or declines.
4. After acceptance, we send file data over that end-to-end encrypted channel.

## Security & Privacy

- We use a **discovery server** so two devices can connect from anywhere in the world. The server only receives your `Endpoint` address (what we need to reach the other peer), not your files.
- After discovery, we open an **[end-to-end encrypted](https://docs.iroh.computer/deployment/security-privacy)** connection between the two devices. Your files are sent only over that link, after the receiver accepts the transfer.
- If a **direct connection** is not possible, we may route traffic through a **relay**. The relay may see **metadata** (for example IP addresses, timing, file count, or total size), but **not** the contents of your files. Payloads stay end-to-end encrypted and readable only on the sender and receiver.

## Roadmap

Drift is still in its early stages. We are focused on stability and UX, and we will continue shipping essential features. Feel free to open a discussion with suggestions. Here are some ideas we are working on:

- Remember trusted devices as favorites for faster repeat transfers.
- Add resumable downloads/transfers for interrupted sessions.
- Keep Drift listening in the background so it is always ready to receive files.

## Acknowledgments

Special thanks to [iroh](https://github.com/n0-computer/iroh) for abstracting away the complex networking details that power Drift. We are also grateful to [LocalSend](https://github.com/localsend/localsend) and [croc](https://github.com/schollz/croc) for inspiring our design.

## License

This project is licensed under the MIT License. See [`LICENSE`](LICENSE).
