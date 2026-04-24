class_name WaterGrid
extends Node3D

const GRID_W         := 20
const GRID_H         := 20
const EVAP_RATE      := 0.0001
const TICKS_PER_SIM  := 4
const FLOW_FRACTION  := 0.22
const FLOW_THRESHOLD := 0.008
const EDGE_DRAIN     := 0.06   # sanfterer Abfluss am Kartenrand
const VIS_THRESHOLD  := 0.003  # Mindestpegel zum Anzeigen

var source_rate: float = 0.05
var _drought:    bool  = false
var _show:       bool  = true

var _water:   Dictionary = {}  # Vector2i(x,z) -> float
var _meshes:  Dictionary = {}  # Vector2i(x,z) -> MeshInstance3D
var _sources: Array[Vector2i] = []
var _terrain: Terrain = null
var _tick:    int = 0
var _water_mat: ShaderMaterial

const _WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4  deep_color    : source_color = vec4(0.04, 0.20, 0.62, 0.90);
uniform vec4  shallow_color : source_color = vec4(0.16, 0.55, 0.88, 0.55);
uniform float wave_speed    : hint_range(0.0, 4.0) = 0.9;
uniform float wave_scale    : hint_range(0.5, 8.0) = 2.8;
uniform float ripple_str    : hint_range(0.0, 0.5) = 0.18;

void fragment() {
	float t  = TIME * wave_speed;
	float rx = sin(UV.x * wave_scale * 6.283 + t) * ripple_str;
	float rz = sin(UV.y * wave_scale * 6.283 + t * 0.71 + 1.57) * ripple_str;
	float rx2 = sin(UV.x * wave_scale * 3.14 - t * 0.53 + 0.8) * ripple_str * 0.5;
	float rz2 = sin(UV.y * wave_scale * 3.14 + t * 0.63 + 2.4) * ripple_str * 0.5;
	NORMAL_MAP = normalize(vec3(rx + rx2, rz + rz2, 1.0));

	float fresnel = pow(clamp(1.0 - dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	ALBEDO  = mix(shallow_color.rgb, deep_color.rgb, fresnel);
	ALPHA   = mix(shallow_color.a,   deep_color.a,   fresnel);

	ROUGHNESS = 0.04;
	METALLIC  = 0.0;
	SPECULAR  = 0.96;
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
			next[src] = next.get(src, 0.0) + source_rate

	for key in _water:
		var lvl: float = _water.get(key, 0.0)
		if lvl < 0.001:
			continue
		var my_total: float = _surface(key) + lvl
		for dir: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nk: Vector2i = key + dir
			if nk.x < 0 or nk.y < 0 or nk.x >= GRID_W or nk.y >= GRID_H:
				# Nur den Wasseranteil abfließen lassen, nicht vom Terrainniveau abhängig
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
		if not (key in _sources):
			next[key] = maxf(0.0, next.get(key, 0.0) - evap)

	_water = next

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
			# Plane liegt auf der Wasseroberfläche: Terrain-Top + Wasserstand
			var surf_top: float = _surface(key) - 0.5
			mi.position.y = surf_top + lvl
			mi.visible = true
		else:
			mi.visible = false

func _make_water_mesh(x: int, z: int) -> MeshInstance3D:
	var mi   := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size            = Vector2(1.0, 1.0)
	mesh.subdivide_width  = 0
	mesh.subdivide_depth  = 0
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
		if not key in _sources:
			_sources.append(key)
	else:
		_sources.erase(key)

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
