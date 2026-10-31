class_name Athlete
extends Node3D
## One player drawn as a motion-captured athlete (assets/players): an MPFB body in the team's jersey and shorts,
## with CMU motion capture clips. The view drives it from the simulation: where the player is, how fast they
## move and which way, what they look at (the disc), and when they throw. The simulation never reads it.
##
## Locomotion is a 2D blend by the player's velocity in their own frame (x right, y forward, m/s), with the
## clips placed at the speeds they were captured at; faster than the fastest clip, the clip plays faster.

const PLAYERS_DIR := "res://assets/players/"
## Women's ultimate: nine body variants (tools/athletes). as1-as5 have East Asian features; the white team is
## mostly East Asian players (as many top women's teams are), the maroon team mixed.
const VARIANTS := ["as1", "as2", "as3", "as4", "as5", "w1", "w2", "w4", "w5"]
const ROSTERS := [["as1", "as4", "as2", "w2", "as3", "as5", "as1"],
		["w4", "w5", "as3", "w1", "w2", "as2", "w5"]]
## Hair colour over the hair texture (the MPFB hair textures are brown): near black for the East Asian variants.
const HAIR_TINT := {"as1": Color(0.22, 0.2, 0.19), "as2": Color(0.3, 0.27, 0.25), "as3": Color(0.4, 0.37, 0.35),
		"as4": Color(0.22, 0.2, 0.19), "as5": Color(0.4, 0.37, 0.35)}
const HAIR_NODES := ["ponytail", "braid", "bob", "short0", "afro", "long0"]
const TURN_RATE := 9.0          # rad/s: how fast the body turns to its heading
const FACE_MOVE := 2.2          # m/s: above this the player faces where they run, below it the disc
const THROW_LEAD := 0.15        # s: a throw seen only at its release starts its clip this long before it
const THROW_CLIPS := {"backhand": ["backhand", "backhand2"], "pull": ["backhand", "backhand2"],
		"forehand": ["forehand"], "hammer": ["hammer"],
		# The new throws (ULTIMATE-3) on the nearest clip until they have their own: high releases and the cloud on
		# the backhand or forehand, the blade on the backhand, the scoober (overhead) on the hammer, the push on the
		# forehand.
		"high_backhand": ["backhand", "backhand2"], "high_forehand": ["forehand"], "cloud": ["backhand", "backhand2"],
		"blade": ["backhand", "backhand2"], "scoober": ["hammer"], "push": ["forehand"],
		# The lefty forehand: the forehand mirrored (build_athletes.py mirror_poses), an off-hand flick.
		"lefty_forehand": ["lefty_forehand"]}

static var _clips := {}
static var _scenes := {}

var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var tree: AnimationTree
var yaw := 0.0
var foot_lock: FootLock
var toes_final: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]   # the toes where they are drawn (after foot locking)
var _toes: Array = []
var hand_bone := -1
var off_hand_bone := -1         # the left hand: it holds the disc through a lefty forehand
var number_back: Label3D
var throwing := ""              # the throw clip last started
var throw_clock := 0.0          # where that clip is now (s)
var _run_speed := 1.0           # the fastest forward clip's own speed


static func clips() -> Dictionary:
	if _clips.is_empty():
		var f := FileAccess.open(PLAYERS_DIR + "clips.json", FileAccess.READ)
		_clips = JSON.parse_string(f.get_as_text())
	return _clips


## kit: {"jersey", "shorts", "sleeves" (the undershirt), "number", "outline"} colours.
func setup(variant: String, kit: Dictionary, number: int) -> void:
	if not _scenes.has(variant):
		_scenes[variant] = load(PLAYERS_DIR + "athlete_%s.glb" % variant)
	model = (_scenes[variant] as PackedScene).instantiate()
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	hand_bone = skeleton.find_bone("RightHand")
	off_hand_bone = skeleton.find_bone("LeftHand")
	_tint(kit, variant)
	_build_tree(variant)
	foot_lock = FootLock.new()
	skeleton.add_child(foot_lock)
	foot_lock.setup(skeleton, self)
	_toes = [skeleton.find_bone("LeftToeBase"), skeleton.find_bone("RightToeBase")]
	skeleton.skeleton_updated.connect(_on_skeleton_updated)
	_add_numbers(number, kit)


func _tint(kit: Dictionary, variant: String) -> void:
	for m: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var n := String(m.name)
		if HAIR_TINT.has(variant) and HAIR_NODES.any(func(h): return n.contains(h)):
			var hm := m.get_active_material(0)
			if hm is BaseMaterial3D:
				var dup := (hm as BaseMaterial3D).duplicate() as BaseMaterial3D
				dup.albedo_color = HAIR_TINT[variant]
				m.material_override = dup
			continue
		var c := Color.TRANSPARENT
		if n.begins_with("Jersey"):
			c = kit["jersey"]
		elif n.begins_with("Shorts"):
			c = kit["shorts"]
		elif n.begins_with("Sleeves") or n.begins_with("KneeSleeves") or n.begins_with("Headband"):
			c = kit["sleeves"]                           # the undershirt, knee sleeves and headbands match
		if c.a == 0.0:
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mat.roughness = 0.85
		m.material_override = mat


