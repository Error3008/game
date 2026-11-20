class_name TechniqueLoadout
extends RefCounted
## Debug-лоадаут лаборатории: все приёмы из resources/techniques/*.tres.
## Новый приём = новый .tres в этой папке, код менять не нужно.

const DIR: String = "res://resources/techniques"


static func load_all() -> Array[TechniqueData]:
	var out: Array[TechniqueData] = []
	var names: PackedStringArray = ResourceLoader.list_directory(DIR) if DirAccess.dir_exists_absolute(DIR) else PackedStringArray()
	names.sort()
	for file_name in names:
		var file := file_name.trim_suffix(".remap")
		if file.ends_with(".tres"):
			var data := load("%s/%s" % [DIR, file]) as TechniqueData
			if data != null:
				out.append(data)
	return out


## Экипирует все приёмы; самостоятельные (TRIGGER_SLOT) раскладывает по слотам 1–4.
static func give(actor: CombatCharacter3D, list: Array[TechniqueData]) -> void:
	var tc: TechniqueComponent = actor.technique_component
	if tc == null:
		return
	for i in TechniqueComponent.SLOT_COUNT:
		tc.bind_slot(i, &"")
	var slot := 0
	for data in list:
		tc.equip(data)
		if data.trigger == TechniqueData.TRIGGER_SLOT and slot < TechniqueComponent.SLOT_COUNT:
			tc.bind_slot(slot, data.id)
			slot += 1
