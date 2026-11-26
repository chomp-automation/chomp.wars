extends Node3D
const ChompModel := preload("res://scripts/chomp_model.gd")
## Builds the low-poly moonscape at runtime: rolling hills and a few tall ones, craters, a dark
## frozen lake, a dark water pond (hazard), a domed moonbase on a flat pad, cliffs, rocks, a path,
## signposts, the start pad, the orb spots, the drone and evil chompbot spots, the exit portal and
## invisible walls at the edge. Terrain heights come from get_height_at(), so every placed object
## sits on the same ground the player walks on.

signal water_entered(body: Node3D)
signal portal_entered(body: Node3D)
signal base_hit()
signal trapped_chomps_released()
signal rocks_destroyed()

const TERRAIN_SIZE := 200  # height samples per side, 1 m apart
const HALF_EXTENT := (TERRAIN_SIZE - 1) / 2.0
const WORLD_EDGE := HALF_EXTENT + 0.5  # the invisible walls stand just outside the terrain
const ROCK_COUNT := 24  # a sparse scatter, so the moonscape is not cluttered
const ROCK_SPREAD := 92.0  # rocks are scattered within this many metres of the middle
const BASE_CENTER := Vector2(50, 5)  # the moonbase dome
const BASE_RADIUS := 7.0  # the dome's radius; the ground under it is levelled to a flat pad
const BASE_BLEND := 8.0  # the levelled pad slopes back into the hills over this many metres
const BASE_CLEARANCE := 10.0  # enemies and rocks keep this far from the base's edge

const LAKE_CENTER := Vector2(10, -18)
const LAKE_RADIUS := 11.0
const LAKE_LEVEL := -0.9
const POND_CENTER := Vector2(-8, -35)
const POND_RADIUS := 6.0
const POND_LEVEL := -1.6
const PORTAL_POSITION := Vector2(25, 40)

# Craters as (x, z, radius, depth).
const CRATERS := [
	Vector4(-20, -15, 6.0, 2.5),
	Vector4(25, -30, 8.0, 3.5),
	Vector4(-40, 10, 5.0, 2.0),
	Vector4(35, 15, 4.0, 1.5),
	Vector4(-65, -20, 7.0, 3.0),
	Vector4(55, 60, 6.0, 2.8),
	Vector4(-15, 60, 5.0, 2.2),
	Vector4(70, -35, 8.0, 3.6),
	Vector4(-75, 40, 6.0, 2.6),
	Vector4(40, -75, 6.0, 2.5),
]
# Tall hills as (x, z, radius, height). Each is a smooth bump; the steepest slope stays walkable.
const HILLS := [
	Vector4(-62, 52, 16.0, 20.0),
	Vector4(58, -58, 18.0, 18.0),
	Vector4(72, 22, 13.0, 15.0),
	Vector4(-70, -62, 17.0, 22.0),
	Vector4(18, 84, 15.0, 16.0),
	Vector4(-30, 82, 12.0, 14.0),
]
# The walkable path from the start pad to the portal.
const PATH_POINTS := [Vector2(0, 0), Vector2(4, 18), Vector2(12, 30), Vector2(25, 40)]
# Cliff walls as (x, z, length, yaw in degrees).
const CLIFFS := [
	Vector4(-16, 14, 12, 25),
	Vector4(30, -8, 8, 0),
	Vector4(-30, -20, 14, -20),
]
# Signposts as (x, z) with the text shown when the player presses interact nearby.
const SIGNS := [
	Vector2(3.5, 2.5),
	Vector2(-10, 30),
	Vector2(20, 22),
]
const SIGN_TEXTS := [
	"Welcome to the moon. Collect all 10 issues, then reach the glowing portal.",
	"Water resets you to the start. Stay on the ice and the hills.",
	"Cliffs are too steep to climb. Walk around them.",
]
# Where the 10 orbs are placed (x, z).
const ORB_POSITIONS := [
	Vector2(-12, 8),
	Vector2(8, 22),
	Vector2(-26, 30),
	Vector2(30, 5),
	Vector2(-38, -8),
	Vector2(18, -4),
	Vector2(-20, -28),
	Vector2(38, -22),
	Vector2(-2, -50),
	Vector2(45, 35),
]

