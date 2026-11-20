extends SceneTree
## Тесты статов через модификаторы: формула StatBlock, AttributeRules, пресеты брони/ловкости,
## интеграция в take_damage / дэш / атаку / парирование ИИ.
## Запуск: godot --headless -s res://scripts/tools/test_build_stats.gd

func _init() -> void:
	_run_tests()


func _near(a: float, b: float, eps: float = 0.0001) -> bool:
	return absf(a - b) <= eps


func _run_tests() -> void:
	print("--- STARTING BUILD STATS TESTS ---")

	# ---------- TEST 1: формула StatBlock ----------
	print("\n[TEST 1] StatBlock formula")
	var sb := StatBlock.new()
	sb.set_base(StatKeys.DASH_SPEED, 8.5)
	sb.set_base(StatKeys.DASH_COOLDOWN, 0.55)
	assert(_near(sb.get_value(StatKeys.DASH_SPEED), 8.5), "no modifiers -> base")
	# проценты от РАЗНЫХ источников складываются: 8.5 * (1 + 0.10 + 0.20) = 11.05, а не 8.5*1.1*1.2
	sb.add_modifier(StatModifier.make(StatKeys.DASH_SPEED, StatModifier.Op.PERCENT, 0.10), &"a")
	sb.add_modifier(StatModifier.make(StatKeys.DASH_SPEED, StatModifier.Op.PERCENT, 0.20), &"b")
	assert(_near(sb.get_value(StatKeys.DASH_SPEED), 11.05), "percent stacks additively, got %f" % sb.get_value(StatKeys.DASH_SPEED))
	# (8.5 + 1) * 1.3 * 1.1 = 13.585 (FLAT -> PERCENT -> MULT)
	sb.add_modifier(StatModifier.make(StatKeys.DASH_SPEED, StatModifier.Op.FLAT, 1.0), &"c")
	sb.add_modifier(StatModifier.make(StatKeys.DASH_SPEED, StatModifier.Op.MULT, 1.1), &"d")
	assert(_near(sb.get_value(StatKeys.DASH_SPEED), 13.585), "order flat/percent/mult, got %f" % sb.get_value(StatKeys.DASH_SPEED))
	# clamp: max 14
	sb.add_modifier(StatModifier.make(StatKeys.DASH_SPEED, StatModifier.Op.MULT, 5.0), &"e")
	assert(_near(sb.get_value(StatKeys.DASH_SPEED), 14.0), "clamped to max")
	# clamp min у кулдауна: 0.55 - 2.0 -> 0.15
	sb.add_modifier(StatModifier.make(StatKeys.DASH_COOLDOWN, StatModifier.Op.FLAT, -2.0), &"f")
	assert(_near(sb.get_value(StatKeys.DASH_COOLDOWN), 0.15), "clamped to min")
	# снятие источника
	sb.remove_source(&"e")
	assert(_near(sb.get_value(StatKeys.DASH_SPEED), 13.585), "remove_source restores value")
	# один шаблон-модификатор у двух блоков (общий .tres): источник хранится в блоке
	var shared := StatModifier.make(StatKeys.DASH_SPEED, StatModifier.Op.PERCENT, 0.5)
	var sb2 := StatBlock.new()
	sb2.set_base(StatKeys.DASH_SPEED, 8.0)
	sb.add_modifier(shared, &"shared")
	sb2.add_modifier(shared, &"other_name")
	sb.remove_source(&"shared")
	assert(_near(sb2.get_value(StatKeys.DASH_SPEED), 12.0), "shared template unaffected by other block's remove")
	sb.free()
	sb2.free()
	print(">> TEST 1 PASSED")

	# ---------- TEST 2: AttributeRules ----------
	print("\n[TEST 2] AttributeRules control numbers")
	var rules := AttributeRules.new()
	var ab := StatBlock.new()
	ab.set_base(StatKeys.DASH_SPEED, 8.5)
	ab.set_base(StatKeys.DAMAGE_TAKEN, 1.0)
	ab.set_base(StatKeys.DAMAGE_TAKEN_PHYSICAL, 1.0)
	ab.set_base(StatKeys.ATTACK_SPEED, 1.0)
	ab.set_base(StatKeys.DASH_COOLDOWN, 0.55)
	ab.set_base(StatKeys.PARRY_WINDOW, 0.2)
	ab.set_base(StatKeys.BLOCK_STAMINA_COST, 35.0)
	ab.set_base(StatKeys.MOVE_SPEED, 1.0)
	ab.set_base(StatKeys.DASH_IFRAME_DURATION, 0.28)
	ab.set_base(StatKeys.DASH_STAMINA_COST, 25.0)
	rules.apply(ab, 0, 8)
	rules.apply(ab, 0, 8)  # повторный вызов не должен дублировать бонусы
	assert(_near(ab.get_value(StatKeys.DASH_SPEED), 10.54), "agility 8 dash.speed 8.5 -> 10.54, got %f" % ab.get_value(StatKeys.DASH_SPEED))
	assert(_near(ab.get_value(StatKeys.DAMAGE_TAKEN_PHYSICAL), 1.0), "agility does not touch damage.taken_physical")
	assert(_near(ab.get_value(StatKeys.DAMAGE_TAKEN), 1.16), "agility 8 damage.taken 1.0 -> 1.16, got %f" % ab.get_value(StatKeys.DAMAGE_TAKEN))
	assert(_near(ab.get_value(StatKeys.ATTACK_SPEED), 1.24), "agility 8 attack.speed 1.24")
	assert(_near(ab.get_value(StatKeys.DASH_COOLDOWN), 0.39), "agility 8 dash.cooldown 0.39")
	rules.apply(ab, 8, 0)  # пересчёт: агильность снимается, броня добавляется
	assert(_near(ab.get_value(StatKeys.DASH_SPEED), 8.5), "armor-only build: dash unchanged")
	assert(_near(ab.get_value(StatKeys.DAMAGE_TAKEN_PHYSICAL), 0.68), "armor 8 damage.taken_physical 0.68")
	assert(_near(ab.get_value(StatKeys.DAMAGE_TAKEN), 1.0), "armor does not touch damage.taken")
	assert(_near(ab.get_value(StatKeys.PARRY_WINDOW), 0.32), "armor 8 parry window 0.32")
	assert(_near(ab.get_value(StatKeys.BLOCK_STAMINA_COST), 19.0), "armor 8 block cost 19")
	rules.apply(ab, 0, 0)
	assert(_near(ab.get_value(StatKeys.DAMAGE_TAKEN), 1.0) and _near(ab.get_value(StatKeys.DAMAGE_TAKEN_PHYSICAL), 1.0) and _near(ab.get_value(StatKeys.DASH_SPEED), 8.5), "zero build = neutral")
	rules.apply(ab, 10, 0)
	assert(_near(ab.get_value(StatKeys.DAMAGE_TAKEN_PHYSICAL), 0.6), "armor 10 hits physical floor 0.6")
	ab.free()
	print(">> TEST 2 PASSED")

	# ---------- сцена ----------
	var scene: Node = (load("res://scenes/test_player.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await physics_frame

	var player: Player = scene.get_node("Player") as Player
	var balanced: Enemy = scene.get_node("DynamicEnemy") as Enemy
	var armored: Enemy = scene.get_node("ObstacleRooms/Room1_RightWall/Dummy_RightWall") as Enemy
	var agile: Enemy = scene.get_node("ObstacleRooms/Room3_Tunnel/Dummy_Tunnel") as Enemy
	var neutral: Enemy = scene.get_node("ObstacleRooms/Room2_LeftWall/Dummy_LeftWall") as Enemy

	# ---------- TEST 3: все ключи имеют базы, пресеты применились ----------
	print("\n[TEST 3] Bases registered & presets applied")
	for actor: CombatCharacter3D in [player, balanced, armored, agile, neutral]:
		for k: StringName in StatKeys.BOUNDS:
			assert(actor.stat_block.has_base(k), "%s missing base for %s" % [actor.name, k])
	assert(_near(player.stat(StatKeys.DAMAGE_TAKEN), 1.0), "player neutral")
	assert(_near(neutral.stat(StatKeys.DAMAGE_TAKEN), 1.0), "left-wall dummy neutral")
	assert(_near(armored.stat(StatKeys.DAMAGE_TAKEN), 1.0 + 0.02 * 1) and _near(armored.stat(StatKeys.DAMAGE_TAKEN_PHYSICAL), 1.0 - 0.04 * 8), "armored preset damage.taken / taken_physical")
	assert(_near(agile.stat(StatKeys.DASH_SPEED), 8.5 * (1.0 + 0.03 * 8)), "agile preset dash.speed")
	assert(_near(balanced.stat(StatKeys.DAMAGE_TAKEN), 1.0 + 0.02 * 4) and _near(balanced.stat(StatKeys.DAMAGE_TAKEN_PHYSICAL), 1.0 - 0.04 * 4), "balanced preset damage.taken / taken_physical")
	print(">> TEST 3 PASSED")

	# ---------- TEST 4: входящий урон через take_damage ----------
	print("\n[TEST 4] take_hit: armor only vs physical")
	var hp_a: float = armored.health_component.current_health
	armored.take_damage(20.0, Vector3.ZERO, player)
	# броня 8, ловкость 1: физический ×1.02 × 0.68, магический только ×1.02
	var phys_mult: float = 1.02 * 0.68
	assert(_near(armored.damage_multiplier(DamageInfo.DamageType.PHYSICAL), phys_mult), "armored physical multiplier")
	assert(_near(armored.damage_multiplier(DamageInfo.DamageType.MAGIC), 1.02), "armored magic multiplier ignores armor")
	assert(_near(hp_a - armored.health_component.current_health, 20.0 * phys_mult), "armored physical damage scaled")
	var hp_m: float = armored.health_component.current_health
	var magic := DamageInfo.make(20.0, Vector3.ZERO, player)
	magic.damage_type = DamageInfo.DamageType.MAGIC
	var mres: Dictionary = armored.take_hit(magic)
	assert(_near(hp_m - armored.health_component.current_health, 20.0 * 1.02) and _near(mres["final_damage"], 20.0 * 1.02), "armored takes magic without armor")
	var bal_phys: float = balanced.damage_multiplier(DamageInfo.DamageType.PHYSICAL)
	assert(_near(bal_phys, 1.08 * 0.84), "balanced physical multiplier")
	var hp_n: float = neutral.health_component.current_health
	neutral.take_damage(20.0, Vector3.ZERO, player)
	assert(_near(hp_n - neutral.health_component.current_health, 20.0), "neutral damage unscaled")
	print(">> TEST 4 PASSED")

	# ---------- TEST 5: скорость удара ----------
	print("\n[TEST 5] attack.speed")
	var ok: bool = agile.attack_component.start_attack(false)
	assert(ok, "agile can attack")
	assert(_near(agile.attack_component.attack_speed_scale, agile.stat(StatKeys.ATTACK_SPEED)), "agile attack scale = attack.speed (%f)" % agile.attack_component.attack_speed_scale)
	assert(agile.attack_component.attack_speed_scale > 1.0, "agile swings faster")
	agile.attack_component.cancel_attack()
	print(">> TEST 5 PASSED")

	# ---------- TEST 6: дэш (скорость, кулдаун от конца, i-frames в пределах дэша) ----------
	print("\n[TEST 6] dash stats")
	var dc: DashComponent = agile.dash_component
	assert(dc.start_dash(DashComponent.DashDirection.BACKWARD), "agile can dash")
	assert(_near(dc.dash_cooldown_timer, 0.0), "cooldown not started during dash")
	assert(_near(dc._active_speed, agile.stat(StatKeys.DASH_SPEED)), "active dash speed from StatBlock")
	assert(dc._active_iframe_end <= dc._active_duration - 0.02 + 0.0001, "iframes end inside dash duration")
	dc.end_dash()
	assert(_near(dc.dash_cooldown_timer, agile.stat(StatKeys.DASH_COOLDOWN)), "cooldown starts at dash end")
	assert(not dc.can_dash(), "cannot dash during cooldown")
	print(">> TEST 6 PASSED")

	# ---------- TEST 7: ИИ планирует окно парирования под удар цели ----------
	print("\n[TEST 7] AI parry timing")
	assert(player.attack_component.start_attack(false), "player starts heavy attack")
	var ai: EnemyAIController = balanced.ai_controller
	ai.target = player
	var wd: WeaponData = player.attack_component.weapon_data
	var window: float = balanced.stat(StatKeys.PARRY_WINDOW)
	var expected: float = (wd.windup_time + EnemyAIController.PARRY_IMPACT_OFFSET) / player.attack_component.attack_speed_scale - window * EnemyAIController.PARRY_LEAD_FRACTION
	for i in 20:
		var d: float = ai._parry_start_delay()
		assert(absf(d - expected) <= 0.031, "parry delay %f ~ %f" % [d, expected])
		# окно должно накрывать момент открытия хитбокса (windup)
		assert(d <= wd.windup_time and d + window >= wd.windup_time - 0.03, "parry window covers hit moment")
	player.attack_component.cancel_attack()
	print(">> TEST 7 PASSED")

	# ---------- TEST 8: скорость движения и SpeedScale анимации ----------
	print("\n[TEST 8] move speed & animation SpeedScale")
	# armor 8 -> все скорости ×(1 − 0.02×8) = ×0.84
	assert(_near(armored.move_speed(StatKeys.MOVE_RUN), armored.stats.run_speed * 0.84), "armored run speed x0.84, got %f" % armored.move_speed(StatKeys.MOVE_RUN))
	assert(_near(neutral.move_speed(StatKeys.MOVE_RUN), neutral.stats.run_speed), "neutral run speed unchanged")
	assert(_near(armored.stat_block.get_base(StatKeys.MOVE_WALK), armored.stats.walk_speed), "get_base ignores modifiers")
	# Бежим на своей максимальной скорости: темп шагов должен быть пропорционален скорости.
	# Регрессия: если делить на эффективную ходьбу (с бронёй), ноги бронированного шли бы в обычном темпе.
	neutral.velocity = Vector3(neutral.move_speed(StatKeys.MOVE_RUN), 0.0, 0.0)
	armored.velocity = Vector3(armored.move_speed(StatKeys.MOVE_RUN), 0.0, 0.0)
	neutral._update_animations(0.016)
	armored._update_animations(0.016)
	var scale_n: float = neutral.animation_tree.get("parameters/SpeedScale/scale")
	var scale_a: float = armored.animation_tree.get("parameters/SpeedScale/scale")
	assert(_near(scale_a / scale_n, 0.84, 0.001), "armored step rate scales with speed (x0.84), got %f" % (scale_a / scale_n))
	neutral.velocity = Vector3.ZERO
	armored.velocity = Vector3.ZERO
	print(">> TEST 8 PASSED")

	# ---------- TEST 9: кулдаун уклонов ИИ стартует только после успешного cmd_dash ----------
	print("\n[TEST 9] AI dodge cooldown only after successful dash")
	var ai2: EnemyAIController = balanced.ai_controller
	balanced.defense_component.end_block()
	assert(balanced.defense_component.start_block(), "balanced raises guard")
	ai2.dodge_cooldown_timer = 0.0
	ai2._execute_random_dodge()  # cmd_dash откажет: нельзя дэшить из блока
	assert(not balanced.is_dashing, "dash refused while blocking")
	assert(_near(ai2.dodge_cooldown_timer, 0.0), "failed dash must NOT start dodge cooldown, got %f" % ai2.dodge_cooldown_timer)
	balanced.defense_component.end_block()
	ai2._execute_random_dodge()
	assert(balanced.is_dashing, "dash started when guard is down")
	assert(ai2.dodge_cooldown_timer > 0.0 and ai2.dodge_cooldown_timer <= ai2.dodge_cooldown_max, "successful dash starts dodge cooldown, got %f" % ai2.dodge_cooldown_timer)
	balanced.dash_component.end_dash()
	print(">> TEST 9 PASSED")

	# ---------- TEST 10: броня в DefenseComponent (цена блока, окно парирования) ----------
	print("\n[TEST 10] armor in DefenseComponent")
	var dfn: DefenseComponent = armored.defense_component
	dfn.end_block()
	assert(dfn.start_block(), "armored raises guard")
	var stam_before: float = armored.stamina_component.current_stamina
	var res: Dictionary = dfn.evaluate_hit(DamageInfo.make(20.0, Vector3.ZERO))  # attacker=null -> удар «спереди»
	assert(res["was_blocked"], "hit is blocked")
	# armor 8: цена блока 35 − 2×8 = 19
	assert(_near(stam_before - armored.stamina_component.current_stamina, armored.stat(StatKeys.BLOCK_STAMINA_COST)), "block costs build-adjusted stamina")
	assert(_near(armored.stat(StatKeys.BLOCK_STAMINA_COST), 19.0), "armor 8 block cost = 19")
	assert(dfn.trigger_parry(), "armored opens parry window")
	assert(_near(dfn.parry_timer, armored.stat(StatKeys.PARRY_WINDOW)), "parry window from StatBlock")
	assert(dfn.parry_timer > dfn.parry_window_duration, "armor widens parry window")
	dfn.end_block()
	print(">> TEST 10 PASSED")

	# ---------- TEST 11: цена блока зависит от удара (WeaponData.block_stamina_damage) ----------
	print("\n[TEST 11] per-hit block stamina cost")
	assert(_near((load("res://resources/weapons/greatsword.tres") as WeaponData).block_stamina_damage, 35.0), "player heavy block cost 35")
	assert(_near((load("res://resources/weapons/enemy_sword.tres") as WeaponData).block_stamina_damage, 35.0), "enemy heavy block cost 35")
	assert(_near((load("res://resources/weapons/greatsword_light.tres") as WeaponData).block_stamina_damage, 15.0), "player light block cost 15")
	assert(_near((load("res://resources/weapons/enemy_sword_light.tres") as WeaponData).block_stamina_damage, 15.0), "enemy light block cost 15")
	var hb: Hitbox = armored.attack_component.weapon_hitbox
	assert(hb != null and _near(hb.block_stamina_damage, armored.attack_component.weapon_data.block_stamina_damage), "hitbox takes block cost from weapon data")
	# armored: stat цена блока 19 (база 35). Heavy 35 -> 19, light 15 -> 19 * 15 / 35, без значения -> 19
	var costs: Dictionary = {35.0: 19.0, 15.0: 19.0 * 15.0 / 35.0, -1.0: 19.0}
	for hit_cost: float in costs:
		dfn.end_block()
		armored.stamina_component.current_stamina = armored.stamina_component.max_stamina
		assert(dfn.start_block(), "armored raises guard (hit cost %.0f)" % hit_cost)
		var before: float = armored.stamina_component.current_stamina
		var r: Dictionary = dfn.evaluate_hit(DamageInfo.make(20.0, Vector3.ZERO, null, &"direct", hit_cost))
		assert(r["was_blocked"], "hit is blocked (hit cost %.0f)" % hit_cost)
		var spent: float = before - armored.stamina_component.current_stamina
		assert(_near(spent, costs[hit_cost]), "hit cost %.0f -> spent %.3f, expected %.3f" % [hit_cost, spent, costs[hit_cost]])
	# Нейтральный билд: лёгкий удар 15, тяжёлый 35
	var neutral_dfn: DefenseComponent = player.defense_component
	for hit_cost: float in [35.0, 15.0]:
		neutral_dfn.end_block()
		player.stamina_component.current_stamina = player.stamina_component.max_stamina
		assert(neutral_dfn.start_block(), "player raises guard")
		var before_n: float = player.stamina_component.current_stamina
		neutral_dfn.evaluate_hit(DamageInfo.make(20.0, Vector3.ZERO, null, &"direct", hit_cost))
		assert(_near(before_n - player.stamina_component.current_stamina, hit_cost), "neutral build pays exactly %.0f" % hit_cost)
	# Сквозная цепочка take_damage -> evaluate_hit: цена блока передаётся 4-м аргументом
	neutral_dfn.end_block()
	player.stamina_component.current_stamina = player.stamina_component.max_stamina
	assert(neutral_dfn.start_block(), "player raises guard for take_damage check")
	var before_t: float = player.stamina_component.current_stamina
	player.take_damage(1.0, Vector3.ZERO, null, 15.0)
	assert(_near(before_t - player.stamina_component.current_stamina, 15.0), "take_damage passes block cost to DefenseComponent")
	neutral_dfn.end_block()
	dfn.end_block()
	print(">> TEST 11 PASSED")

	print("\nALL BUILD STATS TESTS PASSED 100%!")
	quit()
