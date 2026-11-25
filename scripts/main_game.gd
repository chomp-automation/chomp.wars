extends Node3D
## Runs one playthrough: spawns the orbs, drones and evil chompbots, drives the HUD, the energy
## bar, the game timer, the pause and game-over menus, increases game speed after two minutes,
## handles water resets, enemy laser damage, falls, signposts and the exit portal.

const BOSS_SCRIPT := preload("res://scripts/alien_boss.gd")
const ORB_SCENE := preload("res://scenes/Orb.tscn")
const ENEMY_SCENE := preload("res://scenes/Enemy.tscn")
const EVIL_BOT_SCENE := preload("res://scenes/EvilChompbot.tscn")
const ENEMY_LASER_SCENE := preload("res://scenes/EnemyLaser.tscn")
const LASER_SCENE := preload("res://scenes/Laser.tscn")
const GAME_SCENE := "res://scenes/MainGame.tscn"
const MAIN_MENU_SCENE := "res://scenes/MainMenu.tscn"
const VICTORY_SCENE := "res://scenes/VictoryScreen.tscn"
const FALL_LIMIT := -15.0
const ESCALATION_TIME := 120.0
const ESCALATED_SPEED := 1.3

@onready var environment = $Environment
@onready var player = $Player
@onready var orbs_label: Label = $Hud/OrbsLabel
@onready var status_label: Label = $Hud/StatusLabel
@onready var score_label: Label = $Hud/ScoreLabel
@onready var time_label: Label = $Hud/TimeLabel
@onready var character_label: Label = $Hud/CharacterLabel
@onready var pause_button: Button = $Hud/PauseButton
@onready var pause_menu: Control = $Hud/PauseMenu
@onready var energy_bar: ProgressBar = $Hud/EnergyBar
@onready var game_over_menu: Control = $Hud/GameOverMenu
@onready var game_over_message: Label = $Hud/GameOverMenu/Center/Menu/Message

var _boss: Area3D
var _boss_spawned := false
var boss_health_bar: ProgressBar
var boss_health_label: Label
var _finished := false
var _game_over := false
var _status_time_left := 0.0
var _elapsed := 0.0  # seconds of play in this run (the timer pauses with the game)
var _game_speed := 1.0


func _ready() -> void:
	# The game tree is pausable, but this root keeps running so the pause menu works.
	process_mode = Node.PROCESS_MODE_ALWAYS
	environment.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	Game.reset_run()
	Game.restore_music()
	player.apply_character(Game.selected_character)
	player.respawn(environment.start_position)
	environment.water_entered.connect(_on_water_entered)
	environment.portal_entered.connect(_on_portal_entered)
	environment.trapped_chomps_released.connect(_on_trapped_chomps_released)
	environment.base_hit.connect(_on_moonbase_hit)
	player.fired.connect(_on_player_fired)
	$Hud/Minimap.player = player
	$Hud/Minimap.environment = environment
	_spawn_orbs()
	_spawn_enemies()
	_spawn_evil_bots()

	pause_button.pressed.connect(toggle_pause)
	$Hud/PauseMenu/Center/Menu/ResumeButton.pressed.connect(toggle_pause)
	$Hud/PauseMenu/Center/Menu/MenuButton.pressed.connect(_go_to_main_menu)
	$Hud/PauseMenu/Center/Menu/QuitButton.pressed.connect(get_tree().quit)
	pause_menu.visible = false
	$Hud/GameOverMenu/Center/Menu/TryAgainButton.pressed.connect(_try_again)
	$Hud/GameOverMenu/Center/Menu/GameOverMenuButton.pressed.connect(_go_to_main_menu)
	game_over_menu.visible = false

	character_label.text = "Playing as " + Game.CHARACTERS[Game.selected_character]
	boss_health_bar = ProgressBar.new()
	boss_health_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boss_health_bar.position = Vector2(-300, 24)
	boss_health_bar.size = Vector2(600, 36)
	boss_health_bar.show_percentage = false
	boss_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var boss_fill := StyleBoxFlat.new()
	boss_fill.bg_color = Color(0.65, 0.12, 0.22)
	boss_health_bar.add_theme_stylebox_override("fill", boss_fill)
	$Hud.add_child(boss_health_bar)
	boss_health_label = Label.new()
	boss_health_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	boss_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	boss_health_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_health_bar.add_child(boss_health_label)
	boss_health_bar.hide()
	charge_bar = ProgressBar.new()
	charge_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	charge_bar.position = Vector2(-300, -110)
	charge_bar.size = Vector2(600, 38)
	charge_bar.show_percentage = false
	charge_bar.step = 0.01  # Do not round an almost-full charge to 100%.
	charge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Hud.add_child(charge_bar)
	for quarter in range(1, 4):
		var divider := ColorRect.new()
		divider.position = Vector2(600 * quarter / 4.0 - 1, 0)
		divider.size = Vector2(2, 38)
		divider.color = Color.BLACK
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		charge_bar.add_child(divider)
	charge_label = Label.new()
	charge_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	charge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	charge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	charge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charge_bar.add_child(charge_label)
	_style_energy_bar()
	Game.set_music_speed(1.0)
	_update_hud()
	show_status("Find the 10 issues! Hold fire to charge; release to shoot. Up/Down aim. Shift jumps.", 4.0)


