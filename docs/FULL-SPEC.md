# SOLANAZATION — Объединённое ТЗ (v1.0)

Свод всех ТЗ-сообщений заказчика в один документ. Источники:
1. «Ультимативное ТЗ» (база: концепт, ресурсы, юниты, здания, техы, вайб-пайплайн)
2. «Древо Технологий (Архиотех) и Эволюция Сетки» (эры, 5 фракций, дипломатия, протоколы, усталость, чудеса)
3. «6 критических систем Civ 1» (терминалы, ботнеты, формула боя, победы, сохранения, аудио)
4. «Пасхалки и Лор Solana + Solana Seeker» (события, артефакты, мобильный UI, монетизация)
5. «Карты» (размеры × типы + классическая Земля)
6. Требования процесса: игра полностью на английском; «продолжай» = автономное доведение плана до конца.

---

## 0. Общие сведения

- **Название:** Solanazation. **Жанр:** пошаговая 4X-стратегия (форк Civ 1 logic).
- **Сеттинг:** постапокалиптический кибер-дизельпанк; единственная ценность — $SOL.
- **Движок:** Godot 4 (GDScript). **Визуал:** стилизованный 2D-арт поверх дискретной сетки.
- **Цель игры:** контролировать Консенсус — захватить/построить как можно больше Валидаторов.
- **Платформа (пивот):** мобильное приложение Solana Seeker (портрет, одна рука), десктоп-прототип как база.
- **Язык:** интерфейс, логи, комментарии, доки — только английский (проверка: grep кириллицы = 0).

## 1. Концепт и сюжет

- Гиперинфляция уничтожила фиат; сеть «Solana-Genesis» на спутниках/бункерах выжила.
- Прошло 100 лет; кланы «майнят» $SOL физически — восстанавливают электростанции, питают серверные стойки.
- Игрок — лидер клана «Мусорщиков Сети», нашёл обесточенный Genesis Node.
- Игровой цикл: Биомасса → Запчасти → Электростанция → Валидатор → $SOL → Архиотех → Армия → Захват Валидаторов.

## 2. Ресурсы

| Ресурс | Роль |
|---|---|
| Scrap (Запчасти) | производство (здания, простые юниты) |
| Biomass (Биомасса) | рост населения |
| Energy (Энергия) | содержание (upkeep) зданий/юнитов; 0 энергии → $SOL не майнится (аптайм) |
| $SOL (Солана) | технологии, дипломатия, высокие юниты, Сетевой Сбор (города не бесплатны) |

## 3. Карты

- **Размеры:** Small 60×40 / Medium 80×50 / Large 120×70.
- **Типы:** Continents, Pangaea (много суши), Archipelago, Inland Sea, Islands, **Earth** (классическая Земля), Random.
- **Генерация:** числовой seed; биомы через FastNoiseLite: < −0.3 вода/болото, −0.3..0.4 пустошь, 0.4..0.7 руины, > 0.7 непроходимые горы.
- **Архитектура сценариев:** реестр генераторов (новый сценарий = новый класс + строка реестра).
- **Старт фракций:** разные регионы/материки карты.

## 4. Ландшафт

| Тип | Еда | Scrap | Энергия | $SOL | Особенность | Защита |
|---|---|---|---|---|---|---|
| Wasteland | 1 | 1 | 0 | 0 | — | ×1.0 |
| Server Ruins | 0 | 3 | 0 | 1 | — | ×1.5 |
| Toxic Swamp | 2 | 0 | 0 | 0 | +1 радиация (штраф роста) | ×0.75 |
| Node Zone | 0 | 0 | 20 | 5 | только ТЭЦ/Валидатор | — |
| Mountains | 0 | 1 | 0 | 0 | непроходимые | ×2.0 |
| Ocean | 0 | 0 | 0 | 0 | вода, непроходимо | — |
| Server Crater (реликт) | 0 | 0 | 0 | 15 | реликтовое место | — |
| Living Dump (реликт) | 0 | 10 | 0 | 0 | реликтовое место | — |
| Geothermal Rift (реликт) | 0 | 0 | 50 | 0 | реликтовое место | — |

