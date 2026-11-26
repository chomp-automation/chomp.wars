extends SceneTree
## Headless smoke test for Chomp Wars. It drives the real scenes frame by frame.
##
## Run from the repository root:
##   godot --headless --path . -s res://tests/smoke_test.gd
## Exit code 0 means every check passed.

const SCENE_PATHS := [
	"res://scenes/MainMenu.tscn",
	"res://scenes/MainGame.tscn",
	"res://scenes/Player.tscn",
	"res://scenes/Orb.tscn",
	"res://scenes/Enemy.tscn",
	"res://scenes/EvilChompbot.tscn",
	"res://scenes/Laser.tscn",
	"res://scenes/EnemyLaser.tscn",
	"res://scenes/Environment.tscn",
	"res://scenes/VictoryScreen.tscn",
]
const PINK_CHECK := Color(1.0, 0.36, 0.72)
const POINTS_PER_DRONE := 100

var _failures: Array[String] = []
var _passes := 0
var _step := 0
var _wait := 0
var _game: Node
var _env: Node
var _player: CharacterBody3D
var _game_state: Node
var _cover: StaticBody3D
var _player_before_cover: Vector3
var _level_one_score: int
var _rain_centre: Vector3
var _rain_seen := {}
var _rain_waves := 0
var _rain_ticks := 0


func _initialize() -> void:
	for path in SCENE_PATHS:
		_check(ResourceLoader.exists(path), "scene exists: " + path)
	_game_state = root.get_node_or_null("Game")
	_check(_game_state != null, "Game autoload is running")
	if _game_state == null:
		_finish()
		return
	_game_state.selected_character = "chomp"
	_start_game()


