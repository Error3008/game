class_name CombatFeedback
extends Node
## «Сок» боя: редкие плавные замедления времени («моменты») в красивые мгновения.
## Идеальное парирование, слом защиты, добивающий удар. Обычные удары время не трогают.
## Слушает hit_received всех актёров сцены и не лезёт в боевую логику.
## Единственная точка записи Engine.time_scale — _apply_scale().

const GROUP: StringName = &"combat_feedback"

enum Moment { NONE, GUARD_BREAK, PARRY, KILL }

@export var enabled: bool = true
## Только когда в ударе участвует игрок (дуэли ботов не тормозят мир).
@export var player_only: bool = true
@export var cooldown: float = 2.0  ## пауза между моментами, реальные секунды; добивание её игнорирует

@export_group("Идеальное парирование")
@export var parry_scale: float = 0.3
@export var parry_in: float = 0.08
@export var parry_hold: float = 0.25
@export var parry_out: float = 0.35
@export_group("Слом защиты")
@export var guard_break_scale: float = 0.35
@export var guard_break_in: float = 0.08
@export var guard_break_hold: float = 0.20
@export var guard_break_out: float = 0.30
@export_group("Добивающий удар")
@export var kill_scale: float = 0.2
@export var kill_in: float = 0.10
@export var kill_hold: float = 0.50
@export var kill_out: float = 0.60

var _moment: int = Moment.NONE
var _start_msec: int = 0
var _target_scale: float = 1.0
var _t_in: float = 0.0
var _t_hold: float = 0.0
var _t_out: float = 0.0
var _last_end_msec: int = -1000000


func _ready() -> void:
	add_to_group(GROUP)
	# В headless (тесты) эффект выключен: он сдвигает тайминги. Тест включает его вручную.
	if DisplayServer.get_name() == "headless":
		enabled = false
	for actor: Node in get_tree().root.find_children("*", "CombatCharacter3D", true, false):
		_watch(actor as CombatCharacter3D)
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	_moment = Moment.NONE
	_apply_scale(1.0)


func _on_node_added(node: Node) -> void:
	if node is CombatCharacter3D:
		_watch(node as CombatCharacter3D)


func _watch(actor: CombatCharacter3D) -> void:
	if not actor.hit_received.is_connected(_on_hit_received):
		actor.hit_received.connect(_on_hit_received.bind(actor))


func _on_hit_received(info: DamageInfo, result: Dictionary, victim: CombatCharacter3D) -> void:
	if not enabled or result.get("dodged", false):
		return
	if player_only and not (victim is Player or info.attacker is Player):
		return
	var kind: int = Moment.NONE
	if not victim.is_alive():
		kind = Moment.KILL
	elif result.get("was_parried", false):
		kind = Moment.PARRY
	elif result.get("was_guard_broken", false):
		kind = Moment.GUARD_BREAK
	if kind != Moment.NONE:
		begin(kind)


## Запускает момент. Сильнее текущего (по порядку enum) перебивает, слабее и в паузе игнорируется.
func begin(kind: int, now_msec: int = -1) -> bool:
	if kind == Moment.NONE:
		return false
	if now_msec < 0:
		now_msec = Time.get_ticks_msec()
	if _moment != Moment.NONE:
		if kind <= _moment:
			return false
	elif kind != Moment.KILL and now_msec - _last_end_msec < int(cooldown * 1000.0):
		return false
	# Стартуем плавно с текущего масштаба: перебитый момент не даёт скачка.
	var from_scale: float = Engine.time_scale
	_moment = kind
	_start_msec = now_msec
	match kind:
		Moment.PARRY:
			_set_params(parry_scale, parry_in, parry_hold, parry_out)
		Moment.GUARD_BREAK:
			_set_params(guard_break_scale, guard_break_in, guard_break_hold, guard_break_out)
		_:
			_set_params(kill_scale, kill_in, kill_hold, kill_out)
	_from_scale = from_scale
	return true


var _from_scale: float = 1.0


func _set_params(scale: float, t_in: float, t_hold: float, t_out: float) -> void:
	_target_scale = scale
	_t_in = maxf(t_in, 0.001)
	_t_hold = t_hold
	_t_out = maxf(t_out, 0.001)


## Масштаб времени в момент t секунд от старта: плавный вход, удержание, плавный выход.
func scale_at(t: float) -> float:
	if t < 0.0:
		return _from_scale
	if t < _t_in:
		return lerpf(_from_scale, _target_scale, smoothstep(0.0, 1.0, t / _t_in))
	t -= _t_in
	if t < _t_hold:
		return _target_scale
	t -= _t_hold
	if t < _t_out:
		return lerpf(_target_scale, 1.0, smoothstep(0.0, 1.0, t / _t_out))
	return 1.0


func is_active() -> bool:
	return _moment != Moment.NONE


## Двигает кривую по реальным часам. Вызывается из _process, в тестах — вручную.
func tick(now_msec: int = -1) -> void:
	if _moment == Moment.NONE:
		return
	if now_msec < 0:
		now_msec = Time.get_ticks_msec()
	var t: float = float(now_msec - _start_msec) / 1000.0
	if t >= _t_in + _t_hold + _t_out:
		_moment = Moment.NONE
		_last_end_msec = now_msec
		_apply_scale(1.0)
	else:
		_apply_scale(scale_at(t))


func _process(_delta: float) -> void:
	tick()


func _apply_scale(value: float) -> void:
	Engine.time_scale = value
