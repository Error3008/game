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

@export_group("Enemies (временный простой спавн)")
## Рыцари, случайно разбросанные по всем сгенерированным чанкам (кроме зоны вокруг игрока). Заглушка до этапа 5.
@export var spawn_enemies : bool = true
@export var enemy_scene : PackedScene = preload("res://scenes/enemy.tscn")
@export var enemy_count : int = 10
## Радиус вокруг игрока, в котором враги не спавнятся (защита от ранних нападений).
@export var enemy_min_distance : float = 15.0
## Ставить ли игрока на землю после генерации (до этого он заморожен, чтобы не падать в пустоту).
@export var place_player_on_ground : bool = true
## Максимальный угол склона (градусы) для точки спавна игрока/врага.
@export var spawn_max_slope : float = 30.0
## Минимальная высота над водой (в метрах), ниже — не спавним.
@export var spawn_min_height : float = 1.0

## Высота цилиндра, если у объекта нет меша (м). Обычно высота берётся по AABB меша * масштаб.
## Метка на StaticBody3D стволов: лучи спавна пропускают такие тела (см. _ground_point).
const TRUNK_BODY_META : StringName = &"is_trunk_body"
const TRUNK_COLLISION_HEIGHT_FALLBACK : float = 6.0
## Насколько цилиндр ствола уходит под землю (м), чтобы на склоне не было щели у основания.
const TRUNK_COLLISION_SINK : float = 1.0

## Радиус и высота центра сферы проверки "не в стволе" при спавне игрока/врага (м).
const SPAWN_CLEARANCE_RADIUS : float = 0.5
const SPAWN_CLEARANCE_HEIGHT : float = 1.2
## Поиск места для игрока спиралью вокруг стартовой точки: радиус и шаг (м).
const PLAYER_SPAWN_SEARCH_RADIUS : float = 80.0
const PLAYER_SPAWN_SEARCH_STEP : float = 4.0

const ENEMY_BUILDS : Array[String] = [
	"res://resources/stats/enemy_armored.tres",
	"res://resources/stats/enemy_agile.tres",
	"res://resources/stats/enemy_balanced.tres",
]
const ENEMY_PERSONALITIES : Array[String] = [
	"res://resources/ai/personality_duelist.tres",
	"res://resources/ai/personality_bully.tres",
	"res://resources/ai/personality_turtle.tres",
]

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
## Дистанция LOD, за которой трава не рендерится (в метрах). 0 = без ограничений.
@export var grass_lod_distance : float = 60.0
## Сколько чанков травы загружать на GPU за один кадр. 1 = плавнее, 2-3 = быстрее.
@export var grass_uploads_per_frame : int = 1
## Сколько чанков геометрии добавлять в сцену за один кадр.
## 1 = максимально плавно, 2-3 = быстрее появление мира.
@export var spawn_chunks_per_frame : int = 2

var current_coords: Array

var task_id: int = -1
var cancel_generation: bool = false
# Кэш заглушек-мешей: spacing_radius -> BoxMesh (создаётся по первому запросу)
var _placeholder_meshes: Dictionary = {}
# Копия spawnable_items, отсортированная по убыванию spacing_radius.
# Заполняется один раз в generate_chunks() до старта потоков; потоки читают только.
var _sorted_spawnable_items: Array = []
# Кэшированные ресурсы травы для безопасного чтения рабочими потоками без обращений к ResourceLoader
var _cached_grass_mesh : Mesh
var _cached_grass_material : ShaderMaterial

# Очередь отложенной загрузки травы: каждый элемент — словарь с данными одного чанка.
# Обрабатывается по grass_uploads_per_frame элементов за кадр в _process(),
# чтобы связывание нод и создание текстур происходило плавно.
var _grass_upload_queue : Array[Dictionary] = []

# Очередь отложенного добавления чанков геометрии в сцену.
# Заполняется из фоновых потоков через _enqueue_chunk (call_deferred).
# Обрабатывается по spawn_chunks_per_frame штук за кадр в _process().
var _chunk_spawn_queue : Array[Dictionary] = []

# task_id генерации, которую нужно дождаться перед очисткой (неблокирующий polling).
# -1 = нет ожидающей задачи.
## Печатать статистику коллизии стволов (число стволов на чанк, время блока в spawn_chunk, размер кэша шейпов).
@export var debug_trunk_stats : bool = false
var _dbg_chunks : int = 0
var _dbg_trunks_total : int = 0
var _dbg_trunks_max : int = 0
var _dbg_usec_total : int = 0
var _dbg_usec_max : int = 0
# Общие CylinderShape3D для стволов: ключ = Vector2i(радиус в 0.1 м, высота в 0.5 м). Только основной поток.
var _trunk_shape_cache : Dictionary = {}
var _enemies_pending : bool = false
var _spawned_enemies : Array[Node] = []
var _held_player : Node = null  # заморожен до готовности земли

var _pending_clear_task_id : int = -1
var _waiting_to_clear : bool = false

func _ready() -> void:
	if not Engine.is_editor_hint():
		_hold_player()
		generate_chunks()

func _process(_delta: float) -> void:
	# --- Неблокирующее ожидание завершения старой генерации перед очисткой ---
	# Вместо wait_for_group_task_completion (полный фриз) проверяем готовность
	# каждый кадр. Как только старые потоки финишировали — чистим сцену и стартуем заново.
	if _waiting_to_clear and _pending_clear_task_id != -1:
		if WorkerThreadPool.is_group_task_completed(_pending_clear_task_id):
			_pending_clear_task_id = -1
			_waiting_to_clear = false
			_do_clear_chunks()
			_do_start_generation()
		return  # Пока ждём — ничего больше не трогаем
	
	# --- Отложенная загрузка травы на GPU (по N чанков за кадр) ---
	# ImageTexture.create_from_image() и build_grass_multimesh() вызываются здесь,
	# а не в spawn_chunk(), чтобы не блокировать фрейм разом для всех чанков.
	var uploads_done := 0
	while not _grass_upload_queue.is_empty() and uploads_done < grass_uploads_per_frame:
		var entry : Dictionary = _grass_upload_queue.pop_front()
		_upload_grass_chunk(entry)
		uploads_done += 1

	# --- Отложенный спавн чанков геометрии (по N за кадр) ---
	# MeshInstance3D и MultiMeshInstance3D добавляются в сцену порционно,
	# чтобы не создавать пик нагрузки когда весь батч потоков завершается разом.
	var spawns_done := 0
	while not _chunk_spawn_queue.is_empty() and spawns_done < spawn_chunks_per_frame:
		var entry : Dictionary = _chunk_spawn_queue.pop_front()
		spawn_chunk(entry["pos"], entry["mesh"], entry["objects"], entry["terrain"], entry.get("col_shape", null))
		spawns_done += 1

	# --- Простой спавн врагов: когда все чанки появились (коллайдеры уже есть) ---
	if _enemies_pending and task_id != -1 and _chunk_spawn_queue.is_empty() \
			and WorkerThreadPool.is_group_task_completed(task_id):
		_enemies_pending = false
		# Ждём физический шаг: только что добавленные коллайдеры чанков могут стать видны лучам не сразу.
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		_place_player_on_ground()
		_spawn_enemies_around_player()

