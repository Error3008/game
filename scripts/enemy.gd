extends CharacterBody3D

# --- Node references ---
@onready var pawn: Node3D = $pawn
@onready var animation_tree: AnimationTree = $pawn/AnimationTree

# --- Dummy / Training ---
@export_group("Dummy / Training")
@export var is_dummy: bool = false # If true, stays in place, faces player and holds combat stance
@export var dummy_can_attack: bool = false # If true, dummy will also test attack swings

# --- Combat & Attacks ---
@export_group("Combat & Attacks")
@export var max_health: float = 100.0
@export var attack_damage: float = 20.0
@export var attack_range: float = 2.8           # Range to initiate attack
@export var attack_cooldown_min: float = 3.0    # Min seconds between attacks
@export var attack_cooldown_max: float = 5.0    # Max seconds between attacks
@export var attack_lunge_speed: float = 2.0     # Forward step during slash
@export var attack_windup_time: float = 0.40    # Windup / telegraph phase
@export var attack_active_end_time: float = 0.75 # Active damage window end
@export var attack_total_duration: float = 1.40 # Total attack recovery duration

# --- Movement speeds ---
@export_group("Movement Speeds")
@export var run_speed: float = 5.0
@export var walk_speed: float = 2.5
@export var combat_walk_speed: float = 2.4
@export var combat_strafe_speed: float = 2.0

# --- Acceleration / Deceleration ---
@export_group("Acceleration")
@export var accel: float = 10.0
@export var decel: float = 12.0
@export var combat_accel: float = 8.0

# --- Combat Distances ---
@export_group("Distances")
@export var combat_engage_dist: float = 4.0      # CHASE -> COMBAT
@export var combat_disengage_dist: float = 6.0   # COMBAT -> CHASE
@export var ideal_combat_dist_min: float = 2.0   # If closer than this, back up (Combat_Walk_Bwd)
@export var ideal_combat_dist_max: float = 3.2   # If farther than this, approach (Combat_Walk_Fwd)
@export var lose_player_dist: float = 16.0       # Distance to lose interest and return to IDLE

# --- Blend & Rotation Speeds ---
@export_group("Blend & Rotation Speeds")
@export var combat_mode_blend_speed: float = 5.0
@export var combat_movement_blend_speed: float = 6.0
@export var locomotion_blend_speed: float = 8.0
@export var rotation_speed: float = 8.0
@export var anim_speed_multiplier: float = 1.0

# --- State Machine ---
enum State { IDLE, CHASE, COMBAT, ATTACK }
var current_state: State = State.IDLE

var player: Node3D = null
var current_health: float = 100.0

# Animation targets
var target_combat_mode: float = 0.0
# CombatMovement blend position:
#   (0, 1)  = Forward,  (0, -1) = Backward
#   (1, 0)  = Right,    (-1, 0) = Left
#   (0, 0)  = Combat Idle
var target_combat_movement: Vector2 = Vector2.ZERO

# Tactical timers
var combat_action_timer: float = 0.0
var attack_cooldown_timer: float = 0.0
var attack_time_elapsed: float = 0.0

# Weapon Hitbox
var weapon_hitbox: Hitbox = null


func _ready() -> void:
	current_health = max_health
	attack_cooldown_timer = randf_range(1.5, 3.5)

	# Ensure AnimationTree is active
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
		weapon_hitbox.collision_mask = 2 # scans Player (collision layer 2)
		sword.add_child(weapon_hitbox)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Process states
	match current_state:
		State.IDLE:
			_process_idle_state(delta)
		State.CHASE:
			_process_chase_state(delta)
		State.COMBAT:
			_process_combat_state(delta)
		State.ATTACK:
			_process_attack_state(delta)

	_update_animations(delta)
	move_and_slide()


# --- State Handlers ---

func _process_idle_state(delta: float) -> void:
	target_combat_mode = 0.0
	target_combat_movement = Vector2.ZERO

	# Smooth deceleration to zero
	velocity.x = lerp(velocity.x, 0.0, decel * delta)
	velocity.z = lerp(velocity.z, 0.0, decel * delta)


