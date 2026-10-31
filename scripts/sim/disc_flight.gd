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

## The rigid disc (ULTIMATE-3): Hummel's six-degree-of-freedom model. S. A. Hummel, "Frisbee Flight Simulation and
## Throw Biomechanics", M.S. thesis, University of California, Davis (2003): eqs. 3.3-3.8, Table 3-1 (the disc),
## Table 3-2 (the coefficients: the "short flights" set, with the "long flight" f2302 damping coefficients, as her
## simulation code in the appendix uses them; CRr as that code applies it, scaled by sqrt(d/g)).
##   roll moment  R = 1/2 rho v^2 A d (CRr sqrt(d/g) w_spin + CRp w_roll)        about the in-plane velocity
##   pitch moment M = 1/2 rho v^2 A d (CM0 + CMa alpha + CMq w_pitch)            about (in-plane velocity x axis)
##   spin down    N = CNr w_spin                                                  about the axis
## The attitude then moves: a nose-up moment on a spinning disc rolls it (gyroscopic precession), which is the late
## fade of a slowing disc, and turnover, flip-up and air bounce come from the same equations.
static var rigid := false          # true: the rigid disc; false: the fixed-attitude point mass above
## The lift, drag and pitch coefficients [CL0, CLA, CD0, CDA, CM0, CMA]: "hummel" (her short flights, about 13 m/s)
## or "potts" (Potts and Crowther's wind-tunnel measurements, linearised as in Hummel's Table 3-2). The damping
## and spin terms are Hummel's in both.
const COEF_SETS := {"hummel": [0.3331, 1.9124, 0.1769, 0.685, -0.0821, 0.4338],
		"potts": [0.2, 2.96, 0.08, 2.72, -0.02, 0.13]}
static var coef: Array = COEF_SETS["hummel"]
const H_CL0 := 0.3331
const H_CLA := 1.9124
const H_CD0 := 0.1769
const H_CDA := 0.685
const H_CM0 := -0.0821
const H_CMA := 0.4338
const H_CMQ := -1.44e-2
const H_CRR := 0.00171
const H_CRP := -1.25e-2
const H_CNR := -3.41e-5
const H_AREA := 0.057
const H_D := 0.269
const IZZ := 0.00235               # kg m^2, about the axis (measured, Table 2-2)
const IXX := 0.00122               # about a diameter


class State:
	extends RefCounted
	var pos: Vector3
	var vel: Vector3
	var normal: Vector3          # the disc's axis, out of its top face (straight up for a flat throw)
	var ang := Vector3.ZERO      # angular momentum (the rigid disc), kg m^2/s
	var time := 0.0

	func _init(p: Vector3 = Vector3.ZERO, v: Vector3 = Vector3.ZERO, n: Vector3 = Vector3.UP) -> void:
		pos = p
		vel = v
		normal = n.normalized()

	## Spin about the axis, rad/s: positive is anticlockwise seen from the top face (a right-hander's forehand
	## and hammer), negative clockwise (the backhand).
	func set_spin(w: float) -> void:
		ang = normal * (w * IZZ)

	func spin() -> float:
		return ang.dot(normal) / IZZ

	## Turn the whole disc about the vertical (a throw's aim error).
	func turn(yaw: float) -> void:
		vel = vel.rotated(Vector3.UP, yaw)
		normal = normal.rotated(Vector3.UP, yaw)
		ang = ang.rotated(Vector3.UP, yaw)

	func copy() -> State:
		var s := State.new(pos, vel, normal)
		s.ang = ang
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


## The rigid disc's angular velocity from its angular momentum (axisymmetric: Ixx about every diameter).
static func omega(ang: Vector3, n: Vector3) -> Vector3:
	var along := ang.dot(n)
	return (ang - n * along) / IXX + n * (along / IZZ)