## Замораживает игрока до готовности земли: иначе он падает с y≈45 в пустоту, пока нет коллайдера.
func _hold_player() -> void:
	if not place_player_on_ground:
		return
	_held_player = get_tree().get_first_node_in_group("player")
	if _held_player != null:
		_held_player.process_mode = Node.PROCESS_MODE_DISABLED

func _release_player() -> void:
	if is_instance_valid(_held_player):
		_held_player.process_mode = Node.PROCESS_MODE_INHERIT
	_held_player = null

## Сфера-проверка "не в стволе" (см. _ground_point).
func _make_clearance_query() -> PhysicsShapeQueryParameters3D:
	var clearance := SphereShape3D.new()
	clearance.radius = SPAWN_CLEARANCE_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = clearance
	query.collision_mask = 1
	return query

## Подходящая точка на земле для спавна в мировых (x, z) или null.
## Луч вниз по коллизии рельефа (слой 1), затем фильтры: вода/пляж, крутой склон,
## и сфера над землёй — на слое 1 с ней может пересечься только ствол (или будущее препятствие).
func _ground_point(space: PhysicsDirectSpaceState3D, x: float, z: float,
		clearance_query: PhysicsShapeQueryParameters3D) -> Variant:
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -100.0, z), 1)
	var hit := space.intersect_ray(query)
	# Луч сверху может попасть в верхнюю крышку цилиндра ствола (у деревьев конечная высота) —
	# тогда пропускаем это тело и ищем дальше вниз настоящую землю.
	var excluded : Array[RID] = []
	while not hit.is_empty() and (hit["collider"] as Object).has_meta(TRUNK_BODY_META) and excluded.size() < 8:
		excluded.append(hit["rid"])
		query.exclude = excluded
		hit = space.intersect_ray(query)
	if hit.is_empty():
		return null # за пределами сгенерированной области
	var pos : Vector3 = hit["position"]
	if pos.y < spawn_min_height or (hit["normal"] as Vector3).y < cos(deg_to_rad(spawn_max_slope)):
		return null # вода/пляж или крутой склон
	clearance_query.transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP * SPAWN_CLEARANCE_HEIGHT)
	if not space.intersect_shape(clearance_query, 1).is_empty():
		return null # внутри ствола или вплотную к нему
	return pos

## Ставит игрока на ближайшую подходящую точку к его стартовым (x, z) спиралью наружу и размораживает.
## Если подходящей точки нет — размораживает на месте (с предупреждением), чтобы игра не зависла.
func _place_player_on_ground() -> void:
	var player := _held_player as Node3D
	if Engine.is_editor_hint() or player == null or not is_instance_valid(player):
		_release_player()
		return
	var space := get_world_3d().direct_space_state
	var clearance_query := _make_clearance_query()
	var origin := player.global_position
	var found : Variant = null
	var radius := 0.0
	while found == null and radius <= PLAYER_SPAWN_SEARCH_RADIUS:
		var steps := 1 if radius == 0.0 else 12
		for i in steps:
			var angle := TAU * float(i) / float(steps)
			found = _ground_point(space, origin.x + cos(angle) * radius, origin.z + sin(angle) * radius, clearance_query)
			if found != null:
				break
		radius += PLAYER_SPAWN_SEARCH_STEP
	if found == null:
		push_warning("world_generation: не нашли землю для игрока в радиусе %.0f м, оставляем на месте." % PLAYER_SPAWN_SEARCH_RADIUS)
	else:
		player.global_position = (found as Vector3) + Vector3.UP * 0.2
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO
	_release_player()

## Временная заглушка: случайные точки по всем сгенерированным чанкам (кроме зоны вокруг игрока).
func _spawn_enemies_around_player() -> void:
	if Engine.is_editor_hint() or not spawn_enemies or enemy_scene == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	_free_spawned_enemies()
	
	var space := get_world_3d().direct_space_state
	var center := player.global_position
	var clearance_query := _make_clearance_query()
	
	# Границы всех сгенерированных чанков в локальных координатах этого узла.
	var chunk_world_size := chunk_size * cell_size
	var min_c := Vector2(INF, INF)
	var max_c := Vector2(-INF, -INF)
	for c: Vector2 in current_coords:
		min_c = min_c.min(c)
		max_c = max_c.max(c)
	var area_min := min_c * chunk_world_size
	var area_max := (max_c + Vector2.ONE) * chunk_world_size
	
	var spawned := 0
	for attempt in enemy_count * 30:
		if spawned >= enemy_count:
			break
		var local_xz := Vector2(randf_range(area_min.x, area_max.x), randf_range(area_min.y, area_max.y))
		var world_xz := to_global(Vector3(local_xz.x, 0.0, local_xz.y))
		if Vector2(world_xz.x - center.x, world_xz.z - center.z).length() < enemy_min_distance:
			continue # слишком близко к игроку
		var pos : Variant = _ground_point(space, world_xz.x, world_xz.z, clearance_query)
		if pos == null:
			continue
		
		var enemy := enemy_scene.instantiate() as Node3D
		enemy.set("stats", load(ENEMY_BUILDS.pick_random()))
		enemy.set("personality", load(ENEMY_PERSONALITIES.pick_random()))
		add_child(enemy)
		enemy.global_position = (pos as Vector3) + Vector3.UP * 0.2
		# Тело НЕ вращаем: cmd_face_point считает угол как мировой для $pawn.
		var pawn := enemy.get_node_or_null("pawn") as Node3D
		if pawn != null:
			pawn.rotation.y = randf() * TAU
		_spawned_enemies.append(enemy)
		spawned += 1
	if spawned < enemy_count:
		push_warning("world_generation: заспавнено %d из %d врагов (мало подходящих точек)." % [spawned, enemy_count])

