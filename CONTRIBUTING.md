# Contributing

Thanks for your interest in Sonance. Issues and pull requests are welcome.

## Before you start

For anything substantial — a new feature, a new dependency, or a behavior change — please open an issue first so the approach can be agreed on before you write code. Small fixes (typos, obvious bugs, doc corrections) can go straight to a pull request.

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for the full build commands, the auto-update setup, the manual smoke test, and diagnostics. In short:

```sh
brew install xcodegen
xcodegen generate
./scripts/dev.sh        # build Debug and launch
```

CI builds both the base `Sonance` target and the Sparkle-linked `Sonance-Direct` target and runs the test suite on every pull request, so please make sure the tests pass locally first:

```sh
xcodebuild -project Sonance.xcodeproj -scheme Sonance \
  -destination 'platform=macOS' -derivedDataPath build test
```

## Pull requests

- Keep changes focused; one topic per pull request.
- Match the style of the surrounding code.
- Update the [README](README.md) and [CHANGELOG.md](CHANGELOG.md) when you change user-facing behavior.

## License

By contributing, you agree that your contributions are licensed under the project's [GPL-3.0 license](LICENSE).
