class_name CombatCharacter3D
extends CharacterBody3D

signal character_died(attacker: Node3D)

@export_group("Configuration")
@export var stats: CharacterStats = null
@export var hitbox_target_mask: int = 4 # Default 4 (scans enemies) for player, 2 for enemy

# --- Node References ---
@onready var pawn: Node3D = get_node_or_null("pawn")
@onready var animation_tree: AnimationTree = get_node_or_null("pawn/AnimationTree")

var health_component: HealthComponent = null
var defense_component: DefenseComponent = null
var attack_component: MeleeAttackComponent = null
var dash_component: DashComponent = null

# Target & Combat State
var current_target: Node3D = null
var is_staggered: bool = false
var stagger_timer: float = 0.0

# Movement Wish State (fed by Controller)
var target_combat_mode: float = 0.0
var target_combat_movement: Vector2 = Vector2.ZERO
var desired_move_velocity: Vector3 = Vector3.ZERO
var is_moving_requested: bool = false

# Duck-typing accessors for compatibility
var is_attacking: bool:
	get:
		return attack_component.is_attacking if is_instance_valid(attack_component) else false

var attack_time_elapsed: float:
	get:
		return attack_component.attack_time_elapsed if is_instance_valid(attack_component) else 0.0

var attack_active_end_time: float:
	get:
		if is_instance_valid(attack_component) and is_instance_valid(attack_component.weapon_data):
			return attack_component.weapon_data.active_end_time
		return 0.75

var is_dashing: bool:
	get:
		return dash_component.is_dashing if is_instance_valid(dash_component) else false

var current_health: float:
	get:
		return health_component.current_health if is_instance_valid(health_component) else 100.0

var max_health: float:
	get:
		return health_component.max_health if is_instance_valid(health_component) else 100.0


func _ready() -> void:
	if stats == null:
		stats = CharacterStats.new()

	floor_snap_length = 0.3
	floor_stop_on_slope = true
	floor_constant_speed = true

	_discover_and_setup_components()

	if is_instance_valid(animation_tree):
		animation_tree.active = true


func _discover_and_setup_components() -> void:
	health_component = get_node_or_null("HealthComponent") as HealthComponent
	if not is_instance_valid(health_component):
		health_component = HealthComponent.new()
		health_component.name = "HealthComponent"
		add_child(health_component)
	health_component.init_health(stats.max_health)
	health_component.died.connect(_on_died)

	defense_component = get_node_or_null("DefenseComponent") as DefenseComponent
	if is_instance_valid(defense_component):
		defense_component.setup(self)

	attack_component = get_node_or_null("MeleeAttackComponent") as MeleeAttackComponent
	if is_instance_valid(attack_component):
		attack_component.setup(self, hitbox_target_mask)

	dash_component = get_node_or_null("DashComponent") as DashComponent
	if is_instance_valid(dash_component):
		dash_component.setup(self)


func _physics_process(delta: float) -> void:
	if stats == null:
		stats = CharacterStats.new()

	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		if velocity.y < 0.0:
			velocity.y = 0.0

	if not is_alive():
		if is_on_floor():
			velocity = Vector3.ZERO
		else:
			velocity.x = lerp(velocity.x, 0.0, stats.decel * delta)
			velocity.z = lerp(velocity.z, 0.0, stats.decel * delta)
			move_and_slide()
		return

	# Always tick dash component (cooldown countdown + active dash movement)
	if is_instance_valid(dash_component):
		dash_component.update(delta)

	# 1. Process stagger recovery
	if is_staggered:
		stagger_timer -= delta
		velocity.x = lerp(velocity.x, 0.0, stats.decel * delta)
		velocity.z = lerp(velocity.z, 0.0, stats.decel * delta)
		if stagger_timer <= 0.0:
			is_staggered = false

	# 2. Process dash state
	elif is_dashing:
		target_combat_mode = 1.0
		# Align pawn with target during dash
		if is_instance_valid(current_target):
			cmd_face_point(current_target.global_position, delta, 1.5)

	# 3. Process attack component
	elif is_attacking and is_instance_valid(attack_component):
		attack_component.process_attack(delta)
		target_combat_mode = 1.0
		target_combat_movement = Vector2.ZERO

		# Align during windup
		if attack_component.attack_time_elapsed < attack_component.weapon_data.windup_time:
			if is_instance_valid(current_target):
				cmd_face_point(current_target.global_position, delta)
			velocity.x = lerp(velocity.x, 0.0, stats.decel * delta)
			velocity.z = lerp(velocity.z, 0.0, stats.decel * delta)
		elif not (attack_component.attack_time_elapsed < attack_component.weapon_data.active_end_time):
			velocity.x = lerp(velocity.x, 0.0, stats.decel * delta)
			velocity.z = lerp(velocity.z, 0.0, stats.decel * delta)

	# 4. Process defense component
	elif is_blocking() and is_instance_valid(defense_component):
		defense_component.process_defense(delta)
		target_combat_mode = 1.0
		target_combat_movement = Vector2.ZERO

		if is_instance_valid(current_target):
			cmd_face_point(current_target.global_position, delta)

		if defense_component.block_state != DefenseComponent.BlockState.ACTIVE_PARRY:
			velocity.x = lerp(velocity.x, 0.0, stats.decel * delta)
			velocity.z = lerp(velocity.z, 0.0, stats.decel * delta)
		else:
			# Damping parry thrust
			velocity.x = lerp(velocity.x, 0.0, 10.0 * delta)
			velocity.z = lerp(velocity.z, 0.0, 10.0 * delta)

	# 5. Normal movement
	else:
		if is_moving_requested:
			velocity.x = desired_move_velocity.x
			velocity.z = desired_move_velocity.z
		else:
			velocity.x = lerp(velocity.x, 0.0, stats.decel * delta)
			velocity.z = lerp(velocity.z, 0.0, stats.decel * delta)
			target_combat_movement = Vector2.ZERO

	_update_animations(delta)
	move_and_slide()

	# Reset one-frame movement request
	is_moving_requested = false


