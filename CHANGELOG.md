# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-09-03

### Fixed
- **AppKit Startup & Main Queue Responsiveness**: Migrated application entry point from `main.swift` to synchronous `@main struct BeamApp` in `BeamApp.swift`, eliminating main-dispatch-queue starvation and unblocking global hotkeys, delayed captures, and async actions.
- **Swift 5.9 Compatibility on macOS 13**: Removed reliance on `MainActor.assumeIsolated` (which the Swift 5.9 toolchain restricted to macOS 14+), ensuring clean builds targeting macOS 13.
- **Contacts App Sandbox Access**: Added `com.apple.security.personal-information.addressbook` entitlement to `Config/Beam.entitlements`, enabling macOS TCC privacy prompts when saving scanned contacts.
- **OTP Secret Redaction Robustness**: Enhanced OTP query parameter decoding to canonicalize multi-pass percent-encoded keys and safely handle multibyte UTF-8 and emoji labels without string index corruption.
- **Compiler Compatibility Guards**: Guarded `nonisolated(unsafe)` properties in `HotKeyManager` with `#if compiler(>=5.10)` to support both Swift 5.9 (Xcode 15.2) and modern Swift 6+.

### Added
- **Dual-Matrix CI**: Added automated matrix testing across Swift 5.9 (Xcode 15.2) and modern Swift environments alongside automated whitespace linting in `.github/workflows/ci.yml`.
- **Open-Source Installation Guidance**: Added Gatekeeper bypass commands and security explanations to README and SECURITY documentation.

---

## [1.0.0] - 2026-09-02

### Added
- Initial open-source release of Beam for macOS.
- Menu bar status item with multi-monitor selection overlay via Apple Vision framework and ScreenCaptureKit.
- Contextual smart actions for Web URLs, Wi-Fi networks, Contacts (vCard/MECARD), Two-Factor Auth (TOTP/HOTP), JSON data, and plain text.
- Opt-in, disabled-by-default history with automatic credential masking (`••••••••`).
- Universal binary (`arm64` + `x86_64`) automated packaging with Hardened Runtime codesigning.