## 5. Юниты (база)

| Юнит | Moves | Atk | Def | Цена | Энергия |
|---|---|---|---|---|---|
| Node Founder | 1 | 0 | 1 | 🔩20 | 1 |
| Rust Guard | 2 | 1 | 1 | 🔩10 | 0 |
| Miner Quad | 4 | 2 | 1 | 🔩15 ◎5 | 1 |
| Raider Walker | 3 | 3 | 2 | 🔩25 ◎10 | 2 |
| Heavy Mech | 3 | 5 | 4 | 🔩40 ◎30 | 5 |
| Net Broker | 2 | 0 | 1 | ◎25 | 1 |

- **Эволюция юнитов** (апгрейд за $SOL в городе): Rust Guard → Raider Walker → Heavy Mech; Miner Quad → Raider; Founder → Miner Quad.
- **Ветеранство:** +50% к характеристике; статус после первого выживания в бою.

## 6. Здания (база)

Genesis Node (+5◎), Steam Turbine (+20⚡), Relic Validator (+10◎, только руины), Assembly Forge (ветераны), Net Shrine (снижает усталость), SOL Exchange ($SOL от населения), Archio-Archive (+50% очки техов), Biomass Purifier (убирает штрафы), Nuclear Plant (+100⚡), Auto-Factory (+5🔩), Cyber Forge.

- **Эволюция зданий:** Steam Turbine → Nuclear Plant (Atomic Reactor, ◎20) → Fusion Plant (+200⚡, Quantum Computing, ◎50).

## 7. Технологии (Архиотех): 4 эры × 3 ветки

Ветки: **Железо & Энергия** (iron) · **Сеть & Консенсус** (net) · **Биотех & Выживание** (bio).
Для перехода в новую эру исследуется «Ключевой Протокол» (первая техника ветки iron эры).

| Эра I: Дизель | Эра II: Кремний | Эра III: Кибернетика | Эра IV: Орбита |
|---|---|---|---|
| Steam Synthesis → | Atomic Reactor → | Quantum Computing → | Satellite Uplink |
| Primitive Coding → | Block Encryption → | Smart Contracts → | Global Consensus |
| Hydroponics → | Radiation Engineering → | Cyber Implants → | Terraforming |
| + Firedancer (Эра IV, независимый клиент) | | | |

Пассивные эффекты:
- Steam Synthesis: +1 Scrap на всех руинах.
- Primitive Coding: открывает Net Broker; разрешает торговлю $SOL.
- Block Encryption: −25% шанс взлома ваших городов; открывает Relic Validator, SOL Exchange.
- Atomic Reactor: города +10 Energy/ход; открывает Nuclear Plant.
- Smart Contracts: авто-конверсия 10 избыточной Energy → 1 $SOL; открывает Auto-Factory.
- Cyber Implants: пехота +1 движение; открывает Heavy Mech, Cyber Forge.
- Satellite Uplink: снимает туман войны вокруг вражеских валидаторов.
- Global Consensus: Совет Консенсуса, +$SOL.
- Terraforming: пустошь +1 еда.
- Firedancer: навсегда убирает риск «Сбоя Консенсуса», +50% лимит Energy.

## 8. Фракции (5)

| Фракция | Архетип | Пассивка | UU (замена) | UB (замена) |
|---|---|---|---|---|
| Rust-Tech Clan | Промышленники | здания −20% Scrap | Steam Shredder (Heavy Mech: −50% ◎, +50% против пехоты) | Scrap Dock (Assembly Forge: +2🔩 с руин, ветераны) |
| Global-Net Cult | Сетевые | валидаторы +25% $SOL при избытке Energy | Cyber Acolyte (Miner Quad: EMP-аура −1 движение соседям) | Server Altar (Net Shrine: +2◎ +2⚡) |
| DAO Syndicate | Капиталисты | Net Broker без содержания; торговля +50% $SOL | Armored Courier (Raider: 50% стоимости врага в $SOL при убийстве) | Liquidity Pool (SOL Exchange: 1 Pop = 1◎) |
| Bio-Coders | Адаптанты | иммунитет к радиации/болотам | Genetic Walker (Heavy Mech: питается Биомассой, без содержания) | Bio-Server (Steam Turbine: Energy из Биомассы) |
| Steel Protocol | Милитаристы | +25% атака вне территории | Centurion (Raider: двойная броня против дальнего боя) | Fortress Server (Assembly Forge: +100% защита города) |

