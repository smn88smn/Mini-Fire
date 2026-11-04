extends Node
## Procedurally generated sound effects (no audio files needed).
## Replace with real .ogg/.wav files later by assigning to `sounds[name]`.

const MIX_RATE := 22050
const POOL_SIZE := 16

var sounds: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	randomize()
	sounds["pistol"] = _make_shot(0.16, 900.0, 0.55, 18.0)
	sounds["smg"] = _make_shot(0.09, 1200.0, 0.45, 30.0)
	sounds["rifle"] = _make_shot(0.14, 700.0, 0.6, 20.0)
	sounds["shotgun"] = _make_shot(0.3, 350.0, 0.8, 9.0)
	sounds["sniper"] = _make_shot(0.45, 260.0, 0.9, 6.0)
	sounds["rocket"] = _make_whoosh(0.5)
	sounds["explosion"] = _make_shot(0.8, 120.0, 1.0, 4.0)
	sounds["hit"] = _make_tone(0.07, 1400.0, 0.35)
	sounds["death"] = _make_sweep(0.45, 500.0, 90.0, 0.5)
	sounds["reload"] = _make_click()
	sounds["jet"] = _make_noise_loop(0.25, 0.12)
	sounds["ui"] = _make_tone(0.05, 880.0, 0.25)
	sounds["buy"] = _make_sweep(0.25, 600.0, 1400.0, 0.35)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)


## volume: 0..1 (multiplied by profile volume). pitch_var: random pitch variation.
func play(sound_name: String, volume: float = 1.0, pitch_var: float = 0.08) -> void:
	if not sounds.has(sound_name):
		return
	var v := volume * Profile.sfx_volume
	if v <= 0.01:
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = sounds[sound_name]
	p.volume_db = linear_to_db(v)
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


## Plays a sound attenuated by distance from the listener (local camera).
func play_at(sound_name: String, pos: Vector2, listener: Vector2, volume: float = 1.0) -> void:
	var d := pos.distance_to(listener)
	var att := clampf(1.0 - d / 1800.0, 0.0, 1.0)
	if att > 0.02:
		play(sound_name, volume * att)


# ---------------------------------------------------------------- generators
func _to_stream(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var s := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _make_shot(dur: float, tone_hz: float, amp: float, decay: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-t * decay)
		var noise := randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.35)
		var body := sin(TAU * tone_hz * t * (1.0 - t * 0.8)) * exp(-t * decay * 1.5)
		out[i] = (lp * 0.75 + body * 0.45) * env * amp
	return _to_stream(out)


func _make_tone(dur: float, hz: float, amp: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		out[i] = sin(TAU * hz * t) * (1.0 - t / dur) * amp
	return _to_stream(out)


func _make_sweep(dur: float, from_hz: float, to_hz: float, amp: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += TAU * lerpf(from_hz, to_hz, t) / MIX_RATE
		out[i] = (1.0 if sin(phase) > 0.0 else -1.0) * (1.0 - t) * amp * 0.5
	return _to_stream(out)


func _make_click() -> AudioStreamWAV:
	var n := int(0.18 * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var a := exp(-t * 90.0) + exp(-maxf(t - 0.1, 0.0) * 90.0) * (1.0 if t > 0.1 else 0.0)
		out[i] = randf_range(-1.0, 1.0) * a * 0.5
	return _to_stream(out)


func _make_whoosh(dur: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.08 + t * 0.2)
		out[i] = lp * sin(PI * t) * 1.6
	return _to_stream(out)


func _make_noise_loop(dur: float, amp: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.2)
		out[i] = lp * amp
	return _to_stream(out, true)
