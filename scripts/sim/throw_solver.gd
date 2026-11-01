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
const MAX_REACH := 40.0         # m: the longest huck shaped like a D1 huck on this disc model (ULTIMATE-7)
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
	# ULTIMATE-3 (PO: "Add cloud, high forehand, high backhand - these are commonly used"; no thumber):
	# Released at the shoulder to head, over the mark: about 1.5 m (the 2026 final's close-up of a marked handler;
	# was 1.85 and 1.8, unmeasured, out of a drawn arm's reach).
	"high_backhand": [2.0, 3.0, -12.0, 1.5, -0.3],
	"high_forehand": [2.0, 3.0, 12.0, 1.5, 0.4],
	"cloud": [15.0, 5.0, -4.0, 1.9, -0.3],              # a floater lofted from overhead into space (over the cup)
	"blade": [18.0, 4.0, -60.0, 1.2, -0.3],             # steeply banked: a slicing arc that drops fast
	"scoober": [30.0, 4.0, -10.0, 1.9, 0.0],            # overhead, upside down, short, spun the backhand way
	"push": [8.0, 6.0, 0.0, 1.1, 0.4],                  # a short soft push from the forehand side, little spin
	# The lefty forehand (PO 10-31: "add lefty forehand to the types of throws"; "right handed players also use lefty
	# forehand, especially handlers"): the off-hand flick, released wide on the backhand side and spun clockwise like
	# a backhand, so it flies like one, but from further out round the mark and quicker.
	"lefty_forehand": [4.0, 3.0, -12.0, 0.9, -0.7],
	# Breaks round the mark (ULTIMATE-7; the 2026 final's close-ups): a long step out under the marker's arm and a
	# release low, about knee height (0.5-0.6 m), wide of the body.
	"low_backhand": [4.0, 3.0, -12.0, 0.55, -0.8],
	"low_forehand": [4.0, 3.0, 12.0, 0.55, 0.9],
}
## The short throws' useful range, m (past it their flights balloon or dive).
const RANGE := {"cloud": 15.0, "blade": 15.0, "scoober": 15.0, "push": 12.0, "lefty_forehand": 25.0}
## Kinds that are a backhand or a forehand released differently: they use those throws' calibrated tables, from
## their own release height.
const FLAT_LIKE := {"high_backhand": "backhand", "high_forehand": "forehand", "lefty_forehand": "backhand",
		"low_backhand": "backhand", "low_forehand": "forehand"}
## The rigid disc (DiscFlight.rigid): a good thrower's releases by distance, rows [distance m, speed m/s, elevation,
## nose angle, bank] (degrees; a backhand's bank: negative is hyzer). Calibrated by tests/probe_calibrate.gd (Potts
## and Crowther coefficients, advance ratio 0.5, released 1 m up). The solver fine-tunes the speed within SPEED_BAND
## of the row's and corrects the aim; with the angles fixed, a throw far off its speed dives or balloons.
## PROFILE (flat): of all releases up to 27 m/s, the one that gets there soonest at a catchable height (0.6-2.6 m),
## arriving no faster than 14 m/s, never more than 3 m off line or 3.5 m up.
## From 25 m the rows are hucks shaped like a D1 huck (ULTIMATE-7, probe_calibrate.gd MODE=huck: no air bounce, never
## back towards the thrower, the top before 75% of the flight, above 1 m for its first two thirds); the soonest-
## arriving rows before them dipped to the turf and climbed again, and one drifted back (PO: "a beginner's mistake").
## Nothing so shaped reaches 45 m on this disc model.
const PROFILE := [[8.0, 17.0, 0.0, 3.0, 0.0], [12.0, 19.0, 0.0, 3.0, 0.0], [16.0, 20.0, 0.0, -2.0, -8.0],
		[20.0, 21.0, 0.0, -6.0, 0.0], [25.0, 20.0, 9.0, -16.0, -48.0], [27.5, 20.0, 9.0, -16.0, -48.0],
		[30.0, 16.0, 5.0, -8.0, -8.0], [32.5, 17.0, 13.0, -16.0, -16.0], [35.0, 18.0, 11.0, -16.0, -16.0],
		[37.5, 19.0, 11.0, -16.0, -24.0], [40.0, 20.0, 9.0, -16.0, -32.0]]
## PROFILE_IO: the same with the bank the other way (up to 6 m of curve). None reaches past 25 m: a fast disc banked
## that way turns over.
const PROFILE_IO := [[8.0, 17.0, 0.0, 3.0, 4.0], [12.0, 18.0, 0.0, -2.0, 4.0], [16.0, 20.0, 0.0, 0.0, 4.0],
		[20.0, 21.0, 0.0, -4.0, 4.0], [25.0, 23.0, 0.0, -8.0, 4.0]]
