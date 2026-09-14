@tool
#Этот скрипт закладывает основу. 
#При настройке не забудь использовать следующую архитектуру: 
#Для каждой местности должен быть шум спавна, 
#Для самой местности шум генерации, 
#А также кривые для каждого типа шума, чтобы можно было точно настроить параметры генерации.
extends Node3D
enum BiomeType {
	OCEAN,
	PLAINS,
	FOREST,
	HILLS,
}

enum DebugMapMode {
	BIOMES,
	BIOMES_SHADED,
	HEIGHTMAP,
	FOREST_SPAWN_MASK,
	ROUGHNESS_MAP,
}

@export_group("Triggers")
@export var get_map_image : bool = false:
	set(value):
		if value:
			get_map_image_f()
			
@export var generate : bool = false:
	set(value):
		if value:
			generate_chunks()

@export var clear_chunks : bool = false:
	set(value):
		if value:
			clear_generated_chunks()

@export_group("Map 2D Debug")
@export var debug_map_mode : DebugMapMode = DebugMapMode.BIOMES_SHADED
@export var draw_chunk_bounds : bool = true
@export var image_size : int = 1024
@export var offset_x : int = 0
@export var offset_y : int = 0
@export var zoom : float = 128.0

@export_group("3D World Settings")
@export var generate_point : Vector2 = Vector2(0, 0)
@export var generate_radius : int = 1
@export var chunks_count : int = 8192
@export var chunk_size : int = 16
@export var cell_size : float = 1.0
@export var height_scale : float = 100.0
@export var micro_noise: FastNoiseLite

@export_group("Base Continent / Sea")
@export var base_noise : FastNoiseLite
@export var base_noise_scale : float = 0.002
@export var water_level : float = 0.0

@export_group("Plains (Biome)")
# Шум микрорельефа равнин (пологий, спокойный)
@export var plains_gen_noise : FastNoiseLite
@export var plains_gen_noise_scale : float = 0.003
@export var plains_amplitude : float = 0.04
@export var plains_curve : Curve

@export_group("Hills (Biome)")
# Шум спавна (где появляются холмы)
@export var hills_spawn_noise : FastNoiseLite
@export var hills_spawn_noise_scale : float = 0.0015
@export var hills_threshold : float = 0.25
@export var hills_blend_margin : float = 0.1 # Ширина зоны плавного перехода в равнину

# Шум генерации рельефа холмов (хребты, лощины и высота)
@export var hills_gen_noise : FastNoiseLite
@export var hills_gen_noise_scale : float = 0.004
@export var hills_amplitude : float = 0.35
@export var hills_curve : Curve
@export var hills_inland_curve : Curve # Усиление холмов в глубине материка

@export_group("Forest (Vegetation Cover)")
# Шум спавна лесного покрова поверх рельефа
@export var forest_noise : FastNoiseLite
@export var forest_noise_scale : float = 0.001
@export var forest_curve : Curve
@export var forest_threshold : float = 0.5
@export var forest_blend_margin : float = 0.08

@export_group("Objects Generation (Jittered Grid)")
# Сид генератора объектов для детерминированного хэша ячеек
@export var spawn_seed : int = 1337
# Список типов объектов для спавна (деревья, валуны, кусты, грибы и т.д.).
# Нажми «+» в инспекторе чтобы добавить новый SpawnableItem.
@export var spawnable_items : Array[SpawnableItem]
## Для обратной совместимости со сценами, где использовался tree_types
@export var tree_types : Array

@export_group("Grass Generation (GPU Carpet)")
## Включить процедурную генерацию травяного ковра на GPU
@export var enable_grass : bool = true
## 3D-меш травинки (по умолчанию загружается res://meshes/grass.res)
@export var grass_mesh : Mesh
## Шейдерный материал травы (по умолчанию загружается res://materials/grass_material.tres)
@export var grass_material : ShaderMaterial
## Расстояние между травинками в сетке (в метрах). 0.5м = ~1024 травинки на чанк 16x16м.
@export var grass_density_step : float = 0.5
## Максимальный уклон склона в градусах, на котором растёт трава
@export var grass_max_slope : float = 38.0
## Шаг детализации текстуры рельефа чанка (в метрах на пиксель). По умолчанию 0.25м (64x64 пикселей для 16м чанка).
@export var grass_texture_step : float = 0.25

