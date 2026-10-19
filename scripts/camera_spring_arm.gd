extends Node3D

# --- 1. Free Look ---
@export_group("Free Look")
@export var mouse_sensibility: float = 0.003
@export_range(-90.0, 0.0, 0.1, "radians_as_degrees") var min_vertical_angle: float = deg_to_rad(-80.0)
@export_range(0.0, 90.0, 0.1, "radians_as_degrees") var max_vertical_angle: float = deg_to_rad(45.0)
@export_range(0.1, 10.0, 0.1) var free_spring_length: float = 1.0
@export var default_pivot_height: float = 1.65

# --- 2. Combat Framing ---
@export_group("Combat Framing")
@export_range(0.0, 60.0, 0.5, "radians_as_degrees") var shoulder_angle_offset: float = deg_to_rad(30.0)
@export_range(0.0, 2.0, 0.05) var shoulder_lateral_offset: float = 0.75 # Lateral offset in meters
@export_range(0.0, 1.0, 0.05) var focus_bias_to_enemy: float = 0.5     # 0.0 = player, 1.0 = enemy
@export_range(-45.0, 45.0, 0.5, "radians_as_degrees") var combat_pitch_offset: float = deg_to_rad(-12.0)
@export_range(0.1, 15.0, 0.1) var combat_base_distance: float = 1.0
@export_range(0.1, 15.0, 0.1) var combat_max_distance: float = 2.0

# --- 3. Obstacle Avoidance ---
@export_group("Obstacle Avoidance")
@export var wall_detection_distance: float = 1.6 # Clearance detection distance in meters
@export var shoulder_switch_speed: float = 5.0
@export var lock_tracking_speed: float = 8.0

# --- 4. Overhead Mode ---
@export_group("Overhead Mode")
@export_range(-90.0, 0.0, 0.5, "radians_as_degrees") var overhead_pitch: float = deg_to_rad(-42.0)
@export var overhead_height_lift: float = 0.5      # Extra vertical lift in narrow spaces
@export_range(0.1, 15.0, 0.1) var overhead_spring_length: float = 1.5

# --- 5. Framing Deadzone ---
@export_group("Framing Deadzone")
@export var deadzone_enabled: bool = true
@export_range(0.0, 45.0, 0.5, "radians_as_degrees") var deadzone_yaw: float = deg_to_rad(14.0)
@export_range(0.0, 30.0, 0.5, "radians_as_degrees") var deadzone_pitch: float = deg_to_rad(7.0)
@export var deadzone_tracking_speed: float = 6.0
@export var show_deadzone_debug: bool = false

@onready var spring_arm: SpringArm3D = $SpringArm3D

# Active target for lock-on framing (set by player.gd)
var lock_target: Node3D = null

# Smooth adaptive state variables
var current_shoulder_offset: float = deg_to_rad(30.0)
var target_shoulder_sign: float = 1.0 # 1.0 = right shoulder, -1.0 = left shoulder
var current_overhead_weight: float = 0.0

