class_name KickComponent
extends Node

## Modular combat component for executing an unblockable guard-breaking kick.
## If target is holding block or parrying: triggers GUARD BREAK (1.5s stun + defenses collapsed).
## If target released block in time: inflicts only minor damage without severe stun.

signal kick_started
signal kick_hit_landed(target: Node3D, broke_guard: bool)
signal kick_finished

@export_group("Timings")
@export var windup_time: float = 0.33
@export var active_end_time: float = 0.55
@export var total_duration: float = 0.90

@export_group("Reach & Physics")
@export var kick_reach: float = 1.85
@export var kick_radius: float = 0.50
@export var lunge_speed: float = 1.4

@export_group("Stamina")
@export var stamina_cost: float = 20.0

@export_group("Impact & Damage")
@export var guard_break_damage: float = 10.0
@export var guard_break_knockback: float = 4.0
@export var guard_break_stagger_duration: float = 1.5
@export var guard_break_stamina_drain: float = 50.0
@export var unblocked_damage: float = 10.0
@export var unblocked_knockback: float = 2.0

var is_kicking: bool = false
var kick_time_elapsed: float = 0.0
var has_hit_target: bool = false

var actor: CombatCharacter3D = null
var target_collision_mask: int = 4 # 4 for player scanning enemy, 2 for enemy scanning player


func setup(parent_actor: Node3D, collision_mask: int = 4) -> void:
	actor = parent_actor as CombatCharacter3D
	target_collision_mask = collision_mask


func start_kick() -> bool:
	if is_kicking:
		return false

	if is_instance_valid(actor) and "stamina_component" in actor and is_instance_valid(actor.stamina_component):
		var stam: StaminaComponent = actor.stamina_component
		if not stam.can_afford(stamina_cost):
			print("[%s] Cannot kick! Insufficient stamina (need %.1f, have %.1f)." % [actor.name, stamina_cost, stam.current_stamina])
			return false
		stam.consume(stamina_cost)

	is_kicking = true
	kick_time_elapsed = 0.0
	has_hit_target = false

	if is_instance_valid(actor) and actor.has_method("play_action"):
		actor.play_action(&"kick", 1.0)

	kick_started.emit()
	return true


func process_kick(delta: float) -> void:
	if not is_kicking:
		return

	kick_time_elapsed += delta

	# Phase 1: Windup (raise knee)
	if kick_time_elapsed < windup_time:
		if is_instance_valid(actor) and is_instance_valid(actor.current_target):
			actor.cmd_face_point(actor.current_target.global_position, delta, 1.5)

	# Phase 2: Active thrust
	elif kick_time_elapsed < active_end_time:
		# Kinetic forward lunge
		if is_instance_valid(actor) and actor.has_method("apply_attack_lunge"):
			actor.apply_attack_lunge(lunge_speed, delta)

		# Hit check
		if not has_hit_target:
			_check_kick_hit()

	# Phase 3: Recovery
	else:
		pass

	if kick_time_elapsed >= total_duration:
		end_kick()


func _check_kick_hit() -> void:
	if not is_instance_valid(actor):
		return

	# 1. Direct evaluation against current_target for 100% responsiveness
	if is_instance_valid(actor.current_target) and actor.current_target.is_inside_tree():
		var target_body := actor.current_target
		var to_target := (target_body.global_position - actor.global_position)
		to_target.y = 0.0
		var dist := to_target.length()
		var forward := actor.get_forward_basis() if actor.has_method("get_forward_basis") else actor.global_transform.basis.z
		forward.y = 0.0

		if dist <= (kick_reach + 0.35) and dist > 0.001:
			var dot := to_target.normalized().dot(forward.normalized())
			if dot >= 0.25:
				has_hit_target = true
				_apply_kick_impact(target_body)
				return

	# 2. Spatial physics shape query for any candidate in front of actor
	var space_state := actor.get_world_3d().direct_space_state
	if is_instance_valid(space_state):
		var shape := SphereShape3D.new()
		shape.radius = kick_radius
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		var forward := actor.get_forward_basis() if actor.has_method("get_forward_basis") else actor.global_transform.basis.z
		forward.y = 0.0
		query.transform = Transform3D(Basis(), actor.global_position + forward.normalized() * kick_reach + Vector3(0.0, 0.85, 0.0))
		query.collision_mask = target_collision_mask
		query.exclude = [actor.get_rid()]

		var results := space_state.intersect_shape(query, 4)
		for hit in results:
			var collider = hit.get("collider")
			if is_instance_valid(collider) and collider != actor and collider.has_method("take_damage"):
				has_hit_target = true
				_apply_kick_impact(collider as Node3D)
				return


func _apply_kick_impact(target_node: Node3D) -> void:
	if not is_instance_valid(target_node) or not is_instance_valid(actor):
		return

	if target_node.has_method("is_alive") and not target_node.is_alive():
		return

	# I-frame check (dash dodge)
	if "is_dashing" in target_node and target_node.is_dashing:
		if "dash_component" in target_node and is_instance_valid(target_node.dash_component):
			if target_node.dash_component.is_in_iframe():
				print("[%s] Kick dodged by %s via dash i-frame!" % [actor.name, target_node.name])
				return

	# Direction for knockback
	var knockback_dir := (target_node.global_position - actor.global_position)
	knockback_dir.y = 0.0
	if knockback_dir.length_squared() > 0.001:
		knockback_dir = knockback_dir.normalized()
	else:
		knockback_dir = actor.get_forward_basis()

	# Check if target is blocking (holding RMB or parrying)
	var is_target_blocking: bool = false
	if target_node.has_method("is_blocking"):
		is_target_blocking = target_node.is_blocking()
	elif "defense_component" in target_node and is_instance_valid(target_node.defense_component):
		is_target_blocking = target_node.defense_component.is_blocking()

	if is_target_blocking:
		# === GUARD BREAK ===
		print("[%s] KICK BROKE GUARD OF %s! Defenses collapsed." % [actor.name, target_node.name])

		# 1. Force end block immediately
		if "defense_component" in target_node and is_instance_valid(target_node.defense_component):
			target_node.defense_component.end_block()
			target_node.defense_component.guard_broken.emit(actor)

		# 2. Drain stamina
		if "stamina_component" in target_node and is_instance_valid(target_node.stamina_component):
			target_node.stamina_component.consume(guard_break_stamina_drain)
			target_node.stamina_component.trigger_guard_break(actor)

		# 3. Apply damage and knockback
		if target_node.has_method("take_damage"):
			target_node.take_damage(guard_break_damage, knockback_dir * guard_break_knockback, actor)

		# 4. Apply heavy guard break stagger (1.5s stun)
		if target_node.has_method("stagger"):
			target_node.stagger(guard_break_stagger_duration, actor)

		kick_hit_landed.emit(target_node, true)
	else:
		# === SAFE UNBLOCKED IMPACT ===
		# Target released RMB in time or was not in guard: no guard break, no 1.5s stun!
		print("[%s] Kick struck %s (target was NOT blocking - no guard break)." % [actor.name, target_node.name])

		if target_node.has_method("take_damage"):
			target_node.take_damage(unblocked_damage, knockback_dir * unblocked_knockback, actor)

		kick_hit_landed.emit(target_node, false)


func cancel_kick() -> void:
	if not is_kicking:
		return
	is_kicking = false
	kick_time_elapsed = 0.0
	has_hit_target = false
	kick_finished.emit()


func end_kick() -> void:
	cancel_kick()


func is_in_recovery() -> bool:
	return is_kicking and kick_time_elapsed >= active_end_time
