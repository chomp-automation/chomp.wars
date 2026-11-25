extends SceneTree
## Saves the three README screenshots from the real game. It needs a display (it is not
## headless), and it writes into screencaps/.
##
## Run from the repository root:
##   godot --path . -s res://tools/capture_screencaps.gd
##
## 1. The opening screen. 2. Chomp firing a cyan laser. 3. Mrs. Chomp firing a pink laser.
## 4. An evil chompbot, facing the player with its mouth open.

const OUT_DIR := "res://screencaps"
const SHOT_SIZE := Vector2i(1920, 1080)
# The staged shots fire east across open ground, clear of the drones, so the bolt stays visible.
const SHOT_SPOT := Vector2(0, 2)


func _initialize() -> void:
	DisplayServer.window_set_size(SHOT_SIZE)
	print("Screen size: ", DisplayServer.screen_get_size())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await _frames(10)

	var menu: Node = load("res://scenes/MainMenu.tscn").instantiate()
	root.add_child(menu)
	await _frames(90)  # let the previews turn and chomp
	await _save("01-opening-screen")
	root.remove_child(menu)
	menu.free()

	for id in ["chomp", "mrs_chomp"]:
		await _staged_laser_shot(id)

	await _evil_chompbot_shot()

	print("Saved screenshots to ", ProjectSettings.globalize_path(OUT_DIR))
	quit(0)


func _staged_laser_shot(character_id: String) -> void:
	var game_state := root.get_node("Game")
	game_state.selected_character = character_id
	var game: Node = load("res://scenes/MainGame.tscn").instantiate()
	root.add_child(game)
	await _frames(20)

	var environment: Node3D = game.get_node("Environment")
	var player: CharacterBody3D = game.get_node("Player")
	var spot := SHOT_SPOT
	player.respawn(Vector3(spot.x, environment.get_height_at(spot.x, spot.y) + 0.5, spot.y))
	player.rotation.y = -PI / 2.0  # forward is +X
	await _frames(60)

	# A bolt flies away from the third-person camera, so it looks like a dot in the picture.
	# For the still, launch it from the side of the character at an angle, so the beam reads.
	var origin := player.global_position + Vector3(0.3, 1.3, 0)
	var direction := Vector3(0.5, 0.0, -0.87)
	game.call("_on_player_fired", origin, direction, character_id)
	await _frames(1)
	for laser in get_nodes_in_group("laser"):
		laser.global_position = origin + direction * 4.0
	await _frames(1)
	await _save("0%d-%s-firing-laser" % [2 if character_id == "chomp" else 3, character_id.replace("_", "-")])

	root.remove_child(game)
	game.free()
	await _frames(10)


## Stages an evil chompbot a few metres ahead of the player, turned to face the camera, with
## its mouth open. Its roaming and firing are switched off so it holds still for the picture.
func _evil_chompbot_shot() -> void:
	root.get_node("Game").selected_character = "chomp"
	var game: Node = load("res://scenes/MainGame.tscn").instantiate()
	root.add_child(game)
	await _frames(20)

	var environment: Node3D = game.get_node("Environment")
	var player: CharacterBody3D = game.get_node("Player")
	player.respawn(Vector3(SHOT_SPOT.x, environment.get_height_at(SHOT_SPOT.x, SHOT_SPOT.y) + 0.5, SHOT_SPOT.y))
	player.rotation.y = -PI / 2.0  # forward is +X
	var bots := get_nodes_in_group("evil_bot")
	if bots.is_empty():
		push_error("No evil chompbot to photograph")
		quit(1)
		return
	var bot: Node3D = bots[0]
	bot.set_process(false)
	var bot_x := SHOT_SPOT.x + 7.0
	bot.position = Vector3(bot_x, environment.get_height_at(bot_x, SHOT_SPOT.y) + 1.8, SHOT_SPOT.y)
	bot.call("_face", player.global_position)
	var model: Node3D = bot.get_node("Model")
	model.call("set_mouth_open", 1.0)
	await _frames(60)
	await _save("04-evil-chompbot")

	root.remove_child(game)
	game.free()
	await _frames(10)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [ProjectSettings.globalize_path(OUT_DIR), name]
	image.save_png(path)
	print("Saved ", path, " (", image.get_size(), ")")


func _frames(count: int) -> void:
	for i in count:
		await process_frame
