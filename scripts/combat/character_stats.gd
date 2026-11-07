class_name CharacterStats
extends Resource

@export_group("Health")
@export var max_health: float = 100.0

@export_group("Movement Speeds")
@export var walk_speed: float = 2.5
@export var run_speed: float = 5.0
@export var combat_walk_speed: float = 2.4
@export var combat_strafe_speed: float = 2.0

@export_group("Acceleration & Deceleration")
@export var accel: float = 10.0
@export var decel: float = 12.0
@export var combat_accel: float = 8.0

@export_group("Rotation & Blending")
@export var rotation_speed: float = 10.0
@export var lerp_angle_weight_scale: float = 10.0
@export var combat_rotation_speed: float = 12.0
@export var combat_mode_blend_speed: float = 6.0
@export var combat_movement_blend_speed: float = 8.0
@export var locomotion_blend_speed: float = 8.0
@export var anim_speed_multiplier: float = 1.0

@export_group("Stamina")
@export var enable_stamina: bool = true
@export var max_stamina: float = 100.0
@export var stamina_regen_rate: float = 25.0
@export var stamina_regen_delay: float = 0.8
@export_range(0.0, 1.0) var block_regen_multiplier: float = 0.25
@export var block_impact_stamina_cost: float = 35.0
@export var parry_bonus_stamina: float = 15.0
@export var parry_attempt_stamina_cost: float = 0.0
@export var guard_break_stagger_duration: float = 1.5

@export_group("Healing")
@export var heal_charges: int = 3
@export var heal_amount: float = 40.0

@export_group("Reactions")
## Сколько секунд получатель не может действовать после чистого попадания (клип Hit_React ~0.5 с).
@export var hit_react_stun_duration: float = 0.35
