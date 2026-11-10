class_name GameOverScreen
extends CanvasLayer

## Экран конца демки: затемнение + надпись + рестарт сцены.
## Вешается дочерним узлом на CombatCharacter3D игрока (как CombatHUD),
## сам подписывается на его `character_died`. Логику боя не трогает.

@export_group("Target Actor")
@export var player_actor: CombatCharacter3D = null

@export_group("Timing")
## Пауза после смерти, чтобы доиграла анимация Death (с).
@export_range(0.0, 10.0, 0.1, "suffix:с") var show_delay: float = 2.0
## Длительность плавного появления (с).
@export_range(0.0, 10.0, 0.1, "suffix:с") var fade_duration: float = 1.2

@export_group("Texts")
@export var title_text: String = "ВЫ ПОГИБЛИ"
@export var hint_text: String = "R / Enter — начать заново"

@export_group("Colors")
@export var dim_color: Color = Color(0.0, 0.0, 0.0, 0.72)
@export var title_color: Color = Color(0.88, 0.18, 0.22, 1.0)
@export var hint_color: Color = Color(0.92, 0.92, 0.92, 1.0)
@export var text_outline_color: Color = Color(0.0, 0.0, 0.0, 0.95)

var _root_control: Control = null
var _dim_rect: ColorRect = null
var _title_label: Label = null
var _hint_label: Label = null
var _is_shown: bool = false
var _can_restart: bool = false


func _ready() -> void:
	layer = 20  # выше CombatHUD (10)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if player_actor == null and get_parent() is CombatCharacter3D:
		player_actor = get_parent() as CombatCharacter3D

	_build_ui()
	_root_control.visible = false

	if is_instance_valid(player_actor):
		player_actor.character_died.connect(_on_player_died)


func is_shown() -> bool:
	return _is_shown


func _build_ui() -> void:
	_root_control = Control.new()
	_root_control.name = "GameOverRoot"
	_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_control)

	_dim_rect = ColorRect.new()
	_dim_rect.name = "Dim"
	_dim_rect.color = dim_color
	_dim_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_control.add_child(_dim_rect)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 18)
	_root_control.add_child(box)

	_title_label = _make_label(title_text, 64, title_color)
	_title_label.name = "TitleLabel"
	box.add_child(_title_label)

	_hint_label = _make_label(hint_text, 22, hint_color)
	_hint_label.name = "HintLabel"
	box.add_child(_hint_label)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", text_outline_color)
	label.add_theme_constant_override("outline_size", 6)
	return label


func _on_player_died(_attacker: Node3D) -> void:
	if _is_shown:
		return
	_is_shown = true
	if show_delay > 0.0:
		await get_tree().create_timer(show_delay).timeout
	if not is_inside_tree():
		return
	_show_screen()


func _show_screen() -> void:
	# Курсор может быть захвачен камерой; для экрана конца он не нужен, но и не мешает.
	_root_control.modulate.a = 0.0
	_root_control.visible = true
	if fade_duration > 0.0:
		var tween: Tween = create_tween()
		tween.tween_property(_root_control, "modulate:a", 1.0, fade_duration)
		tween.finished.connect(func() -> void: _can_restart = true)
	else:
		_root_control.modulate.a = 1.0
		_can_restart = true


func _unhandled_input(event: InputEvent) -> void:
	if not _can_restart:
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_R or key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
		restart()


func restart() -> void:
	get_tree().reload_current_scene()
