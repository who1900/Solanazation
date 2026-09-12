# Solanazation — Music & SFX Prompts

## Ambient / Music (Suno, Udio)
Generate with: **Dark industrial ambient, post-apocalyptic synthesizer, steam engine rhythmic pulses, distant mechanical hum, ominous, slow tempo, looping game soundtrack**

Save as `res://assets/audio/ambient.ogg` (loop). AudioManager picks it up automatically if present.

### Variants (optional)
- **Menu theme** (slower, more space): "Desolate synth pad, echoing server room hum, sparse piano, slow, 70 BPM, looping"
- **Combat / war** (tension): "Industrial war drums, distorted synth bass, metallic percussion, urgent, 120 BPM, looping"
- **Victory** (rise): "Triumphant synth choir, rising arpeggio, warm pad, epic, 90 BPM"
- **Discovery (terminal)** (curiosity): "Glitchy chiptune arpeggio, mysterious, retro-future, 100 BPM"

## SFX (already procedural in code — AudioManager.gd)
| Event | Sound | Method |
|---|---|---|
| Unit move | Steam hiss | `_hiss()` |
| End Turn | Heavy relay click | `_relay()` |
| $SOL gained | Cashier ping | `_ping()` |
| Building done | Low thunk | `_thunk()` |
| Combat | Noise burst | `_bang()` |

## Export note
Godot imports `.ogg`/`.wav` from `res://assets/audio/` automatically; no extra config needed.
