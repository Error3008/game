class_name SchoolData
extends Resource
## Школа: набор приёмов и родные статы. Дерево приёмов появится в этапе 6, пока плоский список.

@export var id: StringName = &""
@export var display_name: String = ""
## Ключи родных статов (силa, ловкость и т.д.): дают синергии, не ограничения.
@export var native_stats: Array[StringName] = []
@export var techniques: Array[TechniqueData] = []
