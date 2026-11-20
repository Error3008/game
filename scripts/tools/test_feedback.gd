extends SceneTree
## Задача 2.1: CombatFeedback — плавные глобальные замедления («моменты»).


func _init() -> void:
	_run_tests()


func _near(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps


func _run_tests() -> void:
	print("--- STARTING FEEDBACK TESTS ---")
	var scene: Node = (load("res://scenes/test_player.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var player: Player = scene.get_node("Player") as Player
	var dummy: Enemy = scene.get_node("ObstacleRooms/Room2_LeftWall/Dummy_LeftWall") as Enemy
	var fb: CombatFeedback = root.find_children("*", "CombatFeedback", true, false)[0] as CombatFeedback
	assert(fb != null, "feedback created by player")
	assert(not fb.enabled, "disabled in headless")
	assert(_near(Engine.time_scale, 1.0), "time normal at start")

	print("\n[TEST 1] curve: ramp in, hold, ramp out")
	assert(fb.begin(CombatFeedback.Moment.PARRY, 1000), "parry starts")
	fb.tick(1000)
	assert(_near(Engine.time_scale, 1.0), "starts from normal")
	fb.tick(1040)  # середина входа (0.04 из 0.08): smoothstep(0.5) = 0.5
	assert(_near(Engine.time_scale, 0.65, 0.01), "mid ramp in: %f" % Engine.time_scale)
	fb.tick(1200)
	assert(_near(Engine.time_scale, fb.parry_scale), "hold")
	fb.tick(1330 + 175)  # середина выхода
	assert(Engine.time_scale > fb.parry_scale and Engine.time_scale < 1.0, "ramp out")
	var prev: float = 0.0
	for ms in range(1000, 1700, 10):  # кривая без скачков
		fb.tick(ms)
		assert(absf(Engine.time_scale - prev) < 0.2 or ms == 1000, "no jump at %d" % ms)
		prev = Engine.time_scale
	fb.tick(1700)
	assert(_near(Engine.time_scale, 1.0) and not fb.is_active(), "back to 1.0")
	print(">> TEST 1 PASSED")

	print("\n[TEST 2] cooldown, priority, kill override")
	assert(not fb.begin(CombatFeedback.Moment.PARRY, 2000), "blocked by cooldown")
	assert(fb.begin(CombatFeedback.Moment.PARRY, 4000), "after cooldown")
	assert(not fb.begin(CombatFeedback.Moment.GUARD_BREAK, 4050), "weaker does not override")
	assert(fb.begin(CombatFeedback.Moment.KILL, 4100), "kill overrides")
	fb.tick(4100 + 5000)
	assert(_near(Engine.time_scale, 1.0) and not fb.is_active(), "no sticking")
	assert(fb.begin(CombatFeedback.Moment.KILL, 9100), "kill ignores cooldown")
	fb.tick(20000)
	print(">> TEST 2 PASSED")

	print("\n[TEST 3] hit events: only special moments, player involved")
	fb.enabled = true
	fb._last_end_msec = -1000000
	player.restore_full()
	dummy.restore_full()
	player.take_hit(DamageInfo.make(10.0, Vector3.ZERO, dummy))
	assert(not fb.is_active(), "ordinary hit triggers nothing")
	assert(_near(Engine.time_scale, 1.0), "time untouched")
	dummy.take_hit(DamageInfo.make(10000.0, Vector3.ZERO, player))
	assert(not dummy.is_alive() and fb.is_active(), "killing blow by player triggers")
	fb.tick(Time.get_ticks_msec() + 10000)
	assert(_near(Engine.time_scale, 1.0), "restored")
	fb.player_only = true
	var other: Enemy = scene.get_node_or_null("ObstacleRooms/Room1_RightWall/Dummy_RightWall") as Enemy
	if other != null:
		other.restore_full()
		dummy.restore_full()
		dummy.take_hit(DamageInfo.make(10000.0, Vector3.ZERO, other))
		assert(not fb.is_active(), "bots without player do not trigger")
	fb.enabled = false
	print(">> TEST 3 PASSED")

	print("\n[TEST 4] exit restores time")
	fb.enabled = true
	fb.begin(CombatFeedback.Moment.KILL, Time.get_ticks_msec())
	fb.tick(Time.get_ticks_msec() + 200)
	assert(Engine.time_scale < 1.0, "slowed")
	fb._exit_tree()
	assert(_near(Engine.time_scale, 1.0), "restored on exit")
	print(">> TEST 4 PASSED")

	print("\nALL FEEDBACK TESTS PASSED 100%!")
	quit()
