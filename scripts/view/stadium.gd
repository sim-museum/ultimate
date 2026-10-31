class_name Stadium
extends Node3D
## Everything off the field along the far sideline, which the broadcast cameras look across (the top third of
## every frame in the gold-standard recordings): a line of low boards, pop-up tents, and stepped stands with a
## seated crowd (the substitutes, nearer the field, are athletes: main.gd). The crowd are simple figures (a body
## and a head) drawn in batches: at broadcast distance they are a few pixels tall. Our own words on the boards: no
## real marks.

const SIDE := -1.0                 # the far sideline is at z = SIDE * Field.HALF_W
const TEAM_AREA := 4.5             # m behind the sideline: the substitutes (main.gd places them)
const BOARDS := 8.0                # the boards
const TENTS := 11.0
const STANDS := 14.0               # the front row of the stands
const ROWS := 9
const ROW_DEPTH := 0.85
const ROW_RISE := 0.45
const STANDS_LENGTH := 76.0
const SEAT := 0.55                 # m between seated spectators
const SHIRTS := [Color(0.9, 0.9, 0.92), Color(0.15, 0.2, 0.45), Color(0.5, 0.1, 0.14), Color(0.1, 0.1, 0.1),
		Color(0.85, 0.75, 0.2), Color(0.3, 0.55, 0.8), Color(0.75, 0.3, 0.2), Color(0.35, 0.5, 0.3)]
const SKIN := [Color(0.93, 0.78, 0.65), Color(0.82, 0.64, 0.48), Color(0.6, 0.42, 0.3), Color(0.38, 0.25, 0.18)]

var rng := RandomNumberGenerator.new()
var people := 0                    # spectators placed
var deepest_in := 1e9              # the nearest anything comes to the field: metres outside the sideline


func build() -> void:
	rng.seed = 1977
	var bodies: Array = []         # [Transform3D, Color]
	var heads: Array = []
	# The boards: a low line of panels, dark, with our own words.
	var words := ["ULTIMATE", "SPIRIT OF THE GAME", "ULTIMATE", "SEVEN ON SEVEN", "ULTIMATE"]
	for k in words.size():
		var x := -40.0 + k * 20.0
		var z := SIDE * (Field.HALF_W + BOARDS)
		_box(Vector3(16.0, 0.9, 0.12), Vector3(x, 0.45, z), Color(0.08, 0.1, 0.22))
		var l := Label3D.new()
		l.text = words[k]
		l.font_size = 64
		l.pixel_size = 0.012
		l.modulate = Color(0.95, 0.95, 0.95)
		l.outline_size = 0
		l.position = Vector3(x, 0.47, z - SIDE * 0.07)
		l.double_sided = false
		add_child(l)
		deepest_in = minf(deepest_in, BOARDS)
	# Tents: pop-up canopies behind the team areas and the scorers' table at midfield.
	for x in [-20.0, -4.0, 14.0, 26.0]:
		_tent(Vector3(x, 0, SIDE * (Field.HALF_W + TENTS)), Color(0.92, 0.92, 0.95) if x != -4.0 else Color(0.2, 0.3, 0.6))
	# The stands: stepped rows, a spectator in most seats.
	for r in ROWS:
		var z := SIDE * (Field.HALF_W + STANDS + r * ROW_DEPTH)
		var y := r * ROW_RISE
		_box(Vector3(STANDS_LENGTH, ROW_RISE, ROW_DEPTH), Vector3(0, y + ROW_RISE * 0.5, z), Color(0.55, 0.56, 0.58))
		var n := int(STANDS_LENGTH / SEAT)
		for i in n:
			if rng.randf() < 0.22:
				continue                                   # empty seats
			var x := -STANDS_LENGTH * 0.5 + (i + 0.5) * SEAT + rng.randf_range(-0.08, 0.08)
			var shirt: Color = SHIRTS[rng.randi() % SHIRTS.size()]
			_person(bodies, heads, Vector3(x, y + ROW_RISE, z), 1.05, shirt)
	_box(Vector3(STANDS_LENGTH, ROWS * ROW_RISE + 1.2, 0.3),
			Vector3(0, (ROWS * ROW_RISE + 1.2) * 0.5, SIDE * (Field.HALF_W + STANDS + ROWS * ROW_DEPTH + 0.2)),
			Color(0.3, 0.32, 0.36))
	_batch(bodies, _capsule())
	_batch(heads, _head())
	people = bodies.size()


## A figure: a body (a capsule, its height standing or seated) and a head.
func _person(bodies: Array, heads: Array, at: Vector3, h: float, shirt: Color) -> void:
	var body_h := h - 0.22
	var t := Transform3D(Basis().scaled(Vector3(1, body_h / 1.4, 1)), at + Vector3(0, body_h * 0.5, 0))
	bodies.append([t, shirt])
	heads.append([Transform3D(Basis(), at + Vector3(0, body_h + 0.1, 0)), SKIN[rng.randi() % SKIN.size()]])


func _capsule() -> Mesh:
	var m := CapsuleMesh.new()
	m.radius = 0.2
	m.height = 1.4
	m.radial_segments = 8
	m.rings = 2
	return m


func _head() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 0.11
	m.height = 0.24
	m.radial_segments = 8
	m.rings = 4
	return m


## One draw for many figures: a MultiMesh with a colour per instance.
func _batch(items: Array, mesh: Mesh) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mi.material_override = mat
	add_child(mi)


func _tent(at: Vector3, colour: Color) -> void:
	var s := 3.0
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(s, 0.6, s)
	roof.mesh = pm
	roof.material_override = _mat(colour)
	roof.position = at + Vector3(0, 2.4, 0)
	add_child(roof)
	for dx in [-1, 1]:
		for dz in [-1, 1]:
			_box(Vector3(0.05, 2.1, 0.05), at + Vector3(dx * s * 0.47, 1.05, dz * s * 0.47), Color(0.7, 0.7, 0.72))


func _box(size: Vector3, at: Vector3, colour: Color) -> void:
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	b.mesh = bm
	b.material_override = _mat(colour)
	b.position = at
	add_child(b)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m
