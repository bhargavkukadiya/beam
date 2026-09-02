# Security Policy

## Reporting Security Issues

We take the security and privacy of Beam seriously. If you discover a vulnerability or security flaw, please report it privately rather than posting a public issue.

To report a vulnerability:
- Please open a private security advisory report via GitHub (`Security > Advisories > Report a vulnerability`).
- Please include:
  - A description of the vulnerability.
  - Steps or a proof-of-concept payload to reproduce the issue.
  - Potential impact and affected versions.

We will acknowledge receipt of your report within 48 hours and work towards resolving it promptly.

## Security Architecture

1. **Zero Network Communication**: Beam contains no networking code, third-party analytics, or telemetry SDKs. The app operates completely offline. No data is transmitted in the background.
2. **Untrusted Payload Isolation**:
   - URL execution is filtered against an allowlist of safe standard schemes (`http`, `https`, `mailto`, `tel`, `sms`, `maps`, `geo`). Custom or local application schemes (such as `terminal://`, `applescript://`, or custom URI handlers) require explicit confirmation dialogs before opening.
   - Contact import utilizes Apple's native Contacts framework (`CNContactVCardSerialization`), avoiding custom deserialization scripts.
3. **Local Data Redaction**:
   - Wi-Fi network passwords (`WIFI:P:...`) and 2FA OTP seeds (`otpauth://...secret=...`) are redacted using escape-aware parsing before persisting to `UserDefaults`.
   - History retention is disabled by default.
4. **Hardened Runtime**: Released binaries are compiled with Apple's Hardened Runtime enabled (`--options runtime`).
