extends Area3D
## Sweeps the bolt's cross-section from its nose to the next position each physics tick.

var _sweep: ShapeCast3D


func _configure_sweep(mask: int, width: float, hit_areas: bool = false) -> void:
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, width, 0.02)
	_sweep = ShapeCast3D.new()
	_sweep.shape = shape
	_sweep.collision_mask = mask
	_sweep.collide_with_areas = hit_areas
	_sweep.enabled = false  # Only query when the projectile advances.
	add_child(_sweep)


## Returns the first impact, giving solid cover priority when contacts coincide.
func _advance(motion: Vector3) -> Node3D:
	# A sweep can skip a collider that already overlaps the nose, for example at launch.
	_sweep.target_position = Vector3.ZERO
	_sweep.force_shapecast_update()
	if not _sweep.is_colliding():
		_sweep.target_position = to_local(global_position + motion)
		_sweep.force_shapecast_update()
		global_position += motion * _sweep.get_closest_collision_safe_fraction()
	var impact: Node3D
	for i in _sweep.get_collision_count():
		var collider := _sweep.get_collider(i) as Node3D
		if collider is PhysicsBody3D and not collider.is_in_group("player"):
			return collider
		impact = collider
	return impact
