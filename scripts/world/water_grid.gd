class_name WaterGrid
extends Node3D

const GRID_W         := 20
const GRID_H         := 20
const EVAP_RATE      := 0.0001
const TICKS_PER_SIM  := 4
const FLOW_FRACTION  := 0.22
const FLOW_THRESHOLD := 0.008
const EDGE_DRAIN     := 0.06
const VIS_THRESHOLD  := 0.003
const CELL_SIZE      := 1.0    # Meter pro Zelle (entspricht Terrain-Boxgröße 1×1×1)
const WE_PER_METER   := 1.0    # Balance 1:1: 1 WE = 1 m Wassertiefe in einer Zelle
const MIN_WATER      := 0.001  # Schwelle für „trocken"

signal simulation_updated

var source_rate: float = 0.05
var _drought:    bool  = false
var _show:       bool  = true

var _water:   Dictionary = {}
var _meshes:  Dictionary = {}
var _sources: Dictionary = {}   # Vector2i → float (Rate in m/Sim-Tick)
var _terrain: Terrain = null
var _tick:    int = 0
var _water_mat: ShaderMaterial

const _WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4  color_shallow : source_color = vec4(0.20, 0.65, 0.82, 0.60);
uniform vec4  color_deep    : source_color = vec4(0.02, 0.16, 0.52, 0.90);
uniform vec4  color_foam    : source_color = vec4(0.92, 0.95, 1.00, 1.00);
uniform float wave_speed    : hint_range(0.0, 5.0)  = 1.2;
uniform float wave_scale    : hint_range(0.1, 6.0)  = 1.4;
uniform float wave_height   : hint_range(0.0, 0.3)  = 0.05;
uniform float ripple_str    : hint_range(0.0, 1.0)  = 0.30;
uniform float foam_depth    : hint_range(0.05, 2.0) = 0.25;
uniform float refraction_str : hint_range(0.0, 0.05) = 0.018;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

instance uniform float water_depth = 1.0;

varying vec2 world_xz;

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_xz = vec2(wp.x, wp.z);
	float t = TIME * wave_speed;
	float h = sin(wp.x * 1.8 + wp.z * 1.1 + t)          * 0.50
			+ sin(wp.x * 2.9 - wp.z * 1.6 + t * 0.73)   * 0.30
			+ sin(wp.x * 0.9 + wp.z * 2.7 + t * 1.37)   * 0.20;
	VERTEX.y += h * wave_height;
}

