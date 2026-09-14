extends CharacterBody3D

@onready var pawn: Node3D = $pawn
@onready var animation_tree: AnimationTree = $pawn/AnimationTree
@onready var navigation_agent_3d: NavigationAgent3D = $NavigationAgent3D

# --- Movement speeds ---
@export_group("Movement Speeds")
@export var run_speed := 5.0          # Normal run (CHASE)
@export var walk_speed := 2.5         # Normal walk (used as the base threshold for animation blending)
@export var combat_walk_speed := 2.0  # Approach speed while in combat (ORBIT, approach)
@export var combat_strafe_speed := 1.8 # Strafe speed while in combat (ORBIT, strafe)

# --- Acceleration / deceleration ---
@export_group("Acceleration")
@export var accel := 5.0              # Acceleration for normal movement
@export var decel := 8.0              # Deceleration (used during approach/strafe pauses)
@export var combat_accel := 6.0       # Separate acceleration for combat movement (approach/strafe)

# --- Distances ---
@export_group("Distances")
@export var combat_engage_dist := 5.0 # Distance to enter combat mode (CHASE -> ORBIT)
@export var combat_disengage_margin := 0.5 # Buffer before leaving combat back to CHASE (hysteresis, prevents flickering at the border)
@export var orbit_dist := 2.0         # Distance at which strafing starts instead of approaching

# --- Cautious approach ---
@export_group("Approach Caution")
@export var approach_pause_time := 0.5
@export var approach_move_time := 0.8

# --- Cautious strafe ---
@export_group("Strafe Caution")
@export var strafe_pause_time := 0.6
@export var strafe_move_time := 0.8

# --- AnimationTree parameter interpolation speed ---
# The higher the value, the faster the animation catches up to the target state.
@export_group("Animation Blend Speeds")
@export var combat_mode_blend_speed := 5.0      # Combat mode switch speed (normal <-> combat)
@export var combat_movement_blend_speed := 8.0  # Combat movement BlendSpace2D interpolation speed
@export var movement_blend_speed := 10.0        # Default movement update speed (idle/walk/run); should be faster than combat_mode, otherwise leg animation will lag behind actual speed

# --- Rotation ---
@export_group("Rotation")
@export var rotation_speed := 8.0     # Smooth rotation speed toward the player (higher = snappier)
@export var use_smooth_rotation := true # If true, rotation is smoothed instead of a hard look_at snap (removes rotation jitter)

enum State { IDLE, CHASE, ORBIT }
var current_state: State = State.IDLE
var prev_state: State = State.IDLE

var player: Node3D

var target_combat_mode := 0.0
# Target position for the Combat movement BlendSpace2D:
#   (0, 1)  = walk forward,  (0, -1) = walk backward (unused for now)
#   (1, 0)  = strafe right,  (-1, 0) = strafe left
#   (0, 0)  = combat idle
var target_combat_movement := Vector2.ZERO

var strafe_timer := 0.0
var strafe_dir_sign := 1.0
var is_strafe_paused := false

var approach_timer := 0.0
var is_approach_paused := false

var _was_strafing := false # Tracks approach <-> strafe sub-state to reset timers on switch


func _on_area_3d_body_entered(body):
	if body.is_in_group("player"):
		player = body
		current_state = State.CHASE
		print("I can see a player!")


func _on_area_3d_body_exited(body):
	if body == player:
		player = null
		current_state = State.IDLE


# Smoothly rotates toward the target to avoid a hard look_at snap every frame.
func _face_target(target_pos: Vector3, delta: float) -> void:
	var flat_target = Vector3(target_pos.x, global_position.y, target_pos.z)

	# Bail out if target is directly above/below us (zero-length direction would crash look_at)
	if global_position.distance_squared_to(flat_target) < 0.0001:
		return

	if use_smooth_rotation:
		var current_xform = global_transform
		var desired_xform = current_xform.looking_at(flat_target, Vector3.UP)
		var current_quat = current_xform.basis.get_rotation_quaternion()
		var desired_quat = desired_xform.basis.get_rotation_quaternion()
		var new_quat = current_quat.slerp(desired_quat, clamp(rotation_speed * delta, 0.0, 1.0))
		global_transform.basis = Basis(new_quat)
	else:
		look_at(flat_target, Vector3.UP)