var current_coords: Array

var task_id: int = -1
var cancel_generation: bool = false
# Кэш заглушек-мешей: footprint_radius -> BoxMesh (создаётся по первому запросу)
var _placeholder_meshes: Dictionary = {}
# Копия spawnable_items, отсортированная по убыванию footprint_radius.
# Заполняется один раз в generate_chunks() до старта потоков; потоки читают только.
var _sorted_spawnable_items: Array = []

# Кэш единого шаблонного MultiMesh для травы на Y = 0 (делится между всеми чанками мира)
var _shared_grass_multimesh : MultiMesh = null
var _last_grass_density_step : float = -1.0
var _last_grass_chunk_size : float = -1.0
var _last_grass_mesh : Mesh = null

func get_shared_grass_multimesh() -> MultiMesh:
	var chunk_world_size := chunk_size * cell_size
	var mesh_to_use : Mesh = grass_mesh
	if mesh_to_use == null:
		var default_mesh_path := "res://meshes/grass.res"
		if ResourceLoader.exists(default_mesh_path):
			mesh_to_use = load(default_mesh_path)
	if mesh_to_use == null:
		var quad := QuadMesh.new()
		quad.size = Vector2(0.5, 0.6)
		mesh_to_use = quad
	
	if _shared_grass_multimesh != null \
		and _last_grass_density_step == grass_density_step \
		and _last_grass_chunk_size == chunk_world_size \
		and _last_grass_mesh == mesh_to_use:
		return _shared_grass_multimesh
	
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh_to_use
	
	var step := maxf(0.15, grass_density_step)
	var steps_count := int(ceil(chunk_world_size / step))
	var count := steps_count * steps_count
	mm.instance_count = count
	
	var idx := 0
	for ix in range(steps_count):
		for iz in range(steps_count):
			var base_x := (float(ix) + 0.5) * step
			var base_z := (float(iz) + 0.5) * step
			
			var h := get_cell_hash(ix, iz, 55555)
			var jitter_x := (hash_to_float(h, 0) * 2.0 - 1.0) * (step * 0.4)
			var jitter_z := (hash_to_float(h, 1) * 2.0 - 1.0) * (step * 0.4)
			var rot_y := hash_to_float(h, 2) * TAU
			var scale_rnd := lerpf(0.85, 1.2, hash_to_float(h, 3))
			
			var x := clampf(base_x + jitter_x, 0.0, chunk_world_size)
			var z := clampf(base_z + jitter_z, 0.0, chunk_world_size)
			
			var t := Transform3D()
			# Масштабируем по X и Z для вариативности кустиков, Y масштабируется шейдером по маске
			t = t.scaled(Vector3(scale_rnd, 1.0, scale_rnd))
			t = t.rotated(Vector3.UP, rot_y)
			t.origin = Vector3(x, 0.0, z)
			
			mm.set_instance_transform(idx, t)
			idx += 1
			
	_shared_grass_multimesh = mm
	_last_grass_density_step = grass_density_step
	_last_grass_chunk_size = chunk_world_size
	_last_grass_mesh = mesh_to_use
	return mm


func get_placeholder_mesh(item: SpawnableItem) -> Mesh:
	# Заглушки кэшируются по footprint_radius — каждый уникальный размер создаётся один раз.
	var key := item.footprint_radius
	if _placeholder_meshes.has(key):
		return _placeholder_meshes[key]
	
	# =========================================================================
	# ЗАТЫЧКА ДЛЯ ОБЪЕКТА:
	# Пропорциональный прямоугольник с коричневым материалом.
	# Размеры выводятся из footprint_radius типа объекта.
	# Когда появится готовая 3D-модель: задай её в поле mesh у SpawnableItem.
	# =========================================================================
	var width := item.footprint_radius * 0.4
	var height := item.footprint_radius * 1.2
	
	var box := BoxMesh.new()
	box.size = Vector3(width, height, width)
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.17, 0.09) # Коричневый оттенок
	box.material = mat
	
	_placeholder_meshes[key] = box
	return box


func get_cell_hash(cx: int, cz: int, seed_val: int) -> int:
	# Быстрый целочисленный хэш координаты ячейки и сида
	var h: int = cx * 73856093 ^ cz * 19349663 ^ seed_val * 83492791
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = h ^ (h >> 16)
	return h

