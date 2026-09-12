# Solanazation Art Pipeline

## Purpose

This document defines the production pipeline for a coherent, legally reviewable art set for Solanazation. It is the source of truth for visual direction, asset naming, generation, processing, validation, and Godot import.

`docs/ART-PROMPTS.md` remains an asset-brief catalog. It must be revised later to conform to this pipeline, but it is intentionally not changed as part of this document.

## Current Runtime Constraints

The current game uses a square orthogonal map with a logical tile size of `16x16` pixels.

- `MapView` loads terrain only from `res://assets/terrain/tile_<terrain_id>.png` and draws it into a `16x16` rectangle.
- `UnitsView` loads units only from `res://assets/icons/units/unit_<unit_id>.png` and does not scale the resulting `Sprite2D`. A unit export larger than `16x16` will therefore render at the wrong size.
- Existing `128x128` SVG files are placeholders. Their filenames do not use the required `tile_` and `unit_` prefixes, so they are not the PNG assets requested by the runtime loaders.
- Building icons are not currently displayed by the game.
- UI resource icons are not currently loaded by `GameUI`; the UI uses text and emoji.

These constraints make native-size readability more important than master-image detail. The production pipeline keeps high-resolution masters, but the currently visible gameplay exports must be authored and reviewed at `16x16`.

## Style Bible: Salvaged Validator Frontier

The visual identity is **salvaged validator frontier**: a post-apocalyptic dieselpunk civilization that physically grafts distributed-network hardware onto repaired industrial machinery.

### Visual Language

- Heavy, readable silhouettes built from patched steel, dark copper, brass, cables, server cages, heat shields, and scavenged mechanical parts.
- Network technology appears as restrained cyan light, data conduits, validator cores, antenna geometry, and modular circuitry.
- Surfaces are worn and repaired rather than uniformly dirty: chipped paint, oxidized seams, soot near exhausts, and localized weld marks.
- Every asset has one dominant shape and one clear gameplay idea.
- Avoid photorealism, glossy generic cyberpunk, clean science-fiction plastics, fantasy ornament, text, micro-lettering, decorative frames, and recognizable third-party designs.
- Technological glow is an accent, not a substitute for silhouette. Emissive color should normally occupy no more than 10-15% of an asset.

### Palette

| Role | Color | Hex |
|---|---|---|
| Deep background | Graphite | `#0B1117` |
| Secondary dark | Soot | `#161C22` |
| Primary corrosion | Rust | `#8F4E2B` |
| Warm metal | Copper | `#B86F3D` |
| High-value metal | Brass | `#C7A454` |
| Light neutral | Weathered bone | `#D8CCAC` |
| Primary network accent | Cyan | `#22D3EE` |
| Secondary network accent | Violet | `#9945FF` |
| Rare network accent | Mint | `#14F195` |
| Hostile/hazard accent | Warning red | `#D1493F` |
| Biomass/toxic accent | Muted toxic green | `#7EA33C` |

The cyan accent matches the visual language already present in the placeholder assets. Violet and mint may evoke the broader Solana ecosystem palette, but they must not turn every object into a brand mark.

### Camera, Lighting, and Scale

- **Terrain camera: top-down orthographic, square tile, no isometric perspective.** This explicitly supersedes the isometric wording in `ART-PROMPTS.md`, which conflicts with the actual renderer.
- Terrain must tile seamlessly on all four edges. Special terrain may have a central landmark, but ordinary terrain should distribute visual mass across the tile.
- Unit camera: top-down or a very shallow three-quarter view that remains compatible with an orthogonal map. All units face down-right unless a later animation specification says otherwise.
- Light direction is always 45 degrees from the top-left; shadows fall down-right.
- A unit should occupy roughly 70-80% of its canvas while retaining at least one transparent pixel of safe padding at the gameplay export size.
- No essential feature may depend on a line thinner than one final pixel.

## Asset Scope and Manifest

The manifest is driven by the IDs in `scripts/core/Data.gd`, not by manually maintained prompt lists.

### Currently Visible Terrain

