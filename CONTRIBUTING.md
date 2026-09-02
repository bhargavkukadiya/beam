# Contributing to Beam

Thank you for your interest in contributing to **Beam**! We welcome bug fixes, documentation improvements, performance optimizations, and architectural enhancements.

---

## Code of Conduct

All contributors and maintainers are expected to adhere to our [Code of Conduct](CODE_OF_CONDUCT.md). Please read it before participating.

---

## Architecture Overview

The codebase is strictly modularized into two isolated Swift targets:

* **`Sources/BeamCore/`** *(SwiftPM Library Target)*:
  * Contains headless domain data structures, LinkParser, URL scheme security rules, and HistoryManager.
  * **Rule**: Must never import or depend on `AppKit`, `SwiftUI`, or `ScreenCaptureKit`.
* **`Sources/BeamApp/`** *(SwiftPM Executable Target)*:
  * Contains AppKit lifecycle, status bar item, ScreenCaptureKit capture pipelines, Carbon global hotkeys, and SwiftUI views.
  * **Rule**: UI coordinators and views must be isolated to `@MainActor`. Data structures crossing concurrency domains must conform to `Sendable`.

---

## How to Contribute

### 1. Reporting Issues
* Search existing [Issues](https://github.com/bhargavkukadiya/beam/issues) first to avoid duplicate reports.
* For bugs, use the [Bug Report](.github/ISSUE_TEMPLATE/bug_report.md) template and include reproduction payloads (without private credentials).
* For feature suggestions, use the [Feature Request](.github/ISSUE_TEMPLATE/feature_request.md) template.
* For security or privacy vulnerabilities, please follow our [Security Policy](SECURITY.md).

### 2. Pull Request Workflow
1. **Fork and Clone**:
   ```bash
   git clone https://github.com/YOUR_USERNAME/beam.git
   cd beam
   ```
2. **Create a Topic Branch**:
   ```bash
   # Branch naming conventions: feature/*, fix/*, docs/*, refactor/*
   git checkout -b fix/issue-description
   ```
3. **Make Your Changes**:
   * Keep the project **zero-dependency**: do not add external Swift packages.
   * Maintain backward compatibility with macOS 13.0+.
   * Preserve universal binary compatibility (`arm64` and `x86_64`).
4. **Commit Guidelines**:
   * Use concise, descriptive commit messages (e.g. `Fix Wi-Fi password escaping in history`, `Add unit test for MECARD parsing`).

---

## Pre-Submission Verification Checklist

Before opening a pull request, run the local verification suite:

```bash
# 1. Run all unit tests
swift test

# 2. Verify strict concurrency (Warnings as Errors)
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

- **Formatting**: 4-space indentation enforced by `.swift-format`. Run `xcrun swift-format format --in-place --recursive Sources Tests Package.swift` to automatically format code.
- **Privacy First**: Never introduce telemetry, user tracking, or background network calls.
- **Strict Concurrency**: All code must compile cleanly under Swift 6 strict concurrency rules with zero warnings.