func _exit_tree() -> void:
	# The music is shared with the menus, so it goes back to normal speed when this run ends.
	Engine.time_scale = 1.0
	Game.restore_music()
	Game.set_music_speed(1.0)


var charge_bar: ProgressBar
var charge_label: Label


func _process(delta: float) -> void:
	if get_tree().paused or _finished:
		return
	var charge: float = player.charge_time / player.MAX_CHARGE_TIME
	charge_bar.value = charge * 100.0
	charge_label.text = "Adversarial agents: %d%% — %s" % [floori(charge * 100.0), attack_name(charge)]
	_elapsed += delta
	time_label.text = "Time %s" % _format_time(_elapsed)
	_update_escalation()
	if player.global_position.y < FALL_LIMIT:
		_reset_player("You fell off the moon. Back to the start.")
	if _status_time_left > 0.0:
		_status_time_left -= delta
		if _status_time_left <= 0.0:
			status_label.text = _default_status()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause", false):
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact", false):
		var text: String = environment.nearby_sign_text()
		if text != "":
			show_status(text, 6.0)
			get_viewport().set_input_as_handled()
		elif not _game_over and not _finished:
			# No sign to read: the bottom button makes the character turn round and chomp.
			player.chomp_greeting()
			get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	if _game_over:
		return
	player.cancel_charge()
	var paused := not get_tree().paused
	get_tree().paused = paused
	pause_menu.visible = paused
	if paused:
		# Lets a controller pick Resume, Main Menu or Quit with the D-pad and A.
		$Hud/PauseMenu/Center/Menu/ResumeButton.grab_focus()


func show_status(text: String, seconds: float) -> void:
	status_label.text = text
	_status_time_left = seconds


func _default_status() -> String:
	if Game.all_orbs_collected():
		return "Defeat the Alien Overlord to unlock the portal!" if is_instance_valid(_boss) else "All issues found! Reach the glowing portal."
	return "Exploring"


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%02d:%02d" % [total / 60, total % 60]


## After two minutes, speed up gameplay and music together.
func _update_escalation() -> void:
	var target := ESCALATED_SPEED if _elapsed >= ESCALATION_TIME else 1.0
	if is_equal_approx(_game_speed, target):
		return
	_game_speed = target
	Engine.time_scale = _game_speed
	Game.set_music_speed(_game_speed)
	if _game_speed > 1.0:
		show_status("Two minutes elapsed! The moon is moving faster!", 5.0)


