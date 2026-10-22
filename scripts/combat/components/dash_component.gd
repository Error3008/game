class_name DashComponent
extends Node

signal dash_started(direction: DashDirection)
signal dash_finished

enum DashDirection {
	FORWARD,
	BACKWARD,
	LEFT,
	RIGHT
}

const DASH_ANIM_MAP: Dictionary = {
	DashDirection.FORWARD: &"dash_fwd",
	DashDirection.BACKWARD: &"dash_bwd",
	DashDirection.LEFT: &"dash_left",
	DashDirection.RIGHT: &"dash_right",
}

@export_group("Combat Dash")
@export var dash_speed: float = 8.5
@export var dash_duration: float = 0.42
@export var dash_cooldown: float = 0.55
@export var dash_iframe_start: float = 0.04
@export var dash_iframe_end: float = 0.32

var is_dashing: bool = false
var dash_time_elapsed: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_move_direction: Vector3 = Vector3.ZERO

var actor: Node3D = null


func setup(parent_actor: Node3D) -> void:
	actor = parent_actor


func update(delta: float) -> void:
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer = maxf(0.0, dash_cooldown_timer - delta)

	if not is_dashing:
		return

	dash_time_elapsed += delta

	# Physical movement: smoothly decelerate toward combat walk speed
	if dash_time_elapsed < dash_duration:
		var progress := clampf(dash_time_elapsed / dash_duration, 0.0, 1.0)
		var target_speed := lerpf(dash_speed, 2.4, progress)
		if is_instance_valid(actor) and actor.has_method("apply_dash_velocity"):
			actor.apply_dash_velocity(dash_move_direction, target_speed, delta)
	else:
		end_dash()


func process_dash(delta: float) -> void:
	update(delta)


func can_dash() -> bool:
	return not is_dashing and dash_cooldown_timer <= 0.0


func start_dash(chosen_dir: DashDirection) -> bool:
	if not can_dash():
		return false

	is_dashing = true
	dash_time_elapsed = 0.0
	dash_cooldown_timer = dash_cooldown

	var forward_basis := Vector3.FORWARD
	var right_basis := Vector3.RIGHT
	if is_instance_valid(actor):
		if actor.has_method("get_forward_basis"):
			forward_basis = actor.get_forward_basis()
		if actor.has_method("get_right_basis"):
			right_basis = actor.get_right_basis()

	match chosen_dir:
		DashDirection.FORWARD:
			dash_move_direction = forward_basis
		DashDirection.BACKWARD:
			dash_move_direction = -forward_basis
		DashDirection.LEFT:
			dash_move_direction = -right_basis
		DashDirection.RIGHT:
			dash_move_direction = right_basis

	var anim_name: StringName = DASH_ANIM_MAP.get(chosen_dir, &"dash_bwd")
	if is_instance_valid(actor) and actor.has_method("play_action"):
		actor.play_action(anim_name)

	# Apply initial kinetic impulse
	if is_instance_valid(actor) and actor.has_method("set_dash_initial_velocity"):
		actor.set_dash_initial_velocity(dash_move_direction * dash_speed)

	dash_started.emit(chosen_dir)
	return true


func end_dash() -> void:
	if not is_dashing:
		return
	is_dashing = false
	dash_finished.emit()


func is_in_iframe() -> bool:
	return is_dashing and dash_time_elapsed >= dash_iframe_start and dash_time_elapsed <= dash_iframe_end