func hash_to_float(h: int, index: int) -> float:
	# Генерирует детерминированное число 0.0 .. 1.0 из хэша
	var v: int = h ^ (index * 0x9e3779b9)
	v = (v ^ (v >> 13)) * 0x5bd1e995
	v = v ^ (v >> 15)
	return float(v & 0x7FFFFFFF) / float(0x7FFFFFFF)

func get_spawn_weight_for_item(item: SpawnableItem, pos: Vector2) -> float:
	# Если для объекта задан собственный шум спавна — вычисляем вес по нему
	if item.spawn_noise != null:
		var raw_n := (item.spawn_noise.get_noise_2d(pos.x * item.spawn_noise_scale, pos.y * item.spawn_noise_scale) + 1.0) * 0.5
		if item.spawn_curve != null:
			raw_n = item.spawn_curve.sample_baked(raw_n)
		return smoothstep(item.spawn_threshold - 0.08, item.spawn_threshold + 0.08, raw_n)
	else:
		# По умолчанию объекты привязаны к покрову леса
		return get_forest_weight(pos)

func get_micro_height(pos : Vector2) -> float:
	return micro_noise.get_noise_2dv(pos)


func get_hills_weight(pos : Vector2) -> float:
	var s_noise = hills_spawn_noise 
	var s_scale = hills_spawn_noise_scale
	if not s_noise:
		return 0.0
	var raw_spawn := (s_noise.get_noise_2d(pos.x * s_scale, pos.y * s_scale) + 1.0) * 0.5
	return smoothstep(hills_threshold - hills_blend_margin, hills_threshold + hills_blend_margin, raw_spawn)

func get_forest_weight(pos : Vector2) -> float:
	if not forest_noise:
		return 0.0
	var raw_f := (forest_noise.get_noise_2d(pos.x * forest_noise_scale, pos.y * forest_noise_scale) + 1.0) * 0.5
	if forest_curve:
		raw_f = forest_curve.sample_baked(raw_f)
	return smoothstep(forest_threshold - forest_blend_margin, forest_threshold + forest_blend_margin, raw_f)

func get_point_height(pos : Vector2) -> float:
	var base_val := 0.0
	if base_noise:
		base_val = base_noise.get_noise_2d(pos.x * base_noise_scale, pos.y * base_noise_scale)
	
	# Вес холмов (0.0 = равнина, 1.0 = холмы)
	var w_hills := get_hills_weight(pos)
	var w_plains := 1.0 - w_hills
	
	# 1. Рельеф равнины
	var plains_relief := 0.0
	if plains_gen_noise:
		var p_noise := plains_gen_noise.get_noise_2d(pos.x * plains_gen_noise_scale, pos.y * plains_gen_noise_scale)
		if plains_curve:
			p_noise = plains_curve.sample_baked((p_noise + 1.0) * 0.5) * 2.0 - 1.0
		plains_relief = p_noise * plains_amplitude
	
	# 2. Рельеф холмов
	var hills_relief := 0.0
	var g_noise = hills_gen_noise 
	var g_scale = hills_gen_noise_scale
	var g_curve = hills_curve
	var inland_curve = hills_inland_curve
	
	if g_noise:
		var h_noise := (g_noise.get_noise_2d(pos.x * g_scale, pos.y * g_scale) + 1.0) * 0.5
		if g_curve:
			h_noise = g_curve.sample_baked(h_noise)
		var inland_factor := 1.0
		if inland_curve:
			inland_factor = inland_curve.sample_baked(maxf(0.0, base_val))
		hills_relief = h_noise * hills_amplitude * inland_factor
	
	var blended_relief := (w_plains * plains_relief) + (w_hills * hills_relief)
	return base_val + blended_relief

func get_point_info(pos : Vector2) -> float:
	return get_point_height(pos)

func get_point_color(pos : Vector2, height : float) -> Color:
	# Океан
	if height <= water_level:
		return Color(0.08, 0.35, 0.65, 1.0)
	
	var w_hills := get_hills_weight(pos)
	var w_forest := get_forest_weight(pos)
	
	# Базовый цвет рельефа: плавный переход от лугов к холмам
	var plains_color := Color(0.44, 0.73, 0.26, 1.0) # Луговой салатовый
	var hills_color := Color(0.68, 0.54, 0.33, 1.0)  # Охристо-холмистый
	var base_terrain_color := plains_color.lerp(hills_color, w_hills)
	
	# Лесной покров поверх рельефа
	var forest_color := Color(0.13, 0.42, 0.17, 1.0) # Темная хвоя/листва
	var final_color := base_terrain_color.lerp(forest_color, w_forest * 0.85)
	
	return final_color

