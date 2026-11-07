extends SceneTree

## Регрессия: Hit_React прерывает действие, Stagger масштабируется, лёгкая атака,
## лечение флягой (+прерывание), Death (действия отменяются, поза замораживается).

func _init() -> void:
	_run_tests()


func _state(at: AnimationTree) -> String:
	return str(at.get("parameters/ActionSelect/current_state"))


func _run_tests() -> void:
	print("--- STARTING REACTIONS / LIGHT ATTACK / HEAL / DEATH TESTS ---")
	var scene: Node = (load("res://scenes/test_player.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var player: Player = scene.get_node("Player") as Player
	var dummy: Enemy = scene.get_node("ObstacleRooms/Room2_LeftWall/Dummy_LeftWall") as Enemy
	var p_at: AnimationTree = player.animation_tree
	var d_at: AnimationTree = dummy.animation_tree
	assert(player != null and dummy != null, "Player and dummy must exist")

	player.global_position = Vector3(0.0, 0.0, 0.0)
	dummy.global_position = Vector3(0.0, 0.0, -1.5)
	player.pawn.rotation.y = atan2(dummy.global_position.x - player.global_position.x, dummy.global_position.z - player.global_position.z)
	dummy.pawn.rotation.y = atan2(player.global_position.x - dummy.global_position.x, player.global_position.z - dummy.global_position.z)
	player.cmd_set_target(dummy)
	dummy.cmd_set_target(player)

	# --- TEST 1: Hit_React interrupts attack ---
	print("\n[TEST 1] Clean hit interrupts the victim's attack and plays Hit_React")
	dummy.stamina_component.current_stamina = 100.0
	assert(dummy.cmd_attack() == true, "Dummy starts an attack")
	assert(dummy.is_attacking == true, "Dummy is attacking")
	dummy.take_damage(10.0, Vector3.ZERO, player)
	await physics_frame
	assert(dummy.is_attacking == false, "Hit must interrupt the attack")
	assert(dummy.is_staggered == true, "Victim is briefly stunned")
	assert(_state(d_at) == "hit_react", "ActionSelect must be hit_react, got %s" % _state(d_at))
	print(">> TEST 1 PASSED")

	# --- TEST 2: Stagger time scale ---
	print("\n[TEST 2] Stagger clip speed follows stagger duration")
	dummy.is_staggered = false
	dummy.stagger(0.8, player)
	assert(absf(float(d_at.get("parameters/ActionTimeScale/scale")) - 1.46) < 0.02, "Parry stagger x1.46")
	await physics_frame
	assert(_state(d_at) == "stagger", "State must be stagger, got %s" % _state(d_at))
	dummy.is_staggered = false
	dummy.stagger(1.5, player)
	assert(absf(float(d_at.get("parameters/ActionTimeScale/scale")) - 0.78) < 0.02, "Guard break stagger x0.78")
	print(">> TEST 2 PASSED")

	# --- TEST 3: Light attack ---
	print("\n[TEST 3] Light attack: light weapon, 10 stamina, light_attack clip; heavy still heavy")
	player.is_staggered = false
	player.stamina_component.current_stamina = 100.0
	assert(player.cmd_attack_light() == true, "Light attack starts")
	assert(player.attack_component.weapon_data == player.attack_component.light_weapon_data, "Light weapon active")
	assert(player.current_stamina == 90.0, "Light costs 10 stamina, have %.1f" % player.current_stamina)
	await physics_frame
	assert(_state(p_at) == "light_attack", "State light_attack, got %s" % _state(p_at))
	player.attack_component.cancel_attack()
	player.stamina_component.current_stamina = 100.0
	assert(player.cmd_attack() == true, "Heavy attack starts")
	assert(player.attack_component.weapon_data == player.attack_component.heavy_weapon_data, "Heavy weapon active")
	assert(player.current_stamina == 80.0, "Heavy costs 20 stamina")
	assert(is_equal_approx(player.attack_component.weapon_data.active_end_time, 0.71), "Heavy v2 timings")
	player.attack_component.cancel_attack()
	print(">> TEST 3 PASSED")

	# --- TEST 4: Heal ---
	print("\n[TEST 4] Heal: flask visibility, heal at ~0.8s, charge spent, refused at full HP")
	player.is_staggered = false
	var hc: HealComponent = player.heal_component
	var flask: Node3D = player.find_child("flask", true, false) as Node3D
	assert(flask != null, "flask node must exist in knight model")
	assert(flask.visible == false, "flask hidden by default")
	assert(hc.charges == 3, "3 charges at start")
	assert(player.cmd_heal() == false, "No heal at full HP")
	player.health_component.current_health = 50.0
	assert(player.cmd_heal() == true, "Heal starts")
	assert(hc.charges == 2, "Charge spent at start")
	assert(player.cmd_block_start() == false, "No block while drinking")
	await physics_frame
	assert(_state(p_at) == "heal", "State heal")
	hc.process_heal(0.5)
	assert(flask.visible == true, "flask visible at 0.5s")
	assert(player.current_health == 50.0, "Not healed yet")
	hc.process_heal(0.4)
	assert(player.current_health == 90.0, "Healed +40 at 0.9s, have %.1f" % player.current_health)
	hc.process_heal(0.6)
	assert(hc.is_healing == false and flask.visible == false, "Heal finished, flask hidden")

	print("[TEST 4b] Interrupted heal: no HP, charge lost, flask hidden")
	player.health_component.current_health = 50.0
	assert(player.cmd_heal() == true, "Second heal starts")
	hc.process_heal(0.5)
	player.take_damage(5.0, Vector3.ZERO, dummy)
	assert(hc.is_healing == false, "Hit cancels heal")
	assert(flask.visible == false, "flask hidden after interrupt")
	hc.process_heal(1.0)
	assert(player.current_health == 45.0, "No heal applied, only damage, have %.1f" % player.current_health)
	assert(hc.charges == 1, "Charge was spent")
	print(">> TEST 4 PASSED")

	# --- TEST 5: Death ---
	print("\n[TEST 5] Death cancels actions, plays Death, freezes corpse pose")
	dummy.is_staggered = false
	dummy.health_component.current_health = 100.0
	dummy.cmd_attack()
	dummy.take_damage(1000.0, Vector3.ZERO, player)
	await physics_frame
	assert(dummy.is_alive() == false, "Dummy dead")
	assert(dummy.is_attacking == false, "Attack cancelled on death")
	assert(_state(d_at) == "death", "State death, got %s" % _state(d_at))
	assert(d_at.active == true, "Tree still running during the fall")
	for i in range(125):
		await physics_frame
	assert(d_at.active == false, "Pose frozen after the fall")
	print(">> TEST 5 PASSED")

	print("\n==============================================")
	print("ALL REACTIONS / LIGHT / HEAL / DEATH TESTS PASSED 100%!")
	print("==============================================")
	quit()
