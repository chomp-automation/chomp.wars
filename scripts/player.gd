extends CharacterBody3D
## The playable character. Chomp and Mrs. Chomp share one mascot model (chomp_model.gd);
## Mrs. Chomp is recoloured pink and slightly slimmer, and her lasers are pink.
##
## Default view is third-person so the character is visible. Press V to switch to
## first-person. W and S move forwards and backwards, A and D turn the character round
## (a full circle). The body does not tumble: it stays upright and leans slightly into turns.
## Hold Space or the R1 / right shoulder button to charge, then release to deploy agent attacks.
## Left stick strafes; right stick turns and aims. L2 locks movement for faster
## left-stick aiming. R2 gives a 5x sniper view with finer aiming.

signal fired(origin: Vector3, direction: Vector3, character_id: String, charge: float)

const ChompModel := preload("res://scripts/chomp_model.gd")

const WALK_SPEED := 6.0
const SPRINT_MULTIPLIER := 2.0
const AIM_SPEED_MULTIPLIER := 0.7
const JUMP_VELOCITY := 5.5
const MOUSE_SENSITIVITY := 0.00165
const LEAN_ANGLE := 0.35  # radians (about 20 degrees) of horizontal lean when turning
const LEAN_SPEED := 8.0
const MOUSE_TURN_SCALE := 0.04
const TURN_SPEED := 2.6  # radians per second while A/D or D-pad left/right is held
const STICK_TURN_SPEED := 1.43  # radians per second at full right-stick tilt
const STICK_PITCH_SPEED := 0.99
const MIN_PITCH := -70.0  # degrees
const MAX_PITCH := 60.0
const FIRST_PERSON_CAMERA := Vector3(0, 0, 0)
const THIRD_PERSON_CAMERA := Vector3(0, 0.6, 3.6)
const MRS_CHOMP_SCALE := Vector2(0.92, 0.92)  # width/depth factor; height unchanged
const NORMAL_FOV := 75.0
const SNIPER_MAGNIFICATION := 5.0
const FIRE_COOLDOWN := 0.35
const MAX_CHARGE_TIME := 10.0
const KEY_AIM_SPEED := 0.33  # radians per second for precise keyboard aiming
const MOUTH_FIRE_TIME := 0.25  # seconds the mouth stays open after firing

@onready var body: Node3D = $Body
var model: Node3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera

var character_id := "chomp"
var third_person := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _base_model_scale := Vector3.ONE
var _mouse_turn := 0.0  # mouse turn pending for the lean, decays each frame
var charge_time := 0.0
var _charging := false
var _fire_timer := 0.0
var _mouth_timer := 0.0


func _ready() -> void:
	add_to_group("player")
	model = ChompModel.new()
	model.name = "Model"
	body.add_child(model)
	_base_model_scale = model.scale
	_set_third_person(true)


func apply_character(id: String) -> void:
	character_id = id
	model.scale = _base_model_scale
	if id == "mrs_chomp":
		model.scale = Vector3(_base_model_scale.x * MRS_CHOMP_SCALE.x, _base_model_scale.y,
				_base_model_scale.z * MRS_CHOMP_SCALE.y)
	model.character_id = id


func respawn(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	cancel_charge()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		Game.play_sfx("jump")

	# Keyboard/D-pad turning must not reduce forward speed when both are held.
	var turn_input := Input.get_axis("move_left", "move_right")
	var forward_input := Input.get_axis("move_forward", "move_back")
	var stick := Input.get_vector("stick_left", "stick_right", "stick_forward", "stick_back")
	var aim_lock := Input.is_action_pressed("aim_lock")
	var zoom_scale := 1.0 / SNIPER_MAGNIFICATION if Input.is_action_pressed("sniper") else 1.0
	var precision := zoom_scale * AIM_SPEED_MULTIPLIER
	# Perspective magnification scales tan(FOV / 2), rather than the angle itself.
	camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(NORMAL_FOV) / 2.0) * zoom_scale))
	rotate_y(-turn_input * TURN_SPEED * delta * precision)
	var movement := Vector3(stick.x, 0, clampf(forward_input + stick.y, -1.0, 1.0)).limit_length()
	if aim_lock:
		movement = Vector3.ZERO
		rotate_y(-stick.x * STICK_TURN_SPEED * 2.0 * delta * precision)
		_pitch_camera(-stick.y * STICK_PITCH_SPEED * 2.0 * delta * precision)
	var direction := global_transform.basis * movement
	var speed := WALK_SPEED * SPRINT_MULTIPLIER if Input.is_action_pressed("sprint") else WALK_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()
	_pitch_camera(Input.get_axis("aim_down", "aim_up") * KEY_AIM_SPEED * delta * precision)
	_look_with_stick(delta * precision)
	_lean_body(turn_input, delta)
	_update_mouth(delta)


