class_name EnemyAIController
extends Node

enum State {
	IDLE,
	CHASE,
	COMBAT,
	ATTACK_APPROACH
}

# --- Dummy / Training ---
@export_group("Dummy / Training")
@export var is_dummy: bool = false
@export var dummy_can_attack: bool = false

# --- Combat & Attacks ---
@export_group("Combat & Attacks")
@export var attack_range: float = 3.5
@export var strike_effective_reach: float = 1.85
@export var attack_approach_speed: float = 3.0
@export var attack_approach_timeout: float = 2.5
@export var attack_cooldown_min: float = 2.5
@export var attack_cooldown_max: float = 4.5

# --- Combat Dodge / Reactions ---
@export_group("Combat Dodge / Reactions")
@export var can_dodge: bool = true
@export var dodge_chance: float = 0.50
@export var dodge_trigger_distance: float = 3.5
@export var reaction_time_min: float = 0.10
@export var reaction_time_max: float = 0.22
@export var dodge_cooldown_min: float = 0.5
@export var dodge_cooldown_max: float = 1.0

# --- Distances ---
@export_group("Distances")
@export var combat_engage_dist: float = 4.0
@export var combat_disengage_dist: float = 6.0
@export var ideal_combat_dist_min: float = 2.0
@export var ideal_combat_dist_max: float = 3.2
@export var lose_player_dist: float = 16.0

var actor: CombatCharacter3D = null
var current_state: State = State.IDLE
var target: Node3D = null

# Timers
var combat_action_timer: float = 0.0
var attack_cooldown_timer: float = 0.0
var dodge_cooldown_timer: float = 0.0
var approach_time_elapsed: float = 0.0

# Pending reaction
var is_dodge_pending: bool = false
var pending_dodge_timer: float = 0.0
var _has_reacted_to_attack: bool = false
var current_orbit_movement: Vector2 = Vector2.ZERO


func _ready() -> void:
	actor = get_parent() as CombatCharacter3D
	if not is_instance_valid(actor):
		push_error("[EnemyAIController] Parent node must be a CombatCharacter3D!")
		return

	attack_cooldown_timer = randf_range(1.5, 3.5)
	_setup_detection_area()


func _setup_detection_area() -> void:
	var area := actor.get_node_or_null("DetectionArea") as Area3D
	if is_instance_valid(area):
		if not area.body_entered.is_connected(_on_detection_area_body_entered):
			area.body_entered.connect(_on_detection_area_body_entered)
		if not area.body_exited.is_connected(_on_detection_area_body_exited):
			area.body_exited.connect(_on_detection_area_body_exited)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(actor) or not actor.is_alive():
		return

	if actor.is_staggered or actor.is_dashing or actor.is_attacking:
		is_dodge_pending = false
		return

	if dodge_cooldown_timer > 0.0:
		dodge_cooldown_timer -= delta

	# Process delayed reaction dodge
	if is_dodge_pending:
		pending_dodge_timer -= delta
		if pending_dodge_timer <= 0.0:
			is_dodge_pending = false
			if not is_dummy and not actor.is_dashing and not actor.is_staggered:
				_execute_random_dodge()

	# Validate target
	if is_instance_valid(target):
		if not target.is_inside_tree() or (target.has_method("is_alive") and not target.is_alive()):
			target = null
			actor.cmd_clear_target()
			current_state = State.IDLE

	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.CHASE:
			_process_chase(delta)
		State.COMBAT:
			_process_combat(delta)
		State.ATTACK_APPROACH:
			_process_attack_approach(delta)


func _process_idle(_delta: float) -> void:
	actor.cmd_clear_target()


func _process_chase(_delta: float) -> void:
	if not is_instance_valid(target):
		current_state = State.IDLE
		return

	var to_target := (target.global_position - actor.global_position)
	to_target.y = 0.0
	var dist := to_target.length()

	if dist > lose_player_dist:
		target = null
		actor.cmd_clear_target()
		current_state = State.IDLE
		return

	if dist <= combat_engage_dist or is_dummy:
		current_state = State.COMBAT
		combat_action_timer = 0.0
		actor.cmd_set_target(target)
		return

	# Reaction check during chase
	if _check_dodge_reaction(dist):
		return

	var dir := to_target.normalized()
	actor.cmd_move(dir, true)