# --- Command Interface (API for Controllers) ---

func cmd_move(world_dir: Vector3, is_running: bool) -> void:
	if is_staggered or is_attacking or is_dashing or is_blocking():
		return

	target_combat_mode = 0.0
	target_combat_movement = Vector2.ZERO

	if world_dir != Vector3.ZERO:
		var speed := stats.run_speed if is_running else stats.walk_speed
		desired_move_velocity.x = lerp(velocity.x, world_dir.x * speed, stats.accel * get_physics_process_delta_time())
		desired_move_velocity.z = lerp(velocity.z, world_dir.z * speed, stats.accel * get_physics_process_delta_time())
		is_moving_requested = true
		cmd_face_direction(world_dir, get_physics_process_delta_time())
	else:
		is_moving_requested = false


func cmd_combat_move(lateral: float, forward: float, speed_override: float = -1.0) -> void:
	if is_staggered or is_attacking or is_dashing or is_blocking():
		return

	target_combat_mode = 1.0
	target_combat_movement = Vector2(lateral, forward)

	if is_instance_valid(current_target):
		cmd_face_point(current_target.global_position, get_physics_process_delta_time())

	if absf(lateral) > 0.01 or absf(forward) > 0.01:
		var forward_b := get_forward_basis()
		var right_b := get_right_basis()

		var move_dir := (forward_b * forward + right_b * lateral).normalized()
		var speed := speed_override if speed_override > 0.0 else (stats.combat_strafe_speed if absf(lateral) > 0.1 else stats.combat_walk_speed)

		desired_move_velocity.x = lerp(velocity.x, move_dir.x * speed, stats.combat_accel * get_physics_process_delta_time())
		desired_move_velocity.z = lerp(velocity.z, move_dir.z * speed, stats.combat_accel * get_physics_process_delta_time())
		is_moving_requested = true
	else:
		is_moving_requested = false


func cmd_face_point(target_point: Vector3, delta: float, speed_scale: float = 1.0) -> void:
	if not is_instance_valid(pawn):
		return
	var diff := target_point - global_position
	diff.y = 0.0
	if diff.length_squared() > 0.001:
		var target_angle := atan2(diff.x, diff.z)
		pawn.rotation.y = lerp_angle(pawn.rotation.y, target_angle, stats.combat_rotation_speed * speed_scale * delta)


func cmd_face_direction(direction: Vector3, delta: float, speed_scale: float = 1.0) -> void:
	if not is_instance_valid(pawn):
		return
	var dir := Vector3(direction.x, 0.0, direction.z)
	if dir.length_squared() > 0.001:
		var target_angle := atan2(dir.x, dir.z)
		pawn.rotation.y = lerp_angle(pawn.rotation.y, target_angle, stats.lerp_angle_weight_scale * speed_scale * delta)


func cmd_attack() -> bool:
	if is_staggered or is_dashing:
		return false
	if is_blocking():
		return cmd_parry()
	if is_instance_valid(attack_component):
		target_combat_movement = Vector2.ZERO
		target_combat_mode = 1.0
		return attack_component.start_attack()
	return false


