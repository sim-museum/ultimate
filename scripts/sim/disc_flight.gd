class_name DiscFlight
extends RefCounted
## Disc flight: gravity plus lift and drag, with the disc's attitude held fixed through the flight (the
## point-mass model, without the pitching and rolling moments that make a real disc fade late).
##
## Coefficients: the set used in open frisbee flight models (CL0 0.1, CLA 1.4, CD0 0.08, CDA 2.72,
## alpha0 -4 degrees, 0.175 kg, 0.0568 m^2), after Hummel's frisbee flight work (UC Davis, 2003).
## Provisional: to be checked against Hummel's thesis.
##   lift  = 1/2 rho v^2 A (CL0 + CLA alpha)              perpendicular to the velocity, on the disc's top side
##   drag  = 1/2 rho v^2 A (CD0 + CDA (alpha - alpha0)^2)  against the velocity
## alpha, the angle of attack, is positive when the air meets the disc's underside.

const RHO := 1.23
const AREA := 0.0568
const MASS := 0.175
const CL0 := 0.1
const CLA := 1.4
const CD0 := 0.08
const CDA := 2.72
const ALPHA0 := -4.0 * PI / 180.0
const G := Vector3(0.0, -9.81, 0.0)
const RADIUS := 0.137


class State:
	extends RefCounted
	var pos: Vector3
	var vel: Vector3
	var normal: Vector3          # the disc's axis, out of its top face (straight up for a flat throw)
	var time := 0.0

	func _init(p: Vector3 = Vector3.ZERO, v: Vector3 = Vector3.ZERO, n: Vector3 = Vector3.UP) -> void:
		pos = p
		vel = v
		normal = n.normalized()

	func copy() -> State:
		var s := State.new(pos, vel, normal)
		s.time = time
		return s


static func angle_of_attack(vel: Vector3, normal: Vector3) -> float:
	if vel.length_squared() < 1e-6:
		return 0.0
	return -asin(clampf(vel.normalized().dot(normal), -1.0, 1.0))


static func acceleration(vel: Vector3, normal: Vector3, wind: Vector3 = Vector3.ZERO) -> Vector3:
	var air := vel - wind
	var v2 := air.length_squared()
	if v2 < 1e-6:
		return G
	var vhat := air / sqrt(v2)
	var alpha := -asin(clampf(vhat.dot(normal), -1.0, 1.0))
	var q := 0.5 * RHO * v2 * AREA
	var lift_dir := normal - normal.dot(vhat) * vhat
	var lift := Vector3.ZERO
	if lift_dir.length_squared() > 1e-9:
		lift = lift_dir.normalized() * q * (CL0 + CLA * alpha)
	var drag := -vhat * q * (CD0 + CDA * (alpha - ALPHA0) * (alpha - ALPHA0))
	return G + (lift + drag) / MASS


## One step of length `dt` (midpoint method: steady at the 1/120 s physics tick).
static func step(s: State, dt: float, wind: Vector3 = Vector3.ZERO) -> void:
	var a1 := acceleration(s.vel, s.normal, wind)
	var v_mid := s.vel + a1 * (dt * 0.5)
	var a2 := acceleration(v_mid, s.normal, wind)
	s.pos += v_mid * dt
	s.vel += a2 * dt
	s.time += dt


## The disc's attitude for a release: the axis tilted back by `pitch` (nose up) and banked by `roll`
## about the direction of flight `heading` (a horizontal unit vector). roll > 0 dips the disc's
## right edge (looking along the flight), so the lift leans right and the disc curves right.
static func attitude(heading: Vector3, pitch: float, roll: float) -> Vector3:
	var right := heading.cross(Vector3.UP).normalized()
	var n := Vector3.UP.rotated(right, pitch)       # rotating up about "right" tilts the top backwards
	return n.rotated(heading, roll).normalized()        # about the heading: up turns towards "right"


## Flies the disc until it comes down through `catch_height` (or reaches the ground), and returns the
## sampled path: an Array of [time, position]. `max_time` caps runaway flights.
static func simulate(s0: State, dt: float = 1.0 / 120.0, catch_height: float = 0.0,
		max_time: float = 12.0, wind: Vector3 = Vector3.ZERO) -> Array:
	var s := s0.copy()
	var path: Array = [[0.0, s.pos]]
	while s.time < max_time:
		var prev := s.pos
		step(s, dt, wind)
		path.append([s.time, s.pos])
		if s.pos.y <= catch_height and s.vel.y < 0.0 and prev.y > catch_height:
			break
		if s.pos.y <= 0.0:
			break
	return path
