extends CharacterBody3D

var item_index := -1
var amount := 1
var age := 0.0
var being_collected := false
var item_material: Material
var visual_root: Node3D


func setup(drop_item_index: int, drop_amount: int, material: Material) -> void:
	item_index = drop_item_index
	amount = drop_amount
	item_material = material


func _ready() -> void:
	name = "ItemDrop"
	add_to_group("item_drops")
	collision_layer = 0
	collision_mask = 1
	safe_margin = 0.02

	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.17
	collision.shape = sphere
	collision.position.y = 0.18
	add_child(collision)

	visual_root = Node3D.new()
	visual_root.position.y = 0.28
	add_child(visual_root)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.36, 0.36, 0.36) if item_index != 14 else Vector3(0.48, 0.22, 0.34)
	mesh.material = item_material
	mesh_instance.mesh = mesh
	visual_root.add_child(mesh_instance)

	velocity = Vector3(randf_range(-0.65, 0.65), 1.7, randf_range(-0.65, 0.65))


func _physics_process(delta: float) -> void:
	age += delta
	if age >= 300.0:
		queue_free()
		return
	if being_collected:
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.x = move_toward(velocity.x, 0.0, delta * 2.8)
		velocity.z = move_toward(velocity.z, 0.0, delta * 2.8)
	move_and_slide()
	visual_root.rotation.y += delta * 1.8
	visual_root.position.y = 0.28 + sin(age * 4.2) * 0.045


func attract_to(target: Vector3, delta: float) -> void:
	being_collected = true
	collision_mask = 0
	velocity = Vector3.ZERO
	global_position = global_position.move_toward(target, delta * 9.0)
	visual_root.rotation.y += delta * 7.0


func can_be_collected() -> bool:
	return age >= 0.30
