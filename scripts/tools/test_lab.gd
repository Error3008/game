extends SceneTree

## Тестовая лаборатория (test_player.tscn): порталы, клетки дуэлей, сброс игрока.
## Запуск: godot --headless -s res://scripts/tools/test_lab.gd (с timeout)


func _init() -> void:
	_run()


func _wait_physics(frames: int) -> void:
	for i: int in frames:
		await physics_frame


func _portals(lab: Node) -> Array[ArenaPortal]:
	var out: Array[ArenaPortal] = []
	for c in lab.get_children():
		if c is ArenaPortal:
			out.append(c as ArenaPortal)
	return out


func _run() -> void:
	print("--- STARTING TEST LAB TESTS ---")
	var scene: Node = (load("res://scenes/test_player.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var player: Player = scene.get_node("Player") as Player
	var lab: TestLab = scene.get_node("TestLab") as TestLab
	assert(lab != null, "TestLab must exist")
	# Контроллер игрока сбросил бы цель/блок — в тесте отключаем (см. CLAUDE.md §8).
	var ctrl: Node = player.get_node_or_null("PlayerController")
	if ctrl != null:
		ctrl.set_process(false)
		ctrl.set_physics_process(false)
		ctrl.set_process_unhandled_input(false)

	# --- Test 1: структура ---
	var portals := _portals(lab)
	# арена->хаб, хаб->арена, 7 хаб->клетка, 7 клетка->хаб
	assert(portals.size() == 2 + TestLab.CELLS.size() * 2, "Portal count (was %d)" % portals.size())
	var cells: Array[DuelCell] = []
	for c in lab.get_children():
		if c is DuelCell:
			cells.append(c as DuelCell)
	assert(cells.size() == TestLab.CELLS.size(), "Cell count")
	print(">> TEST 1 PASSED")

	# --- Test 2: реальный вход в портал на арене -> хаб, полный сброс ---
	var arena_portal: ArenaPortal = null
	for p in portals:
		if p.global_position.is_equal_approx(TestLab.ARENA_PORTAL_POS):
			arena_portal = p
	assert(arena_portal != null, "Arena portal at ARENA_PORTAL_POS")
	player.health_component.take_damage(50.0)
	player.stamina_component.consume(60.0)
	player.heal_component.charges = 0
	assert(player.current_health < player.max_health, "Player damaged before teleport")
	player.global_position = TestLab.ARENA_PORTAL_POS + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	await _wait_physics(120)
	assert(player.global_position.y > TestLab.HUB_HEIGHT - 1.0, "Player teleported to hub (y=%.2f)" % player.global_position.y)
	assert(is_equal_approx(player.current_health, player.max_health), "Health restored")
	assert(is_equal_approx(player.current_stamina, player.max_stamina), "Stamina restored")
	assert(player.heal_component.charges == player.heal_component.max_charges, "Flask charges restored")
	print(">> TEST 2 PASSED")

	# --- Test 3: портал в клетку Bully создаёт врага с нужными статами/характером ---
	var bully_cell: DuelCell = lab.get_node("Cell_Bully") as DuelCell
	var bully_portal: ArenaPortal = null
	for p in portals:
		if p.target_cell == bully_cell:
			bully_portal = p
	assert(bully_portal != null, "Portal to Bully cell")
	ArenaPortal._next_allowed_msec = 0
	bully_portal._player = player
	bully_portal._teleport()
	await _wait_physics(2)
	var e1: Enemy = bully_cell.get_node_or_null("Enemy_Bully") as Enemy
	assert(e1 != null, "Bully cell spawned an enemy")
	assert(e1.personality != null and e1.personality.resource_path.ends_with("personality_bully.tres"), "Bully personality")
	assert(e1.stats.resource_path.ends_with("enemy_agile.tres"), "Bully uses agile build")
	assert(player.global_position.distance_to(bully_cell.arrival.global_position) < 0.5, "Player at cell arrival")
	print(">> TEST 3 PASSED")

	# --- Test 4: повторный вход пересоздаёт врага (труп/избитый не мешает) ---
	e1.health_component.take_damage(30.0)
	bully_portal._player = player
	bully_portal._teleport()
	await _wait_physics(3)
	var alive := 0
	for c in bully_cell.get_children():
		if c is Enemy and not c.is_queued_for_deletion():
			alive += 1
			assert(is_equal_approx((c as Enemy).current_health, (c as Enemy).max_health), "Fresh enemy has full HP")
	assert(alive == 1, "Exactly one fresh enemy (was %d)" % alive)
	print(">> TEST 4 PASSED")

	# --- Test 5: манекен ---
	var dummy_cell: DuelCell = lab.get_node("Cell_Манекен") as DuelCell
	dummy_cell.respawn()
	await _wait_physics(2)
	var d: Enemy = dummy_cell.get_node("Enemy_Манекен") as Enemy
	assert(d != null and d.is_dummy, "Dummy cell enemy is a dummy")
	print(">> TEST 5 PASSED")

	print("ALL TEST LAB TESTS PASSED 100%!")
	quit()
