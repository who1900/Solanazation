extends Node
## AudioManager — procedural SFX (no external files needed).
## move: steam hiss; end_turn: heavy relay click; sol: cashier ping.
## Music placeholder: drop .ogg into res://assets/audio/ and set music_path.

const RATE := 22050

var _player: AudioStreamPlayer
var _music: AudioStreamPlayer
var _sfx: Dictionary = {}
var music_path := "res://assets/audio/ambient.ogg"  # optional external music


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_music = AudioStreamPlayer.new()
	add_child(_music)
	_sfx["move"] = _hiss()
	_sfx["end_turn"] = _relay()
	_sfx["sol"] = _ping()
	_sfx["build"] = _thunk()
	_sfx["combat"] = _bang()


func play(sfx_name: String) -> void:
	if _sfx.has(sfx_name):
		_player.stream = _sfx[sfx_name]
		_player.play()


## Start ambient music if the file exists (placeholder for Suno/Udio export).
func start_music() -> void:
	if ResourceLoader.exists(music_path):
		_music.stream = load(music_path)
		_music.volume_db = -12.0
		_music.play()


## White noise with exponential decay (steam hiss).
func _hiss() -> AudioStreamWAV:
	var dur := 0.45
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in n:
		var t := float(i) / n
		var v := (rng.randf() * 2.0 - 1.0) * pow(1.0 - t, 2.0) * 0.5
		data.encode_s16(i * 2, int(v * 32767))
	return _wav(data, dur)


## Heavy relay click: short low-frequency thump + click.
func _relay() -> AudioStreamWAV:
	var dur := 0.12
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / n
		var v := sin(2.0 * PI * 220.0 * t) * exp(-t * 22.0) * 0.7
		if i < n / 4:
			v += (sin(2.0 * PI * 880.0 * t)) * exp(-t * 60.0) * 0.4
		data.encode_s16(i * 2, int(v * 32767))
	return _wav(data, dur)


## Cashier ping: rising sine blip.
func _ping() -> AudioStreamWAV:
	var dur := 0.3
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / n
		var freq := 880.0 + 660.0 * t
		var v := sin(2.0 * PI * freq * t) * exp(-t * 9.0) * 0.5
		data.encode_s16(i * 2, int(v * 32767))
	return _wav(data, dur)


## Build thunk: low square-ish knock.
func _thunk() -> AudioStreamWAV:
	var dur := 0.18
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / n
		var v := sin(2.0 * PI * 110.0 * t) * exp(-t * 14.0) * 0.8
		data.encode_s16(i * 2, int(v * 32767))
	return _wav(data, dur)


## Combat bang: noise burst.
func _bang() -> AudioStreamWAV:
	var dur := 0.2
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / n
		var v := (rng.randf() * 2.0 - 1.0) * exp(-t * 12.0) * 0.8
		data.encode_s16(i * 2, int(v * 32767))
	return _wav(data, dur)


func _wav(data: PackedByteArray, dur: float) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
