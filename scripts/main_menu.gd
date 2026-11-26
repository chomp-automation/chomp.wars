extends Control
## Start screen. Two live previews of the mascot turn slowly and chomp, one for Chomp and
## one for Mrs. Chomp. Pick a player, then start, or quit. The layout is built in code.

const ChompModel := preload("res://scripts/chomp_model.gd")
const CARD_SIZE := Vector2(420, 500)
const PREVIEW_SIZE := Vector2i(400, 340)
const TURN_SPEED := 0.45  # radians per second
const CHOMP_RATE := 2.4  # mouth open/close cycles per second
const IDLE_BORDER := Color(0.30, 0.28, 0.42)

const LOGO_PATH := "res://assets/images/chomp_logo.png.bin"
const STARFIELD_SHADER := preload("res://shaders/starfield.gdshader")

var _cards := {}  # character id -> card data (panel, button, pivot, model, color, phase)
var _status_label: Label
var _start_button: Button
var _music_button: Button
var _difficulty_button: Button
var _time := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	Game.play_music()
	_build_background()
	_build_layout()
	_select(Game.selected_character)
	# Focus a button so a controller (D-pad or left stick, then A) or the keyboard
	# (arrows, then Enter) can drive the menu without a mouse.
	_start_button.grab_focus()


func _process(delta: float) -> void:
	_time += delta
	for id in _cards:
		var card: Dictionary = _cards[id]
		(card.pivot as Node3D).rotate_y(delta * TURN_SPEED)
		var wave := 0.5 + 0.5 * sin(_time * TAU * CHOMP_RATE + card.phase)
		(card.model as Node3D).call("set_mouth_open", smoothstep(0.2, 0.8, wave))


## A black night sky with stars and galaxies (see shaders/starfield.gdshader).
func _build_background() -> void:
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.material = ShaderMaterial.new()
	(background.material as ShaderMaterial).shader = STARFIELD_SHADER
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)


func _build_layout() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	add_child(column)

	column.add_child(_build_header())
	column.add_child(_label("Stranded on the moon. Find the 10 issues. Shoot the drones and the evil chompbots.", 22,
			Color(0.85, 0.82, 0.95)))

	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 48)
	column.add_child(cards)
	for id in ["chomp", "mrs_chomp"]:
		cards.add_child(_build_card(id))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	column.add_child(buttons)
	var start := _button("Start", Vector2(300, 64), Color(0.2, 0.95, 1.0))
	start.pressed.connect(_on_start_pressed)
	start.name = "Start"
	_start_button = start
	buttons.add_child(start)
	_music_button = _button("", Vector2(300, 64), Color(1.0, 0.36, 0.72))
	_music_button.pressed.connect(_on_music_pressed)
	_music_button.name = "Music"
	buttons.add_child(_music_button)
	_update_music_button()
	_difficulty_button = _button("", Vector2(230, 64), IDLE_BORDER)
	_difficulty_button.name = "Difficulty"
	_difficulty_button.pressed.connect(_on_difficulty_pressed)
	buttons.add_child(_difficulty_button)
	_update_difficulty_button()
	var quit := _button("Quit", Vector2(200, 64), IDLE_BORDER)
	quit.pressed.connect(get_tree().quit)
	buttons.add_child(quit)

	_status_label = _label("", 22, Color.WHITE)
	column.add_child(_status_label)
	column.add_child(_label("W / S move  |  A / D turn  |  Hold Space charge, release fire  |  Up/Down aim  |  Shift jump  |  Ctrl sprint  |  Right-drag look  |  E read sign  |  Esc pause",
			18, Color(0.7, 0.68, 0.82)))
	column.add_child(_label("Controller: left stick move/strafe  |  right stick aim/turn  |  L2 lock aim  |  R2 5x zoom  |  R1 / RB fire  |  right button jump  |  bottom button sprint/read sign  |  left button view  |  Start pause",
			18, Color(0.7, 0.68, 0.82)))


