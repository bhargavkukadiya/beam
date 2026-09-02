## Description

Briefly describe the change, motivation, and context.

## Related Issue

Fixes #(issue number)

## Type of Change

- [ ] 🐛 Bug fix (non-breaking change fixing an issue)
- [ ] ✨ New feature (non-breaking change adding functionality)
- [ ] 🛡️ Security / Privacy enhancement
- [ ] 📝 Documentation update
- [ ] ♻️ Refactoring / Code quality improvement

## How Has This Been Tested?

Describe the tests or manual steps taken to verify the changes:

- [ ] Automated unit test added/updated
- [ ] Manually tested screen capture on macOS

## Contributor Checklist

- [ ] Code builds cleanly: `swift build`
- [ ] Concurrency passes: `swift test -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete`
- [ ] All unit tests pass: `swift test`
- [ ] Formatting passes: `xcrun swift-format lint --strict --recursive Sources Tests Package.swift`
- [ ] Zero trailing whitespace: `git diff --check`
- [ ] Universal release build passes: `./Scripts/build-app.sh`
- [ ] Zero external SPM dependencies introduced
