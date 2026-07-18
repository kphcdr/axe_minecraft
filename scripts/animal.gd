extends CharacterBody3D

var species := "cow"
var home_position := Vector3.ZERO
var move_direction := Vector3.ZERO
var decision_timer := 0.0
var move_speed := 1.1
var body_height := 0.9
var visual_root: Node3D
var walking_leg_parts: Array[Node3D] = []
var walk_phase := 0.0
var external_push := Vector3.ZERO


func setup(animal_species: String, spawn_position: Vector3) -> void:
	species = animal_species
	position = spawn_position
	home_position = spawn_position


func _ready() -> void:
	name = species.capitalize()
	add_to_group("animals")
	visual_root = Node3D.new()
	visual_root.name = "Visuals"
	add_child(visual_root)
	build_model()
	choose_new_action()


func build_model() -> void:
	var collision_size := Vector3(0.9, 1.4, 0.9)
	match species:
		"cow":
			body_height = 1.4
			move_speed = 1.05
			collision_size = Vector3(0.9, 1.4, 0.9)
			add_box(Vector3(0.82, 0.72, 1.30), Vector3(0, 0.91, 0), Color("#eee9df"))
			add_box(Vector3(0.66, 0.68, 0.54), Vector3(0, 1.04, -0.80), Color("#f2ede3"))
			add_box(Vector3(0.44, 0.24, 0.10), Vector3(0, 0.91, -1.10), Color("#c98f91"))
			add_box(Vector3(0.16, 0.11, 0.10), Vector3(-0.25, 1.39, -0.82), Color("#e8d6ad"))
			add_box(Vector3(0.16, 0.11, 0.10), Vector3(0.25, 1.39, -0.82), Color("#e8d6ad"))
			add_face_eyes(0.19, 1.15, -1.075)
			# 原创黑白奶牛斑纹，左右分布不对称。
			add_box(Vector3(0.025, 0.31, 0.42), Vector3(-0.422, 0.98, -0.14), Color("#24272a"))
			add_box(Vector3(0.026, 0.16, 0.20), Vector3(-0.424, 0.80, -0.40), Color("#24272a"))
			add_box(Vector3(0.026, 0.13, 0.18), Vector3(-0.424, 1.16, 0.02), Color("#24272a"))
			add_box(Vector3(0.025, 0.24, 0.31), Vector3(-0.422, 0.78, 0.42), Color("#383b3d"))
			add_box(Vector3(0.026, 0.14, 0.17), Vector3(-0.424, 0.94, 0.55), Color("#383b3d"))
			add_box(Vector3(0.025, 0.28, 0.36), Vector3(0.422, 0.91, 0.26), Color("#222528"))
			add_box(Vector3(0.026, 0.15, 0.19), Vector3(0.424, 1.10, 0.11), Color("#222528"))
			add_box(Vector3(0.026, 0.17, 0.18), Vector3(0.424, 0.73, 0.48), Color("#222528"))
			add_box(Vector3(0.025, 0.20, 0.27), Vector3(0.422, 1.03, -0.42), Color("#34373a"))
			add_box(Vector3(0.026, 0.12, 0.15), Vector3(0.424, 0.87, -0.55), Color("#34373a"))
			add_box(Vector3(0.30, 0.025, 0.38), Vector3(-0.16, 1.282, 0.12), Color("#303336"))
			add_box(Vector3(0.19, 0.026, 0.22), Vector3(0.07, 1.284, 0.34), Color("#303336"))
			add_box(Vector3(0.22, 0.026, 0.27), Vector3(0.20, 1.284, -0.42), Color("#25282b"))
			add_box(Vector3(0.20, 0.26, 0.025), Vector3(0.19, 1.14, -1.082), Color("#282b2e"))
			add_legs(Color("#e2ddd4"), 0.30, 0.45, 0.56, 0.18)
		"sheep":
			body_height = 1.3
			move_speed = 0.95
			collision_size = Vector3(0.9, 1.3, 0.9)
			add_box(Vector3(0.88, 0.82, 1.20), Vector3(0, 0.86, 0), Color("#e8e3d6"))
			add_box(Vector3(0.58, 0.62, 0.48), Vector3(0, 0.94, -0.73), Color("#4c4642"))
			add_box(Vector3(0.42, 0.17, 0.12), Vector3(0, 1.28, -0.73), Color("#f4f0e5"))
			add_face_eyes(0.17, 1.03, -0.98)
			add_box(Vector3(0.025, 0.28, 0.35), Vector3(-0.452, 0.98, 0.10), Color("#fffdf4"))
			add_legs(Color("#403b38"), 0.30, 0.40, 0.48)
		"pig":
			body_height = 0.9
			move_speed = 1.0
			collision_size = Vector3(0.9, 0.9, 0.9)
			add_box(Vector3(0.82, 0.58, 1.08), Vector3(0, 0.57, 0), Color("#dd8f9b"))
			add_box(Vector3(0.62, 0.52, 0.48), Vector3(0, 0.67, -0.68), Color("#e79ba6"))
			add_box(Vector3(0.34, 0.20, 0.12), Vector3(0, 0.60, -0.98), Color("#bf6676"))
			add_face_eyes(0.18, 0.78, -0.93)
			# 不对称泥点：只覆盖身体局部，保留粉色主体。
			add_box(Vector3(0.026, 0.23, 0.34), Vector3(0.422, 0.61, 0.18), Color("#75513a"))
			add_box(Vector3(0.027, 0.13, 0.20), Vector3(0.424, 0.76, -0.04), Color("#75513a"))
			add_box(Vector3(0.027, 0.12, 0.16), Vector3(0.424, 0.48, 0.37), Color("#75513a"))
			add_box(Vector3(0.026, 0.15, 0.22), Vector3(-0.422, 0.72, -0.16), Color("#8a6042"))
			add_box(Vector3(0.027, 0.10, 0.14), Vector3(-0.424, 0.60, -0.32), Color("#8a6042"))
			add_box(Vector3(0.30, 0.026, 0.25), Vector3(0.16, 0.872, 0.27), Color("#684832"))
			add_box(Vector3(0.18, 0.027, 0.16), Vector3(-0.07, 0.874, 0.42), Color("#684832"))
			add_legs(Color("#ad5d6c"), 0.29, 0.37, 0.30, 0.17)
		"chicken":
			body_height = 0.7
			move_speed = 1.25
			collision_size = Vector3(0.4, 0.7, 0.4)
			add_box(Vector3(0.46, 0.46, 0.58), Vector3(0, 0.43, 0), Color("#eeeade"))
			add_box(Vector3(0.38, 0.38, 0.34), Vector3(0, 0.69, -0.40), Color("#fffdf2"))
			add_box(Vector3(0.28, 0.12, 0.22), Vector3(0, 0.65, -0.68), Color("#e8ac31"))
			add_box(Vector3(0.14, 0.16, 0.10), Vector3(0, 0.94, -0.39), Color("#d5483e"))
			add_box(Vector3(0.12, 0.17, 0.08), Vector3(0, 0.50, -0.59), Color("#d5483e"))
			add_face_eyes(0.12, 0.77, -0.575, 0.065, false)
			add_box(Vector3(0.10, 0.32, 0.38), Vector3(-0.26, 0.43, 0.03), Color("#d9d4c8"))
			add_box(Vector3(0.10, 0.32, 0.38), Vector3(0.26, 0.43, 0.03), Color("#d9d4c8"))
			# 鸡只有两条腿，每条腿下方带一只向前伸出的扁脚。
			for x_sign in [-1.0, 1.0]:
				var leg := add_box(Vector3(0.065, 0.23, 0.065), Vector3(x_sign * 0.12, 0.115, 0.04), Color("#d99d2e"))
				var foot := add_box(Vector3(0.10, 0.045, 0.20), Vector3(x_sign * 0.12, 0.025, -0.035), Color("#e3aa32"))
				leg.set_meta("walk_side", x_sign)
				foot.set_meta("walk_side", x_sign)
				walking_leg_parts.append(leg)
				walking_leg_parts.append(foot)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = collision_size
	collision.shape = shape
	collision.position.y = shape.size.y * 0.5
	add_child(collision)


