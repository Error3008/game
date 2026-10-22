class_name MeleeAttackComponent
extends Node

signal attack_started
signal attack_hitbox_opened
signal attack_hitbox_closed
signal attack_finished

@export var weapon_data: WeaponData = null
@export var hitbox_scene: PackedScene = preload("res://scenes/combat/hitbox.tscn")
@export var target_collision_mask: int = 4 # Default scans enemies (layer 4)

var is_attacking: bool = false
var attack_time_elapsed: float = 0.0

var actor: Node3D = null
var weapon_hitbox: Hitbox = null


func _ready() -> void:
	if weapon_data == null:
		weapon_data = WeaponData.new()


func setup(parent_actor: Node3D, collision_mask: int = 4) -> void:
	actor = parent_actor
	target_collision_mask = collision_mask
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


func start_attack() -> bool:
	if is_attacking:
		return false

	is_attacking = true
	attack_time_elapsed = 0.0

	if is_instance_valid(actor) and actor.has_method("play_action"):
		actor.play_action(weapon_data.action_anim_name)

	attack_started.emit()
	return true


func process_attack(delta: float) -> void:
	if not is_attacking:
		return

	attack_time_elapsed += delta

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
			actor.apply_attack_lunge(weapon_data.lunge_speed, delta)

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
	attack_time_elapsed = 0.0
	attack_finished.emit()


func end_attack() -> void:
	cancel_attack()


func is_in_recovery() -> bool:
	return is_attacking and attack_time_elapsed >= weapon_data.active_end_time


func is_in_threat_phase() -> bool:
	return is_attacking and attack_time_elapsed <= weapon_data.active_end_time
