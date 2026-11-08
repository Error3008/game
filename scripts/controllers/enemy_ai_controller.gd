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
@export var dummy_always_block: bool = false

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

# --- Combat Defense / Block & Parry ---
@export_group("Combat Defense / Block & Parry")
@export var can_block: bool = true
@export var block_chance: float = 0.50
@export var parry_chance: float = 0.25
@export var tactical_block_chance: float = 0.35
@export var block_duration_min: float = 0.6
@export var block_duration_max: float = 1.3

# --- Combat Kick ---
@export_group("Combat Kick")
@export var can_kick: bool = true
@export var kick_chance_on_blocking_player: float = 0.70
@export var kick_cooldown_min: float = 2.0
@export var kick_cooldown_max: float = 4.0
@export var kick_trigger_dist: float = 2.2

# --- Distances ---
@export_group("Distances")
@export var combat_engage_dist: float = 4.0
@export var combat_disengage_dist: float = 6.0
@export var ideal_combat_dist_min: float = 2.0
@export var ideal_combat_dist_max: float = 3.2
@export var lose_player_dist: float = 16.0

## Контакт клинка — чуть позже открытия хитбокса (окно хитбокса начинается в windup_time).
const PARRY_IMPACT_OFFSET: float = 0.05
## Доля окна парирования, которая приходится ДО момента удара (остаток — после).
const PARRY_LEAD_FRACTION: float = 0.6

var actor: CombatCharacter3D = null
var current_state: State = State.IDLE
var target: Node3D = null

# Timers
var combat_action_timer: float = 0.0
var attack_cooldown_timer: float = 0.0
var dodge_cooldown_timer: float = 0.0
var kick_cooldown_timer: float = 0.0
var block_hold_timer: float = 0.0
var approach_time_elapsed: float = 0.0

# Pending reaction
var is_dodge_pending: bool = false
var pending_dodge_timer: float = 0.0
var is_defense_pending: bool = false
var pending_defense_timer: float = 0.0
var pending_defense_action: int = 0 # 1 = dodge, 2 = block, 3 = parry
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

	if actor.is_staggered or actor.is_dashing or actor.is_attacking or actor.is_kicking:
		is_dodge_pending = false
		is_defense_pending = false
		return

	if dodge_cooldown_timer > 0.0:
		dodge_cooldown_timer -= delta

	if kick_cooldown_timer > 0.0:
		kick_cooldown_timer -= delta

	# Process block hold countdown
	if block_hold_timer > 0.0:
		block_hold_timer -= delta
		if block_hold_timer <= 0.0:
			if not (is_dummy and dummy_always_block) and actor.is_blocking():
				actor.cmd_block_release()

	# Process delayed reaction defense (dodge, block, parry)
	if is_defense_pending:
		pending_defense_timer -= delta
		if pending_defense_timer <= 0.0:
			is_defense_pending = false
			if not is_dummy and not actor.is_dashing and not actor.is_staggered and not actor.is_kicking:
				_execute_pending_defense()

	# Process delayed reaction dodge
	if is_dodge_pending:
		pending_dodge_timer -= delta
		if pending_dodge_timer <= 0.0:
			is_dodge_pending = false
			if not is_dummy and not actor.is_dashing and not actor.is_staggered and not actor.is_kicking:
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

	if is_dummy and dummy_always_block:
		if not actor.is_blocking() and not actor.is_staggered and not actor.is_dashing:
			actor.cmd_block_start()
		return

	# Counter-kick against turtling player holding block
	if not is_dummy and can_kick and kick_cooldown_timer <= 0.0 and dist <= kick_trigger_dist:
		var is_player_blocking: bool = false
		if target.has_method("is_blocking"):
			is_player_blocking = target.is_blocking()
		elif "defense_component" in target and is_instance_valid(target.defense_component):
			is_player_blocking = target.defense_component.is_blocking()

		if is_player_blocking and not actor.is_attacking and not actor.is_kicking:
			if randf() <= kick_chance_on_blocking_player:
				if actor.is_blocking():
					actor.cmd_block_release()
				actor.cmd_kick()
				kick_cooldown_timer = randf_range(kick_cooldown_min, kick_cooldown_max)
				return

	# Dodge / block reaction check
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
	# Drop block if stamina gets dangerously low
	if actor.is_blocking() and not (is_dummy and dummy_always_block):
		if actor.stamina_component and actor.stamina_component.current_stamina < _block_drop_stamina_threshold():
			actor.cmd_block_release()

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

	# Tactical blocking while maneuvering in combat
	if not is_dummy and can_block and randf() <= tactical_block_chance and not actor.is_blocking():
		actor.cmd_block_start()
		block_hold_timer = randf_range(block_duration_min, block_duration_max)