func get_point_biome(pos : Vector2, height : float) -> BiomeType:
	if height <= water_level:
		return BiomeType.OCEAN
	var w_forest := get_forest_weight(pos)
	if w_forest > 0.5:
		return BiomeType.FOREST
	var w_hills := get_hills_weight(pos)
	if w_hills > 0.5:
		return BiomeType.HILLS
	return BiomeType.PLAINS

func get_map_image_f():
	var map := Image.create(image_size, image_size, false, Image.FORMAT_RGB8)
	var need_shading := (debug_map_mode == DebugMapMode.BIOMES_SHADED)
	
	for y in range(image_size):
		for x in range(image_size):
			var world_x : float = offset_x + (x * zoom)
			var world_y : float = offset_y + (y * zoom)
			var world_pos := Vector2(world_x, world_y)
			
			var height := get_point_height(world_pos)
			var pixel_color : Color
			
			match debug_map_mode:
				DebugMapMode.BIOMES, DebugMapMode.BIOMES_SHADED:
					pixel_color = get_point_color(world_pos, height)
					
					if need_shading and height > water_level:
						# Псевдо-затенение рельефа (свет падает с северо-запада)
						var prev_pos := Vector2(world_x - zoom, world_y - zoom)
						var prev_height := get_point_height(prev_pos)
						var slope := (prev_height - height) * 8.0
						var shade := clampf(1.0 + slope, 0.45, 1.4)
						pixel_color = Color(
							clampf(pixel_color.r * shade, 0.0, 1.0),
							clampf(pixel_color.g * shade, 0.0, 1.0),
							clampf(pixel_color.b * shade, 0.0, 1.0),
							1.0
						)
				
				DebugMapMode.HEIGHTMAP:
					var norm_h := clampf((height + 0.5) / 1.5, 0.0, 1.0)
					if height <= water_level:
						pixel_color = Color(0.0, 0.1, 0.3).lerp(Color(0.1, 0.4, 0.7), norm_h)
					else:
						pixel_color = Color(norm_h, norm_h, norm_h)
				
				DebugMapMode.FOREST_SPAWN_MASK:
					var w_f := get_forest_weight(world_pos)
					pixel_color = Color(w_f * 0.1, 0.08 + w_f * 0.7, w_f * 0.15)
				
				DebugMapMode.ROUGHNESS_MAP:
					var w_h := get_hills_weight(world_pos)
					pixel_color = Color(w_h * 0.85, w_h * 0.55, w_h * 0.2)
			
			map.set_pixel(x, y, pixel_color)
	
	if draw_chunk_bounds:
		draw_generation_zone_on_map(map)
	
	DirAccess.make_dir_recursive_absolute("res://saves")
	var err_map = map.save_png("res://saves/map.png")
	
	if err_map == OK:
		print("Map successfully saved to res://saves/map.png")
	else:
		print("Error saving map: ", err_map)

func draw_generation_zone_on_map(map: Image) -> void:
	var center_px_x := int((generate_point.x - offset_x) / zoom)
	var center_px_y := int((generate_point.y - offset_y) / zoom)
	var radius_world := generate_radius * chunk_size * cell_size
	var radius_px := int(radius_world / zoom)
	
	if radius_px < 1:
		radius_px = 1
	
	var border_color := Color(1.0, 0.15, 0.15, 1.0) # Ярко-красный круг зоны
	var center_color := Color(1.0, 1.0, 0.0, 1.0)  # Желтый крестик центра
	
	# Отрисовка центра (крестик 5x5)
	for dx in range(-2, 3):
		var px := center_px_x + dx
		var py := center_px_y
		if px >= 0 and px < image_size and py >= 0 and py < image_size:
			map.set_pixel(px, py, center_color)
	for dy in range(-2, 3):
		var px := center_px_x
		var py := center_px_y + dy
		if px >= 0 and px < image_size and py >= 0 and py < image_size:
			map.set_pixel(px, py, center_color)
	
	# Отрисовка окружности радиуса генерации
	var cx := center_px_x
	var cy := center_px_y
	var r := radius_px
	
	var x := 0
	var y := r
	var d := 1 - r
	
	var plot_circle_points := func(plot_x: int, plot_y: int):
		var points := [
			Vector2i(cx + plot_x, cy + plot_y),
			Vector2i(cx - plot_x, cy + plot_y),
			Vector2i(cx + plot_x, cy - plot_y),
			Vector2i(cx - plot_x, cy - plot_y),
			Vector2i(cx + plot_y, cy + plot_x),
			Vector2i(cx - plot_y, cy + plot_x),
			Vector2i(cx + plot_y, cy - plot_x),
			Vector2i(cx - plot_y, cy - plot_x),
		]
		for pt in points:
			if pt.x >= 0 and pt.x < image_size and pt.y >= 0 and pt.y < image_size:
				map.set_pixel(pt.x, pt.y, border_color)
	
	while x <= y:
		plot_circle_points.call(x, y)
		x += 1
		if d < 0:
			d += 2 * x + 1
		else:
			y -= 1
			d += 2 * (x - y) + 1

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

