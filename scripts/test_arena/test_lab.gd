class_name TestLab
extends Node3D
## Лаборатория в test_player.tscn: хаб-платформа высоко над ареной и клетки дуэлей по кругу.
## Всё строится кодом из таблицы CELLS (добавить/убрать клетку = строка в таблице).
## Навигация только порталами (прыжка в игре нет): портал у старта арены -> хаб -> клетки -> обратно.
## Узел ставится в корень сцены (в начало координат); существующие узлы арены не трогает.

const HUB_HEIGHT: float = 60.0
const HUB_SIZE: Vector2 = Vector2(26.0, 26.0)
const HUB_PORTAL_RADIUS: float = 9.0
const HUB_ARRIVAL_RADIUS: float = 5.5
const CELL_RING_RADIUS: float = 45.0
const CELL_SIZE: Vector2 = Vector2(24.0, 24.0)
const SLOTS: int = 8 # 7 клеток + выход на арену
## Портал на арене: подальше от врагов арены (их зона обнаружения 12 м).
const ARENA_PORTAL_POS: Vector3 = Vector3(0.0, 0.0, 10.0)
const ARENA_ARRIVAL_POS: Vector3 = Vector3(0.0, 0.05, 5.5)

const GRID_MATERIAL: String = "res://materials/prototype_grid.tres"
const BUILD_ARMORED: String = "res://resources/stats/enemy_armored.tres"
const BUILD_AGILE: String = "res://resources/stats/enemy_agile.tres"
const BUILD_BALANCED: String = "res://resources/stats/enemy_balanced.tres"
const PERS_DUELIST: String = "res://resources/ai/personality_duelist.tres"
const PERS_BULLY: String = "res://resources/ai/personality_bully.tres"
const PERS_TURTLE: String = "res://resources/ai/personality_turtle.tres"

## Клетки: name — подпись, stats/personality — пути ресурсов ("" = по умолчанию), dummy — манекен.
## Билды Броня/Ловкость/Баланс — без характера (базовые шансы), чтобы сравнивать чистые статы.
const CELLS: Array[Dictionary] = [
	{"name": "Манекен", "stats": "", "personality": "", "dummy": true,
		"hint": "анимации и удары без ответа", "color": Color(0.8, 0.8, 0.8)},
	{"name": "Броня", "stats": BUILD_ARMORED, "personality": "", "dummy": false,
		"hint": "билд: броня 8", "color": Color(0.45, 0.6, 1.0)},
	{"name": "Ловкость", "stats": BUILD_AGILE, "personality": "", "dummy": false,
		"hint": "билд: ловкость 8", "color": Color(0.4, 1.0, 0.5)},
	{"name": "Баланс", "stats": BUILD_BALANCED, "personality": "", "dummy": false,
		"hint": "билд: 4/4", "color": Color(1.0, 0.9, 0.4)},
	{"name": "Bully", "stats": BUILD_AGILE, "personality": PERS_BULLY, "dummy": false,
		"hint": "ловкость + агрессор", "color": Color(1.0, 0.45, 0.35)},
	{"name": "Turtle", "stats": BUILD_ARMORED, "personality": PERS_TURTLE, "dummy": false,
		"hint": "броня + трус/защита", "color": Color(0.5, 0.9, 0.9)},
	{"name": "Duelist", "stats": BUILD_BALANCED, "personality": PERS_DUELIST, "dummy": false,
		"hint": "баланс + рациональный", "color": Color(0.85, 0.6, 1.0)},
]

var _grid_material: Material = null


func _ready() -> void:
	_grid_material = load(GRID_MATERIAL) as Material
	var hub_center := Vector3(0.0, HUB_HEIGHT, 0.0)
	_make_platform(self, hub_center, HUB_SIZE)
	_make_sign("ЛАБОРАТОРИЯ", hub_center + Vector3(0.0, 4.5, 0.0))

	# Выход с хаба на арену — последний слот.
	var arena_arrival := _make_marker("ArenaArrival", ARENA_ARRIVAL_POS)
	var exit_dir := _slot_dir(SLOTS - 1)
	var exit_portal := _make_portal("На арену\n(к старту)", hub_center + exit_dir * HUB_PORTAL_RADIUS,
			arena_arrival, Color(1.0, 1.0, 1.0))
	_face_center(exit_portal, hub_center)

	for i in CELLS.size():
		_build_cell(i, hub_center, arena_arrival)

	# Портал на арене, рядом со стартом игрока -> центр хаба.
	var hub_arrival := _make_marker("HubArrival", hub_center + Vector3(0.0, 0.05, 0.0))
	_make_portal("Лаборатория\n(площадки для дуэлей)", ARENA_PORTAL_POS, hub_arrival, Color(0.3, 0.8, 1.0))