## PROFILE_PULL: the longest hang time to where it lands (up to 29 m/s, at most 6 m off line and 16 m up): heavy
## hyzer, 6.3-6.8 s in the air.
const PROFILE_PULL := [[30.0, 29.0, 12.0, -6.0, -48.0], [35.0, 28.0, 12.0, -10.0, -48.0], [40.0, 28.0, 8.0, -8.0, -48.0],
		[45.0, 27.0, 8.0, -13.0, -48.0]]
const SPEED_BAND := 0.15
const ADVANCE := 0.5               # spin: the rim's speed over the flight speed (d w / 2 v)
## Spin sense by kind (seen from the disc's top face): a right-hander's backhand and pull clockwise (-1), forehand
## and hammer anticlockwise (+1).
const SPIN := {"backhand": -1.0, "forehand": 1.0, "hammer": 1.0, "pull": -1.0, "high_backhand": -1.0,
		"high_forehand": 1.0, "cloud": -1.0, "blade": -1.0, "scoober": -1.0, "push": 0.4, "lefty_forehand": -1.0,
		"low_backhand": -1.0, "low_forehand": 1.0}
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


## The rigid disc's release for a distance: [speed, elevation, nose, bank], interpolated in a table; null when the
## kind has no table (the hammer keeps its fixed angles).
static func profile(kind: String, inside_out: bool, dist: float) -> Variant:
	var table: Array = PROFILE_PULL if kind == "pull" else (PROFILE_IO if inside_out else PROFILE)
	if not (kind in ["backhand", "forehand", "pull"] or FLAT_LIKE.has(kind)):
		return null
	if dist <= table[0][0]:
		return table[0].slice(1)
	for i in range(1, table.size()):
		if dist <= table[i][0]:
			var a: Array = table[i - 1]
			var b: Array = table[i]
			var f: float = (dist - a[0]) / (b[0] - a[0])
			return [lerpf(a[1], b[1], f), lerpf(a[2], b[2], f), lerpf(a[3], b[3], f), lerpf(a[4], b[4], f)]
	return table[-1].slice(1)


static func release_state(thrower_pos: Vector3, heading: Vector3, kind: String, huck: bool,
		inside_out: bool, speed: float, dist: float = -1.0) -> DiscFlight.State:
	var k: Array = KINDS[kind]
	var el: float = deg_to_rad(k[0] + (HUCK_EXTRA[0] if huck else 0.0))
	var aoa: float = deg_to_rad(k[1] + (HUCK_EXTRA[1] if huck else 0.0))
	var bank: float = deg_to_rad(k[2] * (-1.0 if inside_out and kind != "hammer" else 1.0))
	var pr: Variant = null
	if DiscFlight.rigid and dist > 0.0 and profile(kind, inside_out, 10.0) != null:
		pr = _row if _row != null else profile(kind, inside_out, dist)
	if pr != null:
		# The release for the distance (a huck is the same throw, longer). The tables are a backhand's; a forehand
		# spins the other way, so its bank mirrors.
		el = deg_to_rad(pr[1])
		aoa = deg_to_rad(pr[2])
		bank = deg_to_rad(pr[3] * signf(float(SPIN[kind])) * -1.0)
	var right := heading.cross(Vector3.UP).normalized()
	var pos := thrower_pos + Vector3(0.0, k[3], 0.0) + right * float(k[4])
	var vel := (heading * cos(el) + Vector3.UP * sin(el)) * speed
	var n := DiscFlight.attitude(heading, el + aoa, bank)
	if kind == "hammer" or kind == "scoober":
		n = -n
	var st := DiscFlight.State.new(pos, vel, n)
	st.set_spin(float(SPIN[kind]) * ADVANCE * 2.0 * speed / DiscFlight.H_D)
	return st


## The wind the thrower allows for (the match's steady wind; its gusts are not foreseen).
static var wind := Vector3.ZERO


static func _fly(s: DiscFlight.State, to_ground: bool = false) -> Array:
	return DiscFlight.simulate(s, SOLVE_DT, 0.0 if to_ground else CATCH_HEIGHT, 12.0, wind)


## Where a flight first gets `dist` along `heading` from the thrower: [time, position], or [] if it never does.
static func _crossing(path: Array, from: Vector3, heading: Vector3, dist: float) -> Array:
	var o := Vector3(from.x, 0.0, from.z)
	for i in range(1, path.size()):
		var q: Vector3 = path[i][1]
		var along := (Vector3(q.x, 0.0, q.z) - o).dot(heading)
		if along >= dist:
			var q0: Vector3 = path[i - 1][1]
			var a0 := (Vector3(q0.x, 0.0, q0.z) - o).dot(heading)
			var f := clampf((dist - a0) / maxf(along - a0, 1e-6), 0.0, 1.0)
			return [lerpf(path[i - 1][0], path[i][0], f), q0.lerp(q, f)]
	return []


