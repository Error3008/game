extends SceneTree
## Задача 2.2: CombatFX — выбор эффекта по исходу, пул, точка контакта.


func _init() -> void:
	_run_tests()


func _run_tests() -> void:
	print("--- STARTING FX TESTS ---")
	var scene: Node = (load("res://scenes/test_player.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var fx: CombatFX = root.find_children("*", "CombatFX", true, false)[0] as CombatFX
	assert(fx != null, "fx created by player")
	assert(not fx.enabled, "disabled in headless")

	print("\n[TEST 1] outcome -> kind")
	assert(CombatFX.kind_for({"dodged": true}) == -1)
	assert(CombatFX.kind_for({"was_parried": true}) == CombatFX.Kind.PARRY)
	assert(CombatFX.kind_for({"was_guard_broken": true, "was_blocked": true}) == CombatFX.Kind.GUARD_BREAK)
	assert(CombatFX.kind_for({"was_blocked": true, "final_damage": 3.0}) == CombatFX.Kind.BLOCK)
	assert(CombatFX.kind_for({"final_damage": 10.0}) == CombatFX.Kind.HIT)
	assert(CombatFX.kind_for({"final_damage": 0.0}) == -1)
	print(">> TEST 1 PASSED")

	print("\n[TEST 2] pool: no growth, round robin, position")
	var count_before: int = fx.get_child_count()
	var first: GPUParticles3D = fx.spawn(CombatFX.Kind.HIT, Vector3(1, 2, 3))
	assert(first.global_position.is_equal_approx(Vector3(1, 2, 3)), "position")
	for i in fx.pool_size - 1:
		fx.spawn(CombatFX.Kind.HIT, Vector3.ZERO)
	assert(fx.spawn(CombatFX.Kind.HIT, Vector3.ZERO) == first, "wraps around")
	for i in 50:
		fx.spawn(CombatFX.Kind.PARRY, Vector3.ZERO)
	assert(fx.get_child_count() == count_before, "pool did not grow")
	assert(fx.spawn(CombatFX.Kind.PARRY, Vector3.ZERO).get_node_or_null("Flash") != null, "parry has light")
	print(">> TEST 2 PASSED")

	print("\n[TEST 3] hit event spawns at contact point")
	fx.enabled = true
	var player: Player = scene.get_node("Player") as Player
	var dummy: Enemy = scene.get_node("ObstacleRooms/Room2_LeftWall/Dummy_LeftWall") as Enemy
	player.restore_full()
	dummy.restore_full()
	var info: DamageInfo = DamageInfo.make(10.0, Vector3.ZERO, player)
	info.contact_point = Vector3(5, 6, 7)
	info.has_contact_point = true
	var nxt: int = fx._next[CombatFX.Kind.HIT]
	dummy.take_hit(info)
	var used: GPUParticles3D = fx._pools[CombatFX.Kind.HIT][nxt]
	assert(used.global_position.is_equal_approx(Vector3(5, 6, 7)), "at contact point")
	fx.enabled = false
	print(">> TEST 3 PASSED")

	print("\n[TEST 4] kick guard break and blade crossing")
	var kick_info: DamageInfo = DamageInfo.make(10.0, Vector3.ZERO, player, &"kick")
	assert(CombatFX.kind_for({"final_damage": 10.0}, kick_info) == CombatFX.Kind.HIT, "plain kick = hit")
	kick_info.broke_guard = true
	assert(CombatFX.kind_for({"final_damage": 10.0}, kick_info) == CombatFX.Kind.GUARD_BREAK, "guard-breaking kick")
	# Клинки рядом: искры на скрещении, а не на теле; клинки далеко: на теле
	var hit: DamageInfo = DamageInfo.make(10.0, Vector3.ZERO, player, &"light")
	var body_point: Vector3 = fx._contact_for(CombatFX.Kind.HIT, hit, dummy)
	assert(body_point.distance_to(dummy.global_position + Vector3.UP * fx.chest_height) < 0.5, "hit on body")
	var guarded: Vector3 = fx._contact_for(CombatFX.Kind.BLOCK, hit, dummy)
	assert(guarded.is_finite(), "block point valid")
	fx.crossing_max_gap = 0.0
	var far: Vector3 = fx._contact_for(CombatFX.Kind.BLOCK, hit, dummy)
	assert(far.distance_to(dummy.global_position + Vector3.UP * fx.chest_height) < 0.5, "far blades -> body")
	print(">> TEST 4 PASSED")

	print("\nALL FX TESTS PASSED 100%!")
	quit()
