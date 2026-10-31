class_name FootLock
extends SkeletonModifier3D
## Foot locking (ULTIMATE-2): a planted foot stays where it was put down while the body turns, slows or speeds up
## over it, instead of skating with the clip. Runs on the animated pose, before a TwoBoneIK3D (which it adds
## after itself) that bends each leg to reach its target.
##
## Each frame, for each foot: the animated ankle's place in the world. A foot is planted when the ankle is within
## PLANT of its standing height; a newly planted foot is locked where it is. A locked foot lets go when the clip
## lifts it (LIFT above standing height) or when the body has moved so far that the leg would overstretch
## (STRIDE from the animated place). The IK target eases between the animated and the locked place (EASE s), so a
## foot never jumps.

const FEET := [["LeftUpLeg", "LeftLeg", "LeftFoot"], ["RightUpLeg", "RightLeg", "RightFoot"]]
const PLANT := 0.06               # m above standing height: planted
const LIFT := 0.09                 # m: the clip has lifted it
const STRIDE := 0.45               # m from the animated place: let go
const EASE := 0.04                 # s to blend a lock in or out

var targets: Array[Node3D] = []
var poles: Array[Node3D] = []
var locked: Array[bool] = [false, false]
var lock_at: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var weight: Array[float] = [0.0, 0.0]
var stand_h: Array[float] = [0.0, 0.0]   # the ankle's height standing (rest pose, skeleton space)
var bones: Array = []                     # [upper, lower, foot] bone indices per foot
var ik: TwoBoneIK3D
var holder: Node3D                        # where the target and pole nodes live (the athlete)


## Called once the skeleton is in place: the targets, the poles and the IK after this modifier.
func setup(skel: Skeleton3D, owner_node: Node3D) -> void:
	holder = owner_node
	ik = TwoBoneIK3D.new()
	ik.set_setting_count(FEET.size())
	skel.add_child(ik)
	for i in FEET.size():
		var b: Array = FEET[i]
		bones.append([skel.find_bone(b[0]), skel.find_bone(b[1]), skel.find_bone(b[2])])
		stand_h[i] = skel.get_bone_global_rest(bones[i][2]).origin.y
		var t := Node3D.new()
		var p := Node3D.new()
		holder.add_child(t)
		holder.add_child(p)
		targets.append(t)
		poles.append(p)
		ik.set_root_bone_name(i, b[0])
		ik.set_middle_bone_name(i, b[1])
		ik.set_end_bone_name(i, b[2])
		ik.set_target_node(i, ik.get_path_to(t))
		ik.set_pole_node(i, ik.get_path_to(p))


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or bones.is_empty():
		return
	var xf := skel.global_transform
	var fwd := holder.global_transform.basis.z if holder != null else Vector3.BACK      # the model faces +Z
	fwd = Vector3(fwd.x, 0, fwd.z).normalized()
	for i in FEET.size():
		var foot_s := skel.get_bone_global_pose(bones[i][2]).origin
		var foot: Vector3 = xf * foot_s
		var knee: Vector3 = xf * skel.get_bone_global_pose(bones[i][1]).origin
		var above := foot_s.y - stand_h[i]
		if not locked[i] and above < PLANT:
			locked[i] = true
			lock_at[i] = foot
		elif locked[i]:
			var drift := Vector2(foot.x - lock_at[i].x, foot.z - lock_at[i].z).length()
			if above > LIFT or drift > STRIDE:
				locked[i] = false
		weight[i] = move_toward(weight[i], 1.0 if locked[i] else 0.0, delta / EASE)
		var held := Vector3(lock_at[i].x, foot.y, lock_at[i].z)
		targets[i].global_position = foot.lerp(held, weight[i])
		poles[i].global_position = knee + fwd * 0.6 + Vector3(0, 0.1, 0)


## How far each foot's IK target is from its animated place now (m): 0 when nothing is held.
func correction(i: int) -> float:
	var skel := get_skeleton()
	var foot: Vector3 = skel.global_transform * skel.get_bone_global_pose(bones[i][2]).origin
	return Vector2(targets[i].global_position.x - foot.x, targets[i].global_position.z - foot.z).length()