func cmd_dash(chosen_dir: DashComponent.DashDirection) -> bool:
	if is_staggered or is_dashing or not is_instance_valid(dash_component):
		return false

	# Cannot dash while blocking or holding guard
	if is_blocking():
		return false

	# Dodge cancel: can cancel attack if in recovery phase
	if is_attacking and is_instance_valid(attack_component):
		if attack_component.is_in_recovery():
			attack_component.cancel_attack()
		else:
			return false

	return dash_component.start_dash(chosen_dir)


func cmd_block_start() -> bool:
	if is_staggered or is_dashing or is_attacking or not is_instance_valid(defense_component):
		return false
	return defense_component.start_block()


func cmd_block_release() -> void:
	if is_instance_valid(defense_component):
		defense_component.release_block()


func cmd_parry() -> bool:
	if not is_instance_valid(defense_component):
		return false
	var success := defense_component.trigger_parry()
	if success:
		play_action(&"parry")
	return success


func cmd_set_target(target: Node3D) -> void:
	current_target = target


func cmd_clear_target() -> void:
	current_target = null
	if is_blocking() and is_instance_valid(defense_component):
		defense_component.end_block()


# --- Combat Physics & Reactions ---

func take_damage(amount: float, knockback_impulse: Vector3, attacker_node: Node3D = null) -> void:
	if not is_alive():
		return

	# 1. I-frame check via DashComponent
	if is_dashing and is_instance_valid(dash_component) and dash_component.is_in_iframe():
		var att_name := String(attacker_node.name) if is_instance_valid(attacker_node) else "Attacker"
		print("[%s] Dodged attack from %s via dash i-frame!" % [name, att_name])
		return

	var final_damage := amount
	var final_knockback := knockback_impulse

	# 2. DefenseComponent evaluation (Block, Parry, Penalty, Backstab check)
	if is_instance_valid(defense_component):
		var eval := defense_component.evaluate_hit(amount, knockback_impulse, attacker_node)
		if eval["was_parried"]:
			var att_name := String(attacker_node.name) if is_instance_valid(attacker_node) else "Attacker"
			print("[%s] PERFECT PARRY against %s! Negated %.1f damage with 0 knockback." % [name, att_name, amount])
			return

		if eval["was_blocked"]:
			final_damage = eval["damage_taken"]
			final_knockback = eval["knockback_taken"]
			var att_name := String(attacker_node.name) if is_instance_valid(attacker_node) else "Attacker"
			print("[%s] Blocked attack from %s (took %.1f of %.1f damage)." % [name, att_name, final_damage, amount])

		if eval["was_penalty"]:
			print("[%s] STRUCK DURING PARRY PENALTY! Defenses broken." % name)

	# 3. Apply damage to HealthComponent
	if is_instance_valid(health_component):
		health_component.take_damage(final_damage, attacker_node)
		var att_name := String(attacker_node.name) if is_instance_valid(attacker_node) else "Attacker"
		print("[%s] Took %.1f damage from %s. Remaining HP: %.1f" % [name, final_damage, att_name, health_component.current_health])

	# 4. Apply physical knockback
	velocity.x += final_knockback.x
	velocity.z += final_knockback.z


func stagger(duration: float = 0.8, from_node: Node3D = null) -> void:
	if not is_alive():
		return

	if is_attacking and is_instance_valid(attack_component):
		attack_component.cancel_attack()

	if is_dashing and is_instance_valid(dash_component):
		dash_component.end_dash()

	if is_blocking() and is_instance_valid(defense_component):
		defense_component.end_block()

	abort_action()

	is_staggered = true
	stagger_timer = duration

	# Recoil backward from attacker / source / target
	var away_dir := -get_forward_basis()
	var recoil_source: Node3D = from_node if is_instance_valid(from_node) else current_target
	if is_instance_valid(recoil_source):
		var to_source := (global_position - recoil_source.global_position)
		to_source.y = 0.0
		if to_source.length_squared() > 0.001:
			away_dir = to_source.normalized()

	velocity.x = away_dir.x * 3.5
	velocity.z = away_dir.z * 3.5

	print("[%s] STAGGERED for %.2fs! Action aborted." % [name, duration])


func on_attack_deflected(by_node: Node3D) -> void:
	stagger(0.8, by_node)


func is_alive() -> bool:
	return is_instance_valid(health_component) and not health_component.is_dead


func is_blocking() -> bool:
	return is_instance_valid(defense_component) and defense_component.is_blocking()