# Where the hovering enemy drones patrol (x, z). They float above the ground at these spots.
const ENEMY_POSITIONS := [
	Vector2(-6, 15),
	Vector2(14, 12),
	Vector2(-22, 22),
	Vector2(32, -12),
	Vector2(-2, -44),
	Vector2(22, 38),
]
const ENEMY_HOVER_HEIGHT := 5.0
# Where the evil chompbots start. They roam about 10 m from each spot, on the ground.
const EVIL_BOT_POSITIONS := [
	Vector2(-14, -6),
	Vector2(-18, 36),
	Vector2(34, -40),
	Vector2(-48, -34),
	Vector2(46, 58),
]

# Moon rock shades: greys.
const ROCK_COLORS := [
	Color(0.50, 0.50, 0.52),
	Color(0.38, 0.38, 0.41),
	Color(0.60, 0.60, 0.62),
]

var start_position := Vector3.ZERO
var portal_active := false

var _noise := FastNoiseLite.new()
var _props: Node3D
var _portal: Node3D
var _portal_material: StandardMaterial3D
var _portal_light: OmniLight3D
var _nearby_sign_text := ""
var _rock_spots: Array[Vector3] = []  # (x, z, radius) of each rock, for roaming checks
var _panel_cache: ImageTexture
var _base_hits := 0
var _base_target: StaticBody3D
var _base_target_material: StandardMaterial3D
var _trapped_chomps: Node3D
var _released_chomps := false
var _rocks: Array[StaticBody3D] = []


func _init() -> void:
	_noise.seed = 1958
	_noise.frequency = 0.018
	_noise.fractal_octaves = 3


func _ready() -> void:
	add_to_group("environment")
	_props = Node3D.new()
	_props.name = "Props"
	add_child(_props)
	_build_terrain()
	_build_lake()
	_build_pond()
	_build_cliffs()
	_build_boundary()
	_build_signs()
	_build_base()
	_build_rocks()
	_build_start_pad()
	_build_portal()
	start_position = Vector3(0, get_height_at(0, 0) + 0.05, 0)


## Terrain height at a world (x, z) position. Used for building and for placing objects.
func get_height_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := _natural_height(p)
	# The moonbase stands on a levelled pad: the ground inside BASE_RADIUS sits at the pad's level.
	var pad_level := _natural_height(BASE_CENTER)
	h = lerpf(pad_level, h, smoothstep(BASE_RADIUS, BASE_RADIUS + BASE_BLEND, p.distance_to(BASE_CENTER)))
	var start_weight := clampf(1.0 - (p.length() - 3.0) / 4.0, 0.0, 1.0)
	return lerpf(h, 0.0, start_weight)


## Ground height before the moonbase pad and the start pad are levelled.
func _natural_height(p: Vector2) -> float:
	var h := _noise.get_noise_2d(p.x, p.y) * 6.0 + _noise.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.8
	for hill in HILLS:
		h += _hill_height(p, hill)
	for crater in CRATERS:
		h = _apply_crater(h, p, crater)
	h = _carve_basin(h, p, LAKE_CENTER, LAKE_RADIUS, LAKE_LEVEL, 0.8)
	h = _carve_basin(h, p, POND_CENTER, POND_RADIUS, -2.5, 0.7)
	return lerpf(h, 0.0, _path_weight(p) * 0.85)


func get_evil_bot_spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for p in EVIL_BOT_POSITIONS:
		points.append(Vector3(p.x, get_height_at(p.x, p.y), p.y))
	return points


## True if a roaming enemy may stand at this spot: inside the world, on open ground and clear of
## the lake, pond, cliffs, rocks and the start pad.
func is_roam_clear(p: Vector2) -> bool:
	if absf(p.x) > WORLD_EDGE - 4.0 or absf(p.y) > WORLD_EDGE - 4.0:
		return false
	if p.distance_to(LAKE_CENTER) < LAKE_RADIUS + 1.5 or p.distance_to(POND_CENTER) < POND_RADIUS + 1.5:
		return false
	if p.distance_to(BASE_CENTER) < BASE_RADIUS + BASE_CLEARANCE:
		return false
	if p.length() < 5.0:
		return false
	for cliff in CLIFFS:
		# Work out where the spot sits in the cliff's own, turned, frame.
		var theta := deg_to_rad(cliff.w)
		var d := p - Vector2(cliff.x, cliff.y)
		var local_x := d.x * cos(theta) - d.y * sin(theta)
		var local_z := d.x * sin(theta) + d.y * cos(theta)
		if absf(local_x) < cliff.z * 0.5 + 2.0 and absf(local_z) < 3.0:
			return false
	for rock in _rock_spots:
		if p.distance_to(Vector2(rock.x, rock.y)) < rock.z + 2.0:
			return false
	return true


