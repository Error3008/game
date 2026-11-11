class_name DuelRunner
extends RefCounted

## Общий кусок для headless-инструментов дуэли ботов (scenes/bot_duel.tscn):
## создание дуэли, выбор состава, прогон раунда до конца и разбор итога.
## Используют test_bot_duel.gd (регрессия) и run_duel_matrix.gd (измерение баланса).
## Раннер ничего не знает про asserts и таблицы: он только играет раунд и возвращает факты.
## Составы задаются индексами в `duel.builds` / `duel.personalities`.

const DUEL_SCENE: PackedScene = preload("res://scenes/bot_duel.tscn")

enum Outcome { A_WON, B_WON, DRAW, UNFINISHED }


## Создаёт дуэль для headless-прогонов: без автоперезапуска раундов. Раунд запускает вызывающий.
static func create_duel(tree: SceneTree) -> Node:
	var duel: Node = DUEL_SCENE.instantiate()
	duel.set("auto_next_round", false)
	tree.root.add_child(duel)
	return duel


## Выбирает составы и запускает новый раунд. Не ждёт его конца.
static func start_round(duel: Node, build_a: int, pers_a: int, build_b: int, pers_b: int) -> void:
	duel._sel_build = [build_a, build_b] as Array[int]
	duel._sel_personality = [pers_a, pers_b] as Array[int]
	duel._start_round()


## Ждёт конца текущего раунда по физическим кадрам, пока не истечёт `max_time` секунд
## игрового времени. Возвращает словарь:
##   outcome: Outcome, time: float (с), hp_a / hp_b: float (на момент конца),
##   a_hit_b / b_hit_a: bool (наносил ли бот урон хоть раз).
## Если раунд не закончился за `max_time`, outcome = UNFINISHED.
static func wait_round_end(tree: SceneTree, duel: Node, max_time: float) -> Dictionary:
	var wins_before: Array[int] = [duel._wins[0], duel._wins[1]]
	var draws_before: int = duel._draws
	var a: Enemy = duel._bots[0]
	var b: Enemy = duel._bots[1]
	var a_hit_b: bool = false
	var b_hit_a: bool = false
	var dt: float = 1.0 / Engine.physics_ticks_per_second
	var waited: float = 0.0
	while not duel._round_over and waited < max_time:
		await tree.physics_frame
		waited += dt
		a_hit_b = a_hit_b or b.current_health < b.max_health
		b_hit_a = b_hit_a or a.current_health < a.max_health
	var outcome: Outcome = Outcome.UNFINISHED
	if duel._round_over:
		if duel._draws > draws_before:
			outcome = Outcome.DRAW
		elif duel._wins[0] > wins_before[0]:
			outcome = Outcome.A_WON
		elif duel._wins[1] > wins_before[1]:
			outcome = Outcome.B_WON
	return {
		"outcome": outcome,
		"time": duel._round_time,
		"hp_a": a.current_health,
		"hp_b": b.current_health,
		"a_hit_b": a_hit_b,
		"b_hit_a": b_hit_a,
	}


## Запускает раунд с заданным составом и ждёт конца на скорости `time_scale`.
## Прежний Engine.time_scale восстанавливается.
static func run_round(tree: SceneTree, duel: Node, build_a: int, pers_a: int, build_b: int, pers_b: int, time_scale: float, max_time: float) -> Dictionary:
	var prev_scale: float = Engine.time_scale
	start_round(duel, build_a, pers_a, build_b, pers_b)
	Engine.time_scale = time_scale
	var result: Dictionary = await wait_round_end(tree, duel, max_time)
	Engine.time_scale = prev_scale
	return result
