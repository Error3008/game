class_name CombatCharacter3D
extends CharacterBody3D

signal character_died(attacker: Node3D)

# --- События актора (шина для FX, ИИ, шкалы слома, записи боя) ---
## Успешная команда: &"attack_light", &"attack_heavy" (data = WeaponData), &"block", &"parry", &"dash" (data = DashDirection), &"kick", &"heal".
signal action_started(action: StringName, data: Variant)
## Этот актор получил удар (в т.ч. уклон/парирование/блок). result — итог take_hit.
signal hit_received(info: DamageInfo, result: Dictionary)
## Этот актор нанёс удар цели (эмитится сразу после hit_received цели).
signal hit_dealt(target: Node3D, info: DamageInfo, result: Dictionary)
## Актор оглушён через stagger() (hit-react сюда не входит: см. result["reacted"]).
signal staggered(duration: float, source: Node3D)
## Фаза удара: &"windup", &"active", &"recovery", &"idle".
signal attack_phase_changed(phase: StringName)

# --- Имена состояний ActionSelect (AnimationTree) — единое место ---
const ACTION_HEAVY: StringName = &"heavy_attack"
const ACTION_LIGHT: StringName = &"light_attack"
const ACTION_HIT_REACT: StringName = &"hit_react"
const ACTION_STAGGER: StringName = &"stagger"
const ACTION_DEATH: StringName = &"death"
const ACTION_HEAL: StringName = &"heal"
## Слои коллизий (битовые маски; совпадают со слоями в .tscn): рельеф/пол, игрок и его союзники, враги.
const LAYER_WORLD: int = 1
const LAYER_PLAYER_SIDE: int = 2
const LAYER_ENEMY_SIDE: int = 4
## Длительность клипа Stagger (с) — для масштаба времени под длительность оглушения.
const STAGGER_CLIP_LENGTH: float = 1.17
## Через сколько секунд после старта Death замораживаем позу трупа (клип 2.0 с, после 1.58 неподвижен).
const DEATH_FREEZE_TIME: float = 1.75

@export_group("Configuration")
@export var stats: CharacterStats = null
@export var hitbox_target_mask: int = 4 # Default 4 (scans enemies) for player, 2 for enemy

# --- Node References ---
@onready var pawn: Node3D = get_node_or_null("pawn")
@onready var animation_tree: AnimationTree = get_node_or_null("pawn/AnimationTree")

var stat_block: StatBlock = null
var health_component: HealthComponent = null
var defense_component: DefenseComponent = null
var attack_component: MeleeAttackComponent = null
var dash_component: DashComponent = null
var stamina_component: StaminaComponent = null
var kick_component: KickComponent = null
var heal_component: HealComponent = null

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

var is_kicking: bool:
	get:
		return kick_component.is_kicking if is_instance_valid(kick_component) else false

var is_healing: bool:
	get:
		return heal_component.is_healing if is_instance_valid(heal_component) else false

var is_dashing: bool:
	get:
		return dash_component.is_dashing if is_instance_valid(dash_component) else false

var current_health: float:
	get:
		return health_component.current_health if is_instance_valid(health_component) else 100.0

var max_health: float:
	get:
		return health_component.max_health if is_instance_valid(health_component) else 100.0

var current_stamina: float:
	get:
		return stamina_component.current_stamina if is_instance_valid(stamina_component) else 100.0

var max_stamina: float:
	get:
		return stamina_component.max_stamina if is_instance_valid(stamina_component) else 100.0


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
	# StatBlock создаётся первым: компоненты регистрируют в нём базы в своём setup().
	stat_block = StatBlock.new()
	stat_block.name = "StatBlock"
	add_child(stat_block)
	_register_actor_stat_bases()

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
		if not defense_component.parry_successful.is_connected(_on_parry_successful):
			defense_component.parry_successful.connect(_on_parry_successful)

	attack_component = get_node_or_null("MeleeAttackComponent") as MeleeAttackComponent
	if is_instance_valid(attack_component):
		attack_component.setup(self, hitbox_target_mask)
		attack_component.attack_phase_changed.connect(func(p: StringName) -> void: attack_phase_changed.emit(p))

	dash_component = get_node_or_null("DashComponent") as DashComponent
	if is_instance_valid(dash_component):
		dash_component.setup(self)

	stamina_component = get_node_or_null("StaminaComponent") as StaminaComponent
	if not is_instance_valid(stamina_component):
		stamina_component = StaminaComponent.new()
		stamina_component.name = "StaminaComponent"
		add_child(stamina_component)
	stamina_component.setup(self)
	stamina_component.init_from_stats(stats)

	kick_component = get_node_or_null("KickComponent") as KickComponent
	if not is_instance_valid(kick_component):
		kick_component = KickComponent.new()
		kick_component.name = "KickComponent"
		add_child(kick_component)
	kick_component.setup(self, hitbox_target_mask)

	heal_component = get_node_or_null("HealComponent") as HealComponent
	if not is_instance_valid(heal_component):
		heal_component = HealComponent.new()
		heal_component.name = "HealComponent"
		add_child(heal_component)
	heal_component.setup(self)
	heal_component.init_from_stats(stats)

	# Базы уже зарегистрированы компонентами — теперь накладываем билд.
	apply_build()