func get_orb_spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for p in ORB_POSITIONS:
		points.append(Vector3(p.x, get_height_at(p.x, p.y) + 1.2, p.y))
	return points


func get_enemy_spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for p in ENEMY_POSITIONS:
		points.append(Vector3(p.x, get_height_at(p.x, p.y) + ENEMY_HOVER_HEIGHT, p.y))
	return points


## Opens or closes the exit portal. Only the portal's visuals and light change here.
func set_portal_active(active: bool) -> void:
	portal_active = active
	if active:
		_portal_material.albedo_color = Color(0.4, 1.0, 0.95)
		_portal_material.emission_enabled = true
		_portal_material.emission = Color(0.3, 1.0, 0.9)
		_portal_material.emission_energy_multiplier = 2.0
		_portal_light.light_energy = 3.0
	else:
		_portal_material.albedo_color = Color(0.3, 0.3, 0.35)
		_portal_material.emission_enabled = false
		_portal_light.light_energy = 0.0


## Text of the signpost the player is standing next to, or "" if none.
func nearby_sign_text() -> String:
	return _nearby_sign_text


## Height added by one smooth hill at p (a Gaussian bump).
func _hill_height(p: Vector2, hill: Vector4) -> float:
	var t: float = p.distance_to(Vector2(hill.x, hill.y)) / float(hill.z)
	return hill.w * exp(-0.5 * t * t)


func _apply_crater(h: float, p: Vector2, crater: Vector4) -> float:
	var t := p.distance_to(Vector2(crater.x, crater.y)) / crater.z
	if t < 1.0:
		return h - crater.w * (1.0 - t * t)
	if t < 1.3:
		return h + crater.w * 0.2 * sin(PI * (t - 1.0) / 0.3)
	return h


## Pulls the ground down to a flat floor inside the circle and blends it back out.
func _carve_basin(h: float, p: Vector2, center: Vector2, radius: float, floor_y: float, rim: float) -> float:
	var t := p.distance_to(center) / radius
	var target := floor_y
	if t > rim:
		target = lerpf(floor_y, 0.0, clampf((t - rim) / (1.0 - rim), 0.0, 1.0))
	var blended := minf(h, target)
	return lerpf(h, blended, 1.0 - smoothstep(1.0, 1.5, t))


func _path_weight(p: Vector2) -> float:
	var best := INF
	for i in range(PATH_POINTS.size() - 1):
		best = minf(best, _distance_to_segment(p, PATH_POINTS[i], PATH_POINTS[i + 1]))
	return 1.0 - smoothstep(1.5, 3.5, best)


func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _color_at(p: Vector2, h: float) -> Color:
	var col := Color(0.44, 0.44, 0.47)  # soft grey regolith, kept darker than before
	col = col.lerp(Color(0.56, 0.57, 0.60), clampf(h / 10.0, 0.0, 1.0))  # paler on the high ground
	col = col.lerp(Color(0.30, 0.30, 0.34), clampf(-h / 3.0, 0.0, 1.0))  # darker low ground
	for crater in CRATERS:
		# Craters are darker inside and on their rims, so they read clearly as craters.
		var t: float = p.distance_to(Vector2(crater.x, crater.y)) / float(crater.z)
		if t < 1.1:
			col = col.lerp(Color(0.26, 0.26, 0.29), (1.1 - t) / 1.1 * 0.7)
	col = col.lerp(Color(0.86, 0.74, 0.64), _path_weight(p) * 0.8)  # the path, a little dimmer than before
	var tint := _noise.get_noise_2d(p.x * 2.3, p.y * 2.3) * 0.05
	return Color(col.r + tint, col.g + tint, col.b + tint)


