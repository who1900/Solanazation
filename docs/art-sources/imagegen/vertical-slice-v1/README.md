# Vertical Slice V1 — Source Provenance

Date: 2026-08-21

- Mode: built-in imagegen
- Style reference: `docs/concepts/salvaged-validator-frontier-v2.png`
- Prompt record: normalized user-visible request; service may internally augment.
- Shared constraints: stylized hand-painted orthographic 3/4 mobile 4X asset; fixed upper-left key light/lower-right shading; quiet graphite/dust/ceramic/copper; violet functional signal, cyan rare; strong 64px silhouette; no text, logo, watermark, photorealism, pixel art, or generic neon.
- Entity backdrop: perfectly flat `#00ff00`; no floor, shadow, or green in the subject.
- Terrain framing: direct top-down, continuous edge-to-edge quiet material; no grid, border, objects, or focal point; intended to supply four distinct 64px crops.

## Sources

| Workspace source | Built-in generated filename | Normalized asset brief | SHA-256 |
|---|---|---|---|
| `founder-source.png` | `exec-d8662d03-3e8e-4330-b8fc-5c947abd15b2.png` | Era-I frontier founder: robed salvager-engineer with relay staff and rugged field case. | `9A16E8B384A21E6CB3ED8F55AEAD0E6FCC72880E7F8BC4510BF703DF3D4AC839` |
| `rust-guard-source.png` | `exec-91c03c69-06f8-46de-a70f-9f7e7f0a7d3b.png` | Heavy rust guard in repaired ceramic armor carrying an industrial rifle. | `76ED4F329A3E4D2476A05045DB3DB13F0A3313090D8BD2000996ABB36C99FE42` |
| `steam-cruiser-source.png` | `exec-4ee149b6-43e6-41e0-a9a7-f12c7e8e1d9d.png` | Low, long steam cruiser assembled from armored salvage, pipes, and validator hardware. | `2F634C147D5502543B74355CB3017335FBEA5B37706000DF396335B11BA410DE` |
| `era-1-validator-source.png` | `exec-e72f3e66-16b8-4492-a3fb-1264c77a145f.png` | Compact Era-I validator settlement with repaired ceramic shells, copper conduits, antennas, and restrained violet core light. | `F1A0ACDEB4041BB0968A7251252AA10A32254474C5B1EEA771A6B5F88528F57A` |
| `terminal-source.png` | `exec-37aaf341-7ba6-4b7d-9f4e-21944b5fd81e.png` | Ancient field terminal: squat salvaged console with antenna, copper service pipes, violet screen, and one rare cyan status light. | `A9324B761CF7427D1E277F169CF813FD075D203E070739FF63065200A4B74612` |
| `wasteland-source.png` | `exec-dd091c63-e384-49e2-915d-fe0b86931d4d.png` | Quiet dry wasteland material: compacted dust, worn stone, fine cracks, and very sparse oxidized traces. | `F6F9E77D1BCA58B54115A7985AAD019E69E07FDE49B93D38FBAA8C3030807310` |
| `ocean-source.png` | `exec-7f83fde7-5fed-4848-b72c-8ea9fdb54427.png` | Dark graphite-blue ocean material with subdued wave relief and no bright foam lattice. | `8A7B5665A3F30FEB90A8F49774D881F3208AA06B985607883F17239917B4BE62` |
| `ruins-source.png` | `exec-6b6803c1-772b-4830-be58-136ed217f038.png` | Buried ruined infrastructure material: broken slabs, faint conduit fragments, dust, and quiet copper traces. | `46A7ABD77E221611EF6D729102B49CD191EF2F989F1268952C3867513E622BFE` |
| `node-zone-source.png` | `exec-8258d076-740b-4adb-8020-409c0d68f68c.png` | Dark quiet node-zone material: worn graphite plates and extremely sparse violet/cyan functional points. | `C0FE21B91D21F727AEFF76E10B22D653215108783705FCEB8E88E9BCBCC6B3CD` |

## Runtime derivation

Entity sources are preserved unchanged here. The installed imagegen chroma-key helper creates a soft alpha matte with despill; `.local-tooling/world-art/process_entities.py` then crops, downsamples, and places each subject against its documented ground anchor. Terrain variants and restrained edge overlays are derived by `.local-tooling/world-art/process_terrain.py`; the script verifies exact opposite-edge equality and writes the repeat-grid acceptance sheet at `docs/concepts/salvaged-terrain-seam-check-v1.png`.
