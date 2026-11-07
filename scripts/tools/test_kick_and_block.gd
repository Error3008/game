extends SceneTree

func _init() -> void:
	_run_tests()


func _run_tests() -> void:
	print("--- STARTING KICK & BOT BLOCKING UNIT TESTS ---")
	var scene: Node = (load("res://scenes/test_player.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var player: Player = scene.get_node("Player") as Player
	var dummy: Enemy = scene.get_node("ObstacleRooms/Room2_LeftWall/Dummy_LeftWall") as Enemy

	assert(player != null, "Player must exist")
	assert(dummy != null, "Dummy must exist")
	assert(player.kick_component != null, "Player must have KickComponent")
	assert(dummy.kick_component != null, "Dummy must have KickComponent")
	assert(player.defense_component != null, "Player must have DefenseComponent")
	assert(dummy.defense_component != null, "Dummy must have DefenseComponent")

	# Position player and dummy directly facing each other at 1.5m distance
	player.global_position = Vector3(0.0, 0.0, 0.0)
	dummy.global_position = Vector3(0.0, 0.0, -1.5)
	player.pawn.rotation.y = atan2(dummy.global_position.x - player.global_position.x, dummy.global_position.z - player.global_position.z)
	dummy.pawn.rotation.y = atan2(player.global_position.x - dummy.global_position.x, player.global_position.z - dummy.global_position.z)
	player.cmd_set_target(dummy)
	dummy.cmd_set_target(player)

	# --- TEST 1: Kick Stamina & Setup ---
	print("\n[TEST 1] Kick Stamina & Setup")
	player.stamina_component.current_stamina = 100.0
	var kick_cost: float = player.kick_component.stamina_cost
	assert(kick_cost == 20.0, "Kick stamina cost should be 20.0")

	var kick_res := player.cmd_kick()
	assert(kick_res == true, "Player should be able to kick")
	assert(player.is_kicking == true, "Player is_kicking should be true")
	assert(player.current_stamina == 80.0, "Player stamina should be 80.0 after kick")
	print("Player successfully initiated kick. Stamina: ", player.current_stamina)
	player.kick_component.cancel_kick()
	assert(player.is_kicking == false, "Player is_kicking should be false after cancel")
	print(">> TEST 1 PASSED")

	# --- TEST 2: Kick vs Blocking Target (GUARD BREAK) ---
	print("\n[TEST 2] Kick vs Blocking Target (GUARD BREAK)")
	dummy.stamina_component.current_stamina = 100.0
	dummy.health_component.current_health = 100.0
	dummy.is_staggered = false
	dummy.cmd_block_start()
	assert(dummy.is_blocking() == true, "Dummy must be in block stance")

	var hit_data := {"received": false, "broke_guard": false}
	var hit_callback = func(target: Node3D, broke_guard: bool):
		hit_data["received"] = true
		hit_data["broke_guard"] = broke_guard

	player.kick_component.kick_hit_landed.connect(hit_callback)

	player.cmd_kick()
	# Simulate kick progress into active phase (t = 0.40s)
	player.kick_component.process_kick(0.40)

	assert(hit_data["received"] == true, "Kick hit signal should have been emitted")
	assert(hit_data["broke_guard"] == true, "Kick must break guard of blocking target")
	assert(dummy.is_blocking() == false, "Dummy block must be forcibly collapsed")
	assert(dummy.is_staggered == true, "Dummy must be staggered by Guard Break")
	assert(dummy.stagger_timer >= 1.4, "Dummy stagger timer must be ~1.5s")
	assert(dummy.stamina_component.current_stamina <= 50.0, "Dummy stamina should be penalized by 50.0")
	assert(dummy.current_health < 100.0, "Dummy should have taken kick guard break damage")
	print("Dummy after Guard Break: Staggered=%s (timer=%.2f), HP=%.1f, Stamina=%.1f" % [dummy.is_staggered, dummy.stagger_timer, dummy.current_health, dummy.current_stamina])

	player.kick_component.cancel_kick()
	dummy.is_staggered = false
	dummy.stagger_timer = 0.0
	print(">> TEST 2 PASSED")

	# --- TEST 3: Kick vs Non-Blocking Target (Safe Unblocked Impact) ---
	print("\n[TEST 3] Kick vs Non-Blocking Target (Safe Unblocked Impact)")
	player.global_position = Vector3(0.0, 0.0, 0.0)
	dummy.global_position = Vector3(0.0, 0.0, -1.5)
	player.pawn.rotation.y = atan2(dummy.global_position.x - player.global_position.x, dummy.global_position.z - player.global_position.z)
	dummy.pawn.rotation.y = atan2(player.global_position.x - dummy.global_position.x, player.global_position.z - dummy.global_position.z)
	dummy.defense_component.end_block()
	dummy.is_staggered = false
	dummy.stamina_component.current_stamina = 100.0
	dummy.health_component.current_health = 100.0
	assert(dummy.is_blocking() == false, "Dummy must NOT be blocking")

	hit_data["received"] = false
	hit_data["broke_guard"] = false

	player.cmd_kick()
	player.kick_component.process_kick(0.40)

	assert(hit_data["received"] == true, "Kick hit signal should have been emitted")
	assert(hit_data["broke_guard"] == false, "Kick must NOT trigger Guard Break on non-blocking target")
	assert(dummy.stagger_timer < 1.0, "Target without block should only get a short hit-react, NOT a 1.5s guard-break stagger")
	assert(dummy.stamina_component.current_stamina == 100.0, "Target stamina should NOT be depleted")
	assert(dummy.current_health == 90.0, "Target should only take 10 unblocked damage")
	print("Non-blocking target after Kick: Staggered=%s, HP=%.1f, Stamina=%.1f" % [dummy.is_staggered, dummy.current_health, dummy.current_stamina])

	player.kick_component.cancel_kick()
	print(">> TEST 3 PASSED")

	# --- TEST 4: Unparryable Kick (Kick vs Active Parry) ---
	print("\n[TEST 4] Unparryable Kick (Kick vs Active Parry)")
	player.global_position = Vector3(0.0, 0.0, 0.0)
	dummy.global_position = Vector3(0.0, 0.0, -1.5)
	player.pawn.rotation.y = atan2(dummy.global_position.x - player.global_position.x, dummy.global_position.z - player.global_position.z)
	dummy.pawn.rotation.y = atan2(player.global_position.x - dummy.global_position.x, player.global_position.z - dummy.global_position.z)
	dummy.is_staggered = false # сброс Hit_React из теста 3 (время в тесте не идёт)
	dummy.cmd_block_start()
	dummy.cmd_parry()
	assert(dummy.defense_component.block_state == DefenseComponent.BlockState.ACTIVE_PARRY, "Dummy must be in active parry window")

	hit_data["received"] = false
	hit_data["broke_guard"] = false

	player.cmd_kick()
	player.kick_component.process_kick(0.40)

	assert(hit_data["received"] == true, "Kick hit signal should have been emitted")
	assert(hit_data["broke_guard"] == true, "Kick must shatter active parry")
	assert(dummy.is_staggered == true, "Dummy must be staggered even if attempting parry")
	assert(dummy.is_blocking() == false, "Dummy parry state must be collapsed")
	print("Active parry successfully broken by kick!")

	player.kick_component.kick_hit_landed.disconnect(hit_callback)
	player.kick_component.cancel_kick()
	dummy.is_staggered = false
	print(">> TEST 4 PASSED")

	# --- TEST 5: Dodge Cancel during Kick Recovery ---
	print("\n[TEST 5] Dodge Cancel during Kick Recovery")
	player.stamina_component.current_stamina = 100.0
	player.cmd_kick()
	assert(player.is_kicking == true, "Player should be kicking")
	assert(player.kick_component.is_in_recovery() == false, "Kick should not be in recovery at t=0.0")

	# Cannot dash during windup or active
	var dash_during_active := player.cmd_dash(DashComponent.DashDirection.FORWARD)
	assert(dash_during_active == false, "Cannot dodge cancel during active kick phase")

	# Advance to recovery phase (t = 0.60s)
	player.kick_component.process_kick(0.60)
	assert(player.kick_component.is_in_recovery() == true, "Kick should be in recovery at t=0.60")

	# Now dodge cancel succeeds
	var dash_during_recovery := player.cmd_dash(DashComponent.DashDirection.FORWARD)
	assert(dash_during_recovery == true, "Dodge cancel must succeed during recovery phase")
	assert(player.is_kicking == false, "Kick must be cancelled by dodge")
	assert(player.is_dashing == true, "Player should now be dashing")
	player.dash_component.end_dash()
	print(">> TEST 5 PASSED")

	# --- TEST 6: Bot Blocking & Counter-Kick ---
	print("\n[TEST 6] Bot Blocking & Counter-Kick")
	# Reset dummy state and stamina
	dummy.is_staggered = false
	dummy.stagger_timer = 0.0
	dummy.defense_component.end_block()
	dummy.stamina_component.current_stamina = 100.0
	dummy.health_component.current_health = 100.0
	dummy.pawn.rotation.y = atan2(player.global_position.x - dummy.global_position.x, player.global_position.z - dummy.global_position.z)

	# Test bot blocking command
	var bot_block_res := dummy.cmd_block_start()
	assert(bot_block_res == true, "Bot should be able to raise block")
	assert(dummy.is_blocking() == true, "Bot is_blocking should be true")

	# Bot blocks incoming hit
	var eval := dummy.defense_component.evaluate_hit(35.0, Vector3(0, 0, -2), player)
	assert(eval["was_blocked"] == true, "Incoming strike must be absorbed by bot block")
	assert(eval["damage_taken"] < 6.0, "Bot block should absorb 85% damage")
	dummy.cmd_block_release()

	# Test bot counter-kick against player holding block
	player.global_position = Vector3(0.0, 0.0, 0.0)
	dummy.global_position = Vector3(0.0, 0.0, -1.5)
	player.pawn.rotation.y = atan2(dummy.global_position.x - player.global_position.x, dummy.global_position.z - player.global_position.z)
	dummy.pawn.rotation.y = atan2(player.global_position.x - dummy.global_position.x, player.global_position.z - dummy.global_position.z)
	player.cmd_set_target(dummy)
	dummy.cmd_set_target(player)

	player.stamina_component.current_stamina = 100.0
	player.defense_component.end_block()
	player.is_staggered = false
	player.cmd_block_start()
	assert(player.is_blocking() == true, "Player is holding block")

	# Bot kicks player
	dummy.stamina_component.current_stamina = 100.0
	dummy.cmd_kick()
	assert(dummy.is_kicking == true, "Bot should initiate kick")
	dummy.kick_component.process_kick(0.40)

	assert(player.is_blocking() == false, "Player block must be broken by bot kick")
	assert(player.is_staggered == true, "Player must be staggered for 1.5s by bot kick")
	print("Player staggered by Bot Kick: Staggered=%s (timer=%.2f)" % [player.is_staggered, player.stagger_timer])
	dummy.kick_component.cancel_kick()
	player.is_staggered = false
	print(">> TEST 6 PASSED")

	print("\n==============================================")
	print("ALL 6 KICK & BOT BLOCKING TESTS PASSED 100%!")
	print("==============================================")
	quit()
