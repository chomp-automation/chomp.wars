extends Area3D
## A laser bolt fired by the player. It flies straight, hits the first enemy it touches
## and then disappears. It also disappears after its lifetime runs out.

const SPEED := 45.0
const LIFETIME := 1.6

var max_distance := SPEED * LIFETIME
var _distance := 0.0
var _age := 0.0
var _direction := Vector3.FORWARD
var _spent := false

@onready var bolt: MeshInstance3D = $Bolt
@onready var glow: OmniLight3D = $Glow


func _ready() -> void:
	add_to_group("laser")
	collision_layer = 0
	collision_mask = 3  # enemy areas plus terrain bodies, rocks and the moonbase target
	monitoring = true
	monitorable = false
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


## Places the bolt at origin, aims it along direction and gives it the character's colour.
func launch(origin: Vector3, direction: Vector3, color: Color, charge: float = 0.0) -> void:
	# Scale visuals and hitbox together; full charge calls in a larger agent squad.
	scale = Vector3.ONE * lerpf(1.0, 4.0, clampf(charge, 0.0, 1.0))
	global_position = origin
	_direction = direction.normalized()
	look_at(global_position + _direction, Vector3.FORWARD if absf(_direction.y) > 0.99 else Vector3.UP)
	bolt.rotation_degrees = Vector3(90, 0, 0)  # the cylinder lies along the aim direction
	var material := StandardMaterial3D.new()
	# Unshaded, so the bolt keeps its colour whichever way it faces the sun.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	bolt.material_override = material
	if charge > 0.05:
		for i in 3:
			var agent := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.12
			sphere.height = 0.24
			agent.mesh = sphere
			agent.material_override = material
			var angle := TAU * float(i) / 3.0
			agent.position = Vector3(cos(angle) * 0.32, sin(angle) * 0.32, 0)
			add_child(agent)
	glow.light_color = color
	glow.light_energy = 3.0


func _physics_process(delta: float) -> void:
	if _spent:
		return
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	var travel := minf(SPEED * delta, max_distance - _distance)
	global_position += _direction * travel
	_distance += travel
	if _distance >= max_distance:
		queue_free()


func _on_area_entered(area: Area3D) -> void:
	if _spent or not area.is_in_group("enemy"):
		return
	_spent = true
	if area.has_method("hit"):
		area.hit()
	queue_free()


func _on_body_entered(body: Node3D) -> void:
	if _spent:
		return
	if not body.is_in_group("moon_rock") and not body.is_in_group("moonbase_target"):
		return
	_spent = true
	if body.is_in_group("moon_rock"):
		var environment := get_tree().get_first_node_in_group("environment")
		if environment != null:
			environment.destroy_rock(body)
	elif body.is_in_group("moonbase_target"):
		var environment := get_tree().get_first_node_in_group("environment")
		if environment != null:
			environment.hit_moonbase()
	queue_free()
