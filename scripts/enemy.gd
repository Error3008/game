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
@export var attack_range: float = 2.8           # Range to consider attack option
@export var strike_effective_reach: float = 1.85 # Distance where blade connects solidly
@export var attack_approach_speed: float = 3.0   # Speed when actively stepping in to strike
@export var attack_approach_timeout: float = 2.5 # Timeout if player circles away
@export var attack_cooldown_min: float = 2.5    # Min seconds between attacks
@export var attack_cooldown_max: float = 4.5    # Max seconds between attacks
@export var attack_lunge_speed: float = 2.0     # Forward step during slash
@export var attack_windup_time: float = 0.40    # Windup / telegraph phase
@export var attack_active_end_time: float = 0.75 # Active damage window end
@export var attack_total_duration: float = 1.40 # Total attack recovery duration

# --- Combat Dodge / Reactions ---
@export_group("Combat Dodge / Reactions")
@export var can_dodge: bool = true               # Global toggle for enemy dodges
@export var dodge_chance: float = 0.50           # Chance to dodge incoming player attack (50%)
@export var dodge_trigger_distance: float = 3.5  # Distance within which enemy reacts to player swing
@export var reaction_time_min: float = 0.10      # Minimum visual reaction delay (seconds)
@export var reaction_time_max: float = 0.22      # Maximum visual reaction delay (seconds)
@export var dodge_speed: float = 8.5             # Dodge kinetic impulse speed
@export var dodge_duration: float = 0.42          # Duration of dodge movement
@export var dodge_cooldown_min: float = 0.5      # Min seconds between dodges
@export var dodge_cooldown_max: float = 1.0      # Max seconds between dodges
@export var dodge_iframe_start: float = 0.04     # I-frame start
@export var dodge_iframe_end: float = 0.32       # I-frame end

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
enum State { IDLE, CHASE, COMBAT, ATTACK_APPROACH, ATTACK, DODGE }
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

# Dodge & Reaction State
var is_dashing: bool = false
var dodge_time_elapsed: float = 0.0
var dodge_cooldown_timer: float = 0.0
var dodge_move_direction: Vector3 = Vector3.ZERO
var _has_reacted_to_player_attack: bool = false
var is_dodge_pending: bool = false
var pending_dodge_timer: float = 0.0
var approach_time_elapsed: float = 0.0

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

	if dodge_cooldown_timer > 0.0:
		dodge_cooldown_timer -= delta

	if is_dodge_pending:
		pending_dodge_timer -= delta
		if pending_dodge_timer <= 0.0:
			is_dodge_pending = false
			if current_state != State.DODGE and not is_dummy:
				if is_instance_valid(player) and "is_attacking" in player and player.is_attacking:
					if current_state == State.ATTACK:
						if attack_time_elapsed >= attack_active_end_time:
							_end_attack()
							_start_dodge()
					else:
						_start_dodge()

	# Process states
	match current_state:
		State.IDLE:
			_process_idle_state(delta)
		State.CHASE:
			_process_chase_state(delta)
		State.COMBAT:
			_process_combat_state(delta)
		State.ATTACK_APPROACH:
			_process_attack_approach_state(delta)
		State.ATTACK:
			_process_attack_state(delta)
		State.DODGE:
			_process_dodge_state(delta)

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
		if _check_dodge_reaction(dist):
			return
		return

	# If player attempts to attack while running or approaching, react immediately
	if _check_dodge_reaction(dist):
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

	# Reaction check: can dodge incoming player attack (dummies ignored)
	if _check_dodge_reaction(dist):
		return

	# Attack decision timer
	attack_cooldown_timer -= delta
	if attack_cooldown_timer <= 0.0:
		if is_dummy:
			if dummy_can_attack:
				_start_attack()
			return
		else:
			# If already right in strike reach, strike immediately!
			if dist <= strike_effective_reach:
				_start_attack()
				return
			elif dist <= attack_range:
				# Within tactical attack range: switch to active approach to close the gap into reach
				current_state = State.ATTACK_APPROACH
				approach_time_elapsed = 0.0
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


func _process_attack_approach_state(delta: float) -> void:
	target_combat_mode = 1.0

	if not is_instance_valid(player):
		current_state = State.IDLE
		return

	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	# 1. Reaction check: if player counter-attacks during approach, enemy can dodge!
	if _check_dodge_reaction(dist):
		return

	# 2. Check if player disengaged or ran far away
	if dist > combat_disengage_dist:
		current_state = State.CHASE
		return

	# 3. Always face player directly
	if dist > 0.01:
		var target_angle := atan2(to_player.x, to_player.z)
		pawn.rotation.y = lerp_angle(pawn.rotation.y, target_angle, rotation_speed * 1.5 * delta)

	approach_time_elapsed += delta

	# 4. Check if we reached strike reach!
	if dist <= strike_effective_reach:
		_start_attack()
		return

	# 5. Check timeout: if player kited/backpedaled for too long, fall back to combat
	if approach_time_elapsed >= attack_approach_timeout:
		current_state = State.COMBAT
		attack_cooldown_timer = randf_range(1.0, 2.0)
		combat_action_timer = randf_range(0.8, 1.5)
		return

	# 6. Step forward rapidly to close the distance into weapon reach
	target_combat_movement = Vector2(0.0, 1.0)
	var forward_basis: Vector3 = pawn.global_transform.basis.z
	velocity.x = lerp(velocity.x, forward_basis.x * attack_approach_speed, combat_accel * 1.2 * delta)
	velocity.z = lerp(velocity.z, forward_basis.z * attack_approach_speed, combat_accel * 1.2 * delta)


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


