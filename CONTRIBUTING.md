# Contributing to Beam

Thank you for your interest in contributing to Beam! We welcome bug fixes, documentation improvements, and architectural enhancements.

---

## Code of Conduct

All contributors are expected to adhere to the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md).

---

## Architecture Overview

The repository is divided into two primary targets:

- **`Sources/BeamCore/`**: Standalone Swift library target containing domain models, parsing logic, URL safety checks, and history sanitization. Must remain free of AppKit, SwiftUI, and ScreenCaptureKit dependencies.
- **`Sources/BeamApp/`**: Standalone executable target containing AppKit lifecycle management, ScreenCaptureKit capture pipelines, Carbon global hotkeys, and SwiftUI views.

---

## How to Contribute

1. **Bug Reports & Feature Requests**:
   - Check existing issues before opening a new one.
   - Use the provided [Bug Report](.github/ISSUE_TEMPLATE/bug_report.md) or [Feature Request](.github/ISSUE_TEMPLATE/feature_request.md) templates.

2. **Code Contributions**:
   - Fork the repository and create a feature branch (`git checkout -b feature/my-feature`).
   - Keep the project **dependency-free**: do not introduce external SPM packages.
   - Maintain compatibility with macOS 13.0+ and universal architectures (`arm64` and `x86_64`).
   - UI coordinators and view models must be isolated to `@MainActor`.
   - Data models passed across concurrency boundaries must conform to `Sendable`.

---

## Pre-Submission Verification Checklist

Before opening a pull request, run the local verification suite:

```bash
# 1. Run all unit tests
swift test

# 2. Verify strict concurrency
swift test -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete

# 3. Check code formatting against .swift-format
xcrun swift-format lint --strict --recursive Sources Tests Package.swift

# 4. Check for trailing whitespace
git diff --check

# 5. Build and validate universal release app bundle
./Scripts/build-app.sh
```

---

## Coding Standards

- Indentation: 4 spaces (configured in `.swift-format`).
- Style: Standard Apple Swift API Design Guidelines.
- Privacy: Never introduce telemetry, tracking, or network calls.
- Security: Sanitize all persisted payloads; isolate untrusted URL schemes.
