class_name CombatFX
extends Node
## Искры и вспышки контакта. Слушает hit_received всех актёров, по исходу удара берёт эффект из пула.
## Эффекты создаются заранее (scenes/fx/*.tscn), на удар ничего не инстанцируется.

const GROUP: StringName = &"combat_fx"

enum Kind { HIT, BLOCK, PARRY, GUARD_BREAK }

@export var enabled: bool = true
@export var pool_size: int = 6  ## на каждый вид
@export var chest_height: float = 1.2  ## точка контакта, если у удара её нет
@export var flash_time: float = 0.12

var scenes: Dictionary = {
	Kind.HIT: preload("res://scenes/fx/hit_sparks.tscn"),
	Kind.BLOCK: preload("res://scenes/fx/block_sparks.tscn"),
	Kind.PARRY: preload("res://scenes/fx/parry_sparks.tscn"),
	Kind.GUARD_BREAK: preload("res://scenes/fx/guard_break_sparks.tscn"),
}

var _pools: Dictionary = {}  ## Kind -> Array[GPUParticles3D]
var _tweens: Dictionary = {}  ## OmniLight3D -> Tween вспышки
var _next: Dictionary = {}  ## Kind -> индекс следующего эффекта


func _ready() -> void:
	add_to_group(GROUP)
	if DisplayServer.get_name() == "headless":
		enabled = false
	for kind: int in scenes:
		var list: Array[GPUParticles3D] = []
		for i in pool_size:
			var fx: GPUParticles3D = (scenes[kind] as PackedScene).instantiate() as GPUParticles3D
			fx.top_level = true
			add_child(fx)
			var flash: OmniLight3D = fx.get_node_or_null("Flash") as OmniLight3D
			if flash != null:
				flash.visible = false
			list.append(fx)
		_pools[kind] = list
		_next[kind] = 0
	for actor: Node in get_tree().root.find_children("*", "CombatCharacter3D", true, false):
		_watch(actor as CombatCharacter3D)
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is CombatCharacter3D:
		_watch(node as CombatCharacter3D)


func _watch(actor: CombatCharacter3D) -> void:
	if not actor.hit_received.is_connected(_on_hit_received):
		actor.hit_received.connect(_on_hit_received.bind(actor))


## Исход удара -> вид эффекта; -1 если показывать нечего.
static func kind_for(result: Dictionary) -> int:
	if result.get("dodged", false):
		return -1
	if result.get("was_parried", false):
		return Kind.PARRY
	if result.get("was_guard_broken", false):
		return Kind.GUARD_BREAK
	if result.get("was_blocked", false):
		return Kind.BLOCK
	if float(result.get("final_damage", 0.0)) > 0.0:
		return Kind.HIT
	return -1


func _on_hit_received(info: DamageInfo, result: Dictionary, victim: CombatCharacter3D) -> void:
	if not enabled:
		return
	var kind: int = kind_for(result)
	if kind < 0:
		return
	var point: Vector3 = victim.global_position + Vector3.UP * chest_height
	if info.has_contact_point:
		point = info.contact_point
	elif is_instance_valid(info.attacker):
		var out: Vector3 = info.attacker.global_position - victim.global_position
		out.y = 0.0
		if out.length_squared() > 0.0001:
			point += out.normalized() * 0.3
	spawn(kind, point)


## Берёт следующий эффект вида kind из пула (по кругу) и запускает в точке.
func spawn(kind: int, point: Vector3) -> GPUParticles3D:
	var list: Array = _pools.get(kind, [])
	if list.is_empty():
		return null
	var idx: int = _next[kind]
	_next[kind] = (idx + 1) % list.size()
	var fx: GPUParticles3D = list[idx]
	fx.global_position = point
	fx.restart()
	var light: OmniLight3D = fx.get_node_or_null("Flash") as OmniLight3D
	if light != null:
		if _tweens.has(light) and (_tweens[light] as Tween).is_valid():
			(_tweens[light] as Tween).kill()
		light.visible = true
		light.light_energy = 6.0 if kind == Kind.PARRY else 8.0
		var tw: Tween = create_tween()
		tw.tween_property(light, "light_energy", 0.0, flash_time)
		tw.tween_callback(func() -> void: light.visible = false)
		_tweens[light] = tw
	return fx