func _physics_process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	# Godot installs the next scene at the end of a frame. Several physics ticks
	# can run while current_scene is null, especially after loading the terrain.
	if current_scene == null:
		return false
	match _step:
		0:
			# Freeze enemy AI for the general playthrough and drive it explicitly in combat checks.
			_freeze_enemies()
			_check(_player.is_on_floor(), "player stands on the terrain at the start")
			_check(absf(_player.global_position.y - _env.start_position.y) < 0.4,
				"player start height matches the terrain")
			_check(_terrain_normal_up(), "terrain faces upwards (normals point up)")
			_check(_game_state._music_player != null and _game_state._music_player.stream != null,
				"background music is loaded")
			_check(_game_state._music_player.playing, "background music plays during the game")
			_check(_game_state._sounds.get("collect") != null and _game_state._sounds.get("jump") != null,
				"collect and jump sounds are loaded")
			var minimap = _game.get_node("Hud/Minimap")
			_check(minimap.markers(&"issue").size() == 10, "minimap shows all remaining issues")
			_check(minimap.markers(&"enemy").size() == 11, "minimap shows drones and evil chompbots")
			_check(minimap.world_to_map(Vector3.ZERO).is_equal_approx(Vector2(120, 138)), "minimap maps world centre correctly")
			_check(minimap.world_to_map(Vector3(-100, 0, -100)).is_equal_approx(Vector2(12, 30)), "minimap maps north-west world edge")
			_check(minimap.world_to_map(Vector3(100, 0, 100)).is_equal_approx(Vector2(228, 246)), "minimap maps south-east world edge")
			_check(minimap.mouse_filter == Control.MOUSE_FILTER_IGNORE, "minimap leaves gameplay input available")
			var issue = get_nodes_in_group("issue")[0]
			_check(issue.get_node("Mesh").mesh is QuadMesh, "collectible is a backlog card rather than a sphere")
			_check(issue.get_node("Mesh").material_override.albedo_texture != null, "backlog card has issue artwork")
			_check(_orb_count() == 10, "exactly 10 orbs are placed (found %d)" % _orb_count())
			_check(absf(_model().scale.x - 1.0) < 0.001, "Chomp uses the base model scale")
			_check(_drone_count() == 6, "six hovering drones are placed (found %d)" % _drone_count())
			_check(_bot_count() == 5, "five evil chompbots are placed (found %d)" % _bot_count())
			_check(_game_state.music_name() == "Starlight", "Starlight is the default background music")
			_check(_game_state.MUSIC_TRACKS.size() == 3 and _game_state.MUSIC_TRACKS[1].name == "Extra Terrestrial"
				and _game_state.MUSIC_TRACKS[2].name == "Hard Rock", "the music choices are Starlight, Extra Terrestrial and Hard Rock")
			_check(_game_state._sounds.get("laser") != null and _game_state._sounds.get("explosion") != null,
				"laser and explosion sounds are loaded")
			_check(_env.TERRAIN_SIZE >= 200, "the world is larger than before (%d m)" % _env.TERRAIN_SIZE)
			_check(_env.get_height_at(-62, 52) > 15.0, "tall hills rise well above the moonscape")
			_check(_invisible_boundary(), "the edge of the world has invisible walls, not drawn ones")
			var bot = _first_bot()
			_check(bot != null and bot.is_in_group("enemy"), "evil chompbots count as targets")
			_check(bot != null and bot.get_node("Model").scale.x > 1.5 * _model().scale.x,
				"evil chompbots are larger than the player")
			_check(_lake_is_dark(), "the frozen lake is very dark grey")
			if bot != null:
				bot.call("_pick_target")
				var target: Vector2 = bot.get("_target")
				var home := Vector2(bot.get("_home").x, bot.get("_home").z)
				_check(target.distance_to(home) <= 10.01 and _env.is_roam_clear(target),
					"an evil chompbot picks a clear spot to roam to within its range")
			var first_track: AudioStream = _game_state._music_player.stream
			_game_state.cycle_music()
			_check(_game_state._music_player.stream != first_track, "the start screen can change the music track")
			_check(_game_state._music_player.playing, "the new music track keeps playing")
			_game_state.set_music(0)
			_check(_game_state._music_player.stream == first_track, "music can go back to the first track")
			_check(_game_state.font_regular != null and _game_state.font_semibold != null,
				"Inter fonts are loaded")
			_check(ThemeDB.fallback_font == _game_state.font_regular, "Inter is the default interface font")
			_check(_key_for("fire") == KEY_SPACE, "Space is bound to fire")
			_check(_key_for("jump") == KEY_SHIFT, "Shift is bound to jump")
			_respawn_at_and_settle(Vector2(-26, 30))
		1:
			var expected: float = _env.get_height_at(-26, 30)
			_check(_player.is_on_floor(), "player stands on the terrain away from the start")
			_check(absf(_player.global_position.y - expected) < 0.4,
				"terrain collision lines up with the drawn ground (off by %.2f m)" %
				absf(_player.global_position.y - expected))
			_player.respawn(_env.start_position)
			_wait = 30
			_step = 2
		2:
			# A turns the character on the spot. Turn it back afterwards so walking forward
			# below goes the same way as before.
			_turn_yaw_before = _player.global_rotation.y
			Input.action_press("move_left")
			_wait = 30
			_step = 300
		300:
			Input.action_release("move_left")
			var turned := absf(wrapf(_player.global_rotation.y - _turn_yaw_before, -PI, PI))
			_check(turned > 0.5, "A turns the character round (turned %.2f rad)" % turned)
			_player.global_rotation.y = _turn_yaw_before
			var start_z := _player.global_position.z
			Input.action_press("move_forward")
			_wait = 60
			_step = 3
			_start_z = start_z
		3:
			Input.action_release("move_forward")
			var moved := _start_z - _player.global_position.z
			_check(moved > 3.0, "walking forward moves the player (moved %.2f m)" % moved)
			_check(absf(_player.global_position.y - _env.start_position.y) < 1.0,
				"walking keeps the player on the ground")
			Input.action_press("jump")
			_step = 4
			_wait = 1
		4:
			Input.action_release("jump")
			_check(_player.velocity.y > 0.0, "jump gives upward velocity")
			_wait = 90
			_step = 5
		5:
			_check(_player.is_on_floor(), "player lands after jumping")
			_collect_all_orbs()
			_check(_game.get_node("Hud/Minimap").markers(&"issue").is_empty(), "collected issues disappear from map immediately")
			_check(_game_state.orbs_collected == 10, "collecting all orbs counts to 10 (got %d)" % _game_state.orbs_collected)
			_check(not _env.portal_active, "portal stays locked after the tenth issue")
			var boss = _game.get("_boss")
			_check(_game.boss_health_bar.visible and _game.boss_health_bar.value == 300, "boss fight shows 300 health")
			boss.set_process(false)
			_check(boss.health == 300, "alien has ten times its original health")
			_check(_game_state._music_player.stream == _game_state._music_streams[2], "boss starts Hard Rock music")
			_check(_game_state._sounds.has("boss_attack") and _game_state._sounds.has("portal_error"), "boss attack and blocked portal have audio cues")
			_remove_enemy_lasers()
			boss.attack(_player.global_position)
			_check(_live_enemy_laser_count() == 3, "boss attack fires a three-shot spread")
			_remove_enemy_lasers()
			boss.attack(_player.global_position)
			_check(_live_enemy_laser_count() == 12, "second boss attack fires a radial barrage")
			_remove_enemy_lasers()
			boss.attack(_player.global_position)
			_check(_live_enemy_laser_count() == 1 and boss._burst_remaining == 3, "third boss attack begins tracking burst")
			for shot in 3:
				boss._process(0.31)
			_check(_live_enemy_laser_count() == 4 and boss._burst_remaining == 0, "tracking burst fires four timed shots")
			_remove_enemy_lasers()
			boss._process(1.08)
			_check(_live_enemy_laser_count() == 3, "boss attacks as soon as it emerges")
			var boss_position: Vector3 = boss.position
			boss._process(1.36)
			_check(boss.position.distance_to(boss_position) > 1.0, "boss strafes after emerging")
			_check(_live_enemy_laser_count() == 15, "boss attacks again within 1.36 seconds at full health")
			_remove_enemy_lasers()
			_player.respawn(boss.global_position)
			_env.portal_entered.emit(_player)
			_check(not _game.get("_finished"), "living boss prevents victory")
			_check((Vector2(_player.position.x, _player.position.z) - _env.PORTAL_POSITION).length() >= 3.9, "blocked portal pushes player out")
			var cries := 0
			_check(not boss.hit(), "boss survives its first hit")
			for child in _game_state.get_children():
				if child is AudioStreamPlayer and child.stream == _game_state._sounds["boss_hit"]:
					cries += 1
			_check(cries == 1, "a damaging hit plays an alien yell")
			_check(_damage_without_destroying(boss, 298), "boss survives the next 298 hits")
			_check(not _env.portal_active, "portal remains locked at one boss hitpoint")
			_check(_game.boss_health_bar.value == 1, "screen health bar tracks damage")
			boss._emergence = 2.0
			boss._cooldown = 0.0
			boss._process(0.01)
			_check(is_equal_approx(boss._cooldown, 0.85), "wounded boss attacks faster")
			_remove_enemy_lasers()
			_check(boss.hit(), "300th hit defeats the alien")
			_check(_env.portal_active, "boss defeat opens the portal")
			_check(not _game.boss_health_bar.visible, "boss defeat hides screen health bar")
			_check(_game_state._music_player.stream == _game_state._music_streams[_game_state.selected_music], "boss defeat restores selected music")
			_env.water_entered.emit(_player)
			_check(_player.global_position.distance_to(_env.start_position) < 0.01,
				"water hazard resets the player to the start")
			_wait = 2
			_step = 6
		6:
			_check(_game.get("_finished") == false, "portal is not used before the game is complete")
			_env.portal_entered.emit(_player)
			_wait = 4
			_step = 7
		7:
			var scene := current_scene
			_check(scene != null and scene.scene_file_path == "res://scenes/VictoryScreen.tscn",
				"reaching the portal opens the victory screen")
			_check(_focus_name() == "NextLevelButton", "victory screen focuses the next level for controllers")
			_level_one_score = _game_state.score
			scene.get_node("Center/Menu/NextLevelButton").pressed.emit()
			_wait = 4
			_step = 70
		70:
			_refresh_game_refs()
			_freeze_enemies()
			_check(_game_state.level == 2 and _game.get_node("Hud/CharacterLabel").text.begins_with("Level 2"),
				"continuing from victory enters level two")
			_check(_game_state.orbs_collected == 0 and _orb_count() == 10 and not _env.portal_active,
				"the next level has fresh issues and a locked portal")
			_check(_game_state.score == _level_one_score and _game_state.energy_fraction() == 1.0,
				"the next level carries score and refills energy")
			_check_enemy_settings(12, 360, 1.2)
			_game._boss.health = 1
			_game._boss.hit()
			_env.portal_entered.emit(_player)
			_wait = 4
			_step = 71
		71:
			current_scene.get_node("Center/Menu/NextLevelButton").pressed.emit()
			_wait = 4
			_step = 72
		72:
			_refresh_game_refs()
			_freeze_enemies()
			_check(_game_state.level == 3, "the same portal and continue flow reaches level three")
			_check_enemy_settings(14, 432, 1.44)
			_game._go_to_main_menu()
			_wait = 4
			_step = 8
		8:
			_check(current_scene != null and current_scene.scene_file_path == "res://scenes/MainMenu.tscn",
				"the main menu is available after continuing")
			var difficulty: Button = current_scene.find_child("Difficulty", true, false)
			_check(difficulty.text.ends_with("Hard"), "Hard is selected by default")
			difficulty.pressed.emit()
			_check(difficulty.text.ends_with("Medium"), "the main menu offers Medium")
			_check_selected_difficulty(5, 150, 0.5)
			difficulty.pressed.emit()
			_check(difficulty.text.ends_with("Easy"), "the main menu offers Easy")
			_check_selected_difficulty(2, 60, 0.2)
			difficulty.pressed.emit()
			_check(difficulty.text.ends_with("Hard"), "difficulty cycles back to Hard")
			_game_state.selected_character = "mrs_chomp"
			current_scene.get("_start_button").pressed.emit()
			_wait = 4
			_step = 9
		9:
			_refresh_game_refs()
			_freeze_enemies()
			_remove_enemy_lasers()
			_check(_game_state.orbs_collected == 0, "a new run starts with 0 orbs")
			_check(_game_state.level == 1 and _game_state.score == 0, "Start begins a fresh run at level one")
			_check(_orb_count() == 10, "a restarted run places 10 orbs again")
			_check(absf(_model().scale.x - 0.92) < 0.01, "Mrs. Chomp uses the slimmer model scale")
			_check(_count_pink(_model()) > 0, "Mrs. Chomp has pink recoloured parts")
			_game.toggle_pause()
			_check(paused, "pause menu pauses the game")
			_game.toggle_pause()
			_check(not paused, "pause menu resumes the game")
			_check(_model().visible, "default view shows the character")
			_player.call("_set_third_person", false)
			_check(not _model().visible, "first-person view hides the character body")
			_player.call("_set_third_person", true)
			_check(_model().visible, "third-person view shows the character again")
			_step = 10
		10:
			_player.fire()
			_check(_laser_count() == 1, "firing spawns one laser")
			_check(_laser_color_matches(_game_state.laser_color("mrs_chomp")), "Mrs. Chomp fires pink lasers")
			_player.fire()
			_check(_laser_count() == 1, "the fire cooldown stops a second laser at once")
			_wait = 140
			_step = 100
		100:
			Input.action_press("fire")
			_wait = 2
			_step = 101
		101:
			_check(_laser_count() == 0, "holding fire charges without shooting")
			_player.call("_update_charge", 12.0)
			_check(is_equal_approx(_player.charge_time, 10.0), "charge caps at ten seconds")
			_rain_centre = _player.global_position
			Input.action_release("fire")
			_wait = 1
			_step = 102
		102:
			_record_rain_wave()
			_check(_rain_waves == 1, "full charge releases the first laser rain wave")
			_game.toggle_pause()
			_wait = 35
			_step = 103
		103:
			_record_rain_wave()
			_check(_rain_waves == 1, "laser rain waits while the game is paused")
			_game.toggle_pause()
			_player.respawn(_rain_centre + Vector3.RIGHT * 5.0)
			_step = 104
		104:
			_record_rain_wave()
			_rain_ticks += 1
			if _rain_ticks >= 115:
				_check(_rain_waves == 4 and _rain_seen.size() == 288, "laser rain fires exactly four waves and 288 beams")
				for laser in get_nodes_in_group("laser"):
					laser.free()
				_step = 105
		105:
			var clear_origin := Vector3(0, 40, 0)
			var previous_origin := _player.global_position
			_player.respawn(clear_origin - Vector3.UP)
			for sample in [[0.0, 1], [0.249, 1], [0.25, 1], [0.499, 1], [0.5, 5], [0.749, 5], [0.75, 24], [0.999, 24]]:
				_game.call("_on_player_fired", clear_origin, Vector3.FORWARD, "chomp", sample[0])
				_check(_laser_count() == sample[1], "charge %.3f selects expected attack" % sample[0])
				var active_at_90 := true
				var expires_at_100 := true
				for laser in get_nodes_in_group("laser"):
					laser._physics_process(2.0)
					active_at_90 = active_at_90 and not laser.is_queued_for_deletion()
					laser._physics_process(0.5)
					var distance: float = laser.global_position.distance_to(clear_origin)
					expires_at_100 = expires_at_100 and laser.is_queued_for_deletion() and absf(distance - 100.0) < 0.001
					if sample[0] == 0.25:
						_check(laser.scale.x > 2.0, "second stage creates a big beam")
					laser.free()
				_check(active_at_90 and expires_at_100,
					"unobstructed shots at charge %.3f travel half the map width" % sample[0])
			_player.respawn(previous_origin)
			for sample in [[2.5, "Big laser beam"], [5.0, "Multiple lasers"], [7.5, "Laser circle"], [9.96, "Laser circle"], [10.0, "Laser rain"]]:
				_player.charge_time = sample[0]
				_game.call("_process", 0.0)
				_check(_game.charge_label.text.contains(sample[1]), "charge bar shows the selected attack")
				_check(_game.charge_label.text.contains("%d%%" % floori(sample[0] * 10.0)),
					"charge percentage appears inside the bar")
				_check(is_equal_approx(_game.charge_bar.value, sample[0] * 10.0),
					"charge bar tracks progress without rounding up to the next stage")
			_player.cancel_charge()
			_check(is_zero_approx(_player.charge_time), "release resets charge")
			_player.charge_time = 2.0
			_game.toggle_pause()
			_check(is_zero_approx(_player.charge_time), "pause cancels pending charge")
			_game.toggle_pause()
			_wait = 110
			_step = 11
		11:
			_check(_key_for("aim_up") == KEY_UP and _key_for("aim_down") == KEY_DOWN,
				"Up and Down arrows are bound to aim")
			# These actions are shared by keyboard and D-pad, independent of stick input.
			Input.action_press("move_forward")
			Input.action_press("move_right")
			var yaw_before: float = _player.rotation.y
			_player.call("_physics_process", 0.1)
			_check(is_equal_approx(Vector2(_player.velocity.x, _player.velocity.z).length(), 6.0),
				"keyboard and D-pad keep full movement speed while turning")
			_check(is_equal_approx(yaw_before - _player.rotation.y, 0.182),
				"keyboard and D-pad turn 30 percent more slowly while moving")
			Input.action_release("move_forward")
			Input.action_release("move_right")
			yaw_before = _player.rotation.y
			Input.action_press("stick_right")
			_player.call("_physics_process", 0.1)
			_check(is_equal_approx(_player.rotation.y, yaw_before), "left stick strafes without turning")
			_check(Vector2(_player.velocity.x, _player.velocity.z).length() > 5.0, "left stick strafes at walking speed")
			Input.action_press("aim_lock")
			_player.call("_physics_process", 0.1)
			_check(is_zero_approx(_player.velocity.x) and is_zero_approx(_player.velocity.z), "L2 holds player still")
			_check(is_equal_approx(yaw_before - _player.rotation.y, 0.2002), "L2 left-stick aiming remains twice as fast")
			Input.action_release("aim_lock")
			Input.action_release("stick_right")
			Input.action_press("sniper")
			Input.action_press("look_right")
			yaw_before = _player.rotation.y
			_player.call("_physics_process", 0.1)
			var zoom_fov: float = _player.get_node("CameraPivot/Camera").fov
			var magnification := tan(deg_to_rad(75.0) / 2.0) / tan(deg_to_rad(zoom_fov) / 2.0)
			_check(is_equal_approx(magnification, 5.0), "R2 gives true 5x perspective magnification")
			_check(is_equal_approx(yaw_before - _player.rotation.y, 0.02002), "sniper aiming is five times finer")
			_check(is_zero_approx(_player.charge_time), "R2 does not charge fire")
			Input.action_release("sniper")
			Input.action_release("look_right")
			_player.call("_physics_process", 0.0)
			_check(is_equal_approx(_player.get_node("CameraPivot/Camera").fov, 75.0), "releasing R2 restores view")
			_player.get_node("CameraPivot").rotation.x = 0.0
			Input.action_press("aim_up")
			_player.call("_physics_process", 0.1)
			Input.action_release("aim_up")
			_check(is_equal_approx(_player.get_node("CameraPivot").rotation.x, 0.0231), "keyboard pitch is 30 percent slower")
			_player.call("_pitch_camera", 100.0)
			_check(_player.get_node("CameraPivot").rotation.x <= deg_to_rad(60.0) + 0.001, "aim is limited vertically")
			_player.get_node("CameraPivot").rotation.x = 0.0
			_check(_laser_count() == 0, "lasers disappear after they expire or hit")
			var drone := _first_drone()
			_check(drone != null, "a drone is available to shoot")
			if drone != null:
				_check(_damage_without_destroying(drone, 9) and drone.get("health") == 1,
					"UFO survives nine hits")
				_check(_game_state.score == 0, "damaging a UFO awards no points")
				_check(drone.hit(), "tenth hit destroys a UFO")
			_check(_game.get_node("Hud/Minimap").markers(&"enemy").size() == 10, "destroyed enemies disappear from map immediately")
			_check(_game_state.score == POINTS_PER_DRONE, "destroying a drone scores points (score %d)" % _game_state.score)
			_check(_game.get_node("Hud/ScoreLabel").text == "Score: %d" % _game_state.score, "score is shown on the HUD")
			_wait = 30
			_step = 12
		12:
			_check(_drone_count() == 5, "a destroyed drone is removed (found %d)" % _drone_count())
			var target := _first_drone()
			if target != null:
				_check_drone_pursuit(target)
				_set_up_cover(target)
			_wait = 2
			_step = 120
		120:
			var target := _first_drone()
			if target != null:
				_check_projectile_cover(target)
				_cover.queue_free()
			_wait = 2
			_step = 121
		121:
			var target := _first_drone()
			if target != null:
				_game.call("_spawn_laser", target.global_position + Vector3.RIGHT * 5.0, Vector3.LEFT, Color.CYAN, 0.0)
				var shot: Node = get_first_node_in_group("laser")
				shot._physics_process(0.2)
				_check(target.get("health") == 9, "an unobstructed laser damages the UFO exactly once")
				shot.queue_free()
				_check(_damage_without_destroying(target, 8), "UFO survives until its last hitpoint")
				_game.call("_spawn_laser", target.global_position + Vector3.RIGHT * 5.0, Vector3.LEFT, Color.CYAN, 0.0)
				var player_position := _player.global_position
				var energy_before: float = _game_state.energy_fraction()
				_game.call("_on_enemy_fired", player_position + Vector3(5, 0.6, 0), Vector3.LEFT)
				get_nodes_in_group("enemy_laser").back()._physics_process(0.3)
				_check(_player.global_position.is_equal_approx(player_position), "a red laser hit leaves Chomp in place")
				_check(absf(_game_state.energy_fraction() - (energy_before - 1.0 / 3.0)) < 0.001,
					"an unobstructed red laser takes a third of Chomp's energy")
				_check(not _game.get_node("Hud/GameOverMenu").visible, "one enemy laser hit does not end the run")
			_player.respawn(_player_before_cover)
			_player.set_physics_process(true)
			_wait = 30
			_step = 13
		13:
			_check(_game_state.enemies_destroyed == 2, "a laser destroys a UFO on its last hitpoint")
			_check(_game_state.score == 2 * POINTS_PER_DRONE, "each kill adds points (score %d)" % _game_state.score)
			_check_controller_bindings()
			# Controller: push the left stick forward.
			_player.respawn(_env.start_position)
			_wait = 30
			_step = 130
		130:
			var bot = _first_bot()
			_check(bot != null, "an evil chompbot is available to shoot")
			if bot != null:
				var kills_before: int = _game_state.enemies_destroyed
				_remove_enemy_lasers()  # clear any shots already in flight, so the count below is this shot only
				var before: Vector3 = bot.global_position
				_player.respawn(before + Vector3(0, 0, 8))
				bot._fire_cooldown = 0.0
				bot._process(0.15)
				_check(bot.global_position.distance_to(before) > 0.5, "a chompbot strafes in combat")
				_check(_live_enemy_laser_count() == 1, "an evil chompbot fires at a nearby player")
				bot._process(1.11)
				_check(_live_enemy_laser_count() == 2, "a chompbot fires again within 1.11 seconds")
				_remove_enemy_lasers()
				_check(_has_red_surface(bot.get_node("Model")), "evil chompbots are red")
				_check(_damage_without_destroying(bot, 9) and bot.health == 1, "chompbot survives nine hits")
				_check(bot.hit(), "tenth hit destroys a chompbot")
				_check(_game_state.enemies_destroyed == kills_before + 1, "destroying an evil chompbot counts as a kill")
			_remove_enemy_lasers()  # a shot still in flight from an earlier frame must not count here
			_player.respawn(_env.start_position)
			_wait = 2
			_step = 14
		14:
			_start_z = _player.global_position.z
			_joy_axis(JOY_AXIS_LEFT_Y, -1.0)
			_wait = 60
			_step = 15
		15:
			_joy_axis(JOY_AXIS_LEFT_Y, 0.0)
			var moved := _start_z - _player.global_position.z
			_check(moved > 3.0, "left stick moves the player forward (moved %.2f m)" % moved)
			_start_yaw = _player.rotation.y
			_start_pitch = _player.get_node("CameraPivot").rotation.x
			_joy_axis(JOY_AXIS_RIGHT_X, 1.0)
			_joy_axis(JOY_AXIS_RIGHT_Y, -1.0)
			_wait = 20
			_step = 16
		16:
			_joy_axis(JOY_AXIS_RIGHT_X, 0.0)
			_joy_axis(JOY_AXIS_RIGHT_Y, 0.0)
			_check(_player.rotation.y < _start_yaw - 0.20, "right stick turns the view right")
			_check(_player.get_node("CameraPivot").rotation.x > _start_pitch + 0.14, "right stick tilts the view up")
			_wait = 10
			_step = 17
		17:
			_yaw_after_release = _player.rotation.y
			_joy_axis(JOY_AXIS_RIGHT_X, 0.1)  # small stick drift, inside the deadzone
			_wait = 20
			_step = 18
		18:
			_joy_axis(JOY_AXIS_RIGHT_X, 0.0)
			_check(is_equal_approx(_player.rotation.y, _yaw_after_release), "right-stick drift inside the deadzone is ignored")
			_check(_player.is_on_floor(), "player is on the ground before the controller jump")
			_joy_button(JOY_BUTTON_B, true)  # right face button
			_wait = 2
			_step = 19
		19:
			_joy_button(JOY_BUTTON_B, false)
			_check(_player.velocity.y > 0.0, "right face button jumps")
			_player.fired.connect(func(_origin: Vector3, _direction: Vector3, _character: String, _charge: float) -> void:
				_controller_shots += 1)
			_joy_button(JOY_BUTTON_RIGHT_SHOULDER, true)
			_wait = 2
			_step = 190
		190:
			_joy_button(JOY_BUTTON_RIGHT_SHOULDER, false)
			_wait = 2
			_step = 194
		194:
			_check(_controller_shots == 1, "R1 shoulder button fires on release")
			_wait = 30  # let the fire cooldown pass
			_step = 191
		191:
			_joy_button(JOY_BUTTON_RIGHT_SHOULDER, true)  # R1 shoulder button
			_wait = 2
			_step = 192
		192:
			_joy_button(JOY_BUTTON_RIGHT_SHOULDER, false)
			_wait = 2
			_step = 195
		195:
			_check(_controller_shots == 2, "R1 can fire again after the cooldown")
			_view_before = _player.third_person
			_joy_button(JOY_BUTTON_X, true)  # left face button
			_wait = 2
			_step = 193
		193:
			_joy_button(JOY_BUTTON_X, false)
			_check(_player.third_person != _view_before, "left face button switches the view")
			_player.call("_set_third_person", _view_before)
			_check(_button_for("interact") == JOY_BUTTON_A, "bottom face button reads signposts")
			_check(_key_for("sprint") == KEY_CTRL and _button_for("sprint") == JOY_BUTTON_A,
				"Ctrl and the PlayStation Cross button are bound to sprint")
			_player.respawn(Vector3(0, 30, 0))
			_joy_axis(JOY_AXIS_LEFT_Y, -1.0)
			_joy_button(JOY_BUTTON_A, true)
			_wait = 2
			_step = 196
		196:
			_check(is_equal_approx(Vector2(_player.velocity.x, _player.velocity.z).length(), 12.0),
				"holding Cross doubles movement speed")
			_joy_button(JOY_BUTTON_A, false)
			_wait = 2
			_step = 197
		197:
			_check(is_equal_approx(Vector2(_player.velocity.x, _player.velocity.z).length(), 6.0),
				"releasing Cross restores walking speed")
			_joy_axis(JOY_AXIS_LEFT_Y, 0.0)
			_wait = 2
			_step = 20
		20:
			_joy_button(JOY_BUTTON_START, true)
			_wait = 2
			_step = 21
		21:
			_joy_button(JOY_BUTTON_START, false)
			_check(paused, "Start pauses the game")
			_check(_focus_name() == "ResumeButton", "pause menu focuses Resume for controllers")
			_wait = 2
			_step = 22
		22:
			_joy_button(JOY_BUTTON_A, true)  # bottom face button presses the focused Resume button
			_wait = 2
			_step = 23
		23:
			_joy_button(JOY_BUTTON_A, false)
			_wait = 2
			_step = 24
		24:
			_check(not paused, "bottom face button on Resume resumes the game")
			paused = false
			change_scene_to_file("res://scenes/MainMenu.tscn")
			_wait = 4
			_step = 25
		25:
			_check(_focus_name() == "Start", "main menu focuses Start for controllers")
			_joy_button(JOY_BUTTON_A, true)
			_wait = 2
			_step = 26
		26:
			_joy_button(JOY_BUTTON_A, false)
			_wait = 6
			_step = 27
		27:
			_check(current_scene != null and current_scene.scene_file_path == "res://scenes/MainGame.tscn",
				"bottom face button on Start begins a game from the main menu")
			_refresh_game_refs()
			_check(_game_state.energy_fraction() == 1.0, "a new run starts with full energy")
			_game.call("_on_enemy_laser_hit")
			_game.call("_on_enemy_laser_hit")
			_check(not _game.get_node("Hud/GameOverMenu").visible, "two enemy laser hits do not end the run")
			_game.call("_on_orb_collected", null)
			_check(_game_state.energy_fraction() == 1.0, "collecting an issue restores the energy to 100%")
			_check(_game.get_node("Hud/EnergyBar").value > 99.9, "the energy bar is full again after an issue")
			_game.call("_on_enemy_laser_hit")
			_game.call("_on_enemy_laser_hit")
			_check(not _game.get_node("Hud/GameOverMenu").visible, "two hits after a refill do not end the run")
			_game.call("_on_enemy_laser_hit")
			_check(_game.get_node("Hud/GameOverMenu").visible, "three enemy laser hits show the game over screen")
			_check(_game.get_tree().paused, "the game over screen pauses the game")
			_check(_game.get_node("Hud/EnergyBar").value < 0.01, "the energy bar is empty after three hits")
			_check(_game.get_node("Hud/ScoreLabel").position.x < _game.get_node("Hud/OrbsLabel").position.x \
				and absf(_game.get_node("Hud/ScoreLabel").position.y - _game.get_node("Hud/OrbsLabel").position.y) < 1.0,
				"the score sits top left with the issues to its right")
			_check(_game.get_node("Hud/EnergyBar").get_theme_stylebox("fill").bg_color == _game_state.CYAN,
				"the energy bar fill is cyan")
			_check(_game.get_node("Hud/EnergyBar").get_theme_color("font_color") == Color.BLACK,
				"the energy bar text is black")
			_check(_game.get_node("Hud/TimeLabel").text.begins_with("Time "), "a time counter sits on the HUD")
			_check(_game.call("_format_time", 75.0) == "01:15", "the time counter shows minutes and seconds")
			_check(is_equal_approx(_game.get("_game_speed"), 1.0), "gameplay and music start at normal speed")
			_game.set("_elapsed", 119.9)
			_game.call("_update_escalation")
			_check(is_equal_approx(_game_state._music_player.pitch_scale, 1.0), "music remains normal before two minutes")
			_game.set("_elapsed", 120.0)
			_game.call("_update_escalation")
			_check(is_equal_approx(_game_state._music_player.pitch_scale, 1.3)
				and is_equal_approx(Engine.time_scale, 1.3), "gameplay and music speed up after two minutes")
			Engine.time_scale = 1.0
			_game.set("_game_speed", 1.0)
			_game_state.set_music_speed(1.0)
			_check(_moonbase_exists(), "a domed moonbase is built on the moon")
			var base: Node = _env.get("_props").find_child("MoonBase", true, false)
			_check(base != null and base.get_node("TrappedChomps").get_child_count() == 10,
				"ten tiny Chomps are trapped inside the moonbase")
			for i in 10:
				_env.hit_moonbase()
			_check(_env.get("_released_chomps") and base.get_node("TrappedChomps").get_child(0).position.length() > 9.0,
				"ten moonbase hits release the trapped Chomps")
			var rocks: Array = _env.get("_rocks")
			if not rocks.is_empty():
				_env.destroy_rock(rocks[0])
				_check((_env.get("_rocks") as Array).size() == 23,
					"a moon rock is destroyed by a laser hit")
			_check(_pond_is_not_blue(), "the lake and pond are not blue")
			_check((_env.get("_rock_spots") as Array).size() <= 30, "there are only a few moon rocks")
			_finish()
			return true
	return false


