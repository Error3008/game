class_name Hitbox
extends Area3D

signal hit_landed(target: Node3D, damage: float)

@export_group("Combat Stats")
@export var damage: float = 20.0
@export var knockback_force: float = 4.0
## Цена блока этого удара в стамине защитника (из WeaponData). -1 = цена блока по умолчанию.
@export var block_stamina_damage: float = -1.0

var damage_type: DamageInfo.DamageType = DamageInfo.DamageType.PHYSICAL
var unblockable: bool = false
var unparryable: bool = false
var break_damage: float = 0.0

## Метка источника для DamageInfo.source (&"heavy", &"light"); MeleeAttackComponent выставляет по типу атаки.
var damage_source: StringName = &"heavy"

@export_group("Debug")
@export var debug_visual: bool = true

var attacker: Node3D = null
var is_active: bool = false
var hit_targets: Array[Node3D] = []

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var debug_mesh: MeshInstance3D = get_node_or_null("DebugMesh")


func _ready() -> void:
	# Disabled by default until active attack frames
	set_active(false)
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func set_active(active: bool) -> void:
	is_active = active
	set_deferred("monitoring", active)
	set_deferred("monitorable", active)
	if is_instance_valid(collision_shape):
		collision_shape.set_deferred("disabled", not active)
	if is_instance_valid(debug_mesh):
		debug_mesh.visible = active and debug_visual
	if active:
		hit_targets.clear()


func _calculate_knockback_direction(target_node: Node3D) -> Vector3:
	var default_dir := Vector3.FORWARD
	if is_instance_valid(attacker):
		var facing: Vector3 = attacker.get_facing_direction() if attacker.has_method("get_facing_direction") else attacker.global_transform.basis.z
		facing.y = 0.0
		if facing.length_squared() > 0.001:
			facing = facing.normalized()
		else:
			facing = Vector3.FORWARD

		var to_target := (target_node.global_position - attacker.global_position)
		to_target.y = 0.0

		# If target is sufficiently in front, push away from attacker; if overlapping or behind, push forward along blade swing
		if to_target.length_squared() > 0.09 and to_target.normalized().dot(facing) > 0.2:
			return to_target.normalized()
		return facing
	return default_dir


## Собирает DamageInfo и отдаёт цели (take_hit, иначе take_damage). false — у цели нет приёмника урона.
func _deal(receiver: Object, knockback_dir: Vector3) -> bool:
	if receiver.has_method("take_hit"):
		receiver.take_hit(_build_damage_info(knockback_dir, receiver as Node3D))
		return true
	if receiver.has_method("take_damage"):
		receiver.take_damage(damage, knockback_dir * knockback_force, attacker, block_stamina_damage)
		return true
	return false


## Копирует параметры удара из оружия.
func apply_weapon(w: WeaponData) -> void:
	damage = w.damage
	knockback_force = w.knockback_force
	block_stamina_damage = w.block_stamina_damage
	damage_type = w.damage_type
	unblockable = w.unblockable
	unparryable = w.unparryable
	break_damage = w.break_damage


func _build_damage_info(knockback_dir: Vector3, target: Node3D = null) -> DamageInfo:
	var info := DamageInfo.make(damage, knockback_dir * knockback_force, attacker, damage_source, block_stamina_damage)
	info.damage_type = damage_type
	info.unblockable = unblockable
	info.unparryable = unparryable
	info.break_damage = break_damage
	if target != null:
		info.contact_point = _contact_point(target)
		info.has_contact_point = true
	return info


## Точка, где клинок прошёл ближе всего к оси цели, вынесенная на её переднюю поверхность.
## Позиция самого хитбокса не годится: это рукоять в ладони атакующего.
func _contact_point(target: Node3D) -> Vector3:
	var capsule: CapsuleShape3D = collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return global_position
	var half: float = capsule.height * 0.5
	var blade_a: Vector3 = collision_shape.global_transform * Vector3(0.0, -half, 0.0)
	var blade_b: Vector3 = collision_shape.global_transform * Vector3(0.0, half, 0.0)
	var base: Vector3 = target.global_position
	var closest: PackedVector3Array = Geometry3D.get_closest_points_between_segments(
		blade_a, blade_b, base + Vector3.UP * 0.4, base + Vector3.UP * 1.6)
	var to_attacker: Vector3 = (attacker.global_position if is_instance_valid(attacker) else blade_a) - base
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.0001:
		return closest[1]
	return closest[1] + to_attacker.normalized() * 0.3


func _on_body_entered(body: Node3D) -> void:
	if not is_active:
		return
	if body == attacker or body in hit_targets:
		return

	hit_targets.append(body)
	var knockback_dir := _calculate_knockback_direction(body)

	print("[Hitbox] Hit landed on: ", body.name, " (Damage: ", damage, ")")
	_deal(body, knockback_dir)
	hit_landed.emit(body, damage)


func _on_area_entered(area: Area3D) -> void:
	if not is_active:
		return
	var owner_node: Node3D = area.get_parent() as Node3D
	if owner_node != null and owner_node != attacker and not (owner_node in hit_targets):
		hit_targets.append(owner_node)
		var knockback_dir := _calculate_knockback_direction(owner_node)

		print("[Hitbox] Hit landed on hurtbox: ", area.name, " belonging to ", owner_node.name)
		if not _deal(area, knockback_dir):
			_deal(owner_node, knockback_dir)
		hit_landed.emit(owner_node, damage)
