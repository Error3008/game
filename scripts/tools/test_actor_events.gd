extends SceneTree
## Задача 1.4: события актора. Сценарий «удар → блок → парирование → пинок».

var player: Player
var dummy: Enemy
var log: Array = []


func _init() -> void:
	_run_tests()


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
		a.defense_component.end_block()
		a.dash_component.is_dashing = false
		a.is_staggered = false
		a.stagger_timer = 0.0
		a.velocity = Vector3.ZERO
	log.clear()


## Подписка: каждое событие пишет в журнал строку «кто:событие» и аргументы.
func _watch(actor: CombatCharacter3D, who: String) -> void:
	actor.action_started.connect(func(a: StringName, d: Variant) -> void: log.append([who, &"action_started", a, d]))
	actor.hit_received.connect(func(i: DamageInfo, r: Dictionary) -> void: log.append([who, &"hit_received", i, r]))
	actor.hit_dealt.connect(func(t: Node3D, i: DamageInfo, r: Dictionary) -> void: log.append([who, &"hit_dealt", t, i, r]))
	actor.staggered.connect(func(d: float, s: Node3D) -> void: log.append([who, &"staggered", d, s]))
	actor.attack_phase_changed.connect(func(p: StringName) -> void: log.append([who, &"attack_phase_changed", p]))


## Журнал в виде «кто:событие[:деталь]» для проверки порядка.
func _names() -> Array:
	var out: Array = []
	for e: Array in log:
		var n := "%s:%s" % [e[0], e[1]]
		if e[1] == &"action_started" or e[1] == &"attack_phase_changed":
			n += ":%s" % e[2]
		out.append(n)
	return out


