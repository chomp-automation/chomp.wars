extends Node
## Global run state (chosen player, orbs collected, score), input bindings, music and sound effects.

const TOTAL_ORBS := 10
const CHARACTERS := {"chomp": "Chomp", "mrs_chomp": "Mrs. Chomp"}
const CYAN := Color(0.2, 0.95, 1.0)
const PINK := Color(1.0, 0.36, 0.72)
const POINTS_PER_ENEMY := 100
## Enemy laser hits the player can take before the run ends. Each hit takes a third of the energy bar.
const MAX_LASER_HITS := 3
## Audio is loaded from the WAV files at run time, not through Godot's import cache,
## so the game runs straight from a fresh clone without an editor import step.
## The background music tracks the start screen cycles through, in order. Starlight is the
## default (index 0).
const MUSIC_TRACKS := [
	{"name": "Starlight", "path": "res://assets/audio/starlight.wav.bin"},
	{"name": "Extra Terrestrial", "path": "res://assets/audio/extra_terrestrial.wav.bin"},
	{"name": "Hard Rock", "path": "res://assets/audio/hard_rock.wav.bin"},
]
const SOUND_PATHS := {
	"collect": "res://assets/audio/collect.wav.bin",
	"jump": "res://assets/audio/jump.wav.bin",
	"laser": "res://assets/audio/laser.wav.bin",
	"explosion": "res://assets/audio/explosion.wav.bin",
	"chomp": "res://assets/audio/chomp.wav.bin",
}
## Inter, the interface font (SIL Open Font License, see assets/fonts/Inter-LICENSE.txt).
## Stored as .bin so Godot does not import it, the same as the audio.
const FONT_REGULAR_PATH := "res://assets/fonts/Inter-Regular.ttf.bin"
const FONT_SEMIBOLD_PATH := "res://assets/fonts/Inter-SemiBold.ttf.bin"

var _sounds := {}
var _music_streams: Array[AudioStreamWAV] = []
var font_regular: FontFile
var font_semibold: FontFile

var selected_character := "chomp"
var selected_music := 0
var orbs_collected := 0
var enemies_destroyed := 0
var score := 0
var laser_hits := 0
var _music_player: AudioStreamPlayer


func _ready() -> void:
	_setup_input_map()
	_load_fonts()
	for sound_name in SOUND_PATHS:
		_sounds[sound_name] = _load_wav(SOUND_PATHS[sound_name], false)
	_sounds["portal_error"] = _make_cue(180.0, 65.0)
	_sounds["boss_attack"] = _make_cue(90.0, 650.0)
	_sounds["boss_hit"] = _make_alien_yell()
	for track in MUSIC_TRACKS:
		_music_streams.append(_load_wav(track.path, true))
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = _music_streams[selected_music]
	_music_player.volume_db = -10.0
	add_child(_music_player)


func _load_fonts() -> void:
	font_regular = _load_font(FONT_REGULAR_PATH)
	font_semibold = _load_font(FONT_SEMIBOLD_PATH)
	if font_regular != null:
		# Every control without its own font uses Inter (Godot's built-in font otherwise).
		ThemeDB.fallback_font = font_regular


func _load_font(path: String) -> FontFile:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_warning("Font not found: " + path)
		return null
	var font := FontFile.new()
	font.data = bytes
	return font


func reset_run() -> void:
	orbs_collected = 0
	enemies_destroyed = 0
	score = 0
	laser_hits = 0


## Energy left as a fraction from 1.0 (full) down to 0.0 (empty).
func energy_fraction() -> float:
	return 1.0 - float(laser_hits) / MAX_LASER_HITS


## Records one enemy laser hit on the player. Returns true if this hit uses up all the energy.
func take_laser_hit() -> bool:
	laser_hits = mini(laser_hits + 1, MAX_LASER_HITS)
	return laser_hits >= MAX_LASER_HITS


## Collecting an issue counts it and restores the energy bar to full.
func collect_orb() -> void:
	orbs_collected = mini(orbs_collected + 1, TOTAL_ORBS)
	laser_hits = 0


func destroy_enemy() -> void:
	enemies_destroyed += 1
	score += POINTS_PER_ENEMY


## Chomp fires cyan lasers and Mrs. Chomp fires pink ones.
func laser_color(character_id: String) -> Color:
	return PINK if character_id == "mrs_chomp" else CYAN


func all_orbs_collected() -> bool:
	return orbs_collected >= TOTAL_ORBS


func play_music() -> void:
	if not _music_player.playing:
		_music_player.play()


## Speeds the background music up (above 1.0) or back to normal (1.0). Used to build tension
## when an evil chompbot is close. The player changes tempo and pitch together.
func set_music_speed(scale: float) -> void:
	_music_player.pitch_scale = scale


## Switches to a track by index (wrapping around). If music is playing, the new track starts at once.
func set_music(index: int) -> void:
	selected_music = posmod(index, MUSIC_TRACKS.size())
	# Setting a new stream stops the player, so remember whether it was playing first.
	var was_playing := _music_player.playing
	_music_player.stream = _music_streams[selected_music]
	if was_playing:
		_music_player.play()


func play_boss_music() -> void:
	_music_player.stream = _music_streams[2]  # Hard Rock, without changing the menu selection.
	_music_player.play()


func restore_music() -> void:
	_music_player.stream = _music_streams[selected_music]
	_music_player.play()


