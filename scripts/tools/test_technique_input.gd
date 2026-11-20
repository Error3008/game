extends SceneTree
## Задача 1.7: буфер ввода, слоты приёмов, поиск по триггеру, input-действия 1–4.

var player: Player


func _init() -> void:
	_run_tests()


func _tech(id: StringName, trigger: StringName) -> TechniqueData:
	var t := TechniqueData.new()
	t.id = id
	t.kind = TechniqueData.Kind.BUFF
	t.trigger = trigger
	t.duration = 0.5
	return t


func _run_tests() -> void:
	print("--- STARTING TECHNIQUE INPUT TESTS ---")

	# ---------- TEST 1: InputBuffer ----------
	print("\n[TEST 1] input buffer")
	var buf := InputBuffer.new()
	assert(not buf.consume(&"a", 0.0), "empty buffer")
	buf.push(&"a", 1.0)
	assert(buf.has(&"a", 1.15) and buf.consume(&"a", 1.15), "fresh press consumed")
	assert(not buf.consume(&"a", 1.16), "consumed once")
	buf.push(&"a", 1.0)
	assert(not buf.consume(&"a", 1.5), "stale press expired")
	buf.push(&"a", 2.0)
	buf.clear()
	assert(not buf.has(&"a", 2.0), "clear")
	print(">> TEST 1 PASSED")

	var scene: Node = (load("res://scenes/test_player.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	player = scene.get_node("Player") as Player
	player.set_physics_process(false)
	for child in player.get_children():
		if child is PlayerController:
			child.set_process(false)
			child.set_physics_process(false)
	var tc: TechniqueComponent = player.technique_component

	# ---------- TEST 2: слоты ----------
	print("\n[TEST 2] slots")
	assert(tc.slots.size() == 4 and tc.slots[0] == &"", "four empty slots")
	assert(not tc.use_slot(0), "empty slot does nothing")
	assert(not tc.bind_slot(0, &"zzz"), "cannot bind unequipped")
	assert(not tc.bind_slot(4, &""), "bad index")
	tc.equip(_tech(&"t1", TechniqueData.TRIGGER_SLOT))
	assert(tc.bind_slot(1, &"t1"), "bind slot 2")
	var started := [0]
	tc.technique_started.connect(func(_d: TechniqueData) -> void: started[0] += 1)
	assert(tc.use_slot(1) and started[0] == 1, "slot starts technique")
	tc.cancel()
	tc.unequip(&"t1")
	assert(tc.slots[1] == &"", "unequip clears slot")
	print(">> TEST 2 PASSED")

	# ---------- TEST 3: контекстные триггеры ----------
	print("\n[TEST 3] trigger lookup")
	assert(tc.find_by_trigger(TechniqueData.TRIGGER_HEAVY_HOLD) == null, "none equipped")
	var crush := _tech(&"crush", TechniqueData.TRIGGER_HEAVY_HOLD)
	tc.equip(crush)
	assert(tc.find_by_trigger(TechniqueData.TRIGGER_HEAVY_HOLD) == crush, "found by trigger")
	assert(tc.find_by_trigger(TechniqueData.TRIGGER_BLOCK_KICK) == null, "other trigger empty")
	print(">> TEST 3 PASSED")

	# ---------- TEST 4: input-действия ----------
	print("\n[TEST 4] input actions")
	for i in range(1, 5):
		assert(InputMap.has_action("technique_%d" % i), "action technique_%d" % i)
	print(">> TEST 4 PASSED")

	print("\nALL TECHNIQUE INPUT TESTS PASSED 100%!")
	quit()
