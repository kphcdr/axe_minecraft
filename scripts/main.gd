extends Node3D

const PlayerScript := preload("res://scripts/player.gd")
const AnimalScript := preload("res://scripts/animal.gd")
const ItemDropScript := preload("res://scripts/item_drop.gd")
const MATERIAL_NAMES := ["石头", "木头", "玻璃", "木门", "脚手架", "草地", "水", "红砖", "灯块", "树叶", "原木", "泥土", "沙子", "熔炉", "肉"]
const MATERIAL_COLORS := [
	Color("#71757c"),
	Color("#a66b3f"),
	Color("#78cde0"),
	Color("#9b5b2c"),
	Color("#d6a24a"),
	Color("#58a34a"),
	Color("#3f9ed8"),
	Color("#a84e3f"),
	Color("#ffd36a"),
	Color("#2f7d39"),
	Color("#765037"),
	Color("#70472b"),
	Color("#d9c487"),
	Color("#4b4d50"),
	Color("#a74335"),
]

var selected_material := 0
var selected_hotbar_slot := 0
var hotbar_slot_materials: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8]
var inventory := [30, 30, 20, 5, 20, 20, 10, 20, 5, 0, 0, 0, 0, 0, 0]
var player_health := 20.0
var player_hunger := 20.0
var starvation_damage_timer := 3.0
var occupied: Dictionary = {}
var info_label: Label
var hotbar_labels: Array[Label] = []
var hotbar_panels: Array[PanelContainer] = []
var hotbar_contents: Array[Control] = []
var hotbar_icons: Array[TextureRect] = []
var hotbar_previews: Array[SubViewport] = []
var message_label: Label
var message_timer := 0.0
var selection_label: Label
var selection_timer := 0.0
var player: CharacterBody3D
var block_materials: Array[Material] = []
var glass_edge_material: Material
var door_material: Material
var door_handle_material: Material
var scaffold_material: Material
var lamp_edge_material: Material
var furnace_opening_material: Material
var furnace_trim_material: Material
var water_flow_queue: Array[Dictionary] = []
var water_flow_timer := 0.0
var clouds: Array[Node3D] = []
var animal_spawn_timer := 60.0
var generated_region_centers: Array[Vector3] = [Vector3.ZERO]
var generated_water_centers: Array[Vector3] = []
var generated_ground_cells: Dictionary = {}
var last_ground_center := Vector3i.ZERO
var terrain_generation_queue: Array[Dictionary] = []
var backpack_panel: PanelContainer
var backpack_buttons: Array[Button] = []
var backpack_count_labels: Array = []
var backpack_slot_materials: Array[int] = []
var leaf_material: Material
var mining_target: Node
var mining_progress := 0.0
var mining_overlay: MeshInstance3D
var mining_release_required := false
var furnace_panel: PanelContainer
var furnace_status_label: Label
var furnace_active := false
var furnace_timer := 0.0


func _ready() -> void:
	for index in range(27):
		backpack_slot_materials.append(index if index < MATERIAL_NAMES.size() else -1)
	create_block_materials()
	create_world()
	create_player()
	create_ui()
	create_destructible_ground(Vector3i.ZERO)
	create_bedrock_floor()
	create_natural_landscape()
	spawn_natural_pond(Vector3i(-35, 0, 75))
	spawn_natural_pond(Vector3i(42, 0, 78))
	spawn_natural_pond(Vector3i(-88, 0, -45))
	create_animals()
	update_ui()
	show_selected_material()
	show_message("准星对准地面或方块，点击鼠标右键放置")


func create_world() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#9fd8f5")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)
	create_clouds()
	create_mining_overlay()


func create_mining_overlay() -> void:
	mining_overlay = MeshInstance3D.new()
	mining_overlay.name = "MiningCracks"
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 1.012
	var material := create_shader_material("""
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;
instance uniform float crack_stage = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 p = UV * 12.0;
	vec2 cell = floor(p);
	vec2 f = fract(p) - vec2(0.5);
	float random_value = hash(cell);
	float branch_a = abs(f.y - sin((cell.x + f.x) * 1.7 + random_value * 4.0) * 0.20);
	float branch_b = abs(f.x - cos((cell.y + f.y) * 1.4 + random_value * 5.0) * 0.18);
	float line = 1.0 - smoothstep(0.025, 0.085, min(branch_a, branch_b));
	float reveal = step(random_value, clamp(crack_stage * 1.18, 0.0, 1.0));
	ALBEDO = vec3(0.055, 0.045, 0.038);
	ALPHA = line * reveal * smoothstep(0.06, 0.22, crack_stage) * 0.88;
}
""")
	mesh.material = material
	mining_overlay.mesh = mesh
	mining_overlay.visible = false
	mining_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mining_overlay)


func create_clouds() -> void:
	var cloud_material := StandardMaterial3D.new()
	cloud_material.albedo_color = Color(1.0, 1.0, 1.0, 0.90)
	cloud_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for cloud_index in range(12):
		var cloud := Node3D.new()
		cloud.position = Vector3(
			randf_range(-140.0, 140.0),
			randf_range(20.0, 35.0),
			randf_range(-165.0, 70.0)
		)
		cloud.set_meta("speed", randf_range(0.55, 1.15))
		for part_index in range(randi_range(3, 5)):
			var part := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(randf_range(7.0, 14.0), randf_range(1.8, 3.8), randf_range(5.0, 9.0))
			mesh.material = cloud_material
			part.mesh = mesh
			part.position = Vector3((part_index - 2) * randf_range(4.0, 6.5), randf_range(-0.8, 0.8), randf_range(-2.2, 2.2))
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cloud.add_child(part)
		add_child(cloud)
		clouds.append(cloud)


func create_animals() -> void:
	var species_list := ["cow", "cow", "sheep", "sheep", "pig", "pig", "chicken", "chicken"]
	for index in species_list.size():
		var angle := TAU * float(index) / float(species_list.size()) + randf_range(-0.25, 0.25)
		var distance := randf_range(10.0, 22.0)
		spawn_animal(species_list[index], Vector3(cos(angle) * distance, 1.5, sin(angle) * distance))


func spawn_animals_out_of_view() -> void:
	const MAX_ANIMALS := 40
	if get_tree().get_nodes_in_group("animals").size() >= MAX_ANIMALS:
		return
	var camera_forward: Vector3 = -player.camera.global_transform.basis.z
	camera_forward.y = 0
	if camera_forward.length_squared() < 0.01:
		camera_forward = -player.global_transform.basis.z
		camera_forward.y = 0
	camera_forward = camera_forward.normalized()
	var behind: Vector3 = -camera_forward
	var species_list := ["cow", "cow", "sheep", "sheep", "pig", "pig", "chicken", "chicken"]
	for animal_species in species_list:
		if get_tree().get_nodes_in_group("animals").size() >= MAX_ANIMALS:
			break
		var spawn_position := Vector3.ZERO
		var found_ground := false
		for attempt in range(20):
			var direction: Vector3 = behind.rotated(Vector3.UP, randf_range(-1.20, 1.20))
			var distance := randf_range(18.0, 25.0)
			spawn_position = player.global_position + direction * distance
			spawn_position.y = 1.5
			var ground_cell := Vector3i(roundi(spawn_position.x), 0, roundi(spawn_position.z))
			if occupied.has(ground_cell) and occupied[ground_cell].get_meta("material_index", -1) in [5, 11, 12]:
				found_ground = true
				break
		if found_ground:
			spawn_animal(animal_species, spawn_position)


func spawn_animal(animal_species: String, spawn_position: Vector3) -> void:
	var animal := AnimalScript.new()
	animal.setup(animal_species, spawn_position)
	animal.died.connect(on_animal_died)
	add_child(animal)


func attack_animal(animal: Node) -> void:
	if not is_instance_valid(animal) or not animal.is_in_group("animals"):
		return
	var knockback: Vector3 = animal.global_position - player.global_position
	knockback.y = 0.0
	if knockback.length_squared() > 0.001:
		knockback = knockback.normalized()
	var remaining_health: int = animal.call("take_damage", 1, knockback)
	if remaining_health > 0:
		show_message("命中%s：生命 %d / 10" % [get_species_name(str(animal.species)), remaining_health])


func on_animal_died(animal_species: String, drop_position: Vector3) -> void:
	var meat_drop: int = {"cow": 3, "sheep": 2, "pig": 3, "chicken": 1}.get(animal_species, 1)
	create_item_drop(14, meat_drop, drop_position)
	show_message("击败%s，掉落了 %d 块肉" % [get_species_name(animal_species), meat_drop])


func get_species_name(animal_species: String) -> String:
	return {"cow": "牛", "sheep": "羊", "pig": "猪", "chicken": "鸡"}.get(animal_species, "动物")


func apply_water_and_player_pushes() -> void:
	var animals := get_tree().get_nodes_in_group("animals")
	var player_motion := Vector3(player.velocity.x, 0, player.velocity.z)
	if player_motion.length() > 0.15:
		for animal: CharacterBody3D in animals:
			var separation := animal.global_position - player.global_position
			var horizontal := Vector3(separation.x, 0, separation.z)
			if horizontal.length() < 1.25 and absf(separation.y) < 1.6 and horizontal.length_squared() > 0.001:
				var push_strength := minf(player_motion.length() / 7.0, 1.0) * 0.85
				animal.call("apply_push", horizontal.normalized() * push_strength)

	apply_water_push_to_body(player, 0.45)
	for animal: CharacterBody3D in animals:
		apply_water_push_to_body(animal, 0.90)