## Пересчитывает модификаторы билда (armor/agility) из stats. Безопасно вызывать повторно.
func apply_build() -> void:
	var rules: AttributeRules = stats.attribute_rules if stats.attribute_rules != null else AttributeRules.new()
	rules.apply(stat_block, stats.armor, stats.agility)


## Итоговое значение стата (база + модификаторы билда).
func stat(key: StringName) -> float:
	return stat_block.get_value(key)


## Итоговый множитель входящего урона типа: damage.taken (все типы) × damage.taken_physical (только физический).
## Произведение зажато в те же границы, что и каждый ключ, поэтому броня вместе с ловкостью не пробивает потолок.
func damage_multiplier(type: DamageInfo.DamageType) -> float:
	var mult: float = stat(StatKeys.DAMAGE_TAKEN)
	if type == DamageInfo.DamageType.PHYSICAL:
		mult *= stat(StatKeys.DAMAGE_TAKEN_PHYSICAL)
	var b: Vector2 = StatKeys.BOUNDS[StatKeys.DAMAGE_TAKEN]
	return clampf(mult, b.x, b.y)


## Скорость движения по ключу с общим множителем move.speed.
## StatBlock.get_value кэширует итог, так что вызов дешёвый (2 чтения из словаря).
func move_speed(key: StringName) -> float:
	return stat_block.get_value(key) * stat_block.get_value(StatKeys.MOVE_SPEED)


## Базы статов, которыми владеет сам актор (движение, входящий урон, здоровье).
## Базы компонентов (dash.*, defense.*, stamina.*, attack.speed) регистрируют сами компоненты.
func _register_actor_stat_bases() -> void:
	stat_block.set_base(StatKeys.MOVE_SPEED, 1.0)
	stat_block.set_base(StatKeys.MOVE_RUN, stats.run_speed)
	stat_block.set_base(StatKeys.MOVE_WALK, stats.walk_speed)
	stat_block.set_base(StatKeys.MOVE_COMBAT_WALK, stats.combat_walk_speed)
	stat_block.set_base(StatKeys.MOVE_COMBAT_STRAFE, stats.combat_strafe_speed)
	stat_block.set_base(StatKeys.DAMAGE_TAKEN, 1.0)
	stat_block.set_base(StatKeys.DAMAGE_TAKEN_PHYSICAL, 1.0)
	stat_block.set_base(StatKeys.HEALTH_MAX, stats.max_health)


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

	# Always tick stamina component (regen & delay)
	if is_instance_valid(stamina_component):
		stamina_component.update(delta)

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

	# 3.5. Process kick component
	elif is_kicking and is_instance_valid(kick_component):
		kick_component.process_kick(delta)
		target_combat_mode = 1.0
		target_combat_movement = Vector2.ZERO
		velocity.x = lerp(velocity.x, 0.0, stats.decel * delta)
		velocity.z = lerp(velocity.z, 0.0, stats.decel * delta)

	# 3.6. Process heal component (стоим на месте, пока пьём)
	elif is_healing and is_instance_valid(heal_component):
		heal_component.process_heal(delta)
		target_combat_movement = Vector2.ZERO
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
	if is_staggered or is_attacking or is_dashing or is_kicking or is_healing or is_blocking():
		return

	target_combat_mode = 0.0
	target_combat_movement = Vector2.ZERO

	if world_dir != Vector3.ZERO:
		var speed := move_speed(StatKeys.MOVE_RUN if is_running else StatKeys.MOVE_WALK)
		desired_move_velocity.x = lerp(velocity.x, world_dir.x * speed, stats.accel * get_physics_process_delta_time())
		desired_move_velocity.z = lerp(velocity.z, world_dir.z * speed, stats.accel * get_physics_process_delta_time())
		is_moving_requested = true
		cmd_face_direction(world_dir, get_physics_process_delta_time())
	else:
		is_moving_requested = false