All terrain exports are opaque PNG files in `res://assets/terrain/`.

| Data ID | Runtime filename |
|---|---|
| `ocean` | `tile_ocean.png` |
| `wasteland` | `tile_wasteland.png` |
| `ruins` | `tile_ruins.png` |
| `swamp` | `tile_swamp.png` |
| `node_zone` | `tile_node_zone.png` |
| `mountains` | `tile_mountains.png` |
| `crater` | `tile_crater.png` |
| `dump` | `tile_dump.png` |
| `rift` | `tile_rift.png` |

### Currently Visible Units

All unit exports are transparent PNG files in `res://assets/icons/units/`.

| Data ID | Runtime filename |
|---|---|
| `founder` | `unit_founder.png` |
| `rust_guard` | `unit_rust_guard.png` |
| `miner_quad` | `unit_miner_quad.png` |
| `raider_walker` | `unit_raider_walker.png` |
| `heavy_mech` | `unit_heavy_mech.png` |
| `net_broker` | `unit_net_broker.png` |
| `virus_pickup` | `unit_virus_pickup.png` |
| `auto_mech` | `unit_auto_mech.png` |

### Future Assets: Not Yet Connected

Building icons under `assets/icons/blds/` are future UI assets. The current game does not render them. UI resource icons described in `ART-PROMPTS.md` are also future assets because `GameUI` currently uses text and emoji rather than textures.

Do not produce the complete building or UI icon set before its display sizes, paths, and integration contract are implemented. A small representative building and UI icon may be created as part of the golden set to establish the future visual language, but it is not a current runtime deliverable.

## Source and Export Specifications

| Asset class | Production master | Current runtime export | Color/alpha |
|---|---:|---:|---|
| Terrain | `1024x1024` | `16x16` | sRGB, opaque PNG |
| Units | `1024x1024` | exactly `16x16` | sRGB, RGBA PNG |
| Future buildings | `1024x1024` | TBD; provisional `32x32` or `64x64` | sRGB, RGBA PNG |
| Future UI icons | `512x512` | TBD; provisional `24x24` and `32x32` | sRGB, RGBA PNG |

Keep editable masters and working files separate from runtime assets. A future repository change may add an `art/source/` directory with a `.gdignore`; until that structure is approved, do not place `.kra`, generation intermediates, contact sheets, or prompt metadata inside runtime `assets/` folders.

The `16x16` export is a current runtime limitation, not the desired permanent source resolution. If the renderer later normalizes texture size or increases logical tile size, regenerate exports from the preserved masters rather than upscaling gameplay files.

## Golden Set

No batch production begins until the following representative set is approved together:

1. `tile_wasteland.png` — ordinary seamless terrain.
2. `tile_node_zone.png` — special terrain with a restrained network landmark.
3. `unit_founder.png` — human-scale support silhouette.
4. `unit_rust_guard.png` — human-scale combat silhouette.
5. One future building concept — material and architectural reference only.
6. One sheet containing the five future resource-icon concepts — UI language reference only.

The golden set establishes palette ratios, camera, outline weight, glow strength, texture density, light direction, shadow softness, and final-pixel cleanup. Approved golden masters become visual references for later image-edit requests.

## Deterministic Generation and Editing Pipeline

1. **Freeze the brief.** Assign the exact Data ID, runtime filename, gameplay role, dominant silhouette, material hierarchy, accent color, and required negative constraints.
2. **Generate the master.** Generate one asset per request at `1024x1024`. Use a transparent PNG background for units and future icons; use an opaque square for terrain.
3. **Use approved references.** After the golden set is accepted, provide the relevant golden master through image editing/reference input for every subsequent asset. Do not rely on prose alone for batch consistency.
4. **Record provenance.** Save the model name, date, full prompt, prompt-template version, reference asset IDs and checksums, generation request settings, output checksum, and reviewer.
5. **Human cleanup in Krita.** Remove invented lettering and logos, repair anatomy and machinery, normalize the outline, enforce lighting, clean alpha edges, and reduce uncontrolled glow.
6. **Create a `64x64` intermediate.** Downsample from the master with a fixed high-quality filter. Use the same resize and color-management settings for every asset.
7. **Pixel-author the `16x16` export.** Manually repair the silhouette, clusters, contrast, transparent padding, and focal accent. A fully automatic reduction of a highly detailed image is not an acceptable final asset.
8. **Run automated validation.** Check filename, dimensions, PNG format, color mode, alpha expectations, edge occupancy, and manifest coverage.
9. **Run visual QA.** Evaluate contact sheets and in-game captures at native size before approval.
10. **Import and verify in Godot.** Approve only after the asset is visible in its actual map/UI context.