# Converts horizontal speed into a BlendSpace1D position (0.0 idle / 0.5 walk / 1.0 run).
func _get_blend_position(speed: float) -> float:
	if speed <= 0.01:
		return 0.0
	elif speed <= walk_speed:
		return remap(speed, 0.0, walk_speed, 0.0, 0.5)
	else:
		# Clamp to 1.0 so external forces (explosions, slopes) don't push the blend out of range
		return clamp(remap(speed, walk_speed, run_speed, 0.5, 1.0), 0.5, 1.0)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if not player or not is_instance_valid(player):
		move_and_slide()
		return

	var distance_to_player := global_position.distance_to(player.global_position)

	match current_state:
		State.IDLE:
			# Decelerate to prevent infinite sliding if pushed while idle
			velocity.x = lerp(velocity.x, 0.0, decel * delta)
			velocity.z = lerp(velocity.z, 0.0, decel * delta)

		State.CHASE:
			if distance_to_player <= combat_engage_dist:
				current_state = State.ORBIT

			# Always run chase logic even on the transition frame to avoid a 1-tick freeze
			target_combat_mode = 0.0 # Normal run
			_face_target(player.global_position, delta)

			navigation_agent_3d.target_position = player.global_position
			var next_pos = navigation_agent_3d.get_next_path_position()
			var direction = global_position.direction_to(next_pos)

			velocity.x = lerp(velocity.x, direction.x * run_speed, accel * delta)
			velocity.z = lerp(velocity.z, direction.z * run_speed, accel * delta)

		State.ORBIT:
			if distance_to_player > combat_engage_dist + combat_disengage_margin:
				current_state = State.CHASE

			# Always run orbit logic even on the transition frame to avoid a 1-tick freeze
			target_combat_mode = 1.0 # Combat mode enabled
			_face_target(player.global_position, delta)

			var is_strafing = distance_to_player <= orbit_dist

			# Reset timers when switching between approach and strafe sub-states
			if is_strafing != _was_strafing:
				if is_strafing:
					strafe_timer = strafe_move_time
					is_strafe_paused = false
				else:
					approach_timer = approach_move_time
					is_approach_paused = false
				_was_strafing = is_strafing

			if not is_strafing:
				# Cautious approach: step forward with pauses
				approach_timer -= delta
				if approach_timer <= 0.0:
					is_approach_paused = not is_approach_paused
					approach_timer = approach_pause_time if is_approach_paused else approach_move_time

				var direction = global_position.direction_to(player.global_position)
				var approach_speed = 0.0 if is_approach_paused else combat_walk_speed
				var approach_accel = decel if is_approach_paused else combat_accel

				# Pause -> combat idle (0,0), moving -> walk forward (0,1)
				target_combat_movement = Vector2.ZERO if is_approach_paused else Vector2(0.0, 1.0)

				velocity.x = lerp(velocity.x, direction.x * approach_speed, approach_accel * delta)
				velocity.z = lerp(velocity.z, direction.z * approach_speed, approach_accel * delta)
			else:
				# Cautious strafe: sideways movement with pauses and direction switches
				strafe_timer -= delta
				if strafe_timer <= 0.0:
					if is_strafe_paused:
						is_strafe_paused = false
						strafe_timer = strafe_move_time
						strafe_dir_sign *= -1.0
					else:
						is_strafe_paused = true
						strafe_timer = strafe_pause_time

				var right_dir = global_transform.basis.x
				var strafe_speed = 0.0 if is_strafe_paused else combat_strafe_speed
				var strafe_accel = decel if is_strafe_paused else combat_accel

				# Pause -> combat idle (0,0), moving -> strafe right (1,0) or left (-1,0)
				target_combat_movement = Vector2.ZERO if is_strafe_paused else Vector2(strafe_dir_sign, 0.0)

				velocity.x = lerp(velocity.x, right_dir.x * strafe_dir_sign * strafe_speed, strafe_accel * delta)
				velocity.z = lerp(velocity.z, right_dir.z * strafe_dir_sign * strafe_speed, strafe_accel * delta)

	# --- Leaving combat: reset combat movement blend target ---
	# The node is already faded out by combat_mode -> 0, but keeping the target clean
	# prevents a visible pop if the enemy re-enters combat shortly after.
	if prev_state == State.ORBIT and current_state != State.ORBIT:
		target_combat_movement = Vector2.ZERO

	prev_state = current_state

	# --- Smooth interpolation of AnimationTree parameters ---
	var current_combat = animation_tree.get("parameters/Combat mode/blend_amount")
	animation_tree.set("parameters/Combat mode/blend_amount", lerp(current_combat, target_combat_mode, combat_mode_blend_speed * delta))

	var current_cm_pos: Vector2 = animation_tree.get("parameters/Combat movement/blend_position")
	animation_tree.set("parameters/Combat movement/blend_position", current_cm_pos.lerp(target_combat_movement, combat_movement_blend_speed * delta))

	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	var target_blend_pos = _get_blend_position(horizontal_speed)
	var current_blend_pos = animation_tree.get("parameters/Default movement/blend_position")
	animation_tree.set("parameters/Default movement/blend_position", lerp(current_blend_pos, target_blend_pos, movement_blend_speed * delta))

	move_and_slide()
