extends CharacterBody3D

signal block_place_requested(position: Vector3)
signal block_remove_requested(block: Node)
signal block_interact_requested(block: Node)
signal animal_attack_requested(animal: Node)
signal backpack_requested

const SPEED := 7.0
const SNEAK_SPEED := 2.6
const JUMP_VELOCITY := 5.05
const LOOK_SENSITIVITY := 0.0022

var camera: Camera3D
var ray: RayCast3D
var scaffold_check: Callable
var capsule: CapsuleShape3D
var body_collision: CollisionShape3D
var external_push := Vector3.ZERO
var in_water := false
var input_locked := false


func _ready() -> void:
	name = "Player"
	position = Vector3(0, 2.0, 6.0)
	# 增大碰撞恢复距离，避免高速落入一格坑时嵌进坑壁边缘。
	safe_margin = 0.035
	floor_snap_length = 0.16

	body_collision = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.5
	body_collision.shape = capsule
	body_collision.position.y = 0.75
	add_child(body_collision)

	camera = Camera3D.new()
	camera.position.y = 1.35
	add_child(camera)

	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -8)
	ray.collision_mask = 1
	ray.collide_with_areas = true
	ray.enabled = true
	camera.add_child(ray)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * LOOK_SENSITIVITY)
		camera.rotation.x = clamp(
			camera.rotation.x - event.relative.y * LOOK_SENSITIVITY,
			-deg_to_rad(85.0),
			deg_to_rad(85.0)
		)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event.is_action_pressed("backpack"):
		backpack_requested.emit()

	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if not ray.is_colliding():
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			var collider := ray.get_collider()
			if is_instance_valid(collider) and collider.is_in_group("animals"):
				animal_attack_requested.emit(collider)
			# 方块挖掘仍由主场景的按住进度处理。
			return
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var collider := ray.get_collider()
			if is_instance_valid(collider) and (collider.get_meta("is_door", false) or collider.get_meta("is_furnace", false)) and not Input.is_action_pressed("sneak"):
				block_interact_requested.emit(collider)
				return
			var point := ray.get_collision_point() + ray.get_collision_normal() * 0.5
			block_place_requested.emit(point)


func _physics_process(delta: float) -> void:
	var sneaking := Input.is_action_pressed("sneak")
	var target_height := 1.15 if sneaking else 1.5
	capsule.height = move_toward(capsule.height, target_height, delta * 3.0)
	body_collision.position.y = capsule.height * 0.5
	camera.position.y = move_toward(camera.position.y, 1.02 if sneaking else 1.35, delta * 2.5)

	var climbing: bool = not input_locked and scaffold_check.is_valid() and bool(scaffold_check.call(global_position)) and Input.is_action_pressed("jump")
	if climbing:
		velocity.y = 3.2
	elif not is_on_floor():
		velocity += get_gravity() * delta
	if not input_locked and not climbing and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input := Vector2.ZERO if input_locked else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var movement_speed := SNEAK_SPEED if sneaking else SPEED
	if in_water:
		movement_speed *= 0.52
	if direction:
		velocity.x = direction.x * movement_speed
		velocity.z = direction.z * movement_speed
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0, SPEED * 5.0 * delta)
	velocity.x += external_push.x
	velocity.z += external_push.z
	external_push = external_push.move_toward(Vector3.ZERO, delta * 6.0)
	var previous_position := global_position
	var was_grounded := is_on_floor()
	move_and_slide()
	# 离地跳跃时不能继续吸附地面，否则坑沿会抵消一部分向上速度。
	if velocity.y > 0.0:
		floor_snap_length = 0.0
	else:
		floor_snap_length = 0.16
	if sneaking and was_grounded and not has_close_support():
		global_position = previous_position
		velocity.x = 0
		velocity.y = 0
		velocity.z = 0
		apply_floor_snap()


func apply_push(force: Vector3) -> void:
	external_push = external_push.lerp(force, 0.34)
	if external_push.length() > 0.55:
		external_push = external_push.normalized() * 0.55


func set_in_water(value: bool) -> void:
	in_water = value


func set_input_locked(value: bool) -> void:
	input_locked = value


func has_close_support() -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.08,
		global_position + Vector3.DOWN * 0.30,
		1
	)
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