func _spawn_orbs() -> void:
	for point in environment.get_orb_spawn_points():
		var orb: Node3D = ORB_SCENE.instantiate()
		orb.process_mode = Node.PROCESS_MODE_PAUSABLE
		orb.position = point
		orb.collected.connect(_on_orb_collected)
		add_child(orb)


func _spawn_enemies() -> void:
	var index := 0
	for point in environment.get_enemy_spawn_points():
		var enemy: Area3D = ENEMY_SCENE.instantiate()
		enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
		enemy.setup(point, index * 1.7)
		enemy.destroyed.connect(_on_enemy_destroyed)
		add_child(enemy)
		index += 1


func _spawn_evil_bots() -> void:
	var index := 0
	for point in environment.get_evil_bot_spawn_points():
		var bot: Area3D = EVIL_BOT_SCENE.instantiate()
		bot.process_mode = Node.PROCESS_MODE_PAUSABLE
		bot.setup(point, environment, 100 + index * 37)
		bot.destroyed.connect(_on_enemy_destroyed)
		bot.fired.connect(_on_bot_fired)
		add_child(bot)
		index += 1


const RAIN_RADIUS := 18.0  # Twice the previous ten-Chomp radius.
const CIRCLE_RANGE := 13.5  # Fifteen player collision diameters (0.9 m each).


func attack_name(charge: float) -> String:
	if charge >= 1.0:
		return "Laser rain"
	if charge >= 0.75:
		return "Laser circle"
	if charge >= 0.5:
		return "Multiple lasers"
	if charge >= 0.25:
		return "Big laser beam"
	return "Single laser"


func _on_player_fired(origin: Vector3, direction: Vector3, character_id: String, charge: float = 0.0) -> void:
	var color := Game.laser_color(character_id)
	if charge >= 1.0:
		# Evenly spread downward beams in a disk, within twenty Chomps.
		for i in 48:
			var radius := RAIN_RADIUS * sqrt(float(i) / 47.0)
			var angle := float(i) * 2.399963
			var rain_origin: Vector3 = player.global_position + Vector3(cos(angle) * radius, 12, sin(angle) * radius)
			_spawn_laser(rain_origin, Vector3.DOWN, color, 0.25)
	elif charge >= 0.75:
		for i in 24:
			var radial := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 24.0)
			_spawn_laser(player.global_position + Vector3.UP + radial * 0.8, radial, color, 0.25, CIRCLE_RANGE - 0.8)
	elif charge >= 0.5:
		for i in range(-2, 3):
			_spawn_laser(origin, direction.rotated(Vector3.UP, i * 0.12), color, 0.25)
	else:
		_spawn_laser(origin, direction, color, 0.65 if charge >= 0.25 else 0.0)
	Game.play_sfx("laser")


func _spawn_laser(origin: Vector3, direction: Vector3, color: Color, charge: float, distance: float = 72.0) -> void:
	var laser: Area3D = LASER_SCENE.instantiate()
	laser.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(laser)
	laser.max_distance = distance
	laser.launch(origin, direction, color, charge)


func _on_bot_fired(origin: Vector3, direction: Vector3) -> void:
	var laser: Area3D = ENEMY_LASER_SCENE.instantiate()
	laser.process_mode = Node.PROCESS_MODE_PAUSABLE
	laser.player_hit.connect(_on_enemy_laser_hit)
	add_child(laser)
	laser.launch(origin, direction)


## An evil chompbot's red laser costs a third of the energy. When the energy runs out, the run is over.
func _on_enemy_laser_hit() -> void:
	if _finished or _game_over:
		return
	if Game.take_laser_hit():
		_show_game_over()
	else:
		show_status("Hit by a red laser! Energy at %d%%." % roundi(Game.energy_fraction() * 100.0), 3.0)
	_update_hud()


func _show_game_over() -> void:
	_game_over = true
	pause_menu.visible = false
	game_over_message.text = "%s ran out of energy. Try again?" % Game.CHARACTERS[Game.selected_character]
	game_over_menu.visible = true
	get_tree().paused = true
	$Hud/GameOverMenu/Center/Menu/TryAgainButton.grab_focus()


