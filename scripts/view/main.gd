extends Node3D
## The view: the field, motion-captured athletes (scripts/view/athlete.gd), the disc and the cameras over the match
## simulation (scripts/sim). White is the human's team.
##
## Offence: click a spot on the field to throw there. 1 backhand, 2 forehand, 3 hammer; hold Shift for
## inside-out, hold Space for a huck. Defence: WASD or the arrow keys steer the highlighted player, Tab
## switches to the player nearest the disc. C: the next camera (field, tower, sideline, behind). F1: autoplay (both
## teams AI). Esc: quit.
##
## Command line (after --): --autoplay, --seed=N, --screenshot=path.png [--frames=N], --cam=field|tower|sideline|close

## The kits: White (navy shorts and undershirts, navy numbers) and Maroon (black shorts and undershirts, white numbers).
const KITS := [
	{"jersey": Color(0.93, 0.93, 0.95), "shorts": Color(0.1, 0.13, 0.28), "sleeves": Color(0.08, 0.1, 0.2),
		"number": Color(0.1, 0.13, 0.3), "outline": Color(0.9, 0.9, 0.95), "ring": Color(0.85, 0.85, 0.95)},
	{"jersey": Color(0.42, 0.08, 0.12), "shorts": Color(0.06, 0.05, 0.06), "sleeves": Color(0.05, 0.04, 0.05),
		"number": Color(0.97, 0.97, 0.97), "outline": Color(0.1, 0.02, 0.03), "ring": Color(0.6, 0.12, 0.16)},
]
## The observers (the college game's): orange shirts, black shorts, no numbers; one on each sideline.
const OBSERVER_KIT := {"jersey": Color(1.0, 0.45, 0.08), "shorts": Color(0.06, 0.05, 0.06), "sleeves": Color(0.06, 0.05, 0.06),
		"number": Color.BLACK, "outline": Color.BLACK}
const OBSERVER_VARIANTS := ["w4", "w1"]
const OBSERVER_OFF := 2.5          # m outside the sideline
## The cameras: the whole field from high up; a high wide tower behind the sideline (as in the 2026 semifinal's
## broadcast); a lower tight sideline camera following the disc (the 2025 final's); behind the play at head height.
const CAMERAS := ["field", "tower", "sideline", "behind"]
const FIELD_GREEN := Color(0.2, 0.47, 0.22)
const GRASS := Color(0.16, 0.38, 0.18)
const LINE := Color(0.95, 0.95, 0.92)

var sim: UltimateMatch
var bodies: Array = [[], []]       # Athlete per player
var subs: Array = []               # Athlete per substitute
var observers: Array = []          # [Athlete, PlayerState] per sideline: they walk level with the disc
var windups_drawn := 0             # wind-ups (throws and pulls) the athletes have animated
var tags: Array = [[], []]         # Label3D per player
var rings: Array = [[], []]        # the ring under each player (holder, receiver, human)
var disc_node: MeshInstance3D
var shadow: MeshInstance3D
var target_marker: MeshInstance3D
var camera: Camera3D
var hud: Label
var help: Label
var log_label: Label
var kind := "backhand"
var shot_path := ""
var shot_frames := 240
var frames := 0
var cam_focus := Vector3.ZERO
var cam_mode := 0                  # an index into CAMERAS; C cycles
var cam_pos := Vector3(0, 30, 46)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := 1
	var autoplay := false
	for a in args:
		if a == "--autoplay":
			autoplay = true
		elif a.begins_with("--seed="):
			seed_value = int(a.split("=")[1])
		elif a.begins_with("--screenshot="):
			shot_path = a.split("=")[1]
		elif a.begins_with("--frames="):
			shot_frames = int(a.split("=")[1])
		elif a.begins_with("--cam="):
			var c := a.split("=")[1]
			cam_mode = 3 if c == "close" else maxi(0, CAMERAS.find(c))
	sim = UltimateMatch.new(seed_value, -1 if autoplay else 0)
	_build_world()
	_build_field()
	var stadium := Stadium.new()
	add_child(stadium)
	stadium.build()
	_build_players()
	_build_hud()


