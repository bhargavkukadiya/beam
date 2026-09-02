## Description
Briefly describe the change, motivation, and context.

## Type of Change
- [ ] Bug fix (non-breaking change fixing an issue)
- [ ] New feature (non-breaking change adding functionality)
- [ ] Security / Privacy enhancement
- [ ] Documentation update
- [ ] Refactoring / Code quality

## Checklist
- [ ] Code builds cleanly via `swift build`.
- [ ] Code compiles under strict concurrency: `swift test -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete`.
- [ ] All unit tests pass: `swift test`.
- [ ] Code formatting passes: `xcrun swift-format lint --strict --recursive Sources Tests Package.swift`.
- [ ] Universal release build passes: `./Scripts/build-app.sh`.
- [ ] No third-party dependencies introduced.
