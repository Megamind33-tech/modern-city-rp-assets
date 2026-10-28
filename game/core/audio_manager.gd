extends Node
## Autoload "Audio": procedurally synthesised placeholder sounds (no third-party audio yet).
## One-shots use a small player pool; loops (siren, saw, engine) are long-lived players
## whose pitch/volume gameplay modulates.

const RATE := 22050

var streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _loops: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 7
	streams["alert"] = _wav(_alert())
	streams["chime"] = _wav(_chime())
	streams["thud"] = _wav(_thud())
	streams["click"] = _wav(_tone(1200.0, 0.04, 0.25))
	streams["stall"] = _wav(_sweep(220.0, 90.0, 0.35, 0.4))
	streams["radio"] = _wav(_radio())
	streams["cone"] = _wav(_tone(520.0, 0.08, 0.3))
	streams["siren"] = _wav(_siren(), true)
	streams["saw"] = _wav(_saw(), true)
	streams["engine"] = _wav(_engine(), true)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)


func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not streams.has(sound):
		return
	for p in _pool:
		if not p.playing:
			p.stream = streams[sound]
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return


func loop_start(sound: String, volume_db: float = 0.0) -> void:
	var p: AudioStreamPlayer = _loops.get(sound)
	if p == null:
		p = AudioStreamPlayer.new()
		p.stream = streams[sound]
		add_child(p)
		_loops[sound] = p
	p.volume_db = volume_db
	if not p.playing:
		p.play()


func loop_set(sound: String, pitch: float, volume_db: float) -> void:
	var p: AudioStreamPlayer = _loops.get(sound)
	if p:
		p.pitch_scale = clampf(pitch, 0.3, 3.0)
		p.volume_db = volume_db


func loop_stop(sound: String) -> void:
	var p: AudioStreamPlayer = _loops.get(sound)
	if p:
		p.stop()


func set_master_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(linear, 0.0001, 1.0)))


# --- Synthesis ---------------------------------------------------------------

func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples.size()
	return s


func _env(i: int, n: int, attack: float = 0.01, release: float = 0.1) -> float:
	var t := float(i) / RATE
	var total := float(n) / RATE
	return minf(1.0, t / attack) * minf(1.0, (total - t) / release)


func _tone(freq: float, dur: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = sin(TAU * freq * i / RATE) * amp * _env(i, n, 0.005, dur * 0.5)
	return out


func _sweep(f0: float, f1: float, dur: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		phase += TAU * lerpf(f0, f1, float(i) / n) / RATE
		out[i] = sin(phase) * amp * _env(i, n, 0.01, 0.1)
	return out


## Two-tone station alert: warm rather than shrill, short so it doesn't grate.
func _alert() -> PackedFloat32Array:
	var n := int(1.2 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 784.0 if int(t / 0.2) % 2 == 0 else 587.0
		phase += TAU * f / RATE
		out[i] = (sin(phase) + 0.3 * sin(phase * 2.0)) * 0.3 * _env(i, n, 0.01, 0.15)
	return out


func _chime() -> PackedFloat32Array:
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var n := int(1.0 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for k in notes.size():
		var start := int(k * 0.11 * RATE)
		for i in range(start, n):
			var t := float(i - start) / RATE
			out[i] += sin(TAU * notes[k] * t) * 0.18 * exp(-t * 4.0)
	return out


func _thud() -> PackedFloat32Array:
	var n := int(0.35 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.08)
		out[i] = (lp * 1.5 + sin(TAU * 70.0 * t) * 0.6) * exp(-t * 14.0) * 0.6
	return out


func _radio() -> PackedFloat32Array:
	var n := int(0.5 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var hiss := _rng.randf_range(-1.0, 1.0) * 0.12 * (1.0 if t < 0.25 else 0.0)
		var beep := sin(TAU * 1400.0 * t) * 0.2 * (1.0 if t > 0.3 and t < 0.42 else 0.0)
		out[i] = hiss + beep
	return out


## 1.6 s wail, an exact number of cycles of its LFO so it loops cleanly.
func _siren() -> PackedFloat32Array:
	var n := int(1.6 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var lfo := 0.5 - 0.5 * cos(TAU * float(i) / n)
		phase += TAU * lerpf(620.0, 1050.0, lfo) / RATE
		out[i] = (sin(phase) + 0.25 * sin(phase * 3.0)) * 0.22
	return out


func _saw() -> PackedFloat32Array:
	var freq := 105.0
	var n := int(round(RATE / freq)) * 60
	var out := PackedFloat32Array()
	out.resize(n)
	var period := RATE / freq
	for i in n:
		var ramp := fmod(float(i), period) / period * 2.0 - 1.0
		out[i] = (ramp * 0.25 + _rng.randf_range(-1.0, 1.0) * 0.08)
	return out


func _engine() -> PackedFloat32Array:
	var freq := 48.0
	var n := int(round(RATE / freq)) * 40
	var out := PackedFloat32Array()
	out.resize(n)
	var period := RATE / freq
	var lp := 0.0
	for i in n:
		var ramp := fmod(float(i), period) / period * 2.0 - 1.0
		lp = lerpf(lp, ramp, 0.2)
		out[i] = lp * 0.35 + _rng.randf_range(-1.0, 1.0) * 0.03
	return out