func _physics_process(delta: float) -> void:
	_steer_human()
	sim.step(delta)


func _process(delta: float) -> void:
	_update_players(delta)
	_update_disc()
	_update_camera(delta)
	_update_hud()
	frames += 1
	if shot_path != "" and frames == shot_frames:
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot_path)
		print("screenshot ", shot_path)
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:
				kind = "backhand"
			KEY_2:
				kind = "forehand"
			KEY_3:
				kind = "hammer"
			KEY_TAB:
				sim.switch_human()
			KEY_Z:
				var now: String = sim.defence_call[0] if sim.defence_call[0] != "" else sim.defence[0]
				sim.call_defence(0, "person" if now == "zone" else "zone")
			KEY_C:
				cam_mode = (cam_mode + 1) % CAMERAS.size()
			KEY_F1:
				sim.human_team = -1 if sim.human_team == 0 else 0
				sim.switch_human()
			KEY_ESCAPE:
				get_tree().quit()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var spot: Variant = _ground_point(event.position)
		if spot != null:
			var huck := Input.is_physical_key_pressed(KEY_SPACE)
			var io := Input.is_physical_key_pressed(KEY_SHIFT)
			if sim.user_throw(spot, kind, io, huck):
				target_marker.position = Vector3(spot.x, 0.03, spot.z)
				target_marker.visible = true


func _ground_point(screen: Vector2) -> Variant:
	var o := camera.project_ray_origin(screen)
	var n := camera.project_ray_normal(screen)
	if absf(n.y) < 1e-4:
		return null
	var t := -o.y / n.y
	if t < 0.0:
		return null
	return o + n * t


func _steer_human() -> void:
	if sim.human == null:
		return
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1
	# Screen directions on the broadcast camera: right is +x along the field, up the screen is +z.
	sim.human.steer = Vector3(v.x, 0, -v.y)


# ---------------------------------------------------------------- building the scene

func _material(c: Color, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _box(size: Vector3, pos: Vector3, c: Color, unshaded: bool = false) -> MeshInstance3D:
	var b := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	b.mesh = mesh
	b.material_override = _material(c, unshaded)
	b.position = pos
	add_child(b)
	return b


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.52, 0.82)
	sm.sky_horizon_color = Color(0.72, 0.8, 0.88)
	sm.ground_horizon_color = Color(0.3, 0.45, 0.3)
	sm.ground_bottom_color = Color(0.14, 0.3, 0.15)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.far = 600.0
	add_child(camera)
	camera.position = Vector3(0, 34, 52)
	camera.look_at(Vector3.ZERO)


func _build_field() -> void:
	_box(Vector3(900, 0.1, 900), Vector3(0, -0.06, 0), GRASS)
	_box(Vector3(Field.LENGTH, 0.02, Field.WIDTH), Vector3(0, 0.0, 0), FIELD_GREEN)
	# End zones a shade apart, team-neutral.
	for s in [-1, 1]:
		_box(Vector3(Field.ENDZONE, 0.025, Field.WIDTH), Vector3(s * (Field.GOAL_LINE + Field.ENDZONE / 2), 0.0, 0),
				Color(0.24, 0.52, 0.27))
	var w := 0.12
	for z in [-Field.HALF_W, Field.HALF_W]:
		_box(Vector3(Field.LENGTH + w, 0.04, w), Vector3(0, 0.01, z), LINE, true)
	for x in [-Field.HALF_L, -Field.GOAL_LINE, Field.GOAL_LINE, Field.HALF_L]:
		_box(Vector3(w, 0.04, Field.WIDTH + w), Vector3(x, 0.01, 0), LINE, true)
	for s in [-1, 1]:                           # brick marks: two crossed 1 m lines
		var bx: float = s * (Field.GOAL_LINE - Field.BRICK)
		_box(Vector3(1.0, 0.04, w), Vector3(bx, 0.01, 0), LINE, true)
		_box(Vector3(w, 0.04, 1.0), Vector3(bx, 0.01, 0), LINE, true)
	# Corner cones.
	for x in [-Field.HALF_L, -Field.GOAL_LINE, Field.GOAL_LINE, Field.HALF_L]:
		for z in [-Field.HALF_W, Field.HALF_W]:
			var c := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.03
			cm.bottom_radius = 0.15
			cm.height = 0.35
			c.mesh = cm
			c.material_override = _material(Color(1.0, 0.5, 0.1))
			c.position = Vector3(x, 0.17, z)
			add_child(c)


