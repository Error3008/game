class_name TechniqueData
extends Resource
## Описание приёма школы. Данные, не логика: исполняет TechniqueComponent.
## Приёмы общие для игрока и врагов (универсальный арсенал).

enum Kind {
	ATTACK_VARIANT, ## вариант базовой атаки: исполняет MeleeAttackComponent с другим WeaponData
	COMBO,          ## серия ударов
	BLOCK_ACTION,   ## действие из блока (Отбив)
	PARRY_FOLLOWUP, ## ответ после удачного парирования (Контрудар)
	FEINT,          ## отменяемый замах
	BUFF,           ## усиление следующих ударов
}

## Стабильный английский id (`crush`, `flurry`, `repel`, ...). Код ссылается только на него.
@export var id: StringName = &""
## Рабочее русское название; меняется без правки кода.
@export var display_name: String = ""
## id школы (`onslaught`, `stance`, `tricks`).
@export var school: StringName = &""
@export var kind: Kind = Kind.ATTACK_VARIANT
## Как вызывается: контекстно (`heavy_hold`, `light_chain`, ...) или слотом (`slot`). Правила ввода — задача 1.7.
@export var trigger: StringName = &"slot"
## Удары приёма. Для ATTACK_VARIANT берётся первый; стамину за него списывает сам удар (WeaponData.stamina_cost).
@export var attacks: Array[WeaponData] = []
## Стамина приёма. Для ATTACK_VARIANT не используется (цена в WeaponData).
@export var stamina_cost: float = 0.0
@export var focus_cost: float = 0.0
## Откат в секундах, отсчитывается от старта приёма.
@export var cooldown: float = 0.0
## Длительность приёма без собственного удара (BLOCK_ACTION, BUFF и др.), пока нет анимаций.
@export var duration: float = 0.5
## Метка телеграфа для FX и ИИ (этап 2).
@export var telegraph: StringName = &""
