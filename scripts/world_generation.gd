@tool
extends Node3D

@export var get_map_image : bool = false:
	set(value):
		if value:
			get_map_image_f()
			
@export var generate : bool = false:
	set(value):
		if value:
			generate_chunks()

@export var generate_point : Vector2 = Vector2(0, 0)
@export var generate_radius : int = 1
@export var chunks_count : int = 8192
@export var chunk_size : int = 16
@export var cell_size : float = 1
@export var image_size : int = 1024
@export var offset_x : int = 0
@export var offset_y : int = 0
@export var zoom : float = 128
@export var height_scale : float = 1

@export var base_noise : FastNoiseLite
@export var base_noise_scale : float = 0.002

@export var roughness_noise : FastNoiseLite
@export var roughness_noise_scale : float = 0.002
@export var roughness_curve : Curve

var max_land_height : float = 0
var current_coords: Array

func get_map_image_f():
	var map := Image.create(image_size, image_size, false, Image.FORMAT_RGB8)
	#var test := Image.create(image_size, image_size, false, Image.FORMAT_RGB8)
	
	for y in range(image_size):
		for x in range(image_size):
			var world_x : float = offset_x + (x * zoom)
			var world_y : float = offset_y + (y * zoom)
			
			var height : float = get_point_info(Vector2(world_x, world_y))
			#619 370
			var color : Color
			if height <= 0.0:
				color = Color(0.07, 0.41, 0.63, 1.0)
			elif height <= 0.2:
				color = Color(0.642, 0.635, 0.318, 1.0)
			elif height <= 0.4:
				color = Color(0.221, 0.525, 0.216, 1.0)
			elif height <= 0.6:
				color = Color(0.144, 0.357, 0.14, 1.0)
			elif height <= 1.0:
				color = Color(0.529, 0.529, 0.529, 1.0)
			else:
				color = Color(0.741, 0.741, 0.741, 1.0)
			
			map.set_pixel(x, y, color)
			#test.set_pixel(x, y, Color(roughness_val, roughness_val, roughness_val))
			
	var err_map = map.save_png("res://saves/map.png")
	#test.save_png("res://saves/test.png")
	
	if err_map == OK:
		print("Successful")
	else:
		print("Error")

func get_chunk_coords_in_radius(center: Vector2, radius: int) -> Array[Vector2]:
	var chunks: Array[Vector2] = []
	var radius_squared = radius * radius

	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			if x * x + y * y <= radius_squared:
				chunks.append(center + Vector2(x, y))

	chunks.sort_custom(func(a, b): 
		return center.distance_squared_to(a) < center.distance_squared_to(b)
	)

	return chunks

func get_point_info(pos : Vector2):
	var base_val := base_noise.get_noise_2d(pos.x * base_noise_scale, pos.y * base_noise_scale)
	var roughness_val := (roughness_noise.get_noise_2d(pos.x * roughness_noise_scale, pos.y * roughness_noise_scale) + 1.0) / 2.0
	roughness_val = roughness_val * roughness_curve.sample_baked(maxf(0.0, base_val))
	
	var result := base_val + roughness_val
	
	if max_land_height < result:
		max_land_height = result
	
	return result

func generate_chunks():
	max_land_height = 0
	
	#for child in get_children():
		#child.queue_free()
	
	var pos_of_chunk := get_chunk_coords(generate_point)
	current_coords = get_chunk_coords_in_radius(pos_of_chunk, generate_radius)
	global_position = Vector3(-generate_point.x, 0, -generate_point.y)
	
	WorkerThreadPool.add_group_task(generate_single_chunk, current_coords.size())

func generate_single_chunk(index : int):
	var c : Vector2 = current_coords[index]
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var chunk_noise_x := chunk_size * cell_size * c.x
	var chunk_noise_z := chunk_size * cell_size * c.y
	
	for x in range(chunk_size):
		for z in range(chunk_size):
			var height00 = get_point_info(Vector2(chunk_noise_x + x * cell_size, chunk_noise_z + z * cell_size))
			var y00 = height00 * height_scale
			var p00 = Vector3(x * cell_size, y00, z * cell_size)

			var height01 = get_point_info(Vector2(chunk_noise_x + x * cell_size, chunk_noise_z + (z + 1) * cell_size))
			var y01 = height01 * height_scale
			var p01 = Vector3(x * cell_size, y01, (z + 1) * cell_size)

			var height10 = get_point_info(Vector2(chunk_noise_x + (x + 1) * cell_size, chunk_noise_z + z * cell_size))
			var y10 = height10 * height_scale
			var p10 = Vector3((x + 1) * cell_size, y10, z * cell_size)

			var height11 = get_point_info(Vector2(chunk_noise_x + (x + 1) * cell_size, chunk_noise_z + (z + 1) * cell_size))
			var y11 = height11 * height_scale
			var p11 = Vector3((x + 1) * cell_size, y11, (z + 1) * cell_size)
			
			var n1 = (p01 - p00).cross(p10 - p00).normalized()
			var c1 = Color(0.282, 0.63, 0.1, 1.0)

			st.set_normal(n1); st.set_color(c1); st.add_vertex(p00)
			st.set_normal(n1); st.set_color(c1); st.add_vertex(p10)
			st.set_normal(n1); st.set_color(c1); st.add_vertex(p01)

			var n2 = (p01 - p10).cross(p11 - p10).normalized()
			var c2 = Color(0.282, 0.63, 0.1, 1.0)

			st.set_normal(n2); st.set_color(c2); st.add_vertex(p10)
			st.set_normal(n2); st.set_color(c2); st.add_vertex(p11)
			st.set_normal(n2); st.set_color(c2); st.add_vertex(p01)
			
	var mesh := st.commit()
	call_deferred("spawn_chunk", c, mesh)
	
func spawn_chunk(pos_of_chunk : Vector2, mesh_data: ArrayMesh) -> void:
	var chunk_node = MeshInstance3D.new()
	chunk_node.mesh = mesh_data
	
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true

	chunk_node.material_override = mat
	
	add_child(chunk_node)
	
	chunk_node.position = Vector3(
		pos_of_chunk.x * chunk_size * cell_size, 
		0, 
		pos_of_chunk.y * chunk_size  * cell_size
	)

func get_chunk_coords(world_pos: Vector2) -> Vector2i:
	var chunk_world_size := chunk_size * cell_size
	
	var chunk_x := floori(world_pos.x / chunk_world_size)
	var chunk_z := floori(world_pos.y / chunk_world_size)
	
	return Vector2i(chunk_x, chunk_z)
