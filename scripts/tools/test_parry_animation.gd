extends SceneTree

func _init() -> void:
	_run_tests()


func _run_tests() -> void:
	print("--- STARTING PARRY_SUCCESS ANIMATION & LOGIC UNIT TESTS ---")
	var scene: Node = (load("res://scenes/test_player.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var player: Player = scene.get_node("Player") as Player
	var dummy: Enemy = scene.get_node("ObstacleRooms/Room2_LeftWall/Dummy_LeftWall") as Enemy

	assert(player != null, "Player must exist")
	assert(dummy != null, "Dummy must exist")

	# Unit test drives actor commands directly: the controller would otherwise clear the
	# manually set target (lock not enabled) and thereby drop the block via cmd_clear_target().
	var player_ctrl: Node = player.get_node_or_null("PlayerController")
	assert(player_ctrl != null, "PlayerController must exist")
	player_ctrl.set_physics_process(false)
	player_ctrl.set_process(false)
	player_ctrl.set_process_unhandled_input(false)

	var player_at: AnimationTree = player.get_node("pawn/AnimationTree") as AnimationTree
	var dummy_at: AnimationTree = dummy.get_node("pawn/AnimationTree") as AnimationTree

	assert(player_at != null, "Player AnimationTree must exist")
	assert(dummy_at != null, "Dummy AnimationTree must exist")

	# --- TEST 1: Check AnimationTree configuration in both Player and Enemy ---
	print("\n[TEST 1] AnimationTree node configuration for Parry_Success")
	var player_tree_root: AnimationNodeBlendTree = player_at.tree_root as AnimationNodeBlendTree
	var dummy_tree_root: AnimationNodeBlendTree = dummy_at.tree_root as AnimationNodeBlendTree

	var player_parry_node: AnimationNodeAnimation = player_tree_root.get_node("ParryAnim") as AnimationNodeAnimation
	var dummy_parry_node: AnimationNodeAnimation = dummy_tree_root.get_node("ParryAnim") as AnimationNodeAnimation

	assert(player_parry_node != null, "Player must have ParryAnim node")
	assert(dummy_parry_node != null, "Dummy must have ParryAnim node")

	assert(player_parry_node.animation == &"Parry_Success", "Player ParryAnim must play Parry_Success (was: %s)" % player_parry_node.animation)
	assert(dummy_parry_node.animation == &"Parry_Success", "Dummy ParryAnim must play Parry_Success (was: %s)" % dummy_parry_node.animation)

	print("Player ParryAnim: ", player_parry_node.animation)
	print("Dummy ParryAnim:  ", dummy_parry_node.animation)
	print(">> TEST 1 PASSED")

	# Face each other
	player.global_position = Vector3(0.0, 0.0, 0.0)
	dummy.global_position = Vector3(0.0, 0.0, -1.5)
	player.pawn.rotation.y = atan2(dummy.global_position.x - player.global_position.x, dummy.global_position.z - player.global_position.z)
	dummy.pawn.rotation.y = atan2(player.global_position.x - dummy.global_position.x, player.global_position.z - dummy.global_position.z)
	player.cmd_set_target(dummy)
	dummy.cmd_set_target(player)

	# --- TEST 2: Player cmd_parry triggers Parry_Success ---
	print("\n[TEST 2] Player cmd_parry triggers Parry_Success via ActionOneShot")
	player.cmd_block_start()
	assert(player.is_blocking() == true, "Player must be blocking")
	var parry_res: bool = player.cmd_parry()
	assert(parry_res == true, "cmd_parry must succeed")
	await physics_frame

	assert(player_at.get("parameters/ActionOneShot/active") == true, "Player ActionOneShot must be active")
	assert(str(player_at.get("parameters/ActionSelect/current_state")) == "parry", "ActionSelect state must be parry")
	print("Player ActionOneShot active: %s, ActionSelect state: %s" % [
		player_at.get("parameters/ActionOneShot/active"),
		player_at.get("parameters/ActionSelect/current_state")
	])
	print(">> TEST 2 PASSED")

	# --- TEST 3: Perfect Parry by Player against Incoming Hit ---
	print("\n[TEST 3] Perfect Parry by Player against Incoming Hit")
	player.defense_component.end_block()
	player.stamina_component.current_stamina = 50.0
	player.health_component.current_health = 100.0
	dummy.health_component.current_health = 100.0
	dummy.is_staggered = false

	# Setup parry on Player
	player.cmd_block_start()
	player.cmd_parry()
	assert(player.defense_component.block_state == DefenseComponent.BlockState.ACTIVE_PARRY, "Player in ACTIVE_PARRY")

	var parry_signal_received := {"emitted": false, "attacker": null}
	var on_parry = func(att: Node3D):
		parry_signal_received["emitted"] = true
		parry_signal_received["attacker"] = att

	player.defense_component.parry_successful.connect(on_parry)

	# Incoming hit from Dummy
	player.take_damage(20.0, Vector3(0, 0, 3.0), dummy)
	await physics_frame

	assert(parry_signal_received["emitted"] == true, "parry_successful signal must be emitted")
	assert(parry_signal_received["attacker"] == dummy, "Attacker passed to signal must be dummy")
	assert(player.current_health == 100.0, "Player takes 0 damage on perfect parry")
	assert(is_equal_approx(snappedf(player.current_stamina, 1.0), 65.0), "Player stamina restored by +15 on perfect parry (50 -> 65)")
	assert(dummy.is_staggered == true, "Attacking dummy must be staggered for 0.8s")
	assert(player_at.get("parameters/ActionOneShot/active") == true, "Player ActionOneShot active for Parry_Success")
	assert(str(player_at.get("parameters/ActionSelect/current_state")) == "parry", "State is parry")

	player.defense_component.parry_successful.disconnect(on_parry)
	print(">> TEST 3 PASSED")

	# --- TEST 4: Perfect Parry by Enemy/Dummy against Incoming Hit ---
	print("\n[TEST 4] Perfect Parry by Enemy/Dummy against Incoming Hit")
	dummy.is_staggered = false
	dummy.stamina_component.current_stamina = 50.0
	dummy.health_component.current_health = 100.0
	player.is_staggered = false

	dummy.cmd_block_start()
	dummy.cmd_parry()
	assert(dummy.defense_component.block_state == DefenseComponent.BlockState.ACTIVE_PARRY, "Dummy in ACTIVE_PARRY")

	var dummy_parry_signal := {"emitted": false, "attacker": null}
	var on_dummy_parry = func(att: Node3D):
		dummy_parry_signal["emitted"] = true
		dummy_parry_signal["attacker"] = att

	dummy.defense_component.parry_successful.connect(on_dummy_parry)

	# Player strikes Dummy
	dummy.take_damage(25.0, Vector3(0, 0, -3.0), player)
	await physics_frame

	assert(dummy_parry_signal["emitted"] == true, "Dummy parry_successful signal emitted")
	assert(dummy_parry_signal["attacker"] == player, "Attacker is player")
	assert(dummy.current_health == 100.0, "Dummy takes 0 damage on perfect parry")
	assert(is_equal_approx(snappedf(dummy.current_stamina, 1.0), 65.0), "Dummy stamina restored by +15")
	assert(player.is_staggered == true, "Attacking player staggered by dummy perfect parry")
	assert(dummy_at.get("parameters/ActionOneShot/active") == true, "Dummy ActionOneShot active for Parry_Success")
	assert(str(dummy_at.get("parameters/ActionSelect/current_state")) == "parry", "Dummy state is parry")

	dummy.defense_component.parry_successful.disconnect(on_dummy_parry)
	print(">> TEST 4 PASSED")

	# --- TEST 5: Automatic recovery after Parry_Success finishes ---
	print("\n[TEST 5] Automatic recovery after Parry_Success animation")
	player.is_staggered = false
	player.cmd_block_start()
	player.play_parry_success()
	await physics_frame
	assert(player_at.get("parameters/ActionOneShot/active") == true, "Player ActionOneShot active")

	# Advance 1.0 second (60 physics frames)
	for i in range(60):
		await physics_frame

	assert(player_at.get("parameters/ActionOneShot/active") == false, "ActionOneShot automatically finishes")
	assert(player.is_blocking() == true, "Player returns cleanly to block loop")
	print(">> TEST 5 PASSED")

	# --- TEST 6: play_action(&'parry_success') alias mapping ---
	print("\n[TEST 6] play_action(&'parry_success') alias routes to parry slot")
	dummy.play_action(&"parry_success")
	await physics_frame
	assert(dummy_at.get("parameters/ActionOneShot/active") == true, "OneShot active")
	assert(str(dummy_at.get("parameters/ActionSelect/current_state")) == "parry", "Mapped to parry transition")
	print(">> TEST 6 PASSED")

	print("\n==============================================")
	print("ALL 6 PARRY_SUCCESS ANIMATION TESTS PASSED 100%!")
	print("==============================================")
	quit()