## Общий цилиндр для ствола: размеры округляются (радиус до 0.1 м, высота до 0.5 м), чтобы вместо
## сотен одинаковых ресурсов было несколько штук. Вызывать только из основного потока.
func _get_trunk_shape(radius: float, height: float) -> CylinderShape3D:
	var key := Vector2i(maxi(1, roundi(radius * 10.0)), maxi(1, roundi(height * 2.0)))
	var shape := _trunk_shape_cache.get(key) as CylinderShape3D
	if shape == null:
		shape = CylinderShape3D.new()
		shape.radius = key.x * 0.1
		shape.height = key.y * 0.5
		_trunk_shape_cache[key] = shape
	return shape

func _free_spawned_enemies() -> void:
	for e in _spawned_enemies:
		if is_instance_valid(e):
			e.queue_free()
	_spawned_enemies.clear()

func _upload_grass_chunk(entry: Dictionary) -> void:
	var chunk_node : MeshInstance3D = entry["chunk_node"]
	# Нода могла быть удалена если был вызов clear во время ожидания
	if not is_instance_valid(chunk_node) or chunk_node.is_queued_for_deletion():
		return
	
	var terrain_img      : Image          = entry["terrain_img"]
	var min_h            : float          = entry["min_h"]
	var max_h            : float          = entry["max_h"]
	var chunk_world_size : float          = entry["chunk_world_size"]
	var grass_mm         : MultiMesh      = entry["grass_multimesh"]
	var base_mat         : ShaderMaterial = entry["base_mat"]
	var chunk_world_pos  : Vector2        = entry["chunk_world_pos"]
	
	var grass_mm_inst := MultiMeshInstance3D.new()
	# MultiMesh геометрия уже полностью собрана в фоновом потоке — присваиваем мгновенно!
	grass_mm_inst.multimesh = grass_mm
	
	# AABB: Y по фактическим высотам, X/Z с запасом на jitter и scale_rnd
	var margin_below := 1.0
	var margin_above := 2.0
	var margin_xz    := 2.0
	grass_mm_inst.custom_aabb = AABB(
		Vector3(-margin_xz, min_h - margin_below, -margin_xz),
		Vector3(
			chunk_world_size + margin_xz * 2.0,
			(max_h + margin_above) - (min_h - margin_below),
			chunk_world_size + margin_xz * 2.0
		)
	)
	
	# LOD отсечение
	if grass_lod_distance > 0.0:
		grass_mm_inst.visibility_range_end = grass_lod_distance
		grass_mm_inst.visibility_range_end_margin = 5.0
	
	if base_mat != null:
		var mat_inst := base_mat.duplicate() as ShaderMaterial
		var tex := ImageTexture.create_from_image(terrain_img)
		mat_inst.set_shader_parameter("terrain_data", tex)
		mat_inst.set_shader_parameter("chunk_size_world", chunk_world_size)
		mat_inst.set_shader_parameter("chunk_world_pos", chunk_world_pos)
		grass_mm_inst.material_override = mat_inst
	
	chunk_node.add_child(grass_mm_inst)

func build_grass_multimesh(seed: int) -> MultiMesh:
	var chunk_world_size := chunk_size * cell_size
	var mesh_to_use : Mesh = _cached_grass_mesh
	if mesh_to_use == null:
		mesh_to_use = grass_mesh
	if mesh_to_use == null:
		var default_mesh_path := "res://meshes/grass.res"
		if ResourceLoader.exists(default_mesh_path):
			mesh_to_use = load(default_mesh_path)
	if mesh_to_use == null:
		var quad := QuadMesh.new()
		quad.size = Vector2(0.5, 0.6)
		mesh_to_use = quad
	
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh_to_use
	
	var step := maxf(0.15, grass_density_step)
	var steps_count := int(ceil(chunk_world_size / step))
	var count := steps_count * steps_count
	mm.instance_count = count
	
	# PackedFloat32Array: 12 float на инстанс (матрица Transform3D = BASIS(9) + ORIGIN(3)).
	# Собирается целиком в фоновом потоке WorkerThreadPool.
	var buf := PackedFloat32Array()
	buf.resize(count * 12)
	
	var idx := 0
	for ix in range(steps_count):
		for iz in range(steps_count):
			var base_x := (float(ix) + 0.5) * step
			var base_z := (float(iz) + 0.5) * step
			
			# Сид зависит от координат чанка: распределение травы уникально
			var h := get_cell_hash(ix, iz, seed)
			var jitter_x := (hash_to_float(h, 0) * 2.0 - 1.0) * (step * 0.4)
			var jitter_z := (hash_to_float(h, 1) * 2.0 - 1.0) * (step * 0.4)
			var rot_y := hash_to_float(h, 2) * TAU
			var scale_rnd := lerpf(0.85, 1.2, hash_to_float(h, 3))
			
			var x := clampf(base_x + jitter_x, 0.0, chunk_world_size)
			var z := clampf(base_z + jitter_z, 0.0, chunk_world_size)
			
			# Строим матрицу Transform3D вручную: поворот Y * масштаб XZ
			var cos_r := cos(rot_y)
			var sin_r := sin(rot_y)
			var base_offset := idx * 12
			
			# Строка 0: X-координаты базиса + Origin.x
			buf[base_offset + 0] = cos_r * scale_rnd  # X.x
			buf[base_offset + 1] = 0.0                # Y.x
			buf[base_offset + 2] = sin_r * scale_rnd  # Z.x
			buf[base_offset + 3] = x                  # Позиция X
			
			# Строка 1: Y-координаты базиса + Origin.y
			buf[base_offset + 4] = 0.0                # X.y
			buf[base_offset + 5] = 1.0                # Y.y
			buf[base_offset + 6] = 0.0                # Z.y
			buf[base_offset + 7] = 0.0                # Позиция Y (шейдер сам поднимет)
			
			# Строка 2: Z-координаты базиса + Origin.z
			buf[base_offset + 8] = -sin_r * scale_rnd # X.z
			buf[base_offset + 9] = 0.0                # Y.z
			buf[base_offset + 10] = cos_r * scale_rnd # Z.z
			buf[base_offset + 11] = z                 # Позиция Z
			
			idx += 1
	
	mm.buffer = buf
	return mm