void fragment() {
	float t = TIME * wave_speed;
	float s = wave_scale;
	vec2  w = world_xz;

	// Drei überlagerte Wellenrichtungen für natürliche Oberfläche
	float rx  = sin(w.x * s * 6.28        + t)               * ripple_str;
	float rz  = sin(w.y * s * 6.28        + t * 0.71 + 1.57) * ripple_str;
	float rx2 = sin(w.x * s * 3.14        - t * 0.53 + 0.80) * ripple_str * 0.55;
	float rz2 = sin(w.y * s * 3.14        + t * 0.63 + 2.40) * ripple_str * 0.55;
	float rx3 = sin((w.x + w.y * 0.6) * s * 2.0 + t * 0.88) * ripple_str * 0.30;
	float rz3 = cos((w.y - w.x * 0.7) * s * 2.0 - t * 1.05) * ripple_str * 0.30;

	vec3 n_ts = normalize(vec3(rx + rx2 + rx3, rz + rz2 + rz3, 1.0));
	NORMAL_MAP = n_ts * 0.5 + 0.5;

	float fresnel = pow(clamp(1.0 - dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);

	// Tiefenbasierte Farbmischung
	float depth_t = clamp(water_depth / 2.5, 0.0, 1.0);
	vec4  wcol    = mix(color_shallow, color_deep, depth_t);

	// Screen-Space-Refraktion
	vec3 refr = texture(screen_texture, SCREEN_UV + n_ts.xy * refraction_str).rgb;
	vec3 col  = mix(refr, wcol.rgb, wcol.a * 0.80);
	col = mix(col, wcol.rgb, fresnel * 0.35);

	// Kaustics
	float cx      = sin(w.x * s * 5.5 + t * 2.1) * sin(w.y * s * 5.0 + t * 1.8);
	float caustic = pow(clamp(cx * 0.5 + 0.5, 0.0, 1.0), 3.0) * 0.10 * (1.0 - fresnel);
	col += vec3(caustic * 0.5, caustic * 0.7, caustic);

	// Schaum bei flachem Wasser (per Zelle via instance uniform)
	float foam_t = pow(clamp(1.0 - water_depth / foam_depth, 0.0, 1.0), 2.0);
	float foam_p = sin(w.x * 18.0 + t * 2.5) * sin(w.y * 17.0 + t * 2.1);
	foam_t      *= smoothstep(0.0, 0.6, foam_p * 0.5 + 0.5);
	col          = mix(col, color_foam.rgb, foam_t);

	ALBEDO    = col;
	ALPHA     = clamp(wcol.a + foam_t * 0.3, 0.3, 1.0);
	ROUGHNESS = mix(0.02, 0.35, foam_t);
	METALLIC  = 0.0;
	SPECULAR  = 0.95;
}
"""

func _ready() -> void:
	add_to_group("water_grid")
	var shader := Shader.new()
	shader.code = _WATER_SHADER
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = shader

	for x in range(GRID_W):
		for z in range(GRID_H):
			var key := Vector2i(x, z)
			_water[key] = 0.0
			_meshes[key] = _make_water_mesh(x, z)

	await get_tree().process_frame
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain
	_load_sources_from_map()

func _physics_process(_delta: float) -> void:
	_tick += 1
	if _tick % TICKS_PER_SIM == 0:
		_simulate()
	_update_visuals()

# ── Simulation ───────────────────────────────────────────────

func _simulate() -> void:
	var next: Dictionary = {}
	for key in _water:
		next[key] = _water[key]

	if not _drought:
		for src in _sources:
			next[src] = next.get(src, 0.0) + float(_sources[src])

	for key in _water:
		var lvl: float = _water.get(key, 0.0)
		if lvl < 0.001:
			continue
		var my_total: float = _surface(key) + lvl
		for dir: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nk: Vector2i = key + dir
			if nk.x < 0 or nk.y < 0 or nk.x >= GRID_W or nk.y >= GRID_H:
				var drain: float = minf(lvl * EDGE_DRAIN, maxf(0.0, next.get(key, 0.0)))
				next[key] = maxf(0.0, next.get(key, 0.0) - drain)
				continue
			var n_total: float = _surface(nk) + _water.get(nk, 0.0)
			if my_total > n_total + FLOW_THRESHOLD:
				var flow: float = minf((my_total - n_total) * FLOW_FRACTION, maxf(0.0, next.get(key, 0.0)))
				next[key] = maxf(0.0, next.get(key, 0.0) - flow)
				next[nk]  = next.get(nk, 0.0) + flow

	var evap: float = EVAP_RATE * (5.0 if _drought else 1.0)
	for key in next:
		if not _sources.has(key):
			next[key] = maxf(0.0, next.get(key, 0.0) - evap)

	_water = next
	simulation_updated.emit()

func _surface(key: Vector2i) -> float:
	if _terrain:
		return float(_terrain.get_height_at(key.x, key.y))
	return 1.0

# ── Visualisierung ───────────────────────────────────────────

func _update_visuals() -> void:
	for key in _meshes:
		var lvl: float = _water.get(key, 0.0)
		var mi: MeshInstance3D = _meshes[key]
		if _show and lvl > VIS_THRESHOLD:
			var surf_top: float = _surface(key) - 0.5
			mi.position.y = surf_top + lvl
			mi.set_instance_shader_parameter("water_depth", lvl)
			mi.visible = true
		else:
			mi.visible = false

func _make_water_mesh(x: int, z: int) -> MeshInstance3D:
	var mi   := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size            = Vector2(1.0, 1.0)
	mesh.subdivide_width  = 3
	mesh.subdivide_depth  = 3
	mi.mesh              = mesh
	mi.material_override = _water_mat
	mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position          = Vector3(x, 0.0, z)
	mi.visible           = false
	add_child(mi)
	return mi

func toggle_visible() -> void:
	_show = not _show
	if not _show:
		for key in _meshes:
			(_meshes[key] as MeshInstance3D).visible = false

# ── Quellen ──────────────────────────────────────────────────

func _load_sources_from_map() -> void:
	var map_name := SaveManager.get_current_map_name()
	if map_name.is_empty():
		return
	var data := SaveManager.load_map(map_name)
	for cell: Dictionary in data.get("cells", []):
		if cell.get("is_source", false):
			set_source(int(cell["x"]), int(cell["z"]), true)

func set_drought(active: bool) -> void:
	_drought = active

func set_source(x: int, z: int, enabled: bool) -> void:
	var key := Vector2i(x, z)
	if enabled:
		if not _sources.has(key):
			_sources[key] = source_rate
	else:
		_sources.erase(key)

func set_source_rate(x: int, z: int, rate: float) -> void:
	var key := Vector2i(x, z)
	if rate <= 0.0:
		_sources.erase(key)
	else:
		_sources[key] = rate

func get_source_rate(x: int, z: int) -> float:
	return float(_sources.get(Vector2i(x, z), 0.0))

# ── Öffentliche API: Meter / WE Umrechnung ──────────────────

func meters_to_we(water_level: float) -> float:
	return water_level * CELL_SIZE * CELL_SIZE * WE_PER_METER

func we_to_meters(we: float) -> float:
	return we / (CELL_SIZE * CELL_SIZE * WE_PER_METER)

# ── Öffentliche API: Abfragen ───────────────────────────────

func get_water_level(x: int, z: int) -> float:
	return float(_water.get(Vector2i(x, z), 0.0))

func get_water_surface(x: int, z: int) -> float:
	var key := Vector2i(x, z)
	return _surface(key) + float(_water.get(key, 0.0))

func get_water_we(x: int, z: int) -> float:
	return meters_to_we(get_water_level(x, z))

# ── Öffentliche API: Mutation ───────────────────────────────

func add_water(x: int, z: int, meters: float) -> void:
	var key := Vector2i(x, z)
	if not _water.has(key):
		return
	_water[key] = float(_water[key]) + maxf(0.0, meters)

func remove_water(x: int, z: int, meters: float) -> float:
	var key := Vector2i(x, z)
	if not _water.has(key):
		return 0.0
	var available: float = float(_water[key])
	var taken: float = minf(available, maxf(0.0, meters))
	_water[key] = available - taken
	return taken

# ── Speichern/Laden-Helfer ───────────────────────────────────

func get_all_cells_with_water() -> Array:
	var result: Array = []
	for key in _water:
		if _water[key] > 0.01:
			result.append({"x": key.x, "z": key.y, "level": _water[key]})
	return result

func restore_water(cells: Array) -> void:
	for entry: Dictionary in cells:
		var key := Vector2i(int(entry["x"]), int(entry["z"]))
		_water[key] = float(entry.get("level", 0.0))
