class_name HealComponent
extends Node

## Лечение флягой: клип Heal (1.46 с), хил засчитывается на ~0.8 с.
## Прервали раньше — хила нет, заряд потрачен. Фляга (`flask` на Palm_L) видна 0.29–1.25 с.

signal heal_started
signal heal_applied(amount: float)
signal heal_interrupted
signal heal_finished
signal charges_changed(charges: int, max_charges: int)

@export_group("Timings")
@export var heal_apply_time: float = 0.8
@export var total_duration: float = 1.46
@export var flask_show_time: float = 0.29
@export var flask_hide_time: float = 1.25

@export_group("Flask")
@export var max_charges: int = 3
@export var heal_amount: float = 40.0

var charges: int = 3
var is_healing: bool = false
var heal_time_elapsed: float = 0.0
var _applied: bool = false

var actor: CombatCharacter3D = null
var _flask: Node3D = null


func setup(parent_actor: CombatCharacter3D) -> void:
	actor = parent_actor
	_flask = actor.find_child("flask", true, false) as Node3D
	_set_flask_visible(false)


func init_from_stats(stats: CharacterStats) -> void:
	max_charges = stats.heal_charges
	heal_amount = stats.heal_amount
	charges = max_charges
	charges_changed.emit(charges, max_charges)


func can_heal() -> bool:
	if is_healing or charges <= 0 or not is_instance_valid(actor):
		return false
	return actor.is_alive() and actor.current_health < actor.max_health


func start_heal() -> bool:
	if not can_heal():
		return false
	charges -= 1
	charges_changed.emit(charges, max_charges)
	is_healing = true
	_applied = false
	heal_time_elapsed = 0.0
	actor.play_action(&"heal", 1.0)
	heal_started.emit()
	return true


func process_heal(delta: float) -> void:
	if not is_healing:
		return
	heal_time_elapsed += delta
	_set_flask_visible(heal_time_elapsed >= flask_show_time and heal_time_elapsed < flask_hide_time)
	if not _applied and heal_time_elapsed >= heal_apply_time:
		_applied = true
		actor.health_component.heal(heal_amount)
		heal_applied.emit(heal_amount)
	if heal_time_elapsed >= total_duration:
		is_healing = false
		_set_flask_visible(false)
		heal_finished.emit()


func cancel_heal() -> void:
	if not is_healing:
		return
	is_healing = false
	_set_flask_visible(false)
	heal_interrupted.emit()


func _set_flask_visible(v: bool) -> void:
	if is_instance_valid(_flask):
		_flask.visible = v