var _start_yaw := 0.0
var _start_pitch := 0.0
var _yaw_after_release := 0.0
var _controller_shots := 0
var _view_before := true


var _start_z := 0.0
var _turn_yaw_before := 0.0


func _start_game() -> void:
	var game_scene: PackedScene = load("res://scenes/MainGame.tscn")
	_game = game_scene.instantiate()
	root.add_child(_game)
	current_scene = _game
	_refresh_game_refs()
	_wait = 30
	_step = 0


func _refresh_game_refs() -> void:
	_game = current_scene
	_env = _game.get_node("Environment")
	_player = _game.get_node("Player")


func _respawn_at_and_settle(p: Vector2) -> void:
	_player.respawn(Vector3(p.x, _env.get_height_at(p.x, p.y) + 0.5, p.y))
	_wait = 60
	_step = 1


func _collect_all_orbs() -> void:
	for child in _game.get_children():
		if child is Area3D and child.has_signal("collected"):
			child.emit_signal("body_entered", _player)


func _orb_count() -> int:
	var count := 0
	for child in _game.get_children():
		if child is Area3D and child.has_signal("collected"):
			count += 1
	return count


func _drone_count() -> int:
	var count := 0
	for node in get_nodes_in_group("drone"):
		if node.monitorable and node.is_inside_tree():
			count += 1
	return count


