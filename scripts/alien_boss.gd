extends Area3D
## Portal guardian that strafes after emerging and cycles between three attack patterns.

signal destroyed(enemy: Node3D)
signal fired(origin: Vector3, direction: Vector3)
signal health_changed(current: int, maximum: int)

const MAX_HEALTH := 300
const FIRE_COOLDOWN := 1.35
const WOUNDED_FIRE_COOLDOWN := 0.85
const BURST_INTERVAL := 0.18
var health := MAX_HEALTH
var max_health := MAX_HEALTH
var enemy_name := "Alien Overlord"
var _attack_index := 0
var _burst_remaining := 0
var _burst_timer := 0.0
var _cooldown := 2.0
var _emergence := 0.0
var _strafe_time := 0.0
var _portal := Vector3.ZERO
var _environment: Node
var _health_label: Label3D
var _difficulty: float


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("boss")
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	_difficulty = Game.difficulty_multiplier()
	max_health = Game.scaled_enemy_health(MAX_HEALTH, _difficulty)
	health = max_health
	_portal = position
	_environment = get_tree().get_first_node_in_group("environment")
	# Oversized green head, black almond eyes, torso, long arms and legs.
	_part(Vector3(0, 4.8, 0), Vector3(1.7, 1.9, 1.2), Color(0.35, 0.8, 0.25))
	_part(Vector3(0, 2.6, 0), Vector3(1.1, 1.8, 0.8), Color(0.2, 0.42, 0.17))
	for side in [-1.0, 1.0]:
		_part(Vector3(side * 0.7, 5, -0.95), Vector3(0.55, 0.8, 0.2), Color(0.02, 0.02, 0.03))
		_part(Vector3(side * 1.5, 2.7, 0), Vector3(0.35, 1.8, 0.35), Color(0.35, 0.8, 0.25))
		_part(Vector3(side * 0.65, 0.9, 0), Vector3(0.45, 1.5, 0.45), Color(0.35, 0.8, 0.25))
	var shape := CapsuleShape3D.new()
	shape.radius = 1.8
	shape.height = 7.0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 3.0
	add_child(collision)
	_health_label = Label3D.new()
	_health_label.position.y = 7.2
	_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_health_label.font_size = 48
	add_child(_health_label)
	_update_health()


func _process(delta: float) -> void:
	if health <= 0:
		return
	# Walk out of the portal before attacking, leaving the portal visible behind.
	_strafe_time += maxf(delta - (2.0 - _emergence), 0.0)
	_emergence = minf(_emergence + delta, 2.0)
	position = _portal + Vector3(sin(_strafe_time * 1.5) * 4.5, 0,
		_emergence * 3.0 + sin(_strafe_time * 2.3) * 1.5)
	if _environment != null:
		position.y = _environment.get_height_at(position.x, position.z)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var target := Vector3(player.global_position.x, global_position.y, player.global_position.z)
	if target.distance_squared_to(global_position) > 0.01:
		look_at(target)
	if _burst_remaining > 0:
		_burst_timer -= delta
		if _burst_timer <= 0:
			_fire_aimed(player.global_position + Vector3.UP)
			_burst_remaining -= 1
			_burst_timer = BURST_INTERVAL / _difficulty
	_cooldown -= delta
	if _emergence >= 2.0 and _cooldown <= 0:
		attack(player.global_position + Vector3.UP)
		var interval := WOUNDED_FIRE_COOLDOWN if health <= max_health / 2 else FIRE_COOLDOWN
		_cooldown = interval / _difficulty


func attack(target: Vector3) -> void:
	if health <= 0:
		return
	var origin := global_position + Vector3(0, 3.0, 0)
	Game.play_sfx("boss_attack")
	var direction := (target - origin).normalized()
	match _attack_index % 3:
		0:
			for angle in [-0.12, 0.0, 0.12]:
				fired.emit(origin, direction.rotated(Vector3.UP, angle))
		1:
			# A low ring covers every escape direction but leaves gaps to dodge.
			for i in 12:
				fired.emit(global_position + Vector3.UP, Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 12.0))
		2:
			# Re-aim each shot rather than firing at the player's old position.
			_fire_aimed(target)
			_burst_remaining = 3
			_burst_timer = BURST_INTERVAL / _difficulty
	_attack_index += 1


func _fire_aimed(target: Vector3) -> void:
	var origin := global_position + Vector3(0, 3.0, 0)
	fired.emit(origin, (target - origin).normalized())


func hit() -> bool:
	if health <= 0:
		return false
	health -= 1
	Game.play_sfx("boss_hit")
	health_changed.emit(health, max_health)
	_update_health()
	if health > 0:
		return false
	set_deferred("monitorable", false)
	destroyed.emit(self)
	queue_free()
	return true


func _update_health() -> void:
	_health_label.text = "ALIEN OVERLORD  %d / %d" % [health, max_health]


func _part(offset: Vector3, size: Vector3, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = offset
	visual.scale = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	visual.material_override = material
	add_child(visual)
