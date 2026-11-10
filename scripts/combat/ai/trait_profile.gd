class_name TraitProfile
extends Resource
## Черта характера: набор эффектов «параметр × множитель». Новая черта = новый .tres в редакторе, без кода.
## Неизменяемый шаблон. Параметр, не упомянутый в эффектах, имеет множитель 1.0.

@export var display_name: String = ""
@export var effects: Array[TraitEffect] = []


## Итоговый множитель черты для параметра (если эффектов на один параметр несколько — перемножаются).
func multiplier_for(key: StringName) -> float:
	var result: float = 1.0
	for e: TraitEffect in effects:
		if e != null and e.param == key:
			result *= e.multiplier
	return result


static func make(name: String, list: Array[TraitEffect]) -> TraitProfile:
	var t := TraitProfile.new()
	t.display_name = name
	t.effects = list
	return t
