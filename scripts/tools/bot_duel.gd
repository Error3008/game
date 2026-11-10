extends Node3D

## Дуэль двух ИИ-ботов для наблюдения (сцена scenes/bot_duel.tscn, F6).
## Бот A — обычный враг (слой 4), бот B — Enemy.Team.ALLY (слой 2, бьёт по врагам).
## Оба используют один и тот же EnemyAIController; различаются личностью и билдом.
## Управление: Q/W — личность A, A/S — билд A, O/P — личность B, K/L — билд B,
## R — рестарт, Backspace — сбросить счёт, T — скорость ×1/×2/×4.

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const DEFAULT_PERSONALITIES: Array[String] = [
	"res://resources/ai/personality_duelist.tres",
	"res://resources/ai/personality_bully.tres",
	"res://resources/ai/personality_turtle.tres",
]
const DEFAULT_BUILDS: Array[String] = [
	"res://resources/stats/enemy_balanced.tres",
	"res://resources/stats/enemy_armored.tres",
	"res://resources/stats/enemy_agile.tres",
]

@export_group("Rounds")
## Сам начинать новый раунд после конца. Выключено — следующий раунд по клавише R.
@export var auto_next_round: bool = true
@export var next_round_delay: float = 3.0
## Ничья по таймауту, с (две «черепахи» могут не добить друг друга). 0 = без ограничения.
@export var round_timeout: float = 90.0
## Каждый бот стоит на таком расстоянии от центра, м.
@export var spawn_distance: float = 4.0

@export_group("Lineup")
## Списки, по которым клавиши листают личности и билды. Можно добавлять свои ресурсы.
@export var personalities: Array[AIPersonality] = []
@export var builds: Array[CharacterStats] = []
## Стартовый выбор (индексы в списках выше): A — обычный враг, B — бот-союзник.
@export var start_personality_a: int = 1
@export var start_personality_b: int = 2
@export var start_build_a: int = 2
@export var start_build_b: int = 1

@export_group("Bot Rules")
## Включают/выключают механики у ОБОИХ ботов (чтобы изолировать, что влияет на исход).
@export var bots_can_dodge: bool = true
@export var bots_can_block: bool = true
@export var bots_can_kick: bool = true
@export var bots_can_heal: bool = true
@export var bots_can_light_attack: bool = true

@export_group("Speed")
@export var start_time_scale: float = 1.0
## Шаги скорости по клавише T.
@export var time_scales: Array[float] = [1.0, 2.0, 4.0]

@export_group("View")
@export var show_overlay: bool = true
@export var label_height: float = 2.4
@export var camera_distance: float = 5.5
@export var camera_height: float = 2.2

## Выбор для слотов: [0] = A, [1] = B
var _sel_personality: Array[int] = [1, 2]
var _sel_build: Array[int] = [2, 1]
var _bots: Array[Enemy] = [null, null]
var _wins: Array[int] = [0, 0]
var _draws: int = 0
var _round_time: float = 0.0
var _round_over: bool = false
var _next_round_in: float = 0.0
var _winner_text: String = ""
var _time_scale_idx: int = 0

var _camera: Camera3D
var _labels: Array[Label] = [null, null]
var _header: Label
var _banner: Label
var _cam_side: Vector3 = Vector3.RIGHT


func _ready() -> void:
	if personalities.is_empty():
		for path in DEFAULT_PERSONALITIES:
			personalities.append(load(path) as AIPersonality)
	if builds.is_empty():
		for path in DEFAULT_BUILDS:
			builds.append(load(path) as CharacterStats)
	if time_scales.is_empty():
		time_scales = [1.0]
	_sel_personality = [clampi(start_personality_a, 0, personalities.size() - 1), clampi(start_personality_b, 0, personalities.size() - 1)]
	_sel_build = [clampi(start_build_a, 0, builds.size() - 1), clampi(start_build_b, 0, builds.size() - 1)]
	Engine.time_scale = start_time_scale
	_time_scale_idx = _nearest_time_scale_index(start_time_scale)
	_build_camera_and_ui()
	_start_round()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# --- Раунды ---

