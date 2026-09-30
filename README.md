<div align="center">

<img src="docs/assets/icon.png" width="96" height="96" alt="Keyfinder icon">

# Keyfinder

</div>

> [!WARNING]
> This project is AI-generated.

<div align="center">

A macOS app that shows your Moonlander’s active layer and the action assigned to each key.

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-003049?style=flat-square&labelColor=003049&logo=apple&logoColor=f4f3ee)
![ZSA Moonlander](https://img.shields.io/badge/ZSA-Moonlander-d62828?style=flat-square&labelColor=003049)
![Built with Swift](https://img.shields.io/badge/Swift-native-003049?style=flat-square&labelColor=003049&logo=swift&logoColor=f77f00)
![Packaged with Nix](https://img.shields.io/badge/Nix-flake%20%2B%20nix--darwin-003049?style=flat-square&labelColor=003049&logo=nixos&logoColor=f4f3ee)

[Download](../../releases/latest) · [Installation](#installation) · [Performance](#performance) · [nix-darwin](#nix-darwin) · [User guide](docs/USAGE.md)

<img src="docs/assets/demo.gif" width="1100" alt="Animated Keyfinder demo: the Symbols and Navigation layers show their key legends, then the overlay hides on typing layer 0">

*Simulated layer changes: Symbols → Navigation → Typing (overlay hidden). [Static preview](docs/assets/keyboard.png).*

</div>

## Features

The overlay appears on layers 1 and above and hides on layer 0. It updates as you switch layers, passes clicks through, and leaves keyboard focus in your current app.

| Feature | Behavior |
| :--- | :--- |
| Oryx synchronization | Loads the installed revision when the keyboard connects. Updates after flashing and reconnecting. |
| Keyboard layout | All 72 keys, angled thumb clusters, tap/hold actions, and Oryx key colors. |
| Appearance | Adjustable size, opacity, display, position, and appearance delay. Optional menu bar icon. |
| Offline use | Cached layouts and a bundled three-layer demo. Layer previews in Settings. |
| Privacy | Physical keypress reports are discarded. No typing history is recorded. |

Oryx edits reach the live overlay after you flash them. Unflashed revisions can be previewed separately in Settings.

## Performance

Keyfinder waits for USB and system events, with no polling, repeating timers, or continuous rendering. Hidden overlays do no drawing, duplicate layer reports do no UI work, and Pause stops USB monitoring.

| Measured idle CPU | Resident memory | App bundle |
| :---: | :---: | :---: |
| **~0.0002%** of one core | **~47 MiB** | **1.9 MiB** |

Measured over 30 seconds on Apple Silicon running macOS 26.6.2, using the Nix release build with Settings closed and no keyboard connected. The measurements exclude startup and do not cover a connected keyboard or visible overlay. The app size excludes build tools. [Verification details](docs/VERIFICATION.md).

Oryx is contacted only to fetch an uncached installed revision or refresh a preview. Starting without a keyboard makes no Oryx request.

## Installation

Requires **macOS 26 or later**. [Download the latest release](../../releases/latest).

Use `Keyfinder-macOS-arm64.dmg` for Apple Silicon or `Keyfinder-macOS-x86_64.dmg` for Intel. Open the disk image, drag **Keyfinder.app** to Applications, and open it. The downloaded app does not require Nix.

On first launch, Settings shows the bundled demo. Connect your Moonlander to load its installed layout, or paste an Oryx URL in **Layout & connection**.

The downloads are signed ad hoc and are not notarized. If macOS blocks opening the app, use **System Settings → Privacy & Security → Open Anyway** after attempting to open it. If macOS requests Input Monitoring access, grant it to Keyfinder and retry the connection from Settings.

### Build with Nix

From a checkout with [Nix flakes enabled](https://nix.dev/concepts/flakes):

```sh
nix build
open result/Applications/Keyfinder.app
```

Use `nix run` to build and launch directly.

The flake pins Nixpkgs, Swift, and the macOS SDK for Apple Silicon and Intel. Nix downloads the toolchain, so you do not need a separate Xcode or Command Line Tools installation. [Packaging and reproducibility](docs/NIX.md#reproducibility).

```sh
nix build .#dmg --out-link result-dmg # A disk image containing the standalone .app
nix run . -- --diagnostics          # Check the packaged app and bundled layout
nix run . -- --background           # Start without opening Settings
```

Pushing a Git tag builds and checks both architectures, then uploads their disk images to GitHub Releases. [Release workflow](docs/NIX.md#tag-releases).

## nix-darwin

Add Keyfinder to an existing nix-darwin configuration, replacing `/absolute/path/to/keyfinder` with your checkout path:

```nix
{
  inputs.keyfinder.url = "path:/absolute/path/to/keyfinder";

  outputs = { nix-darwin, keyfinder, ... }: {
    darwinConfigurations.your-mac = nix-darwin.lib.darwinSystem {
      modules = [
        keyfinder.darwinModules.default
        {
          system.primaryUser = "your-username";
          services.keyfinder.enable = true;
        }
      ];
    };
  };
}
```

Keep your existing inputs and modules, then rebuild nix-darwin. Keyfinder is installed in **Applications → Nix Apps** and starts at login for the primary user. Quitting stops it until the next login or service reload.

| Option | Default | Purpose |
| :--- | :--- | :--- |
| `services.keyfinder.enable` | `false` | Install Keyfinder. |
| `services.keyfinder.startAtLogin` | `true` | Create a user LaunchAgent. Set `false` to launch manually. |
| `services.keyfinder.package` | The flake’s package | Select another compatible Keyfinder build. |

When the module handles startup, leave the app’s “Launch Keyfinder at login” toggle off. [Module details](docs/NIX.md#nix-darwin-module).

## Settings

<img src="docs/assets/appearance.png" width="800" alt="Keyfinder’s Appearance settings with controls for width, opacity, delay, screen placement, key colors, and launch at login">

Settings lets you preview layers, inspect key actions, and drag the overlay into position. The overlay accepts clicks while arranging; it passes them through when you finish.

To hide the menu bar icon, turn off **Appearance → Show menu bar icon**. Open Keyfinder from Applications or Spotlight to show Settings again. Hiding the icon leaves the overlay running. Login and background launches leave Settings closed.

Transparent keys can inherit different actions from stacked layers. Stock Oryx reports only the highest active layer, so Keyfinder shows alternatives such as `1 / F1` when the exact action is ambiguous. [User guide and troubleshooting](docs/USAGE.md).

## Development

```sh
nix flake check                    # Build + offline core checks + module checks
nix run .#smoke-test               # AppKit integration checks; opens temporary windows
nix run .#previews                 # Render all bundled layers into artifacts/previews
nix run .#demo                     # Generate the animated demo in artifacts/demo.gif
nix run .#benchmark -- --seconds 30 # Measure the packaged app from a separate process
nix develop                       # Pinned compiler, SDK, Python, and Nix formatter
nix fmt
```

The Swift core handles layouts, labels, USB packet decoding, and caching. AppKit, SwiftUI, and IOKit provide macOS integration. There are no third-party Swift package dependencies. The core is separate from the macOS adapter for a possible Linux port.

USB pairing, physical layer changes, and flash/reconnect behavior have not yet been tested with a connected Moonlander. Current checks use protocol fixtures, simulated USB events, and a live Oryx fetch. [Verification record](docs/VERIFICATION.md).

[Architecture](docs/ARCHITECTURE.md) · [Contributing](CONTRIBUTING.md) · [User guide](docs/USAGE.md) · [Nix packaging](docs/NIX.md)

Built for [ZSA’s Moonlander](https://www.zsa.io/moonlander), using its [Oryx protocol](https://github.com/zsa/qmk_modules/tree/main/oryx). Keyfinder is an independent project.