func _build_players() -> void:
	# The substitutes: seven a team in their area on the far sideline, either side of midfield, watching.
	var sub_numbers := [[1, 3, 8, 11, 15, 19, 27], [6, 10, 13, 20, 22, 33, 50]]
	for t in 2:
		for i in sub_numbers[t].size():
			var s := Athlete.new()
			add_child(s)
			s.setup(Athlete.ROSTERS[t][(i + 3) % Athlete.ROSTERS[t].size()], KITS[t], sub_numbers[t][i])
			var x: float = (-24.0 if t == 0 else 8.0) + i * 2.4 + randf_range(-0.4, 0.4)
			s.position = Vector3(x, 0, Stadium.SIDE * (Field.HALF_W + Stadium.TEAM_AREA + randf_range(-0.6, 0.9)))
			s.rotation.y = 0.0 if Stadium.SIDE < 0.0 else PI          # facing the field
			subs.append(s)
	for k in 2:
		var o := Athlete.new()
		add_child(o)
		o.setup(OBSERVER_VARIANTS[k], OBSERVER_KIT, 0)
		var st := PlayerState.new(-1, k, 0)
		st.speed = 5.0
		st.pos = Vector3(0, 0, (Field.HALF_W + OBSERVER_OFF) * (1.0 if k == 0 else -1.0))
		st.goal = st.pos
		observers.append([o, st])
	for t in 2:
		for i in UltimateMatch.PLAYERS:
			var p := Athlete.new()
			add_child(p)
			p.setup(Athlete.ROSTERS[t][i % Athlete.ROSTERS[t].size()], KITS[t], sim.teams[t][i].number)
			bodies[t].append(p)
			var tag := Label3D.new()
			tag.text = str(sim.teams[t][i].number)
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.font_size = 72
			tag.outline_size = 12
			tag.pixel_size = 0.01
			tag.no_depth_test = true
			add_child(tag)
			tags[t].append(tag)
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.62
			tm.outer_radius = 0.78
			ring.mesh = tm
			ring.scale = Vector3(1, 0.15, 1)
			ring.material_override = _material(Color.WHITE, true)
			ring.visible = false
			add_child(ring)
			rings[t].append(ring)
	disc_node = MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = DiscFlight.RADIUS
	dm.bottom_radius = DiscFlight.RADIUS * 0.96
	dm.height = 0.035
	disc_node.mesh = dm
	disc_node.material_override = _material(Color(0.98, 0.98, 0.95))
	disc_node.scale = Vector3(1.6, 1.6, 1.6)      # drawn larger than life so it reads from the camera
	add_child(disc_node)
	shadow = MeshInstance3D.new()
	var sh := CylinderMesh.new()
	sh.top_radius = 0.25
	sh.bottom_radius = 0.25
	sh.height = 0.01
	shadow.mesh = sh
	shadow.material_override = _material(Color(0, 0, 0, 0.35), true)
	add_child(shadow)
	target_marker = MeshInstance3D.new()
	var tmk := TorusMesh.new()
	tmk.inner_radius = 0.8
	tmk.outer_radius = 1.0
	target_marker.mesh = tmk
	target_marker.scale = Vector3(1, 0.1, 1)
	target_marker.material_override = _material(Color(0.3, 1.0, 0.4), true)
	target_marker.visible = false
	add_child(target_marker)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(20, 14)
	hud.add_theme_font_size_override("font_size", 26)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud)
	log_label = Label.new()
	log_label.position = Vector2(20, 110)
	log_label.add_theme_font_size_override("font_size", 17)
	log_label.add_theme_color_override("font_outline_color", Color.BLACK)
	log_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(log_label)
	help = Label.new()
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.position = Vector2(20, -40)
	help.add_theme_font_size_override("font_size", 16)
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 5)
	help.text = "Offence: click to throw  ·  1 backhand  2 forehand  3 hammer  ·  Shift inside-out  ·  Space huck     Defence: WASD / arrows  ·  Tab switch  ·  Z zone or person     C camera  ·  F1 autoplay  ·  Esc quit"
	layer.add_child(help)