func _first_drone() -> Area3D:
	for node in get_nodes_in_group("drone"):
		if node.monitorable and node.is_inside_tree():
			return node as Area3D
	return null


func _bot_count() -> int:
	return get_nodes_in_group("evil_bot").size()


func _first_bot() -> Area3D:
	for node in get_nodes_in_group("evil_bot"):
		if node.monitorable and node.is_inside_tree():
			return node as Area3D
	return null


func _freeze_enemies() -> void:
	for node in get_nodes_in_group("enemy"):
		node.set_process(false)


func _check_selected_difficulty(normal_health: int, boss_health: int, multiplier: float) -> void:
	_game_state.reset_run()
	_game = load("res://scenes/MainGame.tscn").instantiate()
	root.add_child(_game)
	_player = _game.get_node("Player")
	_check_enemy_settings(normal_health, boss_health, multiplier)
	_game.free()


func _check_enemy_settings(normal_health: int, boss_health: int, multiplier: float) -> void:
	var drone := _first_drone()
	var bot := _first_bot()
	_check(drone.health == normal_health and bot.health == normal_health,
		"%.2fx difficulty scales UFO and chompbot health" % multiplier)
	_check(is_equal_approx(drone._aggro_range, 26.0 * multiplier)
		and is_equal_approx(drone._home_range, 36.0 * multiplier)
		and is_equal_approx(bot._engagement_range, 24.0 * multiplier),
		"%.2fx difficulty scales enemy pursuit and engagement ranges" % multiplier)
	var drone_home: Vector3 = drone.home
	drone._fire_cooldown = 0.0
	_player.respawn(drone_home + Vector3.RIGHT * (26.0 * multiplier + 0.5))
	drone._process(0.0)
	_check(_live_enemy_laser_count() == 0, "UFO ignores Chomp just outside the scaled range")
	_player.respawn(drone_home + Vector3.RIGHT * (26.0 * multiplier - 0.5))
	drone._process(0.0)
	_check(_live_enemy_laser_count() == 1 and is_equal_approx(drone._fire_cooldown, 1.4 / multiplier),
		"UFO fires within the scaled range and uses the scaled interval")
	_remove_enemy_lasers()
	bot._fire_cooldown = 0.0
	var bot_position: Vector3 = bot.position
	_player.respawn(bot_position + Vector3.RIGHT * (24.0 * multiplier + 0.5))
	bot._process(0.0)
	_check(_live_enemy_laser_count() == 0, "chompbot ignores Chomp just outside the scaled range")
	_player.respawn(bot_position + Vector3.RIGHT * (24.0 * multiplier - 0.5))
	bot._process(0.0)
	_check(_live_enemy_laser_count() == 1 and is_equal_approx(bot._fire_cooldown, 1.1 / multiplier),
		"chompbot fires within the scaled range and uses the scaled interval")
	_remove_enemy_lasers()
	_collect_all_orbs()
	var boss = _game._boss
	boss.set_process(false)
	_check(boss.health == boss_health and _game.boss_health_bar.max_value == boss_health
		and boss._health_label.text.ends_with("/ %d" % boss_health),
		"%.2fx difficulty scales boss health in both displays" % multiplier)
	boss._process(2.0)
	_check(_live_enemy_laser_count() == 3 and is_equal_approx(boss._cooldown, 1.35 / multiplier),
		"%.2fx difficulty scales boss firing rate" % multiplier)
	_remove_enemy_lasers()


