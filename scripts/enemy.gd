class_name Enemy
extends CombatCharacter3D

@onready var ai_controller: EnemyAIController = get_node_or_null("EnemyAIController")

var _is_dummy: bool = false
var _dummy_can_attack: bool = false
var _can_dodge: bool = true
var _dodge_chance: float = 0.50
var _reaction_time_min: float = 0.10
var _reaction_time_max: float = 0.22

@export_group("Dummy / Training")
@export var is_dummy: bool:
	get:
		return ai_controller.is_dummy if is_instance_valid(ai_controller) else _is_dummy
	set(val):
		_is_dummy = val
		if is_instance_valid(ai_controller):
			ai_controller.is_dummy = val

@export var dummy_can_attack: bool:
	get:
		return ai_controller.dummy_can_attack if is_instance_valid(ai_controller) else _dummy_can_attack
	set(val):
		_dummy_can_attack = val
		if is_instance_valid(ai_controller):
			ai_controller.dummy_can_attack = val

@export_group("Combat Dodge / Reactions")
@export var can_dodge: bool:
	get:
		return ai_controller.can_dodge if is_instance_valid(ai_controller) else _can_dodge
	set(val):
		_can_dodge = val
		if is_instance_valid(ai_controller):
			ai_controller.can_dodge = val

@export var dodge_chance: float:
	get:
		return ai_controller.dodge_chance if is_instance_valid(ai_controller) else _dodge_chance
	set(val):
		_dodge_chance = val
		if is_instance_valid(ai_controller):
			ai_controller.dodge_chance = val

@export var reaction_time_min: float:
	get:
		return ai_controller.reaction_time_min if is_instance_valid(ai_controller) else _reaction_time_min
	set(val):
		_reaction_time_min = val
		if is_instance_valid(ai_controller):
			ai_controller.reaction_time_min = val

@export var reaction_time_max: float:
	get:
		return ai_controller.reaction_time_max if is_instance_valid(ai_controller) else _reaction_time_max
	set(val):
		_reaction_time_max = val
		if is_instance_valid(ai_controller):
			ai_controller.reaction_time_max = val

# Duck-typing access to player target
var player: Node3D:
	get:
		return ai_controller.target if is_instance_valid(ai_controller) else null
	set(val):
		if is_instance_valid(ai_controller):
			ai_controller.target = val


func _ready() -> void:
	hitbox_target_mask = 2 # Scans player (collision layer 2)

	if stats == null:
		stats = preload("res://resources/stats/enemy_stats.tres")

	# Ensure components exist
	if not has_node("MeleeAttackComponent"):
		var atk := MeleeAttackComponent.new()
		atk.name = "MeleeAttackComponent"
		atk.weapon_data = preload("res://resources/weapons/enemy_sword.tres")
		add_child(atk)
	if not has_node("DashComponent"):
		var dsh := DashComponent.new()
		dsh.name = "DashComponent"
		add_child(dsh)
	if not has_node("EnemyAIController"):
		var ctrl := EnemyAIController.new()
		ctrl.name = "EnemyAIController"
		add_child(ctrl)

	super._ready()

	ai_controller = get_node_or_null("EnemyAIController") as EnemyAIController
	if is_instance_valid(ai_controller):
		ai_controller.is_dummy = _is_dummy
		ai_controller.dummy_can_attack = _dummy_can_attack
		ai_controller.can_dodge = _can_dodge
		ai_controller.dodge_chance = _dodge_chance
		ai_controller.reaction_time_min = _reaction_time_min
		ai_controller.reaction_time_max = _reaction_time_max
