extends Camera3D

@export var spring_arm: Node3D
@export var lerp_power: float = 8.0

func _process(delta: float) -> void:
	if not is_instance_valid(spring_arm):
		return
	position = lerp(position, spring_arm.position, delta * lerp_power)