func _record_rain_wave() -> void:
	var beam_count := 0
	var colors := {}
	var radius := 0.0
	var falling_from_above := true
	var same_range := true
	for laser in get_nodes_in_group("laser"):
		var id: int = laser.get_instance_id()
		if _rain_seen.has(id):
			continue
		_rain_seen[id] = true
		beam_count += 1
		var offset: Vector3 = laser.global_position - _rain_centre
		radius = maxf(radius, Vector2(offset.x, offset.z).length())
		var ground: float = _env.get_height_at(laser.position.x, laser.position.z)
		falling_from_above = falling_from_above and laser.position.y > ground and laser._direction == Vector3.DOWN
		colors[laser.get_node("Bolt").material_override.albedo_color] = true
		same_range = same_range and laser.max_distance == 100.0
	if beam_count == 0:
		return
	_rain_waves += 1
	_check(beam_count == 72 and absf(radius - 72.0) < 0.001,
		"rain wave %d contains 72 beams across the original radius" % _rain_waves)
	_check(falling_from_above and colors.has(Color.RED) and colors.has(Color.WHITE)
		and colors.has(Color(0.18, 0.45, 1.0)) and colors.size() == 3,
		"rain wave %d contains red, white and blue beams falling from above" % _rain_waves)
	_check(same_range, "rain wave %d has the same range limit as other shots" % _rain_waves)


