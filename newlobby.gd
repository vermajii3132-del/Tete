extends Node3D

@onready var player = $Node3D/Player
@onready var camera = $Camera3D
@onready var start_btn = $CanvasLayer/MainUI/BottomRight/StartBtn
@onready var right_sidebar = $CanvasLayer/MainUI/RightSidebar
@onready var friends_toggle = $CanvasLayer/MainUI/LeftSidebar/MarginContainer/VBoxContainer/FriendsToggle
@onready var close_friends = $CanvasLayer/MainUI/RightSidebar/MarginContainer/VBoxContainer/Header/CloseFriends

@onready var solo_btn = $CanvasLayer/MainUI/BottomRight/ModeSelector/SoloBtn
@onready var duo_btn = $CanvasLayer/MainUI/BottomRight/ModeSelector/DuoBtn
@onready var squad_btn = $CanvasLayer/MainUI/BottomRight/ModeSelector/SquadBtn
@onready var tpp_label = $CanvasLayer/MainUI/BottomRight/TppLabel/MarginContainer/Label

@onready var mail_btn = $CanvasLayer/MainUI/TopBar/MarginContainer/HBoxContainer/TopRightBtns/MailBtn
@onready var settings_btn = $CanvasLayer/MainUI/TopBar/MarginContainer/HBoxContainer/TopRightBtns/SettingsBtn

var rotation_speed := 0.4
var is_dragging := false
var last_mouse_pos := Vector2.ZERO

# Game mode
enum GameMode { SOLO, DUO, SQUAD }
var current_mode := GameMode.SOLO
var squad_members := []
var max_squad_size := 4

# Style resources
var style_normal: StyleBoxFlat
var style_active: StyleBoxFlat

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Camera player ki taraf
	camera.look_at(player.global_position + Vector3(0, 1.3, 0), Vector3.UP)

	# Player FPS HUD hide
	_hide_player_fps_hud()

	# Styles save karo
	style_normal = solo_btn.get_theme_stylebox("normal").duplicate()
	style_active = solo_btn.get_theme_stylebox("normal").duplicate()

	# === ALL BUTTON SIGNALS ===
	start_btn.pressed.connect(_on_start_pressed)

	# Friends toggle
	friends_toggle.pressed.connect(_on_toggle_friends)
	close_friends.pressed.connect(_on_toggle_friends)

	# Mode selector
	solo_btn.pressed.connect(_on_mode_solo)
	duo_btn.pressed.connect(_on_mode_duo)
	squad_btn.pressed.connect(_on_mode_squad)

	# Top bar
	mail_btn.pressed.connect(_on_mail_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)

	# Left sidebar
	var left_vbox = $CanvasLayer/MainUI/LeftSidebar/MarginContainer/VBoxContainer
	left_vbox.get_node("MissionsBtn").pressed.connect(_on_missions_pressed)
	left_vbox.get_node("SeasonBtn").pressed.connect(_on_season_pressed)
	left_vbox.get_node("ClanBtn").pressed.connect(_on_clan_pressed)
	left_vbox.get_node("SkillBtn").pressed.connect(_on_skill_pressed)

	# Bottom bar
	var bottom_hbox = $CanvasLayer/MainUI/BottomBar/MarginContainer/HBoxContainer
	bottom_hbox.get_node("TroopBtn").pressed.connect(_on_troop_pressed)
	bottom_hbox.get_node("GarageBtn").pressed.connect(_on_garage_pressed)
	bottom_hbox.get_node("SocialBtn").pressed.connect(_on_social_pressed)
	bottom_hbox.get_node("ArmoryBtn").pressed.connect(_on_armory_pressed)
	bottom_hbox.get_node("SkillsBtn").pressed.connect(_on_skills_pressed)
	bottom_hbox.get_node("MarketBtn").pressed.connect(_on_market_pressed)

	# Team chat
	$CanvasLayer/MainUI/BottomLeft/MarginContainer/VBoxContainer/TeamBtn.pressed.connect(_on_team_pressed)

	# Default
	_update_mode_ui()

func _hide_player_fps_hud():
	var player_canvas = player.get_node_or_null("CanvasLayer")
	if player_canvas:
		player_canvas.hide()
	var head = player.get_node_or_null("Head")
	if head:
		head.hide()
	var flashlight = player.get_node_or_null("Head/Camera3d/Flashlight")
	if flashlight:
		flashlight.hide()

