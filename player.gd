extends CharacterBody3D

var joystick_vector := Vector2.ZERO
var touch_sensitivity : float = 0.2
var mouseSensibility : float = 250.0   # ← ye naya line add karo (value badha/ghata sakte ho)
@onready var animation_player = $Model/AnimationPlayer
@onready var animation_tree = $AnimationTree
@onready var model = $Model

@onready var gunRay = $Head/Camera3d/RaycastShoot as RayCast3D
@onready var grabRay = $Head/Camera3d/RaycastGrab as RayCast3D
@onready var item_hold_pos = $Head/Camera3d/ItemHoldPos

@onready var canvas_layer = $CanvasLayer

# ===== TPP/FPP CAMERAS =====
@onready var camera_tpp = $Head/Camera3d as Camera3D
@onready var camera_fpp = $Head/Camera3D_FPP as Camera3D
@onready var view_toggle_btn = $CanvasLayer/ViewToggleBtn as Button

var is_fpp := false  # false = TPP, true = FPP

@onready var head = $Head
@onready var env_colision = $BodyColision
@onready var general_skeleton = %GeneralSkeleton

@onready var static_body_3d = $Head/Camera3d/StaticBody3D
@onready var joint = $Head/Camera3d/Generic6DOFJoint3D

@onready var flashlight = $Head/Camera3d/Flashlight

@export var CurrentTeam : String
@export var Health : int
@export var Status : String

var _bullet_scene = preload("res://assets/items/Bullet/Bullet.tscn")

var RELATIVE_DIRECTIONALITY = Vector3(0.0, 0.0, 0.0)

var speed
var paused : bool
var mouse_locked = false

const WALK_SPEED = 3.0
const SPRINT_SPEED = 5.0
const CROUCH_SPEED = 2.0
const JUMP_VELOCITY = 4.8
const ACCELERATION = 100

const SENSITIVITY = 0.004
const PLAYER_HEIGHT = 2.5
const PLAYER_CROUCH_HEIGHT = 1
const PLAYER_LIFT_MAX : float = 50.0
const PLAYER_MAX_HEALTH : int = 100
const PLAYER_INJURED_THRESHOLD : int = 50
const PLAYER_INCAPACITATED_THRESHOLD : int = 15
const PLAYER_DEATH_THRESHOLD : int = 0

var held_object
var held_object_old_collision_layers
var pull_power = 20
var rotate_power = 0.1

const BOB_FREQ = 4.0
const BOB_AMP = 0.08
var t_bob = 0.0

const BASE_FOV = 70.0
const FOV_CHANGE = 1.5

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _enter_tree():
	set_multiplayer_authority(str(name).to_int())

func _ready():
	Health = 100
	Status = Globals.PlayerStatus.stable

#	view_toggle_btn.text = "TPP"
	if not is_multiplayer_authority() and Globals.GameMode != Globals.GameModes.practice: 
		canvas_layer.hide()
		return

	if str(name).to_int() != 1:
		pass

	self.model.hide()
	gunRay.add_exception(self)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Default: TPP camera ON
	camera_tpp.current = true
	camera_fpp.current = false
	# ===== VIEW TOGGLE BUTTON SIGNAL =====
	if view_toggle_btn:
		view_toggle_btn.pressed.connect(_on_view_toggle_pressed)
		view_toggle_btn.text = "TPP"

func _physics_process(delta):
	if not is_multiplayer_authority() and Globals.GameMode != Globals.GameModes.practice: 
		return

	velocity.y = clamp(velocity.y, -INF, JUMP_VELOCITY)
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("Jump") and is_on_floor() and not paused:
		velocity.y = JUMP_VELOCITY

	if Input.is_action_pressed("Sprint") and not paused:
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED

	var input_dir = joystick_vector
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()

func _headbob(time) -> Vector3:
	var pos = camera_tpp.position
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos

# ===== TPP/FPP TOGGLE =====
func _on_view_toggle_pressed():
	is_fpp = !is_fpp

	if is_fpp:
		# FPP MODE
		camera_fpp.current = true
		camera_tpp.current = false
		model.hide()  # FPP mein apna model nahi dikhta
		view_toggle_btn.text = "FPP"
		print("Switched to FPP")
	else:
		# TPP MODE
		camera_tpp.current = true
		camera_fpp.current = false
		model.show()  # TPP mein model dikhta hai
		view_toggle_btn.text = "TPP"
		print("Switched to TPP")

func _input(event):
	# Mobile camera rotation
	if event is InputEventScreenDrag:
		rotate_y(deg_to_rad(-event.relative.x * touch_sensitivity))
		var cam = camera_tpp if not is_fpp else camera_fpp
		cam.rotate_x(deg_to_rad(-event.relative.y * touch_sensitivity))
		cam.rotation.x = clamp(cam.rotation.x, deg_to_rad(-89), deg_to_rad(89))
		return

	if not is_multiplayer_authority(): 
		return

	# PC Mouse controls
	if event is InputEventMouseMotion and not mouse_locked:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotation.y -= event.relative.x / mouseSensibility
			var cam = camera_tpp if not is_fpp else camera_fpp
			cam.rotation.x -= event.relative.y / mouseSensibility
			cam.rotation.x = clamp(cam.rotation.x, deg_to_rad(-90), deg_to_rad(90))

	if not held_object and Input.is_action_just_pressed("Shoot") and not paused:
		shoot()

	if Input.is_action_just_pressed("Ability1") and not paused:
		flashlight.visible = !flashlight.visible

