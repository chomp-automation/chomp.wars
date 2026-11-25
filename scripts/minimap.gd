extends Control
## Fixed north-up overview of the whole moon. Markers follow live world positions.

const EnvironmentLayout := preload("res://scripts/environment.gd")
const MAP_RECT := Rect2(12, 30, 216, 216)
const ISSUE_COLOR := Color("c18aff")
const ENEMY_COLOR := Color("ff6868")
var player: Node3D
var environment: Node3D


func _process(_delta: float) -> void:
	queue_redraw()


func world_to_map(point: Vector3) -> Vector2:
	var extent: float = EnvironmentLayout.WORLD_EDGE
	var normalized := (Vector2(point.x, point.z) + Vector2.ONE * extent) / (extent * 2.0)
	return MAP_RECT.position + normalized.clamp(Vector2.ZERO, Vector2.ONE) * MAP_RECT.size


func markers(group: StringName) -> Array[Node]:
	var result: Array[Node] = []
	for node in get_tree().get_nodes_in_group(group):
		if not node.is_queued_for_deletion():
			result.append(node)
	return result


func _draw() -> void:
	draw_style_box(_panel(), Rect2(Vector2.ZERO, size))
	var font := get_theme_default_font()
	draw_string(font, Vector2(12, 21), "MOON MAP                         N ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	draw_rect(MAP_RECT, Color("252833"))
	for fraction in [0.25, 0.5, 0.75]:
		var offset: Vector2 = MAP_RECT.size * fraction
		draw_line(MAP_RECT.position + Vector2(offset.x, 0), MAP_RECT.position + Vector2(offset.x, MAP_RECT.size.y), Color("363b48"))
		draw_line(MAP_RECT.position + Vector2(0, offset.y), MAP_RECT.position + Vector2(MAP_RECT.size.x, offset.y), Color("363b48"))
	if not is_instance_valid(player) or not is_instance_valid(environment):
		return
	var portal := world_to_map(Vector3(EnvironmentLayout.PORTAL_POSITION.x, 0, EnvironmentLayout.PORTAL_POSITION.y))
	var portal_color := Color("66ffe0") if environment.portal_active else Color("9299a8")
	draw_arc(portal, 6, 0, TAU, 24, portal_color, 2, true)
	for issue in markers(&"issue"):
		var point := world_to_map(issue.global_position)
		draw_rect(Rect2(point - Vector2(3, 4), Vector2(6, 8)), ISSUE_COLOR)
	for enemy in markers(&"enemy"):
		var point := world_to_map(enemy.global_position)
		draw_colored_polygon(PackedVector2Array([point + Vector2(0, -4), point + Vector2(4, 0), point + Vector2(0, 4), point + Vector2(-4, 0)]), ENEMY_COLOR)
	var location := world_to_map(player.global_position)
	var forward := Vector2(-sin(player.rotation.y), -cos(player.rotation.y))
	var side := forward.orthogonal()
	draw_circle(location, 7, Color.BLACK)
	draw_colored_polygon(PackedVector2Array([location + forward * 7, location - forward * 4 + side * 5, location - forward * 4 - side * 5]), Color.WHITE)
	draw_string(font, Vector2(12, 265), "▲ You    ◆ Enemy", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	draw_string(font, Vector2(12, 284), "▣ Issue", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ISSUE_COLOR)
	draw_string(font, Vector2(104, 284), "○ Portal", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, portal_color)


func _panel() -> StyleBoxFlat:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.035, 0.04, 0.06, 0.94)
	panel.set_border_width_all(1)
	panel.border_color = Color("677080")
	panel.set_corner_radius_all(8)
	return panel
