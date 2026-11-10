class_name AIParams
extends RefCounted
## Реестр параметров ИИ, которыми могут управлять черты характера. Единственное место, где они описаны
## (по аналогии со StatKeys). Он же источник выпадающего списка в TraitEffect.
## Базовые значения НЕ здесь: они остаются в @export контроллера, личность лишь масштабирует их.
## Добавить новый параметр = строка здесь + место в EnemyAIController, где он читается через _p().

const DODGE_CHANCE: StringName = &"dodge_chance"
const BLOCK_CHANCE: StringName = &"block_chance"
const PARRY_CHANCE: StringName = &"parry_chance"
const TACTICAL_BLOCK_CHANCE: StringName = &"tactical_block_chance"
const KICK_CHANCE: StringName = &"kick_chance"                    # пинок по сидящему в блоке
const LIGHT_ATTACK_CHANCE: StringName = &"light_attack_chance"    # лёгкая вместо тяжёлой
const ATTACK_COOLDOWN: StringName = &"attack_cooldown"            # с, масштабирует min и max
const KICK_COOLDOWN: StringName = &"kick_cooldown"                # с, масштабирует min и max
const REACTION_TIME: StringName = &"reaction_time"                # с, масштабирует min и max
const ENGAGE_DIST: StringName = &"engage_dist"                    # м, дистанция вступления в бой
const HEAL_HP_THRESHOLD: StringName = &"heal_hp_threshold"        # доля HP, ниже которой пьёт
const HEAL_SAFE_DISTANCE: StringName = &"heal_safe_distance"      # м, насколько далеко должна быть цель

## key -> Vector2(min, max). Clamp применяется к ИТОГУ в AIPersonality.resolve().
const BOUNDS: Dictionary = {
	DODGE_CHANCE: Vector2(0.0, 1.0),
	BLOCK_CHANCE: Vector2(0.0, 1.0),
	PARRY_CHANCE: Vector2(0.0, 1.0),
	TACTICAL_BLOCK_CHANCE: Vector2(0.0, 1.0),
	KICK_CHANCE: Vector2(0.0, 1.0),
	LIGHT_ATTACK_CHANCE: Vector2(0.0, 1.0),
	ATTACK_COOLDOWN: Vector2(0.8, 8.0),
	KICK_COOLDOWN: Vector2(0.8, 8.0),
	REACTION_TIME: Vector2(0.05, 0.5),
	ENGAGE_DIST: Vector2(2.5, 8.0),
	HEAL_HP_THRESHOLD: Vector2(0.0, 0.9),
	HEAL_SAFE_DISTANCE: Vector2(2.0, 12.0),
}


static func is_known(key: StringName) -> bool:
	return BOUNDS.has(key)


static func all_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for k: StringName in BOUNDS.keys():
		keys.append(k)
	return keys


static func clamp_value(key: StringName, value: float) -> float:
	if not BOUNDS.has(key):
		push_error("AIParams: неизвестный параметр '%s'" % key)
		return value
	var b: Vector2 = BOUNDS[key]
	return clampf(value, b.x, b.y)