func _run_tests() -> void:
	print("--- STARTING ACTOR EVENTS TESTS ---")
	var scene: Node = (load("res://scenes/test_player.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	player = scene.get_node("Player") as Player
	dummy = scene.get_node("ObstacleRooms/Room2_LeftWall/Dummy_LeftWall") as Enemy
	assert(player != null and dummy != null, "Player and dummy must exist")
	_freeze(player)
	_freeze(dummy)
	player.global_position = Vector3(0.0, 0.0, 0.0)
	dummy.global_position = Vector3(0.0, 0.0, -1.5)
	player.pawn.rotation.y = atan2(dummy.global_position.x - player.global_position.x, dummy.global_position.z - player.global_position.z)
	dummy.pawn.rotation.y = atan2(player.global_position.x - dummy.global_position.x, player.global_position.z - dummy.global_position.z)
	_watch(player, "P")
	_watch(dummy, "D")

	# ---------- TEST 1: удар (фазы атаки + попадание) ----------
	print("\n[TEST 1] attack: action, phases, hit")
	_reset()
	var weapon: WeaponData = player.attack_component.heavy_weapon_data
	assert(player.cmd_attack(), "attack starts")
	assert(_names() == ["P:action_started:attack_heavy", "P:attack_phase_changed:windup"] or _names() == ["P:attack_phase_changed:windup", "P:action_started:attack_heavy"], "start events: %s" % [_names()])
	assert(log.filter(func(e: Array) -> bool: return e[1] == &"action_started")[0][3] == weapon, "action data is the weapon")
	player.attack_component.process_attack(weapon.windup_time + 0.01)
	player.attack_component.process_attack(0.01)
	assert(player.attack_component.phase == &"active", "active phase")
	var hit := DamageInfo.make(weapon.damage, Vector3(2, 0, 0), player, &"heavy", weapon.block_stamina_damage)
	var res_hit: Dictionary = dummy.take_hit(hit)
	player.attack_component.process_attack(weapon.active_end_time)
	player.attack_component.process_attack(weapon.total_duration)
	var names := _names()
	var wanted_tail := ["D:hit_received", "P:hit_dealt", "P:attack_phase_changed:recovery", "P:attack_phase_changed:idle"]
	assert(names.slice(names.size() - 4) == wanted_tail, "order: %s" % [names])
	assert(names.count("P:attack_phase_changed:active") == 1, "active once")
	var recv: Array = log.filter(func(e: Array) -> bool: return e[1] == &"hit_received")[0]
	var dealt: Array = log.filter(func(e: Array) -> bool: return e[1] == &"hit_dealt")[0]
	assert(recv[2] == hit and recv[3] == res_hit and not res_hit["was_blocked"], "hit_received carries info and result")
	assert(dealt[2] == dummy and dealt[3] == hit and dealt[4] == res_hit, "hit_dealt carries target, info, result")
	print(">> TEST 1 PASSED")

	# ---------- TEST 2: блок ----------
	print("\n[TEST 2] block")
	_reset()
	assert(dummy.cmd_block_start(), "dummy blocks")
	var blk: DamageInfo = DamageInfo.make(20.0, Vector3(2, 0, 0), player, &"heavy", 35.0)
	dummy.take_hit(blk)
	assert(_names() == ["D:action_started:block", "D:hit_received", "P:hit_dealt"], "block order: %s" % [_names()])
	assert(log[1][3]["was_blocked"] and not log[1][3]["was_parried"], "result says blocked")
	print(">> TEST 2 PASSED")

	# ---------- TEST 3: парирование ----------
	print("\n[TEST 3] parry staggers attacker")
	_reset()
	assert(dummy.cmd_block_start(), "dummy blocks")
	assert(dummy.cmd_parry(), "parry window")
	var par: DamageInfo = DamageInfo.make(40.0, Vector3(4, 0, 0), player, &"heavy", 35.0)
	assert(player.cmd_attack(), "player swings")
	log.clear()
	var res_par: Dictionary = dummy.take_hit(par)
	assert(res_par["was_parried"], "parried")
	assert(_names() == ["P:attack_phase_changed:idle", "P:staggered", "D:hit_received", "P:hit_dealt"], "parry order: %s" % [_names()])
	var stg: Array = log[1]
	assert(absf(stg[2] - 0.8) < 0.01 and stg[3] == dummy, "stagger duration and source")
	assert(log[2][3]["was_parried"], "hit_received says parried")
	print(">> TEST 3 PASSED")

	# ---------- TEST 4: пинок ----------
	print("\n[TEST 4] kick")
	_reset()
	assert(player.cmd_kick(), "kick starts")
	assert(_names() == ["P:action_started:kick"], "kick action: %s" % [_names()])
	player.kick_component.cancel_kick()
	_reset()
	var kick_info := DamageInfo.make(10.0, Vector3.ZERO, player, &"kick")
	dummy.take_hit(kick_info)
	assert(_names() == ["D:hit_received", "P:hit_dealt"] and log[0][2].source == &"kick", "kick hit: %s" % [_names()])
	print(">> TEST 4 PASSED")

	# ---------- TEST 5: запрещённая команда и прочие действия ----------
	print("\n[TEST 5] refused commands emit nothing, dash and heal emit")
	_reset()
	player.is_staggered = true
	assert(not player.cmd_attack() and not player.cmd_kick() and not player.cmd_block_start() and not player.cmd_heal(), "all refused in stagger")
	assert(log.is_empty(), "no events: %s" % [_names()])
	player.is_staggered = false
	player.health_component.current_health = 50.0
	assert(player.cmd_heal(), "heal starts")
	assert(_names() == ["P:action_started:heal"], "heal action")
	player.heal_component.cancel_heal()
	_reset()
	assert(player.cmd_dash(DashComponent.DashDirection.LEFT), "dash starts")
	assert(_names() == ["P:action_started:dash"] and log[0][3] == DashComponent.DashDirection.LEFT, "dash carries direction")
	print(">> TEST 5 PASSED")

	# ---------- TEST 6: мёртвая цель молчит ----------
	print("\n[TEST 6] dead target emits no hit events")
	_reset()
	dummy.health_component.take_damage(9999.0, player)
	log.clear()
	dummy.take_hit(DamageInfo.make(5.0, Vector3.ZERO, player))
	assert(log.is_empty(), "no events for dead target")
	print(">> TEST 6 PASSED")

	print("\nALL ACTOR EVENTS TESTS PASSED 100%!")
	quit()
