extends SceneTree

func _init() -> void:
	_run_tests()


func _run_tests() -> void:
	print("--- STARTING STAMINA & GUARD BREAK UNIT TESTS ---")
	var scene: Node = (load("res://scenes/test_player.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame

	var player: Player = scene.get_node("Player") as Player
	var dummy: Enemy = scene.get_node("ObstacleRooms/Room2_LeftWall/Dummy_LeftWall") as Enemy

	assert(player != null, "Player must exist")
	assert(dummy != null, "Dummy must exist")
	assert(player.stamina_component != null, "Player must have StaminaComponent")
	assert(dummy.stamina_component != null, "Dummy must have StaminaComponent")

	# Test 1: Capacity & Setup
	print("\n[TEST 1] Capacity & Setup")
	print("Player Max Stamina: ", player.max_stamina, " Current: ", player.current_stamina)
	assert(player.max_stamina == 100.0, "Player max stamina should be 100.0")
	assert(player.current_stamina == 100.0, "Player current stamina should be 100.0")
	print(">> TEST 1 PASSED")

	# Test 2: Dash Stamina Consumption
	print("\n[TEST 2] Dash Stamina Consumption")
	var dash_cost: float = player.dash_component.stamina_cost
	print("Dash cost: ", dash_cost)
	var can_dash_result: bool = player.cmd_dash(DashComponent.DashDirection.FORWARD)
	assert(can_dash_result == true, "Player should be able to dash")
	assert(player.current_stamina == 100.0 - dash_cost, "Stamina should be 75.0 after dash")
	print("Player stamina after dash: ", player.current_stamina)
	player.dash_component.end_dash()
	print(">> TEST 2 PASSED")

	# Test 3: Attack Stamina Consumption & Exhausted Attack
	print("\n[TEST 3] Attack Stamina Consumption & Exhausted Attack")
	var atk_cost: float = player.attack_component.weapon_data.stamina_cost
	print("Attack cost: ", atk_cost)
	var atk_result: bool = player.cmd_attack()
	assert(atk_result == true, "Player should be able to attack")
	print("Stamina after normal attack: ", player.current_stamina)
	assert(player.current_stamina == 75.0 - atk_cost, "Stamina should be 55.0")
	assert(player.attack_component.is_exhausted_attack == false, "Attack should be normal speed")
	assert(player.attack_component.attack_speed_scale == 1.0, "Speed scale should be 1.0")
	player.attack_component.cancel_attack()

	# Drain stamina down to 10
	player.stamina_component.current_stamina = 10.0
	print("Set stamina to 10.0 (less than 20.0 cost)")
	atk_result = player.cmd_attack()
	assert(atk_result == true, "Exhausted attack should proceed with SLOW_ATTACK policy")
	assert(player.attack_component.is_exhausted_attack == true, "Attack should be marked as exhausted")
	assert(player.attack_component.attack_speed_scale == 0.5, "Exhausted attack speed should be 0.5")
	assert(player.current_stamina == 0.0, "Stamina should be fully depleted to 0.0")
	print("Exhausted attack verified at speed scale: ", player.attack_component.attack_speed_scale)
	player.attack_component.cancel_attack()

	# Try dash with 0 stamina
	var dash_zero: bool = player.cmd_dash(DashComponent.DashDirection.FORWARD)
	assert(dash_zero == false, "Dash must be rejected when stamina is 0")
	print("Dash at 0 stamina properly rejected: ", dash_zero)
	print(">> TEST 3 PASSED")

	# Test 4: Passive Block & Guard Break
	print("\n[TEST 4] Passive Block & Guard Break")
	dummy.stamina_component.current_stamina = 100.0
	dummy.cmd_block_start()
	assert(dummy.is_blocking() == true, "Dummy should be in blocking state")

	# Orient dummy towards player for frontal angle check
	dummy.pawn.rotation.y = atan2(player.global_position.x - dummy.global_position.x, player.global_position.z - dummy.global_position.z)

	# Hit 1: 35 stamina consumed
	dummy.take_damage(35.0, Vector3(0, 0, 1), player)
	print("Dummy stamina after Hit 1: ", dummy.current_stamina)
	assert(dummy.current_stamina == 65.0, "Dummy stamina should be 65.0 after 35 drain")
	assert(dummy.is_blocking() == true, "Dummy should still be blocking")
	assert(dummy.is_staggered == false, "Dummy should not be staggered")

	# Hit 2: 35 stamina consumed
	dummy.take_damage(35.0, Vector3(0, 0, 1), player)
	print("Dummy stamina after Hit 2: ", dummy.current_stamina)
	assert(dummy.current_stamina == 30.0, "Dummy stamina should be 30.0 after 2nd hit")
	assert(dummy.is_blocking() == true, "Dummy should still be blocking")

	# Hit 3: 35 stamina consumed -> drops to 0 -> GUARD BREAK!
	dummy.take_damage(35.0, Vector3(0, 0, 1), player)
	print("Dummy stamina after Hit 3: ", dummy.current_stamina)
	assert(dummy.current_stamina == 0.0, "Dummy stamina should be 0.0")
	assert(dummy.is_blocking() == false, "Block must drop immediately on Guard Break!")
	assert(dummy.is_staggered == true, "Dummy must be staggered on Guard Break!")
	assert(dummy.stagger_timer >= 1.4, "Stagger timer must be ~1.5s (got %f)" % dummy.stagger_timer)
	print("Guard Break successfully verified! Dummy staggered for: ", dummy.stagger_timer)
	print(">> TEST 4 PASSED")

	# Test 5: Parry Gold Window & Stamina Bonus
	print("\n[TEST 5] Perfect Parry & Stamina Bonus")
	player.stamina_component.current_stamina = 50.0
	player.cmd_block_start()
	var parry_res: bool = player.cmd_parry()
	assert(parry_res == true, "Parry must be triggered")
	assert(player.defense_component.block_state == DefenseComponent.BlockState.ACTIVE_PARRY, "Should be in ACTIVE_PARRY")

	# Orient player towards dummy for frontal angle check
	player.pawn.rotation.y = atan2(dummy.global_position.x - player.global_position.x, dummy.global_position.z - player.global_position.z)

	# Incoming hit during parry window
	var dummy_sword_dmg := 20.0
	var health_before: float = player.current_health
	var stam_before: float = player.current_stamina
	player.take_damage(dummy_sword_dmg, Vector3(0, 0, 1), dummy)

	assert(player.current_health == health_before, "No damage taken during perfect parry")
	assert(player.current_stamina == stam_before + player.stats.parry_bonus_stamina, "Stamina should be refunded +15.0")
	assert(dummy.is_staggered == true, "Attacking dummy should be staggered by parry")
	print("Player stamina after parry: ", player.current_stamina, " (refunded +15.0)")
	print(">> TEST 5 PASSED")

	# Test 6: Regeneration & Block Penalty
	print("\n[TEST 6] Regeneration & Block Penalty")
	player.cmd_block_release()
	player.defense_component.end_block()
	player.stamina_component.current_stamina = 50.0
	player.stamina_component.consume(10.0) # resets delay to 0.8s, stamina is 40.0
	assert(player.stamina_component.current_stamina == 40.0, "Stamina should be 40.0")

	# Advance 0.5s (still within 0.8s delay)
	player.stamina_component.update(0.5)
	assert(player.stamina_component.current_stamina == 40.0, "Stamina must NOT regenerate during 0.8s delay")

	# Advance 0.4s more (0.9s total -> delay expired, 0.1s of regen at 25/s = 2.5)
	player.stamina_component.update(0.4)
	var expected_stamina := 40.0 + (25.0 * 0.1) # 42.5
	print("Stamina after delay expired: ", player.stamina_component.current_stamina)
	assert(absf(player.stamina_component.current_stamina - expected_stamina) < 0.05, "Stamina should regenerate at normal rate")

	# Now test block regen penalty
	player.cmd_block_start()
	assert(player.is_blocking() == true, "Player should be blocking")
	# Expire delay
	player.stamina_component.regen_delay_timer = 0.0
	var before_block_regen: float = player.stamina_component.current_stamina
	player.stamina_component.update(1.0) # 1.0 second of regen while blocking
	var block_regen_amount: float = player.stamina_component.current_stamina - before_block_regen
	var expected_block_rate := 25.0 * 0.25 # 6.25 (75% penalty)
	print("Regenerated while blocking in 1.0s: ", block_regen_amount, " (expected: ", expected_block_rate, ")")
	assert(absf(block_regen_amount - expected_block_rate) < 0.05, "Block regen should be reduced by 75%")
	player.cmd_block_release()
	print(">> TEST 6 PASSED")

	print("\n==============================================")
	print("ALL 6 STAMINA & GUARD BREAK TESTS PASSED 100%!")
	print("==============================================")
	quit()