func _process(delta: float) -> void:
	_update_charge(delta / Engine.time_scale)


func _update_charge(delta: float) -> void:
	if Input.is_action_just_pressed("fire"):
		_charging = true
		charge_time = 0.0
	if _charging and Input.is_action_pressed("fire"):
		charge_time = minf(charge_time + delta, MAX_CHARGE_TIME)
	elif _charging:
		fire(charge_time / MAX_CHARGE_TIME)
		cancel_charge()


func cancel_charge() -> void:
	_charging = false
	charge_time = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var precision := 1.0 / SNIPER_MAGNIFICATION if Input.is_action_pressed("sniper") else 1.0
		precision *= AIM_SPEED_MULTIPLIER
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY * precision)
		_mouse_turn = clampf(_mouse_turn - event.relative.x * MOUSE_TURN_SCALE, -1.0, 1.0)
		_pitch_camera(-event.relative.y * MOUSE_SENSITIVITY * precision)
	elif event.is_action_pressed("toggle_view", false):
		_set_third_person(not third_person)


## Turns and tilts the view with the controller's right stick. The action deadzone
## filters out stick drift.
func _look_with_stick(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look == Vector2.ZERO:
		return
	rotate_y(-look.x * STICK_TURN_SPEED * delta)
	_mouse_turn = clampf(_mouse_turn - look.x * STICK_TURN_SPEED * delta, -1.0, 1.0)
	_pitch_camera(-look.y * STICK_PITCH_SPEED * delta)


func _pitch_camera(amount: float) -> void:
	camera_pivot.rotation.x = clampf(camera_pivot.rotation.x + amount,
			deg_to_rad(MIN_PITCH), deg_to_rad(MAX_PITCH))


## Fires one laser in the direction the camera is looking, if the cooldown has passed.
func fire(charge: float = 0.0) -> void:
	if _fire_timer > 0.0 or get_tree().paused:
		return
	_fire_timer = FIRE_COOLDOWN
	_mouth_timer = MOUTH_FIRE_TIME
	var forward := -camera.global_transform.basis.z
	var origin := global_position + Vector3.UP
	fired.emit(origin, forward, character_id, clampf(charge, 0.0, 1.0))


func _set_third_person(enabled: bool) -> void:
	third_person = enabled
	camera.position = THIRD_PERSON_CAMERA if enabled else FIRST_PERSON_CAMERA
	model.visible = enabled


## Leans the body slightly into horizontal turns (A and D, the left stick, or turning the view). The body
## stays upright and never tumbles, so it reads as wheeling along rather than rolling.
func _lean_body(strafe_input: float, delta: float) -> void:
	_mouse_turn = move_toward(_mouse_turn, 0.0, delta * 2.0)
	var turn := clampf(-strafe_input + _mouse_turn, -1.0, 1.0)
	var target := turn * LEAN_ANGLE
	body.rotation.y = lerp_angle(body.rotation.y, target, clampf(LEAN_SPEED * delta, 0.0, 1.0))


## The mouth chomps open briefly each time a laser fires.
func _update_mouth(delta: float) -> void:
	_fire_timer = maxf(_fire_timer - delta, 0.0)
	_mouth_timer = maxf(_mouth_timer - delta, 0.0)
	model.set_mouth_open(_mouth_timer / MOUTH_FIRE_TIME)
