class_name DefenseComponent
extends Node

signal block_started
signal block_ended
signal parry_attempted
signal parry_successful(attacker: Node3D)
signal parry_failed_penalty

enum BlockState {
	NONE,
	PASSIVE_BLOCK,
	ACTIVE_PARRY,
	PARRY_PENALTY
}

@export_group("Block & Parry")
@export var block_damage_reduction: float = 0.85
@export var block_knockback_reduction: float = 0.70
@export var parry_window_duration: float = 0.20
@export var parry_penalty_duration: float = 0.40
@export var parry_thrust_speed: float = 1.8
@export var block_blend_speed: float = 10.0
# Cosine of 70 degrees (~0.342): protects a 140-degree frontal cone
@export var block_angle_threshold: float = 0.34
@export var debug_block_visual: bool = true

var block_state: BlockState = BlockState.NONE
var parry_timer: float = 0.0
var penalty_timer: float = 0.0
var is_block_held: bool = false

var actor: Node3D = null
var debug_indicator: MeshInstance3D = null
var _indicator_mat: StandardMaterial3D = null


func setup(parent_actor: Node3D) -> void:
	actor = parent_actor
	_setup_debug_visual()


func _setup_debug_visual() -> void:
	if not debug_block_visual or not is_instance_valid(actor):
		return

	debug_indicator = actor.get_node_or_null("BlockDebugIndicator") as MeshInstance3D
	if not is_instance_valid(debug_indicator):
		debug_indicator = MeshInstance3D.new()
		debug_indicator.name = "BlockDebugIndicator"
		var sphere := SphereMesh.new()
		sphere.radius = 0.12
		sphere.height = 0.24
		debug_indicator.mesh = sphere
		debug_indicator.position = Vector3(0, 2.15, 0)
		actor.add_child(debug_indicator)

	_indicator_mat = StandardMaterial3D.new()
	_indicator_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_indicator.material_override = _indicator_mat
	debug_indicator.visible = false


func process_defense(delta: float) -> void:
	if block_state == BlockState.ACTIVE_PARRY:
		parry_timer -= delta
		if parry_timer <= 0.0:
			_end_parry_window()
	elif block_state == BlockState.PARRY_PENALTY:
		penalty_timer -= delta
		if penalty_timer <= 0.0:
			_end_parry_penalty()


func is_blocking() -> bool:
	return block_state != BlockState.NONE


func is_passive_blocking() -> bool:
	return block_state == BlockState.PASSIVE_BLOCK


func start_block() -> bool:
	if block_state == BlockState.PARRY_PENALTY:
		is_block_held = true
		return false

	is_block_held = true
	if block_state == BlockState.NONE:
		block_state = BlockState.PASSIVE_BLOCK
		_update_debug_visual()
		block_started.emit()
		return true
	return false


func release_block() -> void:
	is_block_held = false
	if block_state == BlockState.PASSIVE_BLOCK:
		end_block()


func end_block() -> void:
	block_state = BlockState.NONE
	_update_debug_visual()
	block_ended.emit()


func trigger_parry() -> bool:
	if block_state != BlockState.PASSIVE_BLOCK:
		return false

	block_state = BlockState.ACTIVE_PARRY
	parry_timer = parry_window_duration
	_update_debug_visual()
	parry_attempted.emit()

	# Apply micro-thrust forward
	if is_instance_valid(actor) and actor.has_method("apply_parry_thrust"):
		actor.apply_parry_thrust(parry_thrust_speed)

	return true


func _end_parry_window() -> void:
	# Rule 2: Missed deflect activates 0.4s penalty window (spam punishment)
	block_state = BlockState.PARRY_PENALTY
	penalty_timer = parry_penalty_duration
	_update_debug_visual()
	parry_failed_penalty.emit()


func _end_parry_penalty() -> void:
	if is_block_held:
		block_state = BlockState.PASSIVE_BLOCK
		_update_debug_visual()
	else:
		end_block()


func can_block_from(attacker: Node3D) -> bool:
	if not is_instance_valid(attacker) or not is_instance_valid(actor):
		return true

	var to_attacker := (attacker.global_position - actor.global_position)
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.001:
		return true
	var dist := to_attacker.length()
	to_attacker = to_attacker.normalized()

	var facing: Vector3 = Vector3.FORWARD
	if actor.has_method("get_facing_direction"):
		facing = actor.get_facing_direction()
	else:
		facing = actor.global_transform.basis.z
	facing.y = 0.0
	facing = facing.normalized()

	# In close-quarters melee (< 0.6m), if characters are facing each other, allow block
	if dist < 0.6 and attacker.has_method("get_facing_direction"):
		var att_facing: Vector3 = attacker.get_facing_direction()
		att_facing.y = 0.0
		if att_facing.length_squared() > 0.001 and facing.dot(att_facing.normalized()) < 0.0:
			return true

	# Dot product > threshold: attacker is within front arc
	return facing.dot(to_attacker) >= block_angle_threshold


func evaluate_hit(amount: float, knockback: Vector3, attacker: Node3D) -> Dictionary:
	var result := {
		"handled": false,
		"damage_taken": amount,
		"knockback_taken": knockback,
		"was_parried": false,
		"was_blocked": false,
		"was_penalty": false
	}

	# Check frontal angle requirement
	var in_front := can_block_from(attacker)

	# 1. Active Parry Check (Gold Window) - strictly in front
	if block_state == BlockState.ACTIVE_PARRY and in_front:
		result["handled"] = true
		result["damage_taken"] = 0.0
		result["knockback_taken"] = Vector3.ZERO
		result["was_parried"] = true

		if is_instance_valid(attacker):
			if attacker.has_method("stagger"):
				attacker.stagger(0.8, actor)
			elif attacker.has_method("on_attack_deflected"):
				attacker.on_attack_deflected(actor)

		parry_successful.emit(attacker)

		# Successful parry resets parry timer and skips penalty
		parry_timer = 0.0
		if is_block_held:
			block_state = BlockState.PASSIVE_BLOCK
		else:
			block_state = BlockState.NONE
		_update_debug_visual()
		return result

	# 2. Passive Block Check (Blue) - strictly in front
	if block_state == BlockState.PASSIVE_BLOCK and in_front:
		result["handled"] = true
		result["damage_taken"] = amount * (1.0 - block_damage_reduction)
		result["knockback_taken"] = knockback * (1.0 - block_knockback_reduction)
		result["was_blocked"] = true
		return result

	# 3. Penalty Window Warning
	if block_state == BlockState.PARRY_PENALTY:
		result["was_penalty"] = true

	return result


func _update_debug_visual() -> void:
	if not is_instance_valid(debug_indicator) or not debug_block_visual:
		if is_instance_valid(debug_indicator):
			debug_indicator.visible = false
		return

	match block_state:
		BlockState.PASSIVE_BLOCK:
			debug_indicator.visible = true
			_set_indicator_color(Color(0.15, 0.5, 1.0, 1.0)) # Blue
		BlockState.ACTIVE_PARRY:
			debug_indicator.visible = true
			_set_indicator_color(Color(1.0, 0.84, 0.0, 1.0)) # Gold
		BlockState.PARRY_PENALTY:
			debug_indicator.visible = true
			_set_indicator_color(Color(1.0, 0.15, 0.15, 1.0)) # Red
		BlockState.NONE:
			debug_indicator.visible = false


func _set_indicator_color(col: Color) -> void:
	if is_instance_valid(_indicator_mat):
		_indicator_mat.albedo_color = col
