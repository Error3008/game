class_name StatBlock
extends Node
## Хранит базы и модификаторы статов актора, отдаёт итоговые значения.
## Формула: clamp((база + ΣFLAT) × max(0, 1 + ΣPERCENT) × ΠMULT, min, max).
## Базы регистрируют сами компоненты в setup() (set_base), читатели берут get_value(key) без базы.

signal stats_changed

var _bases: Dictionary = {}  # StringName -> float
var _entries: Array[Dictionary] = []  # {mod: StatModifier, source: StringName}
var _cache: Dictionary = {}  # StringName -> float, итоговые значения (лениво, сбрасывается целиком)


func set_base(key: StringName, value: float) -> void:
	if not StatKeys.is_known(key):
		push_error("StatBlock.set_base: unknown stat key '%s'" % key)
		return
	_bases[key] = value
	_invalidate()


func has_base(key: StringName) -> bool:
	return _bases.has(key)


## База без модификаторов. Как и get_value, шумит при неизвестном ключе или отсутствии базы,
## чтобы не получить тихий 0.0 (например, деление на ноль в анимации).
func get_base(key: StringName) -> float:
	if not StatKeys.is_known(key):
		push_error("StatBlock.get_base: unknown stat key '%s'" % key)
		return 0.0
	if not _bases.has(key):
		push_error("StatBlock.get_base: no base registered for '%s'" % key)
		return 0.0
	return _bases[key]


## Добавляет модификатор от источника. Один шаблон можно добавлять разным акторам.
func add_modifier(mod: StatModifier, source: StringName) -> void:
	if mod == null:
		return
	if not StatKeys.is_known(mod.stat_key):
		push_error("StatBlock.add_modifier: unknown stat key '%s' (source '%s')" % [mod.stat_key, source])
		return
	_entries.append({"mod": mod, "source": source})
	_invalidate()


## Снимает все модификаторы источника (для повторного пересчёта без дублей).
func remove_source(source: StringName) -> void:
	var kept: Array[Dictionary] = []
	for e: Dictionary in _entries:
		if e["source"] != source:
			kept.append(e)
	if kept.size() != _entries.size():
		_entries = kept
		_invalidate()


## Итоговое значение. Кэшируется лениво: первый вызов после любого изменения считает по
## формуле, следующие читают из _cache за O(1). Любое изменение баз/модификаторов сбрасывает
## весь кэш (см. _invalidate), поэтому setup() с десятками set_base ничего не пересчитывает.
func get_value(key: StringName) -> float:
	var cached: Variant = _cache.get(key)
	if cached != null:
		return cached
	if not StatKeys.is_known(key):
		push_error("StatBlock.get_value: unknown stat key '%s'" % key)
		return 0.0
	if not _bases.has(key):
		push_error("StatBlock.get_value: no base registered for '%s'" % key)
		return 0.0

	var flat: float = 0.0
	var percent: float = 0.0
	var mult: float = 1.0
	for e: Dictionary in _entries:
		var m: StatModifier = e["mod"]
		if m.stat_key != key:
			continue
		match m.op:
			StatModifier.Op.FLAT:
				flat += m.value
			StatModifier.Op.PERCENT:
				percent += m.value
			StatModifier.Op.MULT:
				mult *= m.value

	var result: float = (float(_bases[key]) + flat) * maxf(0.0, 1.0 + percent) * mult
	var bounds: Vector2 = StatKeys.BOUNDS[key]
	var final_value: float = clampf(result, bounds.x, bounds.y)
	_cache[key] = final_value
	return final_value


func _invalidate() -> void:
	_cache.clear()
	stats_changed.emit()