## 9. Бой (точная формула Civ 1)

```
Шанс победы Атакующего = Atk_атаки / (Atk_атаки + Def_защиты × Mod_земли × Mod_опыта)
```
- Модификаторы земли: Ruins ×1.5, Swamp ×0.75, Mountains ×2.0, Wasteland ×1.0.
- Fortify (+50% защиты): юнит простоял на клетке 1 ход без движения.
- Veteran (+50%): после первого выживания в бою.
- Расчёт мгновенный в памяти; анимация лишь визуализирует (анимации — полировка).

## 10. Дипломатия (Network Politics)

- **Net Broker** (вход во вражеский город/юнит):
  - Airdrop/Взятка: переманивание юнита за $SOL.
  - Sybil-Атака/Взлом: похищение до 30% $SOL из казны.
  - DoS-Атака: отключение Электростанции/Валидатора на 3 хода (город теряет производство).
  - Хардфорк: бунт жителей.
- **Договоры:** Эирдроп Дружбы (отношения «Пинг»), Стейкинг-Альянс (общие энергосети), Хардфорк (объявление войны).
- **Совет Консенсуса** (после Global Consensus, раз в 15 ходов): голосование $SOL за глобальные законы — «Сжигание Токенов» (все −20% казны, наука −50% стоимости), «Энергетический Налог» (валидаторы +2⚡), «Блокировка Адреса» (запрет атак на фракцию 10 ходов).

## 11. Протоколы управления (формы правления)

| Протокол | Аналог Civ 1 | Плюсы | Минусы |
|---|---|---|---|
| Peer-to-Peer | Анархия | нет содержания юнитов | −50% генерация $SOL |
| Proof-of-Work | Олигархия | +50% Scrap, юниты быстрее | армия дороже по Energy |
| Proof-of-Stake | Демократия | +50% $SOL, бесплатный ресерч | юниты за $SOL, бунты при войне |
| Central Server | Деспотия | города игнорируют Усталость | −30% наука |

## 12. Сетевая Усталость (High Latency)

- Причины: нехватка Energy, война, отсутствие зданий связи (Net Shrine снижает).
- Последствия при критическом уровне: валидаторы Offline (нет $SOL, производство стоит), спавн «Свихнувшихся Автоматонов», уничтожающих постройки.

## 13. Чудеса (Великие Артефакты Предков)

| Чудо | Аналог Civ 1 | Эффект |
|---|---|---|
| Genesis Block | Великая Стена | иммунитет к DoS/взломам 50 ходов |
| Orbital Mainframe | Библиотека Александрии | открывает победу Uplink (таймер 20 ходов) |
| Quantum Cooler | Сады Семирамиды | upkeep валидаторов = 0 |
| Satellite Emitter | Программа Аполлон | победа «Глобальный Синхрон» (таймер 20 ходов) |

## 14. Победы (4)

| Тип | Название | Условие |
|---|---|---|
| Военная | 51% Attack | захватить/уничтожить Genesis Node (столицы) всех фракций |
| Научная | Global Uplink | Satellite Uplink + Orbital Mainframe работает 20 ходов |
| Экономическая | Validator Monopoly | >80% всех $SOL в казне 10 ходов |
| Дипломатическая | Global Consensus | 2/3 голосов Совета после постройки Global Server |

## 15. Забытые Терминалы (Goody Huts → Ancient Terminals)

