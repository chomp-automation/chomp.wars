extends SceneTree
## Records a 10-second clip of real gameplay for the README. It needs a display (it is not
## headless). Godot writes raw frames with its movie writer at a fixed 30 fps; compress.sh
## then turns them into a small MP4.
##
## Run from the repository root:
##   godot --path . --fixed-fps 30 --write-movie /tmp/chomp-raw.avi -s res://tools/record_gameplay.gd
##
## The clip starts with Chomp on the staged spot, holds Forward and Fire for 10 seconds, then quits.
## The first SETTLE_FRAMES are not part of the 10 seconds; the recording is trimmed to the action.

const SHOT_SIZE := Vector2i(1280, 720)
const FPS := 30
const SETTLE_FRAMES := 60  # about 2 seconds: let the scene load and the camera settle
const CLIP_FRAMES := 300  # 10 seconds at 30 fps
# Same staged spot as the screenshots: open ground, clear of the drones.
const START_SPOT := Vector2(0, 2)


func _initialize() -> void:
	DisplayServer.window_set_size(SHOT_SIZE)
	root.get_node("Game").selected_character = "chomp"
	var game: Node = load("res://scenes/MainGame.tscn").instantiate()
	root.add_child(game)
	await _frames(20)

	var environment: Node3D = game.get_node("Environment")
	var player: CharacterBody3D = game.get_node("Player")
	player.respawn(Vector3(START_SPOT.x, environment.get_height_at(START_SPOT.x, START_SPOT.y) + 0.5, START_SPOT.y))
	player.rotation.y = -PI / 2.0  # forward is +X

	await _frames(SETTLE_FRAMES)
	Input.action_press("move_forward")
	Input.action_press("fire")
	await _frames(CLIP_FRAMES)
	Input.action_release("fire")
	Input.action_release("move_forward")
	await _frames(5)

	print("Recorded ", CLIP_FRAMES, " frames at ", FPS, " fps")
	quit(0)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