# ---------------------------------------------------------------- per frame

func _update_players(delta: float) -> void:
	# A throw (or a pull) being wound up: the thrower's clip starts now, timed so its release meets the sim's.
	if sim.windups != windups_drawn and sim.windup_by != null:
		(bodies[sim.windup_by.team][sim.windup_by.idx] as Athlete).start_throw(sim.windup_kind, _release_in())
	windups_drawn = sim.windups
	for ob in observers:
		var st: PlayerState = ob[1]
		var level := clampf(sim.disc.pos.x, -Field.HALF_L + 4.0, Field.HALF_L - 4.0)
		if absf(level - st.pos.x) > 3.0:             # keep level with the play, without chasing every step
			st.goal = Vector3(level, 0, st.pos.z)
		st.move(delta)
		(ob[0] as Athlete).update_from(st, sim.disc.pos, delta)
	for t in 2:
		for i in UltimateMatch.PLAYERS:
			var p: PlayerState = sim.teams[t][i]
			var b: Athlete = bodies[t][i]
			var look := sim.disc.pos
			if p == sim.holder:
				look = p.pos + Vector3(sim.dir[t] * 10.0, 0, 0)    # the thrower looks downfield
			b.update_from(p, look, delta)
			tags[t][i].position = p.pos + Vector3(0, 2.3, 0)
			tags[t][i].visible = cam_mode == 0      # nearer in, the numbers on the jerseys are enough
			var ring: MeshInstance3D = rings[t][i]
			var colour := Color.TRANSPARENT
			if p == sim.holder:
				colour = Color(1, 0.9, 0.2)
			elif p == sim.receiver:
				colour = Color(0.3, 1.0, 0.9)
			elif p == sim.human:
				colour = Color(1, 1, 1)
			ring.visible = colour.a > 0.0
			if ring.visible:
				ring.position = p.pos + Vector3(0, 0.04, 0)
				(ring.material_override as StandardMaterial3D).albedo_color = colour


## Seconds until the throw being wound up leaves the hand (a pull: until the line-up's end).
func _release_in() -> float:
	if sim.phase == UltimateMatch.Phase.LINE_UP:
		return maxf(0.0, 1.5 - sim.phase_time)
	return sim.windup_left


