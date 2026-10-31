class_name ThrowSolver
extends RefCounted
## Finds the release (speed and heading) that brings a throw of a given kind down to catch height at a
## target spot, by flying the disc: the speed by bisection on the distance, the heading by correcting for
## the curve, a few rounds of each.

## Women's ultimate (PO 2026-10-30: "in the women's game the huck is low because women don't have the upper body
## strength to hurl the disk way high"): the fastest release is about 27 m/s (a long huck of about 44 m), a huck
## is a flat, low, driving throw, and a pull (with its run-up) about 29 m/s.
const MAX_SPEED := 27.0
const PULL_MAX_SPEED := 29.0
const MAX_REACH := 44.0         # m: the longest throw at MAX_SPEED (measured: a huck reaches 44.7 m)
const MIN_SPEED := 5.0
const CATCH_HEIGHT := 1.3
const SOLVE_DT := 1.0 / 60.0

## kind: [elevation deg, angle of attack deg, bank deg (+ curves right), release height m, side offset m]
## The bank and side are for a right-handed thrower: the backhand comes from the left side and bends
## left (outside-in), the forehand from the right and bends right; inside-out flips the bank.
## The hammer is released overhead and flies upside down: its axis is the upright attitude's, reversed.
const KINDS := {
	"backhand": [4.0, 3.0, -12.0, 1.0, -0.4],
	"forehand": [4.0, 3.0, 12.0, 0.9, 0.5],
	"hammer": [25.0, 4.0, 10.0, 2.0, 0.3],
	"pull": [13.0, 2.0, -8.0, 1.0, -0.4],
}
const HUCK_EXTRA := [3.0, 0.5]     # a huck: launch this much higher (elevation, angle of attack): low and driving
const HUCK_OVER := 22.0           # m/s: a flat throw that needs more than this is thrown as a huck


class Release:
	extends RefCounted
	var kind: String
	var state: DiscFlight.State     # the disc at release
	var speed: float
	var arrival: Vector3            # where it comes down to catch height
	var flight_time: float
	var path: Array                 # [[time, position], ...] from release to catch height
	var reachable: bool             # false: the target is beyond MAX_SPEED, so it falls short


static func release_state(thrower_pos: Vector3, heading: Vector3, kind: String, huck: bool,
		inside_out: bool, speed: float) -> DiscFlight.State:
	var k: Array = KINDS[kind]
	var el: float = deg_to_rad(k[0] + (HUCK_EXTRA[0] if huck else 0.0))
	var aoa: float = deg_to_rad(k[1] + (HUCK_EXTRA[1] if huck else 0.0))
	var bank: float = deg_to_rad(k[2] * (-1.0 if inside_out and kind != "hammer" else 1.0))
	var right := heading.cross(Vector3.UP).normalized()
	var pos := thrower_pos + Vector3(0.0, k[3], 0.0) + right * float(k[4])
	var vel := (heading * cos(el) + Vector3.UP * sin(el)) * speed
	var n := DiscFlight.attitude(heading, el + aoa, bank)
	if kind == "hammer":
		n = -n
	return DiscFlight.State.new(pos, vel, n)


static func _fly(s: DiscFlight.State) -> Array:
	return DiscFlight.simulate(s, SOLVE_DT, CATCH_HEIGHT)


static func solve(thrower_pos: Vector3, target: Vector3, kind: String, huck: bool = false,
		inside_out: bool = false) -> Release:
	var flat_target := Vector3(target.x, 0.0, target.z)
	var to_target := flat_target - Vector3(thrower_pos.x, 0.0, thrower_pos.z)
	var dist := to_target.length()
	var yaw := atan2(to_target.z, to_target.x)
	var top := PULL_MAX_SPEED if kind == "pull" else MAX_SPEED
	var speed := top
	var path: Array = []
	for _round in 4:
		var heading := Vector3(cos(yaw), 0.0, sin(yaw))
		var lo := MIN_SPEED
		var hi := top
		for _i in 14:
			var mid := 0.5 * (lo + hi)
			var p := _fly(release_state(thrower_pos, heading, kind, huck, inside_out, mid))
			var end: Vector3 = p[-1][1]
			var along := (Vector3(end.x, 0.0, end.z) - Vector3(thrower_pos.x, 0.0, thrower_pos.z)).dot(heading)
			if along < dist:
				lo = mid
			else:
				hi = mid
		speed = 0.5 * (lo + hi)
		path = _fly(release_state(thrower_pos, heading, kind, huck, inside_out, speed))
		var arrival: Vector3 = path[-1][1]
		var got := Vector3(arrival.x, 0.0, arrival.z) - Vector3(thrower_pos.x, 0.0, thrower_pos.z)
		yaw += wrapf(atan2(to_target.z, to_target.x) - atan2(got.z, got.x), -PI, PI)
	var heading := Vector3(cos(yaw), 0.0, sin(yaw))
	var r := Release.new()
	r.kind = kind
	r.speed = speed
	r.state = release_state(thrower_pos, heading, kind, huck, inside_out, speed)
	r.path = _fly(r.state)
	r.arrival = r.path[-1][1]
	r.flight_time = r.path[-1][0]
	r.reachable = Vector3(r.arrival.x, 0.0, r.arrival.z).distance_to(flat_target) < 1.5
	return r


## A throw at the default height for the target: a flat throw if it gets there, else a huck.
static func solve_auto(thrower_pos: Vector3, target: Vector3, kind: String, inside_out: bool = false) -> Release:
	var r := solve(thrower_pos, target, kind, false, inside_out)
	if not r.reachable or r.speed > HUCK_OVER:
		var h := solve(thrower_pos, target, kind, true, inside_out)
		if h.reachable or not r.reachable:
			return h
	return r