func cmd_combat_move(lateral: float, forward: float, speed_override: float = -1.0) -> void:
	if is_staggered or is_attacking or is_dashing or is_kicking or is_healing or is_blocking():
		return

	target_combat_mode = 1.0
	target_combat_movement = Vector2(lateral, forward)

	if is_instance_valid(current_target):
		cmd_face_point(current_target.global_position, get_physics_process_delta_time())

	if absf(lateral) > 0.01 or absf(forward) > 0.01:
		var forward_b := get_forward_basis()
		var right_b := get_right_basis()

		var move_dir := (forward_b * forward + right_b * lateral).normalized()
		var speed := speed_override * stat(StatKeys.MOVE_SPEED) if speed_override > 0.0 else move_speed(StatKeys.MOVE_COMBAT_STRAFE if absf(lateral) > 0.1 else StatKeys.MOVE_COMBAT_WALK)

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
	return _start_attack(false)


func cmd_attack_light() -> bool:
	return _start_attack(true)


func _start_attack(light: bool) -> bool:
	if is_staggered or is_dashing or is_kicking or is_healing:
		return false
	if is_blocking():
		return cmd_parry()
	if is_instance_valid(attack_component):
		target_combat_movement = Vector2.ZERO
		target_combat_mode = 1.0
		var started := attack_component.start_attack(light)
		if started:
			action_started.emit(&"attack_light" if light else &"attack_heavy", attack_component.weapon_data)
		return started
	return false


func cmd_heal() -> bool:
	if is_staggered or is_dashing or is_attacking or is_kicking or is_blocking() or not is_instance_valid(heal_component):
		return false
	target_combat_movement = Vector2.ZERO
	var started := heal_component.start_heal()
	if started:
		action_started.emit(&"heal", null)
	return started


func cmd_kick() -> bool:
	if is_staggered or is_dashing or is_attacking or is_kicking or is_healing:
		return false
	if is_blocking():
		return false
	if is_instance_valid(kick_component):
		target_combat_movement = Vector2.ZERO
		target_combat_mode = 1.0
		var started := kick_component.start_kick()
		if started:
			action_started.emit(&"kick", null)
		return started
	return false


func cmd_dash(chosen_dir: DashComponent.DashDirection) -> bool:
	if is_staggered or is_dashing or is_healing or not is_instance_valid(dash_component):
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

	# Dodge cancel: can cancel kick if in recovery phase
	if is_kicking and is_instance_valid(kick_component):
		if kick_component.is_in_recovery():
			kick_component.cancel_kick()
		else:
			return false

	var started := dash_component.start_dash(chosen_dir)
	if started:
		action_started.emit(&"dash", chosen_dir)
	return started


func cmd_block_start() -> bool:
	if is_staggered or is_dashing or is_attacking or is_kicking or is_healing or not is_instance_valid(defense_component):
		return false
	var started := defense_component.start_block()
	if started:
		action_started.emit(&"block", null)
	return started


func cmd_block_release() -> void:
	if is_instance_valid(defense_component):
		defense_component.release_block()


func cmd_parry() -> bool:
	if not is_instance_valid(defense_component):
		return false
	var success := defense_component.trigger_parry()
	if success:
		play_parry_success()
		action_started.emit(&"parry", null)
	return success


func cmd_set_target(target: Node3D) -> void:
	current_target = target


func cmd_clear_target() -> void:
	current_target = null
	if is_blocking() and is_instance_valid(defense_component):
		defense_component.end_block()


# --- Combat Physics & Reactions ---

## block_stamina: цена блока этого удара в стамине защитника (WeaponData.block_stamina_damage); -1 = по умолчанию.
## Тонкая обёртка над take_hit для прямых вызовов (тесты, простые источники урона): физический удар без флагов.
func take_damage(amount: float, knockback_impulse: Vector3, attacker_node: Node3D = null, block_stamina: float = -1.0) -> void:
	take_hit(DamageInfo.make(amount, knockback_impulse, attacker_node, &"direct", block_stamina))


## Единая точка урона. Возвращает итог удара для FX и ИИ:
## dodged, was_parried, was_blocked, was_guard_broken, final_damage, reacted.
func take_hit(info: DamageInfo) -> Dictionary:
	if not is_alive():
		return _new_hit_result()
	var result := _resolve_hit(info)
	hit_received.emit(info, result)
	var attacker_actor := info.attacker as CombatCharacter3D
	if is_instance_valid(attacker_actor):
		attacker_actor.hit_dealt.emit(self, info, result)
	return result


