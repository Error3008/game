class_name TechniqueHandler
extends RefCounted
## Исполнитель одного вида приёма. Базовый: приём-таймер длительностью data.duration.
## Наследники переопределяют начало/тик/отмену; TechniqueComponent выбирает обработчик по Kind.

var data: TechniqueData = null
var actor: CombatCharacter3D = null
var elapsed: float = 0.0


## Начинает приём. false — не удалось (ничего не списывается).
func begin(a: CombatCharacter3D, d: TechniqueData) -> bool:
	actor = a
	data = d
	elapsed = 0.0
	return true


func process(delta: float) -> void:
	elapsed += delta


func is_finished() -> bool:
	return elapsed >= data.duration


func cancel() -> void:
	pass


## true — актор занят приёмом (стоит, другие действия запрещены).
## false — приём идёт через другой компонент (ударом управляет MeleeAttackComponent).
func owns_actor() -> bool:
	return true
