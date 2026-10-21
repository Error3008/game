extends CharacterBody3D

# --- Combat & Attacks ---
@export_group("Combat & Attacks")
@export var max_health: float = 100.0
@export var attack_damage: float = 35.0
@export var attack_lunge_speed: float = 2.2
@export var attack_windup_time: float = 0.40
@export var attack_active_end_time: float = 0.75
@export var attack_total_duration: float = 1.40

# --- Combat Dash Settings ---
@export_group("Combat Dash")
@export var dash_speed: float = 8.5
@export var dash_duration: float = 0.42
@export var dash_cooldown: float = 0.55
@export var dash_iframe_start: float = 0.04
@export var dash_iframe_end: float = 0.32

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

# Combat & Attack state
var current_health: float = 100.0
var is_attacking: bool = false
var attack_time_elapsed: float = 0.0
var weapon_hitbox: Hitbox = null

# --- Dash / Dodge System ---
enum DashDirection {
	FORWARD,
	BACKWARD,
	LEFT,
	RIGHT
}

# Maps DashDirection to ActionSelect animation state.
# When Combat_Dash_Left / Combat_Dash_Right are ready, assign them here!
const DASH_ANIM_MAP: Dictionary = {
	DashDirection.FORWARD: &"dash_fwd",
	DashDirection.BACKWARD: &"dash_bwd",
	DashDirection.LEFT: &"dash_bwd",   # Temporary fallback to backward dash without turning
	DashDirection.RIGHT: &"dash_bwd",  # Temporary fallback to backward dash without turning
}

var is_dashing: bool = false
var dash_time_elapsed: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_move_direction: Vector3 = Vector3.ZERO

# Animation targets
var target_combat_mode: float = 0.0
var target_combat_movement: Vector2 = Vector2.ZERO


func _ready() -> void:
	current_health = max_health
	if is_instance_valid(animation_tree):
		animation_tree.active = true
	_setup_weapon_hitbox()


func _setup_weapon_hitbox() -> void:
	if not is_instance_valid(pawn):
		pawn = get_node_or_null("pawn")
	if not is_instance_valid(pawn):
		return

	var sword := pawn.find_child("greatsword", true, false)
	if sword:
		var hitbox_scene := preload("res://scenes/combat/hitbox.tscn")
		weapon_hitbox = hitbox_scene.instantiate()
		weapon_hitbox.attacker = self
		weapon_hitbox.damage = attack_damage
		weapon_hitbox.collision_mask = 4 # scans Enemies (layer 4)
		sword.add_child(weapon_hitbox)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("lock_target"):
		is_lock_enabled = not is_lock_enabled
		if is_lock_enabled:
			_find_best_target()
		else:
			_clear_target()

	if event.is_action_pressed("attack"):
		if not is_attacking and not is_dashing:
			_start_attack()

	if event.is_action_pressed("dash"):
		_try_dash()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta

	if is_dashing:
		_process_dash(delta)
	elif is_attacking:
		_process_attack(delta)
	else:
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


# --- Attack Processing & Combat API ---

func _start_attack() -> void:
	is_attacking = true
	attack_time_elapsed = 0.0
	target_combat_mode = 1.0
	target_combat_movement = Vector2.ZERO
	_play_action(&"heavy_attack")