Спавн при генерации в неисследованных зонах. Вход юнита — один из исходов:
- **Форк Сети:** мгновенно 10–50 $SOL.
- **Утечка Чертежей:** бесплатная 1 случайная технология текущей эры.
- **Древний Автоматон:** юнит Heavy Mech / Miner Quad в армию.
- **Сбой Питания (trap):** спавн 2 вражеских Ботнетов на соседних клетках.

## 16. Свихнувшиеся Ботнеты (варвары)

- Спавн каждые 10 ходов на клетках тумана войны, далеко от валидаторов.
- Virus Pickup (Atk 1, Moves 3) — охотится за Founder, разоряет Электростанции.
- Auto-Mech (Atk 3, Def 2) — атакует города.
- Логово «Магистральный Сервер»: захват юнитом игрока → +25 $SOL +30 Scrap.

## 17. Инфраструктура

- **Кабельная линия:** движение ⅓ MP (3 клетки за 1 очко).
- **Монорельс:** движение 0 MP, +1 $SOL с тайла.
- Строительство — действия юнита (панель/радиальное меню).

## 18. Улучшения территорий

- **Scrap Mine** (только Ruins): +2 Scrap.
- **Hydroponic Dome** (только Swamp): +2 Food, снимает штраф.
- **Relay Tower** (Wasteland): +1 Food +1 Energy.
- Строит Node Founder (1 ход, рядом с городом).

## 19. События (Лор Solana)

- **Network Outage** (Эра II–III): все валидаторы теряют связь на 1 ход — $SOL не добывается, активные способности недоступны.
- **Meme Coin Surge:** на 3 хода случайный город +300% к $SOL, Сетевая Усталость до максимума.
- **Jito Bundle Tip (game abstraction):** instantly completes a unit or building for fictional `$SOL`. A real bundle tip is separate from Solana's compute-unit priority fee, and neither receipt nor a higher tip guarantees that a bundle lands.

## 20. Реликтовые артефакты

- **Dragon Suit (Toly):** находка в Терминале; +20% скорость постройки, мораль войск.
- **Genesis Chapter:** +10% $SOL, защита от Sybil-атак.
- **Firedancer (Священный Грааль):** тех Эры IV — убирает риск Outage, +50% Energy.

## 21. Сохранения и seed

- Вся карта строится на seed (FastNoiseLite); воспроизводимость.
- Сохранение JSON < 500 КБ: seed, turn, global_sol_pool, игроки (id, sol, protocol), map_grid, units, … (плюс все системы: города, техы, события, артефакты, инфраструктура, туман, ИИ-ресурсы, победы-счётчики).

## 22. Аудио

- Музыка: Dark Ambient / Industrial Synthwave (Frostpunk/Cyberpunk 2077) — промпт для Suno/Udio.
- SFX: пар (движение), реле/разряд (конец хода), джингл кассы ($SOL), плюс постройка и бой.
- Ресурсы — через AudioStreamPlayer / AudioStreamPlayer2D.

## 23. Мобильный UI (Solana Seeker)

- **Android Back priority:** Game Over consumes Back until Restart Match or New Game is chosen. Otherwise: Glossary → Network Status → Tech Detail → Diplomacy → Tech → City Actions → Broker Menu → selected city/unit. The first-screen menu consumes Back and never quits or exposes an unstarted match.

- Портретная ориентация (Portrait First), игра одной рукой (Battle for Polytopia).
- Микро-хедер: SOL/Energy.
- **Радиальное контекстное меню** юнита: Атака, Укрепление, Кабель, Разборка.
- **Конец Хода:** кнопка в правой нижней зоне, длинный свайп вправо (защита от случайных нажатий).
- Нижний «однорукий» навигатор: [Дерево Тех] [Города] [Конец Хода].
- **Seed Vault:** аппаратное уведомление + биометрия при DoS/взломе города.
- **Haptics:** разные рисунки вибрации (бой мехов, сбой валидатора, подтверждение транзакций).
- Zero Apple/Google Tax (dApp Store): микро-$SOL транзакции без посредников.