func _build_terrain() -> void:
	var heights := PackedFloat32Array()
	var colors := PackedColorArray()
	heights.resize(TERRAIN_SIZE * TERRAIN_SIZE)
	colors.resize(TERRAIN_SIZE * TERRAIN_SIZE)
	for zi in TERRAIN_SIZE:
		for xi in TERRAIN_SIZE:
			var p := Vector2(xi - HALF_EXTENT, zi - HALF_EXTENT)
			var h := get_height_at(p.x, p.y)
			heights[zi * TERRAIN_SIZE + xi] = h
			colors[zi * TERRAIN_SIZE + xi] = _color_at(p, h)

	# Flat-shaded triangles: each triangle gets its own vertices, so the lighting is faceted.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zi in TERRAIN_SIZE - 1:
		for xi in TERRAIN_SIZE - 1:
			_add_terrain_vertex(st, heights, colors, xi, zi)
			_add_terrain_vertex(st, heights, colors, xi + 1, zi)
			_add_terrain_vertex(st, heights, colors, xi, zi + 1)
			_add_terrain_vertex(st, heights, colors, xi + 1, zi)
			_add_terrain_vertex(st, heights, colors, xi + 1, zi + 1)
			_add_terrain_vertex(st, heights, colors, xi, zi + 1)
	st.generate_normals()
	var mesh := st.commit()

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95

	var terrain: StaticBody3D = $Terrain
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	terrain.add_child(visual)

	var shape := HeightMapShape3D.new()
	shape.map_width = TERRAIN_SIZE
	shape.map_depth = TERRAIN_SIZE
	shape.map_data = heights
	var collision := CollisionShape3D.new()
	collision.shape = shape
	terrain.add_child(collision)


func _add_terrain_vertex(st: SurfaceTool, heights: PackedFloat32Array, colors: PackedColorArray, xi: int, zi: int) -> void:
	var idx := zi * TERRAIN_SIZE + xi
	st.set_color(colors[idx])
	st.add_vertex(Vector3(xi - HALF_EXTENT, heights[idx], zi - HALF_EXTENT))


func _build_lake() -> void:
	var ice := CylinderMesh.new()
	ice.top_radius = 9.5
	ice.bottom_radius = 9.5
	ice.height = 0.12
	_add_decor(Vector3(LAKE_CENTER.x, LAKE_LEVEL, LAKE_CENTER.y), ice, _dark_ice_material())


func _build_pond() -> void:
	var water := CylinderMesh.new()
	water.top_radius = POND_RADIUS * 0.95
	water.bottom_radius = POND_RADIUS * 0.95
	water.height = 0.1
	_add_decor(Vector3(POND_CENTER.x, POND_LEVEL, POND_CENTER.y), water, _dark_ice_material())

	# Hazard volume: touching the water resets the player to the start.
	var area := Area3D.new()
	area.position = Vector3(POND_CENTER.x, -1.0, POND_CENTER.y)
	var shape := CylinderShape3D.new()
	shape.radius = POND_RADIUS
	shape.height = 2.0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)
	area.body_entered.connect(_on_water_body_entered)
	add_child(area)


func _build_cliffs() -> void:
	var material := _rock_material(Color(0.40, 0.40, 0.43))
	for cliff in CLIFFS:
		var x: float = cliff.x
		var z: float = cliff.y
		var size := Vector3(cliff.z, 4.0, 2.0)
		var pos := Vector3(x, get_height_at(x, z) + 1.5, z)
		_add_solid_box(pos, size, Vector3(0, cliff.w, 0), material)


## Invisible walls round the edge of the world. They stop the player walking off the terrain,
## but nothing is drawn.
func _build_boundary() -> void:
	var length := WORLD_EDGE * 2.0
	_add_invisible_wall(Vector3(-WORLD_EDGE, 5, 0), Vector3(1, 10, length))
	_add_invisible_wall(Vector3(WORLD_EDGE, 5, 0), Vector3(1, 10, length))
	_add_invisible_wall(Vector3(0, 5, -WORLD_EDGE), Vector3(length, 10, 1))
	_add_invisible_wall(Vector3(0, 5, WORLD_EDGE), Vector3(length, 10, 1))


