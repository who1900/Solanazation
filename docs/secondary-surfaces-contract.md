# Secondary surfaces UX contract

Status: implementation checkpoint
Scope: existing gameplay surfaces only; no new rules, routes, or assets.

## Shared grammar

- One title row, one scrollable content region, one Back/Close action.
- First level is a scannable status or consequence. Supporting mechanics live behind a
  touch-sized `i` disclosure when reliable detail already exists.
- Opaque Quantum Lab cards, Geist type, one-pixel separators, 4 px maximum radius.
- Interactive controls are at least 48 logical pixels high (60 on compact 575 layouts).
- Opening, closing, or expanding a surface never mutates simulation state.

## Surface information architecture

| Surface | First level | Primary action | Disclosure |
|---|---|---|---|
| Diplomacy | Rival, agenda, relation, ping or war exhaustion | One action appropriate to current relation | `i` shows the remaining legal actions and trade gate |
| Glossary | Group heading, term, one-line definition | None | `i` reveals the official source link |
| Network status | Powered validators, components, available Energy, upkeep; component and validator rows | None | `i` explains that this is a simplified game analogy |
| Protocols | Active/available state, name, one-line effect | Activate protocol | `i` repeats exact mechanics separately from selection |
| Wonders | Built/available/locked state, cost, one-line effect | Build wonder | `i` shows prerequisite and effect classification |
| Game over | Victory/defeat, winner, reason, turn/city/network stats | Restart match | New game is the only secondary recovery action |
| Selected unit | Identity, role, movement, strength, upkeep | One contextual action when legal | `i` expands description and cargo detail |

## Acceptance

- 575x1280 and 720x1280 captures exist for every surface.
- No surface uses default Godot chrome, a multi-button action wall, or nested navigation.
- Content remains reachable by scrolling and Back priority remains unchanged.
- Existing smoke, core-loop, tech, city, world-art, and headless checks remain green.