# --- Dodge & Reaction System ---

func _check_dodge_reaction(dist: float) -> bool:
	# Dummies are strictly excluded from dodging
	if is_dummy or not can_dodge:
		return false
	if current_state == State.DODGE or is_dodge_pending:
		return true
	if not is_instance_valid(player) or not ("is_attacking" in player):
		return false

	# If enemy is currently attacking:
	if current_state == State.ATTACK:
		# Allow dodge-cancel during recovery phase if player counter-attacks
		if attack_time_elapsed >= attack_active_end_time:
			pass
		else:
			return false

	if player.is_attacking:
		# Check if player is in windup or active swing
		var player_in_threat_phase: bool = true
		if "attack_time_elapsed" in player and "attack_active_end_time" in player:
			player_in_threat_phase = player.attack_time_elapsed <= player.attack_active_end_time

		# Only react when player is in threat phase AND within threat range
		if player_in_threat_phase and dist <= dodge_trigger_distance:
			if not _has_reacted_to_player_attack:
				# If dodge_chance >= 0.99 (100%), bypass cooldown so consecutive strikes can be dodged
				var effective_cooldown := 0.0 if dodge_chance >= 0.99 else dodge_cooldown_timer
				if effective_cooldown <= 0.0:
					_has_reacted_to_player_attack = true
					if randf() <= dodge_chance:
						var delay := get_reaction_delay()
						if delay <= 0.001:
							if current_state == State.ATTACK:
								_end_attack()
							_start_dodge()
						else:
							is_dodge_pending = true
							pending_dodge_timer = delay
						return true
	else:
		_has_reacted_to_player_attack = false
		is_dodge_pending = false

	return false


func get_reaction_delay() -> float:
	return randf_range(reaction_time_min, reaction_time_max)


func _start_dodge() -> void:
	current_state = State.DODGE
	is_dashing = true
	dodge_time_elapsed = 0.0
	dodge_cooldown_timer = randf_range(dodge_cooldown_min, dodge_cooldown_max)
	target_combat_mode = 1.0
	target_combat_movement = Vector2.ZERO

	# Align with player
	if is_instance_valid(player):
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		if to_player.length_squared() > 0.001:
			pawn.rotation.y = atan2(to_player.x, to_player.z)

	var forward_basis: Vector3 = pawn.global_transform.basis.z
	var right_basis: Vector3 = -pawn.global_transform.basis.x

	# 60% retreat backward away from blade, 40% side-step left/right
	var roll := randf()
	if roll < 0.60:
		dodge_move_direction = -forward_basis
	elif roll < 0.80:
		dodge_move_direction = -right_basis
	else:
		dodge_move_direction = right_basis

	_play_action(&"dash_bwd")

	velocity.x = dodge_move_direction.x * dodge_speed
	velocity.z = dodge_move_direction.z * dodge_speed


func _process_dodge_state(delta: float) -> void:
	target_combat_mode = 1.0
	dodge_time_elapsed += delta

	# Always face player during dodge (no turning)
	if is_instance_valid(player):
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		if to_player.length_squared() > 0.001:
			var target_angle := atan2(to_player.x, to_player.z)
			pawn.rotation.y = lerp_angle(pawn.rotation.y, target_angle, rotation_speed * 1.5 * delta)

	# Decelerate smoothly
	if dodge_time_elapsed < dodge_duration:
		var progress := clampf(dodge_time_elapsed / dodge_duration, 0.0, 1.0)
		var target_speed := lerpf(dodge_speed, 0.0, progress)
		velocity.x = lerp(velocity.x, dodge_move_direction.x * target_speed, 12.0 * delta)
		velocity.z = lerp(velocity.z, dodge_move_direction.z * target_speed, 12.0 * delta)
	else:
		_end_dodge()


func _end_dodge() -> void:
	is_dashing = false
	current_state = State.COMBAT
	combat_action_timer = randf_range(0.6, 1.2)


func _play_action(action_name: StringName) -> void:
	if not is_instance_valid(animation_tree):
		return
	animation_tree.set("parameters/ActionSelect/transition_request", str(action_name))
	animation_tree.set("parameters/ActionOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func take_damage(amount: float, knockback_impulse: Vector3, attacker_node: Node3D) -> void:
	# I-frame check during active dodge window
	if is_dashing and dodge_time_elapsed >= dodge_iframe_start and dodge_time_elapsed <= dodge_iframe_end:
		var att_name: String = String(attacker_node.name) if is_instance_valid(attacker_node) else "Player"
		print("[%s] Dodged attack from %s via dodge i-frame!" % [name, att_name])
		return

	current_health -= amount
	is_dodge_pending = false
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
