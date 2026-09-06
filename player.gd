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
@onready var camera_tpp = $Camera3D_TPP/SpringArm3D/Camera3D as Camera3D   # asli TPP
@onready var camera_fpp = $Head/Camera3d as Camera3D                       # FPP
@onready var view_toggle_btn = $CanvasLayer/ViewToggleBtn as Button
@onready var spring_arm = $Camera3D_TPP/SpringArm3D as SpringArm3D

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

const WALK_SPEED = 5.0
const SPRINT_SPEED = 5.0
const CROUCH_SPEED = 2.0
const JUMP_VELOCITY = 5.2
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
		model.show()
		return

	if str(name).to_int() != 1:
		pass

	self.model.hide()
	gunRay.add_exception(self)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


	# Default: TPP camera ON
	is_fpp = false
	camera_tpp.current = true
	camera_fpp.current = false
	model.show()
	model.rotation.y = deg_to_rad(180)   # agar character peeche dekh raha ho to
	# ===== VIEW TOGGLE BUTTON SIGNAL =====
	if view_toggle_btn:
		view_toggle_btn.pressed.connect(_on_view_toggle_pressed)
		view_toggle_btn.text = "TPP"
		
# AnimationTree force active karo
	if animation_tree:
		animation_tree.active = true
		animation_tree.set("parameters/BlendSpace2D/blend_position", Vector2.ZERO)
		animation_tree.set("parameters/Blend3/blend_amount", 0.0)

	# Model show
	model.show()
	model.rotation.y = deg_to_rad(180)

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
	_update_animations(delta)
	# _physics_process mein
	if Input.is_action_pressed("Crouch") and is_on_floor():
			speed = CROUCH_SPEED
				# height change (optional)
					# env_colision.shape.height = PLAYER_CROUCH_HEIGHT
	#else:
						# env_colision.shape.height = PLAYER_HEIGHT


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
	# Mobile
	if event is InputEventScreenDrag:
		rotate_y(deg_to_rad(-event.relative.x * touch_sensitivity))
		
		if is_fpp:
			camera_fpp.rotate_x(deg_to_rad(-event.relative.y * touch_sensitivity))
			camera_fpp.rotation.x = clamp(camera_fpp.rotation.x, deg_to_rad(-89), deg_to_rad(89))
		else:
			spring_arm.rotate_x(deg_to_rad(-event.relative.y * touch_sensitivity))
			spring_arm.rotation.x = clamp(spring_arm.rotation.x, deg_to_rad(-55), deg_to_rad(25))
		return

	if not is_multiplayer_authority(): 
		return

	# PC Mouse
	if event is InputEventMouseMotion and not mouse_locked:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotation.y -= event.relative.x / mouseSensibility
			
			if is_fpp:
				camera_fpp.rotation.x -= event.relative.y / mouseSensibility
				camera_fpp.rotation.x = clamp(camera_fpp.rotation.x, deg_to_rad(-89), deg_to_rad(89))
			else:
				spring_arm.rotation.x -= event.relative.y / mouseSensibility
				spring_arm.rotation.x = clamp(spring_arm.rotation.x, deg_to_rad(-55), deg_to_rad(25))
				
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

func _update_animations(delta):
	if not animation_tree or not animation_tree.active:
		return

	# Horizontal velocity
	var horizontal_vel = Vector3(velocity.x, 0, velocity.z)
	var speed = horizontal_vel.length()

	var blend_pos = Vector2.ZERO

	if speed > 0.2:
		# Character ke local direction mein convert karo
		var local_dir = global_transform.basis.inverse() * horizontal_vel.normalized()

		# BlendSpace mapping (tumhare points ke hisaab se)
		# Y = Forward (+1 = Run Forward), X = Right (+1 = Walk Right)
		blend_pos.x = clamp(local_dir.x, -1.0, 1.0)
		blend_pos.y = clamp(-local_dir.z, -1.0, 1.0)

		# Speed ke hisaab se thoda scale
		if speed < WALK_SPEED * 0.7:
			blend_pos *= 0.65   # Walk zone
		else:
			blend_pos *= 1.0    # Run zone
	else:
		blend_pos = Vector2.ZERO

	# Smoothly set karo
	var current_pos = animation_tree.get("parameters/BlendSpace2D/blend_position")
	animation_tree.set("parameters/BlendSpace2D/blend_position", current_pos.lerp(blend_pos, delta * 12.0))

	# ----- Blend3 (Jump / Crouch) -----
	var target_blend3 = 0.0

	if not is_on_floor():
		target_blend3 = 1.0 if velocity.y > 0.8 else 0.5
	elif Input.is_action_pressed("Crouch"):
		target_blend3 = -1.0
	else:
		target_blend3 = 0.0

	var current_blend3 = animation_tree.get("parameters/Blend3/blend_amount")
	animation_tree.set("parameters/Blend3/blend_amount", lerp(current_blend3, target_blend3, delta * 10.0))

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
