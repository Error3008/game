extends SceneTree

func _init() -> void:
	_run_hud_tests()


func _run_hud_tests() -> void:
	print("--- STARTING COMBAT HUD UNIT TESTS ---")
	var scene: Node = (load("res://scenes/test_player.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var player: Player = scene.get_node("Player") as Player
	var dummy: Enemy = scene.get_node("ObstacleRooms/Room2_LeftWall/Dummy_LeftWall") as Enemy
	var hud: CombatHUD = player.get_node_or_null("CombatHUD") as CombatHUD
	var cam: Camera3D = root.get_viewport().get_camera_3d()

	assert(player != null, "Player must exist")
	assert(dummy != null, "Dummy must exist")
	assert(hud != null, "CombatHUD must exist under Player")
	assert(cam != null, "Camera3D must exist in Viewport")

	# Test 1: Player HUD layout & numbers
	print("\n[TEST 1] Player HUD Elements")
	assert(hud._player_panel.visible == true, "Player panel should be visible")
	assert(hud._player_hp_bar != null, "Player HP bar must exist")
	assert(hud._player_stamina_bar != null, "Player Stamina bar must exist")
	print("Player HP Label: ", hud._player_hp_label.text)
	print("Player Stamina Label: ", hud._player_stamina_label.text)
	assert("100 / 100" in hud._player_hp_label.text, "HP label should display 100 / 100")
	assert("100 / 100" in hud._player_stamina_label.text, "Stamina label should display 100 / 100")
	assert(hud.stamina_fill_color.b > 0.9, "Stamina bar fill must be blue!")
	print(">> TEST 1 PASSED")

	# Test 2: Target Overhead HUD initially hidden without lock
	print("\n[TEST 2] Target HUD initially hidden without lock")
	assert(hud._target_panel.visible == false, "Target overhead panel must be hidden when no target is locked")
	print(">> TEST 2 PASSED")

	# Test 3: Target Overhead HUD on Target Lock
	print("\n[TEST 3] Target HUD appears on target lock")
	# Align camera facing the target so it is in front of the camera
	var head_pos := dummy.global_position + Vector3(0.0, 2.25, 0.0)
	cam.global_position = dummy.global_position + Vector3(0.0, 2.0, 5.0)
	cam.look_at(head_pos, Vector3.UP)

	player.cmd_set_target(dummy)
	# Process one frame to let HUD update target position and stats
	hud._process(0.016)
	assert(hud._target_panel.visible == true, "Target overhead panel must be visible when target is locked and in front of camera")
	print("Target Name Label: ", hud._target_name_label.text)
	print("Target HP Label: ", hud._target_hp_label.text)
	print("Target Stamina Label: ", hud._target_stamina_label.text)
	assert("100 / 100" in hud._target_hp_label.text, "Target HP label should show 100 / 100")
	assert("100 / 100" in hud._target_stamina_label.text, "Target Stamina label should show 100 / 100")
	print(">> TEST 3 PASSED")

	# Test 4: Dynamic updates & Guard Break Banner
	print("\n[TEST 4] Target HUD dynamic updates & Guard Break")
	dummy.stamina_component.current_stamina = 0.0
	dummy.is_staggered = true
	hud._process(0.016)
	print("Target Status Label: ", hud._target_status_label.text, " visible: ", hud._target_status_label.visible)
	assert(hud._target_status_label.visible == true, "Guard broken status label must be visible on exhausted stagger")
	print(">> TEST 4 PASSED")

	# Test 5: Clearing target hides HUD
	print("\n[TEST 5] Clearing target hides overhead HUD")
	player.cmd_clear_target()
	hud._process(0.016)
	assert(hud._target_panel.visible == false, "Target overhead panel must hide when target is cleared")
	print(">> TEST 5 PASSED")

	print("\n==============================================")
	print("ALL 5 COMBAT HUD TESTS PASSED 100%!")
	print("==============================================")
	quit()