func _build_signs() -> void:
	var post_material := _rock_material(Color(0.85, 0.85, 0.95))
	var panel_material := StandardMaterial3D.new()
	panel_material.albedo_color = Color(0.25, 0.95, 1.0)
	panel_material.emission_enabled = true
	panel_material.emission = Color(0.25, 0.95, 1.0)
	panel_material.emission_energy_multiplier = 1.2
	for i in SIGNS.size():
		var p: Vector2 = SIGNS[i]
		var base := Vector3(p.x, get_height_at(p.x, p.y), p.y)
		var post := BoxMesh.new()
		post.size = Vector3(0.15, 1.4, 0.15)
		_add_decor(base + Vector3(0, 0.7, 0), post, post_material)
		var panel := BoxMesh.new()
		panel.size = Vector3(0.9, 0.5, 0.08)
		_add_decor(base + Vector3(0, 1.4, 0), panel, panel_material)

		var area := Area3D.new()
		area.position = base + Vector3(0, 1.0, 0)
		var shape := SphereShape3D.new()
		shape.radius = 2.2
		var collision := CollisionShape3D.new()
		collision.shape = shape
		area.add_child(collision)
		var text: String = SIGN_TEXTS[i]
		area.body_entered.connect(_on_sign_body_entered.bind(text))
		area.body_exited.connect(_on_sign_body_exited)
		add_child(area)


func _build_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var placed := 0
	var attempts := 0
	while placed < ROCK_COUNT and attempts < 3000:
		attempts += 1
		var p := Vector2(rng.randf_range(-ROCK_SPREAD, ROCK_SPREAD), rng.randf_range(-ROCK_SPREAD, ROCK_SPREAD))
		if not _rock_location_ok(p):
			continue
		var radius := rng.randf_range(0.6, 2.0)
		var h := get_height_at(p.x, p.y)
		var rock_mesh := SphereMesh.new()
		rock_mesh.radius = radius
		rock_mesh.height = radius * 1.6
		rock_mesh.radial_segments = 6
		rock_mesh.rings = 4
		var material := _rock_material(ROCK_COLORS[rng.randi() % ROCK_COLORS.size()])
		var body := StaticBody3D.new()
		body.add_to_group("moon_rock")
		body.position = Vector3(p.x, h + radius * 0.5, p.y)
		var visual := MeshInstance3D.new()
		visual.mesh = rock_mesh
		visual.material_override = material
		body.add_child(visual)
		var shape := SphereShape3D.new()
		shape.radius = radius * 0.9
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		_props.add_child(body)
		_rocks.append(body)
		_rock_spots.append(Vector3(p.x, p.y, radius))
		placed += 1


func _rock_location_ok(p: Vector2) -> bool:
	if p.distance_to(LAKE_CENTER) < LAKE_RADIUS + 3.0:
		return false
	if p.distance_to(POND_CENTER) < POND_RADIUS + 3.0:
		return false
	if p.length() < 6.0:
		return false
	if p.distance_to(PORTAL_POSITION) < 6.0:
		return false
	if p.distance_to(BASE_CENTER) < BASE_RADIUS + BASE_CLEARANCE:
		return false
	if _path_weight(p) > 0.05:
		return false
	for orb in ORB_POSITIONS:
		if p.distance_to(orb) < 2.5:
			return false
	for sign_pos in SIGNS:
		if p.distance_to(sign_pos) < 2.5:
			return false
	return true


func _build_start_pad() -> void:
	var pad := CylinderMesh.new()
	pad.top_radius = 2.0
	pad.bottom_radius = 2.0
	pad.height = 0.05
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.95, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.45, 0.95, 1.0)
	material.emission_energy_multiplier = 0.6
	_add_decor(Vector3(0, get_height_at(0, 0) + 0.03, 0), pad, material)


