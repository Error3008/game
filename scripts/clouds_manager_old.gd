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
		
@export var spawn_and_move: bool = false

@export_group("Layout Settings")
@export var start_position : Vector3 = Vector3(0.0, 100.0, 0.0)
@export var lines_length : float = 100.0
@export var lines_count : int = 3
@export var distance_between_lines : float = 20.0
@export var wind : Vector2 = Vector2(1.0, 0.0)
@export var max_line_speed : float = 15
@export var min_line_speed : float = 5
@export var spawn_interval: float = 5.0
@export var spawn_probability: float = 0.5

var spawn_timer: float = 0.0

@export_group("Cloud Structure")
#@export var global_cloud_scale: float = 1.0:
	#set(value):
		#var ratio = value / global_cloud_scale if global_cloud_scale != 0 else value
		#global_cloud_scale = value
		#
		#core_scale *= ratio
		#max_child_scale *= ratio
		#min_child_scale *= ratio
		#notify_property_list_changed()
		
@export var cloud_scale: float = 1.0
@export var overlap_threshold: float = 1.0
@export var overlap: float = 0.8
@export var num_of_neighbours: int = 2
@export var n_step: float = 2

#@export_subgroup("Children Scaling")
#@export var max_child_scale: float = 0.8
#@export var min_child_scale: float = 0.3
#@export var child_overlap: float = 1.0
#
#@export_subgroup("Children Count")
#@export var max_children: int = 5
#@export var min_children: int = 0

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
	
	lines.clear()
	for i in range(lines_count):
		var target := start_position + perp.normalized() * distance * side
		var line_speed := randf_range(min_line_speed, max_line_speed)
		lines.append({"id": i, "position": target, "speed": line_speed})
		
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
		
		if distance < (new_R + (R * S)) * overlap * overlap_threshold:
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

#func generate_core(cloud_name : String, pos : Vector3, number_of_neighbours : int, S : float):
	#var cloud_node := get_node("CloudsContainer/%s" % cloud_name)
	#
	#var core := CLOUD.instantiate()
	#cloud_node.add_child(core)
	#core.global_position = pos
	#core.lifetime *= S 
	#core.owner = get_tree().edited_scene_root
	#core.scale = Vector3(S, S, S)
	#
	#for i in range(number_of_neighbours):
		#var max_attempts : int = 20
		#var check : bool = false
		#var R : float = core.process_material.emission_sphere_radius
		#var new_pos : Vector3
		#var attempt : int = 0
		#
		#while !check:
			#if attempt >= max_attempts:
				#break
			#var random_direction := get_spread_for(false)
			#
			#new_pos = random_direction * ((R * core_scale * 2) * core_overlap) + core.global_position
			#check = check_clouds_pos(cloud_name, new_pos, R * core_scale, core_overlap)
			#attempt += 1
		#
		#if check:
			#generate_core(cloud_name, new_pos, number_of_neighbours - n_step, core_scale)
		#else:
			#print("ERROR: a lot of attempts in generate_core func!")
	
#func generate_child(cloud_name : String, num_of_childs : int):
	#var cloud_node := get_node("CloudsContainer/%s" % cloud_name)
	#var existing_cores = cloud_node.get_children()
	#
	#for core in existing_cores:
		#var pos : Vector3 = core.global_position
		#var R : float = core.process_material.emission_sphere_radius
		#var S : float = core.scale.x
		#
		#for i in range(num_of_childs):
			#var max_attempts : int = 20
			#var attempt : int = 0
			#var success : bool = false
			#
			#var final_pos : Vector3
			#var final_scale : float
			#
			#while attempt < max_attempts:
				#var random_direction := get_spread_for(true)	
				#var child_S = randf_range(min_child_scale, max_child_scale)
				#var new_R = R
				#var distance = (R * S + new_R * child_S) * child_overlap
				#var potential_pos = pos + (random_direction * distance)
				#
				#if check_clouds_pos(cloud_name, potential_pos, new_R * child_S, child_overlap):
					#final_pos = potential_pos
					#final_scale = child_S
					#success = true
					#break
				#
				#attempt += 1
			#
			#if success:
				#generate_core(cloud_name, final_pos, 0, final_scale)
			#else:
				#print("Could not find spot for child at core: ", core.name)			

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
	cloud.owner = get_tree().edited_scene_root
	
	var points : Array[Vector3] = []
	generate_points(cloud.name, points, num_of_neighbours)
	
	var tex = create_emission_texture(points)
	if tex:
		var mat = cloud.process_material as ParticleProcessMaterial
		cloud.amount = points.size()
		mat.emission_point_count = points.size()
		mat.emission_point_texture = tex
	
	return CloudInstance.new(cloud, line["speed"], end_pos)

func erase_cloud(cloud: CloudInstance):
	active_clouds.erase(cloud)
	if is_instance_valid(cloud.node):
		cloud.node.queue_free()

func _process(delta: float) -> void:
	if !spawn_and_move:
		return 
		
	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		if randf() <= spawn_probability:
			active_clouds.append(spawn_cloud_func())
			
	for i in range(active_clouds.size() - 1, -1, -1):
		var cloud = active_clouds[i]
		if cloud.node.global_position.distance_to(cloud.end_pos) <= 1.0:		
			cloud.node.emitting = false
			var lifetime = cloud.node.lifetime
			get_tree().create_timer(lifetime).timeout.connect(erase_cloud.bind(cloud))
		
		var direction := Vector3(wind.x, 0.0, wind.y).normalized()
		cloud.node.global_position += direction * cloud.speed * delta
		
	
#func generate_cloud() -> CloudInstance:
	#lines = load_data()
	#if lines.is_empty(): return null
	#
	#var line : LinesData = lines.pick_random()
	#var pos := line.position + Vector3(-wind.x, 0.0, -wind.y).normalized() * (lines_length / 2)
	#
	#var new_cloud : Node3D = Node3D.new()
	#clouds_container.add_child(new_cloud)
	#new_cloud.owner = get_tree().edited_scene_root
	#generate_core(new_cloud.name, pos, num_of_neighbours, core_scale)
	#generate_child(new_cloud.name, randi_range(min_children, max_children))
	#
	#var instance = CloudInstance.new(new_cloud, line.speed)
	#return instance

#func _process(delta: float) -> void:
	#if not Engine.is_editor_hint() and not auto_spawn: return
	#if auto_spawn:
		#spawn_timer += delta
		#if spawn_timer >= spawn_interval:
			#spawn_timer = 0.0
			#if randf() <= spawn_probability:
				#var new_inst = generate_cloud()
				#if new_inst:
					#active_clouds.append(new_inst)
					#
	#for i in range(active_clouds.size() - 1, -1, -1):
		#var cloud = active_clouds[i]
		#
		#if is_instance_valid(cloud.node):
			#cloud.node.global_position += Vector3(wind.x, 0.0, wind.y).normalized() * cloud.speed * delta
		#else:
			#active_clouds.remove_at(i)
