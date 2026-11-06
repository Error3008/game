class_name CombatHUD
extends CanvasLayer

## Comprehensive Combat HUD for Player and Locked Target.
## Displays:
## - Bottom of screen: Player Health bar (with numbers) and Stamina bar (blue, with numbers).
## - Overhead in 3D/2D: Floating Target Health and Stamina bars when locked onto an enemy.

@export_group("Target Actor")
@export var player_actor: CombatCharacter3D = null

@export_group("Player HUD Layout")
@export var show_player_hud: bool = true
@export var player_bar_width: float = 340.0
@export var player_bar_height: float = 20.0
@export var player_bottom_margin: float = 40.0
@export var player_bar_spacing: float = 8.0

@export_group("Target Overhead Layout")
@export var show_overhead_target_hud: bool = true
@export var overhead_vertical_offset: float = 2.25
@export var target_bar_width: float = 190.0
@export var target_bar_height: float = 13.0
@export var target_bar_spacing: float = 5.0

@export_group("Colors")
@export var health_fill_color: Color = Color(0.88, 0.18, 0.22, 1.0)
@export var health_bg_color: Color = Color(0.14, 0.04, 0.05, 0.85)
@export var stamina_fill_color: Color = Color(0.18, 0.58, 0.98, 1.0) # Vibrant blue
@export var stamina_bg_color: Color = Color(0.04, 0.10, 0.22, 0.85)
@export var guard_break_color: Color = Color(1.0, 0.82, 0.15, 1.0)
@export var border_color: Color = Color(0.0, 0.0, 0.0, 0.8)
@export var text_outline_color: Color = Color(0.0, 0.0, 0.0, 0.95)

@export_group("Animation & Smoothing")
@export var smooth_bars: bool = true
@export var bar_lerp_speed: float = 14.0

# --- Node Hierarchy ---
var _root_control: Control = null

# Player UI Nodes
var _player_panel: VBoxContainer = null
var _player_hp_bar: ProgressBar = null
var _player_hp_label: Label = null
var _player_stamina_bar: ProgressBar = null
var _player_stamina_label: Label = null

# Target Overhead UI Nodes
var _target_panel: VBoxContainer = null
var _target_name_label: Label = null
var _target_hp_bar: ProgressBar = null
var _target_hp_label: Label = null
var _target_stamina_bar: ProgressBar = null
var _target_stamina_label: Label = null
var _target_status_label: Label = null

# Smoothed values
var _displayed_player_hp: float = 100.0
var _displayed_player_stamina: float = 100.0
var _displayed_target_hp: float = 100.0
var _displayed_target_stamina: float = 100.0


func _ready() -> void:
	layer = 10
	if player_actor == null and get_parent() is CombatCharacter3D:
		player_actor = get_parent() as CombatCharacter3D

	_build_ui()


func _build_ui() -> void:
	_root_control = Control.new()
	_root_control.name = "CombatUIRoot"
	_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_control)

	_build_player_hud()
	_build_target_hud()


func _build_player_hud() -> void:
	_player_panel = VBoxContainer.new()
	_player_panel.name = "PlayerPanel"
	_player_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_panel.add_theme_constant_override("separation", int(player_bar_spacing))
	_root_control.add_child(_player_panel)

	# Configure Bottom-Center anchor
	_player_panel.anchor_left = 0.5
	_player_panel.anchor_right = 0.5
	_player_panel.anchor_top = 1.0
	_player_panel.anchor_bottom = 1.0

	var total_panel_height: float = player_bar_height * 2.0 + player_bar_spacing
	_player_panel.offset_left = -player_bar_width * 0.5
	_player_panel.offset_right = player_bar_width * 0.5
	_player_panel.offset_top = -player_bottom_margin - total_panel_height
	_player_panel.offset_bottom = -player_bottom_margin

	# Player HP Bar
	var hp_pair := _create_custom_bar(player_bar_width, player_bar_height, health_fill_color, health_bg_color)
	_player_hp_bar = hp_pair["bar"]
	_player_hp_label = hp_pair["label"]
	_player_panel.add_child(_player_hp_bar)

	# Player Stamina Bar
	var stam_pair := _create_custom_bar(player_bar_width, player_bar_height, stamina_fill_color, stamina_bg_color)
	_player_stamina_bar = stam_pair["bar"]
	_player_stamina_label = stam_pair["label"]
	_player_panel.add_child(_player_stamina_bar)

	_player_panel.visible = show_player_hud


func _build_target_hud() -> void:
	_target_panel = VBoxContainer.new()
	_target_panel.name = "TargetOverheadPanel"
	_target_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_panel.add_theme_constant_override("separation", int(target_bar_spacing))
	_target_panel.custom_minimum_size = Vector2(target_bar_width, 0.0)
	_target_panel.visible = false
	_root_control.add_child(_target_panel)

	# Target Name & Status Label
	_target_name_label = Label.new()
	_target_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_target_name_label.add_theme_font_size_override("font_size", 12)
	_target_name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	_target_name_label.add_theme_color_override("font_outline_color", text_outline_color)
	_target_name_label.add_theme_constant_override("outline_size", 3)
	_target_name_label.text = "Target"
	_target_panel.add_child(_target_name_label)

	# Target HP Bar
	var hp_pair := _create_custom_bar(target_bar_width, target_bar_height, health_fill_color, health_bg_color, 11)
	_target_hp_bar = hp_pair["bar"]
	_target_hp_label = hp_pair["label"]
	_target_panel.add_child(_target_hp_bar)

	# Target Stamina Bar
	var stam_pair := _create_custom_bar(target_bar_width, target_bar_height, stamina_fill_color, stamina_bg_color, 11)
	_target_stamina_bar = stam_pair["bar"]
	_target_stamina_label = stam_pair["label"]
	_target_panel.add_child(_target_stamina_bar)

	# Target Guard Break Alert
	_target_status_label = Label.new()
	_target_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_target_status_label.add_theme_font_size_override("font_size", 12)
	_target_status_label.add_theme_color_override("font_color", guard_break_color)
	_target_status_label.add_theme_color_override("font_outline_color", Color(0.2, 0.0, 0.0, 1.0))
	_target_status_label.add_theme_constant_override("outline_size", 4)
	_target_status_label.text = "⚡ GUARD BROKEN ⚡"
	_target_status_label.visible = false
	_target_panel.add_child(_target_status_label)


