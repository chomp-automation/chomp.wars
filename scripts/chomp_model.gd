extends Node3D
## The mascot model, shared by the playable character, the start-screen previews and the
## evil chompbots. Chomp and Mrs. Chomp use the same mesh. Mrs. Chomp has cyan parts recoloured
## pink, and an evil chompbot has them recoloured red. The mouth opens and closes like a jaw: the
## top of the mouth stays put and the bottom swings up to meet it. The model file holds the body
## once per mouth step (BodyStage_0 = open ... last = shut; the model is supplied pre-built),
## and the lip ring has a matching shape key per step. One body step is shown at a time.
## The inside of the mouth (a teal glow with a round black throat) is a shader, because Blender's
## shader nodes are not exported to glTF.

const MODEL_PATH := "res://assets/models/chomp_mascot.glb.bin"
const PINK := Color(1.0, 0.36, 0.72)
const PINK_EMISSION := Color(1.0, 0.45, 0.80)
const RED := Color(0.28, 0.0, 0.01)  # dark red, not orange
const RED_EMISSION := Color(0.4, 0.0, 0.01)
const MOUTH_SHADER := preload("res://shaders/mouth_interior.gdshader")
const MOUTH_INTERIOR_MATERIAL := "Mouth_Interior"  # the glTF material name of the mouth's inside
const MOUTH_TEAL := Color(0.001, 0.42, 0.48)
const MOUTH_PINK := Color(0.62, 0.12, 0.38)
const MOUTH_RED := Color(0.3, 0.0, 0.01)
const MATTE_ROUGHNESS := 0.55  # near-black parts get little shine, so they read as deep black
const TEETH_CLOSED_SCALE := 0.05  # an evil chompbot's teeth fold almost flat when its mouth is shut

var character_id := "chomp":
	set(value):
		character_id = value
		_apply_character()

var _mouth: Node3D
var _mouth_open := 1.0  # as built (open) until something sets it, as before
var _mouth_radius := 0.5  # half the height of the lip ring, in the mouth pivot's own units
var _mouth_half_width := 0.5  # half the width of the lip ring, in the mouth pivot's own units
var _body_stages: Array[Node3D] = []  # the body at each mouth step, open first
var _lip: MeshInstance3D
var _mesh_root: Node3D
var _mouth_materials: Array[ShaderMaterial] = []


func _ready() -> void:
	if _mesh_root == null:
		_build()
	_apply_character()


## Builds the posed mesh from the .glb file. The file is read directly, so Godot's import
## cache is not needed and the model works from a fresh clone.
func _build() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var scene: Node3D = null
	if doc.append_from_file(MODEL_PATH, state) == OK:
		scene = doc.generate_scene(state) as Node3D
	if scene == null:
		push_error("Could not load the mascot model: " + MODEL_PATH)
		scene = Node3D.new()
	scene.position = Vector3(0, -0.5, 0)
	scene.rotation_degrees = Vector3(0, 90, 0)
	scene.scale = Vector3(0.5, 0.5, 0.5)
	_mesh_root = scene
	add_child(_mesh_root)
	_mouth = _attach_mouth_pivot(_mesh_root)
	_find_body_stages(_mesh_root)
	_apply_look(_mesh_root)
	set_mouth_open(_mouth_open)


## Collects the body steps in order (BodyStage_0, BodyStage_1, ...).
func _find_body_stages(root: Node) -> void:
	_body_stages.clear()
	var index := 0
	while true:
		var stage := root.find_child("BodyStage_%d" % index, true, false) as Node3D
		if stage == null:
			break
		_body_stages.append(stage)
		index += 1
	if _body_stages.is_empty():
		push_error("The mascot model has no BodyStage_ meshes; replace it with a model that has the mouth steps")


## Adds a pivot at the top edge of the open lip ring, for things that ride on the mouth (an evil
## chompbot's teeth). The lip ring itself is not moved by it: it follows the mouth by shape keys.
func _attach_mouth_pivot(root: Node) -> Node3D:
	_lip = root.find_child("LipRim*", true, false) as MeshInstance3D
	if _lip == null:
		return null
	var local_center := _lip.get_aabb().get_center()
	var size := _lip.get_aabb().size
	_mouth_radius = size.y * 0.5
	_mouth_half_width = size.z * 0.5
	var local_top := local_center + Vector3(0.0, _mouth_radius, 0.0)
	var pivot := Node3D.new()
	pivot.name = "MouthPivot"
	pivot.transform = Transform3D(_lip.transform.basis, _lip.transform * local_top)
	_lip.get_parent().add_child(pivot)
	return pivot


