class_name FocusComponent
extends Node
## Ресурс приёмов «запал» (рабочее название). Копит со временем, тратится на приёмы.
## По умолчанию максимум 0: у воина без школы запала нет.

signal focus_changed(current: float, max_focus: float)

@export var max_focus: float = 0.0
@export var current_focus: float = 0.0
## Запал в секунду после паузы.
@export var regen_rate: float = 8.0
## Пауза после траты, с.
@export var regen_delay: float = 1.0

var actor: CombatCharacter3D = null
var regen_delay_timer: float = 0.0


func setup(parent_actor: CombatCharacter3D) -> void:
	actor = parent_actor
	if actor.stat_block != null:
		actor.stat_block.set_base(StatKeys.FOCUS_MAX, max_focus)
		actor.stat_block.set_base(StatKeys.FOCUS_REGEN, regen_rate)
	current_focus = clampf(current_focus, 0.0, max_focus)


## Задаёт максимум и реген (школа/билд); текущий запал заполняется до нового максимума.
func configure(new_max: float, new_regen: float = -1.0) -> void:
	max_focus = maxf(0.0, new_max)
	if new_regen >= 0.0:
		regen_rate = new_regen
	current_focus = max_focus
	if is_instance_valid(actor) and actor.stat_block != null:
		actor.stat_block.set_base(StatKeys.FOCUS_MAX, max_focus)
		actor.stat_block.set_base(StatKeys.FOCUS_REGEN, regen_rate)
	focus_changed.emit(current_focus, max_focus)


func update(delta: float) -> void:
	if max_focus <= 0.0:
		return
	if regen_delay_timer > 0.0:
		if delta <= regen_delay_timer:
			regen_delay_timer -= delta
			return
		delta -= regen_delay_timer
		regen_delay_timer = 0.0
	if current_focus >= max_focus:
		return
	current_focus = minf(max_focus, current_focus + regen_rate * delta)
	focus_changed.emit(current_focus, max_focus)


func can_afford(amount: float) -> bool:
	return current_focus >= amount


func consume(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if current_focus < amount:
		return false
	current_focus -= amount
	regen_delay_timer = regen_delay
	focus_changed.emit(current_focus, max_focus)
	return true


func restore_full() -> void:
	current_focus = max_focus
	regen_delay_timer = 0.0
	focus_changed.emit(current_focus, max_focus)
