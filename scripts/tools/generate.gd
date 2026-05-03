@tool
extends Node3D

@onready var island_sand: MeshInstance3D = $".."

@export var max_attempts := 10000
@export var amount := 100
@export var objects_array : Array[Resource] 

@export var start_generation : bool = false:
	set(value):
		if value == true:
			generate()
			start_generation = false
			
@export var clear_details : bool = false:
	set(value):
		if value:
			clear_beach()
			clear_details = false
		

func clear_beach():
	print("Clean-up...")
	var count = 0
	for child in get_children():
		child.free()
		count += 1
	print("Nodes removed: ", count)
			
func generate():
	randomize()
	var space_state := get_world_3d().direct_space_state
	var aabb : AABB = island_sand.get_aabb()
	
	var attempt := 0
	var current_amount := 0
	
	while current_amount < amount:
		if attempt >= max_attempts:
			print("The number of attempts has reached the maximum!")
			break
		attempt += 1
		
		var x : float = randf_range(aabb.position.x, aabb.position.x + aabb.size.x)
		var y : float = aabb.position.y + aabb.size.y + 2 
		var z : float = randf_range(aabb.position.z, aabb.position.z + aabb.size.z)
		
		var l_origin : Vector3 =  Vector3(x, y, z)
		var l_end : Vector3 = l_origin + Vector3(0, -(aabb.size.y + 4) , 0)
		var g_origin := island_sand.to_global(l_origin)
		var g_end := island_sand.to_global(l_end)
		
		var query := PhysicsRayQueryParameters3D.create(g_origin, g_end)
		
		var result := space_state.intersect_ray(query)
		
		if result and result.collider.name == "StaticBodyIslandSand":
			print("Getting into: ", result.collider)
			print("Position: ", result.position)
			print("Normal: ", result.normal)
			
			var resource = objects_array.pick_random()
			var node = resource.instantiate()
			
			add_child(node)
			
			node.global_position = result.position
			
			var random_dir = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))

			if random_dir.length() < 0.1:
				random_dir = Vector3.FORWARD
			
			var target_pos = node.global_position + random_dir
			node.look_at(target_pos, result.normal)
			var mesh_instance : MeshInstance3D = node.find_child("*", true, false)
			
			if mesh_instance:
				var new_aabb : AABB = node.global_transform * mesh_instance.get_aabb()
				
				var can_place := true
				
				for child in get_children():
					if child == node:
						continue
					
					var child_mesh : MeshInstance3D = child.find_child("*", true, false)
					if child_mesh:
						var child_aabb : AABB = child_mesh.global_transform * child_mesh.get_aabb()
						
						if new_aabb.intersects(child_aabb):
							print("An intersection has been detected with: ", child.name)
							can_place = false
							break
							
				if can_place:
					node.owner = get_tree().edited_scene_root
					print(resource, " was successfully created in: ", result.position)
					current_amount += 1
				else:
					node.free()
					print("The space is taken; we'll give it a miss...")
			else:
				print("Error: MeshInstance3D not found in the model file")
				node.free()
				
				
			
		
