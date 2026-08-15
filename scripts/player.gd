extends CharacterBody3D


@export var max_speed: = 5.0
@export var accel: = 8.0
@export var lerp_angle_weight_scale: = 10.0

@onready var pawn: Node3D = $pawn
@onready var animation_tree: AnimationTree = $pawn/AnimationTree
@onready var spring_arm_pivot: Node3D = $SpringArmPivot

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var input_dir := Input.get_vector("a", "d", "w", "s")
	var cam_dir := (spring_arm_pivot.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var direction := Vector3(cam_dir.x, 0, cam_dir.z).normalized()
	
	if direction:
		var target_angle := atan2(direction.x, direction.z)
		pawn.rotation.y = lerp_angle(pawn.rotation.y, target_angle, lerp_angle_weight_scale * delta)
		
		var speed : float
		
		if Input.is_action_pressed("shift"):
			speed = max_speed
		else:
			speed = max_speed / 2.0
		
		velocity.x = lerp(velocity.x, direction.x * speed, accel * delta)
		velocity.z = lerp(velocity.z, direction.z * speed, accel * delta)
		
	else:
		velocity.x = lerp(velocity.x, 0.0, accel * delta)
		velocity.z = lerp(velocity.z, 0.0, accel * delta)

	var current_speed := Vector2(velocity.x, velocity.z).length()
	var blend_value := current_speed / max_speed
	animation_tree.set("parameters/blend_position", blend_value)	

	move_and_slide()
