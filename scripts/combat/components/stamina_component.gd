class_name StaminaComponent
extends Node

## Modular Stamina Component for CombatCharacter3D.
## Manages stamina consumption (attacks, dashes, blocked impacts),
## delayed regeneration with guard penalty, and guard-break state transitions.

signal stamina_changed(current: float, max_stamina: float)
signal stamina_depleted
signal stamina_recovered
signal guard_broken(attacker: Node3D)

@export_group("Stamina Capacity")
@export var max_stamina: float = 100.0
@export var current_stamina: float = 100.0

@export_group("Regeneration")
## Rate of stamina regeneration per second when not delayed.
@export var regen_rate: float = 25.0
## Delay in seconds after stamina consumption before regeneration begins.
@export var regen_delay: float = 0.8
## Multiplier applied to regen_rate when blocking (e.g. 0.25 = 75% penalty).
@export_range(0.0, 1.0) var block_regen_multiplier: float = 0.25
## If true, regeneration delay timer pauses while the character is in a staggered state.
@export var pause_regen_during_stagger: bool = false

@export_group("Configuration")
## If true, will copy values from actor's CharacterStats if available.
@export var use_stats_resource: bool = true
@export var debug_logging: bool = true

var actor: CombatCharacter3D = null
var regen_delay_timer: float = 0.0


func _ready() -> void:
	current_stamina = clampf(current_stamina, 0.0, max_stamina)


func setup(parent_actor: CombatCharacter3D) -> void:
	actor = parent_actor


func init_from_stats(stats: CharacterStats) -> void:
	if not use_stats_resource or stats == null:
		return
	if stats.max_stamina > 0.0:
		max_stamina = stats.max_stamina
		current_stamina = max_stamina
	if stats.stamina_regen_rate > 0.0:
		regen_rate = stats.stamina_regen_rate
	if stats.stamina_regen_delay >= 0.0:
		regen_delay = stats.stamina_regen_delay
	if stats.block_regen_multiplier >= 0.0:
		block_regen_multiplier = stats.block_regen_multiplier
	if is_instance_valid(actor) and actor.stat_block != null:
		actor.stat_block.set_base(StatKeys.STAMINA_MAX, max_stamina)
		actor.stat_block.set_base(StatKeys.STAMINA_REGEN, regen_rate)
	stamina_changed.emit(current_stamina, max_stamina)


func update(delta: float) -> void:
	if is_instance_valid(actor) and actor.has_method("is_alive") and not actor.is_alive():
		return

	# If configured, pause regen while staggered
	if pause_regen_during_stagger and is_instance_valid(actor) and actor.is_staggered:
		return

	# 1. Process regeneration delay after consumption
	if regen_delay_timer > 0.0:
		if delta <= regen_delay_timer:
			regen_delay_timer -= delta
			return
		else:
			delta -= regen_delay_timer
			regen_delay_timer = 0.0

	# 2. Already full
	if current_stamina >= max_stamina:
		return

	# 3. Calculate effective regeneration rate
	var effective_rate: float = regen_rate
	var is_blocking: bool = false
	if is_instance_valid(actor) and actor.has_method("is_blocking"):
		is_blocking = actor.is_blocking()

	if is_blocking:
		effective_rate *= block_regen_multiplier

	# 4. Regenerate stamina
	var old_val: float = current_stamina
	current_stamina = minf(max_stamina, current_stamina + effective_rate * delta)

	if current_stamina != old_val:
		stamina_changed.emit(current_stamina, max_stamina)
		if old_val <= 0.0 and current_stamina > 0.0:
			stamina_recovered.emit()


func can_afford(amount: float) -> bool:
	return current_stamina >= amount


func consume(amount: float) -> bool:
	if amount <= 0.0:
		return true

	var prev: float = current_stamina
	current_stamina = maxf(0.0, current_stamina - amount)
	regen_delay_timer = regen_delay

	if debug_logging and is_instance_valid(actor):
		print("[%s] Consumed %.1f stamina (%.1f -> %.1f). Regen delayed by %.2fs." % [actor.name, amount, prev, current_stamina, regen_delay])

	stamina_changed.emit(current_stamina, max_stamina)

	if current_stamina <= 0.0 and prev > 0.0:
		stamina_depleted.emit()

	return true


func restore(amount: float) -> void:
	if amount <= 0.0:
		return

	var prev: float = current_stamina
	current_stamina = minf(max_stamina, current_stamina + amount)

	if debug_logging and is_instance_valid(actor):
		print("[%s] Restored %.1f stamina (%.1f -> %.1f)." % [actor.name, amount, prev, current_stamina])

	if current_stamina != prev:
		stamina_changed.emit(current_stamina, max_stamina)
		if prev <= 0.0 and current_stamina > 0.0:
			stamina_recovered.emit()


func trigger_guard_break(attacker: Node3D = null) -> void:
	current_stamina = 0.0
	regen_delay_timer = regen_delay
	stamina_changed.emit(current_stamina, max_stamina)
	stamina_depleted.emit()
	guard_broken.emit(attacker)

	if debug_logging and is_instance_valid(actor):
		var att_name: String = String(attacker.name) if is_instance_valid(attacker) else "Attacker"
		print("[%s] GUARD BROKEN by %s! Stamina reduced to 0, defenses collapsed for %.2fs." % [actor.name, att_name, actor.stats.guard_break_stagger_duration])


func is_exhausted() -> bool:
	return current_stamina <= 0.0
