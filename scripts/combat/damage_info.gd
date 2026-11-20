class_name DamageInfo
extends RefCounted
## Описание одного удара. Передаётся в CombatCharacter3D.take_hit() и DefenseComponent.evaluate_hit().
## Расширяется флагами без изменения сигнатур (неблокируемые удары, магия, приёмы школ).

enum DamageType { PHYSICAL, MAGIC }

var amount: float = 0.0
var knockback: Vector3 = Vector3.ZERO
var attacker: Node3D = null
var damage_type: DamageType = DamageType.PHYSICAL
## Проходит сквозь блок и парирование (логика в задаче 1.3).
var unblockable: bool = false
## Парировать нельзя, можно только блокировать (логика в задаче 1.3).
var unparryable: bool = false
## false — удар не запускает hit-react (например, горение).
var causes_hit_react: bool = true
## Вклад в шкалу слома (этап 5). Пока не используется.
var break_damage: float = 0.0
## Цена блока этого удара в стамине защитника (WeaponData.block_stamina_damage). -1 = базовая цена блока.
var block_stamina: float = -1.0
## Откуда удар: &"heavy", &"light", &"kick", &"burn", &"direct", позже id приёмов.
var source: StringName = &"direct"
## Мировая точка контакта (для FX). Заполняет Hitbox; без неё FX берёт грудь цели.
var contact_point: Vector3 = Vector3.ZERO
var has_contact_point: bool = false


static func make(p_amount: float, p_knockback: Vector3, p_attacker: Node3D = null, p_source: StringName = &"direct", p_block_stamina: float = -1.0) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = p_amount
	info.knockback = p_knockback
	info.attacker = p_attacker
	info.source = p_source
	info.block_stamina = p_block_stamina
	return info
