class_name Player
extends CombatCharacter3D

@onready var controller: PlayerController = get_node_or_null("PlayerController")
@onready var spring_arm_pivot: Node3D = get_node_or_null("SpringArmPivot")

# Lock-on state forwarding for camera_spring_arm and external queries
var is_lock_enabled: bool:
	get:
		return controller.is_lock_enabled if is_instance_valid(controller) else false
	set(val):
		if is_instance_valid(controller):
			controller.is_lock_enabled = val


func _ready() -> void:
	hitbox_target_mask = 4 # Scans enemies (collision layer 4)

	if stats == null:
		stats = preload("res://resources/stats/player_stats.tres")

	# Ensure components exist
	if not has_node("DefenseComponent"):
		var def := DefenseComponent.new()
		def.name = "DefenseComponent"
		add_child(def)
	if not has_node("MeleeAttackComponent"):
		var atk := MeleeAttackComponent.new()
		atk.name = "MeleeAttackComponent"
		atk.weapon_data = preload("res://resources/weapons/greatsword.tres")
		add_child(atk)
	if not has_node("DashComponent"):
		var dsh := DashComponent.new()
		dsh.name = "DashComponent"
		add_child(dsh)
	if not has_node("PlayerController"):
		var ctrl := PlayerController.new()
		ctrl.name = "PlayerController"
		add_child(ctrl)

	super._ready()
