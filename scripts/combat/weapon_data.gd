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
## Сколько стамины у защитника отнимает блок этого удара (до скидок билда). 35 = базовая цена блока.
## Скидка брони пропорциональна: цена = stat(defense.block_stamina_cost) × block_stamina_damage / 35.
@export var block_stamina_damage: float = 35.0

@export_group("Attack Flags")
## Тип урона удара (броня режет только физический).
@export var damage_type: DamageInfo.DamageType = DamageInfo.DamageType.PHYSICAL
## Проходит сквозь блок и парирование (красный телеграф: только уходить).
@export var unblockable: bool = false
## Парировать нельзя, только блокировать.
@export var unparryable: bool = false
## Защита от прерывания с начала замаха до конца активной фазы: чужое попадание не вызывает hit-react,
## нокбэк ×0.3. Парирование всё равно сбивает.
@export var hyper_armor: bool = false
## Вклад в шкалу слома (этап 5).
@export var break_damage: float = 0.0
## Метка телеграфа для FX и ИИ (этап 2): &"" = обычный удар.
@export var telegraph: StringName = &""
