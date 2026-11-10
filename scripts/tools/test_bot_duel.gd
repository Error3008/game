extends SceneTree

## Регрессия дуэли ботов (scenes/bot_duel.tscn): бот-союзник (Enemy.Team.ALLY) и обычный враг
## находят друг друга, дерутся, один из них умирает; игрок/камера не путают бота с героем.

func _init() -> void:
	_run_tests()


func _run_tests() -> void:
	print("--- STARTING BOT DUEL TESTS ---")
	seed(4242)
	var duel: Node = (load("res://scenes/bot_duel.tscn") as PackedScene).instantiate()
	root.add_child(duel)
	await process_frame
	# Два агрессора с одинаковым билдом: бой должен закончиться быстро
	duel._sel_personality = [1, 1] as Array[int]
	duel._sel_build = [0, 0] as Array[int]
	duel._start_round()
	await physics_frame
	await physics_frame

	var a: Enemy = duel._bots[0]
	var b: Enemy = duel._bots[1]

	print("\n[TEST 1] Teams: A hostile (layer 4, group enemy), B ally (layer 2, group ally, not player/enemy)")
	assert(a.is_in_group("enemy") and not a.is_in_group("ally"), "A is a regular enemy")
	assert(b.is_in_group("ally") and not b.is_in_group("enemy") and not b.is_in_group("player"), "B is an ally bot, not the hero")
	assert(a.collision_layer == 4 and b.collision_layer == 2, "Layers 4 and 2, got %d/%d" % [a.collision_layer, b.collision_layer])
	assert(a.hitbox_target_mask == 2 and b.hitbox_target_mask == 4, "Hitboxes scan the opposite layer")
	assert(b.ai_controller.target_groups.size() == 1 and b.ai_controller.target_groups[0] == &"enemy", "Ally targets enemies only")
	print(">> TEST 1 PASSED")

	print("\n[TEST 2] Bots acquire each other as targets")
	var t: float = 0.0
	while t < 5.0 and (a.ai_controller.target != b or b.ai_controller.target != a):
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	assert(a.ai_controller.target == b, "A targets B")
	assert(b.ai_controller.target == a, "B targets A")
	print(">> TEST 2 PASSED")

	print("\n[TEST 3] The duel ends: both land hits, one dies, a winner is recorded")
	Engine.time_scale = 8.0
	var a_hit: bool = false
	var b_hit: bool = false
	while not duel._round_over and duel._round_time < 120.0:
		await physics_frame
		a_hit = a_hit or b.current_health < b.max_health
		b_hit = b_hit or a.current_health < a.max_health
	Engine.time_scale = 1.0
	print("   round time %.1fs, A hp %.0f, B hp %.0f, wins %s, draws %d" % [duel._round_time, a.current_health, b.current_health, str(duel._wins), duel._draws])
	assert(a_hit and b_hit, "Both bots damage each other (A hit B: %s, B hit A: %s)" % [a_hit, b_hit])
	assert(duel._round_over, "The duel ended within 120s")
	assert(not a.is_alive() or not b.is_alive() or duel._draws > 0, "Someone died (or timeout draw)")
	assert(duel._wins[0] + duel._wins[1] + duel._draws == 1, "Exactly one result recorded")
	print(">> TEST 3 PASSED")

	print("\n[TEST 4] Next round respawns both bots alive; changing selection resets the score")
	duel._start_round()
	await physics_frame
	assert(is_instance_valid(duel._bots[0]) and duel._bots[0].is_alive(), "A respawned")
	assert(is_instance_valid(duel._bots[1]) and duel._bots[1].is_alive(), "B respawned")
	duel._change_selection(duel._sel_personality, 0, 1, duel.personalities.size())
	assert(duel._wins[0] == 0 and duel._wins[1] == 0 and duel._draws == 0, "Score reset on selection change")
	print(">> TEST 4 PASSED")

	print("\nALL BOT DUEL TESTS PASSED 100%!")
	quit()