Model outputs are probabilistic, so determinism here means frozen inputs, recorded provenance, fixed post-processing, explicit approval gates, and reproducible exports—not an assumption that identical prompts always produce identical pixels.

## Prompt Template

Use the same ordered template for every generation request:

```text
SOLANAZATION ASSET MASTER

Asset ID: {data_id}
Asset class: {terrain | unit | future_building | future_ui}
Gameplay function: {one sentence}

Visual style: salvaged validator frontier; stylized post-apocalyptic dieselpunk game art;
patched industrial machinery fused with distributed-network hardware; strong readable silhouette;
dark graphite, rust, copper and brass materials; restrained cyan network glow;
violet or mint only when specified.

Camera: {top-down orthographic seamless square terrain | shallow top-down three-quarter unit facing down-right}
Lighting: fixed soft key light from top-left at 45 degrees, shadow down-right.
Composition: {asset-specific dominant shape and occupancy}.
Distinctive feature: {one gameplay-readable feature}.
Background: {opaque seamless terrain | transparent}.

Consistency references: {approved golden asset IDs}.

Exclude: isometric terrain, side view, photorealism, glossy generic cyberpunk, clean sci-fi plastic,
fantasy ornament, text, letters, numbers, signatures, watermarks, borders, UI frames,
recognizable trademarks, franchise designs, named characters, excessive glow, tiny disconnected details.

Output: one centered production master, 1024x1024 PNG, no mockup, no caption, no sprite sheet.
```

Add asset-specific facts after the shared template. Do not silently change camera, palette, light direction, exclusion list, or output contract between assets.

## QA and Approval Gates

### Automated Gate

- The filename exactly matches the manifest.
- The export is a PNG at the required dimensions.
- Terrain is opaque; units have an alpha channel and transparent padding.
- No opaque pixel touches a unit canvas edge unless explicitly approved.
- Every current Data ID has exactly one export and there are no undocumented runtime files.

### Contact-Sheet Gate

Review every batch in a single contact sheet:

- at native `16x16` size;
- enlarged with nearest-neighbor preview for pixel inspection;
- on graphite, mid-gray, and terrain backgrounds;
- in grayscale;
- under common red-green and blue-yellow color-vision-deficiency simulations.

Units must remain distinguishable by silhouette, not only by hue. Accent brightness, outline weight, camera, light direction, material density, and visual mass must match the golden set.

### Terrain Gate

- Repeat every terrain tile in a `3x3` grid.
- Reject visible seams, edge discontinuities, directional light discontinuities, repeated central blobs, or obvious checkerboard rhythm.
- Confirm that gameplay overlays, selection frames, terminals, lairs, infrastructure, and units remain readable over the tile.

### In-Game Gate

- Capture the real Godot viewport at minimum, normal, and maximum camera zoom.
- Check explored, visible, and fogged states.
- Check player, enemy, and barbarian faction backdrops.
- Verify selected-unit framing and effects.
- Approval requires the real gameplay capture, not only an isolated asset preview.

## Godot Import Settings

Place only final runtime PNG files at the exact manifest paths. Godot imports source assets automatically and records their settings in adjacent `.import` files.

Recommended settings for the current 2D assets:

- compression mode: **Lossless**;
- mipmap generation: **Off**;
- alpha border fix: **On** for RGBA units/icons;
- premultiplied alpha: **Off** unless the rendering material is explicitly configured for it;
- no VRAM compression for these tiny 2D gameplay textures.

