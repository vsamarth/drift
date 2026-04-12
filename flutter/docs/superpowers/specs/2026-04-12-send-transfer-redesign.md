# Send Transfer Redesign: The "Handshake" Approach

## Overview
A product-grade redesign of the Send Transfer screen, taking inspiration from native transfer tools like Apple AirDrop and Google Nearby Share. The focus is on the "Handshake"—the connection to the recipient.

## Core Principles
- **Recipient First:** The primary visual anchor is the device/person receiving the files.
- **Native & Familiar:** Clean, system-integrated feel with soft animations and clear hierarchy.
- **Progress Integration:** Transfer status is tied visually to the recipient rather than presented as abstract data blocks.

## Design Details

### 1. The Avatar (Primary Anchor)
- A large, central icon representing the recipient's device type (phone, laptop, etc.).
- Surrounded by a **static soft glow** (persistent cyan halo) during the "waiting on recipient" state to indicate an active connection without distracting motion.
- The recipient's name is displayed prominently directly below the avatar.

### 2. Status & Progress
- **Primary Metric:** Time remaining (e.g., "2 mins left") or a clear status ("Waiting to accept...").
- **Secondary Metric:** A sleek, high-precision progress bar or circular progress indicator wrapped around the avatar.
- Raw byte counts (e.g., "1.2 GB of 5 GB") are de-emphasized but still accessible.

### 3. Content Summary (The "Payload")
- A compact card at the bottom summarizing the payload (e.g., "3 Photos, 1 Video" or just file count and total size).
- The detailed file list is hidden behind an expander or a separate sheet to maintain a clean primary view.

### 4. Actions
- **Done:** Prominent primary button when the transfer completes.
- **Cancel:** A discreet but accessible secondary action (e.g., a text button or an 'X' icon) during the transfer.

## Implementation Steps
1. Replace `SendingConnectionStrip` with the new Avatar-centric design.
2. Update `TransferFlowLayout` to support the new centered hierarchy.
3. Modify `_TransferStateCard` in `send_transfer_route.dart` to use the new layout and components.
4. Integrate the progress bar into the Avatar component.
5. Simplify the `PreviewTable` (manifest) to a compact summary card.