func clear_generated_chunks():
	if task_id != -1:
		cancel_generation = true
		WorkerThreadPool.wait_for_group_task_completion(task_id)
		task_id = -1
	
	var removed := 0
	for child in get_children():
		if child is MeshInstance3D:
			child.free()
			removed += 1
	print("Cleared generated chunks: ", removed)

func generate_chunks():
	clear_generated_chunks()
	
	# Подготовка и сортировка объектов по убыванию footprint_radius (крупные первыми)
	_sorted_spawnable_items = []
	if spawnable_items != null:
		for it in spawnable_items:
			if it != null:
				_sorted_spawnable_items.append(it)
	# Поддержка объектов из ранее настроенных сцен (tree_types)
	if tree_types != null:
		for it in tree_types:
			if it != null and not _sorted_spawnable_items.has(it):
				_sorted_spawnable_items.append(it)
	
	# Если список пуст — создаём дефолтный тип-заглушку для работы "из коробки"
	if _sorted_spawnable_items.is_empty():
		var default_item := SpawnableItem.new()
		default_item.name = "Default Tree"
		default_item.footprint_radius = 2.5
		default_item.density_multiplier = 0.85
		default_item.scale_min = 0.8
		default_item.scale_max = 1.3
		default_item.check_slope = true
		default_item.max_slope = 35.0
		default_item.check_collisions = true
		default_item.is_obstacle = true
		_sorted_spawnable_items.append(default_item)
	else:
		_sorted_spawnable_items.sort_custom(func(a: SpawnableItem, b: SpawnableItem): return a.footprint_radius > b.footprint_radius)
	
	var pos_of_chunk := get_chunk_coords(generate_point)
	current_coords = get_chunk_coords_in_radius(pos_of_chunk, generate_radius)
	global_position = Vector3(-generate_point.x, 0, -generate_point.y)
	
	cancel_generation = false
	task_id = WorkerThreadPool.add_group_task(generate_single_chunk, current_coords.size())

