@tool
extends Node3D

var degree_step : float = 0

@export var sky_material: ProceduralSkyMaterial
@export var top_gradient: Gradient
@export var horizon_gradient: Gradient
@export var curve_transition: Curve

@export var start_change_sky_color: bool = false

@export var start_time_change : bool = false
@export var time_of_day_in_minutes : int = 24:
	set(value):
		degree_step = 0
		time_of_day_in_minutes = value
@export var reset_time : bool = false:
	set(value):
		if(value):
			rotation_degrees = Vector3(0, 0, 0)
		reset_time = false

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	if (start_time_change == true):
		if (degree_step == 0):
			degree_step = 360.0 / (time_of_day_in_minutes * 60.0)
		rotation_degrees.x -= degree_step * delta
		if (rotation_degrees.x <= -360):
			rotation_degrees.x += 360
			
	if sky_material != null and start_change_sky_color == true:
		var time_normalized = wrapf((abs(rotation_degrees.x) / 360.0) + 0.25, 0.0, 1.0)
		
		if top_gradient != null:
			sky_material.sky_top_color = top_gradient.sample(time_normalized)
		if horizon_gradient != null:
			sky_material.sky_horizon_color = horizon_gradient.sample(time_normalized)
			sky_material.ground_horizon_color = horizon_gradient.sample(time_normalized)
		if curve_transition != null:
			sky_material.sky_curve = curve_transition.sample(time_normalized)
