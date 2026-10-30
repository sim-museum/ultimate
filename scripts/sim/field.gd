class_name Field
extends RefCounted
## The playing field, after the WFDF championship field: 100 m by 37 m, an 18 m end zone at each end
## (so a 64 m central zone), brick marks 18 m in from each goal line, midway between the sidelines.
## x runs along the field (the end zones at -x and +x), z across it, y up. Lines are out of bounds.

const LENGTH := 100.0
const WIDTH := 37.0
const ENDZONE := 18.0
const BRICK := 18.0

const HALF_L := LENGTH / 2.0                  # 50: the back of each end zone
const HALF_W := WIDTH / 2.0                   # 18.5: the sidelines
const GOAL_LINE := HALF_L - ENDZONE           # 32: the goal lines at x = -32 and +32


static func in_bounds(p: Vector3) -> bool:
	return absf(p.x) < HALF_L and absf(p.z) < HALF_W


## Whether `p` is inside the end zone that a team attacking in direction `dir` (+1 or -1) scores in.
## The goal line belongs to the central zone, so a catch on it is not a goal.
static func in_attacking_endzone(p: Vector3, dir: int) -> bool:
	return in_bounds(p) and p.x * dir > GOAL_LINE


static func goal_line_x(dir: int) -> float:
	return GOAL_LINE * dir


static func brick(dir: int) -> Vector3:
	## The brick mark a team attacking in `dir` restarts from: the one nearer its own end zone.
	return Vector3(-dir * (GOAL_LINE - BRICK), 0.0, 0.0)


## Where play restarts after the disc went out at `exit`: the nearest point of the central zone or
## field on the line, pulled 0.5 m inside the sideline.
static func restart_point(exit: Vector3) -> Vector3:
	return Vector3(clampf(exit.x, -HALF_L + 0.5, HALF_L - 0.5), 0.0, clampf(exit.z, -HALF_W + 0.5, HALF_W - 0.5))


## An attacking team that takes possession in the end zone it attacks... cannot; one in its own end zone
## walks the disc up to the goal line (WFDF: a turnover in the defended end zone restarts on the goal line).
static func clamp_restart(p: Vector3, dir: int) -> Vector3:
	var q := Vector3(p.x, 0.0, clampf(p.z, -HALF_W + 0.5, HALF_W - 0.5))
	if q.x * dir < -GOAL_LINE:
		q.x = -GOAL_LINE * dir
	return q