func _process_chase_state(delta: float) -> void:
	target_combat_mode = 0.0
	target_combat_movement = Vector2.ZERO

	if not is_instance_valid(player):
		current_state = State.IDLE
		return

	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	# Check distance thresholds
	if dist > lose_player_dist:
		player = null
		current_state = State.IDLE
		return

	if dist <= combat_engage_dist:
		current_state = State.COMBAT
		combat_action_timer = 0.0
		return

	# Dummies do not pursue player, they directly switch to combat stance
	if is_dummy:
		current_state = State.COMBAT
		return

	# Move toward player
	var dir := to_player.normalized()
	velocity.x = lerp(velocity.x, dir.x * run_speed, accel * delta)
	velocity.z = lerp(velocity.z, dir.z * run_speed, accel * delta)

	# Face movement direction smoothly (prevents running sideways)
	var target_angle := atan2(dir.x, dir.z)
	pawn.rotation.y = lerp_angle(pawn.rotation.y, target_angle, rotation_speed * delta)


func _process_combat_state(delta: float) -> void:
	target_combat_mode = 1.0

	if not is_instance_valid(player):
		current_state = State.IDLE
		return

	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	# If player escaped too far, resume chase (unless dummy)
	if not is_dummy and dist > combat_disengage_dist:
		current_state = State.CHASE
		return

	# Always smoothly face player in combat
	if dist > 0.01:
		var target_angle := atan2(to_player.x, to_player.z)
		pawn.rotation.y = lerp_angle(pawn.rotation.y, target_angle, rotation_speed * delta)

	# Dummies hold ground in combat idle unless dummy_can_attack is set
	if is_dummy and not dummy_can_attack:
		target_combat_movement = Vector2.ZERO
		velocity.x = lerp(velocity.x, 0.0, decel * delta)
		velocity.z = lerp(velocity.z, 0.0, decel * delta)
		return

	# Attack decision timer
	attack_cooldown_timer -= delta
	if attack_cooldown_timer <= 0.0 and dist <= attack_range:
		_start_attack()
		return

	# If is_dummy is true but dummy_can_attack is enabled, hold ground between attacks
	if is_dummy:
		target_combat_movement = Vector2.ZERO
		velocity.x = lerp(velocity.x, 0.0, decel * delta)
		velocity.z = lerp(velocity.z, 0.0, decel * delta)
		return

	# Tactical distance management
	if dist < ideal_combat_dist_min:
		# Player is too close: step backwards
		target_combat_movement = Vector2(0.0, -1.0)
	elif dist > ideal_combat_dist_max:
		# Player is too far: step forward
		target_combat_movement = Vector2(0.0, 1.0)
	else:
		# In ideal range: orbital strafe with pauses
		combat_action_timer -= delta
		if combat_action_timer <= 0.0:
			_pick_new_orbit_action()

	# Calculate 3D velocity from pawn's local orientation:
	# pawn.global_transform.basis.z is forward (facing player)
	# pawn.global_transform.basis.x is right
	var forward_basis: Vector3 = pawn.global_transform.basis.z
	var right_basis: Vector3 = -pawn.global_transform.basis.x

	var desired_dir := (forward_basis * target_combat_movement.y + right_basis * target_combat_movement.x).normalized()
	var desired_speed := 0.0

	if target_combat_movement != Vector2.ZERO:
		desired_speed = combat_strafe_speed if absf(target_combat_movement.x) > 0.1 else combat_walk_speed

	velocity.x = lerp(velocity.x, desired_dir.x * desired_speed, combat_accel * delta)
	velocity.z = lerp(velocity.z, desired_dir.z * desired_speed, combat_accel * delta)


func _pick_new_orbit_action() -> void:
	var roll := randf()
	if roll < 0.4:
		# Strafe right
		target_combat_movement = Vector2(1.0, 0.0)
		combat_action_timer = randf_range(1.2, 2.2)
	elif roll < 0.8:
		# Strafe left
		target_combat_movement = Vector2(-1.0, 0.0)
		combat_action_timer = randf_range(1.2, 2.2)
	else:
		# Combat pause / stare down
		target_combat_movement = Vector2.ZERO
		combat_action_timer = randf_range(0.6, 1.2)


# --- Attack State & Combat API ---

func _start_attack() -> void:
	current_state = State.ATTACK
	attack_time_elapsed = 0.0
	target_combat_movement = Vector2.ZERO
	_play_action(&"heavy_attack")


