class_name TechniqueComponent
extends Node
## Экипированные приёмы, откаты и исполнение. Каждый Kind обслуживает свой TechniqueHandler.
## Вызывается только через CombatCharacter3D.cmd_technique().

signal technique_started(data: TechniqueData)
## cancelled = true, если приём прервали (hit-react, stagger, смерть).
signal technique_finished(data: TechniqueData, cancelled: bool)

var actor: CombatCharacter3D = null
## id -> TechniqueData
var equipped: Dictionary = {}
## id -> оставшийся откат, с
var cooldowns: Dictionary = {}
var _handler: TechniqueHandler = null


func setup(parent_actor: CombatCharacter3D) -> void:
	actor = parent_actor


func equip(data: TechniqueData) -> void:
	if data != null and data.id != &"":
		equipped[data.id] = data


func unequip(id: StringName) -> void:
	equipped.erase(id)


func is_equipped(id: StringName) -> bool:
	return equipped.has(id)


func cooldown_left(id: StringName) -> float:
	return cooldowns.get(id, 0.0)


## Идёт ли приём, который держит актора на месте (приём-удар сюда не входит).
func is_busy() -> bool:
	return _handler != null and _handler.owns_actor()


func current() -> TechniqueData:
	return _handler.data if _handler != null else null


func can_use(id: StringName) -> bool:
	var data: TechniqueData = equipped.get(id)
	if data == null or not is_instance_valid(actor) or not actor.is_alive():
		return false
	if _handler != null or cooldown_left(id) > 0.0:
		return false
	if actor.is_staggered or actor.is_dashing or actor.is_attacking or actor.is_kicking \
			or actor.is_healing or actor.is_blocking():
		return false
	if data.stamina_cost > 0.0 and not (is_instance_valid(actor.stamina_component) and actor.stamina_component.can_afford(data.stamina_cost)):
		return false
	if data.focus_cost > 0.0 and not (is_instance_valid(actor.focus_component) and actor.focus_component.can_afford(data.focus_cost)):
		return false
	return true


func start(id: StringName) -> bool:
	if not can_use(id):
		return false
	var data: TechniqueData = equipped[id]
	var handler := _make_handler(data.kind)
	if not handler.begin(actor, data):
		return false
	if data.stamina_cost > 0.0:
		actor.stamina_component.consume(data.stamina_cost)
	if data.focus_cost > 0.0:
		actor.focus_component.consume(data.focus_cost)
	if data.cooldown > 0.0:
		cooldowns[id] = data.cooldown
	_handler = handler
	technique_started.emit(data)
	return true


func cancel() -> void:
	if _handler == null:
		return
	var h := _handler
	_handler = null
	h.cancel()
	technique_finished.emit(h.data, true)


## Откаты и текущий приём; тикается всегда, пока актор жив.
func update(delta: float) -> void:
	for id: StringName in cooldowns.keys():
		var left: float = cooldowns[id] - delta
		if left <= 0.0:
			cooldowns.erase(id)
		else:
			cooldowns[id] = left
	if _handler == null:
		return
	_handler.process(delta)
	if _handler.is_finished():
		var h := _handler
		_handler = null
		technique_finished.emit(h.data, false)


func reset() -> void:
	cancel()
	cooldowns.clear()


func _make_handler(kind: TechniqueData.Kind) -> TechniqueHandler:
	match kind:
		TechniqueData.Kind.ATTACK_VARIANT:
			return AttackVariantHandler.new()
		_:
			# COMBO/BLOCK_ACTION/PARRY_FOLLOWUP/FEINT/BUFF: свои обработчики появятся вместе с приёмами.
			return TechniqueHandler.new()
