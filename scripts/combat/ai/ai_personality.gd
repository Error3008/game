class_name AIPersonality
extends Resource
## Характер ИИ: веса черт. Итог по параметру = база × Σ(вес × множитель черты) / Σ(вес), затем clamp по AIParams.
## Без черт (или с нулевой суммой весов) возвращает базу без изменений.
## Ресурс общий для инстансов: в рантайме не менять; для вариаций использовать randomized().

@export var display_name: String = ""
## Черта -> вес (любое неотрицательное число; нормируется при расчёте).
@export var traits: Dictionary[TraitProfile, float] = {}


func total_weight() -> float:
	var sum: float = 0.0
	for t: TraitProfile in traits:
		if t != null:
			sum += maxf(0.0, traits[t])
	return sum


## Множитель для параметра (без базы и clamp), 1.0 если черт нет.
func multiplier_for(key: StringName) -> float:
	var total: float = total_weight()
	if total <= 0.0:
		return 1.0
	var acc: float = 0.0
	for t: TraitProfile in traits:
		if t != null:
			acc += maxf(0.0, traits[t]) * t.multiplier_for(key)
	return acc / total


func resolve(key: StringName, base: float) -> float:
	return AIParams.clamp_value(key, base * multiplier_for(key))


## Копия с веса́ми, случайно сдвинутыми на ±spread от каждого (в долях веса, например 0.3 = ±30%).
func randomized(spread: float, rng: RandomNumberGenerator = null) -> AIPersonality:
	var r: RandomNumberGenerator = rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var copy := AIPersonality.new()
	copy.display_name = display_name
	for t: TraitProfile in traits:
		if t != null:
			var w: float = maxf(0.0, traits[t])
			copy.traits[t] = maxf(0.0, w * (1.0 + r.randf_range(-spread, spread)))
	return copy
