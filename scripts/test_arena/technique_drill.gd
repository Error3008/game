class_name TechniqueDrill
extends Node3D
## Тренажёр приёмов: актор-манекен в цикле исполняет выбранный приём, игрок отрабатывает ответ.
## Переключение приёма: «,» — предыдущий, «.» — следующий. Список приёмов — TechniqueLoadout.

@export var interval: float = 3.0

var actor: CombatCharacter3D = null
var techniques: Array[TechniqueData] = []
var index: int = 0
var _timer: float = 1.5
var _label: Label3D = null


func setup(drill_actor: CombatCharacter3D, list: Array[TechniqueData]) -> void:
	actor = drill_actor
	techniques = list
	TechniqueLoadout.give(actor, techniques)
	_label = Label3D.new()
	_label.font_size = 64
	_label.pixel_size = 0.01
	_label.outline_size = 12
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	add_child(_label)
	_label.position = Vector3(0.0, 3.0, -5.0)
	_update_label()


func current() -> TechniqueData:
	return techniques[index] if not techniques.is_empty() else null


func select(step: int) -> void:
	if techniques.is_empty():
		return
	index = posmod(index + step, techniques.size())
	_timer = 1.0
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_COMMA:
				select(-1)
			KEY_PERIOD:
				select(1)


func _physics_process(delta: float) -> void:
	var data := current()
	if data == null or not is_instance_valid(actor) or not actor.is_alive():
		return
	_timer -= delta
	if _timer <= 0.0:
		if actor.cmd_technique(data.id):
			_timer = interval
		else:
			_timer = 0.3 # занят или откат: повторить скоро


func _update_label() -> void:
	var data := current()
	_label.text = "Приём: нет (resources/techniques пуст)" if data == null \
			else "Приём %d/%d: %s\n[,] назад  [.] вперёд" % [index + 1, techniques.size(), data.display_name if data.display_name != "" else String(data.id)]