func _damage_without_destroying(enemy: Area3D, hits: int) -> bool:
	for i in hits:
		if enemy.hit():
			return false
	return true


func _check_drone_pursuit(drone: Area3D) -> void:
	var player_position := _player.global_position
	var home: Vector3 = drone.get("home")
	_remove_enemy_lasers()
	_player.respawn(home + Vector3.RIGHT * 30.0)
	drone.set("_fire_cooldown", 0.0)
	drone._process(0.5)
	_check(_live_enemy_laser_count() == 0 and drone.global_position.distance_to(home) < 3.5,
		"an out-of-range UFO stays on patrol")
	_player.respawn(home + Vector3.RIGHT * 18.0)
	var before := drone.global_position.distance_to(_player.global_position)
	drone._process(0.5)
	_check(drone.global_position.distance_to(_player.global_position) < before - 2.0, "a nearby UFO follows the player")
	_check(_live_enemy_laser_count() == 1, "a pursuing UFO fires at the player")
	drone._process(1.41)
	_check(_live_enemy_laser_count() == 2, "a pursuing UFO fires again within 1.41 seconds")
	_remove_enemy_lasers()
	_player.respawn(player_position)


func _set_up_cover(drone: Area3D) -> void:
	_player_before_cover = _player.global_position
	_player.set_physics_process(false)
	_player.respawn(Vector3(0, 30, 0))
	drone.global_position = _player.global_position + Vector3.UP * 0.6
	_cover = StaticBody3D.new()
	_cover.position = Vector3(2, 30, 0)
	var box := BoxShape3D.new()
	box.size = Vector3(0.1, 4.0, 4.0)
	var shape := CollisionShape3D.new()
	shape.shape = box
	_cover.add_child(shape)
	_game.add_child(_cover)


