class_name PlayerController
extends Node

@export_group("Target Lock")
@export var auto_lock_distance: float = 9.0
@export var max_lock_distance: float = 16.0
@export var break_lock_on_sprint: bool = true

var actor: CombatCharacter3D = null
var spring_arm_pivot: Node3D = null
var is_lock_enabled: bool = false


func _ready() -> void:
	actor = get_parent() as CombatCharacter3D
	if not is_instance_valid(actor):
		push_error("[PlayerController] Parent node must be a CombatCharacter3D!")
		return

	spring_arm_pivot = actor.get_node_or_null("SpringArmPivot") as Node3D
	actor.character_died.connect(_on_actor_died)


func _on_actor_died(_attacker: Node3D) -> void:
	is_lock_enabled = false
	_clear_target()


func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(actor) or not actor.is_alive():
		return

	if event.is_action_pressed("lock_target"):
		is_lock_enabled = not is_lock_enabled
		if is_lock_enabled:
			_find_best_target()
		else:
			_clear_target()

	# Attack input (strictly in combat mode with target)
	if event.is_action_pressed("attack"):
		if not is_instance_valid(actor.current_target):
			return
		if actor.is_blocking():
			actor.cmd_parry()
		elif not actor.is_attacking and not actor.is_dashing:
			actor.cmd_attack()

	# Block input (strictly in combat mode with target)
	if event.is_action_pressed("block"):
		if is_instance_valid(actor.current_target):
			actor.cmd_block_start()

	if event.is_action_released("block"):
		actor.cmd_block_release()

	# Dash input (strictly in combat mode with target, and NOT while holding block)
	if event.is_action_pressed("dash"):
		if is_instance_valid(actor.current_target):
			if actor.is_blocking() or Input.is_action_pressed("block"):
				return
			_trigger_directional_dash()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(actor) or not actor.is_alive():
		return

	_update_target_lock()

	# Continuous block hold sync
	if Input.is_action_pressed("block") and is_instance_valid(actor.current_target):
		if not actor.is_blocking() and not actor.is_attacking and not actor.is_dashing:
			actor.cmd_block_start()
	elif not Input.is_action_pressed("block"):
		if actor.is_blocking() and actor.defense_component and actor.defense_component.is_passive_blocking():
			actor.cmd_block_release()

	# Process locomotion input
	if actor.is_blocking() or actor.is_attacking or actor.is_dashing or actor.is_staggered:
		return

	var input_dir := Input.get_vector("a", "d", "w", "s")

	if is_instance_valid(actor.current_target):
		var forward_step := -input_dir.y
		var lateral_step := input_dir.x
		actor.cmd_combat_move(lateral_step, forward_step)
	else:
		var cam_basis := spring_arm_pivot.global_transform.basis if is_instance_valid(spring_arm_pivot) else actor.global_transform.basis
		var cam_dir := (cam_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
		var world_dir := Vector3(cam_dir.x, 0.0, cam_dir.z).normalized()
		var is_running := Input.is_action_pressed("shift")
		actor.cmd_move(world_dir, is_running)


func _trigger_directional_dash() -> void:
	var input_dir := Input.get_vector("a", "d", "w", "s")
	var forward_step := -input_dir.y
	var lateral_step := input_dir.x

	var chosen_dir: DashComponent.DashDirection = DashComponent.DashDirection.BACKWARD

	if input_dir.length_squared() < 0.05:
		chosen_dir = DashComponent.DashDirection.BACKWARD
	else:
		if absf(forward_step) >= absf(lateral_step):
			chosen_dir = DashComponent.DashDirection.FORWARD if forward_step > 0.0 else DashComponent.DashDirection.BACKWARD
		else:
			chosen_dir = DashComponent.DashDirection.RIGHT if lateral_step > 0.0 else DashComponent.DashDirection.LEFT

	actor.cmd_dash(chosen_dir)


# --- Target Lock System ---

func _update_target_lock() -> void:
	if break_lock_on_sprint and Input.is_action_pressed("shift"):
		if is_lock_enabled or is_instance_valid(actor.current_target):
			is_lock_enabled = false
			_clear_target()
		return

	if not is_lock_enabled:
		if is_instance_valid(actor.current_target):
			_clear_target()
		return

	if is_instance_valid(actor.current_target):
		# Verify target is still valid and alive
		var target := actor.current_target
		if not target.is_inside_tree() or (target.has_method("is_alive") and not target.is_alive()):
			_clear_target()
			return

		var dist := actor.global_position.distance_to(target.global_position)
		if dist > max_lock_distance:
			is_lock_enabled = false
			_clear_target()
	else:
		_check_auto_lock()


func _check_auto_lock() -> void:
	if not is_inside_tree():
		return
	var enemies := get_tree().get_nodes_in_group("enemy")
	var closest_enemy: Node3D = null
	var closest_dist := auto_lock_distance

	for enemy in enemies:
		if enemy is Node3D and is_instance_valid(enemy) and enemy != actor and enemy.is_inside_tree():
			if enemy.has_method("is_alive") and not enemy.is_alive():
				continue
			var dist := actor.global_position.distance_to(enemy.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_enemy = enemy

	if closest_enemy != null:
		_set_target(closest_enemy)


func _find_best_target() -> void:
	if not is_inside_tree():
		return
	var enemies := get_tree().get_nodes_in_group("enemy")
	var best_enemy: Node3D = null
	var min_dist := max_lock_distance

	for enemy in enemies:
		if enemy is Node3D and is_instance_valid(enemy) and enemy != actor and enemy.is_inside_tree():
			if enemy.has_method("is_alive") and not enemy.is_alive():
				continue
			var dist := actor.global_position.distance_to(enemy.global_position)
			if dist < min_dist:
				min_dist = dist
				best_enemy = enemy

	if best_enemy != null:
		_set_target(best_enemy)


func _set_target(target: Node3D) -> void:
	actor.cmd_set_target(target)
	if is_instance_valid(spring_arm_pivot) and "lock_target" in spring_arm_pivot:
		spring_arm_pivot.lock_target = target


func _clear_target() -> void:
	actor.cmd_clear_target()
	if is_instance_valid(spring_arm_pivot) and "lock_target" in spring_arm_pivot:
		spring_arm_pivot.lock_target = null
