extends Area3D
## An evil chompbot: a larger copy of the mascot with red highlights and a ring of teeth.
## It roams the moonscape and strafes while firing red lasers at nearby players.

signal destroyed(enemy: Node3D)
signal fired(origin: Vector3, direction: Vector3)

const ChompModel := preload("res://scripts/chomp_model.gd")

const ENEMY_LAYER := 2  # collision layer that lasers look for
const MAX_HEALTH := 10
const BOT_SCALE := 2.4  # the model's size, relative to the player's (the player is 1.0)
const HOVER_HEIGHT := 1.8  # the centre sits this far above the ground (about 0.75 x BOT_SCALE)
const BODY_RADIUS := 2.1  # the laser target, in metres
const ROAM_RADIUS := 10.0  # metres from the home spot the bot wanders
const ROAM_SPEED := 3.2  # metres per second
const STRAFE_SPEED := 5.5
const PAUSE_MIN := 0.3
const PAUSE_MAX := 1.0
const FIRE_RANGE := 24.0  # the bot shoots only when the player is this close
const FIRE_COOLDOWN := 1.1
const TEETH_COUNT := 12

var enemy_name := "Evil Chompbot"
var health := MAX_HEALTH

var _environment  # the Environment node: get_height_at() and is_roam_clear()
var _home := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _model: Node3D
var _target := Vector2.ZERO
var _pause_left := 0.0
var _fire_cooldown := 0.0
var _strafe_direction := 1.0
var _player: Node3D
var _dead := false


## Call before adding the bot to the tree. home_position is where it starts and roams around.
func setup(home_position: Vector3, environment, seed_value: int) -> void:
	_home = home_position
	_environment = environment
	_rng.seed = seed_value


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("evil_bot")
	collision_layer = ENEMY_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	_build_visuals()
	_fire_cooldown = _rng.randf_range(0.7, FIRE_COOLDOWN)
	_pause_left = _rng.randf_range(0.0, PAUSE_MAX)
	_place_on_ground(Vector2(_home.x, _home.z))
	_pick_target()


func _process(delta: float) -> void:
	if _dead:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)

	if _player != null and _distance_to_player() < FIRE_RANGE:
		_strafe(delta)
		var player_point := Vector3(_player.global_position.x, position.y, _player.global_position.z)
		_face(player_point)
		if _fire_cooldown <= 0.0:
			_shoot()
		return

	if _pause_left > 0.0:
		_pause_left -= delta
		return

	var here := Vector2(position.x, position.z)
	var to_target := _target - here
	if to_target.length() < 0.3:
		_pause_left = _rng.randf_range(PAUSE_MIN, PAUSE_MAX)
		_pick_target()
		return
	var next := here + to_target.normalized() * minf(ROAM_SPEED * delta, to_target.length())
	_place_on_ground(next)
	_face(Vector3(_target.x, position.y, _target.y))


## Returns true if this hit destroyed the bot.
func hit() -> bool:
	if _dead:
		return false
	health -= 1
	if health > 0:
		return false
	_dead = true
	set_deferred("monitorable", false)
	_explode()
	destroyed.emit(self)
	queue_free()
	return true


func _distance_to_player() -> float:
	var offset := Vector2(_player.global_position.x - position.x, _player.global_position.z - position.z)
	return offset.length()


func _strafe(delta: float) -> void:
	var here := Vector2(position.x, position.z)
	var player_point := Vector2(_player.global_position.x, _player.global_position.z)
	var offset := here - player_point
	var radial := offset.normalized() if offset.length_squared() > 0.01 else Vector2.RIGHT
	var tangent := radial.orthogonal() * _strafe_direction
	var retreat := radial * clampf((8.0 - offset.length()) / 4.0, -0.5, 1.0)
	var centre := Vector2(_home.x, _home.z)
	var next := here + (tangent + retreat).normalized() * STRAFE_SPEED * delta
	if next.distance_to(centre) > ROAM_RADIUS + 4.0 or not _environment.is_roam_clear(next):
		_strafe_direction *= -1.0
		return
	_place_on_ground(next)


## Picks a new spot to walk to, a random point within ROAM_RADIUS that the terrain allows.
func _pick_target() -> void:
	var centre := _home
	for attempt in 30:
		var angle := _rng.randf() * TAU
		var distance := sqrt(_rng.randf()) * ROAM_RADIUS
		var point := Vector2(centre.x, centre.z) + Vector2(cos(angle), sin(angle)) * distance
		if _environment.is_roam_clear(point):
			_target = point
			return
	_target = Vector2(position.x, position.z)  # nowhere clear to go: stay put


func _place_on_ground(point: Vector2) -> void:
	var ground: float = _environment.get_height_at(point.x, point.y)
	position = Vector3(point.x, ground + HOVER_HEIGHT, point.y)