## The rigid disc's derivatives: [acceleration, torque] for velocity v, axis n, angular momentum L.
static func rigid_rates(v: Vector3, n: Vector3, L: Vector3, wind: Vector3) -> Array:
	var air := v - wind
	var v2 := air.length_squared()
	var w := omega(L, n)
	var w_spin := w.dot(n)
	if v2 < 1e-6:
		return [G, n * (H_CNR * w_spin)]
	var vm := sqrt(v2)
	var vhat := air / vm
	var vn := air.dot(n)
	var vp := air - n * vn                      # the velocity in the disc's plane
	var vp_len := vp.length()
	var alpha := atan2(-vn, vp_len)             # positive: the air meets the underside
	var q := 0.5 * RHO * v2 * H_AREA
	var u_vp := vp / vp_len if vp_len > 1e-6 else Vector3.ZERO
	var u_pitch := u_vp.cross(n)               # a positive moment about it lifts the nose
	var cl: float = coef[0] + coef[1] * alpha
	var a0: float = -coef[0] / coef[1]
	var cd: float = coef[2] + coef[3] * (alpha - a0) * (alpha - a0)
	var lift_dir := u_pitch.cross(vhat)         # perpendicular to the flight, on the top side
	var acc := G + (lift_dir * (cl * q) - vhat * (cd * q)) / MASS
	var roll := q * H_D * (sqrt(H_D / 9.81) * H_CRR * (-w_spin) + H_CRP * w.dot(u_vp))
	var pitch: float = q * H_D * (coef[4] + coef[5] * alpha + H_CMQ * w.dot(u_pitch))
	# Hummel's spin is positive clockwise seen from the top (his axis points down): hence -w_spin in the roll term.
	var torque := u_vp * roll + u_pitch * pitch + n * (H_CNR * w_spin)
	return [acc, torque]


## One rigid-disc step (RK4 on position, velocity, axis and angular momentum).
static func rigid_step(s: State, dt: float, wind: Vector3) -> void:
	var p0 := s.pos
	var v0 := s.vel
	var n0 := s.normal
	var l0 := s.ang
	var k1 := rigid_rates(v0, n0, l0, wind)
	var nd1 := omega(l0, n0).cross(n0)
	var v1: Vector3 = v0 + k1[0] * (dt * 0.5)
	var n1 := (n0 + nd1 * (dt * 0.5)).normalized()
	var l1: Vector3 = l0 + k1[1] * (dt * 0.5)
	var k2 := rigid_rates(v1, n1, l1, wind)
	var nd2 := omega(l1, n1).cross(n1)
	var v2: Vector3 = v0 + k2[0] * (dt * 0.5)
	var n2 := (n0 + nd2 * (dt * 0.5)).normalized()
	var l2: Vector3 = l0 + k2[1] * (dt * 0.5)
	var k3 := rigid_rates(v2, n2, l2, wind)
	var nd3 := omega(l2, n2).cross(n2)
	var v3: Vector3 = v0 + k3[0] * dt
	var n3 := (n0 + nd3 * dt).normalized()
	var l3: Vector3 = l0 + k3[1] * dt
	var k4 := rigid_rates(v3, n3, l3, wind)
	var nd4 := omega(l3, n3).cross(n3)
	s.pos = p0 + (v0 + v1 * 2.0 + v2 * 2.0 + v3) * (dt / 6.0)
	s.vel = v0 + (k1[0] + k2[0] * 2.0 + k3[0] * 2.0 + k4[0]) * (dt / 6.0)
	s.normal = (n0 + (nd1 + nd2 * 2.0 + nd3 * 2.0 + nd4) * (dt / 6.0)).normalized()
	s.ang = l0 + (k1[1] + k2[1] * 2.0 + k3[1] * 2.0 + k4[1]) * (dt / 6.0)
	s.time += dt


## One step of length `dt` (midpoint method: steady at the 1/120 s physics tick).
static func step(s: State, dt: float, wind: Vector3 = Vector3.ZERO) -> void:
	if rigid:
		rigid_step(s, dt, wind)
		return
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