func apply_water_push_to_body(body: CharacterBody3D, strength: float) -> void:
	var water := find_water_at_position(body.global_position)
	if body == player:
		body.call("set_in_water", water != null)
	if not water:
		return
	var direction: Vector2 = water.get_meta("flow_direction", Vector2.ZERO)
	if direction.length_squared() <= 0.01:
		return
	direction = direction.normalized()
	body.call("apply_push", Vector3(direction.x, 0, direction.y) * strength)


func find_water_at_position(world_position: Vector3) -> Node:
	var x := roundi(world_position.x)
	var z := roundi(world_position.z)
	var base_y := roundi(world_position.y)
	for y in range(base_y - 1, base_y + 2):
		var cell := Vector3i(x, y, z)
		if occupied.has(cell):
			var candidate: Node = occupied[cell]
			if candidate.get_meta("material_index", -1) == 6:
				var water_bottom := float(y) - 0.5
				var water_top := water_bottom + float(candidate.get_meta("water_amount", 1.0))
				if world_position.y < water_top and world_position.y + 0.30 > water_bottom:
					return candidate
	return null


func create_block_materials() -> void:
	block_materials = [
		create_shader_material("""
shader_type spatial;
varying vec3 world_pos;
float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 fine_cell = floor(world_pos * 13.0);
	float speckle = hash(fine_cell);
	float broad = hash(floor(world_pos * 2.5));
	float shade = (speckle - 0.5) * 0.10 + (broad - 0.5) * 0.07;
	vec3 stone = vec3(0.30, 0.32, 0.34) + vec3(shade);
	float dark_fleck = step(0.92, speckle);
	ALBEDO = mix(stone, vec3(0.16, 0.18, 0.20), dark_fleck * 0.55);
	ROUGHNESS = 0.94;
}
"""),
		create_shader_material("""
shader_type spatial;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
	// 每个方块表面由 2×4 块错缝木板组成。
	vec2 plank_uv = vec2(UV.x * 2.0, UV.y * 4.0);
	float row = floor(plank_uv.y);
	plank_uv.x += mod(row, 2.0) * 0.5;
	vec2 plank_id = floor(plank_uv);
	vec2 within = fract(plank_uv);
	float edge_distance = min(min(within.x, 1.0 - within.x), min(within.y, 1.0 - within.y));
	float seam = 1.0 - smoothstep(0.018, 0.045, edge_distance);

	float variation = hash(plank_id + vec2(row, 0.0));
	float flowing_grain = sin(within.x * 72.0 + sin(within.y * 9.0) * 3.0 + variation * 5.0);
	float fine_grain = sin(within.x * 190.0 + within.y * 17.0) * 0.5;
	float grain = flowing_grain * 0.035 + fine_grain * 0.014;
	vec3 light_oak = vec3(0.61, 0.36, 0.17);
	vec3 plank_color = light_oak + vec3((variation - 0.5) * 0.11 + grain, grain * 0.65, grain * 0.25);
	ALBEDO = mix(plank_color, vec3(0.105, 0.052, 0.022), seam * 0.88);
	ROUGHNESS = 0.68;
}
"""),
		create_shader_material("""
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;
void fragment() {
	// 面板仅保留极淡的蓝色和光点；十二条棱使用独立实体渲染。
	float dot_a = 1.0 - smoothstep(0.010, 0.032, length(UV - vec2(0.23, 0.71)));
	float dot_b = 1.0 - smoothstep(0.008, 0.026, length(UV - vec2(0.68, 0.31)));
	float dot_c = 1.0 - smoothstep(0.006, 0.021, length(UV - vec2(0.79, 0.76)));
	float twinkle_a = 0.68 + sin(TIME * 2.1) * 0.32;
	float twinkle_b = 0.70 + sin(TIME * 1.7 + 2.4) * 0.30;
	float sparkle = max(dot_a * twinkle_a, max(dot_b * twinkle_b, dot_c * 0.72));

	ALBEDO = mix(vec3(0.25, 0.62, 0.76), vec3(1.0), sparkle);
	EMISSION = vec3(0.75, 0.92, 1.0) * sparkle * 0.8;
	ALPHA = max(0.028, sparkle * 0.76);
	METALLIC = 0.02;
	ROUGHNESS = 0.08;
}
""")
	]
	glass_edge_material = create_shader_material("""
shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	vec3 ice_blue = vec3(0.48, 0.82, 1.0);
	vec3 clean_white = vec3(0.96, 0.99, 1.0);
	float shine = 0.55 + 0.45 * abs(NORMAL.y);
	ALBEDO = mix(ice_blue, clean_white, shine);
	EMISSION = mix(ice_blue, clean_white, 0.72) * 0.24;
}
""")
	door_material = create_shader_material("""
shader_type spatial;
float hash(float n) { return fract(sin(n * 91.731) * 43758.5453); }
void fragment() {
	float board = floor(UV.x * 5.0);
	float within_board = fract(UV.x * 5.0);
	float seam = 1.0 - smoothstep(0.025, 0.065, min(within_board, 1.0 - within_board));
	float board_tone = (hash(board) - 0.5) * 0.10;
	float grain = sin(UV.y * 95.0 + sin(UV.x * 22.0) * 2.5) * 0.026;
	vec3 oak = vec3(0.58, 0.31, 0.135) + vec3(board_tone + grain, board_tone * 0.55 + grain * 0.55, grain * 0.25);

	// 两块嵌板的深色轮廓，和普通木方块使用同一暖棕色系。
	vec2 upper = abs((UV - vec2(0.5, 0.70)) / vec2(0.34, 0.17));
	vec2 lower = abs((UV - vec2(0.5, 0.30)) / vec2(0.34, 0.19));
	float upper_frame = smoothstep(0.78, 0.84, max(upper.x, upper.y)) - smoothstep(0.94, 1.0, max(upper.x, upper.y));
	float lower_frame = smoothstep(0.78, 0.84, max(lower.x, lower.y)) - smoothstep(0.94, 1.0, max(lower.x, lower.y));
	float frame = clamp(upper_frame + lower_frame, 0.0, 1.0);
	ALBEDO = mix(oak, vec3(0.25, 0.105, 0.038), max(seam * 0.72, frame * 0.82));
	ROUGHNESS = 0.72;
}
""")
	var handle := StandardMaterial3D.new()
	handle.albedo_color = Color("#d6b56f")
	handle.metallic = 0.72
	handle.roughness = 0.25
	door_handle_material = handle
	var scaffold := StandardMaterial3D.new()
	scaffold.albedo_color = Color("#d3a04c")
	scaffold.roughness = 0.82
	scaffold_material = scaffold
	var furnace_opening := StandardMaterial3D.new()
	furnace_opening.albedo_color = Color("#17191c")
	furnace_opening.roughness = 0.98
	furnace_opening_material = furnace_opening
	var furnace_trim := StandardMaterial3D.new()
	furnace_trim.albedo_color = Color("#55595d")
	furnace_trim.roughness = 0.92
	furnace_trim_material = furnace_trim
	# 门和脚手架各自使用专用几何，这两个占位让数组索引与材料编号保持一致。
	block_materials.append(door_material)
	block_materials.append(scaffold_material)
	block_materials.append(create_shader_material("""
shader_type spatial;
varying vec3 local_pos;
varying vec3 local_normal;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}
void fragment() {
	vec2 horizontal = abs(local_normal.x) > 0.5 ? local_pos.zy : local_pos.xy;
	float soil_noise = (hash(floor(horizontal * 12.0)) - 0.5) * 0.10;
	vec3 soil = vec3(0.34, 0.19, 0.085) + vec3(soil_noise, soil_noise * 0.72, soil_noise * 0.38);
	if (local_normal.y > 0.55) {
		float top_noise = (hash(floor(local_pos.xz * 14.0)) - 0.5) * 0.09;
		float tiny_blades = sin(local_pos.x * 83.0) * sin(local_pos.z * 71.0) * 0.025;
		ALBEDO = vec3(0.18, 0.47, 0.14) + vec3(top_noise + tiny_blades, top_noise * 1.15 + tiny_blades, top_noise * 0.48);
	} else if (local_normal.y < -0.55) {
		ALBEDO = soil;
	} else {
		float side_axis = abs(local_normal.x) > 0.5 ? local_pos.z : local_pos.x;
		float uneven_edge = 0.24 + hash(vec2(floor(side_axis * 10.0), 4.0)) * 0.12;
		float grass_mask = smoothstep(uneven_edge - 0.025, uneven_edge + 0.025, local_pos.y);
		float grass_noise = (hash(floor(vec2(side_axis, local_pos.y) * 13.0)) - 0.5) * 0.07;
		vec3 side_grass = vec3(0.17, 0.44, 0.13) + vec3(grass_noise, grass_noise * 1.1, grass_noise * 0.4);
		ALBEDO = mix(soil, side_grass, grass_mask);
	}
	ROUGHNESS = 0.96;
}
"""))
	block_materials.append(create_shader_material("""
shader_type spatial;
varying vec3 local_pos;
float hash(vec3 p) { return fract(sin(dot(p, vec3(17.1, 91.7, 43.3))) * 43758.5453); }
void vertex() { local_pos = VERTEX; }
void fragment() {
	float grain = (hash(floor(local_pos * 14.0)) - 0.5) * 0.12;
	ALBEDO = vec3(0.34, 0.20, 0.10) + vec3(grain, grain * 0.68, grain * 0.34);
	ROUGHNESS = 0.97;
}
"""))
	block_materials.append(create_shader_material("""
shader_type spatial;
varying vec3 local_pos;
float hash(vec3 p) { return fract(sin(dot(p, vec3(31.7, 12.9, 74.1))) * 43758.5453); }
void vertex() { local_pos = VERTEX; }
void fragment() {
	float grain = (hash(floor(local_pos * 18.0)) - 0.5) * 0.10;
	ALBEDO = vec3(0.72, 0.62, 0.39) + vec3(grain, grain * 0.92, grain * 0.62);
	ROUGHNESS = 0.93;
}
"""))
	block_materials.append(create_shader_material("""
shader_type spatial;
varying vec3 local_normal;
varying vec3 local_pos;
float hash(vec3 p) { return fract(sin(dot(p, vec3(31.7, 67.3, 13.1))) * 43758.5453); }
void vertex() { local_normal = NORMAL; local_pos = VERTEX; }
void fragment() {
	// 大块、低对比度的灰色石面；没有裂缝或勾边。
	float patch = (hash(floor((local_pos + vec3(0.5)) * 4.0)) - 0.5) * 0.07;
	vec3 stone = vec3(0.41, 0.42, 0.43) + vec3(patch);
	if (local_normal.y > 0.55) {
		stone += vec3(0.045);
	} else if (abs(local_normal.x) > 0.55) {
		stone -= vec3(0.025);
	}
	ALBEDO = stone;
	ROUGHNESS = 0.96;
}
"""))
	block_materials.append(create_shader_material("""
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;
varying vec3 world_pos;
instance uniform vec2 flow_direction = vec2(0.0, 0.0);
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (VERTEX.y > 0.45) {
		VERTEX.y += sin(world_pos.x * 3.2 + TIME * 1.7) * 0.018 + cos(world_pos.z * 3.7 + TIME * 1.3) * 0.014;
	}
}
void fragment() {
	vec2 direction = length(flow_direction) > 0.01 ? normalize(flow_direction) : normalize(vec2(0.8, 0.35));
	vec2 across = vec2(-direction.y, direction.x);
	float along_coord = dot(world_pos.xz, direction);
	float across_coord = dot(world_pos.xz, across);
	float flowing_bands = sin(along_coord * 10.0 - TIME * 5.2 + sin(across_coord * 6.0) * 0.8);
	float small_ripples = sin(along_coord * 19.0 - TIME * 7.0 + across_coord * 3.0) * 0.5;
	float ripple = flowing_bands * 0.035 + small_ripples * 0.016;
	ALBEDO = vec3(0.07, 0.40, 0.69) + vec3(ripple, ripple * 1.2, ripple * 1.35);
	NORMAL_MAP = vec3(0.5 + direction.x * flowing_bands * 0.06, 0.5 + direction.y * flowing_bands * 0.06, 1.0);
	ALPHA = 0.48;
	ROUGHNESS = 0.18;
	METALLIC = 0.04;
}
"""))
	block_materials.append(create_shader_material("""
shader_type spatial;
void fragment() {
	vec2 brick_uv = vec2(UV.x * 4.0, UV.y * 8.0);
	float row = floor(brick_uv.y);
	brick_uv.x += mod(row, 2.0) * 0.5;
	vec2 cell = fract(brick_uv);
	float mortar = 1.0 - smoothstep(0.035, 0.075, min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y)));
	float variation = sin(floor(brick_uv.x) * 12.3 + row * 7.1) * 0.035;
	vec3 brick = vec3(0.52, 0.20, 0.15) + vec3(variation);
	ALBEDO = mix(brick, vec3(0.66, 0.61, 0.53), mortar);
	ROUGHNESS = 0.9;
}
"""))
	block_materials.append(create_shader_material("""
shader_type spatial;
render_mode cull_back;
void fragment() {
	vec3 glowing_center = vec3(1.0, 0.92, 0.58);
	ALBEDO = glowing_center;
	EMISSION = glowing_center * 1.65;
	ROUGHNESS = 0.24;
}
"""))
	var lamp_edges := StandardMaterial3D.new()
	lamp_edges.albedo_color = Color("#080a0c")
	lamp_edges.roughness = 0.9
	lamp_edge_material = lamp_edges
	leaf_material = create_shader_material("""
shader_type spatial;
varying vec3 local_pos;
float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 45.164))) * 43758.5453); }
void vertex() { local_pos = VERTEX; }
void fragment() {
	float pixel = hash(floor(local_pos * 12.0));
	vec3 dark_leaf = vec3(0.08, 0.29, 0.10);
	vec3 light_leaf = vec3(0.18, 0.48, 0.16);
	ALBEDO = mix(dark_leaf, light_leaf, pixel);
	ROUGHNESS = 0.94;
}
""")
	block_materials.append(leaf_material)
	block_materials.append(create_shader_material("""
shader_type spatial;
varying vec3 local_pos;
varying vec3 local_normal;
void vertex() { local_pos = VERTEX; local_normal = NORMAL; }
void fragment() {
	if (abs(local_normal.y) > 0.55) {
		float rings = sin(length(local_pos.xz) * 42.0) * 0.045;
		ALBEDO = vec3(0.47, 0.30, 0.16) + vec3(rings, rings * 0.65, rings * 0.30);
	} else {
		float bark = sin(local_pos.y * 31.0 + sin((local_pos.x + local_pos.z) * 13.0)) * 0.038;
		ALBEDO = vec3(0.30, 0.19, 0.105) + vec3(bark, bark * 0.62, bark * 0.25);
	}
	ROUGHNESS = 0.94;
}
"""))
	# 上方材质按创建依赖分组生成，这里统一整理为物品编号顺序。
	var generated_materials := block_materials.duplicate()
	block_materials[6] = generated_materials[9]   # 水
	block_materials[7] = generated_materials[10]  # 红砖
	block_materials[8] = generated_materials[11]  # 灯块
	block_materials[9] = generated_materials[12]  # 树叶
	block_materials[10] = generated_materials[13] # 原木
	block_materials[11] = generated_materials[6]  # 泥土
	block_materials[12] = generated_materials[7]  # 沙子
	block_materials[13] = generated_materials[8]  # 熔炉
	var meat_material := StandardMaterial3D.new()
	meat_material.albedo_color = Color("#a74335")
	meat_material.roughness = 0.86
	block_materials.append(meat_material)