func generate_chunk_terrain_image(c : Vector2, local_obstacles : Array) -> Image:
	var chunk_world_size := chunk_size * cell_size
	var chunk_world_min_x := c.x * chunk_world_size
	var chunk_world_min_z := c.y * chunk_world_size
	
	var step := maxf(0.05, grass_texture_step)
	var tex_size := clampi(int(round(chunk_world_size / step)), 16, 256)
	
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGF)
	
	# 1. Заполняем рельеф и базовую маску уклона/воды
	for px in range(tex_size):
		for py in range(tex_size):
			var u := (float(px) + 0.5) / float(tex_size)
			var v := (float(py) + 0.5) / float(tex_size)
			var world_x := chunk_world_min_x + u * chunk_world_size
			var world_z := chunk_world_min_z + v * chunk_world_size
			var pos2d := Vector2(world_x, world_z)
			
			var h := get_point_height(pos2d)
			var world_y := h * height_scale + get_micro_height(pos2d)
			
			var mask := 1.0
			if h <= water_level:
				mask = 0.0
			else:
				var slope_step := 0.5
				var h_dx := (get_point_height(Vector2(world_x + slope_step, world_z)) - get_point_height(Vector2(world_x - slope_step, world_z))) / (2.0 * slope_step) * height_scale
				var h_dz := (get_point_height(Vector2(world_x, world_z + slope_step)) - get_point_height(Vector2(world_x, world_z - slope_step))) / (2.0 * slope_step) * height_scale
				var slope_deg := rad_to_deg(atan(sqrt(h_dx * h_dx + h_dz * h_dz)))
				mask = clampf(1.0 - smoothstep(grass_max_slope - 6.0, grass_max_slope, slope_deg), 0.0, 1.0)
			
			img.set_pixel(px, py, Color(world_y, mask, 0.0, 1.0))
			
	# 2. Штампуем препятствия (деревья, валуны) в маску травы с плавным затуханием
	for obs in local_obstacles:
		var obs_x : float = obs.x
		var obs_z : float = obs.y
		var obs_radius : float = obs.z
		
		var center_px := ((obs_x - chunk_world_min_x) / chunk_world_size) * float(tex_size)
		var center_py := ((obs_z - chunk_world_min_z) / chunk_world_size) * float(tex_size)
		var r_px := (obs_radius / chunk_world_size) * float(tex_size)
		
		var min_px := clampi(int(floor(center_px - r_px - 1.0)), 0, tex_size - 1)
		var max_px := clampi(int(ceil(center_px + r_px + 1.0)), 0, tex_size - 1)
		var min_py := clampi(int(floor(center_py - r_px - 1.0)), 0, tex_size - 1)
		var max_py := clampi(int(ceil(center_py + r_px + 1.0)), 0, tex_size - 1)
		
		var inner_r_px := r_px * 0.7
		
		for px in range(min_px, max_px + 1):
			for py in range(min_py, max_py + 1):
				var dx := float(px) + 0.5 - center_px
				var dy := float(py) + 0.5 - center_py
				var dist := sqrt(dx * dx + dy * dy)
				
				if dist < r_px:
					var fade := clampf((dist - inner_r_px) / maxf(0.001, r_px - inner_r_px), 0.0, 1.0)
					var col := img.get_pixel(px, py)
					img.set_pixel(px, py, Color(col.r, col.g * fade, 0.0, 1.0))
					
	return img