func _check_projectile_cover(drone: Area3D) -> void:
	var from := drone.global_position + Vector3.RIGHT * 5.0
	_game.call("_spawn_laser", from, Vector3.LEFT, Color.CYAN, 0.65)
	var shot: Node3D = get_first_node_in_group("laser")
	shot._physics_process(0.2)
	_check(shot.is_queued_for_deletion() and shot.position.x > 2.0 and drone.get("health") == 10,
		"charged laser stops at thin cover without damaging the UFO behind it")
	_game.call("_spawn_laser", Vector3(2, from.y, from.z), Vector3.LEFT, Color.CYAN, 0.0)
	var muzzle_blocked: Node3D = get_nodes_in_group("laser").back()
	muzzle_blocked._physics_process(0.2)
	_check(muzzle_blocked.is_queued_for_deletion() and is_equal_approx(muzzle_blocked.position.x, 2.0)
		and drone.get("health") == 10, "a shot that starts against cover cannot pass through it")
	var energy_before: float = _game_state.energy_fraction()
	_game.call("_on_enemy_fired", from, Vector3.LEFT)
	var hostile: Node3D = get_nodes_in_group("enemy_laser").back()
	hostile._physics_process(0.3)
	_check(hostile.is_queued_for_deletion() and hostile.position.x > 2.0
		and _game_state.energy_fraction() == energy_before, "cover blocks a red laser before it hits Chomp")
	var ground: Vector3 = _env.start_position
	_game.call("_spawn_laser", ground + Vector3.UP * 3.0, Vector3.DOWN, Color.CYAN, 0.25)
	var rain: Node3D = get_nodes_in_group("laser").back()
	rain._physics_process(0.2)
	_check(rain.is_queued_for_deletion() and absf(rain.position.y - ground.y) < 0.5,
		"a downward beam stops at the real heightmap terrain")
	var rocks: Array = _env.get("_rocks")
	var rock: StaticBody3D = rocks[0]
	_game.call("_spawn_laser", rock.global_position + Vector3.UP * 4.0, Vector3.DOWN, Color.CYAN, 0.0)
	get_nodes_in_group("laser").back()._physics_process(0.2)
	_check(not rocks.has(rock), "a laser impact still destroys the moon rock it hits")
	var base_target: StaticBody3D = _env.get("_base_target")
	_game.call("_spawn_laser", base_target.global_position + Vector3.LEFT * 4.0, Vector3.RIGHT, Color.CYAN, 0.0)
	get_nodes_in_group("laser").back()._physics_process(0.2)
	_check(_env.moonbase_hits() == 1, "a laser impact still registers on the moonbase target")