func add_face_eyes(x_offset: float, eye_y: float, front_z: float, eye_size: float = 0.085, with_white: bool = true) -> void:
	for x_sign in [-1.0, 1.0]:
		if with_white:
			add_box(Vector3(eye_size * 1.75, eye_size * 1.35, 0.022), Vector3(x_sign * x_offset, eye_y, front_z), Color("#f8f7f1"))
			add_box(Vector3(eye_size * 0.68, eye_size * 0.82, 0.026), Vector3(x_sign * x_offset, eye_y, front_z - 0.015), Color("#121518"))
		else:
			add_box(Vector3(eye_size, eye_size, 0.025), Vector3(x_sign * x_offset, eye_y, front_z), Color("#151719"))


func add_legs(color: Color, x_offset: float, z_offset: float, height: float, thickness: float = 0.13) -> void:
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			var leg := add_box(Vector3(thickness, height, thickness), Vector3(x_sign * x_offset, height * 0.5, z_sign * z_offset), color)
			# 对角腿同步，另一对反相，形成稳定的四足步态。
			leg.set_meta("walk_side", x_sign * z_sign)
			walking_leg_parts.append(leg)


func add_box(size: Vector3, box_position: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = box_position
	visual_root.add_child(mesh_instance)
	return mesh_instance


func choose_new_action() -> void:
	decision_timer = randf_range(1.6, 4.5)
	if randf() < 0.32:
		move_direction = Vector3.ZERO
	else:
		var angle := randf_range(-PI, PI)
		move_direction = Vector3(sin(angle), 0, cos(angle)).normalized()


func _physics_process(delta: float) -> void:
	decision_timer -= delta
	if decision_timer <= 0.0:
		choose_new_action()
	if global_position.distance_to(home_position) > 22.0:
		move_direction = (home_position - global_position) * Vector3(1, 0, 1)
		move_direction = move_direction.normalized()
	if not is_on_floor():
		velocity += get_gravity() * delta
	velocity.x = move_direction.x * move_speed + external_push.x
	velocity.z = move_direction.z * move_speed + external_push.z
	external_push = external_push.move_toward(Vector3.ZERO, delta * 5.0)
	if move_direction.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-move_direction.x, -move_direction.z), delta * 4.0)
	animate_walk(delta)
	move_and_slide()


func apply_push(force: Vector3) -> void:
	external_push = external_push.lerp(force, 0.34)
	if external_push.length() > 1.0:
		external_push = external_push.normalized() * 1.0


func animate_walk(delta: float) -> void:
	var is_walking := move_direction.length_squared() > 0.01 and is_on_floor()
	var frequency := 10.0 if species == "chicken" else (7.5 if species == "pig" else 6.2)
	var swing := 0.48 if species == "chicken" else (0.34 if species == "pig" else 0.30)
	var bob_amount := 0.018 if species == "chicken" else (0.025 if species == "pig" else 0.032)
	if is_walking:
		walk_phase += delta * frequency
		visual_root.position.y = abs(sin(walk_phase * 2.0)) * bob_amount
		for part in walking_leg_parts:
			var side: float = part.get_meta("walk_side")
			part.rotation.x = sin(walk_phase) * swing * side
	else:
		visual_root.position.y = move_toward(visual_root.position.y, 0.0, delta * 0.18)
		for part in walking_leg_parts:
			part.rotation.x = move_toward(part.rotation.x, 0.0, delta * 3.0)
