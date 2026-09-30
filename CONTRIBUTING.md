# Contributing to Keyfinder

Keyfinder targets macOS 26 and later. Start with the [architecture](docs/ARCHITECTURE.md) and [Nix packaging guide](docs/NIX.md). Linux support is a future direction; changes to the shared core should avoid unnecessary AppKit dependencies.

## Development

Use the checked-in flake and lock file for the compiler, SDK, build tools, and checks:

```sh
nix develop
swift build
swift run KeyfinderCoreChecks
nix flake check
nix fmt
```

For changes to windows, preferences, or app lifecycle, run `nix run .#smoke-test` in a graphical macOS session. For packaging changes, build `nix build .#dmg --out-link result-dmg`, mount the disk image, and verify that the copied app launches. See the packaging guide for signature and reproducibility checks.

## Changes and verification

Keep commits focused and describe the user-visible behavior, the reason for the change, and the checks performed. Include screenshots for visible UI changes. Separate simulated behavior from hardware observations in reports; a passing fixture test is not evidence of a successful firmware flash or real USB pairing.

Preserve event-driven operation. Avoid polling, repeating timers, idle network requests, and continuous rendering. If a change may affect idle behavior, measure the packaged app with `nix run .#benchmark -- --seconds 30` and record the conditions alongside the results.

## Fixtures and reports

Use synthetic layouts and identifiers in committed fixtures. The bundled demo exercises typing, symbols, navigation, tap/hold actions, and ambiguous transparent keys without depending on an Oryx account. Live service checks require an explicitly supplied exact-revision URL and are separate from offline checks.

Before attaching a snapshot, screenshot, or diagnostic report to an issue, remove personal layout URLs, account names, device serials, and private macros. Keep local editor settings, cached layouts, and generated artifacts out of commits. A useful bug report includes the macOS version, processor architecture, app revision, steps to reproduce, and expected versus observed behavior.