func _build_cell(i: int, hub_center: Vector3, _arena_arrival: Marker3D) -> void:
	var def: Dictionary = CELLS[i]
	var dir := _slot_dir(i)

	var cell := DuelCell.new()
	cell.name = "Cell_%s" % def["name"]
	cell.cell_name = def["name"]
	cell.is_dummy = def["dummy"]
	if def["stats"] != "":
		cell.enemy_stats = load(def["stats"]) as CharacterStats
	if def["personality"] != "":
		cell.personality = load(def["personality"]) as AIPersonality
	add_child(cell)
	cell.position = hub_center + dir * CELL_RING_RADIUS
	_make_platform(cell, cell.global_position, CELL_SIZE)

	# Хаб -> клетка (с пересозданием врага).
	var to_cell := _make_portal("Дуэль: %s\n%s" % [def["name"], def["hint"]],
			hub_center + dir * HUB_PORTAL_RADIUS, cell.arrival, def["color"])
	to_cell.target_cell = cell
	_face_center(to_cell, hub_center)

	# Клетка -> обратно в хаб, перед своим порталом.
	var hub_back := _make_marker("HubBack_%s" % def["name"], hub_center + dir * HUB_ARRIVAL_RADIUS + Vector3.UP * 0.05)
	_make_portal("Назад в хаб", cell.global_position + Vector3(0.0, 0.0, DuelCell.BACK_PORTAL_Z),
			hub_back, Color(1.0, 1.0, 1.0))
	_make_sign("%s\n%s" % [def["name"], def["hint"]], cell.global_position + Vector3(0.0, 5.0, -10.0))


## Направление слота на хабе (в плоскости XZ).
func _slot_dir(slot: int) -> Vector3:
	var angle := TAU * float(slot) / float(SLOTS)
	return Vector3(cos(angle), 0.0, sin(angle))


func _face_center(portal: Node3D, center: Vector3) -> void:
	var look := Vector3(center.x, portal.global_position.y, center.z)
	if look.distance_to(portal.global_position) > 0.1:
		portal.look_at(look, Vector3.UP)


func _make_marker(marker_name: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = marker_name
	add_child(m)
	m.global_position = pos
	return m


func _make_portal(text: String, pos: Vector3, dest: Marker3D, color: Color) -> ArenaPortal:
	var p := ArenaPortal.new()
	p.label_text = text
	p.glow_color = color
	p.destination = dest
	add_child(p)
	p.global_position = pos
	return p


func _make_sign(text: String, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.01
	label.outline_size = 16
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)
	label.global_position = pos


## Платформа с видимым низким бортиком, чтобы не свалиться вниз (прыжка/лазания нет).
## top_center — мировая точка центра верхней грани.
func _make_platform(parent: Node3D, top_center: Vector3, size: Vector2) -> void:
	var body := StaticBody3D.new()
	body.name = "Platform"
	parent.add_child(body)
	body.global_position = top_center - Vector3(0.0, 0.5, 0.0)
	_add_box(body, Vector3(size.x, 1.0, size.y), Vector3.ZERO, _grid_material)

	var rim_h := 1.6
	var rim_t := 0.4
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.35)
	rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var y := 0.5 + rim_h * 0.5
	_add_box(body, Vector3(size.x, rim_h, rim_t), Vector3(0.0, y, size.y * 0.5 - rim_t * 0.5), rim_mat)
	_add_box(body, Vector3(size.x, rim_h, rim_t), Vector3(0.0, y, -size.y * 0.5 + rim_t * 0.5), rim_mat)
	_add_box(body, Vector3(rim_t, rim_h, size.y), Vector3(size.x * 0.5 - rim_t * 0.5, y, 0.0), rim_mat)
	_add_box(body, Vector3(rim_t, rim_h, size.y), Vector3(-size.x * 0.5 + rim_t * 0.5, y, 0.0), rim_mat)


func _add_box(body: StaticBody3D, size: Vector3, pos: Vector3, material: Material) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = material
	mesh.mesh = box_mesh
	mesh.position = pos
	body.add_child(mesh)
