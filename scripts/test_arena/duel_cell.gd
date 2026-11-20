class_name DuelCell
extends Node3D
## Клетка дуэли тестовой лаборатории: платформа в воздухе + один враг с заданным билдом/характером.
## respawn() удаляет прошлого врага (живого или труп) и создаёт свежего. Вызывается порталом.
## Локальные координаты: игрок прибывает в (0, 0, ARRIVAL_Z), враг стоит в (0, 0, ENEMY_Z).

const ARRIVAL_Z: float = 5.5
const ENEMY_Z: float = -5.0
const BACK_PORTAL_Z: float = 9.0

@export var cell_name: String = "Клетка"
@export var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
@export var enemy_stats: CharacterStats = null
@export var personality: AIPersonality = null
## Манекен: стоит, не уклоняется, не бьёт (для разглядывания анимаций и ударов).
@export var is_dummy: bool = false
## Тренажёр приёмов: враг-манекен в цикле исполняет выбранный приём, игроку выдаётся debug-лоадаут.
@export var technique_drill: bool = false

## Точка прибытия игрока (создаётся в _ready).
var arrival: Marker3D = null
var drill: TechniqueDrill = null
var _enemy: Node3D = null


func _ready() -> void:
	arrival = Marker3D.new()
	arrival.name = "Arrival"
	arrival.position = Vector3(0.0, 0.05, ARRIVAL_Z)
	add_child(arrival)


func respawn() -> void:
	if is_instance_valid(_enemy):
		_enemy.queue_free()
	if is_instance_valid(drill):
		drill.queue_free()
		drill = null
	_enemy = enemy_scene.instantiate() as Node3D
	_enemy.name = "Enemy_%s" % cell_name
	_enemy.set("stats", enemy_stats)
	_enemy.set("personality", personality)
	_enemy.set("is_dummy", is_dummy)
	add_child(_enemy)
	_enemy.position = Vector3(0.0, 0.05, ENEMY_Z)
	if technique_drill:
		drill = TechniqueDrill.new()
		drill.name = "TechniqueDrill"
		add_child(drill)
		drill.setup(_enemy as CombatCharacter3D, TechniqueLoadout.load_all())


## Вызывается порталом при входе игрока: в клетке приёмов выдаёт полный набор.
func arm_player(player: CombatCharacter3D) -> void:
	if technique_drill and is_instance_valid(drill):
		TechniqueLoadout.give(player, drill.techniques)