func _start_round() -> void:
	for i in 2:
		if is_instance_valid(_bots[i]):
			_bots[i].queue_free()
	_round_time = 0.0
	_round_over = false
	_winner_text = ""
	for i in 2:
		_bots[i] = _spawn_bot(i)


func _spawn_bot(slot: int) -> Enemy:
	var bot: Enemy = ENEMY_SCENE.instantiate() as Enemy
	var p: AIPersonality = personalities[_sel_personality[slot]]
	bot.name = "Bot%s_%s" % ["AB"[slot], p.display_name]
	bot.team = Enemy.Team.HOSTILE if slot == 0 else Enemy.Team.ALLY
	bot.stats = builds[_sel_build[slot]]
	bot.personality = p
	bot.can_dodge = bots_can_dodge
	bot.can_block = bots_can_block
	bot.can_kick = bots_can_kick
	var x: float = -spawn_distance if slot == 0 else spawn_distance
	bot.position = Vector3(x, 0.05, 0.0)
	add_child(bot)
	bot.ai_controller.can_heal_self = bots_can_heal
	bot.ai_controller.can_light_attack = bots_can_light_attack
	# Лицом друг к другу
	bot.pawn.rotation.y = atan2(-x, 0.0)
	bot.character_died.connect(_on_bot_died.bind(slot))
	return bot


func _on_bot_died(_attacker: Node3D, slot: int) -> void:
	if _round_over:
		# Второй умер в тот же момент: ничья вместо победы первого
		_wins[1 - slot] = maxi(0, _wins[1 - slot] - 1)
		_draws += 1
		_winner_text = "DRAW"
		return
	_round_over = true
	_next_round_in = next_round_delay
	_wins[1 - slot] += 1
	_winner_text = "WINNER: %s" % _slot_title(1 - slot)


func _slot_title(slot: int) -> String:
	var p: AIPersonality = personalities[_sel_personality[slot]]
	var b: CharacterStats = builds[_sel_build[slot]]
	return "%s %s [armor %d / agility %d]" % ["AB"[slot], p.display_name, b.armor, b.agility]


# --- Цикл ---

func _process(delta: float) -> void:
	if not _round_over:
		_round_time += delta
		if round_timeout > 0.0 and _round_time >= round_timeout:
			_round_over = true
			_next_round_in = next_round_delay
			_draws += 1
			_winner_text = "DRAW (timeout)"
	elif auto_next_round:
		_next_round_in -= delta
		if _next_round_in <= 0.0:
			_start_round()
	_update_camera(delta)
	_update_ui()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_Q: _change_selection(_sel_personality, 0, -1, personalities.size())
		KEY_W: _change_selection(_sel_personality, 0, 1, personalities.size())
		KEY_A: _change_selection(_sel_build, 0, -1, builds.size())
		KEY_S: _change_selection(_sel_build, 0, 1, builds.size())
		KEY_O: _change_selection(_sel_personality, 1, -1, personalities.size())
		KEY_P: _change_selection(_sel_personality, 1, 1, personalities.size())
		KEY_K: _change_selection(_sel_build, 1, -1, builds.size())
		KEY_L: _change_selection(_sel_build, 1, 1, builds.size())
		KEY_R: _start_round()
		KEY_BACKSPACE:
			_wins = [0, 0]
			_draws = 0
			_start_round()
		KEY_T:
			_time_scale_idx = (_time_scale_idx + 1) % time_scales.size()
			Engine.time_scale = time_scales[_time_scale_idx]


func _nearest_time_scale_index(value: float) -> int:
	var best: int = 0
	for i in time_scales.size():
		if absf(time_scales[i] - value) < absf(time_scales[best] - value):
			best = i
	return best


func _change_selection(sel: Array[int], slot: int, step: int, count: int) -> void:
	sel[slot] = posmod(sel[slot] + step, count)
	# Другая пара — другая статистика
	_wins = [0, 0]
	_draws = 0
	_start_round()


# --- Камера и оверлей ---

