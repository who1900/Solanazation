# Landscape and Water v1 — Code-native provenance

Date: 2026-08-28

## Source decision

- Built-in imagegen calls: **0**.
- New raster sources: **none**.
- Reason: the approved `ocean-source.png` and its four existing 64px runtime derivatives already supplied the correct graphite-blue material. The visible weakness was renderer motion, shoreline hierarchy, fog gating, and low-bit variant repetition; replacing the authored source would have expanded the slice without addressing those causes.
- Existing raster provenance remains unchanged in `docs/art-sources/imagegen/vertical-slice-v1/README.md` and `docs/art-sources/imagegen/world-completion-v1/README.md`.

## Runtime derivation

`scripts/ui/WaterSurfaceView.gd` draws sparse paired ripple flecks in world space and two-value coast lines. It is visibility- and camera-bounded, updates at 4 Hz only at zoom 1.0 or above, and becomes static for reduced motion, headless execution, and overview zoom. `MapView` adds sparse deterministic material marks for wasteland, ruins, swamp, and node-zone, and never samples a neighboring transition through fog.

`WorldArt.variant_index()` retains four authored variants but avalanches the stable cosmetic hash before modulo four. This removes the former low-bit four-cell lattice without advancing or consuming gameplay RNG.

## Acceptance evidence

- Focused tests: `WORLD_ART_PASS`; `LANDSCAPE_WATER_PASS`.
- Native repeat/seam sheet: `docs/concepts/salvaged-terrain-all-nine-seam-check-v1.png`, SHA-256 `3EA6AA82B42CAFFE3BEDD578E0A3BE6015A5F9CA21BB7746D3C2820B8F29A10D`.
- 575px zoom sheet: `docs/captures/landscape/landscape-575-zoom-sheet.png`, SHA-256 `4FE2A45084EC0E0263BF0FF529AE8847F2F6ECDA012F691A511F18C45F276342`.
- 720px zoom sheet: `docs/captures/landscape/landscape-720-zoom-sheet.png`, SHA-256 `ACC86CB7F6B324102D4D1FE7CB8B982D15CA9D46D8221041C475B9E58198EBE0`.
- 575px phase A/B sheet: `docs/captures/landscape/landscape-575-phase-sheet.png`, SHA-256 `BB3FAB17061B044014D6E617DF59C7AC4BC66E22610E5E256054097090EEDBD3`.
- 720px phase A/B sheet: `docs/captures/landscape/landscape-720-phase-sheet.png`, SHA-256 `882A97D3E0F6E1353CBA7076FF7306F2E1DD55AA8350336E98776A745FE0A05E`.
- Original / grayscale / deuteranopia sheet: `docs/captures/landscape/landscape-720-cvd-sheet.png`, SHA-256 `10B9D0B42F5097FFA6941B47A161ADA23E285F15FB676DD496448BAC85480D08`.

The ten source captures are real Windows OpenGL Compatibility frames at 575×1280 and 720×1280. The zoom captures use 0.6, 2.0, and 3.5 with real city/unit art plus selection, reachable, and attack states. Phase A/B uses zoom 2.0 at water phase 0 and 7. Their SHA-256 values are:

| Capture | SHA-256 |
|---|---|
| `landscape-575-0.6.png` | `9F9037279734E8B246D0265B9D7C4A575D1AACA2076984FE0F41A560FE92644F` |
| `landscape-575-2.0.png` | `76393D93DE9F7FB83E758179F1146F3606C7CABB5091577F75ECAC55EAF40C0A` |
| `landscape-575-3.5.png` | `5D81263A9E413B2B2167EB8377D53DEFA20C6A7EA4E4AAFD872DF14AA0D648E5` |
| `landscape-575-phase-a.png` | `3516C5ACED2A9AF8143BF9ACF23062A8D7B49AD0CFDA4262ED2E83CB31F067CC` |
| `landscape-575-phase-b.png` | `29A59DF7E889E28A1324D257B6C829E05349CD3CD32B942363F994E0BAEAF7BB` |
| `landscape-720-0.6.png` | `E0664FAC4DCF122CA91A5A3C21937CFF652409E0CE008640F4A4BAF9B027637C` |
| `landscape-720-2.0.png` | `5EB3731543A5ADCD07E1841D7B83DFEE2473C8F285718504B7C7AD3C63C49817` |
| `landscape-720-3.5.png` | `AD29854A3A03B83A5CC5581B53E15943929F5CBE260DAF64CA4DB854D0974FBC` |
| `landscape-720-phase-a.png` | `923233736B221EB144DBB3216B34400114419F4ACD73F357B7DA55C8432B39A0` |
| `landscape-720-phase-b.png` | `5EB3731543A5ADCD07E1841D7B83DFEE2473C8F285718504B7C7AD3C63C49817` |

Measured water command generation on the GL test host was approximately 0.9–1.9 ms at maximum zoom, 6–7 ms at default zoom, and 21–27 ms for the one-time full-map overview draw. Overview animation is disabled, so the full-map cost is not recurring.