func get_placeholder_mesh(item: SpawnableItem) -> Mesh:
	# Заглушки кэшируются по spacing_radius — каждый уникальный размер создаётся один раз.
	var key := item.spacing_radius
	if _placeholder_meshes.has(key):
		return _placeholder_meshes[key]
	
	# Пропорциональный прямоугольник с коричневым материалом
	var width := item.spacing_radius * 0.4
	var height := item.spacing_radius * 1.2
	
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

## Билинейная интерполяция значения из кэша высот чанка.
## local_x / local_z — координаты в локальном пространстве чанка (0 .. chunk_size * cell_size).
## gs — grid_size (chunk_size + 1).
func _bilerp_cache(cache: Array[float], local_x: float, local_z: float, gs: int) -> float:
	var fx := local_x / cell_size
	var fz := local_z / cell_size
	var xi := clampi(floori(fx), 0, gs - 2)
	var zi := clampi(floori(fz), 0, gs - 2)
	var tx := clampf(fx - float(xi), 0.0, 1.0)
	var tz := clampf(fz - float(zi), 0.0, 1.0)
	var h00 := cache[xi * gs + zi]
	var h10 := cache[(xi + 1) * gs + zi]
	var h01 := cache[xi * gs + (zi + 1)]
	var h11 := cache[(xi + 1) * gs + (zi + 1)]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


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
	# Сигнализируем потокам остановиться
	cancel_generation = true
	# Сбрасываем очереди — данные от старой генерации больше не нужны
	_grass_upload_queue.clear()
	_chunk_spawn_queue.clear()
	
	if task_id != -1:
		if WorkerThreadPool.is_group_task_completed(task_id):
			# Потоки уже завершились — чистим немедленно
			task_id = -1
			_do_clear_chunks()
		else:
			# Потоки ещё работают — запоминаем id и ждём в _process без блокировки
			_pending_clear_task_id = task_id
			task_id = -1
			_waiting_to_clear = true
	else:
		_do_clear_chunks()

func _do_clear_chunks() -> void:
	_free_spawned_enemies()
	# Фактическое удаление чанков — вызывается только когда потоки точно завершены
	var removed := 0
	for child in get_children():
		if child is MeshInstance3D:
			child.free()
			removed += 1
	print("Cleared generated chunks: ", removed)

func generate_chunks():
	# Подготовка списка объектов (потокобезопасно читается потоками)
	_sorted_spawnable_items = []
	if spawnable_items != null:
		for it in spawnable_items:
			if it != null:
				_sorted_spawnable_items.append(it)

	# Если список пуст — создаём дефолтный тип-заглушку для работы «из коробки»
	if _sorted_spawnable_items.is_empty():
		var default_item := SpawnableItem.new()
		default_item.name = "Default Tree"
		default_item.spacing_radius = 2.5
		default_item.trunk_radius = 0.5
		default_item.density_multiplier = 0.85
		default_item.scale_min = 0.8
		default_item.scale_max = 1.3
		default_item.check_slope = true
		default_item.max_slope = 35.0
		default_item.check_collisions = true
		default_item.is_obstacle = true
		_sorted_spawnable_items.append(default_item)
	else:
		_sorted_spawnable_items.sort_custom(func(a: SpawnableItem, b: SpawnableItem): return a.spacing_radius > b.spacing_radius)
	
	# Предзагрузка заглушек для потокобезопасного доступа в WorkerThreadPool
	for it in _sorted_spawnable_items:
		if it.mesh == null:
			get_placeholder_mesh(it)
			
	# Предзагрузка ресурсов травы в основном потоке для исключения обращений к ResourceLoader из фоновых потоков
	_cached_grass_mesh = grass_mesh
	if _cached_grass_mesh == null:
		var default_mesh_path := "res://meshes/grass.res"
		if ResourceLoader.exists(default_mesh_path):
			_cached_grass_mesh = load(default_mesh_path)
	if _cached_grass_mesh == null:
		var quad := QuadMesh.new()
		quad.size = Vector2(0.5, 0.6)
		_cached_grass_mesh = quad
		
	_cached_grass_material = grass_material
	if _cached_grass_material == null:
		var default_mat_path := "res://materials/grass_material.tres"
		if ResourceLoader.exists(default_mat_path):
			_cached_grass_material = load(default_mat_path)
	
	# Предварительное выпекание кэша всех Curve в основном потоке,
	# чтобы исключить гонку потоков (data race) при первом sample_baked()
	if plains_curve:
		plains_curve.bake()
	if hills_curve:
		hills_curve.bake()
	if hills_inland_curve:
		hills_inland_curve.bake()
	if forest_curve:
		forest_curve.bake()
	for it in _sorted_spawnable_items:
		if it and it.spawn_curve:
			it.spawn_curve.bake()
	
	# Сначала очищаем старые чанки (возможно асинхронно), потом стартуем
	if task_id != -1:
		# Старая генерация ещё идёт — откладываем, _process запустит после завершения
		cancel_generation = true
		_grass_upload_queue.clear()
		_pending_clear_task_id = task_id
		task_id = -1
		_waiting_to_clear = true
	else:
		_do_clear_chunks()
		_do_start_generation()

func _do_start_generation() -> void:
	var pos_of_chunk := get_chunk_coords(generate_point)
	current_coords = get_chunk_coords_in_radius(pos_of_chunk, generate_radius)
	global_position = Vector3(-generate_point.x, 0, -generate_point.y)
	
	cancel_generation = false
	task_id = WorkerThreadPool.add_group_task(generate_single_chunk, current_coords.size())
	_enemies_pending = true

