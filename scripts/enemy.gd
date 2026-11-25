extends Area3D
## A hovering enemy drone. It drifts and bobs around its home point. One laser hit destroys
## it and scores points (see game_state.gd). Drones do not hurt the player.

signal destroyed(enemy: Node3D)

var enemy_name := "Drone"

const ENEMY_LAYER := 2  # collision layer that lasers look for
const DRIFT_RADIUS := 1.8
const BOB_HEIGHT := 0.35
const DEATH_TIME := 0.2

var home := Vector3.ZERO
var _phase := 0.0
var _time := 0.0
var _dead := false


## Call before adding the drone to the tree.
func setup(home_position: Vector3, phase: float) -> void:
	home = home_position
	_phase = phase


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("drone")
	collision_layer = ENEMY_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	position = home
	_build_visuals()


func _process(delta: float) -> void:
	if _dead:
		return
	_time += delta
	var angle := _time * 0.6 + _phase
	position = home + Vector3(cos(angle) * DRIFT_RADIUS, sin(_time * 1.3 + _phase) * BOB_HEIGHT,
			sin(angle) * DRIFT_RADIUS)
	rotate_y(delta * 0.8)


## Called by a laser when it hits. Returns true if this hit destroyed the drone.
func hit() -> bool:
	if _dead:
		return false
	_dead = true
	set_deferred("monitorable", false)
	destroyed.emit(self)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, DEATH_TIME)
	tween.tween_callback(queue_free)
	return true


func _build_visuals() -> void:
	# Broad saucer hull, raised cockpit and a ring of engine lights.
	var hull := CylinderMesh.new()
	hull.top_radius = 0.55
	hull.bottom_radius = 1.15
	hull.height = 0.3
	_part(hull, Vector3.ZERO, Vector3.ONE, Color(0.55, 0.6, 0.7))
	var dome := SphereMesh.new()
	dome.radius = 0.5
	dome.height = 1.0
	_part(dome, Vector3(0, 0.22, 0), Vector3(1, 0.6, 1), Color(0.2, 0.9, 0.8))
	for i in 8:
		var lamp := SphereMesh.new()
		lamp.radius = 0.1
		lamp.height = 0.2
		var angle := TAU * i / 8.0
		_part(lamp, Vector3(cos(angle), -0.08, sin(angle)), Vector3.ONE, Color(1, 0.45, 0.2), 4.0)

	var shape := SphereShape3D.new()
	shape.radius = 1.15
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)

	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.5, 0.25)
	glow.light_energy = 0.8
	glow.omni_range = 4.0
	add_child(glow)


func _material(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.metallic = 0.4
	material.roughness = 0.5
	if energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = energy
	return material


func _part(mesh: Mesh, offset: Vector3, size: Vector3, color: Color, emission: float = 0.0) -> void:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = offset
	visual.scale = size
	visual.material_override = _material(color, color, emission)
	add_child(visual)