func _process_attack(delta: float) -> void:
	target_combat_mode = 1.0
	attack_time_elapsed += delta

	# Phase 1: Windup (0.0 to attack_windup_time)
	if attack_time_elapsed < attack_windup_time:
		# If locked onto target, orient towards target
		if is_instance_valid(current_target):
			var to_enemy := current_target.global_position - global_position
			to_enemy.y = 0.0
			if to_enemy.length_squared() > 0.01:
				var target_angle := atan2(to_enemy.x, to_enemy.z)
				pawn.rotation.y = lerp_angle(pawn.rotation.y, target_angle, combat_rotation_speed * delta)
		else:
			# Free mode: steer initial direction if WASD is held
			var input_dir := Input.get_vector("a", "d", "w", "s")
			if input_dir != Vector2.ZERO:
				var cam_dir := (spring_arm_pivot.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
				var target_angle := atan2(cam_dir.x, cam_dir.z)
				pawn.rotation.y = lerp_angle(pawn.rotation.y, target_angle, lerp_angle_weight_scale * delta)

		velocity.x = lerp(velocity.x, 0.0, decel * delta)
		velocity.z = lerp(velocity.z, 0.0, decel * delta)

	# Phase 2: Active Swing (attack_windup_time to attack_active_end_time)
	elif attack_time_elapsed < attack_active_end_time:
		if is_instance_valid(weapon_hitbox) and not weapon_hitbox.is_active:
			weapon_hitbox.set_active(true)
		# Lunge forward slightly along pawn orientation
		var forward_dir: Vector3 = pawn.global_transform.basis.z
		velocity.x = lerp(velocity.x, forward_dir.x * attack_lunge_speed, 10.0 * delta)
		velocity.z = lerp(velocity.z, forward_dir.z * attack_lunge_speed, 10.0 * delta)

	# Phase 3: Recovery (attack_active_end_time to attack_total_duration)
	else:
		if is_instance_valid(weapon_hitbox) and weapon_hitbox.is_active:
			weapon_hitbox.set_active(false)
		velocity.x = lerp(velocity.x, 0.0, decel * delta)
		velocity.z = lerp(velocity.z, 0.0, decel * delta)

	if attack_time_elapsed >= attack_total_duration:
		_end_attack()


func _end_attack() -> void:
	if is_instance_valid(weapon_hitbox):
		weapon_hitbox.set_active(false)
	is_attacking = false


# --- Dash Processing & Dodge System ---

func _try_dash() -> void:
	# Dash is strictly permitted only in combat mode (locked onto a target)
	if not is_instance_valid(current_target):
		return
	if is_dashing:
		return
	if dash_cooldown_timer > 0.0:
		return

	# Dodge cancel: if attacking, allow cancel only during recovery phase
	if is_attacking:
		if attack_time_elapsed >= attack_active_end_time:
			_end_attack()
		else:
			return

	_start_dash()


func _start_dash() -> void:
	is_dashing = true
	dash_time_elapsed = 0.0
	dash_cooldown_timer = dash_cooldown
	target_combat_mode = 1.0

	# Align pawn with enemy before launching dash
	if is_instance_valid(current_target):
		var to_enemy := current_target.global_position - global_position
		to_enemy.y = 0.0
		if to_enemy.length_squared() > 0.001:
			pawn.rotation.y = atan2(to_enemy.x, to_enemy.z)

	var input_dir := Input.get_vector("a", "d", "w", "s")
	var forward_step := -input_dir.y
	var lateral_step := input_dir.x

	var forward_basis: Vector3 = pawn.global_transform.basis.z
	var right_basis: Vector3 = -pawn.global_transform.basis.x

	var chosen_dir: DashDirection = DashDirection.BACKWARD

	if input_dir.length_squared() < 0.05:
		# Neutral input in combat: quick backward retreat
		chosen_dir = DashDirection.BACKWARD
		dash_move_direction = -forward_basis
	else:
		dash_move_direction = (forward_basis * forward_step + right_basis * lateral_step).normalized()
		if absf(forward_step) >= absf(lateral_step):
			chosen_dir = DashDirection.FORWARD if forward_step > 0.0 else DashDirection.BACKWARD
		else:
			chosen_dir = DashDirection.RIGHT if lateral_step > 0.0 else DashDirection.LEFT

	var anim_name: StringName = DASH_ANIM_MAP.get(chosen_dir, &"dash_bwd")
	_play_action(anim_name)

	# Initial kinetic velocity
	velocity.x = dash_move_direction.x * dash_speed
	velocity.z = dash_move_direction.z * dash_speed


func _process_dash(delta: float) -> void:
	dash_time_elapsed += delta
	target_combat_mode = 1.0

	# Critical requirement: Keep pawn facing the target at all times (no turning)
	if is_instance_valid(current_target):
		var to_enemy := current_target.global_position - global_position
		to_enemy.y = 0.0
		if to_enemy.length_squared() > 0.001:
			var target_angle := atan2(to_enemy.x, to_enemy.z)
			pawn.rotation.y = lerp_angle(pawn.rotation.y, target_angle, combat_rotation_speed * 1.5 * delta)

	# Physical movement: smoothly decelerate toward combat speed
	if dash_time_elapsed < dash_duration:
		var progress := clampf(dash_time_elapsed / dash_duration, 0.0, 1.0)
		var target_speed := lerpf(dash_speed, combat_walk_speed, progress)
		velocity.x = lerp(velocity.x, dash_move_direction.x * target_speed, 12.0 * delta)
		velocity.z = lerp(velocity.z, dash_move_direction.z * target_speed, 12.0 * delta)
	else:
		_end_dash()


func _end_dash() -> void:
	is_dashing = false


func _play_action(action_name: StringName) -> void:
	if not is_instance_valid(animation_tree):
		return
	animation_tree.set("parameters/ActionSelect/transition_request", str(action_name))
	animation_tree.set("parameters/ActionOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func take_damage(amount: float, knockback_impulse: Vector3, attacker_node: Node3D) -> void:
	# I-frame check during active dash window
	if is_dashing and dash_time_elapsed >= dash_iframe_start and dash_time_elapsed <= dash_iframe_end:
		var att_name: String = String(attacker_node.name) if is_instance_valid(attacker_node) else "Enemy"
		print("[Player] Dodged attack from %s via dash i-frame!" % att_name)
		return

	current_health -= amount
	var attacker_name: String = String(attacker_node.name) if is_instance_valid(attacker_node) else "Unknown"
	print("[Player] Took %.1f damage from %s! Remaining HP: %.1f" % [amount, attacker_name, current_health])

	# Apply knockback
	velocity.x += knockback_impulse.x
	velocity.z += knockback_impulse.z


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