## Original synthesized cues; no external audio assets or import step.
func _make_cue(start_hz: float, end_hz: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	var samples := 11025
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / 22050.0
		var fraction := float(i) / samples
		var phase := TAU * (start_hz * t + (end_hz - start_hz) * t * fraction * 0.5)
		var sample := sin(phase) * (1.0 - fraction) * 14000.0
		data.encode_s16(i * 2, int(sample))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = data
	return stream


func cycle_music() -> void:
	set_music(selected_music + 1)


func music_name() -> String:
	return MUSIC_TRACKS[selected_music].name


func play_sfx(sound_name: String) -> void:
	var stream: AudioStream = _sounds.get(sound_name)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Reads a 16-bit PCM WAV file straight into an AudioStreamWAV. Godot 4.3 has no runtime
## WAV loader, so the RIFF header is parsed here.
func _load_wav(path: String, loop: bool) -> AudioStreamWAV:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		push_warning("Not a WAV file: " + path)
		return null
	var channels := 1
	var sample_rate := 44100
	var bits := 16
	var pos := 12
	while pos + 8 <= bytes.size():
		var chunk_id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var chunk_size := bytes.decode_u32(pos + 4)
		var body := pos + 8
		if chunk_id == "fmt ":
			channels = bytes.decode_u16(body + 2)
			sample_rate = bytes.decode_u32(body + 4)
			bits = bytes.decode_u16(body + 14)
		elif chunk_id == "data":
			if bits != 16:
				push_warning("Only 16-bit WAV files are supported: " + path)
				return null
			var stream := AudioStreamWAV.new()
			stream.format = AudioStreamWAV.FORMAT_16_BITS
			stream.mix_rate = sample_rate
			stream.stereo = channels == 2
			stream.data = bytes.slice(body, mini(body + chunk_size, bytes.size()))
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
			stream.loop_begin = 0
			stream.loop_end = stream.data.size() / (2 * channels)
			return stream
		pos = body + chunk_size + (chunk_size & 1)
	push_warning("No audio data in: " + path)
	return null


## Keyboard keys come first in each action, so the first event is always the key.
## Godot names controller face buttons by position, whatever is printed on them:
## JOY_BUTTON_A is the bottom one, B the right, X the left and Y the top.
const KEY_BINDINGS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"fire": KEY_SPACE,
	"aim_up": KEY_UP,
	"aim_down": KEY_DOWN,
	"jump": KEY_SHIFT,
	"interact": KEY_E,
	"toggle_view": KEY_V,
	"pause": KEY_ESCAPE,
}
const JOY_BUTTON_BINDINGS := {
	"move_forward": [JOY_BUTTON_DPAD_UP],
	"move_back": [JOY_BUTTON_DPAD_DOWN],
	"move_left": [JOY_BUTTON_DPAD_LEFT],
	"move_right": [JOY_BUTTON_DPAD_RIGHT],
	"fire": [JOY_BUTTON_RIGHT_SHOULDER],  # R1 / RB
	"jump": [JOY_BUTTON_B],  # right
	"interact": [JOY_BUTTON_A],  # bottom
	"toggle_view": [JOY_BUTTON_X],  # left
	"pause": [JOY_BUTTON_START],
	# Godot 4.3's built-in ui_accept has no controller button. The D-pad and left stick
	# already move between menu buttons; the bottom button presses the focused one.
	"ui_accept": [JOY_BUTTON_A],
}
## [axis, direction]. Sticks use -1 for left/up and +1 for right/down; triggers use +1.
const JOY_AXIS_BINDINGS := {
	"stick_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"stick_back": [JOY_AXIS_LEFT_Y, 1.0],
	"stick_left": [JOY_AXIS_LEFT_X, -1.0],
	"stick_right": [JOY_AXIS_LEFT_X, 1.0],
	"look_left": [JOY_AXIS_RIGHT_X, -1.0],
	"look_right": [JOY_AXIS_RIGHT_X, 1.0],
	"look_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	"aim_lock": [JOY_AXIS_TRIGGER_LEFT, 1.0],
	"sniper": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
}
const STICK_DEADZONE := 0.2


func _setup_input_map() -> void:
	for action in KEY_BINDINGS:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_BINDINGS[action]
		_bind(action, key)
	for action in JOY_BUTTON_BINDINGS:
		for button_index in JOY_BUTTON_BINDINGS[action]:
			var button := InputEventJoypadButton.new()
			button.button_index = button_index
			_bind(action, button)
	for action in JOY_AXIS_BINDINGS:
		var motion := InputEventJoypadMotion.new()
		motion.axis = JOY_AXIS_BINDINGS[action][0]
		motion.axis_value = JOY_AXIS_BINDINGS[action][1]
		_bind(action, motion)


## Adds an event to an action (creating the action if needed). Events apply to any
## connected controller.
func _bind(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, STICK_DEADZONE)
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		event.device = -1
	InputMap.action_add_event(action, event)


## An original raspy, pitch-bending alien cry, synthesized without voice samples.
func _make_alien_yell() -> AudioStreamWAV:
	var data := PackedByteArray()
	var samples := 15435
	data.resize(samples * 2)
	var phase := 0.0
	for i in samples:
		var t := float(i) / 22050.0
		var fraction := float(i) / samples
		var pitch := 160.0 + 380.0 * sin(PI * fraction) + 35.0 * sin(TAU * 29.0 * t)
		phase += TAU * pitch / 22050.0
		var voice := sin(phase) + 0.45 * sin(phase * 2.0) + 0.25 * sin(phase * 3.0)
		var envelope := minf(t * 30.0, 1.0) * pow(1.0 - fraction, 0.6)
		data.encode_s16(i * 2, int(voice * envelope * 10000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = data
	return stream
