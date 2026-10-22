class_name HealthComponent
extends Node

signal health_changed(current: float, max_health: float)
signal damaged(amount: float, attacker: Node3D)
signal healed(amount: float)
signal died(attacker: Node3D)

@export var max_health: float = 100.0
var current_health: float = 100.0
var is_dead: bool = false


func _ready() -> void:
	current_health = max_health


func init_health(new_max: float) -> void:
	max_health = new_max
	current_health = new_max
	is_dead = false
	health_changed.emit(current_health, max_health)


func take_damage(amount: float, attacker: Node3D = null) -> float:
	if is_dead:
		return 0.0

	var damage_applied := minf(amount, current_health)
	current_health -= damage_applied
	health_changed.emit(current_health, max_health)
	damaged.emit(damage_applied, attacker)

	if current_health <= 0.0:
		die(attacker)

	return damage_applied


func heal(amount: float) -> void:
	if is_dead:
		return
	current_health = minf(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)
	healed.emit(amount)


func die(attacker: Node3D = null) -> void:
	if is_dead:
		return
	is_dead = true
	current_health = 0.0
	died.emit(attacker)