func _on_enemy_destroyed(enemy: Node3D) -> void:
	enemy.remove_from_group("enemy")
	if enemy == _boss:
		_boss = null
		boss_health_bar.hide()
		environment.set_portal_active(true)
		Game.restore_music()
		show_status("Alien defeated! The exit portal is open.", 5.0)
	Game.destroy_enemy()
	Game.play_sfx("explosion")
	_update_hud()
	if enemy.enemy_name != "Alien Overlord":
		show_status("%s destroyed! +%d points" % [enemy.enemy_name, Game.POINTS_PER_ENEMY], 2.0)


func _on_trapped_chomps_released() -> void:
	show_status("The moonbase opens! Ten tiny Chomps escape!", 5.0)


func _on_moonbase_hit() -> void:
	show_status("Moonbase hit: %d / 10" % environment.moonbase_hits(), 2.0)


func _on_orb_collected(_orb: Node3D) -> void:
	Game.collect_orb()
	Game.play_sfx("collect")
	_update_hud()
	if Game.all_orbs_collected():
		if not _boss_spawned:
			_boss_spawned = true
			_boss = BOSS_SCRIPT.new()
			_boss.process_mode = Node.PROCESS_MODE_PAUSABLE
			var point: Vector2 = environment.PORTAL_POSITION
			_boss.position = Vector3(point.x, environment.get_height_at(point.x, point.y), point.y)
			_boss.destroyed.connect(_on_enemy_destroyed)
			_boss.fired.connect(_on_bot_fired)
			_boss.health_changed.connect(_on_boss_health_changed)
			add_child(_boss)
			_on_boss_health_changed(_boss.health, _boss.MAX_HEALTH)
			Game.play_boss_music()
			show_status("The Alien Overlord emerges! Defeat it to unlock the portal.", 5.0)
	else:
		show_status("Issue collected! %d to go." % (Game.TOTAL_ORBS - Game.orbs_collected), 2.0)


func _on_water_entered(body: Node3D) -> void:
	if body == player and not _game_over:
		_reset_player("Splash! Back to the start.")


func _on_portal_entered(body: Node3D) -> void:
	if body != player or _finished or _game_over or not Game.all_orbs_collected():
		return
	if is_instance_valid(_boss):
		Game.play_sfx("portal_error")
		var portal: Vector2 = environment.PORTAL_POSITION
		var away: Vector2 = Vector2(player.global_position.x, player.global_position.z) - portal
		if away.length_squared() < 0.01:
			away = Vector2(0, 1)
		var landing := portal + away.normalized() * 4.0
		player.respawn(Vector3(landing.x, environment.get_height_at(landing.x, landing.y) + 0.5, landing.y))
		show_status("Portal blocked! Defeat the Alien Overlord first.", 3.0)
		return
	_finished = true
	get_tree().change_scene_to_file(VICTORY_SCENE)


func _reset_player(message: String) -> void:
	player.respawn(environment.start_position)
	show_status(message, 3.0)


func _style_energy_bar() -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = Game.CYAN
	energy_bar.add_theme_stylebox_override("fill", fill)
	# The percentage on the bar is black, so it reads on the cyan fill.
	energy_bar.add_theme_color_override("font_color", Color.BLACK)


func _update_hud() -> void:
	orbs_label.text = "Issues: %d / %d" % [Game.orbs_collected, Game.TOTAL_ORBS]
	score_label.text = "Score: %d" % Game.score
	energy_bar.value = Game.energy_fraction() * 100.0


func _try_again() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func _go_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_boss_health_changed(current: int, maximum: int) -> void:
	boss_health_bar.max_value = maximum
	boss_health_bar.value = current
	boss_health_label.text = "ALIEN OVERLORD  %d / %d" % [current, maximum]
	boss_health_bar.visible = current > 0
