# Contributing

Thanks for helping improve RelatoKit.

## Development

```sh
swift build
swift test
swift run relato --help
```

The live CLI help is part of the public contract. If you change commands or flags, update the generated reference:

```sh
make generate-command-docs
make check-command-docs
```

Before opening a pull request:

```sh
make check
```

## Boundaries

RelatoKit automates Feedback Assistant through native Accessibility and an experimental authenticated web workflow. It should not bypass entitlements, forge Apple credentials, patch platform protections, or inject into Apple processes.

Undocumented web submission must require explicit user confirmation and verify the resulting Apple server record.