func generate_grid_objects(c : Vector2) -> Dictionary:
	var result: Array = []
	
	var chunk_world_min_x := c.x * chunk_size * cell_size
	var chunk_world_max_x := (c.x + 1) * chunk_size * cell_size
	var chunk_world_min_z := c.y * chunk_size * cell_size
	var chunk_world_max_z := (c.y + 1) * chunk_size * cell_size
	
	# Локальный массив препятствий для этого чанка: Vector3(x, z, footprint_radius).
	# Хранит все уже успешно размещённые объекты чанка.
	# Позволяет выполнять мгновенную проверку коллизий в кэше CPU без единого повторного вызова шума!
	var local_obstacles: Array[Vector3] = []
	
	for ti in range(_sorted_spawnable_items.size()):
		var item : SpawnableItem = _sorted_spawnable_items[ti]
		var type_seed := spawn_seed + ti
		var type_cell_size := item.footprint_radius * 2.0
		var max_offset := item.footprint_radius * 0.72
		
		var min_cx := floori(chunk_world_min_x / type_cell_size)
		var max_cx := floori(chunk_world_max_x / type_cell_size)
		var min_cz := floori(chunk_world_min_z / type_cell_size)
		var max_cz := floori(chunk_world_max_z / type_cell_size)
		
		var transforms: Array[Transform3D] = []
		
		for cx in range(min_cx, max_cx + 1):
			for cz in range(min_cz, max_cz + 1):
				var center_x := (float(cx) + 0.5) * type_cell_size
				var center_z := (float(cz) + 0.5) * type_cell_size
				
				# Чанк обрабатывает только те ячейки, чей центр попадает строго в его границы.
				# Это предотвращает дублирование объектов на стыках соседних чанков.
				if center_x < chunk_world_min_x or center_x >= chunk_world_max_x:
					continue
				if center_z < chunk_world_min_z or center_z >= chunk_world_max_z:
					continue
				
				# 1. Проверка маски спавна (собственный шум объекта или лесной покров по умолчанию)
				var spawn_weight := get_spawn_weight_for_item(item, Vector2(center_x, center_z))
				if spawn_weight <= 0.05:
					continue
				
				# 2. Детерминированный хэш и бросок вероятности появления
				var h := get_cell_hash(cx, cz, type_seed)
				var spawn_roll := hash_to_float(h, 0)
				if spawn_roll > (spawn_weight * item.density_multiplier):
					continue
				
				# 3. Случайное смещение (jitter) строго в пределах ячейки
				var offset_x_pos := (hash_to_float(h, 1) * 2.0 - 1.0) * max_offset
				var offset_z_pos := (hash_to_float(h, 2) * 2.0 - 1.0) * max_offset
				var world_x := center_x + offset_x_pos
				var world_z := center_z + offset_z_pos
				
				var pos2d := Vector2(world_x, world_z)
				var h_center := get_point_height(pos2d)
				
				# Объекты не растут под водой
				if h_center <= water_level:
					continue
				
				# 4. Индивидуальная проверка крутизны склона (если включена)
				if item.check_slope:
					var step := 0.5
					var h_dx := (get_point_height(Vector2(world_x + step, world_z)) - get_point_height(Vector2(world_x - step, world_z))) / (2.0 * step) * height_scale
					var h_dz := (get_point_height(Vector2(world_x, world_z + step)) - get_point_height(Vector2(world_x, world_z - step))) / (2.0 * step) * height_scale
					var slope_tan := sqrt(h_dx * h_dx + h_dz * h_dz)
					var slope_deg := rad_to_deg(atan(slope_tan))
					if slope_deg > item.max_slope:
						continue
				
				# 5. Быстрая проверка коллизий по локальному массиву без обращения к шуму!
				if item.check_collisions and not local_obstacles.is_empty():
					var collided := false
					var r_item := item.footprint_radius
					for obs in local_obstacles:
						var dx := world_x - obs.x
						var dz := world_z - obs.y
						var min_dist := r_item + obs.z
						if (dx * dx + dz * dz) < (min_dist * min_dist):
							collided = true
							break
					if collided:
						continue
				
				# Если объект является препятствием — заносим его в массив для последующих объектов
				if item.is_obstacle:
					local_obstacles.append(Vector3(world_x, world_z, item.footprint_radius))
				
				# 6. Высота точки посадки с учетом микрорельефа
				var world_y := h_center * height_scale + get_micro_height(pos2d)
				
				# 7. Случайный поворот вокруг оси Y и вариация масштаба
				var rot_y := hash_to_float(h, 3) * TAU
				var scale_factor := lerpf(item.scale_min, item.scale_max, hash_to_float(h, 4))
				
				# Локальная позиция объекта внутри чанка
				var local_pos := Vector3(
					world_x - chunk_world_min_x,
					world_y,
					world_z - chunk_world_min_z
				)
				
				# Корректировка опоры для затычки (BoxMesh)
				if item.mesh == null:
					var trunk_height := item.footprint_radius * 1.2
					local_pos.y += (trunk_height * 0.5) * scale_factor
				
				var t := Transform3D()
				t = t.scaled(Vector3(scale_factor, scale_factor, scale_factor))
				t = t.rotated(Vector3.UP, rot_y)
				t.origin = local_pos
				
				transforms.append(t)
		
		if not transforms.is_empty():
			result.append({
				"item": item,
				"transforms": transforms
			})
			
	return {
		"objects": result,
		"obstacles": local_obstacles
	}

