class_name Enemy
extends CombatCharacter3D

@onready var ai_controller: EnemyAIController = get_node_or_null("EnemyAIController")

enum Team {
	HOSTILE, ## обычный враг: слой 4, бьёт по игроку (слой 2)
	ALLY,    ## бот на стороне игрока (дуэли ботов): слой 2, группа "ally", бьёт по врагам (слой 4)
}

@export var team: Team = Team.HOSTILE

## Характер ИИ этого врага (передаётся контроллеру в _ready). null = базовые параметры контроллера.
@export var personality: AIPersonality = null

var _is_dummy: bool = false
var _dummy_can_attack: bool = false
var _dummy_always_block: bool = false
var _can_dodge: bool = true
var _dodge_chance: float = 0.50
var _reaction_time_min: float = 0.10
var _reaction_time_max: float = 0.22
var _can_block: bool = true
var _block_chance: float = 0.50
var _parry_chance: float = 0.25
var _tactical_block_chance: float = 0.35
var _can_kick: bool = true
var _kick_chance_on_blocking_player: float = 0.70

@export_group("Dummy Training")
@export var is_dummy: bool = false:
	get:
		return ai_controller.is_dummy if is_instance_valid(ai_controller) else _is_dummy
	set(val):
		_is_dummy = val
		if is_instance_valid(ai_controller):
			ai_controller.is_dummy = val

@export var dummy_can_attack: bool = false:
	get:
		return ai_controller.dummy_can_attack if is_instance_valid(ai_controller) else _dummy_can_attack
	set(val):
		_dummy_can_attack = val
		if is_instance_valid(ai_controller):
			ai_controller.dummy_can_attack = val

@export var dummy_always_block: bool = false:
	get:
		return ai_controller.dummy_always_block if is_instance_valid(ai_controller) else _dummy_always_block
	set(val):
		_dummy_always_block = val
		if is_instance_valid(ai_controller):
			ai_controller.dummy_always_block = val

@export_group("Combat Dodge")
@export var can_dodge: bool = true:
	get:
		return ai_controller.can_dodge if is_instance_valid(ai_controller) else _can_dodge
	set(val):
		_can_dodge = val
		if is_instance_valid(ai_controller):
			ai_controller.can_dodge = val

@export_range(0.0, 1.0, 0.05) var dodge_chance: float = 0.50:
	get:
		return ai_controller.dodge_chance if is_instance_valid(ai_controller) else _dodge_chance
	set(val):
		_dodge_chance = val
		if is_instance_valid(ai_controller):
			ai_controller.dodge_chance = val

@export_range(0.0, 1.0, 0.02) var reaction_time_min: float = 0.10:
	get:
		return ai_controller.reaction_time_min if is_instance_valid(ai_controller) else _reaction_time_min
	set(val):
		_reaction_time_min = val
		if is_instance_valid(ai_controller):
			ai_controller.reaction_time_min = val

@export_range(0.0, 1.0, 0.02) var reaction_time_max: float = 0.22:
	get:
		return ai_controller.reaction_time_max if is_instance_valid(ai_controller) else _reaction_time_max
	set(val):
		_reaction_time_max = val
		if is_instance_valid(ai_controller):
			ai_controller.reaction_time_max = val

@export_group("Combat Defense")
@export var can_block: bool = true:
	get:
		return ai_controller.can_block if is_instance_valid(ai_controller) else _can_block
	set(val):
		_can_block = val
		if is_instance_valid(ai_controller):
			ai_controller.can_block = val

@export_range(0.0, 1.0, 0.05) var block_chance: float = 0.50:
	get:
		return ai_controller.block_chance if is_instance_valid(ai_controller) else _block_chance
	set(val):
		_block_chance = val
		if is_instance_valid(ai_controller):
			ai_controller.block_chance = val

@export_range(0.0, 1.0, 0.05) var parry_chance: float = 0.25:
	get:
		return ai_controller.parry_chance if is_instance_valid(ai_controller) else _parry_chance
	set(val):
		_parry_chance = val
		if is_instance_valid(ai_controller):
			ai_controller.parry_chance = val

