extends Area3D
## A hovering saucer that follows and circles nearby players while firing red lasers.

signal destroyed(enemy: Node3D)
signal fired(origin: Vector3, direction: Vector3)

var enemy_name := "Drone"

const ENEMY_LAYER := 2  # collision layer that lasers look for
const MAX_HEALTH := 10
const DRIFT_RADIUS := 3.0
const BOB_HEIGHT := 0.65
const AGGRO_RANGE := 26.0
const HOME_RANGE := 36.0
const ORBIT_DISTANCE := 8.0
const FLIGHT_SPEED := 7.0
const FIRE_COOLDOWN := 1.4
const DEATH_TIME := 0.2

var home := Vector3.ZERO
var health := MAX_HEALTH
var _environment: Node
var _player: Node3D
var _phase := 0.0
var _time := 0.0
var _fire_cooldown: float
var _fire_interval: float
var _aggro_range: float
var _home_range: float
var _dead := false


## Call before adding the drone to the tree.
func setup(home_position: Vector3, phase: float, environment: Node = null) -> void:
	home = home_position
	_phase = phase
	_environment = environment


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("drone")
	collision_layer = ENEMY_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	position = home
	var difficulty := Game.difficulty_multiplier()
	health = Game.scaled_enemy_health(MAX_HEALTH, difficulty)
	_fire_interval = FIRE_COOLDOWN / difficulty
	_fire_cooldown = (FIRE_COOLDOWN + fposmod(_phase, 1.0)) / difficulty
	_aggro_range = AGGRO_RANGE * difficulty
	_home_range = HOME_RANGE * difficulty
	_build_visuals()


func _process(delta: float) -> void:
	if _dead:
		return
	_time += delta
	_fire_cooldown -= delta
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var centre := Vector2(home.x, home.z)
	var here := Vector2(position.x, position.z)
	var angle := _time * 1.2 + _phase
	var target := centre + Vector2(cos(angle), sin(angle)) * DRIFT_RADIUS
	if _player != null:
		var player_point := Vector2(_player.global_position.x, _player.global_position.z)
		if here.distance_to(player_point) <= _aggro_range and centre.distance_to(player_point) <= _home_range:
			var offset := here - player_point
			var radial := offset.normalized() if offset.length_squared() > 0.01 else Vector2.RIGHT
			var orbit := radial.rotated(0.55 if sin(_phase) >= 0.0 else -0.55)
			var orbit_distance := minf(ORBIT_DISTANCE, _aggro_range * 0.8)
			target = centre + (player_point + orbit * orbit_distance - centre).limit_length(_home_range)
			if _environment != null:
				var edge: float = _environment.HALF_EXTENT
				target = target.clamp(Vector2.ONE * -edge, Vector2.ONE * edge)
			if _fire_cooldown <= 0.0:
				var origin := global_position - Vector3.UP * 0.25
				fired.emit(origin, (_player.global_position + Vector3.UP - origin).normalized())
				_fire_cooldown = _fire_interval
	var next := here.move_toward(target, FLIGHT_SPEED * delta)
	var altitude := home.y
	if _environment != null:
		altitude = _environment.get_height_at(next.x, next.y) + _environment.ENEMY_HOVER_HEIGHT
	position = Vector3(next.x, altitude + sin(_time * 2.3 + _phase) * BOB_HEIGHT, next.y)
	rotate_y(delta * 1.8)


## Called by a laser when it hits. Returns true if this hit destroyed the drone.
func hit() -> bool:
	if _dead:
		return false
	health -= 1
	if health > 0:
		return false
	_dead = true
	set_deferred("monitorable", false)
	destroyed.emit(self)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.02, DEATH_TIME)
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
