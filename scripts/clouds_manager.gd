@tool
extends Node3D

const CLOUD = preload("uid://bk1conydogbu4")
@onready var lines_container: Node3D = $LinesContainer
@onready var clouds_container: Node3D = $CloudsContainer


@export_group("Actions")
@export var spawn_cloud: bool = false:
	set(value):
		if value:
			spawn_cloud_func()
		spawn_cloud = false

@export var create_lines: bool = false:
	set(value):
		if value:
			create_cloud_lines()
		create_lines = false

@export var show_lines: bool = false:
	set(value):
		show_lines = value
		show_cloud_lines()
		
@export var spawn_random: bool = false
@export var move: bool = false

@export_group("Layout Settings")
@export var start_position : Vector3 = Vector3(0.0, 100.0, 0.0)
@export var lines_length : float = 100.0
@export var lines_count : int = 3
@export var distance_between_lines : float = 20.0
@export var second_layer : bool = false
@export var wind : Vector2 = Vector2(1.0, 0.0)
@export var max_line_speed : float = 15
@export var min_line_speed : float = 5
@export var spawn_interval: float = 5.0
@export var spawn_probability: float = 0.5

var spawn_timer: float = 0.0

@export_group("Cloud Structure")

@export var cloud_scale: float = 1.0
@export var overlap: float = 0.8
@export var num_of_neighbours: int = 2
@export var n_step: float = 2
@export var life_time: float = 20.0

@export_group("Direction Settings")
@export var direction_spread := Vector3(1.0, 1.0, 1.0)


func get_spread() -> Vector3:
	return Vector3(
		randf_range(-direction_spread.x, direction_spread.x),
		randf_range(-direction_spread.y, direction_spread.y),
		randf_range(-direction_spread.z, direction_spread.z)
	).normalized()

const SAVE_PATH = "res://saves/lines.cfg"

var lines : Array[Dictionary] = []
var last_line : int = -1

class CloudInstance:
	var node: GPUParticles3D
	var speed: float
	var end_pos: Vector3

	func _init(_node: GPUParticles3D, _speed: float, _end_pos: Vector3):
		node = _node
		speed = _speed
		end_pos = _end_pos
var active_clouds: Array[CloudInstance] = []

func save_data() -> void:
	var config = ConfigFile.new()
	
	config.set_value("PlayerData", "lines", lines)
	
	var error = config.save(SAVE_PATH)
	if error != OK:
		print("ERROR: Save cloud lines data failed")

func load_data() -> Array:
	var config = ConfigFile.new()
	var error = config.load(SAVE_PATH)
	
	if error == OK:
		lines = config.get_value("PlayerData", "lines", [])
	else:
		lines = []
		print("Warning: Could not load cloud lines data")
	
	return lines	

func show_cloud_lines():
	if show_lines:
		var box_mesh := BoxMesh.new()
		
		lines = load_data()
		for target in lines:
			var line := MeshInstance3D.new()
			lines_container.add_child(line)
			
			line.mesh = box_mesh
			line.position = target["position"]
			line.rotation.y = -wind.angle()
			line.scale = Vector3(lines_length, 1.0, 1.0)
	else:
		for child in lines_container.get_children():
			child.queue_free()

func create_cloud_lines() -> void:
	var side := 1
	var distance := 0.0
	var perp := Vector3(-wind.y, 0, wind.x)
	var j := 0
	
	lines.clear()
	for i in range(lines_count):
		var target := start_position + perp.normalized() * distance * side
		var line_speed := randf_range(min_line_speed, max_line_speed)
		lines.append({"id": i, "position": target, "speed": line_speed})
		
		if second_layer and distance != 0:
			target = start_position + perp.normalized() * (distance - distance_between_lines / 2) * side
			target.y += 0.866 * distance_between_lines
			line_speed = randf_range(min_line_speed, max_line_speed)
			lines.append({"id": lines_count + j, "position": target, "speed": line_speed})
			j += 1
			
		if side == 1:
			distance += distance_between_lines
		side *= -1
		
	save_data()
	
func check_clouds_pos(cloud_name : String, new_pos : Vector3, new_R : float) -> bool:
	var cloud_node := get_node("CloudsContainer/%s" % cloud_name)
	for child in cloud_node.get_children():
		var pos : Vector3 = child.global_position
		var R : float = child.process_material.emission_sphere_radius
		var S : float = child.scale.x
		var distance : float = pos.distance_to(new_pos)
		
		if distance < (new_R + (R * S)) * overlap:
			return false
	return true