func _face(point: Vector3) -> void:
	if point.distance_to(global_position) > 0.01:
		look_at(point, Vector3.UP)


## Fires one red laser from the mouth towards the player's chest.
func _shoot() -> void:
	_fire_cooldown = FIRE_COOLDOWN
	var origin := global_position + Vector3(0, 0.3, 0)
	var aim := _player.global_position + Vector3(0, 1.0, 0) - origin
	fired.emit(origin, aim.normalized())


func _build_visuals() -> void:
	_model = ChompModel.new()
	_model.name = "Model"
	_model.character_id = "evil"
	_model.scale = Vector3.ONE * BOT_SCALE
	add_child(_model)
	_add_teeth()

	var shape := SphereShape3D.new()
	shape.radius = BODY_RADIUS
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)

	var glow := OmniLight3D.new()
	glow.light_color = Color(0.6, 0.0, 0.01)  # dark red, so it does not tint the body orange
	glow.light_energy = 0.8
	glow.omni_range = 6.0
	add_child(glow)


## A ring of white teeth round the lip, pointing in towards the middle of the mouth. They
## sit on the mouth pivot so they open and close with it.
func _add_teeth() -> void:
	var pivot: Node3D = _model.get_mouth_pivot()
	var parent: Node3D = pivot if pivot != null else _model
	var radius: float = _model.get_mouth_radius() * 0.85 if pivot != null else 0.5
	var across: float = _model.get_mouth_half_width() * 0.85 if pivot != null else 0.5
	# The pivot sits on the top edge of the lip, so the ring's middle is one lip-radius below it.
	var centre := Vector3(0.0, -radius if pivot != null else 0.0, 0.0)
	var tooth_mesh := CylinderMesh.new()
	tooth_mesh.top_radius = 0.0
	tooth_mesh.bottom_radius = radius * 0.1
	tooth_mesh.height = radius * 0.3
	tooth_mesh.radial_segments = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.96, 0.95, 0.9)
	material.roughness = 0.4
	for i in TEETH_COUNT:
		# Half-step offsets keep a tooth clear of straight up and straight down.
		var angle := TAU * (i + 0.5) / TEETH_COUNT
		# The lip ring lies in the face's plane (across the face along z, up along y), so the
		# teeth follow that ring rather than standing across the mouth.
		var offset := Vector3(0.0, sin(angle) * radius, cos(angle) * across)
		var spot := centre + offset
		var tooth := MeshInstance3D.new()
		tooth.mesh = tooth_mesh
		tooth.material_override = material
		tooth.position = spot
		tooth.quaternion = Quaternion(Vector3.UP, -offset.normalized())
		tooth.add_to_group("tooth")
		parent.add_child(tooth)


## A fireball-coloured burst, a flash of light and a few flying chunks, then the bot is gone.
func _explode() -> void:
	var stage := get_parent()
	var centre := global_position

	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.6, 0.2)
	flash.light_energy = 6.0
	flash.omni_range = 9.0
	stage.add_child(flash)
	flash.global_position = centre
	var flash_tween := flash.create_tween()
	flash_tween.tween_property(flash, "light_energy", 0.0, 0.5)
	flash_tween.tween_callback(flash.queue_free)

	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.9
	sphere.height = 1.8
	var ball_material := StandardMaterial3D.new()
	ball_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball_material.albedo_color = Color(1.0, 0.55, 0.15, 0.9)
	ball.mesh = sphere
	ball.material_override = ball_material
	stage.add_child(ball)
	ball.global_position = centre
	var ball_tween := ball.create_tween()
	ball_tween.set_parallel(true)
	ball_tween.tween_property(ball, "scale", Vector3.ONE * 3.5, 0.45)
	ball_tween.tween_property(ball_material, "albedo_color:a", 0.0, 0.45)
	ball_tween.chain().tween_callback(ball.queue_free)

	for i in 8:
		var angle := TAU * i / 8.0
		var direction := Vector3(cos(angle), 0.6, sin(angle)).normalized()
		var chunk := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.25
		var chunk_material := StandardMaterial3D.new()
		chunk_material.albedo_color = Color(0.4, 0.2, 0.2)
		chunk_material.emission_enabled = true
		chunk_material.emission = Color(1.0, 0.3, 0.1)
		chunk_material.emission_energy_multiplier = 1.5
		chunk.mesh = box
		chunk.material_override = chunk_material
		stage.add_child(chunk)
		chunk.global_position = centre
		var chunk_tween := chunk.create_tween()
		chunk_tween.tween_property(chunk, "global_position", centre + direction * 2.5, 0.5)
		chunk_tween.tween_callback(chunk.queue_free)