func _on_died(attacker: Node3D) -> void:
	print("[%s] has DIED!" % name)
	is_staggered = false
	if is_attacking and is_instance_valid(attack_component):
		attack_component.cancel_attack()
	if is_dashing and is_instance_valid(dash_component):
		dash_component.end_dash()
	if is_blocking() and is_instance_valid(defense_component):
		defense_component.end_block()

	abort_action()
	cmd_clear_target()

	# Keep collision shape enabled so corpse never falls through the floor!
	# Set layer to 0 (no targeting/hits) and mask to 1 (floor/platforms only).
	collision_layer = 0
	collision_mask = 1
	velocity.x = 0.0
	velocity.z = 0.0

	character_died.emit(attacker)


# --- Impulse Helpers Called by Components ---

func apply_parry_thrust(speed: float) -> void:
	var forward_b := get_forward_basis()
	velocity.x = forward_b.x * speed
	velocity.z = forward_b.z * speed


func apply_attack_lunge(speed: float, delta: float) -> void:
	var forward_b := get_forward_basis()
	velocity.x = lerp(velocity.x, forward_b.x * speed, 10.0 * delta)
	velocity.z = lerp(velocity.z, forward_b.z * speed, 10.0 * delta)


func set_dash_initial_velocity(vel: Vector3) -> void:
	velocity.x = vel.x
	velocity.z = vel.z


func apply_dash_velocity(dir: Vector3, speed: float, delta: float) -> void:
	velocity.x = lerp(velocity.x, dir.x * speed, 12.0 * delta)
	velocity.z = lerp(velocity.z, dir.z * speed, 12.0 * delta)


# --- Geometry & Basis Helpers ---

func get_facing_direction() -> Vector3:
	if is_instance_valid(pawn):
		return pawn.global_transform.basis.z.normalized()
	return global_transform.basis.z.normalized()


func get_forward_basis() -> Vector3:
	if is_instance_valid(pawn):
		return pawn.global_transform.basis.z
	return global_transform.basis.z


func get_right_basis() -> Vector3:
	if is_instance_valid(pawn):
		return -pawn.global_transform.basis.x
	return -global_transform.basis.x


# --- Animation & Action Management ---

func play_action(action_name: StringName) -> void:
	if not is_instance_valid(animation_tree):
		return
	animation_tree.set("parameters/ActionSelect/transition_request", str(action_name))
	animation_tree.set("parameters/ActionOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func abort_action() -> void:
	if not is_instance_valid(animation_tree):
		return
	animation_tree.set("parameters/ActionOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


func _update_animations(delta: float) -> void:
	if not is_instance_valid(animation_tree):
		return

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()

	# 1. Combat mode blend
	if "parameters/CombatMode/blend_amount" in animation_tree:
		var cur_cm: float = animation_tree.get("parameters/CombatMode/blend_amount")
		animation_tree.set("parameters/CombatMode/blend_amount", lerp(cur_cm, target_combat_mode, stats.combat_mode_blend_speed * delta))

	# 2. Block mode blend: 1.0 during active guard, 0.0 otherwise
	if "parameters/BlockMode/blend_amount" in animation_tree:
		var cur_bm: float = animation_tree.get("parameters/BlockMode/blend_amount")
		var target_bm := 1.0 if (is_blocking() and defense_component.block_state != DefenseComponent.BlockState.PARRY_PENALTY) else 0.0
		animation_tree.set("parameters/BlockMode/blend_amount", lerp(cur_bm, target_bm, 10.0 * delta))

	# 3. Combat movement BlendSpace2D
	if "parameters/CombatMovement/blend_position" in animation_tree:
		var cur_pos: Vector2 = animation_tree.get("parameters/CombatMovement/blend_position")
		animation_tree.set("parameters/CombatMovement/blend_position", cur_pos.lerp(target_combat_movement, stats.combat_movement_blend_speed * delta))

	# 4. Locomotion BlendSpace1D
	var blend_val := 0.0
	if horizontal_speed > 0.05:
		if horizontal_speed <= stats.walk_speed:
			blend_val = remap(horizontal_speed, 0.0, stats.walk_speed, 0.0, 0.5)
		else:
			blend_val = clampf(remap(horizontal_speed, stats.walk_speed, stats.run_speed, 0.5, 1.0), 0.5, 1.0)

	if "parameters/Locomotion/blend_position" in animation_tree:
		var cur_loco: float = animation_tree.get("parameters/Locomotion/blend_position")
		animation_tree.set("parameters/Locomotion/blend_position", lerp(cur_loco, blend_val, stats.locomotion_blend_speed * delta))

	# 5. Step rate adjustment (TimeScale)
	if "parameters/SpeedScale/scale" in animation_tree:
		var speed_scale := 1.0
		if horizontal_speed > 0.05:
			speed_scale = maxf(0.8, (horizontal_speed / 2.5) * stats.anim_speed_multiplier)
		animation_tree.set("parameters/SpeedScale/scale", speed_scale)