func generate_points(cloud_name : String, points : Array[Vector3], number_of_neighbours : float, prev_pos : Vector3 = Vector3(0.0, 0.0, 0.0)):
	points.append(prev_pos)
	for i in range(round(number_of_neighbours)):
		var max_attempts : int = 20
		var check : bool = false
		var R : float = 0.5
		var new_pos : Vector3
		var attempt : int = 0
		
		while !check:
			if attempt >= max_attempts:
				break
			var random_direction := get_spread()
			
			new_pos = random_direction * ((R * cloud_scale * 2) * overlap) + prev_pos
			check = check_clouds_pos(cloud_name, new_pos, R * cloud_scale)
			attempt += 1
		
		if check:
			generate_points(cloud_name, points, number_of_neighbours - n_step, new_pos)
		else:
			print("WARNING: a lot of attempts in generate_core func!")

func create_emission_texture(points: Array[Vector3]) -> ImageTexture:
	var count = points.size()
	if count == 0: return null
	
	var image = Image.create_empty(count, 1, false, Image.FORMAT_RGBF)
	
	for i in range(count):
		var p = points[i]
		var color = Color(p.x, p.y, p.z) 
		image.set_pixel(i, 0, color)
	
	return ImageTexture.create_from_image(image)

func spawn_cloud_func() -> CloudInstance:
	lines = load_data()
	if lines.is_empty(): return null
	
	var line : Dictionary
	if lines.size() == 1:
		line = lines[0]
	else:
		while true:
			line = lines.pick_random()
			if line["id"] != last_line:
				break
		last_line = line["id"]
		
	var pos := (line["position"] as Vector3) + Vector3(-wind.x, 0.0, -wind.y).normalized() * (lines_length / 2)
	var end_pos := (line["position"] as Vector3) + Vector3(wind.x, 0.0, wind.y).normalized() * (lines_length / 2)
	
	var cloud := CLOUD.instantiate()
	clouds_container.add_child(cloud)
	cloud.global_position = pos
	#cloud.owner = get_tree().edited_scene_root
	cloud.lifetime = life_time
	
	var new_mesh = SphereMesh.new()
	new_mesh.radius = 0.5 * cloud_scale
	new_mesh.height = 1.0 * cloud_scale
	new_mesh.radial_segments = 8
	new_mesh.rings = 4
	cloud.draw_pass_1 = new_mesh
	
	var points : Array[Vector3] = []
	generate_points(cloud.name, points, num_of_neighbours)
	
	var tex = create_emission_texture(points)
	if tex:
		var mat = cloud.process_material as ParticleProcessMaterial
		cloud.amount = points.size()
		mat.emission_point_count = points.size()
		mat.emission_point_texture = tex
	
	return CloudInstance.new(cloud, line["speed"], end_pos)

func gen_appearance():
	cloud_scale = randf_range(4.0, 5.0)
	overlap = randf_range(0.35, 0.5)
	n_step = randf_range(2.3, 2.7)
	num_of_neighbours = 6
	direction_spread = Vector3(
		randf_range(1.2, 1.8),
		randf_range(0.4, 0.7),
		randf_range(1.2, 1.8)
	)
	life_time = randf_range(20.0, 40.0)

func erase_cloud(cloud: CloudInstance):
	active_clouds.erase(cloud)
	if is_instance_valid(cloud.node):
		cloud.node.queue_free()

func _process(delta: float) -> void:
	if spawn_random:
		spawn_timer += delta
		if spawn_timer >= spawn_interval:
			spawn_timer = 0.0
			if randf() <= spawn_probability:
				gen_appearance()
				active_clouds.append(spawn_cloud_func())
				
	if move:
		for i in range(active_clouds.size() - 1, -1, -1):
			var cloud = active_clouds[i]
			if cloud.node.global_position.distance_to(cloud.end_pos) <= 1.0:		
				cloud.node.emitting = false
				var lifetime = cloud.node.lifetime
				get_tree().create_timer(lifetime).timeout.connect(erase_cloud.bind(cloud))
			
			var direction := Vector3(wind.x, 0.0, wind.y).normalized()
			cloud.node.global_position += direction * cloud.speed * delta
		
