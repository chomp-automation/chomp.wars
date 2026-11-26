extends "res://scripts/projectile.gd"
## A red laser that bursts into a flash when it hits the player or solid cover.

signal player_hit

const SPEED := 22.0  # metres per second: slower than the player's laser, so it can be dodged
const LIFETIME := 4.0
const LENGTH := 2.6
const RADIUS := 0.12
const BEAM_COLOR := Color(1.0, 0.1, 0.08)

var _age := 0.0
var _direction := Vector3.FORWARD


func _ready() -> void:
	add_to_group("enemy_laser")
	_configure_sweep(1, RADIUS * 3.0)  # World bodies and the player.
	_build_visuals()


## Places the bolt at origin and aims it along direction.
func launch(origin: Vector3, direction: Vector3) -> void:
	global_position = origin
	_direction = direction.normalized()
	look_at(global_position + _direction, Vector3.FORWARD if absf(_direction.y) > 0.99 else Vector3.UP)


func _physics_process(delta: float) -> void:
	if is_queued_for_deletion():
		return
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	var impact := _advance(_direction * SPEED * delta)
	if impact == null:
		return
	if impact.is_in_group("player"):
		player_hit.emit()
	_burst()
	queue_free()


func _build_visuals() -> void:
	# A thin, bright red bolt along the aim direction, with a red glow around it.
	var bolt := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = RADIUS
	cylinder.bottom_radius = RADIUS
	cylinder.height = LENGTH
	cylinder.radial_segments = 8
	bolt.mesh = cylinder
	bolt.rotation_degrees = Vector3(90, 0, 0)  # the cylinder lies along the aim direction
	bolt.position.z = LENGTH * 0.5
	bolt.material_override = _unshaded(BEAM_COLOR)
	add_child(bolt)

	var glow := OmniLight3D.new()
	glow.light_color = BEAM_COLOR
	glow.light_energy = 2.0
	glow.omni_range = 4.0
	add_child(glow)


func _unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


## A short red flash where the laser ended, so a hit or a miss is easy to see.
func _burst() -> void:
	var stage := get_parent()
	if stage == null:
		return
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	var material := _unshaded(Color(1.0, 0.1, 0.08, 0.9))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.mesh = sphere
	flash.material_override = material
	stage.add_child(flash)
	flash.global_position = global_position
	var tween := flash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 3.0, 0.3)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.3)
	tween.chain().tween_callback(flash.queue_free)
