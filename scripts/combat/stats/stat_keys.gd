class_name StatKeys
extends RefCounted
## Реестр ключей статов и их допустимых границ. Единственное место, где ключи описаны.
## Неизвестный ключ в StatBlock = ошибка (push_error), а не молчаливая база.
## Базовые значения НЕ здесь: их регистрируют компоненты в setup() через StatBlock.set_base().

const MOVE_SPEED: StringName = &"move.speed"                    # множитель ко всем скоростям
const MOVE_RUN: StringName = &"move.run"                        # м/с
const MOVE_WALK: StringName = &"move.walk"                      # м/с
const MOVE_COMBAT_WALK: StringName = &"move.combat_walk"        # м/с
const MOVE_COMBAT_STRAFE: StringName = &"move.combat_strafe"    # м/с
const ATTACK_SPEED: StringName = &"attack.speed"                # множитель
const DASH_SPEED: StringName = &"dash.speed"                    # м/с
const DASH_DURATION: StringName = &"dash.duration"              # с
const DASH_COOLDOWN: StringName = &"dash.cooldown"              # с
const DASH_IFRAME_DURATION: StringName = &"dash.iframe_duration"  # с
const DASH_STAMINA_COST: StringName = &"dash.stamina_cost"      # стамина
const PARRY_WINDOW: StringName = &"defense.parry_window"        # с
const BLOCK_STAMINA_COST: StringName = &"defense.block_stamina_cost"  # стамина
const DAMAGE_TAKEN: StringName = &"damage.taken"                # множитель входящего урона
const STAMINA_MAX: StringName = &"stamina.max"
const STAMINA_REGEN: StringName = &"stamina.regen"             # стамина/с
const HEALTH_MAX: StringName = &"health.max"

## key -> Vector2(min, max). Clamp применяется в StatBlock.get_value().
const BOUNDS: Dictionary = {
	MOVE_SPEED: Vector2(0.5, 1.5),
	MOVE_RUN: Vector2(1.0, 10.0),
	MOVE_WALK: Vector2(0.5, 5.0),
	MOVE_COMBAT_WALK: Vector2(0.5, 5.0),
	MOVE_COMBAT_STRAFE: Vector2(0.5, 5.0),
	ATTACK_SPEED: Vector2(0.5, 1.6),
	DASH_SPEED: Vector2(4.0, 14.0),
	DASH_DURATION: Vector2(0.25, 0.6),
	DASH_COOLDOWN: Vector2(0.15, 2.0),
	# max статический. Зависимость от длительности дэша (i-frames не длиннее дэша: ≤ duration − 0.02)
	# обеспечивает сам DashComponent.start_dash() через minf(), а не границы здесь.
	DASH_IFRAME_DURATION: Vector2(0.1, 0.4),
	DASH_STAMINA_COST: Vector2(5.0, 50.0),
	PARRY_WINDOW: Vector2(0.1, 0.4),
	BLOCK_STAMINA_COST: Vector2(5.0, 60.0),
	DAMAGE_TAKEN: Vector2(0.6, 1.5),
	STAMINA_MAX: Vector2(50.0, 200.0),
	STAMINA_REGEN: Vector2(5.0, 60.0),
	HEALTH_MAX: Vector2(50.0, 300.0),
}


static func is_known(key: StringName) -> bool:
	return BOUNDS.has(key)
