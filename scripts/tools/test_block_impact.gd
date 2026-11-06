extends SceneTree

func _init() -> void:
	_run_tests()


func _run_tests() -> void:
	print("--- STARTING BLOCK IMPACT ANIMATION & LOGIC UNIT TESTS ---")
	var scene: Node = (load("res://scenes/test_player.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var player: Player = scene.get_node("Player") as Player
	var dummy: Enemy = scene.get_node("ObstacleRooms/Room2_LeftWall/Dummy_LeftWall") as Enemy

	assert(player != null, "Player must exist")
	assert(dummy != null, "Dummy must exist")
	assert(player.defense_component != null, "Player must have DefenseComponent")
	assert(dummy.defense_component != null, "Dummy must have DefenseComponent")

	# Position facing each other
	player.global_position = Vector3(0.0, 0.0, 0.0)
	dummy.global_position = Vector3(0.0, 0.0, -1.5)
	player.pawn.rotation.y = atan2(dummy.global_position.x - player.global_position.x, dummy.global_position.z - player.global_position.z)
	dummy.pawn.rotation.y = atan2(player.global_position.x - dummy.global_position.x, player.global_position.z - dummy.global_position.z)
	player.cmd_set_target(dummy)
	dummy.cmd_set_target(player)

	var dummy_at: AnimationTree = dummy.get_node("pawn/AnimationTree") as AnimationTree
	var player_at: AnimationTree = player.get_node("pawn/AnimationTree") as AnimationTree
	assert(dummy_at != null, "Dummy must have AnimationTree")
	assert(player_at != null, "Player must have AnimationTree")

	# --- TEST 1: Dummy Blocks Attack -> Block_Impact Triggers ---
	print("\n[TEST 1] Dummy Blocks Hit -> Block_Impact Triggers")
	dummy.stamina_component.current_stamina = 100.0
	dummy.health_component.current_health = 100.0
	dummy.is_staggered = false
	dummy.cmd_block_start()
	assert(dummy.is_blocking() == true, "Dummy must be blocking")

	var dummy_data := {"received": false, "attacker": null}
	var on_dummy_block_impact = func(att: Node3D):
		dummy_data["received"] = true
		dummy_data["attacker"] = att

	dummy.defense_component.block_impact.connect(on_dummy_block_impact)

	# Apply damage from player in front
	var initial_hp := dummy.current_health
	var initial_stam := dummy.current_stamina
	dummy.take_damage(20.0, Vector3(0, 0, -3.0), player)
	await process_frame

	assert(dummy_data["received"] == true, "DefenseComponent.block_impact signal must be emitted")
	assert(dummy_data["attacker"] == player, "Attacker passed to signal must be player")
	assert(dummy.current_stamina < initial_stam, "Dummy stamina must be drained by block impact")
	assert(dummy.current_health < initial_hp, "Dummy took reduced block damage")
	assert(dummy.current_health > initial_hp - 20.0, "Damage must be absorbed (not full)")
	
	# Verify AnimationTree action state
	assert(dummy_at.get("parameters/ActionOneShot/active") == true, "Dummy ActionOneShot must be active")
	assert(str(dummy_at.get("parameters/ActionSelect/current_state")) == "block_impact", "ActionSelect must be playing block_impact")
	print("Dummy Block_Impact successfully playing! ActionOneShot active: %s, State: %s" % [
		dummy_at.get("parameters/ActionOneShot/active"),
		dummy_at.get("parameters/ActionSelect/current_state")
	])

	dummy.defense_component.block_impact.disconnect(on_dummy_block_impact)
	print(">> TEST 1 PASSED")

	# --- TEST 2: Player Blocks Attack -> Block_Impact Triggers ---
	print("\n[TEST 2] Player Blocks Hit -> Block_Impact Triggers")
	player.stamina_component.current_stamina = 100.0
	player.health_component.current_health = 100.0
	player.is_staggered = false
	Input.action_press("block")
	player.cmd_block_start()
	assert(player.is_blocking() == true, "Player must be blocking")

	var player_data := {"received": false, "attacker": null}
	var on_player_block_impact = func(att: Node3D):
		player_data["received"] = true
		player_data["attacker"] = att

	player.defense_component.block_impact.connect(on_player_block_impact)

	player.take_damage(25.0, Vector3(0, 0, 2.0), dummy)
	await process_frame

	assert(player_data["received"] == true, "Player DefenseComponent.block_impact signal must be emitted")
	assert(player_data["attacker"] == dummy, "Attacker passed to signal must be dummy")
	assert(player.current_stamina == 65.0, "Player stamina must be drained from 100.0 to 65.0")
	assert(player_at.get("parameters/ActionOneShot/active") == true, "Player ActionOneShot must be active")
	assert(str(player_at.get("parameters/ActionSelect/current_state")) == "block_impact", "Player ActionSelect must be playing block_impact")
	print("Player Block_Impact successfully playing! ActionOneShot active: %s, State: %s" % [
		player_at.get("parameters/ActionOneShot/active"),
		player_at.get("parameters/ActionSelect/current_state")
	])

	player.defense_component.block_impact.disconnect(on_player_block_impact)
	print(">> TEST 2 PASSED")

	# --- TEST 3: Block Impact Auto Recovery back to Block Loop ---
	print("\n[TEST 3] Block Impact Auto Recovery back to Block Pose")
	dummy.stamina_component.current_stamina = 100.0
	dummy.cmd_block_start()
	assert(dummy.is_blocking() == true, "Dummy is blocking")
	dummy.play_block_impact()
	await process_frame
	assert(dummy_at.get("parameters/ActionOneShot/active") == true, "Dummy ActionOneShot active")

	# Simulate 1.2 seconds of animation
	for i in range(72):
		await physics_frame

	assert(dummy_at.get("parameters/ActionOneShot/active") == false, "ActionOneShot must automatically finish and return to base pose")
	assert(dummy.is_blocking() == true, "Dummy still safely in block stance")
	print(">> TEST 3 PASSED")

	# --- TEST 4: Guard Break does NOT trigger Block_Impact ---
	print("\n[TEST 4] Guard Break (Stamina 0) triggers Stagger, NOT Block_Impact")
	dummy.is_staggered = false
	dummy.cmd_block_start()
	dummy.stamina_component.current_stamina = 20.0 # Less than 35 required to absorb hit
	dummy_data["received"] = false
	dummy.defense_component.block_impact.connect(on_dummy_block_impact)

	dummy.take_damage(20.0, Vector3(0, 0, -2.0), player)
	await process_frame

	assert(dummy_data["received"] == false, "Guard break should NOT emit block_impact")
	assert(dummy.is_staggered == true, "Dummy must be staggered by guard break")
	assert(dummy.is_blocking() == false, "Dummy block collapsed")
	assert(dummy_at.get("parameters/ActionOneShot/active") == false, "ActionOneShot should be aborted by stagger")
	dummy.defense_component.block_impact.disconnect(on_dummy_block_impact)
	print(">> TEST 4 PASSED")

	# --- TEST 5: Retriggering Block Impact on Consecutive Hits ---
	print("\n[TEST 5] Retriggering Block Impact on Consecutive Hits")
	dummy.is_staggered = false
	dummy.stamina_component.current_stamina = 100.0
	dummy.cmd_block_start()
	assert(dummy.is_blocking() == true, "Dummy is blocking")

	# First hit
	dummy.take_damage(10.0, Vector3.ZERO, player)
	await process_frame
	assert(dummy_at.get("parameters/ActionOneShot/active") == true, "OneShot active after 1st hit")

	# Advance 0.3s (18 frames)
	for i in range(18):
		await physics_frame

	# Second hit while 1st Block_Impact is still playing
	dummy.take_damage(10.0, Vector3.ZERO, player)
	await process_frame
	assert(dummy_at.get("parameters/ActionOneShot/active") == true, "OneShot still active after 2nd hit retrigger")
	assert(str(dummy_at.get("parameters/ActionSelect/current_state")) == "block_impact", "Still in block_impact state")
	print(">> TEST 5 PASSED")

	print("\n==============================================")
	print("ALL 5 BLOCK IMPACT TESTS PASSED 100%!")
	print("==============================================")
	quit()