## heights_cache — финальные высоты (h*scale + micro), raw_h_cache — «сырые» (до scale, для water_level).
## Оба кэша имеют размер grid_size*grid_size, где grid_size = chunk_size + 1.
func generate_chunk_terrain_image(c : Vector2, local_obstacles : Array,
		heights_cache : Array[float], raw_h_cache : Array[float], cache_gs : int) -> Dictionary:
	var chunk_world_size := chunk_size * cell_size
	var chunk_world_min_x := c.x * chunk_world_size
	var chunk_world_min_z := c.y * chunk_world_size

	var step := maxf(0.05, grass_texture_step)
	var tex_size := clampi(int(round(chunk_world_size / step)), 16, 256)

	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGF)

	# Диапазон фактических высот рельефа чанка — нужен для плотного
	# custom_aabb травы (см. spawn_chunk)
	var min_h := INF
	var max_h := -INF

	# slope_step в локальных единицах чанка (0.5 м, как было раньше)
	var slope_step := 0.5

	# 1. Заполняем рельеф и базовую маску уклона/воды.
	# Высоты берём из кэша через билинейную интерполяцию —
	# get_point_height() и get_micro_height() больше не вызываются.
	for px in range(tex_size):
		for py in range(tex_size):
			# Edge-aligned UV: первый пиксель строго на u=0.0, последний на u=1.0.
			# Устраняет half-texel смещение, из-за которого края чанка читали
			# шейдером смещённые высоты и маски.
			var u := float(px) / float(tex_size - 1)
			var v := float(py) / float(tex_size - 1)
			var local_x := u * chunk_world_size
			var local_z := v * chunk_world_size

			# Финальная высота (с масштабом и микрорельефом) из кэша
			var world_y := _bilerp_cache(heights_cache, local_x, local_z, cache_gs)
			# Сырая высота для проверки water_level
			var raw := _bilerp_cache(raw_h_cache, local_x, local_z, cache_gs)

			if world_y < min_h:
				min_h = world_y
			if world_y > max_h:
				max_h = world_y

			var mask := 1.0
			if raw <= water_level:
				mask = 0.0
			else:
				# Уклон через конечные разности из кэша — без вызова шумов
				var h_dx := (_bilerp_cache(heights_cache, local_x + slope_step, local_z, cache_gs)
						   - _bilerp_cache(heights_cache, local_x - slope_step, local_z, cache_gs)) \
						   / (2.0 * slope_step)
				var h_dz := (_bilerp_cache(heights_cache, local_x, local_z + slope_step, cache_gs)
						   - _bilerp_cache(heights_cache, local_x, local_z - slope_step, cache_gs)) \
						   / (2.0 * slope_step)
				var slope_deg := rad_to_deg(atan(sqrt(h_dx * h_dx + h_dz * h_dz)))
				mask = clampf(1.0 - smoothstep(grass_max_slope - 6.0, grass_max_slope, slope_deg), 0.0, 1.0)

			img.set_pixel(px, py, Color(world_y, mask, 0.0, 1.0))

	# 2. Штампуем препятствия (деревья, валуны) в маску травы с плавным затуханием.
	# Координаты пикселей согласованы с edge-aligned UV (tex_size - 1), без half-texel сдвига.
	var tex_coord_scale := float(tex_size - 1) / chunk_world_size
	for obs in local_obstacles:
		var obs_x : float = obs.x
		var obs_z : float = obs.y
		var obs_radius : float = obs.z

		var center_px := (obs_x - chunk_world_min_x) * tex_coord_scale
		var center_py := (obs_z - chunk_world_min_z) * tex_coord_scale
		var r_px := obs_radius * tex_coord_scale

		var min_px := clampi(int(floor(center_px - r_px - 1.0)), 0, tex_size - 1)
		var max_px := clampi(int(ceil(center_px + r_px + 1.0)), 0, tex_size - 1)
		var min_py := clampi(int(floor(center_py - r_px - 1.0)), 0, tex_size - 1)
		var max_py := clampi(int(ceil(center_py + r_px + 1.0)), 0, tex_size - 1)

		var inner_r_px := r_px * 0.6

		for px in range(min_px, max_px + 1):
			for py in range(min_py, max_py + 1):
				var dx := float(px) - center_px
				var dy := float(py) - center_py
				var dist := sqrt(dx * dx + dy * dy)

				if dist < r_px:
					var fade := clampf((dist - inner_r_px) / maxf(0.001, r_px - inner_r_px), 0.0, 1.0)
					var col := img.get_pixel(px, py)
					img.set_pixel(px, py, Color(col.r, col.g * fade, 0.0, 1.0))

	return {
		"image": img,
		"min_height": min_h if min_h != INF else 0.0,
		"max_height": max_h if max_h != -INF else 0.0,
	}

