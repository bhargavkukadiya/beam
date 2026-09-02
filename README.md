# Beam for macOS

[![macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](https://apple.com/macos)
[![Swift 5.9 / 6](https://img.shields.io/badge/Swift-5.9%20%7C%206-orange.svg)](https://swift.org)
[![Zero Dependencies](https://img.shields.io/badge/dependencies-zero-brightgreen.svg)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A lightweight, native, privacy-first screen QR code reader for the macOS menu bar with zero external dependencies.

Built in Swift using SwiftUI, AppKit, ScreenCaptureKit, and Apple's Vision framework.

---

## Features

- ⚡ **Native & Blazing Fast**: Built with pure Swift, AppKit, and SwiftUI without Electron or third-party frameworks.
- 🔒 **100% Offline & Private**: All image processing occurs locally via Apple's Vision framework. Zero telemetry, zero analytics, and zero background network requests.
- 🛡️ **Privacy-First History**: History retention is **opt-in and disabled by default**. Sensitive credentials (Wi-Fi passwords and 2FA OTP seeds) are automatically masked before persistence.
- 🖥️ **Multi-Monitor Ready**: Overlays activate across all connected monitors, allowing selection and capture on any active display.
- 🎯 **Rich Action Handlers**:
  - **URLs**: One-click opening in default browser, with confirmation alerts for untrusted/custom URL schemes.
  - **Wi-Fi**: One-click credential copying and direct shortcut to macOS Wi-Fi Settings.
  - **Contacts (vCard / MECARD)**: Direct integration with macOS Contacts via Apple's native `CNContactVCardSerialization`.
  - **Two-Factor Auth (OTP)**: Parsed account and issuer details with direct links to Authenticator apps.
  - **Formatted JSON**: Automatic indentation, sorted keys, and syntax formatting.
  - **Plain Text**: Quick copy and native macOS share sheet.

---

## Architecture & Modular Design

The project is structured as a modular Swift package separating headless domain logic from macOS UI presentation:

```
Sources/
  BeamCore/                       # SwiftPM Library Target
    Models/                       # Domain data structures (WiFiInfo, ContactInfo, OTPInfo, ScanResult)
    Parsing/                      # URL scheme validation and actionable link extraction
    History/                      # Opt-in persistence, credential sanitization, and migration
  BeamApp/                        # SwiftPM Executable Target
    App/                          # Lifecycle, menu bar status item, and global Carbon hotkey
    Capture/                      # Multi-monitor overlay windows and ScreenCaptureKit pipeline
    Results/                      # Floating result panel controller
    UI/                           # SwiftUI result card, action buttons, and share sheet
Tests/
  BeamCoreTests/                  # Domain tests (Privacy sanitization, payload parsing, URL security)
  BeamAppTests/                   # Presentation tests (Result panel lifecycle and callbacks)
Resources/                        # Packaged multi-resolution AppIcon (.icns) and vector source (.svg)
Config/                           # Info.plist and Hardened Runtime entitlements (Beam.entitlements)
Scripts/                          # Universal packaging (build-app.sh) and Apple notarization (notarize.sh)
```

---

## Requirements

- **Operating System**: macOS 13.0 (Ventura) or later
- **Architecture**: Universal binary supporting both Apple Silicon (`arm64`) and Intel (`x86_64`)
- **Xcode**: Xcode 15+ or Command Line Tools

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| <kbd>⌘</kbd> + <kbd>⇧</kbd> + <kbd>2</kbd> | Trigger screen QR code capture |
| <kbd>Space</kbd> *(while dragging)* | Reposition selection rectangle |
| <kbd>Esc</kbd> | Cancel capture |
| <kbd>⌘</kbd> + <kbd>C</kbd> | Copy scanned payload to clipboard |
| <kbd>⌘</kbd> + <kbd>W</kbd> | Close result window |

---

## Privacy & Security

Beam is built with privacy as a foundational principle:

1. **Opt-In History**: Scanned payloads are **never written to disk** unless you explicitly check **"Save Scan History"** in the menu. Unchecking the option instantly purges stored data.
2. **Credential Redaction**: When history is enabled, Wi-Fi passwords and OTPauth secret seeds are automatically masked with `••••••••` to prevent plaintext retention on disk.
3. **URL Scheme Allowlist**: Safe standard schemes (`http`, `https`, `mailto`, `tel`, `sms`, `maps`, `geo`) open directly. Custom or potentially hazardous application schemes require explicit confirmation before execution.
4. **Hardened Runtime**: Built and signed with Apple's Hardened Runtime enabled (`--options runtime`).

---

## Building from Source

### Prerequisites
- macOS 13.0+ (macOS 14+ recommended for ScreenCaptureKit)
- Xcode 15+ or Command Line Tools installed

### 1. Clone the Repository
```bash
git clone https://github.com/bhargavkukadiya/beam.git
cd beam
```

### 2. Run Automated Tests
```bash
# Standard test run
swift test

# Verify strict concurrency
swift test -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete
```

### 3. Verify Code Formatting
```bash
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
```

### 4. Build Universal Release App Bundle
```bash
./Scripts/build-app.sh
```

The resulting `Beam.app` bundle and `Beam-*.zip` distribution archive will be created in the repository root.

---

## Release Packaging & Apple Notarization

To sign with your Apple Developer ID and submit for Apple Notarization:

```bash
# Option A: Build, sign, and notarize in one step
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAM_ID)" \
NOTARIZE=true \
NOTARY_KEYCHAIN_PROFILE="AC_PASSWORD" \
./Scripts/build-app.sh

# Option B: Notarize an existing release bundle
NOTARY_KEYCHAIN_PROFILE="AC_PASSWORD" ./Scripts/notarize.sh
```

---

## License & Attribution

This project is licensed under the [MIT License](LICENSE).

The application icon is custom-designed for Beam and distributed under the same MIT License. The editable vector source is available in `Resources/AppIcon.svg`; `Resources/AppIcon.icns` contains the packaged macOS icon sizes used by the build.
