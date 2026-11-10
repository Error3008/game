extends SceneTree

## Регрессия характера ИИ: математика AIPersonality, целостность ресурсов resources/ai,
## масштабирование параметров в EnemyAIController, лёгкая атака и лечение ИИ,
## статистическое различие Bully и Turtle (решения считаются на фиксированном сиде, без боя ботов).

func _init() -> void:
	_run_tests()


func _trait(mults: Dictionary) -> TraitProfile:
	var list: Array[TraitEffect] = []
	for k: StringName in mults:
		list.append(TraitEffect.make(k, mults[k]))
	return TraitProfile.make("t", list)


func _personality(weights: Dictionary) -> AIPersonality:
	var p := AIPersonality.new()
	for t: TraitProfile in weights:
		p.traits[t] = weights[t]
	return p


func _run_tests() -> void:
	print("--- STARTING AI PERSONALITY TESTS ---")

	# --- TEST 1: Math ---
	print("\n[TEST 1] AIPersonality math: weights, normalization, clamp, edge cases")
	var half := _trait({&"dodge_chance": 0.5})
	var one_half := _trait({&"dodge_chance": 1.5})
	var even := _personality({half: 1.0, one_half: 1.0})
	assert(is_equal_approx(even.resolve(&"dodge_chance", 0.4), 0.4), "1:1 weights of x0.5 and x1.5 cancel out")
	var skewed := _personality({half: 3.0, one_half: 1.0})
	assert(is_equal_approx(skewed.resolve(&"dodge_chance", 0.4), 0.3), "3:1 -> x0.75, got %f" % skewed.resolve(&"dodge_chance", 0.4))
	assert(is_equal_approx(skewed.resolve(&"block_chance", 0.4), 0.4), "Param not mentioned by any trait stays at base")
	var scaled_weights := _personality({half: 30.0, one_half: 10.0})
	assert(is_equal_approx(scaled_weights.resolve(&"dodge_chance", 0.4), 0.3), "Weights are normalized (30:10 == 3:1)")
	assert(is_equal_approx(AIPersonality.new().resolve(&"dodge_chance", 0.5), 0.5), "Empty personality returns base")
	assert(is_equal_approx(_personality({half: 0.0}).resolve(&"dodge_chance", 0.5), 0.5), "Zero total weight returns base")
	assert(is_equal_approx(_personality({half: -1.0, one_half: 1.0}).resolve(&"dodge_chance", 0.4), 0.6), "Negative weight counts as 0")
	var boost := _personality({_trait({&"dodge_chance": 3.0, &"attack_cooldown": 0.1}): 1.0})
	assert(is_equal_approx(boost.resolve(&"dodge_chance", 0.9), 1.0), "Chance clamps to 1.0")
	assert(is_equal_approx(boost.resolve(&"attack_cooldown", 2.0), 0.8), "Cooldown clamps to lower bound 0.8")
	var double_effect := _personality({_trait_two(&"dodge_chance", 0.5, 0.5): 1.0})
	assert(is_equal_approx(double_effect.resolve(&"dodge_chance", 0.8), 0.2), "Two effects on one param multiply")
	print(">> TEST 1 PASSED")

	# --- TEST 2: Resource integrity ---
	print("\n[TEST 2] resources/ai: every trait param is a known AIParams key; personalities are valid")
	var dir := DirAccess.open("res://resources/ai")
	assert(dir != null, "resources/ai must exist")
	var trait_count: int = 0
	var personality_count: int = 0
	for file in dir.get_files():
		var res: Resource = load("res://resources/ai/" + file)
		if res is TraitProfile:
			trait_count += 1
			assert(res.effects.size() > 0, "%s has effects" % file)
			for e: TraitEffect in res.effects:
				assert(AIParams.is_known(e.param), "%s: unknown param '%s'" % [file, e.param])
				assert(e.multiplier > 0.0, "%s: multiplier > 0" % file)
		elif res is AIPersonality:
			personality_count += 1
			assert(res.total_weight() > 0.0, "%s has positive total weight" % file)
			for t in res.traits:
				assert(t != null, "%s has no null traits" % file)
	assert(trait_count >= 3 and personality_count >= 3, "3 traits and 3 personalities exist, got %d/%d" % [trait_count, personality_count])
	print(">> TEST 2 PASSED (%d traits, %d personalities)" % [trait_count, personality_count])

	# --- TEST 3: randomized ---
	print("\n[TEST 3] randomized(): spread 0 = copy, spread >0 stays within bounds, original untouched")
	var duelist: AIPersonality = load("res://resources/ai/personality_duelist.tres")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var same := duelist.randomized(0.0, rng)
	for t in duelist.traits:
		assert(is_equal_approx(same.traits[t], duelist.traits[t]), "spread 0 keeps weights")
	var before: Dictionary = duelist.traits.duplicate()
	var varied := duelist.randomized(0.5, rng)
	var any_changed: bool = false
	for t in duelist.traits:
		var w: float = duelist.traits[t]
		var vw: float = varied.traits[t]
		assert(vw >= 0.0 and vw >= w * 0.5 - 0.0001 and vw <= w * 1.5 + 0.0001, "weight within +-50%%: %f vs %f" % [vw, w])
		if not is_equal_approx(vw, w):
			any_changed = true
		assert(is_equal_approx(duelist.traits[t], before[t]), "original is not modified")
	assert(any_changed, "spread 0.5 changes at least one weight")
	assert(varied.traits.size() == duelist.traits.size(), "same trait set")
	print(">> TEST 3 PASSED")

	# --- Scene for controller tests ---
	var scene: Node = (load("res://scenes/test_player.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var player: Player = scene.get_node("Player") as Player
	var bully: Enemy = scene.get_node("Enemy_Bully") as Enemy
	var turtle: Enemy = scene.get_node("Enemy_Turtle") as Enemy
	assert(player != null and bully != null and turtle != null, "Player, Enemy_Bully, Enemy_Turtle must exist")
	var ai: EnemyAIController = bully.ai_controller
	var ai_turtle: EnemyAIController = turtle.ai_controller
	ai.set_physics_process(false)
	ai_turtle.set_physics_process(false)
	bully.cmd_set_target(player)
	var bully_p: AIPersonality = load("res://resources/ai/personality_bully.tres")
	var turtle_p: AIPersonality = load("res://resources/ai/personality_turtle.tres")

	# --- TEST 4: _p() and cache ---
	print("\n[TEST 4] EnemyAIController._p(): raw base without personality, scaling with it, cache invalidation")
	assert(ai.personality == bully_p, "Scene assigns Bully personality to Enemy_Bully")
	assert(ai_turtle.personality == turtle_p, "Scene assigns Turtle personality to Enemy_Turtle")
	ai.personality = null
	assert(ai._p(AIParams.DODGE_CHANCE, 0.5) == 0.5, "No personality: base unchanged")
	assert(ai._p(AIParams.DODGE_CHANCE, 5.0) == 5.0, "No personality: base is not even clamped")
	ai.personality = turtle_p
	var turtle_dodge: float = ai._p(AIParams.DODGE_CHANCE, 0.5)
	assert(turtle_dodge > 0.55, "Turtle dodges more than base, got %f" % turtle_dodge)
	ai.personality = bully_p
	var bully_dodge: float = ai._p(AIParams.DODGE_CHANCE, 0.5)
	assert(bully_dodge < 0.45, "Bully dodges less than base (cache must be invalidated), got %f" % bully_dodge)
	print(">> TEST 4 PASSED")

	# --- TEST 5: Bully vs Turtle ---
	print("\n[TEST 5] Bully vs Turtle: resolved parameters and sampled decisions differ in the expected direction")
	var p := func(c: EnemyAIController, key: StringName, base: float) -> float:
		return c._p(key, base)
	ai.personality = bully_p
	ai_turtle.personality = turtle_p
	# Одинаковые базы, различается только личность
	ai_turtle.dodge_chance = ai.dodge_chance
	ai_turtle.block_chance = ai.block_chance
	for pair in [
		[AIParams.DODGE_CHANCE, ai.dodge_chance],
		[AIParams.BLOCK_CHANCE, ai.block_chance],
		[AIParams.TACTICAL_BLOCK_CHANCE, ai.tactical_block_chance],
		[AIParams.HEAL_HP_THRESHOLD, ai.heal_hp_threshold],
		[AIParams.HEAL_SAFE_DISTANCE, ai.heal_safe_distance],
	]:
		assert(p.call(ai, pair[0], pair[1]) < p.call(ai_turtle, pair[0], pair[1]), "Turtle > Bully for %s" % pair[0])
	assert(ai._p(AIParams.ENGAGE_DIST, ai.combat_engage_dist) > ai_turtle._p(AIParams.ENGAGE_DIST, ai.combat_engage_dist), "Bully engages from farther")

	seed(12345)
	var n: int = 2000
	var bully_cd: float = 0.0
	var turtle_cd: float = 0.0
	for i in n:
		bully_cd += ai._roll_scaled(AIParams.ATTACK_COOLDOWN, ai.attack_cooldown_min, ai.attack_cooldown_max)
		turtle_cd += ai_turtle._roll_scaled(AIParams.ATTACK_COOLDOWN, ai.attack_cooldown_min, ai.attack_cooldown_max)
	bully_cd /= n
	turtle_cd /= n
	print("   mean attack cooldown: Bully %.2fs, Turtle %.2fs" % [bully_cd, turtle_cd])
	assert(bully_cd < turtle_cd * 0.6, "Bully attacks much more often")

	var m: int = 20000
	var bully_light: int = 0
	var turtle_light: int = 0
	for i in m:
		ai._plan_next_attack()
		ai_turtle._plan_next_attack()
		bully_light += 1 if ai._planned_light else 0
		turtle_light += 1 if ai_turtle._planned_light else 0
	var bully_frac: float = float(bully_light) / m
	var turtle_frac: float = float(turtle_light) / m
	print("   light attack share: Bully %.3f, Turtle %.3f" % [bully_frac, turtle_frac])
	assert(bully_frac > turtle_frac, "Bully uses light attacks more often")
	assert(absf(bully_frac - ai._p(AIParams.LIGHT_ATTACK_CHANCE, ai.light_attack_chance)) < 0.02, "Sampled share matches resolved chance")
	print(">> TEST 5 PASSED")

	# --- TEST 6: Light attack by AI ---
	print("\n[TEST 6] AI attacks: planned light/heavy, forced light on low stamina, can_light_attack off")
	ai.personality = null
	var atk: MeleeAttackComponent = bully.attack_component
	bully.stamina_component.current_stamina = 100.0
	ai.light_attack_chance = 1.0
	ai._plan_next_attack()
	assert(ai._planned_light and ai._use_light_attack(), "Chance 1.0 plans a light attack")
	assert(ai._planned_strike_reach() == ai.light_strike_reach, "Light attack uses light reach")
	assert(ai._execute_planned_attack() == true, "Light attack starts")
	assert(atk.weapon_data == atk.light_weapon_data, "Light weapon is active")
	atk.cancel_attack()
	ai.light_attack_chance = 0.0
	ai._plan_next_attack()
	assert(not ai._use_light_attack(), "Chance 0 with full stamina plans heavy")
	assert(ai._planned_strike_reach() == ai.strike_effective_reach, "Heavy attack uses heavy reach")
	assert(ai._execute_planned_attack() == true, "Heavy attack starts")
	assert(atk.weapon_data == atk.heavy_weapon_data, "Heavy weapon is active")
	atk.cancel_attack()
	bully.stamina_component.current_stamina = 12.0 # тяжёлая стоит 20, лёгкая 10
	assert(ai._use_light_attack(), "Not enough stamina for heavy forces light")
	assert(ai._execute_planned_attack() == true, "Forced light attack starts")
	assert(atk.weapon_data == atk.light_weapon_data and not atk.is_exhausted_attack, "Light, not an exhausted heavy swing")
	atk.cancel_attack()
	ai.can_light_attack = false
	assert(not ai._use_light_attack(), "can_light_attack=false disables light attacks even at low stamina")
	ai.can_light_attack = true
	ai.light_attack_chance = 0.30
	bully.stamina_component.current_stamina = 100.0
	print(">> TEST 6 PASSED")

	# --- TEST 7: Healing by AI ---
	print("\n[TEST 7] AI heals: threshold, safe distance, retreat, give-up, charges, dummy, personality")
	var hc: HealComponent = bully.heal_component
	hc.charges = 3
	ai.personality = null
	assert(not ai._wants_heal(), "Full HP: does not want to heal")
	bully.health_component.current_health = bully.max_health * 0.5
	assert(not ai._wants_heal(), "50%% HP is above the 35%% threshold")
	bully.health_component.current_health = bully.max_health * 0.2
	assert(ai._wants_heal(), "20%% HP: wants to heal")

	assert(ai._process_heal(10.0, 0.016) == true and bully.is_healing, "Far from target: starts drinking")
	hc.cancel_heal()
	hc.charges = 3

	var gave_up: bool = false
	for i in 400:
		if not ai._process_heal(2.0, 0.016):
			gave_up = true
			break
		assert(not bully.is_healing, "Close to target: retreats instead of drinking")
	assert(gave_up, "Retreat times out")
	assert(ai._heal_retry_timer > 0.0 and not ai._wants_heal(), "After giving up: waits before the next attempt")
	ai._heal_retry_timer = 0.0
	assert(ai._wants_heal(), "Retry timer expired: wants to heal again")

	hc.charges = 0
	assert(not ai._wants_heal(), "No charges: does not want to heal")
	hc.charges = 3
	ai.is_dummy = true
	assert(not ai._wants_heal(), "Dummy never heals")
	ai.is_dummy = false
	ai.can_heal_self = false
	assert(not ai._wants_heal(), "can_heal_self=false disables healing")
	ai.can_heal_self = true

	bully.health_component.current_health = bully.max_health * 0.30
	ai.personality = bully_p
	assert(not ai._wants_heal(), "Bully (threshold ~24%%) fights on at 30%% HP")
	ai.personality = turtle_p
	assert(ai._wants_heal(), "Turtle (threshold ~45%%) drinks at 30%% HP")
	print(">> TEST 7 PASSED")

	print("\nALL AI PERSONALITY TESTS PASSED 100%!")
	quit()


func _trait_two(key: StringName, m1: float, m2: float) -> TraitProfile:
	var list: Array[TraitEffect] = [TraitEffect.make(key, m1), TraitEffect.make(key, m2)]
	return TraitProfile.make("t2", list)
