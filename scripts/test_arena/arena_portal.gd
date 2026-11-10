class_name ArenaPortal
extends Area3D
## Портал тестовой лаборатории (test_player.tscn): игрок стоит в зоне `charge_time` секунд —
## телепорт к `destination`. Отдельной клавиши "использовать" в игре нет, поэтому так.
## При телепорте игрок полностью восстанавливается (restore_full) и теряет лок цели;
## если задана `target_cell`, её враг создаётся заново.
## Визуал (светящийся квадрат + подпись) строится кодом, настраивается через label_text/glow_color.

@export var label_text: String = "Портал"
@export var charge_time: float = 1.0
@export var glow_color: Color = Color(0.3, 0.8, 1.0)

## Куда ставить игрока (выставляется TestLab).
var destination: Marker3D = null
## Клетка, враг которой пересоздаётся при телепорте (может быть null).
var target_cell: DuelCell = null

## Общая пауза между телепортами, чтобы игрок, приземлившись рядом с обратным порталом, не улетел сразу.
static var _next_allowed_msec: int = 0
const COOLDOWN_MSEC: int = 1500

var _player: Player = null
var _charge: float = 0.0
var _material: StandardMaterial3D = null


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # слой игрока
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 3.0, 2.2)
	shape.shape = box
	shape.position.y = 1.5
	add_child(shape)

	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(glow_color, 0.55)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.emission_enabled = true
	_material.emission = glow_color
	_material.emission_energy_multiplier = 0.6
	var quad := MeshInstance3D.new()
	var quad_mesh := BoxMesh.new()
	quad_mesh.size = Vector3(1.8, 2.4, 0.08)
	quad_mesh.material = _material
	quad.mesh = quad_mesh
	quad.position.y = 1.3
	add_child(quad)

	var label := Label3D.new()
	label.text = label_text
	label.font_size = 48
	label.pixel_size = 0.008
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 3.2
	add_child(label)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player = body as Player
		_charge = 0.0


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null
		_charge = 0.0
		_set_glow(0.0)


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.is_alive():
		return
	if Time.get_ticks_msec() < _next_allowed_msec:
		return
	_charge += delta
	_set_glow(_charge / charge_time)
	if _charge >= charge_time:
		_teleport()


func _set_glow(t: float) -> void:
	if _material != null:
		_material.emission_energy_multiplier = 0.6 + 4.0 * clampf(t, 0.0, 1.0)


func _teleport() -> void:
	var player := _player
	_player = null
	_charge = 0.0
	_set_glow(0.0)
	if destination == null or player == null:
		return
	_next_allowed_msec = Time.get_ticks_msec() + COOLDOWN_MSEC

	# Лок снимаем ДО пересоздания врага, чтобы камера не держала удалённую цель.
	if is_instance_valid(player.controller):
		player.controller.release_lock()
	if target_cell != null:
		target_cell.respawn()
	player.restore_full()
	player.global_position = destination.global_position
	player.velocity = Vector3.ZERO
