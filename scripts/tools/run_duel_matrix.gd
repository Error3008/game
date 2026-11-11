extends SceneTree

## Измерительный инструмент (не тест): матрица дуэлей ботов для лога баланса docs/balance_log.md.
## Использует DuelRunner. Слот A — обычный враг, B — бот-союзник; слоты различаются слоем/группой,
## поэтому каждая пара играется в обоих слотах (проверка перекоса).
##
## Запуск (аргументы после `--`):
##   godot --headless -s res://scripts/tools/run_duel_matrix.gd -- mode=builds rounds=10 scale=8
##   mode=builds        билд × билд, личности нейтральные (пустая личность = база)
##   mode=personalities личность × личность при одинаковом билде (build=<индекс>, по умолчанию balanced)
##   rounds=N           раундов на каждый состав и каждый слот (по умолчанию 10)
##   scale=X            Engine.time_scale (по умолчанию 8)
##   maxtime=S          лимит раунда, с игровых (по умолчанию 90)
##   build=I            индекс билда для mode=personalities (по умолчанию 0: balanced)
## Строки результата начинаются с «MATRIX|», остальной вывод — шум боевого лога: `| grep '^MATRIX|'`.
## Порядок индексов совпадает с bot_duel.gd: билды 0 balanced / 1 armored / 2 agile,
## личности 0 duelist / 1 bully / 2 turtle, 3 = нейтральная (добавляется здесь).

const BUILD_NAMES: Array[String] = ["balanced", "armored", "agile"]
const PERS_NAMES: Array[String] = ["duelist", "bully", "turtle", "none"]
const NEUTRAL_PERS: int = 3


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: Dictionary = _parse_args()
	var mode: String = args.get("mode", "builds")
	var rounds: int = int(args.get("rounds", "10"))
	var scale: float = float(args.get("scale", "8"))
	var max_time: float = float(args.get("maxtime", "90"))
	var fixed_build: int = int(args.get("build", "0"))

	var duel: Node = DuelRunner.create_duel(self)
	await process_frame
	var neutral: AIPersonality = AIPersonality.new()
	neutral.display_name = "none"
	duel.personalities.append(neutral)

	print("MATRIX|mode=%s rounds=%d scale=%.1f maxtime=%.0f" % [mode, rounds, scale, max_time])
	print("MATRIX|%s" % "A | B | A wins | B wins | draws | unfinished | avg time, s | avg winner HP")
	var started_ms: int = Time.get_ticks_msec()
	if mode == "personalities":
		for a in 3:
			for b in range(a, 3):
				await _run_pair(duel, [fixed_build, a], [fixed_build, b], rounds, scale, max_time)
	else:
		for a in BUILD_NAMES.size():
			for b in range(a, BUILD_NAMES.size()):
				await _run_pair(duel, [a, NEUTRAL_PERS], [b, NEUTRAL_PERS], rounds, scale, max_time)
	print("MATRIX|total real time %.0fs" % ((Time.get_ticks_msec() - started_ms) / 1000.0))
	quit()


## Один состав «x против y»: `rounds` раундов с x в слоте A и столько же с x в слоте B.
## Строка по каждому слоту, чтобы перекос слотов был виден.
func _run_pair(duel: Node, x: Array, y: Array, rounds: int, scale: float, max_time: float) -> void:
	# Состав x в слоте A, y в слоте B
	await _run_cell(duel, x, y, rounds, scale, max_time)
	if x != y:
		# Те же составы, поменянные местами
		await _run_cell(duel, y, x, rounds, scale, max_time)


func _run_cell(duel: Node, a: Array, b: Array, rounds: int, scale: float, max_time: float) -> void:
	var a_wins: int = 0
	var b_wins: int = 0
	var draws: int = 0
	var unfinished: int = 0
	var time_sum: float = 0.0
	var hp_sum: float = 0.0
	var decided: int = 0
	for i in rounds:
		seed(7000 + i)
		var res: Dictionary = await DuelRunner.run_round(self, duel, a[0], a[1], b[0], b[1], scale, max_time)
		match res["outcome"]:
			DuelRunner.Outcome.A_WON:
				a_wins += 1
				hp_sum += res["hp_a"]
				decided += 1
			DuelRunner.Outcome.B_WON:
				b_wins += 1
				hp_sum += res["hp_b"]
				decided += 1
			DuelRunner.Outcome.DRAW:
				draws += 1
			_:
				unfinished += 1
		time_sum += res["time"]
	var avg_hp: float = hp_sum / maxf(1.0, float(decided))
	print("MATRIX|%s | %s | %d | %d | %d | %d | %.1f | %.0f" % [
		_title(a), _title(b), a_wins, b_wins, draws, unfinished, time_sum / maxf(1.0, float(rounds)), avg_hp,
	])


func _title(sel: Array) -> String:
	return "%s/%s" % [BUILD_NAMES[sel[0]], PERS_NAMES[sel[1]]]


func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		if parts.size() == 2:
			out[parts[0]] = parts[1]
	return out
