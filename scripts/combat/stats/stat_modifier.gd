class_name StatModifier
extends Resource
## Шаблон поправки к стату. ТРЕБОВАНИЕ: считать неизменяемым.
## Один .tres делят несколько акторов, поэтому в рантайме поля не менять,
## а источник (source) здесь НЕ хранится: его задаёт StatBlock.add_modifier().

enum Op {
	FLAT,     ## прибавляется к базе: (база + ΣFLAT)
	PERCENT,  ## складывается с другими процентами: × (1 + ΣPERCENT)
	MULT,     ## перемножается: × ΠMULT
}

@export var stat_key: StringName = &""
@export var op: Op = Op.PERCENT
## FLAT — абсолютная величина; PERCENT — доля (0.03 = +3%); MULT — множитель (1.1 = ×1.1).
@export var value: float = 0.0


static func make(key: StringName, operation: Op, amount: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_key = key
	m.op = operation
	m.value = amount
	return m