Commit the source PNG and its `.import` metadata. Do not commit `res://.godot/imported/`. Godot's official import documentation explains the source/import-metadata split and automatic reimport behavior: [Godot Import Process](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/import_process.html).

Before adopting exports larger than `16x16`, create a separate implementation task to normalize unit texture display size in `UnitsView`. Before producing the full building/UI set, create a separate task to define and implement its `GameUI` integration.

## Provenance, Legal, and IP Checklist

Every approved asset must have a provenance record containing:

- asset ID and version;
- model/tool and generation date;
- complete input prompt and settings;
- every visual reference, its source, license, and checksum;
- generation output checksum;
- manual editor and summary of edits;
- reviewer and approval date;
- confirmation that text, watermarks, logos, signatures, recognizable characters, and third-party trade dress were checked;
- confirmation that the source references were authorized for upload and commercial derivative work.

Additional rules:

- Do not prompt for named living artists, copyrighted characters, entertainment franchises, or imitation of a specific protected work.
- Do not assume AI output is unique or automatically free of third-party rights. OpenAI's agreement states that, as between the customer and OpenAI and to the extent permitted by law, the customer owns output, while also stating that output may not be unique and that the customer remains responsible for inputs and use: [OpenAI Services Agreement](https://openai.com/policies/services-agreement/).
- Human legal/IP review is required before commercial release. Provenance reduces risk but does not replace legal review.
- Krita may be used commercially, and artwork created with it belongs to its creator; the GPL applies to Krita's source code rather than the artwork: [Krita FAQ](https://docs.krita.org/en/KritaFAQ.html).

### Solana Name and Logo Caution

Use original network motifs and restrained cyan/violet/mint accents by default. Do not embed the official Solana logomark into routine terrain, units, buildings, or resource coins.

The Solana Foundation Terms identify “Solana” and its logos as trademarks and state that copying or use requires prior written permission: [Solana Foundation Terms of Service](https://solana.org/tos). If permission is obtained for a specific use, use only official brand assets and follow the official restrictions, including no stretching, outlines, shadows, low-resolution use, framing, or low-contrast placement: [Solana Foundation Branding](https://solana.org/branding).

Color inspiration and validator/network subject matter do not imply endorsement. Marketing copy and store art must not suggest that Solanazation is an official Solana Foundation product unless that relationship is documented.

## Implementation Stages

### Stage 1 — Lock Direction

- Approve this style bible and prompt template.
- Reconcile the asset catalog with the Data-driven manifest.
- Produce and approve the six-part golden set.
- Validate the current `16x16` art direction in the real game.

### Stage 2 — Current Gameplay Coverage

- Produce all nine terrain masters and exports.
- Produce all eight unit masters and exports.
- Complete automated, contact-sheet, seam, accessibility, and in-game gates.
- Retain SVG placeholders until every runtime PNG path has been verified.

### Stage 3 — UI Contract

- Define actual pixel sizes and paths for resource and action icons.
- Integrate texture-backed icons into `GameUI`.
- Produce the final UI icon set from the approved style references.

### Stage 4 — Building Contract

- Define where and at what size building art appears.
- Integrate building icons into city/build menus and details.
- Produce the Data-driven building set only after the contract is testable.

### Stage 5 — Finalization

- Run full-manifest and export validation.
- Perform final IP and trademark review.
- Archive source masters, prompts, references, provenance records, and approval contact sheets.
- Remove placeholders only after confirmed coverage and regression testing.

## Success Criteria

The pipeline is successful when:

- every currently rendered Data ID resolves to exactly one correctly named PNG;
- all current gameplay exports are readable and distinct at native `16x16` size;
- terrain passes `3x3` seam checks;
- batches pass grayscale, color-vision, contact-sheet, and real-viewport review;
- all assets match the approved golden set;
- Godot imports them with consistent 2D settings;
- every approved asset has complete provenance and human IP review;
- future building and UI production remains separated until those assets have a real integration contract.
