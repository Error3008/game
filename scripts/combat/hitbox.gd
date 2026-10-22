class_name Hitbox
extends Area3D

signal hit_landed(target: Node3D, damage: float)

@export_group("Combat Stats")
@export var damage: float = 20.0
@export var knockback_force: float = 4.0

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


func _on_body_entered(body: Node3D) -> void:
	if not is_active:
		return
	if body == attacker or body in hit_targets:
		return

	hit_targets.append(body)
	var knockback_dir := _calculate_knockback_direction(body)

	print("[Hitbox] Hit landed on: ", body.name, " (Damage: ", damage, ")")
	if body.has_method("take_damage"):
		body.take_damage(damage, knockback_dir * knockback_force, attacker)
	hit_landed.emit(body, damage)


func _on_area_entered(area: Area3D) -> void:
	if not is_active:
		return
	var owner_node: Node3D = area.get_parent() as Node3D
	if owner_node != null and owner_node != attacker and not (owner_node in hit_targets):
		hit_targets.append(owner_node)
		var knockback_dir := _calculate_knockback_direction(owner_node)

		print("[Hitbox] Hit landed on hurtbox: ", area.name, " belonging to ", owner_node.name)
		if area.has_method("take_damage"):
			area.take_damage(damage, knockback_dir * knockback_force, attacker)
		elif owner_node.has_method("take_damage"):
			owner_node.take_damage(damage, knockback_dir * knockback_force, attacker)
		hit_landed.emit(owner_node, damage)