## Ниже этого уровня стамины ИИ опускает блок. 20/35 от ЭФФЕКТИВНОЙ цены блока:
## на базовых статах = 20 (как раньше), у бронированного порог падает вместе с ценой блока.
func _block_drop_stamina_threshold() -> float:
	return actor.stat(StatKeys.BLOCK_STAMINA_COST) * (20.0 / 35.0)


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
	if is_dummy or actor.is_dashing or is_dodge_pending or is_defense_pending:
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
		var delay := randf_range(reaction_time_min, reaction_time_max)
		var wants_dodge: bool = can_dodge and (randf() <= dodge_chance)
		var effective_cooldown := 0.0 if dodge_chance >= 0.99 else dodge_cooldown_timer

		var can_dash_now: bool = is_instance_valid(actor.dash_component) and actor.dash_component.can_dash()
		if wants_dodge and effective_cooldown <= 0.0 and can_dash_now:
			pending_defense_action = 1 # Dodge
			if delay <= 0.001:
				_execute_random_dodge()
			else:
				is_defense_pending = true
				pending_defense_timer = delay
			return true
		elif can_block and (randf() <= block_chance):
			if randf() <= parry_chance:
				pending_defense_action = 3 # Parry (block + deflect)
				delay = maxf(delay, _parry_start_delay())
			else:
				pending_defense_action = 2 # Block (passive guard)
			if delay <= 0.001:
				_execute_pending_defense()
			else:
				is_defense_pending = true
				pending_defense_timer = delay
			return true

	return false


## Через сколько секунд открывать окно парирования, чтобы удар цели пришёлся в его начало-середину.
## Учитывает ЭФФЕКТИВНЫЙ замах цели (windup / attack.speed) и ЭФФЕКТИВНОЕ окно самого ИИ (броня расширяет).
func _parry_start_delay() -> float:
	if not is_instance_valid(target) or not ("attack_component" in target):
		return 0.0
	var atk: MeleeAttackComponent = target.attack_component
	if not is_instance_valid(atk) or not is_instance_valid(atk.weapon_data):
		return 0.0
	# attack_time_elapsed идёт во «времени оружия» (уже умножено на attack_speed_scale)
	var scale: float = maxf(atk.attack_speed_scale, 0.1)
	var impact_weapon_time: float = atk.weapon_data.windup_time + PARRY_IMPACT_OFFSET
	var remaining: float = (impact_weapon_time - atk.attack_time_elapsed) / scale
	var window: float = actor.stat(StatKeys.PARRY_WINDOW)
	return maxf(0.0, remaining - window * PARRY_LEAD_FRACTION + randf_range(-0.03, 0.03))


func _execute_pending_defense() -> void:
	if not is_instance_valid(actor) or not actor.is_alive():
		return
	if actor.is_staggered or actor.is_dashing or actor.is_attacking or actor.is_kicking:
		return

	match pending_defense_action:
		1:
			_execute_random_dodge()
		2:
			# Passive block (hold guard)
			actor.cmd_block_start()
			block_hold_timer = randf_range(block_duration_min, block_duration_max)
		3:
			# Block + active parry window
			actor.cmd_block_start()
			actor.cmd_parry()
			block_hold_timer = randf_range(block_duration_min, block_duration_max)


func _execute_random_dodge() -> void:
	var roll := randf()
	var dir := DashComponent.DashDirection.BACKWARD
	if roll < 0.60:
		dir = DashComponent.DashDirection.BACKWARD
	elif roll < 0.80:
		dir = DashComponent.DashDirection.LEFT
	else:
		dir = DashComponent.DashDirection.RIGHT

	# Кулдаун уклонов запускаем только если дэш реально начался (cmd_dash мог отказать: блок, stagger и т.п.).
	if actor.cmd_dash(dir):
		# Паузу между уклонами масштабируем так же, как кулдаун дэша билда (ловкий враг уклоняется чаще).
		var cd_scale: float = actor.stat(StatKeys.DASH_COOLDOWN) / maxf(actor.stat_block.get_base(StatKeys.DASH_COOLDOWN), 0.001)
		dodge_cooldown_timer = randf_range(dodge_cooldown_min, dodge_cooldown_max) * cd_scale


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
