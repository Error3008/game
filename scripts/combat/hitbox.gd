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
	monitoring = active
	monitorable = active
	if is_instance_valid(collision_shape):
		collision_shape.disabled = not active
	if is_instance_valid(debug_mesh):
		debug_mesh.visible = active and debug_visual
	if active:
		hit_targets.clear()


func _on_body_entered(body: Node3D) -> void:
	if not is_active:
		return
	if body == attacker or body in hit_targets:
		return

	hit_targets.append(body)
	var knockback_dir: Vector3 = Vector3.FORWARD
	if is_instance_valid(attacker):
		knockback_dir = (body.global_position - attacker.global_position)
		knockback_dir.y = 0.0
		if knockback_dir.length_squared() > 0.001:
			knockback_dir = knockback_dir.normalized()
		else:
			knockback_dir = attacker.global_transform.basis.z

	print("[Hitbox] Hit landed on: ", body.name, " (Damage: ", damage, ")")
	if body.has_method("take_damage"):
		body.take_damage(damage, knockback_dir * knockback_force, attacker)
	hit_landed.emit(body, damage)


func _on_area_entered(area: Area3D) -> void:
	if not is_active:
		return
	var owner_node: Node3D = area.get_parent() as Node3D
	if owner_node != null and owner_node != attacker and not (owner_node in hit_targets):
		if area.has_method("take_damage"):
			hit_targets.append(owner_node)
			var knockback_dir: Vector3 = (owner_node.global_position - global_position).normalized()
			print("[Hitbox] Hit landed on hurtbox: ", area.name, " belonging to ", owner_node.name)
			area.take_damage(damage, knockback_dir * knockback_force, attacker)
			hit_landed.emit(owner_node, damage)