func create_shader_material(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func create_player() -> void:
	player = PlayerScript.new()
	add_child(player)
	player.block_place_requested.connect(place_block)
	player.block_remove_requested.connect(remove_block)
	player.block_interact_requested.connect(interact_with_block)
	player.animal_attack_requested.connect(attack_animal)
	player.consume_requested.connect(consume_meat)
	player.backpack_requested.connect(toggle_backpack)
	player.scaffold_check = is_player_near_scaffold


func create_destructible_ground(center: Vector3i) -> void:
	# 初始地面立即生成；移动后的扩展分帧处理，避免一次创建数百个碰撞体造成卡顿。
	const SURFACE_RADIUS := 26
	var immediate := generated_ground_cells.is_empty()
	last_ground_center = Vector3i(center.x, 0, center.z)
	for x in range(center.x - SURFACE_RADIUS, center.x + SURFACE_RADIUS + 1):
		for z in range(center.z - SURFACE_RADIUS, center.z + SURFACE_RADIUS + 1):
			var cell := Vector3i(x, 0, z)
			if generated_ground_cells.has(cell):
				continue
			if occupied.has(cell):
				continue
			generated_ground_cells[cell] = true
			if immediate:
				create_block(cell, 5, true)
			else:
				terrain_generation_queue.append({"cell": cell, "material": 5})


func ensure_subsurface_area(surface_cell: Vector3i) -> void:
	# 中心承重柱立即生成；周围 7×7 地下结构分帧补齐，既连续又不会瞬时卡顿。
	const AREA_RADIUS := 3
	for x_offset in range(-AREA_RADIUS, AREA_RADIUS + 1):
		for z_offset in range(-AREA_RADIUS, AREA_RADIUS + 1):
			for y in range(-1, -4, -1):
				var cell := Vector3i(surface_cell.x + x_offset, y, surface_cell.z + z_offset)
				if generated_ground_cells.has(cell) or occupied.has(cell):
					continue
				generated_ground_cells[cell] = true
				var material_index := 5 if y == -1 else 0
				if x_offset == 0 and z_offset == 0:
					create_block(cell, material_index, true)
				else:
					terrain_generation_queue.append({"cell": cell, "material": material_index})


func process_terrain_generation_queue() -> void:
	const BLOCKS_PER_FRAME := 48
	for index in range(mini(BLOCKS_PER_FRAME, terrain_generation_queue.size())):
		var entry: Dictionary = terrain_generation_queue.pop_back()
		var cell: Vector3i = entry.cell
		if not occupied.has(cell):
			create_block(cell, int(entry.material), true)


func create_bedrock_floor() -> void:
	# 黑色底层位于第四层石头正下方，只负责阻挡坠落，永远不能挖除。
	var bedrock := StaticBody3D.new()
	bedrock.name = "BlackBedrock"
	bedrock.position.y = -3.5
	bedrock.set_meta("removable", false)

	var collision := CollisionShape3D.new()
	var boundary := WorldBoundaryShape3D.new()
	boundary.plane = Plane(Vector3.UP, 0.0)
	collision.shape = boundary
	bedrock.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(2000, 2000)
	var black_material := StandardMaterial3D.new()
	black_material.albedo_color = Color("#08090b")
	black_material.roughness = 1.0
	plane_mesh.material = black_material
	mesh_instance.mesh = plane_mesh
	bedrock.add_child(mesh_instance)
	add_child(bedrock)


func create_natural_landscape() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 724031
	# 低矮草丘。
	for hill_index in range(9):
		var center := Vector3i(rng.randi_range(-18, 18), 1, rng.randi_range(-18, 18))
		if Vector2(center.x, center.z).length() < 8.0:
			continue
		for offset: Vector3i in [Vector3i.ZERO, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			var cell: Vector3i = center + offset
			if not occupied.has(cell):
				create_block(cell, 5, true)

	# 可采集石堆。
	for rock_index in range(14):
		var center := Vector3i(rng.randi_range(-19, 19), 1, rng.randi_range(-19, 19))
		if Vector2(center.x, center.z).length() < 7.0:
			continue
		for offset: Vector3i in [Vector3i.ZERO, Vector3i.LEFT, Vector3i.BACK]:
			var cell: Vector3i = center + offset
			if not occupied.has(cell) and rng.randf() > 0.18:
				create_block(cell, 0, true)

	# 方块树与灌木；原木和树叶分别进入各自库存。
	for tree_index in range(13):
		var base := Vector3i(rng.randi_range(-18, 18), 1, rng.randi_range(-18, 18))
		if Vector2(base.x, base.z).length() < 8.0 or occupied.has(base):
			continue
		var trunk_height := rng.randi_range(3, 5)
		for y in range(1, trunk_height + 1):
			create_block(Vector3i(base.x, y, base.z), 10, true)
		var crown_y := trunk_height + 1
		for x_offset in range(-1, 2):
			for z_offset in range(-1, 2):
				if abs(x_offset) == 1 and abs(z_offset) == 1 and rng.randf() < 0.45:
					continue
				var leaf_cell := Vector3i(base.x + x_offset, crown_y, base.z + z_offset)
				if not occupied.has(leaf_cell):
					create_block(leaf_cell, 9, true)
		for offset: Vector3i in [Vector3i.ZERO, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			var leaf_cell: Vector3i = Vector3i(base.x, crown_y + 1, base.z) + offset
			if not occupied.has(leaf_cell):
				create_block(leaf_cell, 9, true)

	for bush_index in range(18):
		var bush := Vector3i(rng.randi_range(-19, 19), 1, rng.randi_range(-19, 19))
		if Vector2(bush.x, bush.z).length() > 6.0 and not occupied.has(bush):
			create_block(bush, 9, true)
	create_distant_natural_regions(rng)


func create_distant_natural_regions(rng: RandomNumberGenerator) -> void:
	var region_centers: Array[Vector3i] = [
		Vector3i(-55, 0, -45), Vector3i(50, 0, -52),
		Vector3i(-65, 0, 28), Vector3i(62, 0, 36),
		Vector3i(0, 0, -72), Vector3i(78, 0, -4),
		Vector3i(-82, 0, -6), Vector3i(15, 0, 68),
	]
	for region_index in region_centers.size():
		var center := region_centers[region_index]
		generated_region_centers.append(Vector3(center))
		# 每个区域都有独立的小型起伏草丘。
		for x_offset in range(-3, 4):
			for z_offset in range(-3, 4):
				var distance: int = abs(x_offset) + abs(z_offset)
				if distance <= 4 and rng.randf() > 0.16:
					var height := 1 if distance >= 3 else (2 if rng.randf() > 0.30 else 1)
					for y in range(height):
						var cell := center + Vector3i(x_offset, y, z_offset)
						if not occupied.has(cell):
							create_block(cell, 5, true)

		match region_index % 3:
			0:
				# 林地区：多棵高低不一的树。
				for tree_index in range(8):
					var base := center + Vector3i(rng.randi_range(-9, 9), 0, rng.randi_range(-9, 9))
					create_natural_tree_at(base, rng)
			1:
				# 岩地区：不规则石柱和散落岩块。
				for rock_index in range(11):
					var base := center + Vector3i(rng.randi_range(-10, 10), 0, rng.randi_range(-10, 10))
					var height := rng.randi_range(1, 4)
					for y in range(height):
						var cell := base + Vector3i(0, y, 0)
						if not occupied.has(cell):
							create_block(cell, 0, true)
					if rng.randf() > 0.45:
						var side := base + Vector3i.RIGHT
						if not occupied.has(side):
							create_block(side, 0, true)
			2:
				# 灌木草地区：低矮叶块混合少量树木。
				for bush_index in range(18):
					var bush := center + Vector3i(rng.randi_range(-11, 11), 0, rng.randi_range(-11, 11))
					if not occupied.has(bush):
						create_block(bush, 9, true)
				for tree_index in range(3):
					var base := center + Vector3i(rng.randi_range(-9, 9), 0, rng.randi_range(-9, 9))
					create_natural_tree_at(base, rng)


func create_natural_tree_at(base: Vector3i, rng: RandomNumberGenerator) -> void:
	if occupied.has(base):
		return
	var trunk_height := rng.randi_range(3, 5)
	for y in range(trunk_height):
		create_block(base + Vector3i(0, y, 0), 10, true)
	var crown := base + Vector3i(0, trunk_height, 0)
	for x_offset in range(-1, 2):
		for z_offset in range(-1, 2):
			if abs(x_offset) == 1 and abs(z_offset) == 1 and rng.randf() < 0.38:
				continue
			var cell := crown + Vector3i(x_offset, 0, z_offset)
			if not occupied.has(cell):
				create_block(cell, 9, true)
	for offset: Vector3i in [Vector3i.ZERO, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		var cell := crown + Vector3i.UP + offset
		if not occupied.has(cell):
			create_block(cell, 9, true)


func spawn_dynamic_natural_region(center: Vector3i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_msec() + center.x * 97 + center.z * 193
	generated_region_centers.append(Vector3(center))
	for x_offset in range(-3, 4):
		for z_offset in range(-3, 4):
			if abs(x_offset) + abs(z_offset) <= 4 and rng.randf() > 0.20:
				var cell := center + Vector3i(x_offset, 0, z_offset)
				if not occupied.has(cell):
					create_block(cell, 5, true)
	for tree_index in range(5):
		var tree_base := center + Vector3i(rng.randi_range(-8, 8), 0, rng.randi_range(-8, 8))
		create_natural_tree_at(tree_base, rng)
	for rock_index in range(7):
		var rock_base := center + Vector3i(rng.randi_range(-9, 9), 0, rng.randi_range(-9, 9))
		for y in range(rng.randi_range(1, 3)):
			var cell := rock_base + Vector3i(0, y, 0)
			if not occupied.has(cell):
				create_block(cell, 0, true)
	for bush_index in range(8):
		var bush := center + Vector3i(rng.randi_range(-9, 9), 0, rng.randi_range(-9, 9))
		if not occupied.has(bush):
			create_block(bush, 9, true)


func spawn_natural_pond(center: Vector3i) -> bool:
	# 椭圆基础上加入平缓起伏，形成连续但不规则的自然岸线。
	var footprint: Dictionary = {}
	var depths: Dictionary = {}
	for x_offset in range(-6, 7):
		for z_offset in range(-5, 6):
			var normalized := Vector2(float(x_offset) / 5.7, float(z_offset) / 4.6)
			var radial := normalized.length()
			var edge_variation := sin(float(x_offset) * 1.73 + float(center.x) * 0.07) * 0.07
			edge_variation += cos(float(z_offset) * 1.31 + float(center.z) * 0.05) * 0.06
			if radial <= 0.92 + edge_variation:
				var offset := Vector2i(x_offset, z_offset)
				footprint[offset] = true
				# 岸边一格深，中部两格深，中心局部三格深。
				depths[offset] = 3 if radial < 0.34 else (2 if radial < 0.69 else 1)

	var bank_cells: Dictionary = {}
	for offset: Vector2i in footprint.keys():
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var bank_offset := offset + direction
			if not footprint.has(bank_offset):
				bank_cells[bank_offset] = true

	# 不覆盖已有景观；三个初始池塘都选择在空旷区域。
	for offset: Vector2i in footprint.keys():
		if occupied.has(center + Vector3i(offset.x, 0, offset.y)):
			return false
	for offset: Vector2i in bank_cells.keys():
		if occupied.has(center + Vector3i(offset.x, 0, offset.y)):
			return false

	# 每一列从水底一直填到黑色底层，深水和浅水之间也不会出现空洞。
	for offset: Vector2i in footprint.keys():
		var depth: int = depths[offset]
		for water_level in range(0, -depth, -1):
			create_water(center + Vector3i(offset.x, water_level, offset.y), 0, true, 0, Vector2.ZERO, 1.0)
		for bottom_level in range(-depth, -4, -1):
			var bottom_material := 12 if bottom_level == -depth and depth <= 2 else 0
			create_block(center + Vector3i(offset.x, bottom_level, offset.y), bottom_material, true)

	# 沙质岸边和地下侧壁完整围住水体。
	for offset: Vector2i in bank_cells.keys():
		for wall_level in range(0, -4, -1):
			var wall_material := 12 if wall_level == 0 else (11 if wall_level == -1 else 0)
			create_block(center + Vector3i(offset.x, wall_level, offset.y), wall_material, true)

	generated_water_centers.append(Vector3(center))
	return true


func choose_unseen_generation_position(minimum_spacing: float) -> Vector3i:
	var camera_forward: Vector3 = -player.camera.global_transform.basis.z
	camera_forward.y = 0
	if camera_forward.length_squared() < 0.01:
		camera_forward = -player.global_transform.basis.z
		camera_forward.y = 0
	camera_forward = camera_forward.normalized()
	var behind := -camera_forward
	var fallback := Vector3i.ZERO
	for attempt in range(36):
		var direction := behind.rotated(Vector3.UP, randf_range(-1.25, 1.25))
		var distance := randf_range(35.0, 95.0)
		var candidate := player.global_position + direction * distance
		fallback = Vector3i(roundi(candidate.x), 0, roundi(candidate.z))
		var separated := true
		for existing_center in generated_region_centers:
			if Vector2(candidate.x - existing_center.x, candidate.z - existing_center.z).length() < minimum_spacing:
				separated = false
				break
		if separated:
			for water_center in generated_water_centers:
				if Vector2(candidate.x - water_center.x, candidate.z - water_center.z).length() < minimum_spacing:
					separated = false
					break
		if separated and not occupied.has(fallback):
			return fallback
	return fallback


func create_block(grid_position: Vector3i, material_index: int, removable := true, visual_material: Material = null) -> StaticBody3D:
	var block := StaticBody3D.new()
	block.position = Vector3(grid_position)
	block.set_meta("grid_position", grid_position)
	block.set_meta("material_index", material_index)
	block.set_meta("removable", removable)
	if material_index == 13:
		block.set_meta("is_furnace", true)

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * (0.84 if material_index == 8 else 1.0)
	box.material = visual_material if visual_material else block_materials[material_index]
	mesh_instance.mesh = box
	block.add_child(mesh_instance)
	if material_index == 2:
		create_glass_edges(block)
	elif material_index == 8:
		create_lamp_edges(block)
		var light := OmniLight3D.new()
		light.light_color = Color("#ffd27a")
		light.light_energy = 1.15
		light.omni_range = 4.5
		light.shadow_enabled = false
		block.add_child(light)
	elif material_index == 13:
		create_furnace_details(block)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	collision.shape = shape
	block.add_child(collision)
	add_child(block)
	occupied[grid_position] = block
	return block


func create_glass_edges(block: Node3D) -> void:
	const THICKNESS := 0.035
	const OFFSET := 0.4825
	# 四条 X 轴棱。
	for y_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			add_glass_edge(block, Vector3(1.0, THICKNESS, THICKNESS), Vector3(0, y_sign * OFFSET, z_sign * OFFSET))
	# 四条 Y 轴棱。
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			add_glass_edge(block, Vector3(THICKNESS, 1.0, THICKNESS), Vector3(x_sign * OFFSET, 0, z_sign * OFFSET))
	# 四条 Z 轴棱。
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			add_glass_edge(block, Vector3(THICKNESS, THICKNESS, 1.0), Vector3(x_sign * OFFSET, y_sign * OFFSET, 0))


func add_glass_edge(parent: Node3D, size: Vector3, edge_position: Vector3) -> void:
	var edge := MeshInstance3D.new()
	var edge_mesh := BoxMesh.new()
	edge_mesh.size = size
	edge_mesh.material = glass_edge_material
	edge.mesh = edge_mesh
	edge.position = edge_position
	parent.add_child(edge)


func create_lamp_edges(block: Node3D) -> void:
	const THICKNESS := 0.085
	const OFFSET := 0.4575
	for y_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			add_lamp_edge(block, Vector3(1.0, THICKNESS, THICKNESS), Vector3(0, y_sign * OFFSET, z_sign * OFFSET))
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			add_lamp_edge(block, Vector3(THICKNESS, 1.0, THICKNESS), Vector3(x_sign * OFFSET, 0, z_sign * OFFSET))
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			add_lamp_edge(block, Vector3(THICKNESS, THICKNESS, 1.0), Vector3(x_sign * OFFSET, y_sign * OFFSET, 0))


func add_lamp_edge(parent: Node3D, size: Vector3, edge_position: Vector3) -> void:
	var edge := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = lamp_edge_material
	edge.mesh = mesh
	edge.position = edge_position
	parent.add_child(edge)


func create_furnace_details(parent: Node3D) -> void:
	# 炉口是局部的立体结构，不再用一圈边框包住整个面。
	add_preview_box(parent, Vector3(0.54, 0.34, 0.025), Vector3(0, -0.10, 0.508), furnace_opening_material)
	# 炉檐稍微向外突出，投下阴影，让开口看起来是凹进去的。
	add_preview_box(parent, Vector3(0.66, 0.10, 0.105), Vector3(0, 0.13, 0.515), furnace_trim_material)
	# 下方托台比炉口略宽，但不连接方块四周的棱。
	add_preview_box(parent, Vector3(0.64, 0.09, 0.12), Vector3(0, -0.32, 0.525), furnace_trim_material)


func place_block(hit_position: Vector3) -> void:
	if selected_material >= 14:
		show_message("肉不能作为方块放置")
		return
	var grid_position := Vector3i(
		roundi(hit_position.x),
		roundi(hit_position.y),
		roundi(hit_position.z)
	)
	if occupied.has(grid_position):
		show_message("这里已经有方块了")
		return
	if selected_material == 3 and occupied.has(grid_position + Vector3i.UP):
		show_message("门上方需要留出一格空间")
		return
	if inventory[selected_material] <= 0:
		show_message("背包里没有这种材料")
		return
	var player_grid := Vector3i(roundi(player.position.x), roundi(player.position.y), roundi(player.position.z))
	if grid_position.x == player_grid.x and grid_position.z == player_grid.z and grid_position.y in [player_grid.y, player_grid.y + 1]:
		show_message("不能把方块放在自己身上")
		return
	inventory[selected_material] -= 1
	if selected_material == 3:
		create_door(grid_position)
	elif selected_material == 4:
		create_scaffold(grid_position)
	elif selected_material == 6:
		var water_source := create_water(grid_position, 0, true, 0, Vector2.ZERO, 1.0)
		var source_id: int = water_source.get_meta("flow_source_id")
		queue_water_spread(grid_position, 0, source_id, Vector2.ZERO)
	else:
		create_block(grid_position, selected_material)
	update_ui()


func remove_block(collider: Node) -> void:
	if not is_instance_valid(collider):
		return
	if not collider.has_meta("grid_position"):
		return
	if not collider.get_meta("removable", false):
		show_message("黑色底层无法挖掘")
		return
	var material_index: int = collider.get_meta("material_index")
	if material_index == 6:
		if float(collider.get_meta("water_amount", 0.0)) < 0.995:
			show_message("水位不足一格，无法汲取")
			return
		inventory[material_index] += 1
		remove_water_network(collider.get_meta("flow_source_id"))
		update_ui()
		return
	var grid_position: Vector3i = collider.get_meta("grid_position")
	if grid_position.y == 0 and generated_ground_cells.has(grid_position):
		# 先生成下方实体碰撞，再移除表层，杜绝一帧内掉进尚未加载的地下。
		ensure_subsurface_area(grid_position)
	if collider.has_meta("occupied_cells"):
		for cell: Vector3i in collider.get_meta("occupied_cells"):
			occupied.erase(cell)
	else:
		occupied.erase(grid_position)
	create_item_drop(material_index, 1, Vector3(grid_position) + Vector3.UP * 0.35)
	collider.queue_free()
	update_ui()


func create_item_drop(item_index: int, amount: int, drop_position: Vector3) -> void:
	var item_drop := ItemDropScript.new()
	item_drop.setup(item_index, amount, block_materials[item_index])
	add_child(item_drop)
	item_drop.global_position = drop_position


func update_item_drops(delta: float) -> void:
	var pickup_target := player.global_position + Vector3.UP * 0.65
	for item_drop: Node in get_tree().get_nodes_in_group("item_drops"):
		if not is_instance_valid(item_drop) or not bool(item_drop.call("can_be_collected")):
			continue
		if item_drop.global_position.distance_to(pickup_target) > 2.8 and not bool(item_drop.get("being_collected")):
			continue
		item_drop.call("attract_to", pickup_target, delta)
		if item_drop.global_position.distance_to(pickup_target) <= 0.55:
			var item_index: int = int(item_drop.get("item_index"))
			var amount: int = int(item_drop.get("amount"))
			inventory[item_index] += amount
			show_message("拾取%s ×%d" % [MATERIAL_NAMES[item_index], amount])
			item_drop.queue_free()
			update_ui()


func update_mining(delta: float) -> void:
	var can_mine := not backpack_panel.visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var holding := can_mine and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not holding:
		mining_release_required = false
	var candidate: Node = null
	if player.ray.is_colliding():
		candidate = player.ray.get_collider()
	if not is_instance_valid(candidate) or not candidate.has_meta("grid_position") or not candidate.get_meta("removable", false):
		candidate = null

	if holding and candidate and not mining_release_required:
		if candidate != mining_target:
			mining_target = candidate
			mining_progress = 0.0
			mining_overlay.position = Vector3(candidate.get_meta("grid_position"))
			mining_overlay.visible = true
		var material_index: int = mining_target.get_meta("material_index")
		mining_progress += delta / get_material_hardness(material_index)
		mining_overlay.set_instance_shader_parameter("crack_stage", clampf(mining_progress, 0.0, 1.0))
		if mining_progress >= 1.0:
			var completed_target := mining_target
			clear_mining_progress()
			remove_block(completed_target)
			# 一次按住只破坏一个方块，防止准星自动向下连续挖穿多层地面。
			mining_release_required = true
	elif mining_target:
		var material_index: int = mining_target.get_meta("material_index", 0) if is_instance_valid(mining_target) else 0
		mining_progress = maxf(0.0, mining_progress - delta / (get_material_hardness(material_index) * 0.55))
		if mining_progress <= 0.0:
			clear_mining_progress()
		else:
			mining_overlay.set_instance_shader_parameter("crack_stage", mining_progress)


func get_material_hardness(material_index: int) -> float:
	var hardness := [1.45, 0.95, 0.58, 0.75, 0.34, 0.42, 0.20, 1.18, 0.82, 0.24, 1.08, 0.40, 0.32, 1.55]
	return hardness[clampi(material_index, 0, hardness.size() - 1)]


func clear_mining_progress() -> void:
	mining_target = null
	mining_progress = 0.0
	mining_overlay.visible = false


func create_door(grid_position: Vector3i) -> StaticBody3D:
	var door := StaticBody3D.new()
	door.name = "WoodDoor"
	var snapped_yaw := roundf(player.rotation.y / (PI * 0.5)) * (PI * 0.5)
	door.rotation.y = snapped_yaw
	door.position = Vector3(grid_position) + Vector3(-0.45, 0, 0).rotated(Vector3.UP, snapped_yaw)
	door.set_meta("grid_position", grid_position)
	door.set_meta("occupied_cells", [grid_position, grid_position + Vector3i.UP])
	door.set_meta("material_index", 3)
	door.set_meta("removable", true)
	door.set_meta("is_door", true)
	door.set_meta("is_open", false)
	door.set_meta("closed_yaw", snapped_yaw)

	var panel := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(0.9, 1.9, 0.09)
	panel_mesh.material = door_material
	panel.mesh = panel_mesh
	panel.position = Vector3(0.45, 0.5, 0)
	door.add_child(panel)

	var collision := CollisionShape3D.new()
	var panel_shape := BoxShape3D.new()
	panel_shape.size = Vector3(0.9, 1.9, 0.10)
	collision.shape = panel_shape
	collision.position = Vector3(0.45, 0.5, 0)
	door.add_child(collision)

	for side in [-1.0, 1.0]:
		var knob := MeshInstance3D.new()
		var knob_mesh := SphereMesh.new()
		knob_mesh.radius = 0.055
		knob_mesh.height = 0.11
		knob_mesh.material = door_handle_material
		knob.mesh = knob_mesh
		knob.position = Vector3(0.72, 0.48, side * 0.075)
		door.add_child(knob)

	add_child(door)
	occupied[grid_position] = door
	occupied[grid_position + Vector3i.UP] = door
	return door


func create_scaffold(grid_position: Vector3i) -> StaticBody3D:
	var scaffold := StaticBody3D.new()
	scaffold.name = "Scaffold"
	scaffold.position = Vector3(grid_position)
	scaffold.set_meta("grid_position", grid_position)
	scaffold.set_meta("material_index", 4)
	scaffold.set_meta("removable", true)

	# 四根立柱。
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			add_scaffold_beam(scaffold, Vector3(0.075, 1.0, 0.075), Vector3(x_sign * 0.43, 0, z_sign * 0.43))
	# 上下两层横梁，形成易读的开放式框架。
	for y in [-0.42, 0.42]:
		for z_sign in [-1.0, 1.0]:
			add_scaffold_beam(scaffold, Vector3(0.86, 0.065, 0.065), Vector3(0, y, z_sign * 0.43))
		for x_sign in [-1.0, 1.0]:
			add_scaffold_beam(scaffold, Vector3(0.065, 0.065, 0.86), Vector3(x_sign * 0.43, y, 0))

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	collision.shape = shape
	scaffold.add_child(collision)
	add_child(scaffold)
	occupied[grid_position] = scaffold
	return scaffold


func create_water(grid_position: Vector3i, flow_depth: int, is_source: bool, source_id: int, flow_direction: Vector2, amount: float) -> Area3D:
	var water := Area3D.new()
	if is_source and source_id == 0:
		source_id = water.get_instance_id()
	water.name = "WaterSource" if is_source else "FlowingWater"
	water.position = Vector3(grid_position)
	water.collision_layer = 1
	water.collision_mask = 0
	water.set_meta("grid_position", grid_position)
	water.set_meta("material_index", 6)
	water.set_meta("removable", true)
	water.set_meta("water_source", is_source)
	water.set_meta("flow_depth", flow_depth)
	water.set_meta("flow_source_id", source_id)
	water.set_meta("flow_direction", flow_direction)
	water.set_meta("water_amount", clampf(amount, 0.08, 1.0))
	water.set_meta("source_contributions", {source_id: clampf(amount, 0.08, 1.0)})

	var height := clampf(amount, 0.08, 1.0)
	var mesh_instance := MeshInstance3D.new()
	var water_mesh := BoxMesh.new()
	water_mesh.size = Vector3(1.0, height, 1.0)
	water_mesh.material = block_materials[6]
	mesh_instance.mesh = water_mesh
	mesh_instance.position.y = (height - 1.0) * 0.5
	mesh_instance.set_instance_shader_parameter("flow_direction", flow_direction)
	water.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	collision.shape = shape
	water.add_child(collision)
	add_child(water)
	occupied[grid_position] = water
	return water


func queue_water_spread(grid_position: Vector3i, flow_depth: int, source_id: int, incoming_direction: Vector2) -> void:
	var below := grid_position + Vector3i.DOWN
	if grid_position.y > 0:
		if not occupied.has(below) or occupied[below].get_meta("material_index", -1) == 6:
			water_flow_queue.append({"position": below, "depth": flow_depth, "source_id": source_id, "direction": incoming_direction})
			return
	if flow_depth >= 5:
		return
	for direction: Vector3i in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		var next_cell: Vector3i = grid_position + direction
		if not occupied.has(next_cell) or occupied[next_cell].get_meta("material_index", -1) == 6:
			water_flow_queue.append({"position": next_cell, "depth": flow_depth + 1, "source_id": source_id, "direction": Vector2(direction.x, direction.z)})


func process_next_water_flow() -> void:
	if water_flow_queue.is_empty():
		return
	var entry: Dictionary = water_flow_queue.pop_front()
	var grid_position: Vector3i = entry.position
	var flow_depth: int = entry.depth
	var source_id: int = entry.source_id
	var flow_direction: Vector2 = entry.direction
	if grid_position.y < 0:
		return
	var amount := maxf(0.18, 1.0 - flow_depth * 0.16)
	if occupied.has(grid_position):
		var existing: Node = occupied[grid_position]
		if existing.get_meta("material_index", -1) == 6 and merge_water_contribution(existing, source_id, amount):
			queue_water_spread(grid_position, flow_depth, source_id, flow_direction)
		return
	create_water(grid_position, flow_depth, false, source_id, flow_direction, amount)
	queue_water_spread(grid_position, flow_depth, source_id, flow_direction)


func merge_water_contribution(water: Node, source_id: int, amount: float) -> bool:
	var contributions: Dictionary = water.get_meta("source_contributions", {})
	var previous_amount: float = float(contributions.get(source_id, 0.0))
	if amount <= previous_amount + 0.001:
		return false
	contributions[source_id] = amount
	water.set_meta("source_contributions", contributions)
	update_water_height(water)
	return true


func update_water_height(water: Node) -> void:
	var contributions: Dictionary = water.get_meta("source_contributions", {})
	var total := 0.0
	for contribution in contributions.values():
		total += float(contribution)
	var height := clampf(total, 0.08, 1.0)
	water.set_meta("water_amount", height)
	var mesh_instance := water.get_child(0) as MeshInstance3D
	var water_mesh := mesh_instance.mesh as BoxMesh
	water_mesh.size.y = height
	mesh_instance.position.y = (height - 1.0) * 0.5


func remove_water_network(source_id: int) -> void:
	for index in range(water_flow_queue.size() - 1, -1, -1):
		if water_flow_queue[index].get("source_id", -1) == source_id:
			water_flow_queue.remove_at(index)
	var cells_to_remove: Array[Vector3i] = []
	for raw_cell in occupied.keys():
		var cell: Vector3i = raw_cell
		var water_node: Node = occupied[cell]
		if water_node.get_meta("material_index", -1) != 6:
			continue
		var contributions: Dictionary = water_node.get_meta("source_contributions", {})
		if not contributions.has(source_id):
			continue
		contributions.erase(source_id)
		water_node.set_meta("source_contributions", contributions)
		if contributions.is_empty():
			cells_to_remove.append(cell)
		else:
			update_water_height(water_node)
	var draining_nodes: Array[Node] = []
	var tween := create_tween()
	tween.set_parallel(true)
	for cell in cells_to_remove:
		var node_to_remove: Area3D = occupied[cell]
		occupied.erase(cell)
		node_to_remove.collision_layer = 0
		draining_nodes.append(node_to_remove)
		var water_mesh := node_to_remove.get_child(0) as MeshInstance3D
		tween.tween_property(water_mesh, "scale:y", 0.055, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(water_mesh, "position:y", -0.47, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_interval(0.16)
	tween.finished.connect(finish_water_drain.bind(draining_nodes))
	show_message("水源已回收，水流正在退去……")


func finish_water_drain(draining_nodes: Array[Node]) -> void:
	for water_node in draining_nodes:
		if is_instance_valid(water_node):
			water_node.queue_free()


func add_scaffold_beam(parent: Node3D, size: Vector3, beam_position: Vector3) -> void:
	var beam := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = scaffold_material
	beam.mesh = mesh
	beam.position = beam_position
	parent.add_child(beam)


func is_player_near_scaffold(player_position: Vector3) -> bool:
	var center := Vector3i(roundi(player_position.x), roundi(player_position.y), roundi(player_position.z))
	for x_offset in range(-1, 2):
		for y_offset in range(-2, 2):
			for z_offset in range(-1, 2):
				var cell := center + Vector3i(x_offset, y_offset, z_offset)
				if occupied.has(cell) and occupied[cell].get_meta("material_index", -1) == 4:
					return true
	return false


func interact_with_block(collider: Node) -> void:
	if not is_instance_valid(collider):
		return
	if collider.get_meta("is_furnace", false):
		toggle_furnace()
		return
	if not collider.get_meta("is_door", false):
		return
	var is_open: bool = collider.get_meta("is_open")
	var closed_yaw: float = collider.get_meta("closed_yaw")
	var target_yaw := closed_yaw if is_open else closed_yaw + PI * 0.5
	collider.set_meta("is_open", not is_open)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(collider, "rotation:y", target_yaw, 0.22)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			selected_hotbar_slot = int(event.physical_keycode - KEY_1)
			selected_material = hotbar_slot_materials[selected_hotbar_slot]
			player.holding_consumable = selected_material == 14
			update_ui()
			show_selected_material()
			if selected_material == 4:
				show_message("脚手架：靠近后按住空格向上攀爬")


func toggle_backpack() -> void:
	if furnace_panel.visible:
		furnace_panel.visible = false
		player.call("set_input_locked", false)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	backpack_panel.visible = not backpack_panel.visible
	player.call("set_input_locked", backpack_panel.visible)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if backpack_panel.visible else Input.MOUSE_MODE_CAPTURED
	if backpack_panel.visible:
		update_ui()


func select_backpack_material(slot_index: int) -> void:
	var material_index := backpack_slot_materials[slot_index]
	if material_index < 0:
		return
	hotbar_slot_materials[selected_hotbar_slot] = material_index
	selected_material = material_index
	player.holding_consumable = selected_material == 14
	refresh_hotbar_preview(selected_hotbar_slot)
	update_ui()
	show_selected_material()
	show_message("已将%s放入快捷栏第%d格" % [MATERIAL_NAMES[material_index], selected_hotbar_slot + 1])
	toggle_backpack()


func consume_meat() -> void:
	if selected_material != 14 or inventory[14] <= 0:
		show_message("手上没有肉")
		return
	if player_hunger >= 19.99:
		show_message("现在还不饿")
		return
	inventory[14] -= 1
	player_hunger = minf(20.0, player_hunger + 6.0)
	show_message("吃下肉，恢复了饥饿值")
	update_ui()


func craft_recipe(recipe_index: int) -> void:
	match recipe_index:
		0:
			if inventory[10] < 1:
				show_message("合成失败：需要 1 个原木")
				return
			inventory[10] -= 1
			inventory[1] += 4
			show_message("合成完成：获得 4 个木头")
		1:
			if inventory[1] < 6:
				show_message("合成失败：需要 6 个木头")
				return
			inventory[1] -= 6
			inventory[3] += 3
			show_message("合成完成：获得 3 扇木门")
		2:
			if inventory[1] < 4:
				show_message("合成失败：需要 4 个木头")
				return
			inventory[1] -= 4
			inventory[4] += 4
			show_message("合成完成：获得 4 个脚手架")
		3:
			if inventory[0] < 9:
				show_message("合成失败：需要 9 个石头")
				return
			inventory[0] -= 9
			inventory[13] += 1
			show_message("合成完成：获得 1 个熔炉")
	update_ui()


func toggle_furnace() -> void:
	if backpack_panel.visible:
		backpack_panel.visible = false
	furnace_panel.visible = not furnace_panel.visible
	player.call("set_input_locked", furnace_panel.visible)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if furnace_panel.visible else Input.MOUSE_MODE_CAPTURED
	update_furnace_status()


func start_smelting() -> void:
	if furnace_active:
		show_message("熔炉正在工作")
		return
	if inventory[12] < 1:
		show_message("烧制失败：背包里没有沙子")
		return
	inventory[12] -= 1
	furnace_active = true
	furnace_timer = 3.0
	update_ui()
	update_furnace_status()


func update_furnace_status() -> void:
	if not furnace_status_label:
		return
	if furnace_active:
		furnace_status_label.text = "烧制中…… %.1f 秒" % furnace_timer
	else:
		furnace_status_label.text = "放入沙子即可烧制玻璃"


func create_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	info_label = Label.new()
	info_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	info_label.position = Vector2(-210, -116)
	info_label.size = Vector2(420, 32)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_font_size_override("font_size", 20)
	info_label.add_theme_color_override("font_color", Color("#fff3d2"))
	info_label.add_theme_constant_override("outline_size", 5)
	info_label.add_theme_color_override("font_outline_color", Color("#15191d"))
	layer.add_child(info_label)

	var help := Label.new()
	help.position = Vector2(24, 58)
	help.text = "右键放置或吃肉 / 左键挖掘或攻击  ·  E背包  ·  点击物品装入快捷栏  ·  1–9切换"
	help.add_theme_font_size_override("font_size", 16)
	help.add_theme_color_override("font_color", Color("#243342"))
	layer.add_child(help)

	var crosshair := Label.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-8, -18)
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 28)
	crosshair.add_theme_color_override("font_color", Color.WHITE)
	layer.add_child(crosshair)

	var hotbar := HBoxContainer.new()
	hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar.position = Vector2(-324, -76)
	hotbar.add_theme_constant_override("separation", 8)
	layer.add_child(hotbar)
	for index in range(9):
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(64, 58)
		var content := Control.new()
		content.custom_minimum_size = Vector2(60, 54)
		panel.add_child(content)
		var material_index := hotbar_slot_materials[index]
		var preview := create_material_preview(material_index)
		content.add_child(preview)
		var icon := TextureRect.new()
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.texture = preview.get_texture()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(icon)
		var key_label := Label.new()
		key_label.position = Vector2(4, 1)
		key_label.text = str(index + 1)
		key_label.add_theme_font_size_override("font_size", 12)
		key_label.add_theme_color_override("font_color", Color("#d5d8dc"))
		key_label.add_theme_constant_override("outline_size", 3)
		key_label.add_theme_color_override("font_outline_color", Color("#11151a"))
		content.add_child(key_label)
		var label := Label.new()
		label.position = Vector2(32, 33)
		label.size = Vector2(25, 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_color_override("font_outline_color", Color("#11151a"))
		content.add_child(label)
		hotbar.add_child(panel)
		hotbar_labels.append(label)
		hotbar_panels.append(panel)
		hotbar_contents.append(content)
		hotbar_icons.append(icon)
		hotbar_previews.append(preview)

	selection_label = Label.new()
	selection_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	selection_label.position = Vector2(-150, -151)
	selection_label.size = Vector2(300, 34)
	selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selection_label.add_theme_font_size_override("font_size", 20)
	selection_label.add_theme_color_override("font_color", Color("#fff0ad"))
	layer.add_child(selection_label)

	message_label = Label.new()
	message_label.set_anchors_preset(Control.PRESET_CENTER)
	message_label.position = Vector2(-180, 70)
	message_label.size = Vector2(360, 40)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 20)
	message_label.add_theme_color_override("font_color", Color("#fff3b0"))
	message_label.z_index = 10
	layer.add_child(message_label)

	backpack_panel = PanelContainer.new()
	backpack_panel.set_anchors_preset(Control.PRESET_CENTER)
	backpack_panel.position = Vector2(-350, -255)
	backpack_panel.custom_minimum_size = Vector2(700, 510)
	backpack_panel.visible = false
	layer.add_child(backpack_panel)
	var backpack_layout := VBoxContainer.new()
	backpack_layout.add_theme_constant_override("separation", 14)
	backpack_panel.add_child(backpack_layout)
	var backpack_title := Label.new()
	backpack_title.text = "背包  ·  点击物品可装入当前快捷栏格  ·  按 E 关闭"
	backpack_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	backpack_title.add_theme_font_size_override("font_size", 24)
	backpack_layout.add_child(backpack_title)
	var backpack_grid := GridContainer.new()
	backpack_grid.columns = 9
	backpack_grid.add_theme_constant_override("h_separation", 7)
	backpack_grid.add_theme_constant_override("v_separation", 7)
	backpack_layout.add_child(backpack_grid)
	for slot_index in range(27):
		var material_index := backpack_slot_materials[slot_index]
		var button := Button.new()
		button.custom_minimum_size = Vector2(68, 68)
		button.disabled = material_index < 0
		if material_index >= 0:
			button.toggle_mode = true
			button.tooltip_text = MATERIAL_NAMES[material_index]
			button.pressed.connect(select_backpack_material.bind(slot_index))
			var preview := create_material_preview(material_index)
			button.add_child(preview)
			var icon := TextureRect.new()
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon.texture = preview.get_texture()
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(icon)
			var count_label := Label.new()
			count_label.position = Vector2(38, 43)
			count_label.size = Vector2(24, 19)
			count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			count_label.add_theme_font_size_override("font_size", 14)
			count_label.add_theme_constant_override("outline_size", 4)
			count_label.add_theme_color_override("font_outline_color", Color("#11151a"))
			count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(count_label)
			backpack_count_labels.append(count_label)
		else:
			backpack_count_labels.append(null)
		backpack_grid.add_child(button)
		backpack_buttons.append(button)

	var crafting_title := Label.new()
	crafting_title.text = "简易合成"
	crafting_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crafting_title.add_theme_font_size_override("font_size", 20)
	backpack_layout.add_child(crafting_title)
	var crafting_row := GridContainer.new()
	crafting_row.columns = 2
	crafting_row.add_theme_constant_override("h_separation", 10)
	crafting_row.add_theme_constant_override("v_separation", 8)
	backpack_layout.add_child(crafting_row)
	for recipe in [
		["1 原木  →  4 木头", 0],
		["6 木头  →  3 木门", 1],
		["4 木头  →  4 脚手架", 2],
		["9 石头  →  1 熔炉", 3],
	]:
		var craft_button := Button.new()
		craft_button.text = recipe[0]
		craft_button.custom_minimum_size = Vector2(205, 48)
		craft_button.pressed.connect(craft_recipe.bind(recipe[1]))
		crafting_row.add_child(craft_button)

	furnace_panel = PanelContainer.new()
	furnace_panel.set_anchors_preset(Control.PRESET_CENTER)
	furnace_panel.position = Vector2(-245, -155)
	furnace_panel.custom_minimum_size = Vector2(490, 310)
	furnace_panel.visible = false
	layer.add_child(furnace_panel)
	var furnace_layout := VBoxContainer.new()
	furnace_layout.alignment = BoxContainer.ALIGNMENT_CENTER
	furnace_layout.add_theme_constant_override("separation", 24)
	furnace_panel.add_child(furnace_layout)
	var furnace_title := Label.new()
	furnace_title.text = "石制熔炉"
	furnace_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	furnace_title.add_theme_font_size_override("font_size", 27)
	furnace_layout.add_child(furnace_title)
	furnace_status_label = Label.new()
	furnace_status_label.text = "放入沙子即可烧制玻璃"
	furnace_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	furnace_status_label.add_theme_font_size_override("font_size", 20)
	furnace_layout.add_child(furnace_status_label)
	var smelt_button := Button.new()
	smelt_button.text = "烧制：1 沙子  →  1 玻璃（3秒）"
	smelt_button.custom_minimum_size = Vector2(380, 58)
	smelt_button.pressed.connect(start_smelting)
	furnace_layout.add_child(smelt_button)
	var furnace_help := Label.new()
	furnace_help.text = "按 E 关闭熔炉"
	furnace_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	furnace_layout.add_child(furnace_help)


func create_material_preview(material_index: int) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "MaterialPreview%d" % material_index
	viewport.size = Vector2i(96, 96)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	var root := Node3D.new()
	viewport.add_child(root)
	if material_index == 3:
		add_preview_box(root, Vector3(0.82, 1.55, 0.09), Vector3.ZERO, door_material)
		var knob := MeshInstance3D.new()
		var knob_mesh := SphereMesh.new()
		knob_mesh.radius = 0.065
		knob_mesh.height = 0.13
		knob_mesh.material = door_handle_material
		knob.mesh = knob_mesh
		knob.position = Vector3(0.27, -0.08, 0.095)
		root.add_child(knob)
	elif material_index == 4:
		for x_sign in [-1.0, 1.0]:
			for z_sign in [-1.0, 1.0]:
				add_scaffold_beam(root, Vector3(0.075, 0.95, 0.075), Vector3(x_sign * 0.40, 0, z_sign * 0.40))
		for y in [-0.40, 0.40]:
			for z_sign in [-1.0, 1.0]:
				add_scaffold_beam(root, Vector3(0.80, 0.065, 0.065), Vector3(0, y, z_sign * 0.40))
			for x_sign in [-1.0, 1.0]:
				add_scaffold_beam(root, Vector3(0.065, 0.065, 0.80), Vector3(x_sign * 0.40, y, 0))
	elif material_index == 14:
		add_preview_box(root, Vector3(0.82, 0.38, 0.58), Vector3.ZERO, block_materials[14])
	else:
		var preview_size := Vector3.ONE * (0.84 if material_index == 8 else 0.92)
		add_preview_box(root, preview_size, Vector3.ZERO, block_materials[material_index])
		if material_index == 2:
			create_glass_edges(root)
		elif material_index == 8:
			create_lamp_edges(root)
		elif material_index == 13:
			create_furnace_details(root)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -35, 0)
	light.light_energy = 1.4
	light.shadow_enabled = false
	viewport.add_child(light)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.75
	environment.environment = env
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.25 if material_index == 3 else 1.75
	camera.look_at_from_position(Vector3(2.1, 1.7, 2.35), Vector3.ZERO)
	viewport.add_child(camera)
	camera.current = true
	return viewport


func add_preview_box(parent: Node3D, size: Vector3, box_position: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	instance.mesh = mesh
	instance.position = box_position
	parent.add_child(instance)


func refresh_hotbar_preview(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= hotbar_icons.size():
		return
	var old_preview := hotbar_previews[slot_index]
	var new_preview := create_material_preview(hotbar_slot_materials[slot_index])
	hotbar_contents[slot_index].add_child(new_preview)
	hotbar_contents[slot_index].move_child(new_preview, 0)
	hotbar_icons[slot_index].texture = new_preview.get_texture()
	hotbar_previews[slot_index] = new_preview
	old_preview.queue_free()


func update_ui() -> void:
	info_label.text = "生命  %d / 20    饥饿  %d / 20" % [ceili(player_health), ceili(player_hunger)]
	for index in hotbar_labels.size():
		var material_index := hotbar_slot_materials[index]
		hotbar_labels[index].text = str(inventory[material_index])
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.055, 0.065, 0.075, 0.90)
		style.border_color = Color("#ffe08a") if index == selected_hotbar_slot else Color(0.22, 0.25, 0.28, 0.92)
		style.set_border_width_all(3 if index == selected_hotbar_slot else 1)
		style.corner_radius_top_left = 7
		style.corner_radius_top_right = 7
		style.corner_radius_bottom_left = 7
		style.corner_radius_bottom_right = 7
		hotbar_panels[index].add_theme_stylebox_override("panel", style)
	for slot_index in backpack_buttons.size():
		var material_index := backpack_slot_materials[slot_index]
		if material_index >= 0 and backpack_count_labels[slot_index] != null:
			backpack_count_labels[slot_index].text = str(inventory[material_index])
			backpack_buttons[slot_index].button_pressed = material_index == selected_material
			backpack_buttons[slot_index].visible = inventory[material_index] > 0


func show_selected_material() -> void:
	selection_label.text = "%d  %s" % [selected_hotbar_slot + 1, MATERIAL_NAMES[selected_material]]
	selection_label.modulate.a = 1.0
	selection_timer = 1.8


func show_message(text: String) -> void:
	message_label.text = text
	message_timer = 2.2


func update_survival(delta: float) -> void:
	# 满饥饿约十分钟耗尽；归零后每三秒受到一点饥饿伤害。
	player_hunger = maxf(0.0, player_hunger - delta / 30.0)
	if player_hunger <= 0.0:
		starvation_damage_timer -= delta
		if starvation_damage_timer <= 0.0:
			starvation_damage_timer = 3.0
			player_health = maxf(0.0, player_health - 1.0)
			show_message("太饿了：生命减少 1 点")
	else:
		starvation_damage_timer = 3.0
	if player_health <= 0.0:
		player_health = 20.0
		player_hunger = 10.0
		player.position = Vector3(0, 2, 6)
		player.velocity = Vector3.ZERO
		show_message("生命耗尽，已回到出生点")
	if info_label:
		info_label.text = "生命  %d / 20    饥饿  %d / 20" % [ceili(player_health), ceili(player_hunger)]


func _process(delta: float) -> void:
	update_mining(delta)
	update_item_drops(delta)
	update_survival(delta)
	apply_water_and_player_pushes()
	var player_ground_cell := Vector3i(roundi(player.position.x), 0, roundi(player.position.z))
	if maxi(absi(player_ground_cell.x - last_ground_center.x), absi(player_ground_cell.z - last_ground_center.z)) >= 7:
		create_destructible_ground(player_ground_cell)
	process_terrain_generation_queue()
	if furnace_active:
		furnace_timer -= delta
		if furnace_timer <= 0.0:
			furnace_active = false
			furnace_timer = 0.0
			inventory[2] += 1
			update_ui()
			show_message("烧制完成：获得 1 个玻璃")
		update_furnace_status()
	animal_spawn_timer -= delta
	if animal_spawn_timer <= 0.0:
		animal_spawn_timer += 60.0
		spawn_animals_out_of_view()
	for cloud in clouds:
		cloud.position.x += float(cloud.get_meta("speed")) * delta
		if cloud.position.x > 155.0:
			cloud.position.x = -155.0
	if player.position.y < -10.0:
		player.position = Vector3(0, 2, 6)
		player.velocity = Vector3.ZERO
		show_message("已将你送回建造区域")
	water_flow_timer -= delta
	if water_flow_timer <= 0.0 and not water_flow_queue.is_empty():
		water_flow_timer = 0.055
		process_next_water_flow()
	if message_timer > 0:
		message_timer -= delta
		if message_timer <= 0:
			message_label.text = ""
	if selection_timer > 0.0:
		selection_timer -= delta
		selection_label.modulate.a = clampf(selection_timer / 0.45, 0.0, 1.0) if selection_timer < 0.45 else 1.0
