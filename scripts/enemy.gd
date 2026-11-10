class_name Enemy
extends CombatCharacter3D

@onready var ai_controller: EnemyAIController = get_node_or_null("EnemyAIController")

enum Team {
	HOSTILE, ## обычный враг: слой 4, бьёт по игроку (слой 2)
	ALLY,    ## бот на стороне игрока (дуэли ботов): слой 2, группа "ally", бьёт по врагам (слой 4)
}

@export var team: Team = Team.HOSTILE

## Характер ИИ этого врага (передаётся контроллеру в _ready). null = базовые параметры контроллера.
@export var personality: AIPersonality = null

var _is_dummy: bool = false
var _dummy_can_attack: bool = false
var _dummy_always_block: bool = false
var _can_dodge: bool = true
var _dodge_chance: float = 0.50
var _reaction_time_min: float = 0.10
var _reaction_time_max: float = 0.22
var _can_block: bool = true
var _block_chance: float = 0.50
var _parry_chance: float = 0.25
var _tactical_block_chance: float = 0.35
var _can_kick: bool = true
var _kick_chance_on_blocking_player: float = 0.70

@export_group("Dummy Training")
@export var is_dummy: bool = false:
	get:
		return ai_controller.is_dummy if is_instance_valid(ai_controller) else _is_dummy
	set(val):
		_is_dummy = val
		if is_instance_valid(ai_controller):
			ai_controller.is_dummy = val

@export var dummy_can_attack: bool = false:
	get:
		return ai_controller.dummy_can_attack if is_instance_valid(ai_controller) else _dummy_can_attack
	set(val):
		_dummy_can_attack = val
		if is_instance_valid(ai_controller):
			ai_controller.dummy_can_attack = val

@export var dummy_always_block: bool = false:
	get:
		return ai_controller.dummy_always_block if is_instance_valid(ai_controller) else _dummy_always_block
	set(val):
		_dummy_always_block = val
		if is_instance_valid(ai_controller):
			ai_controller.dummy_always_block = val

@export_group("Combat Dodge")
@export var can_dodge: bool = true:
	get:
		return ai_controller.can_dodge if is_instance_valid(ai_controller) else _can_dodge
	set(val):
		_can_dodge = val
		if is_instance_valid(ai_controller):
			ai_controller.can_dodge = val

@export_range(0.0, 1.0, 0.05) var dodge_chance: float = 0.50:
	get:
		return ai_controller.dodge_chance if is_instance_valid(ai_controller) else _dodge_chance
	set(val):
		_dodge_chance = val
		if is_instance_valid(ai_controller):
			ai_controller.dodge_chance = val

@export_range(0.0, 1.0, 0.02) var reaction_time_min: float = 0.10:
	get:
		return ai_controller.reaction_time_min if is_instance_valid(ai_controller) else _reaction_time_min
	set(val):
		_reaction_time_min = val
		if is_instance_valid(ai_controller):
			ai_controller.reaction_time_min = val

@export_range(0.0, 1.0, 0.02) var reaction_time_max: float = 0.22:
	get:
		return ai_controller.reaction_time_max if is_instance_valid(ai_controller) else _reaction_time_max
	set(val):
		_reaction_time_max = val
		if is_instance_valid(ai_controller):
			ai_controller.reaction_time_max = val

@export_group("Combat Defense")
@export var can_block: bool = true:
	get:
		return ai_controller.can_block if is_instance_valid(ai_controller) else _can_block
	set(val):
		_can_block = val
		if is_instance_valid(ai_controller):
			ai_controller.can_block = val

@export_range(0.0, 1.0, 0.05) var block_chance: float = 0.50:
	get:
		return ai_controller.block_chance if is_instance_valid(ai_controller) else _block_chance
	set(val):
		_block_chance = val
		if is_instance_valid(ai_controller):
			ai_controller.block_chance = val

@export_range(0.0, 1.0, 0.05) var parry_chance: float = 0.25:
	get:
		return ai_controller.parry_chance if is_instance_valid(ai_controller) else _parry_chance
	set(val):
		_parry_chance = val
		if is_instance_valid(ai_controller):
			ai_controller.parry_chance = val

