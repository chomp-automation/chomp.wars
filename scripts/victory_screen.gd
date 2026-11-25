extends Control
## Shown after the player collects all issues and walks through the exit portal.

@onready var stats_label: Label = $Center/Menu/Stats


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	Game.play_music()
	stats_label.text = "Issues collected: %d / %d   |   Enemies destroyed: %d   |   Score: %d\nPlaying as %s" % [
		Game.orbs_collected, Game.TOTAL_ORBS, Game.enemies_destroyed, Game.score,
		Game.CHARACTERS[Game.selected_character]]
	$Center/Menu/PlayAgainButton.pressed.connect(_on_play_again_pressed)
	$Center/Menu/MainMenuButton.pressed.connect(_on_main_menu_pressed)
	$Center/Menu/QuitButton.pressed.connect(get_tree().quit)
	$Center/Menu/PlayAgainButton.grab_focus()  # so a controller or keyboard can choose


func _on_play_again_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainGame.tscn")


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