func _build_card(id: String) -> PanelContainer:
	var color: Color = Game.laser_color(id)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = CARD_SIZE
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var preview := SubViewportContainer.new()
	preview.stretch = true
	preview.custom_minimum_size = PREVIEW_SIZE
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(preview)
	var viewport := SubViewport.new()
	viewport.size = PREVIEW_SIZE
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	preview.add_child(viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.58, 0.85)
	environment.ambient_light_energy = 0.9
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.6
	viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 30.0
	camera.position = Vector3(0, 0.3, 4.4)
	viewport.add_child(camera)

	var pivot := Node3D.new()
	viewport.add_child(pivot)
	var model: Node3D = ChompModel.new()
	model.character_id = id
	if id == "mrs_chomp":
		model.scale = Vector3(0.92, 1.0, 0.92)  # slimmer, as in the game
	pivot.add_child(model)

	column.add_child(_label(Game.CHARACTERS[id], 32, Color.WHITE))
	column.add_child(_label("Cyan lasers" if id == "chomp" else "Pink lasers", 18, color))
	var button := _button("Select", Vector2(200, 44), color)
	button.pressed.connect(_select.bind(id))
	column.add_child(button)

	_cards[id] = {"panel": panel, "button": button, "pivot": pivot, "model": model,
			"color": color, "phase": 0.0 if id == "chomp" else PI}
	return panel


func _select(character_id: String) -> void:
	Game.selected_character = character_id
	for id in _cards:
		var card: Dictionary = _cards[id]
		var selected: bool = id == character_id
		var border: Color = card.color if selected else IDLE_BORDER
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.06, 0.16, 0.92)
		style.set_border_width_all(4 if selected else 2)
		style.border_color = border
		style.set_corner_radius_all(20)
		style.set_content_margin_all(14)
		(card.panel as PanelContainer).add_theme_stylebox_override("panel", style)
		(card.button as Button).text = "Selected" if selected else "Select"
	_status_label.text = "Selected: " + Game.CHARACTERS[character_id]


## The real Chomp logo, beside the game title, with "Written by Chomp" underneath.
func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 20)
	var logo := TextureRect.new()
	logo.texture = _load_logo()
	logo.custom_minimum_size = Vector2(112, 112)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(logo)
	var titles := VBoxContainer.new()
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	titles.add_child(_label("chomp.wars", 84, Color.WHITE, true))
	titles.add_child(_label("Written by Chomp", 22, Color(0.75, 0.72, 0.88)))
	return header


func _load_logo() -> Texture2D:
	var image := Image.new()
	var error := image.load_png_from_buffer(FileAccess.get_file_as_bytes(LOGO_PATH))
	if error != OK:
		push_warning("Chomp logo could not be loaded: " + LOGO_PATH)
		return null
	return ImageTexture.create_from_image(image)


func _on_start_pressed() -> void:
	Game.reset_run()
	get_tree().change_scene_to_file("res://scenes/MainGame.tscn")


func _on_music_pressed() -> void:
	Game.cycle_music()
	_update_music_button()


func _update_music_button() -> void:
	_music_button.text = "Music: " + Game.music_name()


func _on_difficulty_pressed() -> void:
	Game.selected_difficulty = (Game.selected_difficulty + 1) % Game.DIFFICULTIES.size()
	_update_difficulty_button()


func _update_difficulty_button() -> void:
	_difficulty_button.text = "Difficulty: " + Game.DIFFICULTIES[Game.selected_difficulty]


func _label(text: String, size: int, color: Color, semibold := false) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if semibold and Game.font_semibold != null:
		label.add_theme_font_override("font", Game.font_semibold)
	return label


func _button(text: String, minimum: Vector2, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum
	button.add_theme_font_size_override("font_size", 22)
	if Game.font_semibold != null:
		button.add_theme_font_override("font", Game.font_semibold)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.10, 0.22)
	normal.set_border_width_all(2)
	normal.border_color = accent
	normal.set_corner_radius_all(14)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = accent.darkened(0.55)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.draw_center = false
	focus.set_border_width_all(4)
	focus.border_color = Color.WHITE
	button.add_theme_stylebox_override("focus", focus)
	return button