@export_range(0.0, 1.0, 0.05) var tactical_block_chance: float = 0.35:
	get:
		return ai_controller.tactical_block_chance if is_instance_valid(ai_controller) else _tactical_block_chance
	set(val):
		_tactical_block_chance = val
		if is_instance_valid(ai_controller):
			ai_controller.tactical_block_chance = val

@export_group("Combat Kick")
@export var can_kick: bool = true:
	get:
		return ai_controller.can_kick if is_instance_valid(ai_controller) else _can_kick
	set(val):
		_can_kick = val
		if is_instance_valid(ai_controller):
			ai_controller.can_kick = val

@export_range(0.0, 1.0, 0.05) var kick_chance_on_blocking_player: float = 0.70:
	get:
		return ai_controller.kick_chance_on_blocking_player if is_instance_valid(ai_controller) else _kick_chance_on_blocking_player
	set(val):
		_kick_chance_on_blocking_player = val
		if is_instance_valid(ai_controller):
			ai_controller.kick_chance_on_blocking_player = val

@export_group("Corpse")
## Сколько труп лежит до начала растворения. 0 и меньше — остаётся навсегда.
@export_range(0.0, 600.0, 0.5, "suffix:с") var corpse_lifetime: float = 5.0
## Длительность растворения; в конце узел удаляется.
@export_range(0.1, 30.0, 0.1, "suffix:с") var dissolve_duration: float = 2.0
@export var dissolve_edge_color: Color = Color(1.0, 0.55, 0.15, 1.0)
@export_range(0.0, 20.0, 0.1) var dissolve_edge_energy: float = 4.0
@export_range(0.5, 20.0, 0.1) var dissolve_noise_scale: float = 6.0
## 0 = чистый шум, 1 = ровный фронт снизу вверх.
@export_range(0.0, 1.0, 0.05) var dissolve_height_bias: float = 0.35

const DISSOLVE_SHADER: Shader = preload("res://shaders/dissolve.gdshader")
## Запасной диапазон высот (стоящий рыцарь), если у трупа не нашёлся скелет.
const CORPSE_HEIGHT_RANGE: float = 1.9
## Запас на толщину тела: кости лежат по оси тела, а меш толще.
const CORPSE_BONE_MARGIN: float = 0.15

var _dissolve_materials: Array[ShaderMaterial] = []

# Duck-typing access to player target
var player: Node3D:
	get:
		return ai_controller.target if is_instance_valid(ai_controller) else null
	set(val):
		if is_instance_valid(ai_controller):
			ai_controller.target = val


func _ready() -> void:
	if team == Team.ALLY:
		hitbox_target_mask = LAYER_ENEMY_SIDE
		collision_layer = LAYER_PLAYER_SIDE
		collision_mask = LAYER_WORLD | LAYER_ENEMY_SIDE
		remove_from_group("enemy")
		add_to_group("ally")
		var detection := get_node_or_null("DetectionArea") as Area3D
		if is_instance_valid(detection):
			detection.collision_mask = LAYER_ENEMY_SIDE
	else:
		hitbox_target_mask = LAYER_PLAYER_SIDE

	if stats == null:
		stats = preload("res://resources/stats/enemy_stats.tres")

	# Ensure components exist
	if not has_node("DefenseComponent"):
		var def := DefenseComponent.new()
		def.name = "DefenseComponent"
		add_child(def)
	if not has_node("MeleeAttackComponent"):
		var atk := MeleeAttackComponent.new()
		atk.name = "MeleeAttackComponent"
		atk.weapon_data = preload("res://resources/weapons/enemy_sword.tres")
		atk.light_weapon_data = preload("res://resources/weapons/enemy_sword_light.tres")
		add_child(atk)
	if not has_node("DashComponent"):
		var dsh := DashComponent.new()
		dsh.name = "DashComponent"
		add_child(dsh)
	if not has_node("StaminaComponent"):
		var stam: StaminaComponent = StaminaComponent.new()
		stam.name = "StaminaComponent"
		add_child(stam)
	if not has_node("KickComponent"):
		var kick := KickComponent.new()
		kick.name = "KickComponent"
		add_child(kick)
	if not has_node("EnemyAIController"):
		var ctrl := EnemyAIController.new()
		ctrl.name = "EnemyAIController"
		add_child(ctrl)

	super._ready()
	character_died.connect(_on_enemy_died)

	ai_controller = get_node_or_null("EnemyAIController") as EnemyAIController
	if is_instance_valid(ai_controller):
		ai_controller.personality = personality
		if team == Team.ALLY:
			ai_controller.target_groups = [&"enemy"]
		ai_controller.is_dummy = _is_dummy
		ai_controller.dummy_can_attack = _dummy_can_attack
		ai_controller.dummy_always_block = _dummy_always_block
		ai_controller.can_dodge = _can_dodge
		ai_controller.dodge_chance = _dodge_chance
		ai_controller.reaction_time_min = _reaction_time_min
		ai_controller.reaction_time_max = _reaction_time_max
		ai_controller.can_block = _can_block
		ai_controller.block_chance = _block_chance
		ai_controller.parry_chance = _parry_chance
		ai_controller.tactical_block_chance = _tactical_block_chance
		ai_controller.can_kick = _can_kick
		ai_controller.kick_chance_on_blocking_player = _kick_chance_on_blocking_player


