# Solanazation

Solanazation is a mobile 4X strategy prototype built with Godot 4.4.1 and GDScript,
targeting Android/Seeker in portrait orientation.

## Current state

Implemented offline gameplay:

- map exploration with fog-of-war memory;
- city founding and production;
- an educational Solana-themed technology tree;
- multiple AI rivals;
- turn guidance;
- local save/load.

The project currently targets Android arm64 using Godot's GL Compatibility renderer.

City-depth improvements are work in progress and are not yet fully accepted as part
of the stable gameplay baseline.

## Solana integration status

Solana wallet and staking features are not live.

- A Kotlin Mobile Wallet Adapter plugin is pending authoring/integration.
- It has not been applied to the project, compiled, or tested on a device.
- The staking design selects an existing LST plus separate nonredeemable cosmetic
  gameplay credits; see `docs/web3/STAKING-CREDITS.md`.
- There is no staking backend, live credit accrual, custody, or mainnet transaction
  flow in the current prototype.

The existing offline game can therefore be evaluated without a wallet or network.

## Run from source

Requirements:

- Godot 4.4.1;
- repository source checkout.

Import `project.godot` in Godot 4.4.1 and run the project with **F5**.
The main scene is:

```text
scenes/Main.tscn
```

Command-line validation, assuming `godot` is available on `PATH`:

```sh
godot --headless --editor --path . --quit
godot --headless --path . -s res://tests/smoke.gd
```

These commands are provided as project entry points, not as claims about results
from an unpublished current-source build.

## Android build

`scripts/build_android_debug.ps1` is the current local debug-build entry point.
It requires compatible local Android tooling, Godot export templates, and locally
configured tool paths.

There is no turnkey release build yet. A debug APK from an earlier milestone does
not demonstrate that the current repository revision builds successfully.

## Hackathon status

Target repository: `who1900/Solanazation`.

Solana Mobile CLOCK IN runs September 8 through October 8, 2026 and requires a
functional Android APK, GitHub source, demo video, and pitch/presentation.

MONOLITH has already ended. The intended event must therefore be confirmed before
registration or submission. Solanazation is not currently registered or submitted.

Blocking submission items:

- reproducible current-source Android APK;
- current Mobile Wallet Adapter integration and device verification;
- demo video;
- final pitch material.

There is currently no public APK download or demo-video link.
