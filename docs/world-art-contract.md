# Solanazation World-Art Contract — Complete Terrain Set

Date: 2026-08-28

## Renderer contract

- Logical grid remains `TILE_SIZE = 16`; 64px source tiles are display assets, not a renderer-scale migration.
- `MapView` and `UnitsView` explicitly use linear CanvasItem filtering.
- PNG import contract is Godot lossless compression (`compress/mode=0`), mipmaps off, alpha-border fix on, premultiplied alpha off, and no size limit. SVG imports use the same texture settings at scale 1.
- Terrain variant is `mixed_stable_hash(game seed, terrain id, cell) mod 4`. The final avalanche happens before the power-of-two modulo so adjacent cells do not form the former four-cell lattice. It is cosmetic, deterministic, and never advances gameplay RNG.
- The fallback path remains defensive for unknown or damaged content, but every terrain ID in `Data.TERRAIN` resolves to native world art in ordinary generated maps.

## Runtime manifest

Terrain is opaque 64×64 PNG:

- `assets/world/terrain/{ocean,wasteland,ruins,swamp,node_zone,mountains,crater,dump,rift}/base_00.png` through `base_03.png`.
- `assets/world/terrain/{kind}/edge_{n,e,s,w}.png` is a transparent 64×64 neighboring-material feather. Orthogonal boundaries stack; matching neighbors draw no transition.
- `assets/world/terrain/{mountains,crater,rift}/landmark_00.png` through `landmark_02.png` are transparent 64×64 semantic silhouettes over their matching bases. Variant choice uses the cell, terrain ID, and visual seed; no rotation or mirroring is used. These overlays communicate impassability or hazard without changing terrain rules.

## Water and material-detail pass

- `WaterSurfaceView` is a code-native child of `MapView`. It adds sparse world-space ripple pairs and a restrained two-value coast line over visible ocean only; no new raster or image-generation source was introduced.
- Ripples update at 4 Hz only at zoom `>= 1.0`. Overview zoom, reduced motion, and headless execution use phase zero and do not schedule recurring full-map redraws.
- Water command generation is camera-clamped. At the 575px focused acceptance state the reduced-motion pass drew 121 visible water cells in 1.1–3.2 ms on the Windows GL-compatibility test host.
- Native terrain transitions now require the neighboring cell to be visible before reading or drawing its material. Coastlines follow the same rule, preventing terrain silhouettes from leaking through fog or shroud.
- Wasteland, ruins, swamp, and node-zone receive sparse deterministic code-native material marks. These communicate cracks, broken server slabs, stagnant reeds, and functional node traces without adding icons, rules, or high-chroma noise.

Entities are transparent PNG and use a bottom-center ground anchor:

| ID | Runtime path | Native size | Anchor px | Logical display box | Z |
|---|---|---:|---:|---:|---:|
| Era-I city | `assets/world/entities/city/era_1_validator.png` | 128×128 | 64,112 | 24×24 | 5 |
| Founder | `assets/world/entities/units/founder.png` | 96×96 | 48,84 | 20×20 | 10 |
| Rust Guard | `assets/world/entities/units/rust_guard.png` | 96×96 | 48,84 | 20×20 | 10 |
| Steam Cruiser | `assets/world/entities/units/steam_cruiser.png` | 128×96 | 64,76 | 24×18 | 10 |
| Terminal | `assets/world/entities/terminal.png` | 64×64 | 32,52 | 16×16 | map POI |

Infrastructure and icons:

- `assets/world/infrastructure/cable.svg`: external junction module; renderer adds only those copper connectors whose orthogonal neighbor is also cable.
- `assets/icons/resources/{scrap,biomass,energy,sol}.svg`: 64×64 source, shown at 22 logical px in the HUD with mono numerals.
- `assets/icons/actions/{move,attack,select,reachable,blocked}.svg`: 64×64 source. Current slice wires selection, reachable, attack, and invalid-target states; `move` is reserved for the matching contextual action.

## Capture acceptance states

- `02b-world-golden` at 575×1280 and 720×1280: fixed seed 424242, four slice terrains, all five entities, one terminal, connected cable, resource icons, and fallback fog around the patch.
- `02c-world-all-nine` at 575×1280 and 720×1280: all nine terrain IDs in a deterministic 3×3 material matrix, including the three landmark overlays.
- `09-selected-reachable`: selection brackets plus quiet reachable cells.
- `10-invalid-target`: short-lived branded blocked state.
- Setup, city production, and Tech captures remain in the same harness to guard against visual regressions outside the map.

The complete repeat-grid acceptance sheet is `docs/concepts/salvaged-terrain-all-nine-seam-check-v1.png`; every native terrain variant has exact opposite-edge RGB delta `(0,0)`. Original-slice provenance remains in `docs/art-sources/imagegen/vertical-slice-v1/README.md`; the five added materials and three landmarks are recorded in `docs/art-sources/imagegen/world-completion-v1/README.md`.

Landscape-water acceptance is recorded in `docs/art-sources/code-native/landscape-water-v1/README.md`.