func _process_attack_state(delta: float) -> void:
	target_combat_mode = 1.0
	attack_time_elapsed += delta

	# Phase 1: Windup (0.0 to attack_windup_time)
	# Smoothly track player orientation during windup so attack is well-aimed
	if attack_time_elapsed < attack_windup_time:
		if is_instance_valid(player):
			var to_player := player.global_position - global_position
			to_player.y = 0.0
			if to_player.length_squared() > 0.01:
				var target_angle := atan2(to_player.x, to_player.z)
				pawn.rotation.y = lerp_angle(pawn.rotation.y, target_angle, rotation_speed * delta)
		velocity.x = lerp(velocity.x, 0.0, decel * delta)
		velocity.z = lerp(velocity.z, 0.0, decel * delta)

	# Phase 2: Active Swing (attack_windup_time to attack_active_end_time)
	elif attack_time_elapsed < attack_active_end_time:
		if is_instance_valid(weapon_hitbox) and not weapon_hitbox.is_active:
			weapon_hitbox.set_active(true)
		# Lunge forward slightly along attack vector
		var forward_dir: Vector3 = pawn.global_transform.basis.z
		velocity.x = lerp(velocity.x, forward_dir.x * attack_lunge_speed, 10.0 * delta)
		velocity.z = lerp(velocity.z, forward_dir.z * attack_lunge_speed, 10.0 * delta)

	# Phase 3: Recovery (attack_active_end_time to attack_total_duration)
	else:
		if is_instance_valid(weapon_hitbox) and weapon_hitbox.is_active:
			weapon_hitbox.set_active(false)
		velocity.x = lerp(velocity.x, 0.0, decel * delta)
		velocity.z = lerp(velocity.z, 0.0, decel * delta)

	# Attack completion check
	if attack_time_elapsed >= attack_total_duration:
		_end_attack()


func _end_attack() -> void:
	if is_instance_valid(weapon_hitbox):
		weapon_hitbox.set_active(false)
	current_state = State.COMBAT
	attack_cooldown_timer = randf_range(attack_cooldown_min, attack_cooldown_max)
	combat_action_timer = randf_range(0.8, 1.8)


func _play_action(action_name: StringName) -> void:
	if not is_instance_valid(animation_tree):
		return
	animation_tree.set("parameters/ActionSelect/transition_request", str(action_name))
	animation_tree.set("parameters/ActionOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func take_damage(amount: float, knockback_impulse: Vector3, attacker_node: Node3D) -> void:
	current_health -= amount
	var attacker_name: String = String(attacker_node.name) if is_instance_valid(attacker_node) else "Unknown"
	print("[%s] took %.1f damage from %s! Remaining HP: %.1f" % [name, amount, attacker_name, current_health])

	# Apply knockback
	velocity.x += knockback_impulse.x
	velocity.z += knockback_impulse.z

	# Alert and engage if struck while idle
	if current_state == State.IDLE and is_instance_valid(attacker_node):
		player = attacker_node
		current_state = State.COMBAT



# --- AnimationTree Blending ---

func _update_animations(delta: float) -> void:
	if not is_instance_valid(animation_tree):
		return

	# Smoothly blend between locomotion and combat modes
	var current_combat: float = animation_tree.get("parameters/CombatMode/blend_amount")
	animation_tree.set("parameters/CombatMode/blend_amount", lerp(current_combat, target_combat_mode, combat_mode_blend_speed * delta))

	# Smoothly blend combat movement BlendSpace2D
	var current_cm_pos: Vector2 = animation_tree.get("parameters/CombatMovement/blend_position")
	animation_tree.set("parameters/CombatMovement/blend_position", current_cm_pos.lerp(target_combat_movement, combat_movement_blend_speed * delta))

	# Locomotion BlendSpace1D
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var target_loco := _get_locomotion_blend(horizontal_speed)
	var current_loco: float = animation_tree.get("parameters/Locomotion/blend_position")
	animation_tree.set("parameters/Locomotion/blend_position", lerp(current_loco, target_loco, locomotion_blend_speed * delta))

	# Dynamic step rate adjustment (TimeScale)
	var speed_scale := 1.0
	if horizontal_speed > 0.05:
		speed_scale = maxf(0.8, (horizontal_speed / 2.5) * anim_speed_multiplier)
	animation_tree.set("parameters/SpeedScale/scale", speed_scale)


func _get_locomotion_blend(speed: float) -> float:
	if speed <= 0.05:
		return 0.0
	elif speed <= walk_speed:
		return remap(speed, 0.0, walk_speed, 0.0, 0.5)
	else:
		return clampf(remap(speed, walk_speed, run_speed, 0.5, 1.0), 0.5, 1.0)


# --- Perception Signals ---

func _on_detection_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player = body
		if current_state == State.IDLE:
			current_state = State.CHASE


func _on_detection_area_body_exited(body: Node3D) -> void:
	if body == player:
		# If body exited detection radius and is beyond buffer distance, drop target
		var dist := global_position.distance_to(player.global_position)
		if dist >= lose_player_dist:
			player = null
			current_state = State.IDLE