## 24. Монетизация (Solana dApp Store, Fair F2P без P2W)

- **Consensus Pass:** сезонные награды (бесплатный трек) + премиум за $SOL/SKR (эксклюзивные скины, звуки, анимации победы).
- **PvP Staking Arenas:** дуэли со смарт-контрактом (пул по 0.1 $SOL/SKR, выплата победителю, комиссия 2.5% на сжигание).
- **Holder Benefits (Seeker):** уникальная фракция/скин, +5% XP сезонного пропуска, бесплатные премиум-турниры.
- **cNFT-маркетплейс:** косметика как compressed NFTs с нулевой комиссией, перепродажа.

## 25. Графика

- Промпты для DALL-E/Midjourney: стиль «post-apocalyptic dieselpunk, dark copper/brass, glowing cyan accents».
- Тайлы земли (4), иконки юнитов (founder, rust_guard, miner_quad, heavy_mech), иконки зданий (palace, электростанция, валидатор).
- Замена ассетов перезаписью файлов с теми же именами (assets/icons/…).

## 26. Процессные требования

- План развития волнами (карты → системы → глубина → полировка); «продолжай» = автономное доведение до конца без вопросов между батчами.
- Каждая волна заканчивается запуском + smoke-тестом; строгие предупреждения Godot (явная типизация).
- Игра, код, доки — только английский.

## 27. Standard Educational Layer (Authoritative)

This section supersedes earlier player-facing technology labels while preserving every stable technology ID, dependency, unlock, passive, and save contract. The four eras are pedagogical progression bands, not historical claims:

1. **Foundation** — ordered time, accounts, transactions, and fees.
2. **Composition** — validators and Tower BFT, programs and PDAs, CPI and SPL Tokens.
3. **Scale** — Turbine and stake-weighted QoS, parallel execution and compute units, v0 transactions and Address Lookup Tables.
4. **Production** — RPC and commitment, Bubblegum V2 compressed NFTs, Token Extensions and Jito bundles, plus client diversity as the optional thirteenth node.

The three branches are **Validator Engineering**, **Program Architecture**, and **Transaction Economy**. Each technology detail explicitly separates **Game Effect**, **Real Solana**, and **Wasteland Analogy**, links only to primary official documentation, and exposes the shared glossary without a forced quiz or popup. Gameplay rewards are analogies: Energy is not compute units, fictional `$SOL` is not real SOL, and no technology guarantees returns, throughput, fees, transaction landing, finality, validator uptime, or outage immunity.

The read-only Network Status panel reuses the current energy-component calculation and reports powered validators, component count, signed component surplus, available Energy, unit upkeep, and expected base validator output or its offline reason. It is labeled as a simplified game analogy and is not live network telemetry.

The v1 product remains offline-first. It contains no wallet connection, Seed Vault prompt, onchain transaction, real-SOL payment, staking, token issuance, NFT ownership, or financial reward. Those concepts require separate retention evidence plus legal and security review before they can enter scope.

## 28. Android Debug Export Baseline

After the pinned official templates are provisioned, the metadata-reproducible development export uses Godot 4.4.1, JDK 17, Android SDK/build-tools 34, the GL Compatibility renderer, and no Gradle, NDK, CMake, wallet, or network integration. Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build_android_debug.ps1`; the ignored output is `build/android/solanazation-debug.apk`. The script validates the toolchain and template hashes, replaces inherited debug-signing variables with an isolated disposable keystore, and verifies that the APK signer matches it. Debug APK byte hashes may differ because of signing or archive timestamps.

The development-only identity is `com.solanazation.game.debug`, `versionCode 1`, and `versionName 0.1.0-debug`. It is portrait, ARM64-v8a only, min SDK 21, target SDK 34, contains no requested Android permissions, and is signed by an isolated disposable debug key. It is not eligible for store submission. The permanent package ID, permanent dApp signing key, adaptive store-quality icon set, release APK, upgrade test, and Android 16 Seeker install/launch/logcat evidence remain release gates.