@rpc("any_peer")
func take_damage(damage_in:int):
	if Health <= 0: return
	Health = Health-damage_in
	print("Player ", name, " Has Taken ", damage_in, " Damage")
	check_player_health_apply_status()

func check_player_health_apply_status():
	if Health <= PLAYER_DEATH_THRESHOLD:
		Status = "Dead"
	elif Health <= PLAYER_INCAPACITATED_THRESHOLD:
		Status = "Incapacitated"
	elif Health <= PLAYER_INJURED_THRESHOLD:
		Status = "Injured"
	else: 
		Status = "Stable"

var PreviousStatus
func handle_status():
	if Status == PreviousStatus: return
	else: PreviousStatus = Status
	if Status == Globals.PlayerStatus.stable:
		print("Player ", name, " is Stable")
	elif Status == Globals.PlayerStatus.injured:
		print("Player ", name, " is Injured")
	elif Status == Globals.PlayerStatus.incapacitated:
		print("Player ", name, " is Incapacitated")
	elif Status == Globals.PlayerStatus.stunned:
		print("Player ", name, " is Stunned")
	elif Status == Globals.PlayerStatus.confused:
		print("Player ", name, " is Confused")
	elif Status == Globals.PlayerStatus.dead:
		print("Player ", name, " is Dead")

@rpc("any_peer", "call_local")
func hold_object():
	if held_object != null:
		var forceDirection = (item_hold_pos.global_transform.origin - held_object.global_transform.origin)
		held_object.set_linear_velocity(forceDirection * pull_power)
		var distance_from_player_and_object = held_object.global_position.distance_to(global_transform.origin)
		if distance_from_player_and_object > 2:
			drop_object.rpc()

@rpc("any_peer", "call_local")
func start_hold_object():
	var collider = grabRay.get_collider()
	if collider != null and collider is RigidBody3D or collider is PhysicalBone3D:
		if collider.get("mass") <= PLAYER_LIFT_MAX:
			held_object = collider
			held_object_old_collision_layers = held_object.get("collision_layer")
			held_object.set("collision_layer", 10)
			held_object.set("is_held", true)
			if !held_object.get("metadata/isDoor"):
				joint.set("node_b", held_object.get_path())

@rpc("any_peer", "call_local")
func drop_object():
	if held_object != null:
		held_object.set("is_held", false)
		held_object.set("collision_layer", held_object_old_collision_layers)
		held_object = null
		joint.set("node_b", joint.get_path())

@rpc("any_peer", "call_local")
func rotate_object(event):
	if held_object != null:
		if event is InputEventMouseMotion:
			static_body_3d.rotate_x(deg_to_rad(event.relative.y * rotate_power))
			static_body_3d.rotate_y(deg_to_rad(event.relative.x * rotate_power))

@rpc("any_peer", "call_local")
func throw_object():
	if held_object != null:
		var knockback = held_object.position - self.position
		held_object.apply_force(knockback * pull_power)
		drop_object.rpc()

@rpc("call_local")
func animations_handler(relative_directionality:Vector3):
	animation_tree.set("parameters/BlendSpace2D/blend_position",Vector2(relative_directionality.x, relative_directionality.y))
	animation_tree.set("parameters/Blend3/blend_amount", relative_directionality.z)

func shoot():
	if not gunRay.is_colliding():
		return
	if gunRay.is_colliding() and gunRay.get_collider() is CharacterBody3D:
		var hitplayer = gunRay.get_collider()
		if hitplayer.has_method("take_damage"):
			hitplayer.take_damage.rpc_id(hitplayer.get_multiplayer_authority(), 10)
			print(hitplayer.name, " has been shot by ", name)
	else:
		apply_bullethole.rpc()

@rpc("any_peer", "call_remote")
func apply_bullethole():
	if not gunRay.is_colliding():
		return
	else:
		var bulletInst = _bullet_scene.instantiate() as Node3D
		bulletInst.set_as_top_level(true)
		add_child(bulletInst)
		bulletInst.global_transform.origin = gunRay.get_collision_point() as Vector3
		bulletInst.look_at((gunRay.get_collision_point()+gunRay.get_collision_normal()),Vector3.BACK)
		await get_tree().create_timer(10).timeout
		remove_child(bulletInst)

func _on_h_slider_value_changed(value: float) -> void:
	touch_sensitivity = value / 100.0 
	print("New Sensitivity: ", touch_sensitivity)

func _on_virtual_joystick_plus_analogic_changed(value: Vector2, _distance, _angle, _angle_clockwise, _angle_not_clockwise) -> void:
	joystick_vector = value