## The pivot the mouth opens around (null if the model has no lip ring).
func get_mouth_pivot() -> Node3D:
	return _mouth


## Half the height of the lip ring, in the mouth pivot's own units.
func get_mouth_radius() -> float:
	return _mouth_radius


## Half the width of the lip ring (across the face, in the ring's plane), in the pivot's units.
func get_mouth_half_width() -> float:
	return _mouth_half_width


## Opens and closes the mouth. amount is 0 (closed) to 1 (open). It picks the nearest mouth step,
## shows the body at that step and puts the lip ring on the same step, so the lips always sit on
## the edge of the bite.
func set_mouth_open(amount: float) -> void:
	_mouth_open = clampf(amount, 0.0, 1.0)
	if _body_stages.is_empty():
		return
	var last := _body_stages.size() - 1
	var step := roundi((1.0 - _mouth_open) * last)
	for i in _body_stages.size():
		_body_stages[i].visible = i == step
	if _lip and _lip.mesh:
		# The lip's shape keys are Stage_1 ... Stage_<last>; step 0 is the lip as built (open).
		for i in _lip.get_blend_shape_count():
			_lip.set_blend_shape_value(i, 1.0 if i + 1 == step else 0.0)
	if _mouth:
		_mouth.scale = Vector3(1.0, lerpf(TEETH_CLOSED_SCALE, 1.0, _mouth_open), 1.0)


func get_mouth_open() -> float:
	return _mouth_open


## Matches the current Blender mascot: deep matte blacks, and the mouth's inside as a shader.
## Runs once per model, before any recolouring.
func _apply_look(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mesh_instance := node as MeshInstance3D
		for i in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(i) as StandardMaterial3D
			if source == null:
				continue
			if source.resource_name.begins_with(MOUTH_INTERIOR_MATERIAL):
				var material := ShaderMaterial.new()
				material.shader = MOUTH_SHADER
				mesh_instance.set_surface_override_material(i, material)
				_mouth_materials.append(material)
			elif _is_near_black(source):
				var matte := source.duplicate() as StandardMaterial3D
				matte.roughness = maxf(matte.roughness, MATTE_ROUGHNESS)
				matte.metallic_specular = 0.2
				mesh_instance.set_surface_override_material(i, matte)
	for child in node.get_children():
		_apply_look(child)


func _is_near_black(material: StandardMaterial3D) -> bool:
	var c := material.albedo_color
	return not material.emission_enabled and maxf(c.r, maxf(c.g, c.b)) < 0.06


func _apply_character() -> void:
	if _mesh_root == null:
		return
	var mouth_color := MOUTH_TEAL
	if character_id == "mrs_chomp":
		_recolor(_mesh_root, PINK, PINK_EMISSION)
		mouth_color = MOUTH_PINK
	elif character_id == "evil":
		_recolor(_mesh_root, RED, RED_EMISSION)
		mouth_color = MOUTH_RED
	for material in _mouth_materials:
		material.set_shader_parameter("glow_color", mouth_color)


func _recolor(node: Node, tint: Color, tint_emission: Color) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count := mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0
		for i in surface_count:
			var source := mesh_instance.get_active_material(i) as StandardMaterial3D
			if source == null:
				continue
			if not (_is_cyan(source.albedo_color) or _is_cyan(source.emission)):
				continue
			var material := source.duplicate() as StandardMaterial3D
			if _is_cyan(material.albedo_color):
				material.albedo_color = tint
			if _is_cyan(material.emission):
				material.emission = tint_emission
				# The cyan eyes are bright enough to stay cyan; pink and red would wash out to white.
				material.emission_energy_multiplier = minf(material.emission_energy_multiplier, 1.2)
			mesh_instance.set_surface_override_material(i, material)
	for child in node.get_children():
		_recolor(child, tint, tint_emission)


## Cyan and blue parts of the mascot have a much stronger blue channel than red.
func _is_cyan(color: Color) -> bool:
	return color.b > color.r + 0.25
