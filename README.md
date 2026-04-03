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
| macOS | [Drift-0.1.0.dmg](https://github.com/vsamarth/drift/releases/download/v0.1.0/Drift-0.1.0.dmg) |
| Windows | [Drift-0.1.0.msix](https://github.com/vsamarth/drift/releases/download/v0.1.0/Drift-0.1.0.msix) |
| Linux | *Coming soon* |
| Android | [Drift-0.1.0.apk](https://github.com/vsamarth/drift/releases/download/v0.1.0/Drift-0.1.0.apk) |
| iOS | *Coming soon* |

**From source:** Build the app in [`flutter/`](flutter/); see [`flutter/README.md`](flutter/README.md). A concise guide here is coming soon.

## Getting Started

Drift is simple by design. To get started, follow these quick steps:

1. Choose (or drop) the files you want to send.
2. Select the receiver from nearby devices or use the 6-character pairing code.
3. The receiver reviews and accepts to start the transfer.

## How It Works

- **Discovery:** Devices connect via a **discovery server** or **LAN discovery**. We only exchange the network info needed to find your peer—never your files.
- **Direct P2P:** We establish a direct, **[end-to-end encrypted](https://docs.iroh.computer/deployment/security-privacy)** connection between devices.
- **Explicit Consent:** No data moves until the receiver reviews the file manifest and accepts the transfer.

## Security & Privacy

- Your files belong to you. Drift establishes a direct, **[end-to-end encrypted](https://docs.iroh.computer/deployment/security-privacy)** connection between devices with no servers in between.
- We use a simple discovery server and DNS-SD to help devices find each other by sharing their endpoint address.
- If a direct connection fails, an encrypted relay is used. Relays may see metadata (like IP addresses), but they can never decrypt your files.

## Roadmap

Drift is still in its early stages. We are focused on stability and UX, and we will continue shipping essential features. Feel free to open a discussion with suggestions. Here are some ideas we are working on:

- Remember trusted devices as favorites for faster repeat transfers.
- Add resumable downloads/transfers for interrupted sessions.
- Keep Drift listening in the background so it is always ready to receive files.

## Acknowledgments

Special thanks to [iroh](https://github.com/n0-computer/iroh) for abstracting away the complex networking details that power Drift. We are also grateful to [LocalSend](https://github.com/localsend/localsend) and [croc](https://github.com/schollz/croc) for inspiring our design.

## License

This project is licensed under the MIT License. See [`LICENSE`](LICENSE).