func _new_hit_result() -> Dictionary:
	return {
		"dodged": false,
		"was_parried": false,
		"was_blocked": false,
		"was_guard_broken": false,
		"final_damage": 0.0,
		"reacted": false
	}


func _resolve_hit(info: DamageInfo) -> Dictionary:
	var result := _new_hit_result()

	var attacker_node: Node3D = info.attacker
	var att_name := String(attacker_node.name) if is_instance_valid(attacker_node) else "Attacker"

	# 1. I-frame check via DashComponent
	if is_dashing and is_instance_valid(dash_component) and dash_component.is_in_iframe():
		print("[%s] Dodged attack from %s via dash i-frame!" % [name, att_name])
		result["dodged"] = true
		return result

	var final_damage := info.amount
	var final_knockback := info.knockback
	var was_blocked := false

	# 2. DefenseComponent evaluation (Block, Parry, Penalty, Backstab check)
	if is_instance_valid(defense_component):
		var eval := defense_component.evaluate_hit(info)
		if eval["was_parried"]:
			print("[%s] PERFECT PARRY against %s! Negated %.1f damage with 0 knockback." % [name, att_name, info.amount])
			play_parry_success()
			result["was_parried"] = true
			return result

		if eval["was_blocked"]:
			was_blocked = true
			final_damage = eval["damage_taken"]
			final_knockback = eval["knockback_taken"]
			if eval.get("was_guard_broken", false):
				result["was_guard_broken"] = true
				print("[%s] GUARD BROKEN by %s! Defenses collapsed." % [name, att_name])
			else:
				print("[%s] Blocked attack from %s (took %.1f of %.1f damage)." % [name, att_name, final_damage, info.amount])
				play_block_impact()

		if eval["was_penalty"]:
			print("[%s] STRUCK DURING PARRY PENALTY! Defenses broken." % name)

	result["was_blocked"] = was_blocked

	# 2б. Множитель входящего урона от билда (броня только против физического, ловкость против любого): после блока, до здоровья
	final_damage *= damage_multiplier(info.damage_type)
	result["final_damage"] = final_damage

	# 3. Apply damage to HealthComponent
	if is_instance_valid(health_component):
		health_component.take_damage(final_damage, attacker_node)
		print("[%s] Took %.1f damage from %s. Remaining HP: %.1f" % [name, final_damage, att_name, health_component.current_health])

	# 4. Hit reaction: чистое попадание прерывает текущее действие получателя (hyper armor не прерывается)
	var armored := has_hyper_armor()
	if armored:
		final_knockback *= 0.3
	if info.causes_hit_react and not armored and is_alive() and not was_blocked and final_damage > 0.0 and not is_staggered:
		_react_to_hit()
		result["reacted"] = true

	# 5. Apply physical knockback
	velocity.x += final_knockback.x
	velocity.z += final_knockback.z
	return result


func stagger(duration: float = 0.8, from_node: Node3D = null) -> void:
	if not is_alive():
		return

	_cancel_all_actions()
	abort_action()
	play_action(ACTION_STAGGER, STAGGER_CLIP_LENGTH / maxf(duration, 0.1))

	is_staggered = true
	stagger_timer = duration
	staggered.emit(duration, from_node)

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


## Отменяет всё текущее действие (атака, пинок, дэш, лечение, блок).
func _cancel_all_actions() -> void:
	if is_attacking and is_instance_valid(attack_component):
		attack_component.cancel_attack()
	if is_kicking and is_instance_valid(kick_component):
		kick_component.cancel_kick()
	if is_dashing and is_instance_valid(dash_component):
		dash_component.end_dash()
	if is_healing and is_instance_valid(heal_component):
		heal_component.cancel_heal()
	if is_blocking() and is_instance_valid(defense_component):
		defense_component.end_block()


func _react_to_hit() -> void:
	_cancel_all_actions()
	abort_action()
	play_action(ACTION_HIT_REACT, 1.0)
	is_staggered = true
	stagger_timer = stats.hit_react_stun_duration


## Есть ли сейчас защита от прерывания (оружие с hyper_armor в окне замах + активная фаза).
func has_hyper_armor() -> bool:
	return is_instance_valid(attack_component) and attack_component.has_hyper_armor()


## Профиль идущей атаки (WeaponData) или null, если актор не атакует. Для ИИ и FX.
func get_current_attack_profile() -> WeaponData:
	if is_instance_valid(attack_component) and attack_component.is_attacking:
		return attack_component.weapon_data
	return null


