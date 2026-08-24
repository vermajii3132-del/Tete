extends CharacterBody3D
# 1. Script ke sabse upar (Line 2 ke paas) ye variable banayein:
var joystick_vector := Vector2.ZERO
# 2. Jo function signal se bana, usme ye likhein:
func _on_virtual_joystick_analogic_changed(value: Vector2, _distance, _angle, _angle_clockwise, _angle_not_clockwise):
		joystick_vector = value # Joystick ki direction yahan save ho jayegi
var touch_sensitivity : float = 0.2  # Isse aap sensitivity control karenge

@onready var animation_player = $Model/AnimationPlayer
@onready var animation_tree = $AnimationTree

@onready var model = $Model

@onready var gunRay = $Head/Camera3d/RaycastShoot as RayCast3D
@onready var grabRay = $Head/Camera3d/RaycastGrab as RayCast3D
@onready var item_hold_pos = $Head/Camera3d/ItemHoldPos

@onready var canvas_layer = $CanvasLayer

@onready var camera = $Head/Camera3d as Camera3D
@onready var head = $Head
@onready var env_colision = $BodyColision
@onready var general_skeleton = %GeneralSkeleton

@onready var static_body_3d = $Head/Camera3d/StaticBody3D
@onready var joint = $Head/Camera3d/Generic6DOFJoint3D

@onready var flashlight = $Head/Camera3d/Flashlight

@export var CurrentTeam : String  ## String to handle team of Player
@export var Health : int
@export var Status : String ## Player Statuses: Stable, Injured, Incapacitated, Stunned, Confused, Dead

var _bullet_scene = preload("res://assets/items/Bullet/Bullet.tscn")

## Directionality for animation blend 2d, x y values between 0 and 1.
var RELATIVE_DIRECTIONALITY = Vector3(0.0, 0.0, 0.0)

## Movement Variables
var mouseSensibility = 1200
var mouse_relative_x = 0
var mouse_relative_y = 0
var speed
var paused : bool
var mouse_locked = false

## Movement Speeds 
const WALK_SPEED = 3.0
const SPRINT_SPEED = 5.0
const CROUCH_SPEED = 2.0
const JUMP_VELOCITY = 4.8
const ACCELERATION = 100

## Player Variables
const SENSITIVITY = 0.004
const PLAYER_HEIGHT = 2.5
const PLAYER_CROUCH_HEIGHT = 1
const PLAYER_LIFT_MAX : float = 50.0 #kg
const PLAYER_MAX_HEALTH : int = 100
const PLAYER_INJURED_THRESHOLD : int = 50
const PLAYER_INCAPACITATED_THRESHOLD : int = 15
const PLAYER_DEATH_THRESHOLD : int = 0

var held_object
var held_object_old_collision_layers
var pull_power = 20
var rotate_power = 0.1

## Head Bob Variables
const BOB_FREQ = 4.0
const BOB_AMP = 0.08
var t_bob = 0.0

## FOV Variables
const BASE_FOV = 70.0
const FOV_CHANGE = 1.5

## Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _enter_tree():
	set_multiplayer_authority(str(name).to_int())

func _ready():
	#Spawn In Values
	Health = 100
	Status = Globals.PlayerStatus.stable
	if not is_multiplayer_authority() and Globals.GameMode != Globals.GameModes.practice: 
		canvas_layer.hide()
		return
	if str(name).to_int() != 1:
		pass
	self.model.hide()
	#Captures mouse and stops rgun from hitting yourself
	gunRay.add_exception(self)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	camera.current = true
	
func _physics_process(delta):
	if not is_multiplayer_authority() and Globals.GameMode != Globals.GameModes.practice: 
		return
		
	velocity.y = clamp(velocity.y, -INF, JUMP_VELOCITY)
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump logic
	if Input.is_action_just_pressed("Jump") and is_on_floor() and not paused:
		velocity.y = JUMP_VELOCITY

	# Movement Speed
	if Input.is_action_pressed("Sprint") and not paused:
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED

	# --- MOBILE JOYSTICK MOVEMENT ---
	var input_dir = joystick_vector # Joystick ki value yahan use ho rahi hai
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()

## Headbob, Sin wave for y, Cos wave for x 
func _headbob(time) -> Vector3:
	var pos = camera.position
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos
	
