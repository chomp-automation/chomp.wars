extends "res://scripts/projectile.gd"
## A laser bolt fired by the player. It stops on enemies and solid cover or when it reaches its range limit.

const SPEED := 45.0
const LIFETIME := 1.6

var max_distance := SPEED * LIFETIME
var _distance := 0.0
var _direction := Vector3.FORWARD

@onready var bolt: MeshInstance3D = $Bolt
@onready var glow: OmniLight3D = $Glow


func _ready() -> void:
	add_to_group("laser")
	_configure_sweep(3, 0.25, true)  # World bodies and enemy areas.
	var player := get_tree().get_first_node_in_group("player") as PhysicsBody3D
	if player != null:
		_sweep.add_exception(player)


## Places the bolt at origin, aims it along direction and gives it the character's colour.
func launch(origin: Vector3, direction: Vector3, color: Color, charge: float = 0.0) -> void:
	# Scale visuals and hitbox together; full charge calls in a larger agent squad.
	scale = Vector3.ONE * lerpf(1.0, 4.0, clampf(charge, 0.0, 1.0))
	global_position = origin
	_direction = direction.normalized()
	look_at(global_position + _direction, Vector3.FORWARD if absf(_direction.y) > 0.99 else Vector3.UP)
	bolt.rotation_degrees = Vector3(90, 0, 0)  # the cylinder lies along the aim direction
	bolt.position.z = 1.2  # The visual trails the swept nose.
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
			agent.position = Vector3(cos(angle) * 0.32, sin(angle) * 0.32, 1.2)
			add_child(agent)
	glow.light_color = color
	glow.light_energy = 3.0


func _physics_process(delta: float) -> void:
	if is_queued_for_deletion():
		return
	var travel := minf(SPEED * delta, max_distance - _distance)
	var impact := _advance(_direction * travel)
	if impact != null:
		_hit(impact)
		queue_free()
		return
	_distance += travel
	if _distance >= max_distance:
		queue_free()


func _hit(impact: Node3D) -> void:
	if impact.is_in_group("enemy") and impact.has_method("hit"):
		impact.hit()
	var environment := get_tree().get_first_node_in_group("environment")
	if environment != null:
		if impact.is_in_group("moon_rock"):
			environment.destroy_rock(impact)
		elif impact.is_in_group("moonbase_target"):
			environment.hit_moonbase()
