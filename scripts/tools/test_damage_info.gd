extends SceneTree
## Задача 1.1: DamageInfo и take_hit. Обёртка take_damage и take_hit дают одинаковый итог.

var player: Player
var dummy: Enemy


func _init() -> void:
	_run_tests()


func _near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps


## Сбрасывает игрока в чистое состояние: полные HP/стамина, блока нет, не оглушён.
func _reset() -> void:
	player.defense_component.end_block()
	player.dash_component.is_dashing = false
	player.restore_full()


## Снимок состояния после удара.
func _snap() -> Dictionary:
	return {
		"hp": player.health_component.current_health,
		"stamina": player.stamina_component.current_stamina,
		"vel": Vector2(player.velocity.x, player.velocity.z),
		"staggered": player.is_staggered,
	}


func _same(a: Dictionary, b: Dictionary) -> bool:
	return _near(a["hp"], b["hp"]) and _near(a["stamina"], b["stamina"]) \
		and a["vel"].distance_to(b["vel"]) < 0.01 and a["staggered"] == b["staggered"]


## Прогоняет сценарий дважды: через take_damage (обёртка) и через take_hit. Возвращает [снимок_обёртки, снимок_take_hit, результат_take_hit].
func _compare(prepare: Callable, amount: float, knockback: Vector3, block_stamina: float = -1.0, attacker: Node3D = null) -> Array:
	_reset()
	prepare.call()
	player.take_damage(amount, knockback, attacker, block_stamina)
	var via_wrapper: Dictionary = _snap()

	_reset()
	prepare.call()
	var res: Dictionary = player.take_hit(DamageInfo.make(amount, knockback, attacker, &"direct", block_stamina))
	return [via_wrapper, _snap(), res]


