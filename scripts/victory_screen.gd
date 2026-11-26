extends Control
## Shown after the player clears a level and walks through the exit portal.

const GAME_SCENE := "res://scenes/MainGame.tscn"

@onready var stats_label: Label = $Center/Menu/Stats


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	Game.play_music()
	$Center/Menu/Title.text = "Level %d completed!" % Game.level
	$Center/Menu/NextLevelButton.text = "Start Level %d" % (Game.level + 1)
	stats_label.text = "Issues collected: %d / %d   |   Enemies destroyed: %d   |   Score: %d\nPlaying as %s" % [
		Game.orbs_collected, Game.TOTAL_ORBS, Game.enemies_destroyed, Game.score,
		Game.CHARACTERS[Game.selected_character]]
	$Center/Menu/PlayAgainButton.pressed.connect(_on_play_again_pressed)
	$Center/Menu/NextLevelButton.pressed.connect(_on_next_level_pressed)
	$Center/Menu/MainMenuButton.pressed.connect(_on_main_menu_pressed)
	$Center/Menu/QuitButton.pressed.connect(get_tree().quit)
	$Center/Menu/NextLevelButton.grab_focus()


func _on_next_level_pressed() -> void:
	if get_tree().change_scene_to_file(GAME_SCENE) == OK:
		Game.level += 1


func _on_play_again_pressed() -> void:
	Game.reset_run()
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