func _create_custom_bar(width: float, height: float, fill_col: Color, bg_col: Color, font_size: int = 12) -> Dictionary:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, height)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = bg_col
	bg_style.set_corner_radius_all(3)
	bg_style.border_width_left = 1
	bg_style.border_width_top = 1
	bg_style.border_width_right = 1
	bg_style.border_width_bottom = 1
	bg_style.border_color = border_color
	bar.add_theme_stylebox_override("background", bg_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_col
	fill_style.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill_style)

	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", text_outline_color)
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(label)

	return {"bar": bar, "label": label}


func _process(delta: float) -> void:
	if not is_instance_valid(player_actor):
		return

	_update_player_hud(delta)
	_update_target_hud(delta)


func _update_player_hud(delta: float) -> void:
	if not show_player_hud:
		_player_panel.visible = false
		return

	_player_panel.visible = true

	var target_hp := player_actor.current_health
	var max_hp := player_actor.max_health
	var target_stam := player_actor.current_stamina
	var max_stam := player_actor.max_stamina

	if smooth_bars:
		_displayed_player_hp = lerpf(_displayed_player_hp, target_hp, bar_lerp_speed * delta)
		_displayed_player_stamina = lerpf(_displayed_player_stamina, target_stam, bar_lerp_speed * delta)
	else:
		_displayed_player_hp = target_hp
		_displayed_player_stamina = target_stam

	_player_hp_bar.max_value = max_hp
	_player_hp_bar.value = _displayed_player_hp
	_player_hp_label.text = "HP  %d / %d" % [roundi(_displayed_player_hp), roundi(max_hp)]

	_player_stamina_bar.max_value = max_stam
	_player_stamina_bar.value = _displayed_player_stamina
	_player_stamina_label.text = "STAMINA  %d / %d" % [roundi(_displayed_player_stamina), roundi(max_stam)]


func _update_target_hud(delta: float) -> void:
	if not show_overhead_target_hud:
		_target_panel.visible = false
		return

	var target: Node3D = player_actor.current_target
	if not is_instance_valid(target) or not target.is_inside_tree():
		_target_panel.visible = false
		return

	# If target is dead, hide overhead bar
	if target.has_method("is_alive") and not target.is_alive():
		_target_panel.visible = false
		return

	var cam := get_viewport().get_camera_3d()
	if not is_instance_valid(cam):
		_target_panel.visible = false
		return

	var head_pos := target.global_position + Vector3(0.0, overhead_vertical_offset, 0.0)
	if cam.is_position_behind(head_pos):
		_target_panel.visible = false
		return

	var screen_pos := cam.unproject_position(head_pos)
	var panel_size := _target_panel.size
	_target_panel.position = screen_pos - Vector2(panel_size.x * 0.5, panel_size.y)
	_target_panel.visible = true

	# Target Name
	_target_name_label.text = String(target.name).replace("_", " ")

	# Health stats
	var target_hp := 100.0
	var target_max_hp := 100.0
	if "current_health" in target:
		target_hp = target.current_health
	elif "health_component" in target and is_instance_valid(target.health_component):
		target_hp = target.health_component.current_health
	if "max_health" in target:
		target_max_hp = target.max_health
	elif "health_component" in target and is_instance_valid(target.health_component):
		target_max_hp = target.health_component.max_health

	# Stamina stats
	var target_stam := 100.0
	var target_max_stam := 100.0
	if "current_stamina" in target:
		target_stam = target.current_stamina
	elif "stamina_component" in target and is_instance_valid(target.stamina_component):
		target_stam = target.stamina_component.current_stamina
	if "max_stamina" in target:
		target_max_stam = target.max_stamina
	elif "stamina_component" in target and is_instance_valid(target.stamina_component):
		target_max_stam = target.stamina_component.max_stamina

	if smooth_bars:
		_displayed_target_hp = lerpf(_displayed_target_hp, target_hp, bar_lerp_speed * delta)
		_displayed_target_stamina = lerpf(_displayed_target_stamina, target_stam, bar_lerp_speed * delta)
	else:
		_displayed_target_hp = target_hp
		_displayed_target_stamina = target_stam

	_target_hp_bar.max_value = target_max_hp
	_target_hp_bar.value = _displayed_target_hp
	_target_hp_label.text = "HP  %d / %d" % [roundi(_displayed_target_hp), roundi(target_max_hp)]

	_target_stamina_bar.max_value = target_max_stam
	_target_stamina_bar.value = _displayed_target_stamina
	_target_stamina_label.text = "STAMINA  %d / %d" % [roundi(_displayed_target_stamina), roundi(target_max_stam)]

	# Check Guard Broken / Stagger state
	var is_guard_broken := false
	if "is_staggered" in target and target.is_staggered and target_stam <= 0.05:
		is_guard_broken = true

	_target_status_label.visible = is_guard_broken