func _build_portal() -> void:
	_portal = Node3D.new()
	var h := get_height_at(PORTAL_POSITION.x, PORTAL_POSITION.y)
	_portal.position = Vector3(PORTAL_POSITION.x, h + 2.0, PORTAL_POSITION.y)

	var ring := TorusMesh.new()
	ring.inner_radius = 1.2
	ring.outer_radius = 1.6
	_portal_material = StandardMaterial3D.new()
	var visual := MeshInstance3D.new()
	visual.mesh = ring
	visual.material_override = _portal_material
	visual.rotation_degrees = Vector3(90, 0, 0)  # stand the ring upright, facing +Z
	_portal.add_child(visual)

	_portal_light = OmniLight3D.new()
	_portal_light.light_color = Color(0.4, 1.0, 0.95)
	_portal_light.omni_range = 8.0
	_portal.add_child(_portal_light)

	var area := Area3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.2, 2.6, 0.8)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)
	area.body_entered.connect(_on_portal_body_entered)
	_portal.add_child(area)

	add_child(_portal)
	set_portal_active(false)


## Opaque charcoal for the frozen lake and the pond. Deliberately not blue.
func _dark_ice_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.13, 0.13, 0.14)
	material.roughness = 0.2
	material.metallic = 0.3
	return material


## The moonbase: a glass dome on a levelled pad, a metal base ring, an airlock, two solar panels
## and an antenna. The dome and the airlock have collision, so the player walks around them.
func _build_base() -> void:
	var pad_level := _natural_height(BASE_CENTER)
	var base := Node3D.new()
	base.name = "MoonBase"
	base.position = Vector3(BASE_CENTER.x, pad_level, BASE_CENTER.y)
	_props.add_child(base)

	var panel_material := StandardMaterial3D.new()
	panel_material.albedo_texture = _panel_texture()
	panel_material.uv1_scale = Vector3(2, 2, 2)
	panel_material.roughness = 0.55
	panel_material.metallic = 0.35

	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(0.30, 0.31, 0.34)
	ring_material.roughness = 0.6
	ring_material.metallic = 0.5

	# The glass is see-through, so the trapped Chomps and the moonscape inside show clearly. Only
	# a faint tint and the specular highlights mark the dome's surface.
	var glass_material := StandardMaterial3D.new()
	glass_material.albedo_color = Color(0.85, 0.9, 0.95, 0.12)
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.metallic = 0.0
	glass_material.roughness = 0.08
	glass_material.metallic_specular = 1.0
	glass_material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	glass_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# The dome: a full sphere with its lower half under the levelled pad, so only the top shows.
	var dome := SphereMesh.new()
	dome.radius = BASE_RADIUS
	dome.height = BASE_RADIUS * 2.0
	dome.radial_segments = 32
	dome.rings = 16
	var dome_visual := MeshInstance3D.new()
	dome_visual.name = "DomeVisual"
	dome_visual.mesh = dome
	dome_visual.material_override = glass_material
	base.add_child(dome_visual)
	var dome_body := StaticBody3D.new()
	var dome_shape := SphereShape3D.new()
	dome_shape.radius = BASE_RADIUS
	var dome_collision := CollisionShape3D.new()
	dome_collision.shape = dome_shape
	dome_body.add_child(dome_collision)
	base.add_child(dome_body)

	# Ten complete miniature Chomp models are trapped below the dome and wander around inside it.
	_trapped_chomps = Node3D.new()
	_trapped_chomps.name = "TrappedChomps"
	base.add_child(_trapped_chomps)
	for i in 10:
		var tiny := Node3D.new()
		tiny.name = "TrappedChomp%02d" % (i + 1)
		var model: Node3D = ChompModel.new()
		model.name = "Model"
		tiny.add_child(model)
		model.scale = Vector3.ONE * 0.36
		var angle := TAU * float(i) / 10.0
		tiny.position = Vector3(cos(angle) * 3.0, -2.1 + float(i % 2) * 0.65, sin(angle) * 3.0)
		_trapped_chomps.add_child(tiny)
		var wander := create_tween().set_loops()
		wander.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		wander.tween_property(tiny, "position", Vector3(cos(angle + 1.1) * 4.2, -2.1 + float(i % 2) * 0.65, sin(angle + 1.1) * 4.2), 2.4 + float(i % 3) * 0.35)
		wander.tween_property(tiny, "position", Vector3(cos(angle - 0.8) * 2.5, -2.1 + float(i % 2) * 0.65, sin(angle - 0.8) * 2.5), 2.1 + float(i % 4) * 0.25)

	_base_target = StaticBody3D.new()
	_base_target.name = "MoonBaseTarget"
	_base_target.add_to_group("moonbase_target")
	_base_target.position = Vector3(-BASE_RADIUS - 1.55, 3.2, 0)
	var target_mesh := SphereMesh.new()
	target_mesh.radius = 0.65
	target_mesh.height = 1.3
	_base_target_material = StandardMaterial3D.new()
	_base_target_material.albedo_color = Color(1.0, 0.2, 0.08)
	_base_target_material.emission_enabled = true
	_base_target_material.emission = Color(1.0, 0.08, 0.02)
	_base_target_material.emission_energy_multiplier = 1.5
	var target_visual := MeshInstance3D.new()
	target_visual.mesh = target_mesh
	target_visual.material_override = _base_target_material
	_base_target.add_child(target_visual)
	var target_collision := CollisionShape3D.new()
	var target_shape := SphereShape3D.new()
	target_shape.radius = 0.7
	target_collision.shape = target_shape
	_base_target.add_child(target_collision)
	base.add_child(_base_target)

	# A metal ring where the dome meets the ground.
	var ring := TorusMesh.new()
	ring.inner_radius = BASE_RADIUS - 0.25
	ring.outer_radius = BASE_RADIUS + 0.35
	var ring_visual := MeshInstance3D.new()
	ring_visual.mesh = ring
	ring_visual.material_override = ring_material
	ring_visual.position = Vector3(0, 0.15, 0)
	ring_visual.rotation_degrees = Vector3(90, 0, 0)
	base.add_child(ring_visual)

	# The airlock: a metal box against the dome with a lit door.
	var airlock_pos := Vector3(-BASE_RADIUS - 1.5, 1.4, 0)
	airlock_pos.y += _ground_offset(airlock_pos.x, airlock_pos.z)
	_add_solid_box_at(base, airlock_pos, Vector3(3.6, 2.8, 3.6), panel_material)
	var door := BoxMesh.new()
	door.size = Vector3(0.1, 2.0, 1.4)
	var door_material := StandardMaterial3D.new()
	door_material.albedo_color = Color(1.0, 0.95, 0.8)
	door_material.emission_enabled = true
	door_material.emission = Color(1.0, 0.9, 0.7)
	door_material.emission_energy_multiplier = 0.6
	var door_visual := MeshInstance3D.new()
	door_visual.mesh = door
	door_visual.material_override = door_material
	door_visual.position = airlock_pos + Vector3(-1.85, -0.2, 0)
	base.add_child(door_visual)

	# Two solar panels on short legs, tilted towards the sun.
	for side in [-1.0, 1.0]:
		var foot := Vector3(3.0 * side, 0, 9.5)
		foot.y = _ground_offset(foot.x, foot.z)
		var panel := BoxMesh.new()
		panel.size = Vector3(4.0, 0.12, 2.2)
		var panel_visual := MeshInstance3D.new()
		panel_visual.mesh = panel
		panel_visual.material_override = _solar_material()
		panel_visual.position = foot + Vector3(0, 2.6, 0)
		panel_visual.rotation_degrees = Vector3(-25, 0, 0)
		base.add_child(panel_visual)
		var leg := BoxMesh.new()
		leg.size = Vector3(0.15, 2.4, 0.15)
		var leg_visual := MeshInstance3D.new()
		leg_visual.mesh = leg
		leg_visual.material_override = ring_material
		leg_visual.position = foot + Vector3(0, 1.2, 0)
		base.add_child(leg_visual)

	# A tall antenna with a small warning light.
	var mast := CylinderMesh.new()
	mast.top_radius = 0.06
	mast.bottom_radius = 0.1
	mast.height = 6.0
	var mast_visual := MeshInstance3D.new()
	mast_visual.mesh = mast
	mast_visual.material_override = ring_material
	var mast_foot := Vector3(4.5, 0, -4.5)
	mast_foot.y = _ground_offset(mast_foot.x, mast_foot.z)
	mast_visual.position = mast_foot + Vector3(0, 3.0, 0)
	base.add_child(mast_visual)
	var tip := SphereMesh.new()
	tip.radius = 0.15
	tip.height = 0.3
	var tip_material := StandardMaterial3D.new()
	tip_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tip_material.albedo_color = Color(1.0, 0.25, 0.2)
	var tip_visual := MeshInstance3D.new()
	tip_visual.mesh = tip
	tip_visual.material_override = tip_material
	tip_visual.position = mast_foot + Vector3(0, 6.1, 0)
	base.add_child(tip_visual)


