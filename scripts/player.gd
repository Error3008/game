extends CharacterBody3D

# --- Movement Speeds ---
@export_group("Movement Speeds")
@export var walk_speed: float = 2.5
@export var run_speed: float = 5.0
@export var combat_walk_speed: float = 2.4
@export var combat_strafe_speed: float = 2.0
@export var accel: float = 10.0
@export var decel: float = 12.0
@export var combat_accel: float = 8.0
@export var lerp_angle_weight_scale: float = 10.0
@export var combat_rotation_speed: float = 12.0

# --- Target Lock Settings ---
@export_group("Target Lock")
@export var auto_lock_distance: float = 9.0   # Distance to automatically acquire target
@export var max_lock_distance: float = 16.0   # Distance to disengage lock
@export var break_lock_on_sprint: bool = true # Pressing Shift drops lock for free running

# --- Animation ---
@export_group("Animation")
@export var anim_speed_multiplier: float = 1.0
@export var combat_mode_blend_speed: float = 6.0
@export var combat_movement_blend_speed: float = 8.0

# --- Node references ---
@onready var pawn: Node3D = $pawn
@onready var animation_tree: AnimationTree = $pawn/AnimationTree
@onready var spring_arm_pivot: Node3D = $SpringArmPivot

# Lock-on state
var is_lock_enabled: bool = false
var current_target: Node3D = null

# Animation targets
var target_combat_mode: float = 0.0
var target_combat_movement: Vector2 = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("lock_target"):
		is_lock_enabled = not is_lock_enabled
		if is_lock_enabled:
			_find_best_target()
		else:
			_clear_target()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	_update_target_lock()

	if is_instance_valid(current_target):
		_process_locked_movement(delta)
	else:
		_process_free_movement(delta)

	_update_animations(delta)
	move_and_slide()


# --- Target Lock Management ---

func _update_target_lock() -> void:
	# Sprint cancels lock-on and disables combat mode to let player disengage freely
	if break_lock_on_sprint and Input.is_action_pressed("shift"):
		if is_lock_enabled or is_instance_valid(current_target):
			is_lock_enabled = false
			_clear_target()
		return

	if not is_lock_enabled:
		if is_instance_valid(current_target):
			_clear_target()
		return

	if is_instance_valid(current_target):
		var dist := global_position.distance_to(current_target.global_position)
		if dist > max_lock_distance:
			is_lock_enabled = false
			_clear_target()
	else:
		# Auto-lock check only while combat lock toggle is enabled
		_check_auto_lock()