# Deadzone & Debug Overlay State
var is_acquiring_target: bool = false
var _previous_lock_target: Node3D = null
var debug_is_pushing: bool = false
var current_yaw_diff: float = 0.0
var current_pitch_diff: float = 0.0
var _last_valid_box_center: Vector2 = Vector2.ZERO
var _debug_canvas: CanvasLayer = null
var _debug_overlay: Control = null


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if is_instance_valid(spring_arm):
		spring_arm.spring_length = free_spring_length
	position = Vector3(0.0, default_pivot_height, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	# Mouse look only when NOT locked onto a target
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if not is_instance_valid(lock_target):
			rotation.y -= event.relative.x * mouse_sensibility
			rotation.y = wrapf(rotation.y, 0.0, TAU)

			rotation.x -= event.relative.y * mouse_sensibility
			rotation.x = clamp(rotation.x, min_vertical_angle, max_vertical_angle)

	# Manual zoom adjustment
	if event.is_action_pressed("wheel_up"):
		free_spring_length = maxf(0.1, free_spring_length - 0.25)
		if not is_instance_valid(lock_target):
			spring_arm.spring_length = free_spring_length
	elif event.is_action_pressed("wheel_down"):
		free_spring_length = minf(10.0, free_spring_length + 0.25)
		if not is_instance_valid(lock_target):
			spring_arm.spring_length = free_spring_length

	if event.is_action_pressed("toggle_mouse_capture"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
	if not is_inside_tree():
		return

	if is_instance_valid(lock_target) and lock_target.is_inside_tree():
		if lock_target != _previous_lock_target:
			_previous_lock_target = lock_target
			is_acquiring_target = true
		_update_lock_on_camera(delta)
	else:
		_previous_lock_target = null
		is_acquiring_target = false
		debug_is_pushing = false
		current_yaw_diff = 0.0
		current_pitch_diff = 0.0
		# Smoothly reset position and shoulder offset when unlocked
		position.x = lerp(position.x, 0.0, delta * 4.0)
		position.y = lerp(position.y, default_pivot_height, delta * 4.0)
		position.z = lerp(position.z, 0.0, delta * 4.0)
		current_shoulder_offset = lerp(current_shoulder_offset, shoulder_angle_offset, delta * 4.0)
		current_overhead_weight = lerp(current_overhead_weight, 0.0, delta * 4.0)

	_update_debug_overlay()


func _update_lock_on_camera(delta: float) -> void:
	if not is_inside_tree() or not is_instance_valid(lock_target) or not lock_target.is_inside_tree():
		return

	var player_node: Node3D = get_parent() as Node3D
	var player_pos: Vector3 = player_node.global_position if is_instance_valid(player_node) and player_node.is_inside_tree() else global_position
	var head_pos: Vector3 = player_pos + Vector3(0.0, default_pivot_height, 0.0)
	var target_pos: Vector3 = lock_target.global_position + Vector3(0.0, 1.2, 0.0)

	var to_target: Vector3 = target_pos - head_pos
	var horiz_dist: float = Vector2(to_target.x, to_target.z).length()

	if horiz_dist < 0.01:
		return

	var base_yaw: float = atan2(-to_target.x, -to_target.z)

	var forward_dir := Vector3(to_target.x, 0.0, to_target.z).normalized()
	var right_dir := Vector3(-forward_dir.z, 0.0, forward_dir.x)
	var left_dir := -right_dir

	var diag_right := (-forward_dir + right_dir).normalized()
	var diag_left := (-forward_dir + left_dir).normalized()

	# --- Obstacle Detection & Adaptive Shoulder Probing ---
	var probe_range := wall_detection_distance + 0.5
	var dist_right := minf(_probe_direction(head_pos, right_dir, probe_range), _probe_direction(head_pos, diag_right, probe_range))
	var dist_left := minf(_probe_direction(head_pos, left_dir, probe_range), _probe_direction(head_pos, diag_left, probe_range))

	var right_clear: bool = (dist_right >= wall_detection_distance)
	var left_clear: bool = (dist_left >= wall_detection_distance)

	var target_overhead := 0.0
	var target_offset := 0.0

	if right_clear and left_clear:
		# Both sides clear: maintain current preference, default to right
		target_offset = target_shoulder_sign * shoulder_angle_offset
	elif right_clear and not left_clear:
		# Left is blocked by wall: stay on right shoulder
		target_shoulder_sign = 1.0
		target_offset = shoulder_angle_offset
	elif left_clear and not right_clear:
		# Right is blocked by wall: switch to left shoulder!
		target_shoulder_sign = -1.0
		target_offset = -shoulder_angle_offset
	else:
		# Both sides constrained (narrow tunnel / corner): activate OVERHEAD mode
		target_offset = 0.0
		target_overhead = 1.0

	# Smoothly interpolate shoulder offset and overhead blend weight
	current_shoulder_offset = lerp(current_shoulder_offset, target_offset, shoulder_switch_speed * delta)
	current_overhead_weight = lerp(current_overhead_weight, target_overhead, shoulder_switch_speed * delta)

	# --- Calculate Angles & Transforms ---
	var desired_yaw: float = wrapf(base_yaw + current_shoulder_offset, 0.0, TAU)

	# Calculate normal pitch looking at midpoint
	var focus_point: Vector3 = head_pos.lerp(target_pos, focus_bias_to_enemy)
	var dy: float = focus_point.y - head_pos.y
	var normal_pitch: float = clampf(atan2(dy, horiz_dist) + combat_pitch_offset, min_vertical_angle, max_vertical_angle)

	# Blend normal pitch with overhead pitch
	var final_pitch: float = lerp(normal_pitch, overhead_pitch, current_overhead_weight)

	# --- Smooth rotation with Framing Deadzone ---
	var yaw_diff: float = wrapf(desired_yaw - rotation.y, -PI, PI)
	var pitch_diff: float = final_pitch - rotation.x

	debug_is_pushing = false

	if deadzone_enabled:
		if is_acquiring_target:
			# Smooth initial snap toward target center
			rotation.y = lerp_angle(rotation.y, desired_yaw, lock_tracking_speed * delta)
			rotation.x = lerp(rotation.x, final_pitch, lock_tracking_speed * delta)
			if absf(yaw_diff) <= maxf(deg_to_rad(2.0), deadzone_yaw * 0.25) and absf(pitch_diff) <= maxf(deg_to_rad(1.5), deadzone_pitch * 0.25):
				is_acquiring_target = false
		else:
			# Horizontal Deadzone (Yaw): camera remains still unless target pushes frame edge
			if absf(yaw_diff) > deadzone_yaw:
				var push_yaw: float = yaw_diff - signf(yaw_diff) * deadzone_yaw
				if absf(push_yaw) <= deg_to_rad(0.35):
					rotation.y = wrapf(rotation.y + push_yaw, 0.0, TAU)
				else:
					debug_is_pushing = true
					var target_yaw_edge: float = rotation.y + push_yaw
					rotation.y = lerp_angle(rotation.y, target_yaw_edge, deadzone_tracking_speed * delta)

			# Vertical Deadzone (Pitch): pitch remains still unless target pushes frame edge
			if absf(pitch_diff) > deadzone_pitch:
				var push_pitch: float = pitch_diff - signf(pitch_diff) * deadzone_pitch
				if absf(push_pitch) <= deg_to_rad(0.35):
					rotation.x += push_pitch
				else:
					debug_is_pushing = true
					var target_pitch_edge: float = rotation.x + push_pitch
					rotation.x = lerp(rotation.x, target_pitch_edge, deadzone_tracking_speed * delta)
	else:
		rotation.y = lerp_angle(rotation.y, desired_yaw, lock_tracking_speed * delta)
		rotation.x = lerp(rotation.x, final_pitch, lock_tracking_speed * delta)

	# Update post-rotation angular offsets for exact HUD deadzone box sync
	current_yaw_diff = wrapf(desired_yaw - rotation.y, -PI, PI)
	current_pitch_diff = final_pitch - rotation.x

	# Dynamic lateral shift along camera's horizontal right vector (stays still when camera rotation is still)
	var cam_right_dir := Vector3(cos(rotation.y), 0.0, -sin(rotation.y))
	var target_lateral_shift := cam_right_dir * (target_shoulder_sign * shoulder_lateral_offset * (1.0 - current_overhead_weight))
	position.x = lerp(position.x, target_lateral_shift.x, shoulder_switch_speed * delta)
	position.z = lerp(position.z, target_lateral_shift.z, shoulder_switch_speed * delta)

	# Dynamic pivot height lift in overhead mode
	var target_height: float = default_pivot_height + (overhead_height_lift * current_overhead_weight)
	position.y = lerp(position.y, target_height, lock_tracking_speed * delta)

	# Dynamic spring length: scales between combat_base_distance and combat_max_distance
	var min_combat_len: float = minf(combat_base_distance, combat_max_distance)
	var max_combat_len: float = maxf(combat_base_distance, combat_max_distance)
	var target_len: float = clampf(remap(horiz_dist, 2.0, 9.0, combat_base_distance, combat_max_distance), min_combat_len, max_combat_len)
	if current_overhead_weight > 0.01:
		target_len = lerp(target_len, overhead_spring_length, current_overhead_weight)

	spring_arm.spring_length = lerp(spring_arm.spring_length, target_len, lock_tracking_speed * delta)


# Probes for obstacles along a given direction from origin
func _probe_direction(origin: Vector3, dir: Vector3, max_dist: float) -> float:
	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return max_dist

	var target := origin + dir * max_dist
	var parent_body: CollisionObject3D = get_parent() as CollisionObject3D
	var exclude: Array[RID] = []
	if is_instance_valid(parent_body):
		exclude.append(parent_body.get_rid())

	var query := PhysicsRayQueryParameters3D.create(origin, target, 1, exclude)
	var result := space_state.intersect_ray(query)

	if result.is_empty():
		return max_dist
	return origin.distance_to(result.position)


func _update_debug_overlay() -> void:
	if show_deadzone_debug:
		if not is_instance_valid(_debug_canvas):
			_debug_canvas = CanvasLayer.new()
			_debug_canvas.layer = 100
			add_child(_debug_canvas)
			var overlay := DeadzoneDebugOverlay.new()
			overlay.pivot = self
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_debug_canvas.add_child(overlay)
			_debug_overlay = overlay
	else:
		if is_instance_valid(_debug_canvas):
			_debug_canvas.queue_free()
			_debug_canvas = null
			_debug_overlay = null


# --- Debug HUD Overlay Class ---
class DeadzoneDebugOverlay extends Control:
	var pivot: Node3D = null

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if not is_instance_valid(pivot) or not pivot.deadzone_enabled:
			return

		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam == null:
			if is_instance_valid(pivot):
				cam = pivot.get_node_or_null("Camera3D") as Camera3D
		if cam == null:
			return

		var vp_size: Vector2 = get_viewport_rect().size
		if vp_size.y <= 0:
			return

		var v_fov_rad: float = deg_to_rad(cam.fov) * 0.5
		if v_fov_rad <= 0.001:
			return
		var aspect: float = vp_size.x / maxf(1.0, vp_size.y)
		var h_fov_rad: float = atan(tan(v_fov_rad) * aspect)
		if h_fov_rad <= 0.001:
			return

		var half_w: float = (tan(pivot.deadzone_yaw) / tan(h_fov_rad)) * (vp_size.x * 0.5)
		var half_h: float = (tan(pivot.deadzone_pitch) / tan(v_fov_rad)) * (vp_size.y * 0.5)

		var is_locked: bool = is_instance_valid(pivot.lock_target)
		var is_pushing: bool = pivot.debug_is_pushing
		var is_acquiring: bool = pivot.is_acquiring_target

		var box_center: Vector2 = vp_size * 0.5
		var target_screen: Vector2 = Vector2.ZERO
		var target_visible: bool = false

		if is_locked and is_instance_valid(pivot.lock_target):
			var target_pos: Vector3 = pivot.lock_target.global_position + Vector3(0.0, 1.2, 0.0)
			if not cam.is_position_behind(target_pos):
				target_visible = true
				target_screen = cam.unproject_position(target_pos)
				var clamped_yaw_diff: float = clampf(pivot.current_yaw_diff, -PI * 0.4, PI * 0.4)
				var clamped_pitch_diff: float = clampf(pivot.current_pitch_diff, -PI * 0.4, PI * 0.4)
				var target_offset_from_center := Vector2(
					-(tan(clamped_yaw_diff) / tan(h_fov_rad)) * (vp_size.x * 0.5),
					-(tan(clamped_pitch_diff) / tan(v_fov_rad)) * (vp_size.y * 0.5)
				)
				box_center = target_screen - target_offset_from_center
				pivot._last_valid_box_center = box_center
			elif pivot._last_valid_box_center != Vector2.ZERO:
				box_center = pivot._last_valid_box_center
		elif pivot._last_valid_box_center != Vector2.ZERO:
			box_center = pivot._last_valid_box_center

		var box_rect := Rect2(box_center.x - half_w, box_center.y - half_h, half_w * 2.0, half_h * 2.0)

		var box_color: Color = Color(0.2, 0.9, 0.4, 0.85) # Green
		var bg_color: Color = Color(0.2, 0.9, 0.4, 0.08)
		var status_text: String = "DEADZONE: STILL (STABLE HORIZON)"
		var status_color: Color = Color(0.3, 1.0, 0.5, 1.0)

		if not is_locked:
			box_color = Color(0.4, 0.7, 1.0, 0.6)
			bg_color = Color(0.4, 0.7, 1.0, 0.04)
			status_text = "DEADZONE PREVIEW (FREE LOOK - NO TARGET)"
			status_color = Color(0.5, 0.8, 1.0, 0.8)
		elif is_acquiring:
			box_color = Color(0.2, 0.7, 1.0, 0.85) # Cyan
			bg_color = Color(0.2, 0.7, 1.0, 0.08)
			status_text = "ACQUIRING TARGET..."
			status_color = Color(0.3, 0.8, 1.0, 1.0)
		elif is_pushing:
			box_color = Color(1.0, 0.65, 0.15, 0.95) # Orange
			bg_color = Color(1.0, 0.65, 0.15, 0.12)
			status_text = "DEADZONE: EDGE PUSHING (TURNING)"
			status_color = Color(1.0, 0.75, 0.2, 1.0)

		# Draw translucent filled box and thin border
		draw_rect(box_rect, bg_color, true)
		draw_rect(box_rect, box_color, false, 2.0)

		# Highlighted corner accents
		var corner_len: float = clampf(minf(half_w, half_h) * 0.35, 10.0, 28.0)
		# Top-Left
		draw_line(Vector2(box_rect.position.x, box_rect.position.y), Vector2(box_rect.position.x + corner_len, box_rect.position.y), box_color, 3.5)
		draw_line(Vector2(box_rect.position.x, box_rect.position.y), Vector2(box_rect.position.x, box_rect.position.y + corner_len), box_color, 3.5)
		# Top-Right
		draw_line(Vector2(box_rect.end.x, box_rect.position.y), Vector2(box_rect.end.x - corner_len, box_rect.position.y), box_color, 3.5)
		draw_line(Vector2(box_rect.end.x, box_rect.position.y), Vector2(box_rect.end.x, box_rect.position.y + corner_len), box_color, 3.5)
		# Bottom-Left
		draw_line(Vector2(box_rect.position.x, box_rect.end.y), Vector2(box_rect.position.x + corner_len, box_rect.end.y), box_color, 3.5)
		draw_line(Vector2(box_rect.position.x, box_rect.end.y), Vector2(box_rect.position.x, box_rect.end.y - corner_len), box_color, 3.5)
		# Bottom-Right
		draw_line(Vector2(box_rect.end.x, box_rect.end.y), Vector2(box_rect.end.x - corner_len, box_rect.end.y), box_color, 3.5)
		draw_line(Vector2(box_rect.end.x, box_rect.end.y), Vector2(box_rect.end.x, box_rect.end.y - corner_len), box_color, 3.5)

		# Crosshair in deadzone center
		draw_line(box_center - Vector2(7, 0), box_center + Vector2(7, 0), Color(box_color.r, box_color.g, box_color.b, 0.6), 1.5)
		draw_line(box_center - Vector2(0, 7), box_center + Vector2(0, 7), Color(box_color.r, box_color.g, box_color.b, 0.6), 1.5)

		# Project target 3D position to 2D screen
		if target_visible:
			draw_circle(target_screen, 4.0, Color.RED)
			draw_arc(target_screen, 12.0, 0.0, TAU, 16, Color.RED, 2.0)
			draw_line(target_screen - Vector2(16, 0), target_screen + Vector2(16, 0), Color.RED, 1.5)
			draw_line(target_screen - Vector2(0, 16), target_screen + Vector2(0, 16), Color.RED, 1.5)

		# Status text
		var font: Font = get_theme_default_font()
		var text_pos := Vector2(box_rect.position.x + 4.0, box_rect.position.y - 8.0)
		draw_string(font, text_pos, status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, status_color)