## The flight cut where it passes the target distance (the arrival is the catch); whole if it never does.
static func _to_crossing(path: Array, from: Vector3, heading: Vector3, dist: float) -> Array:
	var c := _crossing(path, from, heading, dist)
	if c.is_empty():
		return path
	var out: Array = []
	for e in path:
		if e[0] >= c[0]:
			break
		out.append(e)
	out.append(c)
	return out


static func solve(thrower_pos: Vector3, target: Vector3, kind: String, huck: bool = false,
		inside_out: bool = false) -> Release:
	var r := _solve(thrower_pos, target, kind, huck, inside_out, null)
	if r.reachable or not DiscFlight.rigid or profile(kind, inside_out, 10.0) == null:
		return r
	# The rigid disc: the interpolated release sits on a knife edge near some distances; try the table's rows round
	# it and keep the best (reachable first, then the nearest miss).
	var table: Array = PROFILE_PULL if kind == "pull" else (PROFILE_IO if inside_out else PROFILE)
	var dist := Vector2(target.x - thrower_pos.x, target.z - thrower_pos.z).length()
	var best := r
	var best_miss := Vector3(r.arrival.x, 0, r.arrival.z).distance_to(Vector3(target.x, 0, target.z))
	for row: Array in table:
		if absf(row[0] - dist) > 12.0:
			continue
		var t := _solve(thrower_pos, target, kind, huck, inside_out, row.slice(1))
		var miss := Vector3(t.arrival.x, 0, t.arrival.z).distance_to(Vector3(target.x, 0, target.z))
		if (t.reachable and not best.reachable) or (t.reachable == best.reachable and miss < best_miss):
			best = t
			best_miss = miss
			if t.reachable:
				break
	return best


static var _row: Variant = null     # a table row forced by solve's retry (else interpolated by distance)


static func _solve(thrower_pos: Vector3, target: Vector3, kind: String, huck: bool, inside_out: bool,
		fixed: Variant) -> Release:
	_row = fixed
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
		var pr: Variant = (fixed if fixed != null else profile(kind, inside_out, dist)) if DiscFlight.rigid else null
		if pr != null:
			lo = pr[0] * (1.0 - SPEED_BAND)
			hi = minf(top, pr[0] * (1.0 + SPEED_BAND))
		var passing := pr != null and kind != "pull"
		for _i in 14:
			var mid := 0.5 * (lo + hi)
			var p := _fly(release_state(thrower_pos, heading, kind, huck, inside_out, mid, dist), passing)
			if passing:
				# The rigid disc's passes are caught on the way through: aim for it to pass the target at catch
				# height (too low or short: faster).
				var c := _crossing(p, thrower_pos, heading, dist)
				if c.is_empty() or c[1].y < CATCH_HEIGHT:
					lo = mid
				else:
					hi = mid
				continue
			var end: Vector3 = p[-1][1]
			var along := (Vector3(end.x, 0.0, end.z) - Vector3(thrower_pos.x, 0.0, thrower_pos.z)).dot(heading)
			if along < dist:
				lo = mid
			else:
				hi = mid
		speed = 0.5 * (lo + hi)
		path = _fly(release_state(thrower_pos, heading, kind, huck, inside_out, speed, dist), passing)
		if passing:
			path = _to_crossing(path, thrower_pos, heading, dist)
		var arrival: Vector3 = path[-1][1]
		var got := Vector3(arrival.x, 0.0, arrival.z) - Vector3(thrower_pos.x, 0.0, thrower_pos.z)
		yaw += wrapf(atan2(to_target.z, to_target.x) - atan2(got.z, got.x), -PI, PI)
	var heading := Vector3(cos(yaw), 0.0, sin(yaw))
	var r := Release.new()
	r.kind = kind
	r.speed = speed
	r.state = release_state(thrower_pos, heading, kind, huck, inside_out, speed, dist)
	var pr_end: Variant = (fixed if fixed != null else profile(kind, inside_out, dist)) if DiscFlight.rigid else null
	var passing_end := pr_end != null and kind != "pull"
	r.path = _fly(r.state, passing_end)
	if passing_end:
		r.path = _to_crossing(r.path, thrower_pos, heading, dist)
	r.arrival = r.path[-1][1]
	r.flight_time = r.path[-1][0]
	r.reachable = dist <= float(RANGE.get(kind, 1e9)) \
			and Vector3(r.arrival.x, 0.0, r.arrival.z).distance_to(flat_target) < 1.5 \
			and (not passing_end or (r.arrival.y > 0.3 and r.arrival.y < 2.6))     # knee height to a jumping catch
	_row = null
	return r


## A throw at the default height for the target: a flat throw if it gets there, else a huck.
static func solve_auto(thrower_pos: Vector3, target: Vector3, kind: String, inside_out: bool = false) -> Release:
	var r := solve(thrower_pos, target, kind, false, inside_out)
	if not r.reachable or r.speed > HUCK_OVER:
		var h := solve(thrower_pos, target, kind, true, inside_out)
		if h.reachable or not r.reachable:
			return h
	return r