func _input(event):
	# PC Mouse drag
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and not _is_mouse_over_ui():
				is_dragging = true
			else:
				is_dragging = false

	if event is InputEventMouseMotion and is_dragging:
		if not _is_mouse_over_ui():
			player.rotate_y(deg_to_rad(event.relative.x * rotation_speed))

	# Mobile touch
	if event is InputEventScreenTouch:
		if event.pressed and not _is_mouse_over_ui():
			is_dragging = true
			last_mouse_pos = event.position
		else:
			is_dragging = false

	if event is InputEventScreenDrag and is_dragging:
		if not _is_mouse_over_ui():
			var delta = event.position - last_mouse_pos
			player.rotate_y(deg_to_rad(delta.x * rotation_speed))
			last_mouse_pos = event.position

func _is_mouse_over_ui() -> bool:
	var mouse_pos = get_viewport().get_mouse_position()
	var ui_rects = [
		$CanvasLayer/MainUI/TopBar.get_global_rect(),
		$CanvasLayer/MainUI/LeftSidebar.get_global_rect(),
		$CanvasLayer/MainUI/RightSidebar.get_global_rect(),
		$CanvasLayer/MainUI/BottomBar.get_global_rect(),
		$CanvasLayer/MainUI/BottomRight.get_global_rect(),
		$CanvasLayer/MainUI/BottomLeft.get_global_rect(),
	]
	for rect in ui_rects:
		if rect.has_point(mouse_pos):
			return true
	return false

# ===== FRIENDS TOGGLE =====
func _on_toggle_friends():
	right_sidebar.visible = !right_sidebar.visible

# ===== MODE SELECTOR =====
func _on_mode_solo():
	current_mode = GameMode.SOLO
	_update_mode_ui()
	print("Mode: SOLO")

func _on_mode_duo():
	current_mode = GameMode.DUO
	_update_mode_ui()
	print("Mode: DUO")

func _on_mode_squad():
	current_mode = GameMode.SQUAD
	_update_mode_ui()
	print("Mode: SQUAD")

func _update_mode_ui():
	# Reset all
	solo_btn.add_theme_stylebox_override("normal", style_normal)
	solo_btn.add_theme_stylebox_override("hover", style_normal)
	duo_btn.add_theme_stylebox_override("normal", style_normal)
	duo_btn.add_theme_stylebox_override("hover", style_normal)
	squad_btn.add_theme_stylebox_override("normal", style_normal)
	squad_btn.add_theme_stylebox_override("hover", style_normal)

	# Active + TPP label update
	match current_mode:
		GameMode.SOLO:
			solo_btn.add_theme_stylebox_override("normal", style_active)
			solo_btn.add_theme_stylebox_override("hover", style_active)
			tpp_label.text = "TPP SOLO"
		GameMode.DUO:
			duo_btn.add_theme_stylebox_override("normal", style_active)
			duo_btn.add_theme_stylebox_override("hover", style_active)
			tpp_label.text = "TPP DUO"
		GameMode.SQUAD:
			squad_btn.add_theme_stylebox_override("normal", style_active)
			squad_btn.add_theme_stylebox_override("hover", style_active)
			tpp_label.text = "TPP SQUAD"

# ===== SQUAD SYSTEM =====
func invite_friend(friend_name: String):
	if current_mode == GameMode.SOLO:
		print("Solo mode mein invite nahi!")
		return
	if squad_members.size() >= max_squad_size - 1:
		print("Squad full! Max 4 players.")
		return
	if friend_name not in squad_members:
		squad_members.append(friend_name)
		print(friend_name + " squad mein add!")
		_update_squad_display()

func remove_from_squad(friend_name: String):
	if friend_name in squad_members:
		squad_members.erase(friend_name)
		print(friend_name + " squad se hataya!")
		_update_squad_display()

func _update_squad_display():
	print("Squad: " + str(squad_members))

# ===== ALL BUTTON CALLBACKS =====
func _on_start_pressed():
	print("START! Mode: " + str(current_mode))
	# Globals.set_gamemode(Globals.GameModes.practice)
	# get_tree().change_scene_to_file("res://levels/Main/Main.tscn")

func _on_mail_pressed():
	print("Mail opened")

func _on_settings_pressed():
	print("Settings opened")

func _on_missions_pressed():
	print("Missions opened")

func _on_season_pressed():
	print("Season opened")

func _on_clan_pressed():
	print("Clan opened")

func _on_skill_pressed():
	print("Skills opened")

func _on_troop_pressed():
	print("Troop opened")

func _on_garage_pressed():
	print("Garage opened")

func _on_social_pressed():
	print("Social opened")

func _on_armory_pressed():
	print("Armory opened")

func _on_skills_pressed():
	print("Skills opened")

func _on_market_pressed():
	print("Market opened")

func _on_team_pressed():
	print("Team chat toggled")
