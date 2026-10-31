class_name PlayerState
extends RefCounted
## One player: where they are, where they are heading, and what they are doing.

const SPRINT := 7.2            # m/s, a quick player's top speed
const ACCEL := 6.0             # m/s^2
const STOP := 9.0              # m/s^2: stopping after a catch (no travelling)

var team: int
var idx: int
var number: int
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var goal := Vector3.ZERO       # where the player is running to
var speed := SPRINT            # this player's top speed
var role := "stack"            # stack, cut, clear, dump, hold, mark, chase, receive, pull, line
var timer := 0.0               # time left in the current role
var mark: PlayerState          # a defender's assignment (person-to-person)
var zone_role := ""            # in a zone defence: cup, middle, wing_l, wing_r or deep (the cup player nearest
                               # the thrower marks)
var steer := Vector3.ZERO      # a human player's stick direction (zero: the AI moves them)
var sprint := false            # run through the goal at full speed (attacking the disc), no slowing down
var inner: Inner               # her inner world: Self, the exile's nerves, the protectors (ULTIMATE-6)


func _init(t: int, i: int, n: int) -> void:
	team = t
	idx = i
	number = n


func move(dt: float) -> void:
	var want := Vector3.ZERO
	if steer.length_squared() > 0.01:
		want = steer.normalized() * speed
	else:
		var to := Vector3(goal.x - pos.x, 0.0, goal.z - pos.z)
		var d := to.length()
		if d > 0.05:
			# Slow down on arrival: the speed that still stops within the distance left.
			want = to / d * (speed if sprint else minf(speed, sqrt(2.0 * ACCEL * d)))
	var dv := want - vel
	var a := STOP if want.length() < vel.length() else ACCEL
	if dv.length() > a * dt:
		dv = dv.normalized() * a * dt
	vel += dv
	pos += vel * dt
	pos.y = 0.0
	sprint = false


func stop(dt: float) -> void:
	var s := vel.length()
	if s > 0.0:
		vel = vel.normalized() * maxf(0.0, s - STOP * dt)
	pos += vel * dt
	goal = pos
