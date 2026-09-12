# Solanazation — Art Pipeline (PNG assets)

Единый стиль: `Stylized game asset icon, post-apocalyptic dieselpunk, isometric perspective, vector art feel, highly detailed, dark copper and brass colors, glowing cyan accents, isolated on white background`

---

## A. Тайлы ландшафта (terrain, res://assets/terrain/)

| Файл | Промпт |
|---|---|
| `tile_wasteland.png` | Radioactive wasteland tile: cracked yellow-brown earth, small debris, isometric game tile |
| `tile_ruins.png` | Server ruins tile: rusty computer racks half-buried in sand, isometric game tile |
| `tile_swamp.png` | Toxic swamp tile: glowing green sludge with bubbles, isometric game tile |
| `tile_mountains.png` | Impassable mountains tile: dark rocky peaks, isometric game tile |
| `tile_node_zone.png` | Node zone tile: clean high-tech server rack in a rusty cage, glowing cyan, isometric game tile |
| `tile_crater.png` | Server crater relic site: massive blast crater with a glowing data core, cyan accents |
| `tile_dump.png` | Living dump relic site: mountain of scrapped circuit boards, salvage drones |
| `tile_rift.png` | Geothermal rift relic site: glowing magma fissure with steam vents |
| `tile_ocean.png` | Dark toxic ocean tile: oily water, faint cyan glow |
| `tile_ancient_terminal.png` | Rusty server rack with blinking green screen half-buried in sand (goody hut) |

## B. Юниты (res://assets/icons/units/, квадрат 1:1, прозрачный фон)

| Файл | Промпт |
|---|---|
| `unit_founder.png` | Stylized game icon, post-apocalyptic nomad with a bulky backpack full of glowing server parts, dieselpunk |
| `unit_rust_guard.png` | Stylized game icon, post-apocalyptic soldier in armor made of old tires, holding a pipe gun, dieselpunk |
| `unit_miner_quad.png` | Stylized game icon, rusty quad bike with a small flamethrower mounted on front, dieselpunk |
| `unit_raider_walker.png` | Stylized game icon, two-legged dieselpunk walker mech with a machine gun, dark copper |
| `unit_heavy_mech.png` | Stylized game icon, bulky two-legged mech with a plasma cannon, dark copper, glowing cyan accents, cyberpunk |
| `unit_net_broker.png` | Stylized game icon, cyberpunk diplomat-hacker in a long coat with holographic contracts, cyan glow |
| `unit_steam_shredder.png` | Stylized game icon, massive steam-powered shredder mech with rotating blades, brass and copper |
| `unit_cyber_acolyte.png` | Stylized game icon, cyber-cultist ranger with electromagnetic rifle, glowing cyan implants |
| `unit_armored_courier.png` | Stylized game icon, armored money-transport walker with a vault on its back, gold and copper |
| `unit_genetic_walker.png` | Stylized game icon, organic-looking mech grown from biomass, green veins, biopunk |
| `unit_centurion.png` | Stylized game icon, heavy diesel tank with double armor plates and a cannon, militaristic red |
| `unit_virus_pickup.png` | Stylized game icon, rusty hijacked pickup truck with a corrupted glowing screen, red warning lights |
| `unit_auto_mech.png` | Stylized game icon, corrupted construction mech with red glowing eyes, dark rust |

## C. Здания (res://assets/icons/blds/)

| Файл | Промпт |
|---|---|
| `bld_genesis_node.png` | Ancient bulky bunker with a satellite dish and glowing "GENESIS" text, validator core |
| `bld_steam_turbine.png` | Rusty steam turbine consuming glowing biomass, smoke stacks, dieselpunk |
| `bld_relic_validator.png` | Clean high-tech server rack tower inside a rusty protective cage, glowing cyan |
| `bld_assembly_forge.png` | Industrial assembly workshop with sparks and a half-built walker, dieselpunk |
| `bld_net_shrine.png` | Religious server altar with holographic candles, cult of the Network, cyan glow |
| `bld_sol_exchange.png` | Cyberpunk stock exchange booth with a glowing ticker showing SOL price, gold accents |
| `bld_archio_archive.png` | Ancient data archive library, shelves of glowing hard drives, dusty |
| `bld_biomass_purifier.png` | Greenhouse-like purifier with algae tanks and clean water output |
| `bld_nuclear_plant.png` | Blocky nuclear reactor with radiation warning signs, industrial |
| `bld_auto_factory.png` | Fully automated factory with robotic arms and conveyor belts |
| `bld_cyber_forge.png` | Cybernetic surgery-forge, implant assembly line, cyan and steel |
| `bld_global_server.png` | Massive global server tower with satellite uplink, world hologram |
| `bld_fusion_plant.png` | Fusion reactor with visible plasma containment ring, white-hot glow |

## D. UI-иконки (res://assets/icons/ui/)

| Файл | Промпт |
|---|---|
| `ui_sol.png` | Glowing cyan coin with the Solana logo, game resource icon |
| `ui_scrap.png` | Pile of rusty gears and metal parts, game resource icon |
| `ui_biomass.png` | Glowing green biomass blob in a flask, game resource icon |
| `ui_energy.png` | Yellow lightning bolt in a copper socket, game resource icon |
| `ui_tech.png` | Ancient circuit board with a graduation cap, research icon |

---

## Варианты внедрения (на утверждение)

**A. Процедурная генерация (я, без внешних сервисов):** стилизованные иконки
генерируются скриптом (Python PIL) в единой дизельпанк-палитре: силуэты +
глоу-акценты. Быстро (минуты), стиль единый, но иконки простые (не арт-класс).

**B. Промпты для DALL-E/Midjourney (ты):** берёшь промпты выше, генерируешь
внешне, кладёшь в папки с теми же именами — Godot подхватит автоматически
(замена ассетов по ТЗ, раздел 7).

**C. Оставить SVG-заглушки** (текущее) — отложить арт.

Рекомендация: A сейчас (играбельный вид), B — когда захочешь арт-класс.