func _run_tests() -> void:
	print("--- STARTING DAMAGE INFO TESTS ---")
	var scene: Node = (load("res://scenes/test_player.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	player = scene.get_node("Player") as Player
	dummy = scene.get_node("ObstacleRooms/Room2_LeftWall/Dummy_LeftWall") as Enemy
	assert(player != null and dummy != null, "Player and dummy must exist")
	# Контроллер игрока сбросил бы блок/цель
	player.set_process(false)
	player.set_physics_process(false)
	for child in player.get_children():
		if child is PlayerController:
			child.set_process(false)
			child.set_physics_process(false)

	# ---------- TEST 1: DamageInfo ----------
	print("\n[TEST 1] DamageInfo defaults")
	var info := DamageInfo.make(12.0, Vector3(1, 0, 0), dummy, &"light", 15.0)
	assert(_near(info.amount, 12.0) and info.knockback == Vector3(1, 0, 0), "amount/knockback")
	assert(info.attacker == dummy and info.source == &"light", "attacker/source")
	assert(_near(info.block_stamina, 15.0), "block_stamina")
	assert(info.damage_type == DamageInfo.DamageType.PHYSICAL, "default type is physical")
	assert(not info.unblockable and not info.unparryable, "flags off by default")
	assert(info.causes_hit_react, "hit-react on by default")
	assert(_near(info.break_damage, 0.0), "break_damage 0")
	var plain := DamageInfo.make(5.0, Vector3.ZERO)
	assert(plain.source == &"direct" and plain.block_stamina < 0.0, "defaults of make()")
	print(">> TEST 1 PASSED")

	# ---------- TEST 2: чистое попадание ----------
	print("\n[TEST 2] clean hit: wrapper == take_hit")
	var r2: Array = _compare(func(): pass, 10.0, Vector3(3, 0, 0))
	assert(_same(r2[0], r2[1]), "wrapper and take_hit give the same state")
	var res2: Dictionary = r2[2]
	assert(_near(player.health_component.current_health, 100.0 - 10.0 * player.stat(StatKeys.DAMAGE_TAKEN)), "hp lost")
	assert(not res2["dodged"] and not res2["was_blocked"] and not res2["was_parried"] and not res2["was_guard_broken"], "no defence flags")
	assert(_near(res2["final_damage"], 10.0 * player.stat(StatKeys.DAMAGE_TAKEN)), "final_damage")
	assert(res2["reacted"] == true, "clean hit reacts")
	print(">> TEST 2 PASSED")

	# ---------- TEST 3: блок ----------
	print("\n[TEST 3] block: wrapper == take_hit, cost from block_stamina")
	var prep_block := func(): assert(player.defense_component.start_block(), "raise guard")
	var r3: Array = _compare(prep_block, 20.0, Vector3(3, 0, 0), 15.0)
	assert(_same(r3[0], r3[1]), "wrapper and take_hit give the same state (block)")
	var res3: Dictionary = r3[2]
	assert(res3["was_blocked"] and not res3["was_parried"] and not res3["was_guard_broken"], "blocked flags")
	assert(_near(res3["final_damage"], 20.0 * 0.15), "blocked damage ×0.15")
	assert(not res3["reacted"], "block does not react")
	assert(_near(100.0 - player.stamina_component.current_stamina, 15.0), "block cost 15 comes from info.block_stamina")
	print(">> TEST 3 PASSED")

	# ---------- TEST 4: парирование ----------
	print("\n[TEST 4] parry")
	var prep_parry := func():
		assert(player.defense_component.start_block(), "raise guard")
		assert(player.defense_component.trigger_parry(), "open parry window")
	var r4: Array = _compare(prep_parry, 30.0, Vector3(3, 0, 0))
	assert(_same(r4[0], r4[1]), "wrapper and take_hit give the same state (parry)")
	var res4: Dictionary = r4[2]
	assert(res4["was_parried"] and not res4["was_blocked"], "parried flags")
	assert(_near(res4["final_damage"], 0.0) and not res4["reacted"], "no damage, no reaction")
	assert(_near(player.health_component.current_health, 100.0), "hp untouched after parry")
	print(">> TEST 4 PASSED")

	# ---------- TEST 5: guard break ----------
	print("\n[TEST 5] guard break")
	var prep_gb := func():
		assert(player.defense_component.start_block(), "raise guard")
		player.stamina_component.current_stamina = 5.0
	var r5: Array = _compare(prep_gb, 20.0, Vector3(3, 0, 0))
	assert(_same(r5[0], r5[1]), "wrapper and take_hit give the same state (guard break)")
	var res5: Dictionary = r5[2]
	assert(res5["was_blocked"] and res5["was_guard_broken"], "guard broken flags")
	assert(player.is_staggered, "guard break staggers")
	print(">> TEST 5 PASSED")

	# ---------- TEST 6: i-frames дэша ----------
	print("\n[TEST 6] dash i-frames")
	var prep_dash := func():
		player.dash_component.is_dashing = true
		player.dash_component.dash_time_elapsed = 0.1
		player.dash_component._active_iframe_end = 0.3
	var r6: Array = _compare(prep_dash, 30.0, Vector3(3, 0, 0))
	assert(_same(r6[0], r6[1]), "wrapper and take_hit give the same state (dodge)")
	var res6: Dictionary = r6[2]
	assert(res6["dodged"] and _near(res6["final_damage"], 0.0) and not res6["reacted"], "dodged")
	assert(_near(player.health_component.current_health, 100.0), "hp untouched when dodged")
	print(">> TEST 6 PASSED")

	# ---------- TEST 7: causes_hit_react = false ----------
	print("\n[TEST 7] causes_hit_react = false")
	_reset()
	var quiet := DamageInfo.make(10.0, Vector3.ZERO)
	quiet.causes_hit_react = false
	var res7: Dictionary = player.take_hit(quiet)
	assert(_near(player.health_component.current_health, 100.0 - 10.0 * player.stat(StatKeys.DAMAGE_TAKEN)), "damage still applied")
	assert(res7["reacted"] == false, "no hit-react without the flag")
	print(">> TEST 7 PASSED")

	# ---------- TEST 8: источники удара ----------
	print("\n[TEST 8] hitbox and kick pass source")
	_reset()
	var hb: Hitbox = player.attack_component.weapon_hitbox
	assert(hb != null, "player has weapon hitbox")
	hb.damage_source = &"light"
	var built: DamageInfo = hb._build_damage_info(Vector3(1, 0, 0))
	assert(built.source == &"light" and _near(built.amount, hb.damage), "hitbox builds DamageInfo from its fields")
	assert(_near(built.block_stamina, hb.block_stamina_damage), "hitbox passes block cost")
	var got: Array = []
	var probe := _SourceProbe.new()
	probe.sink = got
	player.kick_component._hit_target(probe, 10.0, Vector3.ZERO)
	assert(got.size() == 1 and (got[0] as DamageInfo).source == &"kick", "kick sends source=kick via take_hit")
	probe.free()
	print(">> TEST 8 PASSED")

	print("\nALL DAMAGE INFO TESTS PASSED 100%!")
	quit()


## Узел-приёмник: записывает пришедший DamageInfo.
class _SourceProbe extends Node3D:
	var sink: Array = []

	func take_hit(info: DamageInfo) -> Dictionary:
		sink.append(info)
		return {}
