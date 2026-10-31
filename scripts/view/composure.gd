class_name Composure
extends SkeletonModifier3D
## Body language (ULTIMATE-6): a player's nerves, drawn over whatever clip she is playing. Stirred nerves raise and
## tighten the shoulders and quicken and shorten the breath; after a mistake of her own the head drops for a moment
## (Inner.slump). Self-led, the breath is slow and the shoulders down. Works in skeleton space (the model faces +Z,
## its left is +X), so it does not depend on the bones' own axes.

const SHOULDERS := 14.0        # degrees the shoulders rise, fully stirred
const BREATH := [0.22, 0.6]    # breaths a second: Self-led, fully stirred
const BREATH_DEPTH := [2.0, 1.0]   # degrees of chest lift a breath: slow and deep, or quick and shallow
const HEAD_DROP := 28.0        # degrees the head drops after her own mistake

var nerves := 0.0              # set each frame by the athlete (Inner.nerves)
var slump := 0.0               # 0-1: just made a mistake
var _phase := 0.0
var _b := {}


func _ready() -> void:
	var skel := get_skeleton()
	for n in ["LeftShoulder", "RightShoulder", "Spine1", "Neck1"]:
		_b[n] = skel.find_bone(n)


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _b.is_empty():
		return
	var rate := lerpf(BREATH[0], BREATH[1], nerves)
	_phase = fmod(_phase + delta * rate * TAU, TAU)
	var breath := 0.5 - 0.5 * cos(_phase)                    # 0 out, 1 in
	var depth := lerpf(BREATH_DEPTH[0], BREATH_DEPTH[1], nerves)
	# The chest lifts on the in-breath: Spine1 pitches back a little (about +X, the body's left: back is -).
	_rotate_global(skel, _b["Spine1"], Vector3.RIGHT, -deg_to_rad(depth * breath))
	# The shoulders: up with nerves, and a little with each breath.
	var up := deg_to_rad(SHOULDERS * nerves + 1.5 * breath)
	_rotate_global(skel, _b["LeftShoulder"], Vector3.BACK, up)      # left (+X) up: about +Z
	_rotate_global(skel, _b["RightShoulder"], Vector3.BACK, -up)    # right (-X) up: about -Z
	# The head drops after her own mistake.
	if slump > 0.0:
		_rotate_global(skel, _b["Neck1"], Vector3.RIGHT, deg_to_rad(HEAD_DROP * slump))


## Rotate a bone by `angle` about a skeleton-space axis, in place (its children follow).
func _rotate_global(skel: Skeleton3D, b: int, axis: Vector3, angle: float) -> void:
	if b < 0 or absf(angle) < 1e-5:
		return
	var g := skel.get_bone_global_pose(b)
	g.basis = Basis(axis, angle) * g.basis
	skel.set_bone_global_pose(b, g)