func generate_grid_objects(c : Vector2) -> Dictionary:
	var result: Array = []
	
	var chunk_world_size := chunk_size * cell_size
	var chunk_world_min_x := c.x * chunk_world_size
	var chunk_world_max_x := (c.x + 1) * chunk_world_size
	var chunk_world_min_z := c.y * chunk_world_size
	var chunk_world_max_z := (c.y + 1) * chunk_world_size
	
	# Кандидаты объектов, прошедшие проверку в зоне выборки чанка (включая halo).
	# Используются для детерминированной проверки коллизий между объектами без швов.
	var placed_candidates: Array[Dictionary] = []
	# Препятствия для маски травы: Vector3(x, z, trunk_radius * scale).
	# Включают деревья из halo-зоны соседей, чьи стволы перекрывают край текущего чанка.
	var grass_obstacles: Array[Vector3] = []
	
	for ti in range(_sorted_spawnable_items.size()):
		var item : SpawnableItem = _sorted_spawnable_items[ti]
		var type_seed := spawn_seed + ti
		var type_spacing := item.spacing_radius
		var type_trunk := item.trunk_radius
		var type_cell_size := type_spacing * 2.0
		var max_offset := type_spacing * 0.72
		
		# Динамический радиус охвата за пределы границ чанка:
		# Учитывает максимальное смещение и радиус влияния (коллизия крон / ствол).
		# Гарантирует покрытие при любых нестандартных радиусах объектов.
		var max_reach := max_offset + maxf(type_spacing, type_trunk)
		var min_cx := floori((chunk_world_min_x - max_reach) / type_cell_size)
		var max_cx := ceili((chunk_world_max_x + max_reach) / type_cell_size)
		var min_cz := floori((chunk_world_min_z - max_reach) / type_cell_size)
		var max_cz := ceili((chunk_world_max_z + max_reach) / type_cell_size)
		
		var transforms: Array[Transform3D] = []
		# Стволы для коллизии: Vector4(локальный x, y ЦЕНТРА цилиндра, локальный z, радиус * масштаб)
		# и параллельный массив высот цилиндров (высота меша * масштаб + заглубление под землю).
		var trunks: Array[Vector4] = []
		var trunk_heights := PackedFloat32Array()
		var mesh_top := item.mesh.get_aabb().end.y if item.mesh != null else TRUNK_COLLISION_HEIGHT_FALLBACK
		mesh_top = maxf(mesh_top, 0.5)
		var base_collision_radius := item.trunk_collision_radius if item.trunk_collision_radius > 0.0 else type_trunk
		
		for cx in range(min_cx, max_cx + 1):
			for cz in range(min_cz, max_cz + 1):
				var center_x := (float(cx) + 0.5) * type_cell_size
				var center_z := (float(cz) + 0.5) * type_cell_size
				
				# 1. Проверка маски спавна (собственный шум или лесной покров)
				var spawn_weight := get_spawn_weight_for_item(item, Vector2(center_x, center_z))
				if spawn_weight <= 0.05:
					continue
				
				# 2. Детерминированный хэш ячейки
				var h := get_cell_hash(cx, cz, type_seed)
				var spawn_roll := hash_to_float(h, 0)
				if spawn_roll > (spawn_weight * item.density_multiplier):
					continue
				
				# 3. Случайное смещение внутри ячейки (БЕЗ clampf — устраняет просеки)
				var offset_x_pos := (hash_to_float(h, 1) * 2.0 - 1.0) * max_offset
				var offset_z_pos := (hash_to_float(h, 2) * 2.0 - 1.0) * max_offset
				var world_x := center_x + offset_x_pos
				var world_z := center_z + offset_z_pos
				
				var pos2d := Vector2(world_x, world_z)
				var h_center := get_point_height(pos2d)
				if h_center <= water_level:
					continue
				
				# 4. Проверка крутизны склона
				if item.check_slope:
					var step := 0.5
					var h_dx := (get_point_height(Vector2(world_x + step, world_z)) - get_point_height(Vector2(world_x - step, world_z))) / (2.0 * step) * height_scale
					var h_dz := (get_point_height(Vector2(world_x, world_z + step)) - get_point_height(Vector2(world_x, world_z - step))) / (2.0 * step) * height_scale
					var slope_tan := sqrt(h_dx * h_dx + h_dz * h_dz)
					var slope_deg := rad_to_deg(atan(slope_tan))
					if slope_deg > item.max_slope:
						continue
				
				var rot_y := hash_to_float(h, 3) * TAU
				var scale_factor := lerpf(item.scale_min, item.scale_max, hash_to_float(h, 4))
				var eff_spacing := type_spacing * scale_factor
				var eff_trunk := type_trunk * scale_factor
				
				# 5. Проверка коллизий с разделением радиусов (крона vs ствол vs детали)
				if item.check_collisions and not placed_candidates.is_empty():
					var collided := false
					for obs in placed_candidates:
						var dx : float = world_x - obs["x"]
						var dz : float = world_z - obs["z"]
						var dist_sq := dx * dx + dz * dz
						
						var min_dist : float = 0.0
						if obs["is_obstacle"]:
							if item.collide_only_with_trunks or not item.is_obstacle:
								# Мелкие детали (камни/кусты/грибы) проверяют коллизию только со стволом дерева!
								min_dist = eff_spacing + obs["trunk_radius"]
							else:
								# Дерево против дерева — дистанция крон
								min_dist = eff_spacing + obs["spacing_radius"]
						else:
							if item.collide_only_with_trunks:
								continue
							else:
								min_dist = eff_spacing + obs["spacing_radius"]
						
						if dist_sq < (min_dist * min_dist):
							collided = true
							break
					if collided:
						continue
				
				# Регистрируем успешного кандидата в общем пуле
				placed_candidates.append({
					"x": world_x,
					"z": world_z,
					"spacing_radius": eff_spacing,
					"trunk_radius": eff_trunk,
					"is_obstacle": item.is_obstacle,
				})
				
				# Добавляем в маску травы, если ствол касается территории чанка
				if item.is_obstacle:
					if (world_x >= chunk_world_min_x - eff_trunk and world_x <= chunk_world_max_x + eff_trunk and
						world_z >= chunk_world_min_z - eff_trunk and world_z <= chunk_world_max_z + eff_trunk):
						grass_obstacles.append(Vector3(world_x, world_z, eff_trunk))
				
				# 6. Строгое правило владения: в 3D-модель чанка объект попадает ТОЛЬКО если его центр внутри чанка
				var is_inside_chunk := (
					world_x >= chunk_world_min_x and world_x < chunk_world_max_x and
					world_z >= chunk_world_min_z and world_z < chunk_world_max_z
				)
				if not is_inside_chunk:
					continue
				
				var world_y := h_center * height_scale + get_micro_height(pos2d)
				var local_pos := Vector3(
					world_x - chunk_world_min_x,
					world_y,
					world_z - chunk_world_min_z
				)
				if item.has_trunk_collision:
					var col_height := mesh_top * scale_factor + TRUNK_COLLISION_SINK
					trunks.append(Vector4(local_pos.x, local_pos.y + (col_height * 0.5 - TRUNK_COLLISION_SINK),
							local_pos.z, base_collision_radius * scale_factor))
					trunk_heights.append(col_height)
				if item.mesh == null:
					var trunk_height := type_spacing * 1.2
					local_pos.y += (trunk_height * 0.5) * scale_factor
				
				var t := Transform3D()
				t = t.scaled(Vector3(scale_factor, scale_factor, scale_factor))
				t = t.rotated(Vector3.UP, rot_y)
				t.origin = local_pos
				transforms.append(t)
		
		if not transforms.is_empty():
			# Собираем MultiMesh полностью в фоновом потоке!
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.instance_count = transforms.size()
			if item.mesh != null:
				mm.mesh = item.mesh
			else:
				mm.mesh = get_placeholder_mesh(item)
			
			var buf := PackedFloat32Array()
			buf.resize(transforms.size() * 12)
			for i in range(transforms.size()):
				var t : Transform3D = transforms[i]
				var base_off := i * 12
				buf[base_off + 0] = t.basis.x.x
				buf[base_off + 1] = t.basis.y.x
				buf[base_off + 2] = t.basis.z.x
				buf[base_off + 3] = t.origin.x
				
				buf[base_off + 4] = t.basis.x.y
				buf[base_off + 5] = t.basis.y.y
				buf[base_off + 6] = t.basis.z.y
				buf[base_off + 7] = t.origin.y
				
				buf[base_off + 8] = t.basis.x.z
				buf[base_off + 9] = t.basis.y.z
				buf[base_off + 10] = t.basis.z.z
				buf[base_off + 11] = t.origin.z
			mm.buffer = buf
			
			result.append({
				"item": item,
				"multimesh": mm,
				"trunks": trunks,
				"trunk_heights": trunk_heights,
			})
	
	return {
		"objects": result,
		"grass_obstacles": grass_obstacles
	}

