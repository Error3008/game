class_name AttributeRules
extends Resource
## Превращает атрибуты билда (armor, agility) в модификаторы StatBlock.
## Все коэффициенты билдов в одном месте; значения «на уровень» правятся на глаз в инспекторе.
## PERCENT-значения — доли (0.04 = 4%), FLAT — абсолютные поправки к базе.

const SOURCE: StringName = &"attributes"

@export_group("Armor (за уровень)")
@export var armor_damage_taken: float = -0.04      # PERCENT: входящий урон
@export var armor_parry_window: float = 0.015      # FLAT, с: окно парирования
@export var armor_block_stamina_cost: float = -2.0 # FLAT: цена блока в стамине
@export var armor_move_speed: float = -0.02        # PERCENT: цена брони — все скорости
@export var armor_attack_speed: float = -0.02      # PERCENT: цена брони — скорость удара

@export_group("Agility (за уровень)")
@export var agility_attack_speed: float = 0.03     # PERCENT
@export var agility_dash_speed: float = 0.03       # PERCENT
@export var agility_dash_iframe: float = 0.01      # FLAT, с
@export var agility_dash_cooldown: float = -0.02   # FLAT, с
@export var agility_dash_stamina_cost: float = -0.5 # FLAT
@export var agility_damage_taken: float = 0.02     # PERCENT: цена ловкости — хрупкость


## Снимает старые модификаторы источника &"attributes" и добавляет новые (повторный вызов не дублирует).
## По одному модификатору на (ключ, операция); нулевые не добавляются.
func apply(block: StatBlock, armor: int, agility: int) -> void:
	block.remove_source(SOURCE)
	var a: float = float(clampi(armor, 0, 10))
	var g: float = float(clampi(agility, 0, 10))
	var P := StatModifier.Op.PERCENT
	var F := StatModifier.Op.FLAT

	# (ключ, операция) -> суммарное значение
	var sums: Dictionary = {}
	_add(sums, StatKeys.DAMAGE_TAKEN, P, armor_damage_taken * a + agility_damage_taken * g)
	_add(sums, StatKeys.PARRY_WINDOW, F, armor_parry_window * a)
	_add(sums, StatKeys.BLOCK_STAMINA_COST, F, armor_block_stamina_cost * a)
	_add(sums, StatKeys.MOVE_SPEED, P, armor_move_speed * a)
	_add(sums, StatKeys.ATTACK_SPEED, P, armor_attack_speed * a + agility_attack_speed * g)
	_add(sums, StatKeys.DASH_SPEED, P, agility_dash_speed * g)
	_add(sums, StatKeys.DASH_IFRAME_DURATION, F, agility_dash_iframe * g)
	_add(sums, StatKeys.DASH_COOLDOWN, F, agility_dash_cooldown * g)
	_add(sums, StatKeys.DASH_STAMINA_COST, F, agility_dash_stamina_cost * g)

	for entry: Array in sums.values():
		var amount: float = entry[2]
		if is_zero_approx(amount):
			continue
		block.add_modifier(StatModifier.make(entry[0], entry[1], amount), SOURCE)


func _add(sums: Dictionary, key: StringName, op: StatModifier.Op, amount: float) -> void:
	var id: String = "%s|%d" % [key, op]
	if sums.has(id):
		sums[id][2] += amount
	else:
		sums[id] = [key, op, amount]
