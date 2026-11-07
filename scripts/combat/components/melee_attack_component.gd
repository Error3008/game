class_name MeleeAttackComponent
extends Node

signal attack_started
signal attack_hitbox_opened
signal attack_hitbox_closed
signal attack_finished

enum InsufficientStaminaPolicy {
	SLOW_ATTACK,
	IGNORE
}

## Текущее оружие/режим удара. Выставляется в start_attack() из heavy/light.
@export var weapon_data: WeaponData = null
## Тяжёлый удар (по умолчанию = weapon_data из сцены/кода).
var heavy_weapon_data: WeaponData = null
## Лёгкий удар (быстрый, дешёвый, слабый).
@export var light_weapon_data: WeaponData = null
@export var hitbox_scene: PackedScene = preload("res://scenes/combat/hitbox.tscn")
@export var target_collision_mask: int = 4 # Default scans enemies (layer 4)

@export_group("Stamina")
## Base stamina cost for swinging weapon (overridden by WeaponData.stamina_cost if > 0).
@export var stamina_cost: float = 20.0
## Behavior when current stamina is less than the required attack cost.
@export var insufficient_stamina_policy: InsufficientStaminaPolicy = InsufficientStaminaPolicy.SLOW_ATTACK
## Speed multiplier for exhausted attack (0.5 = 2x slower, for D&D realism).
@export var exhausted_attack_speed: float = 0.5
## Minimum stamina required to initiate an attack (if policy is SLOW_ATTACK).
@export var min_stamina_to_attack: float = 0.0

var is_attacking: bool = false
var is_exhausted_attack: bool = false
var attack_speed_scale: float = 1.0
var attack_time_elapsed: float = 0.0

var actor: Node3D = null
var weapon_hitbox: Hitbox = null


func _ready() -> void:
	if weapon_data == null:
		weapon_data = WeaponData.new()


func setup(parent_actor: Node3D, collision_mask: int = 4) -> void:
	actor = parent_actor
	target_collision_mask = collision_mask
	if heavy_weapon_data == null:
		heavy_weapon_data = weapon_data
	_setup_weapon_hitbox()


func _setup_weapon_hitbox() -> void:
	if not is_instance_valid(actor):
		return

	# Look for an explicit weapon node or find a sword/weapon bone attachment
	var weapon_node := actor.find_child("greatsword", true, false)
	if weapon_node and is_instance_valid(hitbox_scene):
		weapon_hitbox = hitbox_scene.instantiate() as Hitbox
		weapon_hitbox.attacker = actor
		weapon_hitbox.damage = weapon_data.damage
		weapon_hitbox.knockback_force = weapon_data.knockback_force
		weapon_hitbox.collision_mask = target_collision_mask
		weapon_node.add_child(weapon_hitbox)


func start_attack(light: bool = false) -> bool:
	if is_attacking:
		return false

	if light and is_instance_valid(light_weapon_data):
		weapon_data = light_weapon_data
	elif is_instance_valid(heavy_weapon_data):
		weapon_data = heavy_weapon_data

	var cost := weapon_data.stamina_cost if (is_instance_valid(weapon_data) and weapon_data.stamina_cost > 0.0) else stamina_cost
	is_exhausted_attack = false
	attack_speed_scale = 1.0

	if is_instance_valid(actor) and "stamina_component" in actor and is_instance_valid(actor.stamina_component):
		var stam: StaminaComponent = actor.stamina_component
		if stam.can_afford(cost):
			stam.consume(cost)
		else:
			# Not enough stamina for standard attack
			if insufficient_stamina_policy == InsufficientStaminaPolicy.SLOW_ATTACK and stam.current_stamina >= min_stamina_to_attack:
				stam.consume(stam.current_stamina)
				is_exhausted_attack = true
				attack_speed_scale = exhausted_attack_speed
				print("[%s] EXHAUSTED ATTACK! Low stamina, swinging weapon at %.1fx speed!" % [actor.name, attack_speed_scale])
			else:
				print("[%s] Cannot attack! Insufficient stamina (need %.1f, have %.1f)." % [actor.name, cost, stam.current_stamina])
				return false

	is_attacking = true
	attack_time_elapsed = 0.0

	if is_instance_valid(actor) and actor.has_method("play_action"):
		actor.play_action(weapon_data.action_anim_name, attack_speed_scale)

	attack_started.emit()
	return true


func process_attack(delta: float) -> void:
	if not is_attacking:
		return

	var effective_delta := delta * attack_speed_scale
	attack_time_elapsed += effective_delta

	# Phase 1: Windup
	if attack_time_elapsed < weapon_data.windup_time:
		pass

	# Phase 2: Active Swing
	elif attack_time_elapsed < weapon_data.active_end_time:
		if is_instance_valid(weapon_hitbox) and not weapon_hitbox.is_active:
			weapon_hitbox.damage = weapon_data.damage
			weapon_hitbox.knockback_force = weapon_data.knockback_force
			weapon_hitbox.set_active(true)
			attack_hitbox_opened.emit()

		# Forward lunge along actor facing
		if is_instance_valid(actor) and actor.has_method("apply_attack_lunge"):
			actor.apply_attack_lunge(weapon_data.lunge_speed * attack_speed_scale, delta)

	# Phase 3: Recovery
	else:
		if is_instance_valid(weapon_hitbox) and weapon_hitbox.is_active:
			weapon_hitbox.set_active(false)
			attack_hitbox_closed.emit()

	if attack_time_elapsed >= weapon_data.total_duration:
		end_attack()


func cancel_attack() -> void:
	if not is_attacking:
		return
	if is_instance_valid(weapon_hitbox):
		weapon_hitbox.set_active(false)
	is_attacking = false
	is_exhausted_attack = false
	attack_speed_scale = 1.0
	attack_time_elapsed = 0.0
	if is_instance_valid(actor) and is_instance_valid(actor.animation_tree):
		if "parameters/ActionTimeScale/scale" in actor.animation_tree:
			actor.animation_tree.set("parameters/ActionTimeScale/scale", 1.0)
	attack_finished.emit()


func end_attack() -> void:
	cancel_attack()


func is_in_recovery() -> bool:
	return is_attacking and attack_time_elapsed >= weapon_data.active_end_time


func is_in_threat_phase() -> bool:
	return is_attacking and attack_time_elapsed <= weapon_data.active_end_time