func generate_single_chunk(index : int):
	if cancel_generation:
		return

	var c : Vector2 = current_coords[index]

	var chunk_world_size := chunk_size * cell_size
	var chunk_noise_x := chunk_world_size * c.x
	var chunk_noise_z := chunk_world_size * c.y

	# --- Кэш высот и цветов (grid_size × grid_size = (chunk_size+1)²) ---
	var grid_size := chunk_size + 1
	var heights   : Array[float] = []
	var raw_h     : Array[float] = []
	var colors    : Array[Color] = []
	heights.resize(grid_size * grid_size)
	raw_h.resize(grid_size * grid_size)
	colors.resize(grid_size * grid_size)

	for xi in range(grid_size):
		for zi in range(grid_size):
			var pos := Vector2(chunk_noise_x + xi * cell_size, chunk_noise_z + zi * cell_size)
			var h   := get_point_height(pos)
			raw_h[xi * grid_size + zi]   = h
			heights[xi * grid_size + zi] = h * height_scale + get_micro_height(pos)
			colors[xi * grid_size + zi]  = get_point_color(pos, h)

	# --- Индексированный меш: (chunk_size+1)² вершин, chunk_size²×6 индексов ---
	# Вместо SurfaceTool: прямая сборка PackedArrays + ArrayMesh.add_surface_from_arrays().
	# Количество вершин: 289 vs 1536 при chunk_size=16 — меньше данных на GPU.
	var vert_count  := grid_size * grid_size
	var index_count := chunk_size * chunk_size * 6

	var verts         := PackedVector3Array()
	var vertex_colors := PackedColorArray()
	var ind_arr       := PackedInt32Array()
	# Накопитель ненормированных нормалей — суммируем со всех треугольников
	var normals_accum : Array[Vector3] = []

	verts.resize(vert_count)
	vertex_colors.resize(vert_count)
	ind_arr.resize(index_count)
	normals_accum.resize(vert_count)

	for i in range(vert_count):
		normals_accum[i] = Vector3.ZERO

	# Заполняем позиции и цвета вершин
	for xi in range(grid_size):
		for zi in range(grid_size):
			var i := xi * grid_size + zi
			verts[i]         = Vector3(xi * cell_size, heights[i], zi * cell_size)
			vertex_colors[i] = colors[i]

	# Строим индексы и накапливаем взвешенные нормали
	var ind_idx := 0
	for x in range(chunk_size):
		for z in range(chunk_size):
			var i00 := x       * grid_size + z
			var i01 := x       * grid_size + (z + 1)
			var i10 := (x + 1) * grid_size + z
			var i11 := (x + 1) * grid_size + (z + 1)

			var p00 := verts[i00]
			var p01 := verts[i01]
			var p10 := verts[i10]
			var p11 := verts[i11]

			# Треугольник 1: i00 → i10 → i01
			var n1 := (p01 - p00).cross(p10 - p00)
			normals_accum[i00] += n1
			normals_accum[i10] += n1
			normals_accum[i01] += n1
			ind_arr[ind_idx]     = i00
			ind_arr[ind_idx + 1] = i10
			ind_arr[ind_idx + 2] = i01

			# Треугольник 2: i10 → i11 → i01
			var n2 := (p01 - p10).cross(p11 - p10)
			normals_accum[i10] += n2
			normals_accum[i11] += n2
			normals_accum[i01] += n2
			ind_arr[ind_idx + 3] = i10
			ind_arr[ind_idx + 4] = i11
			ind_arr[ind_idx + 5] = i01

			ind_idx += 6

	# Нормализуем накопленные нормали
	var normals_packed := PackedVector3Array()
	normals_packed.resize(vert_count)
	for i in range(vert_count):
		normals_packed[i] = normals_accum[i].normalized()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals_packed
	arrays[Mesh.ARRAY_COLOR]  = vertex_colors
	arrays[Mesh.ARRAY_INDEX]  = ind_arr

	var chunk_mesh := ArrayMesh.new()
	chunk_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Построение формы физической коллизии чанка в фоновом потоке
	var col_faces := PackedVector3Array()
	col_faces.resize(index_count)
	for i in range(index_count):
		col_faces[i] = verts[ind_arr[i]]
	var chunk_col_shape := ConcavePolygonShape3D.new()
	chunk_col_shape.set_faces(col_faces)

	var grid_data := generate_grid_objects(c)
	var chunk_objects : Array = grid_data["objects"]
	var grass_obstacles : Array = grid_data["grass_obstacles"]

	var terrain_data : Dictionary = {}
	if enable_grass:
		# Передаём уже построенные кэши — generate_chunk_terrain_image
		# больше не вызывает шумы повторно для тех же точек.
		terrain_data = generate_chunk_terrain_image(c, grass_obstacles, heights, raw_h, grid_size)
		var chunk_seed := get_cell_hash(int(c.x), int(c.y), spawn_seed)
		terrain_data["multimesh"] = build_grass_multimesh(chunk_seed)

	# Передаём данные в главный поток через очередь — _process контролирует темп.
	call_deferred("_enqueue_chunk", c, chunk_mesh, chunk_objects, terrain_data, chunk_col_shape)

## Вызывается через call_deferred из фонового потока.
## Кладёт готовые данные чанка в очередь; _process добавит ноду в сцену в нужный кадр.
func _enqueue_chunk(pos_of_chunk: Vector2, mesh_data: ArrayMesh, chunk_objects: Array, terrain_data: Dictionary, col_shape: Shape3D = null) -> void:
	_chunk_spawn_queue.push_back({
		"pos":       pos_of_chunk,
		"mesh":      mesh_data,
		"objects":   chunk_objects,
		"terrain":   terrain_data,
		"col_shape": col_shape,
	})