## True if the frozen lake (the big light-grey disc, drawn as a cylinder) is very dark.
func _lake_is_dark() -> bool:
	var props: Node = _env.get("_props")
	for child in props.get_children():
		if child is MeshInstance3D and child.mesh is CylinderMesh and is_equal_approx(child.mesh.top_radius, 9.5):
			var material := (child as MeshInstance3D).material_override as StandardMaterial3D
			return material != null and material.albedo_color.r < 0.2 and material.albedo_color.g < 0.2
	return false


## True if the moonbase dome and its parts are in the world.
func _moonbase_exists() -> bool:
	var props: Node = _env.get("_props")
	var base := props.find_child("MoonBase", true, false)
	if base == null:
		return false
	var dome := base.get_node_or_null("DomeVisual") as MeshInstance3D
	var material := dome.material_override as StandardMaterial3D if dome != null else null
	# The dome is see-through: a transparent glass, with no opaque shell hiding the inside.
	return material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
		and material.albedo_color.a < 0.2 \
		and base.get_node_or_null("DomeReflection") == null


## True if no ground, lake, pond or base part is blue (blue means much more blue than green or red).
func _pond_is_not_blue() -> bool:
	var props: Node = _env.get("_props")
	for mesh_node in props.find_children("*", "MeshInstance3D", true, false):
		var material := (mesh_node as MeshInstance3D).material_override as StandardMaterial3D
		if material == null:
			continue
		var c := material.albedo_color
		if c.b - c.g > 0.15 and c.b - c.r > 0.25:
			return false
	return true


func _remove_enemy_lasers() -> void:
	for node in get_nodes_in_group("enemy_laser"):
		node.queue_free()


## Enemy lasers still in the world. A node queued for deletion stays in its group until the frame ends.
func _live_enemy_laser_count() -> int:
	var count := 0
	for node in get_nodes_in_group("enemy_laser"):
		if not node.is_queued_for_deletion():
			count += 1
	return count


## True if some part of the model is painted a strong red.
func _has_red_surface(node: Node) -> bool:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surfaces := mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0
		for i in surfaces:
			var material := mesh_instance.get_surface_override_material(i) as StandardMaterial3D
			# Dark red: clearly red, with almost no green (green would push it toward orange).
			var c := material.albedo_color if material != null else Color.BLACK
			if material != null and c.r > 0.2 and c.g < c.r * 0.2 and c.b < c.r * 0.2:
				return true
	for child in node.get_children():
		if _has_red_surface(child):
			return true
	return false


## True if the edge walls exist, with collision, and nothing is drawn for them.
func _invisible_boundary() -> bool:
	var walls := get_nodes_in_group("boundary")
	if walls.size() != 4:
		return false
	for wall in walls:
		for child in wall.get_children():
			if child is MeshInstance3D:
				return false
	return true


func _laser_count() -> int:
	return get_nodes_in_group("laser").size()


func _laser_color_matches(color: Color) -> bool:
	for laser in get_nodes_in_group("laser"):
		var bolt := laser.get_node("Bolt") as MeshInstance3D
		var material := bolt.material_override as StandardMaterial3D
		return material != null and material.albedo_color.is_equal_approx(color)
	return false


func _key_for(action: String) -> int:
	var events := InputMap.action_get_events(action)
	return (events[0] as InputEventKey).physical_keycode if not events.is_empty() else -1


## Every gameplay action has a controller binding as well as its key, and Godot's
## built-in menu actions accept the D-pad and A button.
func _check_controller_bindings() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "fire",
			"interact", "sprint", "toggle_view", "pause", "look_left", "look_right", "look_up", "look_down"]:
		_check(_has_joy_event(action), "controller is bound to " + action)
	_check(_has_joy_event("ui_accept") and _has_joy_event("ui_down"), "menus accept the D-pad and A button")


func _has_joy_event(action: String) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false


func _button_for(action: String) -> int:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			return (event as InputEventJoypadButton).button_index
	return -1


func _joy_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


func _joy_button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


func _focus_name() -> String:
	var owner := root.gui_get_focus_owner()
	return owner.name if owner != null else ""


func _model() -> Node3D:
	return _player.get_node("Body/Model") as Node3D


func _terrain_normal_up() -> bool:
	var terrain := _env.get_node("Terrain")
	var visual := terrain.get_child(0) as MeshInstance3D
	var normals: PackedVector3Array = visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var total := 0.0
	for n in normals:
		total += n.y
	return total / normals.size() > 0.5


func _count_pink(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surfaces := mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0
		for i in surfaces:
			var material := mesh_instance.get_surface_override_material(i) as StandardMaterial3D
			if material != null and material.albedo_color.is_equal_approx(PINK_CHECK):
				count += 1
	for child in node.get_children():
		count += _count_pink(child)
	return count


func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("PASS  ", label)
	else:
		_failures.append(label)
		print("FAIL  ", label)


func _finish() -> void:
	print("")
	print("%d passed, %d failed" % [_passes, _failures.size()])
	for failure in _failures:
		print("  - ", failure)
	quit(0 if _failures.is_empty() else 1)
