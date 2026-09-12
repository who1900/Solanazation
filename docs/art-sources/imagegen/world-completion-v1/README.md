# World Completion v1 — Source Provenance

Date: 2026-08-21

- `mode: built-in imagegen`
- Reference: `docs/concepts/salvaged-validator-frontier-v2.png`
- `prompt_record: normalized user-visible request; service may internally augment`
- The original generated PNGs are preserved here. Runtime images are derived copies; the Codex-generated originals were not deleted.

## Shared generation brief

Stylized hand-painted orthographic 3/4 mobile 4X asset; fixed upper-left key light and lower-right shading; quiet graphite, dust, ceramic, and copper materials; violet is a functional signal and cyan is rare; strong silhouette at 64px; no text, logo, watermark, photorealism, pixel art, or generic neon.

Entity landmarks used a flat `#00ff00` background with no floor or shadow and no green in the subject. Terrain sources used a direct top-down, continuous edge-to-edge quiet material with no grid, border, objects, or focal point, intended for four distinct 64px crops.

## Sources

| Asset | Generated filename | Preserved source | SHA-256 | Normalized asset request |
|---|---|---|---|---|
| Swamp material | `exec-ea0bf103-78b6-48e5-9401-806ab44faa03.png` | `swamp-source.png` | `715F0C9DB2056B144A37FF9A771A995055CF009A10331785FDCCA55D2A9BCD1B` | Mud, shallow stagnant water, ash reeds, muted olive-brown organic traces; quiet traversable ground. |
| Dump material | `exec-abd29851-b6b8-4a52-ab10-5134a71d1e90.png` | `dump-source.png` | `58031C191EB6EF57ED52B0F20409F4105FFAEB603804EDAE7BE89C9E3656E4D0` | Compacted scrap plates, broken ceramic, cable fragments, dark dust and restrained rust; no discrete loot pile. |
| Mountains base | `exec-fdf187eb-c0a3-416a-a135-3baa8f597f5d.png` | `mountains-base-source.png` | `D210D4E67F7F4AE5D5991AF0E4624BB9DA9CB6C6E2EE0937EBDE86FD423D01C4` | Cold fractured slate and compressed scree, low contrast, suitable beneath a landmark silhouette. |
| Crater base | `exec-42b9d01a-b5fe-42a1-b008-8cdfc1a0573a.png` | `crater-base-source.png` | `52505B0DB4D240AD1A790D4AC617B2461ACA01D482DBAC7BF8E250CE043A9453` | Charred compacted earth and impact dust with a restrained violet mineral trace; no crater focal object. |
| Rift base | `exec-ec5f5ef3-b5c5-41a7-85e5-67027e9081c3.png` | `rift-base-source.png` | `8A4276B9AC9C0BF28BA9D09097FE64A420D6C4C000D92C5A816CEBC54A4DBD56` | Dark tectonic crust and hairline warm mineral traces, quiet enough for an overlay landmark. |
| Mountain landmark | `exec-95519b67-4c09-4639-b157-022d21a03fde.png` | `mountains-landmark-source.png` | `20F03C4E0C2EA745B9E3AE2DD8842244EB3D8CD8616A3F20DAA4970E50741FCB` | Compact jagged impassable slate massif, broad grounded footprint, readable at 64px. |
| Crater landmark | `exec-ad6f3bee-e438-4997-bacf-c33f23d73f42.png` | `crater-landmark-source.png` | `70BF84C7C929F761B0A2356AD5473AEC2BA04EB046F0ADEB3561CE28BC8E73C2` | Circular collapsed impact basin with salvaged retaining fragments and a very small violet signal point. |
| Rift landmark | `exec-c3a790ff-8433-4772-ab14-5a27b96c730c.png` | `rift-landmark-source.png` | `04C49398C1159EA464C50575A1A1560F99A033CBE27FFBE84AD0FF0DDC8E3FF6` | Narrow split in dark rock, restrained amber depth and one small violet instrument; no lava spectacle. |

The later landmark-variation pass is preserved independently from those original
single-silhouette sources:

| Asset | Preserved source | SHA-256 | Normalized asset request |
|---|---|---|---|
| Mountain landmark variations | `mountains-landmark-variants-source.png` | `AB59F12AC95B15B15BC8D74C3AE60926140323A5B0A7CB799455503A6948BB49` | Three distinct compact slate massifs in one three-column chroma-key sheet, with different peak count, height, and footprint. |
| Crater landmark variations | `crater-landmark-variants-source.png` | `92D8C7F0F990B2DB985BC386701FA942FEF887AFAFA8443A986070064BF644CD` | Three distinct collapsed impact basins in one three-column chroma-key sheet, with restrained salvaged rims and violet signal points. |
| Rift landmark variations | `rift-landmark-variants-source.png` | `AF60C6259A99A8225AEE36E10333F31CB4CE166675D455EFD38D6EDCEB5F304F` | Three distinct narrow tectonic splits in one three-column chroma-key sheet, with restrained amber depth and small violet instruments. |

## Processing and acceptance

`remove_chroma_key.py` produced soft alpha mattes with a one-pixel contraction, feathering, and despill. `.local-tooling/world-art/process_world_completion.py` then crops, grades, downsamples, and makes four exact 64x64 repeat-safe variants for each material. It also produces 64x64 transparent landmarks and the acceptance sheet `docs/concepts/salvaged-terrain-all-nine-seam-check-v1.png`.

Runtime paths are `assets/world/terrain/<terrain>/base_00.png` through `base_03.png`, `edge_n.png`, `edge_e.png`, `edge_s.png`, and `edge_w.png`. `mountains`, `crater`, and `rift` additionally provide `landmark_00.png` through `landmark_02.png`. Opposite base edges are pixel-identical; landmark corners are transparent; detected chroma-fringe pixels at native size: zero.