func _build_tree(variant: String) -> void:
	var info: Dictionary = clips()["clips"]
	var lib_names := anim.get_animation_list()
	var bs := AnimationNodeBlendSpace2D.new()
	bs.min_space = Vector2(-4.0, -3.0)
	bs.max_space = Vector2(4.0, 8.0)
	bs.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	for name: String in info:
		var c: Dictionary = info[name]
		if not c["loop"]:
			continue
		var a_name := _anim_name(lib_names, name)
		if a_name == "":
			continue
		anim.get_animation(a_name).loop_mode = Animation.LOOP_LINEAR
		var node := AnimationNodeAnimation.new()
		node.animation = a_name
		var v: Dictionary = c["velocity"].get(variant, c["velocity"].values()[0])   # this body's stride
		var pos := Vector2(v["right"], v["forward"])
		if name == "idle":
			pos = Vector2.ZERO
		bs.add_blend_point(node, pos)
		if pos.y > _run_speed:
			_run_speed = pos.y
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("loco", bs)
	var scale := AnimationNodeTimeScale.new()
	bt.add_node("scale", scale)
	bt.connect_node("scale", 0, "loco")
	var throw_anim := AnimationNodeAnimation.new()
	throw_anim.animation = _anim_name(lib_names, "backhand")
	bt.add_node("throw_anim", throw_anim)
	var seek := AnimationNodeTimeSeek.new()
	bt.add_node("seek", seek)
	bt.connect_node("seek", 0, "throw_anim")
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.08
	shot.fadeout_time = 0.35
	bt.add_node("throw", shot)
	bt.connect_node("throw", 0, "scale")
	bt.connect_node("throw", 1, "seek")
	bt.connect_node("output", 0, "throw")
	tree = AnimationTree.new()
	tree.tree_root = bt
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(anim)
	tree.active = true


func _anim_name(names: PackedStringArray, want: String) -> String:
	for n in names:
		if n == want or n.begins_with(want):
			return n
	return ""


## The number on the back (and smaller on the front), riding on the upper spine so it leans and twists with it.
func _add_numbers(number: int, kit: Dictionary) -> void:
	var spine := skeleton.find_bone("Spine1")
	if spine < 0 or number <= 0:                       # no number (an observer)
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "Spine1"
	skeleton.add_child(att)
	# In the skeleton's own space (upright, facing +Z), so it works before the athlete is in the scene tree.
	var rest := skeleton.get_bone_global_rest(spine)
	var back_h := rest.origin.y
	for side in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = str(number)
		l.font_size = 96 if side < 0 else 48
		l.pixel_size = 0.0028
		l.outline_size = 6
		l.modulate = kit["number"]
		l.outline_modulate = kit["outline"]
		l.double_sided = false
		# The model faces +Z: the back is -Z. A Label3D reads from +Z, so the back one is turned round.
		var want := Transform3D(Basis(Vector3.UP, PI if side < 0 else 0.0),
				Vector3(0.0, back_h - 0.02, 0.14 * side))
		l.transform = rest.affine_inverse() * want
		att.add_child(l)
		if side < 0:
			number_back = l


## Each frame: place the athlete at the player, turn towards the heading, and blend the clips by velocity.
func update_from(p: PlayerState, look: Vector3, dt: float) -> void:
	throw_clock += dt
	position = Vector3(p.pos.x, 0.0, p.pos.z)
	var v := Vector3(p.vel.x, 0.0, p.vel.z)
	var speed := v.length()
	var want := yaw
	if speed > FACE_MOVE:
		want = atan2(v.x, v.z)
	else:
		var to := Vector3(look.x - p.pos.x, 0.0, look.z - p.pos.z)
		if to.length() > 0.5:
			want = atan2(to.x, to.z)
		elif speed > 0.3:
			want = atan2(v.x, v.z)
	var d := wrapf(want - yaw, -PI, PI)
	yaw += clampf(d, -TURN_RATE * dt, TURN_RATE * dt)
	rotation = Vector3(0.0, yaw, 0.0)
	var f := Vector3(sin(yaw), 0.0, cos(yaw))
	var r := Vector3(-cos(yaw), 0.0, sin(yaw))
	var b := Vector2(v.dot(r), v.dot(f))
	var s := 1.0
	if b.length() > _run_speed:
		s = b.length() / _run_speed
		b = b / s
	tree.set("parameters/loco/blend_position", b)
	tree.set("parameters/scale/scale", s)


## A throw of this kind is wound up: the disc leaves the hand `lead` seconds from now (the sim's wind-up). The
## clip starts where its own release is `lead` ahead, so the two releases meet. A backhand (and a pull) is one
## of the two captured backhands; the forehand and the hammer are keyed.
func start_throw(kind: String, lead: float) -> void:
	var options: Array = THROW_CLIPS.get(kind, THROW_CLIPS["backhand"])
	var clip: String = options[randi() % options.size()]
	var node := (tree.tree_root as AnimationNodeBlendTree).get_node("throw_anim") as AnimationNodeAnimation
	node.animation = _anim_name(anim.get_animation_list(), clip)
	var rel: Variant = clips()["clips"][clip]["release"]
	tree.set("parameters/seek/seek_request", maxf(0.0, float(rel) - lead))
	tree.set("parameters/throw/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	throwing = clip
	throw_clock = maxf(0.0, float(rel) - lead)


## The disc has already gone (no wind-up seen): play the clip from just before its release.
func throw_now(kind: String = "backhand") -> void:
	start_throw(kind, THROW_LEAD)


func is_throwing() -> bool:
	return bool(tree.get("parameters/throw/active"))


func hand_position() -> Vector3:
	var b := off_hand_bone if throwing == "lefty_forehand" and is_throwing() else hand_bone
	if b < 0:
		return global_position + Vector3(0, 1.0, 0)
	return skeleton.global_transform * skeleton.get_bone_global_pose(b).origin


func blend_position() -> Vector2:
	return tree.get("parameters/loco/blend_position")


## After the skeleton's modifiers (the foot lock's IK): where the toes are drawn.
func _on_skeleton_updated() -> void:
	for k in 2:
		toes_final[k] = skeleton.global_transform * skeleton.get_bone_global_pose(_toes[k]).origin