func _input(event):
	# --- 1. MOBILE CAMERA ROTATION (Authority se pehle rakha hai taaki hamesha chale) ---
	if event is InputEventScreenDrag:
		# Baayein-Daayein (Horizontal)
		rotate_y(deg_to_rad(-event.relative.x * touch_sensitivity))
		
		# Upar-Neeche (Vertical)
		var cam = $Head/Camera3d
		cam.rotate_x(deg_to_rad(-event.relative.y * touch_sensitivity))
		cam.rotation.x = clamp(cam.rotation.x, deg_to_rad(-89), deg_to_rad(89))
		return # Mobile touch handle ho gaya, ab niche jane ki zaroorat nahi

	# --- 2. MULTIPLAYER CHECK (Iske niche ka code sirf authority ke liye hai) ---
	if not is_multiplayer_authority(): 
		return

	# --- 3. PC MOUSE CONTROLS (Sirf PC par kaam ayega) ---
	if event is InputEventMouseMotion and not mouse_locked:
		# Android Editor mein ye block aksar skip ho jata hai, isliye upar wala code zaroori hai
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotation.y -= event.relative.x / mouseSensibility
			$Head/Camera3d.rotation.x -= event.relative.y / mouseSensibility
			$Head/Camera3d.rotation.x = clamp($Head/Camera3d.rotation.x, deg_to_rad(-90), deg_to_rad(90))

	# --- 4. SHOOTING & OTHER ACTIONS ---
	if not held_object and Input.is_action_just_pressed("Shoot") and not paused:
		shoot()
	
	if Input.is_action_just_pressed("Ability1") and not paused:
		flashlight.visible = !flashlight.visible
## Apply Damage to Player
@rpc("any_peer")
func take_damage(damage_in:int):
	if Health <= 0: return
	Health = Health-damage_in
	print("Player ", name, " Has Taken ", damage_in, " Damage")
	check_player_health_apply_status()

#Handles Player Status Based on Health
func check_player_health_apply_status():
	if Health <= PLAYER_DEATH_THRESHOLD:
		Status = "Dead"
	elif Health <= PLAYER_INCAPACITATED_THRESHOLD:
		Status = "Incapacitated"
	elif Health <= PLAYER_INJURED_THRESHOLD:
		Status = "Injured"
	else: 
		Status = "Stable"
 
## Handle Player Statuses (TEMP: Print Status)
var PreviousStatus
func handle_status():
	if Status == PreviousStatus: return
	else: PreviousStatus = Status
	if Status == Globals.PlayerStatus.stable:
		print("Player ", name, " is Stable")
		pass
	elif Status == Globals.PlayerStatus.injured:
		print("Player ", name, " is Injured")
		pass
	elif Status == Globals.PlayerStatus.incapacitated:
		print("Player ", name, " is Incapacitated")
		pass
	elif Status == Globals.PlayerStatus.stunned:
		print("Player ", name, " is Stunned")
		pass 
	elif Status == Globals.PlayerStatus.confused:
		print("Player ", name, " is Confused")
		pass
	elif Status == Globals.PlayerStatus.dead:
		print("Player ", name, " is Dead")
		pass
	else:
		pass


## RPC for Holding Object
@rpc("any_peer", "call_local")
func hold_object():
	if held_object != null:
		var forceDirection = (item_hold_pos.global_transform.origin - held_object.global_transform.origin)
		held_object.set_linear_velocity(forceDirection * pull_power)
		#if object is too far from player, drop object
		var distance_from_player_and_object = held_object.global_position.distance_to(global_transform.origin)
		if distance_from_player_and_object > 2:
			drop_object.rpc()
		#if object is not in direct sight, drop object
#		var collider = grabRay.get_collider()
#		if collider != held_object:
#			drop_object.rpc()

## RPC for Picking Up Object
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

## RPC for Dropping Object
@rpc("any_peer", "call_local")
func drop_object():
	if held_object != null:
		held_object.set("is_held", false)
		held_object.set("collision_layer", held_object_old_collision_layers)
		held_object = null
		joint.set("node_b", joint.get_path())

## RPC for Rotating Object
@rpc("any_peer", "call_local")
func rotate_object(event):
	if held_object != null:
		if event is InputEventMouseMotion:
			static_body_3d.rotate_x(deg_to_rad(event.relative.y * rotate_power))
			static_body_3d.rotate_y(deg_to_rad(event.relative.x * rotate_power))

## RPC for Throwing Object
@rpc("any_peer", "call_local")
func throw_object():
	if held_object != null:
		var knockback = held_object.position - self.position
		held_object.apply_force(knockback * pull_power)
		drop_object.rpc()
		

## RPC for Syncing Animations from Players
@rpc("call_local")
func animations_handler(relative_directionality:Vector3):
	animation_tree.set("parameters/BlendSpace2D/blend_position",Vector2(relative_directionality.x, relative_directionality.y))
	animation_tree.set("parameters/Blend3/blend_amount", relative_directionality.z)

## RPC for Shooting
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


# Sensitivity Slider Connect
# Sensitivity Slider Connect
func _on_h_slider_value_changed(value: float) -> void:
	# Slider ki value agar 0-100 hai toh use 0.1 - 1.0 ke beech rakhein
	touch_sensitivity = value / 100.0 
	print("New Sensitivity: ", touch_sensitivity)

# Joystick Signal Connect
func _on_virtual_joystick_plus_analogic_changed(value: Vector2, _distance, _angle, _angle_clockwise, _angle_not_clockwise) -> void:
	joystick_vector = value # Isse movement shuru hogi