@export_range(0.0, 1.0, 0.05) var tactical_block_chance: float = 0.35:
	get:
		return ai_controller.tactical_block_chance if is_instance_valid(ai_controller) else _tactical_block_chance
	set(val):
		_tactical_block_chance = val
		if is_instance_valid(ai_controller):
			ai_controller.tactical_block_chance = val

@export_group("Combat Kick")
@export var can_kick: bool = true:
	get:
		return ai_controller.can_kick if is_instance_valid(ai_controller) else _can_kick
	set(val):
		_can_kick = val
		if is_instance_valid(ai_controller):
			ai_controller.can_kick = val

@export_range(0.0, 1.0, 0.05) var kick_chance_on_blocking_player: float = 0.70:
	get:
		return ai_controller.kick_chance_on_blocking_player if is_instance_valid(ai_controller) else _kick_chance_on_blocking_player
	set(val):
		_kick_chance_on_blocking_player = val
		if is_instance_valid(ai_controller):
			ai_controller.kick_chance_on_blocking_player = val

# Duck-typing access to player target
var player: Node3D:
	get:
		return ai_controller.target if is_instance_valid(ai_controller) else null
	set(val):
		if is_instance_valid(ai_controller):
			ai_controller.target = val


func _ready() -> void:
	if team == Team.ALLY:
		hitbox_target_mask = LAYER_ENEMY_SIDE
		collision_layer = LAYER_PLAYER_SIDE
		collision_mask = LAYER_WORLD | LAYER_ENEMY_SIDE
		remove_from_group("enemy")
		add_to_group("ally")
		var detection := get_node_or_null("DetectionArea") as Area3D
		if is_instance_valid(detection):
			detection.collision_mask = LAYER_ENEMY_SIDE
	else:
		hitbox_target_mask = LAYER_PLAYER_SIDE

	if stats == null:
		stats = preload("res://resources/stats/enemy_stats.tres")

	# Ensure components exist
	if not has_node("DefenseComponent"):
		var def := DefenseComponent.new()
		def.name = "DefenseComponent"
		add_child(def)
	if not has_node("MeleeAttackComponent"):
		var atk := MeleeAttackComponent.new()
		atk.name = "MeleeAttackComponent"
		atk.weapon_data = preload("res://resources/weapons/enemy_sword.tres")
		atk.light_weapon_data = preload("res://resources/weapons/enemy_sword_light.tres")
		add_child(atk)
	if not has_node("DashComponent"):
		var dsh := DashComponent.new()
		dsh.name = "DashComponent"
		add_child(dsh)
	if not has_node("StaminaComponent"):
		var stam: StaminaComponent = StaminaComponent.new()
		stam.name = "StaminaComponent"
		add_child(stam)
	if not has_node("KickComponent"):
		var kick := KickComponent.new()
		kick.name = "KickComponent"
		add_child(kick)
	if not has_node("EnemyAIController"):
		var ctrl := EnemyAIController.new()
		ctrl.name = "EnemyAIController"
		add_child(ctrl)

	super._ready()

	ai_controller = get_node_or_null("EnemyAIController") as EnemyAIController
	if is_instance_valid(ai_controller):
		ai_controller.personality = personality
		if team == Team.ALLY:
			ai_controller.target_groups = [&"enemy"]
		ai_controller.is_dummy = _is_dummy
		ai_controller.dummy_can_attack = _dummy_can_attack
		ai_controller.dummy_always_block = _dummy_always_block
		ai_controller.can_dodge = _can_dodge
		ai_controller.dodge_chance = _dodge_chance
		ai_controller.reaction_time_min = _reaction_time_min
		ai_controller.reaction_time_max = _reaction_time_max
		ai_controller.can_block = _can_block
		ai_controller.block_chance = _block_chance
		ai_controller.parry_chance = _parry_chance
		ai_controller.tactical_block_chance = _tactical_block_chance
		ai_controller.can_kick = _can_kick
		ai_controller.kick_chance_on_blocking_player = _kick_chance_on_blocking_player
