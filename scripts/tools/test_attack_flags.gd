extends SceneTree
## Задача 1.3: флаги атаки (WeaponData → Hitbox → DamageInfo), unblockable/unparryable, hyper armor.

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


## Чистое состояние обоих: полные HP/стамина, нет блока и оглушения, действия отменены.
func _reset() -> void:
	for a: CombatCharacter3D in [player, dummy]:
		a.restore_full()
		a.defense_component.end_block()
		a.dash_component.is_dashing = false
		a.is_staggered = false
		a.stagger_timer = 0.0
		a.velocity = Vector3.ZERO


func _info(unblockable: bool = false, unparryable: bool = false) -> DamageInfo:
	var info := DamageInfo.make(20.0, Vector3(3, 0, 0), player, &"heavy", 35.0)
	info.unblockable = unblockable
	info.unparryable = unparryable
	return info


func _run_tests() -> void:
	print("--- STARTING ATTACK FLAGS TESTS ---")
	var scene: Node = (load("res://scenes/test_player.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	player = scene.get_node("Player") as Player
	dummy = scene.get_node("ObstacleRooms/Room2_LeftWall/Dummy_LeftWall") as Enemy
	assert(player != null and dummy != null, "Player and dummy must exist")
	_freeze(player)
	_freeze(dummy)

	# Лицом к лицу на 1.5 м
	player.global_position = Vector3(0.0, 0.0, 0.0)
	dummy.global_position = Vector3(0.0, 0.0, -1.5)
	player.pawn.rotation.y = atan2(dummy.global_position.x - player.global_position.x, dummy.global_position.z - player.global_position.z)
	dummy.pawn.rotation.y = atan2(player.global_position.x - dummy.global_position.x, player.global_position.z - dummy.global_position.z)

	# ---------- TEST 1: WeaponData → Hitbox → DamageInfo ----------
	print("\n[TEST 1] weapon flags reach DamageInfo")
	var plain := WeaponData.new()
	assert(plain.damage_type == DamageInfo.DamageType.PHYSICAL and not plain.unblockable and not plain.unparryable \
		and not plain.hyper_armor and _near(plain.break_damage, 0.0) and plain.telegraph == &"", "weapon defaults")
	var flagged := WeaponData.new()
	flagged.damage_type = DamageInfo.DamageType.MAGIC
	flagged.unblockable = true
	flagged.unparryable = true
	flagged.break_damage = 7.0
	flagged.damage = 25.0
	var hb: Hitbox = player.attack_component.weapon_hitbox
	assert(hb != null, "player has weapon hitbox")
	hb.apply_weapon(flagged)
	var built: DamageInfo = hb._build_damage_info(Vector3(1, 0, 0))
	assert(built.damage_type == DamageInfo.DamageType.MAGIC and built.unblockable and built.unparryable, "flags copied")
	assert(_near(built.break_damage, 7.0) and _near(built.amount, 25.0), "break_damage and damage copied")
	hb.apply_weapon(plain)
	print(">> TEST 1 PASSED")

	# ---------- TEST 2: unblockable проходит сквозь блок ----------
	print("\n[TEST 2] unblockable passes through block")
	_reset()
	dummy.cmd_block_start()
	assert(dummy.is_blocking(), "dummy blocks")
	var res_block: Dictionary = dummy.take_hit(_info())
	assert(res_block["was_blocked"] and _near(res_block["final_damage"], 20.0 * 0.15 * dummy.damage_multiplier(DamageInfo.DamageType.PHYSICAL)), "plain hit is blocked")
	_reset()
	dummy.cmd_block_start()
	var stam_before: float = dummy.stamina_component.current_stamina
	var res_unb: Dictionary = dummy.take_hit(_info(true))
	assert(not res_unb["was_blocked"] and not res_unb["was_parried"], "unblockable not blocked")
	assert(_near(res_unb["final_damage"], 20.0 * dummy.damage_multiplier(DamageInfo.DamageType.PHYSICAL)), "unblockable deals full damage")
	assert(_near(dummy.stamina_component.current_stamina, stam_before), "unblockable costs no block stamina")
	assert(res_unb["reacted"], "unblockable hit reacts")
	print(">> TEST 2 PASSED")

	# ---------- TEST 3: unblockable и окно парирования ----------
	print("\n[TEST 3] unblockable ignores parry window")
	_reset()
	dummy.cmd_block_start()
	assert(dummy.defense_component.trigger_parry(), "parry window open")
	var res_unb_parry: Dictionary = dummy.take_hit(_info(true))
	assert(not res_unb_parry["was_parried"] and _near(res_unb_parry["final_damage"], 20.0 * dummy.damage_multiplier(DamageInfo.DamageType.PHYSICAL)), "unblockable beats parry")
	print(">> TEST 3 PASSED")

	# ---------- TEST 4: unparryable можно только блокировать ----------
	print("\n[TEST 4] unparryable can be blocked, not parried")
	_reset()
	dummy.cmd_block_start()
	assert(dummy.defense_component.trigger_parry(), "parry window open")
	var res_unp: Dictionary = dummy.take_hit(_info(false, true))
	assert(res_unp["was_blocked"] and not res_unp["was_parried"], "unparryable in parry window is a plain block")
	assert(_near(res_unp["final_damage"], 20.0 * 0.15 * dummy.damage_multiplier(DamageInfo.DamageType.PHYSICAL)), "blocked damage")
	assert(not player.is_staggered, "attacker not staggered")
	# обычный удар в окне парируется
	_reset()
	dummy.cmd_block_start()
	dummy.defense_component.trigger_parry()
	var res_par: Dictionary = dummy.take_hit(_info())
	assert(res_par["was_parried"], "plain hit is parried")
	print(">> TEST 4 PASSED")

	# ---------- TEST 5: hyper armor ----------
	print("\n[TEST 5] hyper armor window")
	_reset()
	var armored_weapon: WeaponData = player.attack_component.heavy_weapon_data.duplicate()
	armored_weapon.hyper_armor = true
	player.attack_component.heavy_weapon_data = armored_weapon
	assert(player.get_current_attack_profile() == null and not player.has_hyper_armor(), "idle: no profile, no armor")
	assert(player.cmd_attack(), "player starts heavy attack")
	assert(player.get_current_attack_profile() == armored_weapon, "profile is the current weapon")
	assert(player.has_hyper_armor(), "armor from the first frame of windup")
	var hp0: float = player.health_component.current_health
	var res_hit: Dictionary = player.take_hit(DamageInfo.make(10.0, Vector3(10, 0, 0), dummy))
	assert(not res_hit["reacted"] and not player.is_staggered and player.is_attacking, "hit does not interrupt")
	assert(_near(hp0 - player.health_component.current_health, 10.0 * player.damage_multiplier(DamageInfo.DamageType.PHYSICAL)), "damage still applied")
	assert(_near(player.velocity.x, 3.0), "knockback ×0.3")
	# активная фаза всё ещё под защитой
	player.attack_component.attack_time_elapsed = armored_weapon.active_end_time - 0.01
	assert(player.has_hyper_armor(), "armor lasts to the end of the active phase")
	# восстановление: защиты нет, удар прерывает
	player.attack_component.attack_time_elapsed = armored_weapon.active_end_time + 0.01
	assert(not player.has_hyper_armor(), "no armor in recovery")
	var res_rec: Dictionary = player.take_hit(DamageInfo.make(10.0, Vector3.ZERO, dummy))
	assert(res_rec["reacted"] and player.is_staggered and not player.is_attacking, "recovery hit interrupts")
	print(">> TEST 5 PASSED")

	# ---------- TEST 6: парирование сбивает hyper armor ----------
	print("\n[TEST 6] parry still breaks hyper armor")
	_reset()
	assert(player.cmd_attack() and player.has_hyper_armor(), "armored attack started")
	dummy.cmd_block_start()
	assert(dummy.defense_component.trigger_parry(), "dummy opens parry window")
	var res_p: Dictionary = dummy.take_hit(DamageInfo.make(40.0, Vector3(4, 0, 0), player))
	assert(res_p["was_parried"], "dummy parries")
	assert(player.is_staggered and not player.is_attacking, "armored attacker is staggered by the parry")
	assert(not player.has_hyper_armor(), "armor gone with the attack")
	print(">> TEST 6 PASSED")

	# ---------- TEST 7: обычное оружие без hyper armor прерывается ----------
	print("\n[TEST 7] no hyper armor without the flag")
	_reset()
	player.attack_component.heavy_weapon_data = armored_weapon.duplicate()
	player.attack_component.heavy_weapon_data.hyper_armor = false
	assert(player.cmd_attack() and not player.has_hyper_armor(), "plain attack, no armor")
	var res_plain: Dictionary = player.take_hit(DamageInfo.make(10.0, Vector3.ZERO, dummy))
	assert(res_plain["reacted"] and player.is_staggered, "plain attack is interrupted")
	print(">> TEST 7 PASSED")

	print("\nALL ATTACK FLAGS TESTS PASSED 100%!")
	quit()
