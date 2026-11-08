class_name DashComponent
extends Node

signal dash_started(direction: DashDirection)
signal dash_finished

enum DashDirection {
	FORWARD,
	BACKWARD,
	LEFT,
	RIGHT
}

const DASH_ANIM_MAP: Dictionary = {
	DashDirection.FORWARD: &"dash_fwd",
	DashDirection.BACKWARD: &"dash_bwd",
	DashDirection.LEFT: &"dash_left",
	DashDirection.RIGHT: &"dash_right",
}

@export_group("Combat Dash")
@export var dash_speed: float = 8.5
@export var dash_duration: float = 0.42
@export var dash_cooldown: float = 0.55
@export var dash_iframe_start: float = 0.04
@export var dash_iframe_end: float = 0.32

@export_group("Stamina")
## Stamina consumed per dash maneuver.
@export var stamina_cost: float = 25.0

var is_dashing: bool = false
var dash_time_elapsed: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_move_direction: Vector3 = Vector3.ZERO
# Снимок статов на момент старта дэша (чтобы смена модификаторов не ломала дэш посреди движения)
var _active_speed: float = 0.0
var _active_exit_speed: float = 0.0
var _active_duration: float = 0.0
var _active_iframe_end: float = 0.0

var actor: Node3D = null


func setup(parent_actor: Node3D) -> void:
	actor = parent_actor
	var sb: StatBlock = actor.get("stat_block") if is_instance_valid(actor) else null
	if sb != null:
		sb.set_base(StatKeys.DASH_SPEED, dash_speed)
		sb.set_base(StatKeys.DASH_DURATION, dash_duration)
		sb.set_base(StatKeys.DASH_COOLDOWN, dash_cooldown)
		sb.set_base(StatKeys.DASH_IFRAME_DURATION, dash_iframe_end - dash_iframe_start)
		sb.set_base(StatKeys.DASH_STAMINA_COST, stamina_cost)


## Итоговое значение стата актора (с модификаторами билда); fallback — если StatBlock нет.
func _stat(key: StringName, fallback: float) -> float:
	var sb: StatBlock = actor.get("stat_block") if is_instance_valid(actor) else null
	return sb.get_value(key) if sb != null else fallback


func update(delta: float) -> void:
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer = maxf(0.0, dash_cooldown_timer - delta)

	if not is_dashing:
		return

	dash_time_elapsed += delta

	# Physical movement: smoothly decelerate toward combat walk speed
	if dash_time_elapsed < _active_duration:
		var progress := clampf(dash_time_elapsed / _active_duration, 0.0, 1.0)
		var target_speed := lerpf(_active_speed, _active_exit_speed, progress)
		if is_instance_valid(actor) and actor.has_method("apply_dash_velocity"):
			actor.apply_dash_velocity(dash_move_direction, target_speed, delta)
	else:
		end_dash()


func process_dash(delta: float) -> void:
	update(delta)


func can_dash() -> bool:
	if is_dashing or dash_cooldown_timer > 0.0:
		return false
	if is_instance_valid(actor) and "stamina_component" in actor and is_instance_valid(actor.stamina_component):
		if not actor.stamina_component.can_afford(_stat(StatKeys.DASH_STAMINA_COST, stamina_cost)):
			return false
	return true


func start_dash(chosen_dir: DashDirection) -> bool:
	if not can_dash():
		if is_instance_valid(actor) and "stamina_component" in actor and is_instance_valid(actor.stamina_component):
			var need := _stat(StatKeys.DASH_STAMINA_COST, stamina_cost)
			if not actor.stamina_component.can_afford(need):
				print("[%s] Cannot dash! Insufficient stamina (need %.1f, have %.1f)." % [actor.name, need, actor.stamina_component.current_stamina])
		return false

	if is_instance_valid(actor) and "stamina_component" in actor and is_instance_valid(actor.stamina_component):
		actor.stamina_component.consume(_stat(StatKeys.DASH_STAMINA_COST, stamina_cost))

	is_dashing = true
	dash_time_elapsed = 0.0
	# Кулдаун стартует с КОНЦА дэша (см. end_dash), иначе баф кулдауна «съедается» длительностью.
	dash_cooldown_timer = 0.0
	_active_speed = _stat(StatKeys.DASH_SPEED, dash_speed)
	_active_duration = _stat(StatKeys.DASH_DURATION, dash_duration)
	# Скорость, к которой дэш затухает к концу (боевой шаг билда)
	_active_exit_speed = _stat(StatKeys.MOVE_COMBAT_WALK, 2.4) * _stat(StatKeys.MOVE_SPEED, 1.0)
	# i-frames: окно [start, start + длительность], но не дольше самого дэша (минус 0.02 с запаса)
	_active_iframe_end = minf(dash_iframe_start + _stat(StatKeys.DASH_IFRAME_DURATION, dash_iframe_end - dash_iframe_start), _active_duration - 0.02)

	var forward_basis := Vector3.FORWARD
	var right_basis := Vector3.RIGHT
	if is_instance_valid(actor):
		if actor.has_method("get_forward_basis"):
			forward_basis = actor.get_forward_basis()
		if actor.has_method("get_right_basis"):
			right_basis = actor.get_right_basis()

	match chosen_dir:
		DashDirection.FORWARD:
			dash_move_direction = forward_basis
		DashDirection.BACKWARD:
			dash_move_direction = -forward_basis
		DashDirection.LEFT:
			dash_move_direction = -right_basis
		DashDirection.RIGHT:
			dash_move_direction = right_basis

	var anim_name: StringName = DASH_ANIM_MAP.get(chosen_dir, &"dash_bwd")
	if is_instance_valid(actor) and actor.has_method("play_action"):
		actor.play_action(anim_name)

	# Apply initial kinetic impulse
	if is_instance_valid(actor) and actor.has_method("set_dash_initial_velocity"):
		actor.set_dash_initial_velocity(dash_move_direction * _active_speed)

	dash_started.emit(chosen_dir)
	return true


func end_dash() -> void:
	if not is_dashing:
		return
	is_dashing = false
	dash_cooldown_timer = _stat(StatKeys.DASH_COOLDOWN, dash_cooldown)
	dash_finished.emit()


func is_in_iframe() -> bool:
	return is_dashing and dash_time_elapsed >= dash_iframe_start and dash_time_elapsed <= _active_iframe_end