func _check_auto_lock() -> void:
	if not is_inside_tree():
		return
	var enemies := get_tree().get_nodes_in_group("enemy")
	var closest_enemy: Node3D = null
	var closest_dist := auto_lock_distance

	for enemy in enemies:
		if enemy is Node3D and is_instance_valid(enemy):
			var dist := global_position.distance_to(enemy.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_enemy = enemy

	if closest_enemy != null:
		_set_target(closest_enemy)


func _find_best_target() -> void:
	if not is_inside_tree():
		return
	var enemies := get_tree().get_nodes_in_group("enemy")
	var best_enemy: Node3D = null
	var min_dist := max_lock_distance

	for enemy in enemies:
		if enemy is Node3D and is_instance_valid(enemy):
			var dist := global_position.distance_to(enemy.global_position)
			if dist < min_dist:
				min_dist = dist
				best_enemy = enemy

	if best_enemy != null:
		_set_target(best_enemy)


func _set_target(target: Node3D) -> void:
	current_target = target
	if is_instance_valid(spring_arm_pivot) and "lock_target" in spring_arm_pivot:
		spring_arm_pivot.lock_target = target


func _clear_target() -> void:
	current_target = null
	if is_instance_valid(spring_arm_pivot) and "lock_target" in spring_arm_pivot:
		spring_arm_pivot.lock_target = null


# --- Movement Processing ---

func _process_free_movement(delta: float) -> void:
	target_combat_mode = 0.0
	target_combat_movement = Vector2.ZERO

	var input_dir := Input.get_vector("a", "d", "w", "s")
	var cam_dir := (spring_arm_pivot.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var direction := Vector3(cam_dir.x, 0.0, cam_dir.z).normalized()

	if direction != Vector3.ZERO:
		var target_angle := atan2(direction.x, direction.z)
		pawn.rotation.y = lerp_angle(pawn.rotation.y, target_angle, lerp_angle_weight_scale * delta)

		var target_speed := run_speed if Input.is_action_pressed("shift") else walk_speed
		velocity.x = lerp(velocity.x, direction.x * target_speed, accel * delta)
		velocity.z = lerp(velocity.z, direction.z * target_speed, accel * delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, decel * delta)
		velocity.z = lerp(velocity.z, 0.0, decel * delta)


func _process_locked_movement(delta: float) -> void:
	target_combat_mode = 1.0

	# Always face enemy during lock-on
	var to_enemy := current_target.global_position - global_position
	to_enemy.y = 0.0
	if to_enemy.length_squared() > 0.001:
		var target_angle := atan2(to_enemy.x, to_enemy.z)
		pawn.rotation.y = lerp_angle(pawn.rotation.y, target_angle, combat_rotation_speed * delta)

	# WASD input relative to enemy:
	# w = advance towards enemy, s = retreat from enemy
	# a = strafe left around enemy, d = strafe right around enemy
	var input_dir := Input.get_vector("a", "d", "w", "s")
	var forward_step := -input_dir.y
	var lateral_step := input_dir.x

	target_combat_movement = Vector2(lateral_step, forward_step)

	if input_dir != Vector2.ZERO:
		var forward_basis: Vector3 = pawn.global_transform.basis.z
		var right_basis: Vector3 = -pawn.global_transform.basis.x

		var move_dir := (forward_basis * forward_step + right_basis * lateral_step).normalized()
		var speed := combat_strafe_speed if absf(lateral_step) > 0.1 else combat_walk_speed

		velocity.x = lerp(velocity.x, move_dir.x * speed, combat_accel * delta)
		velocity.z = lerp(velocity.z, move_dir.z * speed, combat_accel * delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, decel * delta)
		velocity.z = lerp(velocity.z, 0.0, decel * delta)


# --- AnimationTree Blending ---

func _update_animations(delta: float) -> void:
	if not is_instance_valid(animation_tree):
		return

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()

	# 1. Combat mode blend
	if "parameters/CombatMode/blend_amount" in animation_tree:
		var cur_cm: float = animation_tree.get("parameters/CombatMode/blend_amount")
		animation_tree.set("parameters/CombatMode/blend_amount", lerp(cur_cm, target_combat_mode, combat_mode_blend_speed * delta))

	# 2. Combat movement BlendSpace2D
	if "parameters/CombatMovement/blend_position" in animation_tree:
		var cur_pos: Vector2 = animation_tree.get("parameters/CombatMovement/blend_position")
		animation_tree.set("parameters/CombatMovement/blend_position", cur_pos.lerp(target_combat_movement, combat_movement_blend_speed * delta))

	# 3. Locomotion BlendSpace1D
	var blend_val := 0.0
	if horizontal_speed > 0.05:
		if horizontal_speed <= walk_speed:
			blend_val = remap(horizontal_speed, 0.0, walk_speed, 0.0, 0.5)
		else:
			blend_val = clampf(remap(horizontal_speed, walk_speed, run_speed, 0.5, 1.0), 0.5, 1.0)

	if "parameters/Locomotion/blend_position" in animation_tree:
		animation_tree.set("parameters/Locomotion/blend_position", blend_val)
	else:
		animation_tree.set("parameters/blend_position", blend_val)

	# 4. Step rate adjustment (TimeScale)
	if "parameters/SpeedScale/scale" in animation_tree:
		var speed_scale := 1.0
		if horizontal_speed > 0.05:
			speed_scale = maxf(0.8, (horizontal_speed / 2.5) * anim_speed_multiplier)
		animation_tree.set("parameters/SpeedScale/scale", speed_scale)