func _build_camera_and_ui() -> void:
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_camera.current = true
	add_child(_camera)
	_camera.position = Vector3(0.0, 4.0, 10.0)
	_camera.look_at(Vector3(0.0, 1.0, 0.0))

	var layer := CanvasLayer.new()
	add_child(layer)
	for i in 2:
		var label := Label.new()
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 6)
		label.add_theme_font_size_override("font_size", 15)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		layer.add_child(label)
		_labels[i] = label
	_header = Label.new()
	_header.position = Vector2(16.0, 12.0)
	_header.add_theme_color_override("font_outline_color", Color.BLACK)
	_header.add_theme_constant_override("outline_size", 6)
	layer.add_child(_header)
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-200.0, 120.0)
	_banner.custom_minimum_size = Vector2(400.0, 0.0)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 32)
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 10)
	layer.add_child(_banner)


func _update_camera(delta: float) -> void:
	var a: Enemy = _bots[0]
	var b: Enemy = _bots[1]
	if not is_instance_valid(a) or not is_instance_valid(b):
		return
	var mid: Vector3 = (a.global_position + b.global_position) * 0.5
	var line: Vector3 = b.global_position - a.global_position
	line.y = 0.0
	var dist: float = line.length()
	# Камера сбоку от линии бойцов; сторона не «перескакивает», когда бойцы меняются местами
	var side: Vector3 = Vector3.UP.cross(line.normalized()) if dist > 0.01 else _cam_side
	if side.dot(_cam_side) < 0.0:
		side = -side
	_cam_side = _cam_side.lerp(side, 1.0 - exp(-3.0 * delta)).normalized()
	var wanted: Vector3 = mid + _cam_side * (camera_distance + dist * 0.9) + Vector3.UP * (camera_height + dist * 0.3)
	_camera.global_position = _camera.global_position.lerp(wanted, 1.0 - exp(-4.0 * delta))
	var focus: Vector3 = mid + Vector3.UP * 1.0
	_camera.look_at(focus)


func _update_ui() -> void:
	_header.visible = show_overlay
	_banner.visible = show_overlay
	_header.text = "%s\n%s\nA %d : %d B   (draws %d)   round %.0fs   speed x%s\nQ/W A personality  A/S A build  |  O/P B personality  K/L B build  |  R restart  Backspace reset score  T speed" % [
		_slot_title(0), _slot_title(1), _wins[0], _wins[1], _draws, _round_time, str(Engine.time_scale)]
	_banner.text = _winner_text if (auto_next_round or not _round_over) else _winner_text + "\n(R - next round)"
	for i in 2:
		var bot: Enemy = _bots[i]
		var label: Label = _labels[i]
		if not is_instance_valid(bot):
			label.visible = false
			continue
		var head: Vector3 = bot.global_position + Vector3.UP * label_height
		label.visible = show_overlay and not _camera.is_position_behind(head)
		label.position = _camera.unproject_position(head) - Vector2(label.size.x * 0.5, label.size.y)
		label.text = _bot_text(i, bot)
		label.modulate = Color(1.0, 0.55, 0.45) if i == 0 else Color(0.5, 0.8, 1.0)


func _bot_text(slot: int, bot: Enemy) -> String:
	var ai: EnemyAIController = bot.ai_controller
	var tags: Array[String] = []
	if not bot.is_alive():
		tags.append("DEAD")
	else:
		if bot.is_blocking(): tags.append("block")
		if bot.is_attacking: tags.append("attack")
		if bot.is_kicking: tags.append("kick")
		if bot.is_dashing: tags.append("dash")
		if bot.is_healing: tags.append("HEAL")
		if bot.is_staggered: tags.append("stagger")
	var state: String = EnemyAIController.State.keys()[ai.current_state] if is_instance_valid(ai) else "-"
	var flasks: int = bot.heal_component.charges if is_instance_valid(bot.heal_component) else 0
	return "%s\nHP %s %d\nST %s %d  flasks %d\n%s %s" % [
		_slot_title(slot).get_slice(" [", 0),
		_bar(bot.current_health / maxf(bot.max_health, 1.0)), int(bot.current_health),
		_bar(bot.current_stamina / maxf(bot.max_stamina, 1.0)), int(bot.current_stamina), flasks,
		state, " ".join(tags)]


func _bar(fraction: float) -> String:
	var filled: int = clampi(roundi(fraction * 10.0), 0, 10)
	return "▮".repeat(filled) + "▯".repeat(10 - filled)