func _update_disc() -> void:
	var s := sim.disc
	disc_node.position = s.pos
	# Held: the disc is in the holder's right hand (drawn there; the sim keeps its own spot).
	if sim.holder != null and sim.phase in [UltimateMatch.Phase.HOLD, UltimateMatch.Phase.PICKUP]:
		disc_node.position = (bodies[sim.holder.team][sim.holder.idx] as Athlete).hand_position()
	elif sim.phase == UltimateMatch.Phase.LINE_UP:
		disc_node.position = (bodies[sim.pulling_team()][3] as Athlete).hand_position()   # the puller
	var n := s.normal if sim.phase in [UltimateMatch.Phase.FLIGHT, UltimateMatch.Phase.PULL] else Vector3.UP
	var axis := Vector3.UP.cross(n)
	if axis.length() > 1e-4:
		disc_node.basis = Basis(axis.normalized(), Vector3.UP.angle_to(n)).scaled(Vector3.ONE * 1.6)
	else:
		disc_node.basis = Basis.IDENTITY.scaled(Vector3.ONE * (1.6 if n.y > 0 else -1.6))
	shadow.position = Vector3(s.pos.x, 0.02, s.pos.z)
	if sim.phase != UltimateMatch.Phase.FLIGHT:
		target_marker.visible = false


func _update_camera(delta: float) -> void:
	var k := clampf(delta * 1.8, 0.0, 1.0)
	var disc_g := Vector3(sim.disc.pos.x, 0, sim.disc.pos.z)
	match CAMERAS[cam_mode]:
		"behind":
			# Behind the disc, looking the way the offence attacks: the players at human size.
			var d := float(sim.dir[sim.offence])
			camera.fov = 42.0
			cam_focus = cam_focus.lerp(disc_g, k)
			cam_pos = cam_pos.lerp(cam_focus + Vector3(-d * 10.0, 5.0, 2.5), k)
			camera.position = cam_pos
			camera.look_at(cam_focus + Vector3(d * 12.0, 0.8, 0))
		"tower":
			# High on a tower 18 m behind the near sideline, looking down about 30 degrees: 50-60 m of field and
			# nearly its whole width; it pans along the field with the disc.
			camera.fov = 40.0
			cam_focus = cam_focus.lerp(Vector3(clampf(disc_g.x, -32.0, 32.0), 0, clampf(disc_g.z * 0.3, -4.0, 4.0)), k)
			cam_pos = Vector3(cam_focus.x, 18.0, Field.HALF_W + 18.0)
			camera.position = cam_pos
			camera.look_at(cam_focus + Vector3(0, 0, -1.0))
		"sideline":
			# Lower, on the near sideline, zoomed to 25-40 m of field and following the disc closely.
			camera.fov = 28.0
			cam_focus = cam_focus.lerp(disc_g, clampf(delta * 2.5, 0.0, 1.0))
			cam_pos = Vector3(cam_focus.x, 10.0, Field.HALF_W + 14.0)
			camera.position = cam_pos
			camera.look_at(cam_focus + Vector3(0, 0.8, 0))
		_:
			# The whole field from high up (the original view).
			camera.fov = 42.0
			var focus := Vector3(clampf(disc_g.x, -38.0, 38.0), 0, clampf(disc_g.z * 0.5, -6.0, 6.0))
			cam_focus = cam_focus.lerp(focus, k)
			cam_pos = cam_focus + Vector3(0, 30, 46)
			camera.position = cam_pos
			camera.look_at(cam_focus + Vector3(0, 0, -2))


func _update_hud() -> void:
	var stall_txt := ""
	if sim.phase == UltimateMatch.Phase.HOLD and sim.stall_called > 0:
		stall_txt = "    Stalling %d" % sim.stall_called
	var who: String = sim.names[sim.offence]
	var arrow := "→" if sim.dir[sim.offence] > 0 else "←"
	var mode := "autoplay" if sim.human_team < 0 else ("you throw: " + kind if sim.offence == 0 else "you defend")
	var call: String = sim.defence[0] + (" (next point: %s)" % sim.defence_call[0] if sim.defence_call[0] != "" else "")
	mode += "        your defence: " + call
	hud.text = "%s %d  –  %d %s        %s on offence %s%s\n%s" % [sim.names[0], sim.score[0], sim.score[1],
			sim.names[1], who, arrow, stall_txt, mode]
	var lines: Array = []
	for e in sim.events.slice(-6):
		lines.append(e.text)
	log_label.text = "\n".join(lines)