func _solar_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.16, 0.18)
	material.metallic = 0.6
	material.roughness = 0.25
	material.albedo_texture = _panel_texture()
	return material


## A procedural metal-panel texture: grey plating with seams, rivets and a little grime, made in
## code so the game needs no image files.
func _panel_texture() -> ImageTexture:
	if _panel_cache != null:
		return _panel_cache
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in size:
		for x in size:
			var shade := 0.66 + rng.randf_range(-0.03, 0.03)
			var seam := x % 32 == 0 or y % 32 == 0
			if seam:
				shade = 0.32
			elif (x % 32 == 16 and y % 32 == 16):
				shade = 0.45  # rivet
			elif rng.randf() < 0.02:
				shade -= 0.12  # scuffs
			image.set_pixel(x, y, Color(shade, shade, shade * 1.02))
	_panel_cache = ImageTexture.create_from_image(image)
	return _panel_cache


## How much higher (or lower) the ground is at this world spot than the levelled pad, so
## props placed out on the blend slope can stand on the ground rather than float or sink.
func _ground_offset(x: float, z: float) -> float:
	return get_height_at(BASE_CENTER.x + x, BASE_CENTER.y + z) - _natural_height(BASE_CENTER)


## Collision and a visible box for a static block, placed in the base's own frame.
func _add_solid_box_at(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var box := BoxMesh.new()
	box.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = box
	visual.material_override = material
	body.add_child(visual)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


func _rock_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


func hit_moonbase() -> void:
	if _released_chomps:
		return
	_base_hits += 1
	base_hit.emit()
	if _base_hits >= 10:
		release_trapped_chomps()


func moonbase_hits() -> int:
	return _base_hits


func release_trapped_chomps() -> void:
	if _released_chomps:
		return
	_released_chomps = true
	for i in _trapped_chomps.get_child_count():
		var tiny := _trapped_chomps.get_child(i) as Node3D
		var angle := TAU * float(i) / 10.0
		tiny.position = Vector3(cos(angle) * (BASE_RADIUS + 3.0), 0.5, sin(angle) * (BASE_RADIUS + 3.0))
	trapped_chomps_released.emit()


func destroy_rock(rock: StaticBody3D) -> void:
	if not is_instance_valid(rock):
		return
	for i in range(_rocks.size() - 1, -1, -1):
		if _rocks[i] == rock:
			var p := rock.position
			for j in range(_rock_spots.size() - 1, -1, -1):
				if Vector2(_rock_spots[j].x, _rock_spots[j].y).distance_to(Vector2(p.x, p.z)) < 0.01:
					_rock_spots.remove_at(j)
					break
			_rocks.remove_at(i)
			rock.queue_free()
			rocks_destroyed.emit()
			return


## Visual-only mesh with no collision.
func _add_decor(pos: Vector3, mesh: Mesh, material: Material) -> void:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.position = pos
	_props.add_child(visual)


## Collision only, with nothing drawn: the walls at the edge of the world.
func _add_invisible_wall(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.add_to_group("boundary")
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	_props.add_child(body)


## Box mesh with collision: cliffs.
func _add_solid_box(pos: Vector3, size: Vector3, rot_deg: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot_deg
	var box := BoxMesh.new()
	box.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = box
	visual.material_override = material
	body.add_child(visual)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	_props.add_child(body)


func _on_water_body_entered(body: Node3D) -> void:
	water_entered.emit(body)


func _on_portal_body_entered(body: Node3D) -> void:
	portal_entered.emit(body)


func _on_sign_body_entered(body: Node3D, text: String) -> void:
	if body.is_in_group("player"):
		_nearby_sign_text = text


func _on_sign_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_nearby_sign_text = ""
