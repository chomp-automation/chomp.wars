extends Area3D
## A glowing backlog ticket that bobs and disappears when collected.

signal collected(orb: Node3D)

@onready var body_mesh: MeshInstance3D = $Mesh
@onready var glow: OmniLight3D = $Glow

var _base_y := 0.0
var _time := 0.0
var _taken := false


func _ready() -> void:
	add_to_group("issue")
	# Original geometric issue-card artwork, rendered at runtime without imported assets.
	var image := Image.new()
	image.load_svg_from_string("""<svg xmlns="http://www.w3.org/2000/svg" width="384" height="288" viewBox="0 0 384 288">
<rect x="8" y="8" width="368" height="272" rx="22" fill="#20142f" stroke="#bc80ff" stroke-width="10"/>
<circle cx="63" cy="66" r="25" fill="none" stroke="#bc80ff" stroke-width="7"/>
<circle cx="63" cy="66" r="7" fill="#bc80ff"/>
<path d="M111 51h217M111 76h154" stroke="#f5ecff" stroke-width="12" stroke-linecap="round"/>
<path d="M40 122h280M40 150h240M40 178h264" stroke="#987fae" stroke-width="9" stroke-linecap="round"/>
<rect x="36" y="213" width="141" height="39" rx="16" fill="#7040a0"/>
<g transform="translate(49 224) scale(1.4)" fill="none" stroke="white" stroke-width="1.8" stroke-linejoin="round">
<path d="M0 0v12h5q6 0 6-3t-6-3H0h5q5 0 5-3T5 0Z M15 12l4-12h2l4 12m-8-4h6 M39 1q-10-4-10 5t10 5 M44 0v12m8-12-8 6 8 6 M57 0v12h9 M75 0q-5 0-5 6t5 6 5-6-5-6Z M95 1q-10-4-10 5t10 5V6h-5"/>
</g>
<path d="M280 216l-5 29m18-29-5 29m-18-19h29m-31 11h29" fill="none" stroke="#bc80ff" stroke-width="4"/>
</svg>""")
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	body_mesh.material_override = material
	_base_y = position.y
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	position.y = _base_y + sin(_time * 2.0) * 0.12
	glow.light_energy = 0.8 + 0.6 * (0.5 + 0.5 * sin(_time * 3.0))


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body.is_in_group("player"):
		return
	_taken = true
	remove_from_group("issue")
	set_deferred("monitoring", false)
	collected.emit(self)
	var tween := create_tween()
	tween.tween_property(body_mesh, "scale", Vector3.ZERO, 0.25)
	tween.tween_callback(queue_free)