func _process_combat(delta: float) -> void:
	if not is_instance_valid(target):
		current_state = State.IDLE
		return

	actor.cmd_set_target(target)

	var to_target := (target.global_position - actor.global_position)
	to_target.y = 0.0
	var dist := to_target.length()

	# Disengage check
	if not is_dummy and dist > combat_disengage_dist:
		current_state = State.CHASE
		return

	# Dodge reaction check
	if _check_dodge_reaction(dist):
		return

	# Attack decision
	attack_cooldown_timer -= delta
	if attack_cooldown_timer <= 0.0:
		if is_dummy:
			if dummy_can_attack and not actor.is_attacking:
				actor.cmd_attack()
				attack_cooldown_timer = randf_range(attack_cooldown_min, attack_cooldown_max)
			return
		else:
			if dist <= strike_effective_reach:
				if not actor.is_attacking:
					actor.cmd_attack()
					attack_cooldown_timer = randf_range(attack_cooldown_min, attack_cooldown_max)
					combat_action_timer = randf_range(0.8, 1.8)
				return
			elif dist <= attack_range:
				current_state = State.ATTACK_APPROACH
				approach_time_elapsed = 0.0
				return

	if is_dummy:
		actor.cmd_combat_move(0.0, 0.0)
		return

	# Tactical distance management
	if dist < ideal_combat_dist_min:
		actor.cmd_combat_move(0.0, -1.0)
	elif dist > ideal_combat_dist_max:
		actor.cmd_combat_move(0.0, 1.0)
	else:
		combat_action_timer -= delta
		if combat_action_timer <= 0.0:
			_pick_new_orbit_action()
		actor.cmd_combat_move(current_orbit_movement.x, current_orbit_movement.y)


func _pick_new_orbit_action() -> void:
	var roll := randf()
	if roll < 0.4:
		current_orbit_movement = Vector2(1.0, 0.0) # Strafe right
		combat_action_timer = randf_range(1.2, 2.2)
	elif roll < 0.8:
		current_orbit_movement = Vector2(-1.0, 0.0) # Strafe left
		combat_action_timer = randf_range(1.2, 2.2)
	else:
		current_orbit_movement = Vector2.ZERO # Combat pause
		combat_action_timer = randf_range(0.6, 1.2)


func _process_attack_approach(delta: float) -> void:
	if not is_instance_valid(target):
		current_state = State.IDLE
		return

	actor.cmd_set_target(target)

	var to_target := (target.global_position - actor.global_position)
	to_target.y = 0.0
	var dist := to_target.length()

	if _check_dodge_reaction(dist):
		return

	if dist > combat_disengage_dist:
		current_state = State.CHASE
		return

	approach_time_elapsed += delta

	if dist <= strike_effective_reach:
		actor.cmd_attack()
		current_state = State.COMBAT
		attack_cooldown_timer = randf_range(attack_cooldown_min, attack_cooldown_max)
		combat_action_timer = randf_range(0.8, 1.8)
		return

	if approach_time_elapsed >= attack_approach_timeout:
		current_state = State.COMBAT
		attack_cooldown_timer = randf_range(1.0, 2.0)
		combat_action_timer = randf_range(0.8, 1.5)
		return

	actor.cmd_combat_move(0.0, 1.0, attack_approach_speed)


func _check_dodge_reaction(dist: float) -> bool:
	if is_dummy or not can_dodge or actor.is_dashing or is_dodge_pending:
		return false
	if not is_instance_valid(target) or not ("is_attacking" in target):
		return false

	var target_attacking: bool = target.is_attacking
	if not target_attacking:
		_has_reacted_to_attack = false
		return false

	if _has_reacted_to_attack:
		return false

	# Target is attacking: check threat range
	if dist <= dodge_trigger_distance:
		_has_reacted_to_attack = true
		var effective_cooldown := 0.0 if dodge_chance >= 0.99 else dodge_cooldown_timer
		if effective_cooldown <= 0.0 and randf() <= dodge_chance:
			var delay := randf_range(reaction_time_min, reaction_time_max)
			if delay <= 0.001:
				_execute_random_dodge()
			else:
				is_dodge_pending = true
				pending_dodge_timer = delay
			return true

	return false


func _execute_random_dodge() -> void:
	dodge_cooldown_timer = randf_range(dodge_cooldown_min, dodge_cooldown_max)
	var roll := randf()
	var dir := DashComponent.DashDirection.BACKWARD
	if roll < 0.60:
		dir = DashComponent.DashDirection.BACKWARD
	elif roll < 0.80:
		dir = DashComponent.DashDirection.LEFT
	else:
		dir = DashComponent.DashDirection.RIGHT

	actor.cmd_dash(dir)


# --- Detection Area Signals ---

func _on_detection_area_body_entered(body: Node3D) -> void:
	if body == actor:
		return
	if body.is_in_group("player"):
		target = body
		if current_state == State.IDLE:
			current_state = State.CHASE


func _on_detection_area_body_exited(body: Node3D) -> void:
	if body == target:
		var dist := actor.global_position.distance_to(target.global_position)
		if dist >= lose_player_dist:
			target = null
			actor.cmd_clear_target()
			current_state = State.IDLE