func on_attack_deflected(by_node: Node3D) -> void:
	stagger(0.8, by_node)


## Полное восстановление живого актора: здоровье, стамина, заряды фляги, прерывание действий.
## Для тестовой лаборатории (телепорт между клетками дуэлей). Мёртвого не воскрешает.
func restore_full() -> void:
	if not is_alive():
		return
	_cancel_all_actions()
	abort_action()
	is_staggered = false
	stagger_timer = 0.0
	velocity = Vector3.ZERO
	health_component.init_health(health_component.max_health)
	stamina_component.restore(stamina_component.max_stamina)
	heal_component.init_from_stats(stats)


func is_alive() -> bool:
	return is_instance_valid(health_component) and not health_component.is_dead


func is_blocking() -> bool:
	return is_instance_valid(defense_component) and defense_component.is_blocking()


func _on_died(attacker: Node3D) -> void:
	print("[%s] has DIED!" % name)
	is_staggered = false
	_cancel_all_actions()

	abort_action()
	play_action(ACTION_DEATH, 1.0)
	if is_inside_tree():
		get_tree().create_timer(DEATH_FREEZE_TIME).timeout.connect(_freeze_corpse_pose)
	cmd_clear_target()

	# Keep collision shape enabled so corpse never falls through the floor!
	# Set layer to 0 (no targeting/hits) and mask to 1 (floor/platforms only).
	collision_layer = 0
	collision_mask = LAYER_WORLD
	velocity.x = 0.0
	velocity.z = 0.0

	character_died.emit(attacker)


func _freeze_corpse_pose() -> void:
	if is_instance_valid(animation_tree) and not is_alive():
		animation_tree.active = false


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

func _on_parry_successful(_attacker: Node3D) -> void:
	play_parry_success()


func play_action(action_name: StringName, speed_scale: float = 1.0) -> void:
	if not is_instance_valid(animation_tree):
		return
	if "parameters/ActionTimeScale/scale" in animation_tree:
		animation_tree.set("parameters/ActionTimeScale/scale", speed_scale)
	var state_name := str(action_name)
	if state_name == "parry_success":
		state_name = "parry"
	animation_tree.set("parameters/ActionSelect/transition_request", state_name)
	animation_tree.set("parameters/ActionOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func play_block_impact(speed_scale: float = -1.0) -> void:
	var speed := 1.0
	if speed_scale > 0.0:
		speed = speed_scale
	elif is_instance_valid(defense_component):
		speed = defense_component.block_impact_speed_scale
	play_action(&"block_impact", speed)


func play_parry_success(speed_scale: float = -1.0) -> void:
	var speed := 1.0
	if speed_scale > 0.0:
		speed = speed_scale
	elif is_instance_valid(defense_component):
		speed = defense_component.parry_speed_scale
	play_action(&"parry", speed)


func abort_action() -> void:
	if not is_instance_valid(animation_tree):
		return
	if "parameters/ActionTimeScale/scale" in animation_tree:
		animation_tree.set("parameters/ActionTimeScale/scale", 1.0)
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
		var walk_spd := move_speed(StatKeys.MOVE_WALK)
		var run_spd := move_speed(StatKeys.MOVE_RUN)
		if horizontal_speed <= walk_spd:
			blend_val = remap(horizontal_speed, 0.0, walk_spd, 0.0, 0.5)
		else:
			blend_val = clampf(remap(horizontal_speed, walk_spd, run_spd, 0.5, 1.0), 0.5, 1.0)

	if "parameters/Locomotion/blend_position" in animation_tree:
		var cur_loco: float = animation_tree.get("parameters/Locomotion/blend_position")
		animation_tree.set("parameters/Locomotion/blend_position", lerp(cur_loco, blend_val, stats.locomotion_blend_speed * delta))

	# 5. Step rate adjustment (TimeScale)
	if "parameters/SpeedScale/scale" in animation_tree:
		var speed_scale := 1.0
		if horizontal_speed > 0.05:
			# Делим на БАЗОВУЮ скорость ходьбы (клип рассчитан на неё): иначе штраф брони
			# сокращает и делитель, и ноги анимируются в обычном темпе при замедленном движении.
			speed_scale = maxf(0.8, (horizontal_speed / stat_block.get_base(StatKeys.MOVE_WALK)) * stats.anim_speed_multiplier)
		animation_tree.set("parameters/SpeedScale/scale", speed_scale)