# --- Corpse dissolve ---

func _on_enemy_died(_attacker: Node3D) -> void:
	if corpse_lifetime <= 0.0:
		return
	# Tween привязан к узлу: если врага удалят раньше (рестарт раунда), он умрёт вместе с ним.
	var tween: Tween = create_tween()
	tween.tween_interval(corpse_lifetime)
	tween.tween_callback(_begin_dissolve)
	tween.tween_method(_set_dissolve_progress, 0.0, 1.0, dissolve_duration)
	tween.tween_callback(queue_free)


func _begin_dissolve() -> void:
	_dissolve_materials.clear()
	if not is_instance_valid(pawn):
		return
	var height_span: Vector2 = _corpse_height_span()
	for node: Node in pawn.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface: int in mesh_instance.mesh.get_surface_count():
			var source: Material = mesh_instance.get_active_material(surface)
			var dissolve: ShaderMaterial = _make_dissolve_material(source, height_span)
			# Override на экземпляре: общие ресурсы материалов (у игрока и др. врагов) не меняются.
			mesh_instance.set_surface_override_material(surface, dissolve)
			_dissolve_materials.append(dissolve)


## Мировая высота низа и размах трупа (x = низ, y = размах) по костям скелета в позе смерти.
## Так градиент «снизу вверх» работает и для лежащего тела, а не только для стоящего.
func _corpse_height_span() -> Vector2:
	var fallback := Vector2(global_position.y, CORPSE_HEIGHT_RANGE)
	if not is_instance_valid(pawn):
		return fallback
	var skeleton: Skeleton3D = null
	for node: Node in pawn.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	if skeleton == null or skeleton.get_bone_count() == 0:
		return fallback
	var low: float = INF
	var high: float = -INF
	for bone: int in skeleton.get_bone_count():
		var y: float = (skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin).y
		low = minf(low, y)
		high = maxf(high, y)
	low -= CORPSE_BONE_MARGIN
	high += CORPSE_BONE_MARGIN
	return Vector2(low, maxf(high - low, 0.3))


func _make_dissolve_material(source: Material, height_span: Vector2) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = DISSOLVE_SHADER
	var std := source as BaseMaterial3D
	if std != null:
		mat.set_shader_parameter("albedo_texture", std.albedo_texture)
		mat.set_shader_parameter("albedo_color", std.albedo_color)
		mat.set_shader_parameter("roughness", std.roughness)
		mat.set_shader_parameter("metallic", std.metallic)
	mat.set_shader_parameter("origin_y", height_span.x)
	mat.set_shader_parameter("height_range", height_span.y)
	mat.set_shader_parameter("edge_color", dissolve_edge_color)
	mat.set_shader_parameter("edge_energy", dissolve_edge_energy)
	mat.set_shader_parameter("noise_scale", dissolve_noise_scale)
	mat.set_shader_parameter("height_bias", dissolve_height_bias)
	mat.set_shader_parameter("progress", 0.0)
	return mat


func _set_dissolve_progress(value: float) -> void:
	for mat: ShaderMaterial in _dissolve_materials:
		mat.set_shader_parameter("progress", value)