func spawn_chunk(pos_of_chunk : Vector2, mesh_data: ArrayMesh, chunk_objects : Array = [], terrain_data : Dictionary = {}, col_shape: Shape3D = null) -> void:
	var chunk_node = MeshInstance3D.new()
	chunk_node.mesh = mesh_data
	
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	chunk_node.material_override = mat
	
	# Статическая физическая коллизия рельефа чанка (создана в фоне)
	if col_shape:
		var static_body := StaticBody3D.new()
		static_body.collision_layer = 1
		static_body.collision_mask = 0
		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = col_shape
		static_body.add_child(collision_shape)
		chunk_node.add_child(static_body)
	
	# Коллизия стволов деревьев (отдельный StaticBody3D, слой 1). Высота цилиндра — по AABB меша
	# * масштаб (считается в потоке), над кроной стены нет.
	#
	# TODO (производительность, СНАЧАЛА ЗАМЕРИТЬ: число стволов на чанк и время этого блока в spawn_chunk):
	# [3] Не создавать ноды CollisionShape3D, а добавлять шейпы прямо в физический сервер:
	#     body = PhysicsServer3D.body_create(); body_set_mode(STATIC); body_set_space(get_world_3d().space);
	#     body_add_shape(body, shape.get_rid(), Transform3D(Basis.IDENTITY, pos)); слой/маску задать через
	#     body_set_collision_layer/mask. RID тела хранить на чанке и освобождать (PhysicsServer3D.free_rid)
	#     при выгрузке чанка/в _do_clear_chunks — иначе утечка. Убирает сотни узлов на чанк.
	# [4] Держать коллизию стволов только у чанков рядом с игроком и врагами (радиус 2-3 чанка):
	#     дальше блок не создавать/удалять, при приближении создавать порциями (как grass_uploads_per_frame).
	#     Данные "trunks"/"trunk_heights" уже лежат в chunk_objects — их надо сохранить на чанке для
	#     отложенного создания. Самый большой выигрыш на больших мирах; не забыть про врагов вдали от игрока.
	var trunk_body: StaticBody3D = null
	var dbg_start_usec := Time.get_ticks_usec()
	var dbg_trunk_count := 0
	for entry in chunk_objects:
		var trunk_list: Array = entry.get("trunks", [])
		var trunk_heights: PackedFloat32Array = entry.get("trunk_heights", PackedFloat32Array())
		for ti in trunk_list.size():
			var trunk: Vector4 = trunk_list[ti]
			if trunk_body == null:
				trunk_body = StaticBody3D.new()
				trunk_body.collision_layer = 1
				trunk_body.collision_mask = 0
				trunk_body.set_meta(TRUNK_BODY_META, true)
				chunk_node.add_child(trunk_body)
			dbg_trunk_count += 1
			var cyl := _get_trunk_shape(trunk.w, trunk_heights[ti])
			var shape_node := CollisionShape3D.new()
			shape_node.shape = cyl
			trunk_body.add_child(shape_node)
			shape_node.position = Vector3(trunk.x, trunk.y, trunk.z)
	if debug_trunk_stats:
		var dbg_usec := Time.get_ticks_usec() - dbg_start_usec
		_dbg_chunks += 1
		_dbg_trunks_total += dbg_trunk_count
		_dbg_trunks_max = maxi(_dbg_trunks_max, dbg_trunk_count)
		_dbg_usec_total += dbg_usec
		_dbg_usec_max = maxi(_dbg_usec_max, dbg_usec)
		print("[trunk_stats] чанк %s: стволов %d, %.2f мс | всего чанков %d, стволов/чанк ср %.1f макс %d, мс ср %.2f макс %.2f, шейпов в кэше %d" % [
				pos_of_chunk, dbg_trunk_count, dbg_usec / 1000.0, _dbg_chunks,
				float(_dbg_trunks_total) / _dbg_chunks, _dbg_trunks_max,
				_dbg_usec_total / 1000.0 / _dbg_chunks, _dbg_usec_max / 1000.0, _trunk_shape_cache.size()])
	
	# =========================================================================
	# СПАВН ОБЪЕКТОВ ЧЕРЕЗ MULTIMESH
	# MultiMesh полностью собран в фоновом потоке generate_single_chunk.
	# Здесь только связываем ресурс с MultiMeshInstance3D без фризов в кадре.
	# =========================================================================
	for entry in chunk_objects:
		var mm : MultiMesh = entry.get("multimesh", null)
		if mm == null:
			continue
		var mm_inst := MultiMeshInstance3D.new()
		mm_inst.multimesh = mm
		chunk_node.add_child(mm_inst)
	
	# =========================================================================
	# СПАВН ТРАВЫ — ОТЛОЖЕННАЯ ЗАГРУЗКА ЧЕРЕЗ ОЧЕРЕДЬ
	# multimesh травы УЖЕ собран в фоне.
	# Очередь нужна лишь для того, чтобы ImageTexture.create_from_image()
	# распределялся по кадрам без единовременного лока GPU.
	# =========================================================================
	if enable_grass and not terrain_data.is_empty():
		var chunk_world_size := chunk_size * cell_size
		var base_mat : ShaderMaterial = _cached_grass_material
		if base_mat == null:
			base_mat = grass_material
		
		# Мировая позиция угла чанка (с учётом смещения генератора)
		var abs_chunk_x := pos_of_chunk.x * chunk_world_size - generate_point.x
		var abs_chunk_z := pos_of_chunk.y * chunk_world_size - generate_point.y
		
		_grass_upload_queue.push_back({
			"chunk_node":       chunk_node,
			"terrain_img":      terrain_data["image"],
			"min_h":            terrain_data["min_height"],
			"max_h":            terrain_data["max_height"],
			"chunk_world_size": chunk_world_size,
			"grass_multimesh":  terrain_data["multimesh"],
			"base_mat":         base_mat,
			"chunk_world_pos":  Vector2(abs_chunk_x, abs_chunk_z),
		})
	
	add_child(chunk_node)
	
	chunk_node.position = Vector3(
		pos_of_chunk.x * chunk_size * cell_size,
		0,
		pos_of_chunk.y * chunk_size * cell_size
	)

func get_chunk_coords(world_pos: Vector2) -> Vector2i:
	var chunk_world_size := chunk_size * cell_size
	
	var chunk_x := floori(world_pos.x / chunk_world_size)
	var chunk_z := floori(world_pos.y / chunk_world_size)
	
	return Vector2i(chunk_x, chunk_z)
