extends SceneTree

## Этап 4: экран конца при смерти игрока и растворение трупа врага.
## Запуск: godot --headless -s res://scripts/tools/test_game_over.gd (с timeout)


func _init() -> void:
	_run()


func _wait_physics(frames: int) -> void:
	for i: int in frames:
		await physics_frame


func _run() -> void:
	print("--- STARTING GAME OVER / CORPSE DISSOLVE TESTS ---")
	var scene: Node = (load("res://scenes/test_player.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var player: Player = scene.get_node("Player") as Player
	var dummy: Enemy = scene.get_node("ObstacleRooms/Room2_LeftWall/Dummy_LeftWall") as Enemy
	var screen: GameOverScreen = player.get_node_or_null("GameOverScreen") as GameOverScreen
	assert(screen != null, "GameOverScreen must exist under Player")
	assert(not screen.is_shown(), "Screen hidden at start")
	assert(not screen._root_control.visible, "Screen root invisible at start")

	# --- Test 1: растворение трупа врага ---
	print("\n[TEST 1] Enemy corpse dissolves and is freed")
	dummy.corpse_lifetime = 0.3
	dummy.dissolve_duration = 0.4
	dummy.take_damage(1000.0, Vector3.ZERO, player)
	assert(not dummy.is_alive(), "Dummy must be dead")
	assert(is_instance_valid(dummy), "Corpse still exists right after death")
	await create_timer(0.2).timeout
	assert(is_instance_valid(dummy), "Corpse still exists during lifetime")
	await create_timer(0.3).timeout  # t=0.5 -> растворение идёт
	assert(is_instance_valid(dummy), "Corpse exists mid-dissolve")
	assert(dummy._dissolve_materials.size() > 0, "Dissolve materials must be applied")
	var progress: float = dummy._dissolve_materials[0].get_shader_parameter("progress")
	assert(progress > 0.0 and progress < 1.0, "Dissolve progress mid-way, got %f" % progress)
	await create_timer(0.5).timeout  # t=1.0 -> удалён
	assert(not is_instance_valid(dummy), "Corpse must be freed after dissolve")
	print(">> TEST 1 PASSED")

	# --- Test 2: corpse_lifetime = 0 -> труп остаётся ---
	print("\n[TEST 2] corpse_lifetime = 0 keeps corpse forever")
	var keeper: Enemy = scene.get_node("Enemy_Bully") as Enemy
	keeper.corpse_lifetime = 0.0
	keeper.take_damage(1000.0, Vector3.ZERO, player)
	assert(not keeper.is_alive(), "Keeper must be dead")
	await create_timer(1.0).timeout
	assert(is_instance_valid(keeper), "Corpse must stay when corpse_lifetime = 0")
	assert(keeper._dissolve_materials.is_empty(), "No dissolve materials when disabled")
	print(">> TEST 2 PASSED")

	# --- Test 3: экран конца при смерти игрока ---
	print("\n[TEST 3] Game over screen after player death")
	screen.show_delay = 0.2
	screen.fade_duration = 0.2
	player.take_damage(1000.0, Vector3.ZERO, keeper)
	assert(not player.is_alive(), "Player must be dead")
	assert(screen.is_shown(), "Screen flagged as shown on death")
	assert(not screen._root_control.visible, "Screen not yet visible during show_delay")
	await create_timer(0.3).timeout
	assert(screen._root_control.visible, "Screen visible after delay")
	assert(not screen._can_restart, "Restart not allowed until fade is done")
	await create_timer(0.4).timeout
	assert(screen._can_restart, "Restart allowed after fade")
	assert(screen._root_control.modulate.a > 0.99, "Screen fully opaque after fade")
	print(">> TEST 3 PASSED")

	print("\n==============================================")
	print("ALL GAME OVER / DISSOLVE TESTS PASSED 100%!")
	print("==============================================")
	quit(0)
