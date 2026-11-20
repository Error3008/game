extends SceneTree
## Задача 1.6: TechniqueComponent, FocusComponent, cmd_technique (фиктивные приёмы).

var player: Player
var dummy: Enemy


func _init() -> void:
	_run_tests()


func _near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps


func _freeze(actor: CombatCharacter3D) -> void:
	actor.set_process(false)
	actor.set_physics_process(false)
	for child in actor.get_children():
		if child is PlayerController or child is EnemyAIController:
			child.set_process(false)
			child.set_physics_process(false)


func _reset() -> void:
	for a: CombatCharacter3D in [player, dummy]:
		a.restore_full()
		a.dash_component.is_dashing = false
		a.is_staggered = false
		a.stagger_timer = 0.0
	player.technique_component.cooldowns.clear()


func _tech(id: StringName, kind: TechniqueData.Kind = TechniqueData.Kind.BUFF) -> TechniqueData:
	var t := TechniqueData.new()
	t.id = id
	t.kind = kind
	t.duration = 0.5
	return t


## Продвигает приём вручную (физический тик актора заморожен).
func _tick(seconds: float) -> void:
	player.technique_component.update(seconds)


func _run_tests() -> void:
	print("--- STARTING TECHNIQUES CORE TESTS ---")
	var scene: Node = (load("res://scenes/test_player.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	player = scene.get_node("Player") as Player
	dummy = scene.get_node("ObstacleRooms/Room2_LeftWall/Dummy_LeftWall") as Enemy
	assert(player != null and dummy != null, "actors exist")
	_freeze(player)
	_freeze(dummy)
	var tc: TechniqueComponent = player.technique_component
	var fc: FocusComponent = player.focus_component
	assert(tc != null and fc != null, "components created")

	# ---------- TEST 1: запал по умолчанию ----------
	print("\n[TEST 1] focus defaults and keys")
	assert(_near(fc.max_focus, 0.0) and _near(fc.current_focus, 0.0), "no focus without a school")
	assert(_near(player.stat(StatKeys.FOCUS_MAX), 0.0) and _near(player.stat(StatKeys.FOCUS_REGEN), 8.0), "focus keys registered")
	fc.configure(100.0)
	assert(_near(fc.max_focus, 100.0) and _near(fc.current_focus, 100.0), "configure fills")
	assert(fc.consume(30.0) and _near(fc.current_focus, 70.0), "consume")
	assert(not fc.consume(80.0) and _near(fc.current_focus, 70.0), "cannot overspend")
	fc.update(0.5)
	assert(_near(fc.current_focus, 70.0), "regen paused after spending")
	fc.update(1.0)  # 0.5 пауза осталась, затем 0.5 с × 8
	assert(_near(fc.current_focus, 74.0), "regen after pause: %f" % fc.current_focus)
	print(">> TEST 1 PASSED")

	# ---------- TEST 2: цена и откат ----------
	print("\n[TEST 2] cost and cooldown")
	_reset()
	fc.configure(100.0)
	var t := _tech(&"dummy")
	t.stamina_cost = 20.0
	t.focus_cost = 30.0
	t.cooldown = 2.0
	assert(not player.cmd_technique(&"dummy"), "not equipped")
	tc.equip(t)
	var s0: float = player.stamina_component.current_stamina
	assert(tc.can_use(&"dummy") and player.cmd_technique(&"dummy"), "starts")
	assert(_near(s0 - player.stamina_component.current_stamina, 20.0), "stamina paid")
	assert(_near(fc.current_focus, 70.0), "focus paid")
	assert(player.is_using_technique, "busy")
	assert(not player.cmd_technique(&"dummy"), "cannot start while running")
	_tick(0.6)
	assert(not player.is_using_technique, "finished by duration")
	assert(not tc.can_use(&"dummy") and tc.cooldown_left(&"dummy") > 1.0, "on cooldown")
	assert(not player.cmd_technique(&"dummy"), "blocked by cooldown")
	_tick(1.5)
	assert(tc.can_use(&"dummy"), "cooldown expired")
	# не хватает запала
	fc.current_focus = 10.0
	assert(not tc.can_use(&"dummy"), "not enough focus")
	fc.current_focus = 100.0
	player.stamina_component.current_stamina = 5.0
	assert(not tc.can_use(&"dummy"), "not enough stamina")
	print(">> TEST 2 PASSED")

	# ---------- TEST 3: запреты ----------
	print("\n[TEST 3] blocked by other actions")
	_reset()
	fc.configure(100.0)
	player.is_staggered = true
	assert(not player.cmd_technique(&"dummy"), "not in stagger")
	player.is_staggered = false
	player.dash_component.is_dashing = true
	assert(not player.cmd_technique(&"dummy"), "not in dash")
	player.dash_component.is_dashing = false
	player.cmd_block_start()
	assert(not player.cmd_technique(&"dummy"), "not in block")
	player.defense_component.end_block()
	assert(player.cmd_technique(&"dummy"), "free actor starts")
	assert(not player.cmd_attack() and not player.cmd_attack_light() and not player.cmd_kick() \
		and not player.cmd_block_start() and not player.cmd_heal(), "no other actions during technique")
	assert(not player.cmd_dash(DashComponent.DashDirection.BACKWARD), "no dash during technique")
	print(">> TEST 3 PASSED")

	# ---------- TEST 4: отмена hit-react и stagger ----------
	print("\n[TEST 4] cancelled by hit-react and stagger")
	_reset()
	var cancelled: Array = []
	tc.technique_finished.connect(func(d: TechniqueData, c: bool) -> void: cancelled.append(c))
	assert(player.cmd_technique(&"dummy"), "start")
	player.take_hit(DamageInfo.make(10.0, Vector3.ZERO, dummy))
	assert(not player.is_using_technique and player.is_staggered, "hit-react cancels")
	assert(cancelled == [true], "finished with cancelled=true")
	_reset()
	assert(player.cmd_technique(&"dummy"), "start again")
	player.stagger(0.8, dummy)
	assert(not player.is_using_technique, "stagger cancels")
	print(">> TEST 4 PASSED")

	# ---------- TEST 5: приём-удар (ATTACK_VARIANT) ----------
	print("\n[TEST 5] attack variant uses its WeaponData")
	_reset()
	var w := WeaponData.new()
	w.damage = 50.0
	w.stamina_cost = 15.0
	var atk := _tech(&"slam", TechniqueData.Kind.ATTACK_VARIANT)
	atk.attacks = [w]
	tc.equip(atk)
	var events: Array = []
	player.action_started.connect(func(a: StringName, d: Variant) -> void: events.append(a))
	var s1: float = player.stamina_component.current_stamina
	assert(player.cmd_technique(&"slam"), "variant starts")
	assert(player.is_attacking and player.attack_component.weapon_data == w, "attack runs with the technique weapon")
	assert(_near(s1 - player.stamina_component.current_stamina, 15.0), "stamina from weapon, not doubled")
	assert(not player.is_using_technique, "attack branch owns the actor")
	assert(&"technique" in events, "action_started technique")
	player.attack_component.cancel_attack()
	_tick(0.01)
	assert(tc.current() == null, "technique finished with the attack")
	# пустой приём-удар не стартует и ничего не тратит
	var empty := _tech(&"empty", TechniqueData.Kind.ATTACK_VARIANT)
	empty.stamina_cost = 10.0
	tc.equip(empty)
	var s2: float = player.stamina_component.current_stamina
	assert(not player.cmd_technique(&"empty") and _near(s2, player.stamina_component.current_stamina), "no weapon, no cost")
	print(">> TEST 5 PASSED")

	print("\nALL TECHNIQUES CORE TESTS PASSED 100%!")
	quit()