func generate_single_chunk(index : int):
	if cancel_generation:
		return
	
	var c : Vector2 = current_coords[index]
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var chunk_noise_x := chunk_size * cell_size * c.x
	var chunk_noise_z := chunk_size * cell_size * c.y
	
	for x in range(chunk_size):
		for z in range(chunk_size):
			var pos00 := Vector2(chunk_noise_x + x * cell_size, chunk_noise_z + z * cell_size)
			var h00 := get_point_height(pos00)
			var p00 := Vector3(x * cell_size, h00 * height_scale + get_micro_height(pos00), z * cell_size)
			var c00 := get_point_color(pos00, h00)

			var pos01 := Vector2(chunk_noise_x + x * cell_size, chunk_noise_z + (z + 1) * cell_size)
			var h01 := get_point_height(pos01)
			var p01 := Vector3(x * cell_size, h01 * height_scale + get_micro_height(pos01), (z + 1) * cell_size)
			var c01 := get_point_color(pos01, h01)

			var pos10 := Vector2(chunk_noise_x + (x + 1) * cell_size, chunk_noise_z + z * cell_size)
			var h10 := get_point_height(pos10)
			var p10 := Vector3((x + 1) * cell_size, h10 * height_scale + get_micro_height(pos10), z * cell_size)
			var c10 := get_point_color(pos10, h10)

			var pos11 := Vector2(chunk_noise_x + (x + 1) * cell_size, chunk_noise_z + (z + 1) * cell_size)
			var h11 := get_point_height(pos11)
			var p11 := Vector3((x + 1) * cell_size, h11 * height_scale + get_micro_height(pos11), (z + 1) * cell_size)
			var c11 := get_point_color(pos11, h11)
			
			var color_tri1 = (c00 + c10 + c01) / 3.0
			var n1 = (p01 - p00).cross(p10 - p00).normalized()
			st.set_normal(n1); st.set_color(color_tri1); st.add_vertex(p00)
			st.set_normal(n1); st.set_color(color_tri1); st.add_vertex(p10)
			st.set_normal(n1); st.set_color(color_tri1); st.add_vertex(p01)

			var color_tri2 = (c10 + c11 + c01) / 3.0
			var n2 = (p01 - p10).cross(p11 - p10).normalized()
			st.set_normal(n2); st.set_color(color_tri2); st.add_vertex(p10)
			st.set_normal(n2); st.set_color(color_tri2); st.add_vertex(p11)
			st.set_normal(n2); st.set_color(color_tri2); st.add_vertex(p01)
			
	var mesh := st.commit()
	var grid_data := generate_grid_objects(c)
	var chunk_objects : Array = grid_data["objects"]
	var local_obstacles : Array = grid_data["obstacles"]
	
	var terrain_img : Image = null
	if enable_grass:
		terrain_img = generate_chunk_terrain_image(c, local_obstacles)
		
	call_deferred("spawn_chunk", c, mesh, chunk_objects, terrain_img)

func spawn_chunk(pos_of_chunk : Vector2, mesh_data: ArrayMesh, chunk_objects : Array = [], terrain_img : Image = null) -> void:
	var chunk_node = MeshInstance3D.new()
	chunk_node.mesh = mesh_data
	
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true

	chunk_node.material_override = mat
	
	# =========================================================================
	# СПАВН ОБЪЕКТОВ ЧЕРЕЗ MULTIMESH
	# Для каждого активного типа объекта создаётся отдельный MultiMeshInstance3D.
	# Все объекты одного типа рендерятся за 1 GPU draw call с максимальным FPS.
	# =========================================================================
	for entry in chunk_objects:
		var item : SpawnableItem = entry["item"]
		var transforms : Array = entry["transforms"]
		if transforms.is_empty():
			continue
		
		var mm_inst := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = transforms.size()
		
		# Если mesh задан в SpawnableItem — используем реальную 3D-модель,
		# иначе процедурную заглушку (BoxMesh).
		if item.mesh != null:
			mm.mesh = item.mesh
		else:
			mm.mesh = get_placeholder_mesh(item)
		
		for i in range(transforms.size()):
			mm.set_instance_transform(i, transforms[i])
		
		mm_inst.multimesh = mm
		chunk_node.add_child(mm_inst)
	
	# =========================================================================
	# СПАВН ТРАВЫ ЧЕРЕЗ GPU-КОВЁР
	# Единый шаблонный MultiMesh на Y=0 поднимается и маскируется шейдером
	# =========================================================================
	if enable_grass and terrain_img != null:
		var grass_mm_inst := MultiMeshInstance3D.new()
		grass_mm_inst.multimesh = get_shared_grass_multimesh()
		
		var base_mat : ShaderMaterial = grass_material
		if base_mat == null:
			var default_mat_path := "res://materials/grass_material.tres"
			if ResourceLoader.exists(default_mat_path):
				base_mat = load(default_mat_path)
		
		if base_mat != null:
			var mat_inst := base_mat.duplicate() as ShaderMaterial
			var tex := ImageTexture.create_from_image(terrain_img)
			mat_inst.set_shader_parameter("terrain_data", tex)
			mat_inst.set_shader_parameter("chunk_size_world", chunk_size * cell_size)
			grass_mm_inst.material_override = mat_inst
			
		chunk_node.add_child(grass_mm_inst)
	
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
