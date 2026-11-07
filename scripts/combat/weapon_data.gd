class_name WeaponData
extends Resource

@export_group("Weapon Identity")
@export var weapon_name: String = "Greatsword"

@export_group("Damage & Force")
@export var damage: float = 35.0
@export var knockback_force: float = 4.0

@export_group("Timing & Animation")
@export var action_anim_name: StringName = &"heavy_attack"
@export var windup_time: float = 0.54
@export var active_end_time: float = 0.71
@export var total_duration: float = 1.40
@export var lunge_speed: float = 2.2

@export_group("Stamina")
@export var stamina_cost: float = 20.0
