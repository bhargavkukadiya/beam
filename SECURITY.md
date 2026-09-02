# Security Policy

## Supported Versions

We provide security updates and patches for the following versions of Beam:

| Version | Supported          |
| :--- | :--- |
| **1.0.x** | :white_check_mark: |
| < 1.0 | :x: |

---

## Reporting a Vulnerability

We take the security and privacy of Beam and its users seriously. If you discover a security vulnerability or sensitive privacy flaw, **please report it privately** rather than opening a public issue.

### How to Report Privately
Please submit a vulnerability report through GitHub's Private Vulnerability Reporting:
👉 **[Open a Security Advisory Report](https://github.com/bhargavkukadiya/beam/security/advisories/new)**

Please include the following details in your advisory:
1. **Description**: Clear description of the vulnerability and its potential impact.
2. **Reproduction Steps**: Step-by-step instructions or proof-of-concept payload to reproduce the issue.
3. **Environment**: macOS version and hardware architecture (Apple Silicon / Intel).

### Our Commitment
- We will acknowledge receipt of your vulnerability report within **48 hours**.
- We will provide a timeline for assessing and addressing the issue.
- Once fixed, a security advisory and patched release will be published with credit given to the reporter.

---

## Security & Privacy Architecture

Beam is designed under zero-trust privacy and local execution principles:

1. **Zero Network Communication**: Beam contains no networking code, telemetry collectors, or background web requests. All image processing and barcode recognition occurs locally on your machine.
2. **Untrusted Payload Isolation**:
   - URL opening is strictly validated against an allowlist of standard safe schemes (`http`, `https`, `mailto`, `tel`, `sms`, `maps`, `geo`).
   - Custom, local, or hazardous URI schemes (e.g. `terminal://`, `applescript://`) trigger a mandatory confirmation dialog displaying the full target payload before execution.
   - Contact cards are deserialized through Apple's native `CNContactVCardSerialization` framework without running custom parsing scripts.
3. **Local Credential Redaction**:
   - History retention is **opt-in and disabled by default**.
   - When history is active, Wi-Fi passwords (`WIFI:P:...`) and 2FA OTP secret seeds (`otpauth://...secret=...`) are masked with `••••••••` before persisting to `UserDefaults`.
4. **Hardened Runtime**: Released binaries are compiled with Apple's Hardened Runtime enabled (`--options runtime`).
