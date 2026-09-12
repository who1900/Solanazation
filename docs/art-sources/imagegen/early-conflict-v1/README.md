# Early Conflict V1 — Source Provenance

Date: 2026-08-25

- Mode: built-in imagegen; one call per distinct source asset.
- Reference language: `docs/world-art-contract.md` and `docs/concepts/salvaged-validator-frontier-v2.png`.
- Use case: `stylized-concept`.
- Shared prompt: polished hand-painted orthographic three-quarter native world sprite for a 16 px-cell mobile 4X game; Civilization-quality silhouette clarity; Salvaged Validator Frontier; dusty post-apocalyptic ivory ceramic, gunmetal, oxidized copper, graphite, restrained violet and rare cyan; single centered subject facing lower-right; no text, watermark, logo, frame, scenery, generic neon, photorealism, pixel art, or micro-detail.
- Chroma prompt: perfectly flat `#00ff00`, no shadow, floor, gradient, texture, reflection, light variation, or green in the subject.
- Transparent workflow: generated originals are preserved unchanged. Each generated alpha was composited over flat `#00ff00`; the installed `remove_chroma_key.py` helper then produced a soft matte with despill and one-pixel edge contraction. Native copies were cropped, Lanczos-downsampled, and placed on fixed transparent canvases. No CLI/API fallback was used.

## Sources and normalized subject prompts

| Asset | Built-in filename | Normalized subject request | SHA-256 |
|---|---|---|---|
| Miner Quad | `exec-5656e223-e316-481e-a902-aedfe9635568.png` | Fast four-wheeled mining/scout quad, low armored chassis, utility rack and compact tool-flamer; nimble silhouette, not a tank. | `6043562F85C9A2251886B04FC8586EF02E0016D26243CBDCEAD012D8D78814BC` |
| Raider Walker | `exec-8a4b235f-64ab-457e-8380-9f1d0efa79f4.png` | Medium biped assault walker, reverse-jointed legs, compact cockpit and blunt autocannon; forward triangular military silhouette. | `C8BA844BC3D76AF65EB09C41E34CFCFCAD6BFF759AA5DDB8B6A781B51C2E12AB` |
| Heavy Mech | `exec-9bacd8b8-399f-4c85-8eb3-fcbc4b67050e.png` | Towering heavy combat mech, asymmetric shoulder armor, large plasma cannon and stabilizer legs; unmistakable mass. | `1D68F20D1E913E76B3E910086CEE190C55BBA2D2B112B340052508BCFD5EC5CA` |
| Net Broker | `exec-ddfcb7d5-f93c-4d04-bbde-cbda9d27656e.png` | Hooded noncombat operator with portable relay console, antenna mast and ledger slab; slim, unarmed silhouette. | `786A6709B6F69C022C799B53A5DE6490033DBA50639F76E0793DEC47610EFBEC` |
| Virus Pickup | `exec-3b284aff-6791-4209-9c34-540735251a41.png` | Rogue pickup with welded ram, corrupted antenna cage and asymmetric armor; low predatory silhouette readable without red. | `A0D3A26B21753DDC8F916EA4983363DC798730683DDCD3E04AED81E69768F55D` |
| Auto-Mech | `exec-9935a444-5c45-4817-953a-43790c798b28.png` | Rogue autonomous industrial-salvage mech, hunched torso, claw, rotary weapon and cable crown; hostile asymmetric silhouette. | `C5E91E1568A1B1BA6A2805AACF058A2DCA1FC41A110B9939F68D3373DABA729F` |
| Master Server Lair | `exec-bee95865-f614-4182-a687-9ac1a5953292.png` | Fortified low server-crypt bunker with broken dish, jagged antenna crown and armored cable roots; boss-objective silhouette. | `05CC47603F1A19AFA16B973CCD95C39E034292F624669F742097EAD69A8BF6B0` |
| Construction | `exec-27d81f4b-2a28-4f54-afb6-3ca2c6bc09c2.png` | Two crossed steel braces, short crane hook and copper hazard pennant; neutral construction signal. | `67674A133EB83555944D7BB75516FC4C311C560DE071A121C98F20C013D32286` |
| Capital | `exec-fc09393a-fbd2-4d43-ba7d-c465b8230107.png` | Three blunt antenna prongs on a reinforced command collar; hierarchy without a literal crown. | `7666AB1D3A61C0EADC69CD146D2648B5FB4E051C3F5F2FD4F24E3FF9E1CC952D` |
| Powered | `exec-8884a511-94ce-4d74-84b5-6d1e907b325a.png` | Ceramic insulator, one cyan vertical core and two contacts; compact positive operational signal. | `597029DFAC1BD48471BB595C855319C27283389AD692E38AF60671E1B1495274` |
| Offline / DoS | `exec-b5936899-44a4-4a2d-ad46-e711464e4922.png` | Snapped antenna crossed by a heavy steel slash and dead-signal plate; failure readable without color. | `9D026D047032B6A3A44F1FB33F26AF74B12263A6B1BF5219CE13482A2BB47C6F` |

## Runtime contract

Units use fixed 96×96 transparent canvases, the lair 128×128, and city overlays 64×64. `WorldArt.gd` is the single path/anchor/display-size contract. Every listed unit ID is native-required and cannot enter the legacy procedural fallback. Ordinary cities intentionally have no state overlay; construction is independent, and state priority is offline/DoS, capital, powered, ordinary. A shared code-native faction marker uses both shape and color for player, rival, and rogue ownership.
