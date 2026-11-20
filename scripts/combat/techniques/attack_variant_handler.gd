class_name AttackVariantHandler
extends TechniqueHandler
## Приём как вариант атаки: тот же MeleeAttackComponent, другой WeaponData.

var _started: bool = false


func begin(a: CombatCharacter3D, d: TechniqueData) -> bool:
	if d.attacks.is_empty() or d.attacks[0] == null or not is_instance_valid(a.attack_component):
		return false
	super.begin(a, d)
	_started = a.attack_component.start_attack(false, d.attacks[0])
	return _started


func process(_delta: float) -> void:
	pass


func is_finished() -> bool:
	return not is_instance_valid(actor) or not actor.is_attacking


func cancel() -> void:
	if _started and is_instance_valid(actor) and actor.is_attacking:
		actor.attack_component.cancel_attack()


func owns_actor() -> bool:
	return false
