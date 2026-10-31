class_name UltimateMatch
extends RefCounted
## A game of ultimate, seven against seven, self-refereed (WFDF rules of ultimate, 2025-2028): the pull,
## no running with the disc, the marker's count to ten, turnovers on a drop, a block, an interception,
## out of bounds or a stall, and a goal for a catch in the attacked end zone. First to 15.
## No rendering here: the view reads the state, and the tests drive it headless.

const PLAYERS := 7
const GAME_TO := 15
const STALL := 10
const REACH := 1.1             # m: how far from a player the disc can be caught (arm and lean)
const DEF_REACH := 0.9         # m: a defender's reach for a block (across the receiver, often from behind)
const DEF_SURE := 0.45         # m: a sure block
const DEF_CHANCE := 0.12       # a block's chance per tick between DEF_SURE and DEF_REACH
const LAYOUT_REACH := 2.4      # m: a full-length dive
const LAYOUT_TOP := 1.0        # m: a layout is for a low disc
const LAYOUT_CHANCE := 0.05    # per tick (120 Hz) while it is in reach
const BID_REACH := 1.6         # m: the intended receiver stretching (a step and a reach) for a disc flying past
const BID_CHANCE := 0.2        # per tick while it is in that reach, at a catchable height (about 95% for a disc
                               # passing 1.3 m away at 15 m/s)
const REACT := 0.35            # s: a defender's reaction to a cut or a throw
const HAND_BLOCK := 0.25       # a break throw past a close mark: the marker's chance of a hand on it
const DROP := 0.03             # a catchable disc dropped (about one catch in thirty), Self-led; nerves add to it
const DROP_NERVES := 3.0       # a fully stirred exile makes a drop this many times likelier again
## The pressure of the moment (ULTIMATE-6), before each player's own Self and sensitivity: the stakes x (a base,
## plus the larger of the opening points' and the late score's). PO: the 2025 final's bad throws and drops came
## "at the beginning (with that start-of-big-championship-everything-on-the-line feeling) and at the end -
## universe point".
const PRESSURE_BASE := 0.3
const OPENING := 0.5           # the first point of a big game; fades over OPENING_POINTS
const OPENING_POINTS := 4.0
const UNIVERSE := 0.75         # both a point from winning
const GAME_POINT := 0.45
const CLOSE_LATE := 0.3        # within a point of each other in the last few points
const STALL_PRESSURE := 0.25   # the holder's own, by the end of the count
const HUCK_URGE := 8.0         # a blended firefighter's pull towards the long throw (the AI's score, per unit blend)
const CATCH_TOP := 2.7         # m: the highest catch, jumping
const MARK_DIST := 1.6         # m: the marker stands this far from the thrower (disc space)
const COUNT_RANGE := 3.0       # m: the marker counts only within this distance
const DT := 1.0 / 120.0
const WINDUP := {"backhand": 0.4, "forehand": 0.3, "hammer": 0.45, "pull": 0.6, "high_backhand": 0.45,
		"high_forehand": 0.35, "cloud": 0.45, "blade": 0.4, "scoober": 0.4, "push": 0.25,
		"lefty_forehand": 0.3}   # s from decision to release
## The lefty forehand (PO 10-31: "right handed players also use lefty forehand, especially handlers"): a right-hander's
## off-hand flick, a quick break round the mark on the backhand side, released wide of the marker's reach. Short
## (an off-hand has less power), less accurate, but harder for the mark to get a hand to than a backhand break.
const LEFTY_RANGE := 18.0      # m: the AI's longest lefty forehand
const LEFTY_HAND := 0.5        # its share of the marker's chance of a hand on a break
const LEFTY_ERROR := 1.4       # its aiming error over a right-handed throw's
## A long throw's lane (ULTIMATE-1 sprint 4): a huck stays low, at a height a defender can reach, for its first
## LANE_TO m (traced: 40 of 48 in-flight blocks came in the first 60% of hucks, mostly 8-15 m out, from defenders
## in the stack). The thrower looks along that stretch for a defender who could get there in time.
const LOOK_AGAIN := 0.15      # s: a thrower who held a throw back looks again after this
const LANE_MIN := 20.0         # m: throws this long are checked
const LANE_FROM := 3.0
const LANE_TO := 16.0
const LANE_SPEED := 18.0       # m/s: the disc's pace over that stretch
const HANDLERS := 3            # the first three of each team (by index) are handlers: they throw the lefty forehand
const GUST := 0.35             # gusts: up to this share of the steady wind, either way
const WIND_RISK := 0.25        # the AI's score cost per (m/s of wind x s in the air): floaty throws in wind are risky
const HIGH_RELEASE := 0.4      # a high release over the mark: this share of the marker's chance of a hand on a break
const CLOUD_RANGE := 15.0      # m: against a zone, a short throw whose line runs through the cup goes over it
const ZONE_ROLES := ["deep", "wing_l", "wing_r", "middle", "cup", "cup", "cup"]
const CLAMP_AFTER := 2.0       # s into a hold: the zone's cup closes in on the thrower
const CUP_RANGE := 7.0         # m from the thrower: a zone defender this close can get a hand or foot to a throw
const HOLE_SEARCH := 6.0       # m: against a zone, a popper or deep looks this far round their spot for a gap
const HOLE_EVERY := 0.7        # s between looks
const CUP_REACH := 1.1         # m: how far from a cup defender a throw's line can pass and still be blocked

enum Phase { LINE_UP, PULL, PICKUP, HOLD, FLIGHT, GOAL, OVER }

var rng := RandomNumberGenerator.new()
var teams: Array = [[], []]    # Array of PlayerState per team
var dir: Array[int] = [1, -1]  # the end each team attacks: +1 = the end zone at +x
var score: Array[int] = [0, 0]
var names: Array[String] = ["White", "Maroon"]
var offence := 0               # the team with the disc (during a pull: the receiving team)
var phase := Phase.LINE_UP
var phase_time := 0.0
var clock := 0.0
var human_team := 0            # -1: both teams are AI (autoplay)
var human: PlayerState         # the player the human steers on defence

var disc := DiscFlight.State.new()
var holder: PlayerState
var thrower: PlayerState       # the last thrower (cannot catch their own throw)
var receiver: PlayerState      # the intended receiver of the throw in the air
var release: ThrowSolver.Release
var stakes := 0.95             # how much the game means: a championship final (ULT_STAKES overrides)
var look_again := 0.0          # s until the thrower looks again (after a throw held back for a defender in its path)
var last_block := {}
var last_miss := {}             # the last throw that came down uncaught, for tracing (tests/probe_blocks.gd)
var recv_closest := 1e9         # the receiver's closest approach to the disc in flight, at a catchable height (m)
var recv_closest_at := []      # [disc height, flight time, receiver's speed, disc's speed] there
var aim_spot := Vector3.ZERO
var last_aim := {}    # where the throw was aimed (crossing catch height)            # the last in-flight block, for tracing (_defended)
var is_pull := false
var last_in := Vector3.ZERO    # the disc's last in-bounds spot over the ground (out-of-bounds restarts)
var stall := 0.0
var stall_called := 0
var hold_time := 0.0
var wind := Vector3.ZERO           # the wind now (the steady wind with its gusts), m/s
var wind_base := Vector3.ZERO      # the steady wind (ULT_WIND="speed,direction degrees"; 0 = towards +x): the
                                   # throwers allow for it; the gusts (GUST of it, changing over seconds) they cannot

var tune := {"margin": 0.5, "react": REACT, "def_chance": DEF_CHANCE, "def_reach": DEF_REACH,
		"hand_block": HAND_BLOCK, "break_penalty": 2.0, "late": -0.15, "swing": 4.0, "lean": 0.0, "goal_side": 2.5,
		"zone_swing": 2.0, "swing_margin": 0.15, "cup_block": 0.45,
		"zone_area": 7.0, "zone_shade": 0.4, "zone_hand": 0.5, "lane_penalty": 3.0}   # the AI's knobs; ULT_TUNE (JSON) overrides them
## Each team's defence: "person" (person to person) or "zone" (a cup of three round the thrower, a middle, two
## wings and a deep; common in the women's game: the PO's semifinal recording is a zone throughout). Maroon plays
## zone by default; ULT_DEFENCE="person,zone" (White, Maroon) overrides.
var defence: Array[String] = ["person", "zone"]
var defence_call: Array[String] = ["", ""]       # a defence called for the next point (call_defence)
var pending: ThrowSolver.Release                # a throw being wound up (released when windup_left runs out)
var pending_to: PlayerState
var windup_left := 0.0
var windup_kind := ""          # the kind of the last throw wound up (pull, backhand, forehand, hammer)
var windup_by: PlayerState     # who wound it up
var windups := 0               # throws (and pulls) wound up so far: the view starts the thrower's clip on a new one
var events: Array = []         # [{t, text}], newest last
var stats := {"throws": 0, "catches": 0, "turnovers": 0, "goals": 0, "pulls": 0, "stalls": 0, "blocks": 0}


func _init(seed_value: int = 1, human_side: int = 0) -> void:
	rng.seed = seed_value
	human_team = human_side
	var env := OS.get_environment("ULT_TUNE")
	if env != "":
		var extra = JSON.parse_string(env)
		if extra is Dictionary:
			for k in extra:
				tune[k] = float(extra[k])
	var env_w := OS.get_environment("ULT_WIND")
	if env_w != "":
		var wp := env_w.split(",")
		set_wind(float(wp[0]), float(wp[1]) if wp.size() > 1 else 0.0)
	var env_d := OS.get_environment("ULT_DEFENCE")
	if env_d != "":
		var parts := env_d.split(",")
		for t in mini(2, parts.size()):
			defence[t] = parts[t].strip_edges()
	var numbers := [[4, 7, 10, 12, 21, 23, 88], [2, 5, 9, 14, 17, 31, 44]]
	for t in 2:
		for i in PLAYERS:
			var p := PlayerState.new(t, i, numbers[t][i])
			p.speed = PlayerState.SPRINT * rng.randf_range(0.93, 1.0)
			p.inner = Inner.new(rng)
			teams[t].append(p)
	if OS.get_environment("ULT_STAKES") != "":
		stakes = float(OS.get_environment("ULT_STAKES"))
	start_point(1)                              # Maroon pulls first (the toss)


## The pressure of the moment for everyone on the field (ULTIMATE-6): the stakes x (a base, plus the larger of the
## opening points' and the late score's).
func moment_pressure() -> float:
	var played := float(score[0] + score[1])
	var opening := OPENING * maxf(0.0, 1.0 - played / OPENING_POINTS)
	var hi := maxi(score[0], score[1])
	var late := 0.0
	if score[0] == GAME_TO - 1 and score[1] == GAME_TO - 1:
		late = UNIVERSE
	elif hi == GAME_TO - 1:
		late = GAME_POINT
	elif hi >= GAME_TO - 4 and absi(score[0] - score[1]) <= 1:
		late = CLOSE_LATE
	return clampf(stakes * (PRESSURE_BASE + maxf(opening, late)), 0.0, 1.0)


## The stage of the game, as the players feel it: "universe point", "game point", "opening" (the first points of
## a big game) or "".
func stage() -> String:
	if score[0] == GAME_TO - 1 and score[1] == GAME_TO - 1:
		return "universe point"
	if maxi(score[0], score[1]) == GAME_TO - 1:
		return "game point"
	if score[0] + score[1] < OPENING_POINTS and stakes > 0.7:
		return "opening"
	return ""


## A steady wind of `speed` m/s blowing towards `deg` degrees (0: towards +x, 90: towards +z).
func set_wind(speed: float, deg: float) -> void:
	wind_base = Vector3(cos(deg_to_rad(deg)), 0, sin(deg_to_rad(deg))) * speed
	wind = wind_base
	ThrowSolver.wind = wind_base


func say(text: String) -> void:
	events.append({"t": clock, "text": text})
	if events.size() > 60:
		events.pop_front()


## A team calls its defence ("person" or "zone"), as teams do on the line: it applies from the next pull.
func call_defence(t: int, kind: String) -> void:
	defence_call[t] = kind
	say("%s will play %s defence from the next pull" % [names[t], "zone" if kind == "zone" else "person-to-person"])


func pulling_team() -> int:
	return 1 - offence


# ---------------------------------------------------------------- the point

## Both lines on their goal lines: the pulling team on the line of the end zone it defends.
func start_point(puller: int) -> void:
	offence = 1 - puller
	for t in 2:
		for q: PlayerState in teams[t]:
			q.inner.huddle()                          # the huddle between points
	for t in 2:
		if defence_call[t] != "":
			defence[t] = defence_call[t]
			defence_call[t] = ""
	holder = null
	receiver = null
	thrower = null
	is_pull = false
	windup_by = null
	for t in 2:
		var x := -Field.GOAL_LINE * dir[t]          # each team lines up on the goal line it defends
		for i in PLAYERS:
			var p: PlayerState = teams[t][i]
			p.pos = Vector3(x, 0.0, -15.0 + 5.0 * i)
			p.vel = Vector3.ZERO
			p.goal = p.pos
			p.role = "line"
			p.steer = Vector3.ZERO
	# Person-to-person: defender i takes attacker i, both ways. A zone's roles: a deep, two wings, a middle and the
	# cup of three (fixed for the point, as in a real zone).
	for t in 2:
		for i in PLAYERS:
			teams[t][i].mark = teams[1 - t][i]
			teams[t][i].zone_role = ZONE_ROLES[i]
	_pick_human()
	disc = DiscFlight.State.new(teams[puller][3].pos + Vector3(0, 1, 0))
	set_phase(Phase.LINE_UP)
	say("%s pull to %s.  %s %d, %s %d" % [names[puller], names[offence], names[0], score[0], names[1], score[1]])


func set_phase(p: Phase) -> void:
	phase = p
	phase_time = 0.0
	if p != Phase.HOLD:
		pending = null                             # a turnover or a goal cancels a throw being wound up
		pending_to = null
		windup_left = 0.0


func _pick_human() -> void:
	if human_team < 0:
		human = null
		return
	if human != null:
		human.steer = Vector3.ZERO
	# On defence the human steers the defender nearest the disc; on offence nobody (the human throws).
	human = null
	if offence != human_team:
		var best := 1e9
		for p: PlayerState in teams[human_team]:
			var d := p.pos.distance_to(Vector3(disc.pos.x, 0, disc.pos.z))
			if d < best:
				best = d
				human = p


func switch_human() -> void:
	_pick_human()


func step(dt: float = DT) -> void:
	if phase == Phase.OVER:
		return
	clock += dt
	if wind_base != Vector3.ZERO:
		# Gusts: the strength wanders over a few seconds, and the direction a little.
		var g := 1.0 + GUST * (0.6 * sin(clock * 0.53) + 0.4 * sin(clock * 1.71 + 1.3))
		wind = wind_base.rotated(Vector3.UP, 0.15 * sin(clock * 0.31)) * g
	ThrowSolver.wind = wind_base
	var mp := moment_pressure()
	for t in 2:
		for q: PlayerState in teams[t]:
			var own := STALL_PRESSURE * stall / 10.0 if q == holder else 0.0
			q.inner.update(dt, clampf(mp + own, 0.0, 1.0))
	phase_time += dt
	match phase:
		Phase.LINE_UP:
			if windup_by == null and phase_time > 1.5 - float(WINDUP.pull):
				windup_by = teams[pulling_team()][3]         # the puller winds up
				windup_kind = "pull"
				windups += 1
			if phase_time > 1.5:
				_throw_pull()
		Phase.FLIGHT, Phase.PULL:
			_fly(dt)
		Phase.PICKUP:
			_pickup(dt)
		Phase.HOLD:
			_hold(dt)
		Phase.GOAL:
			if phase_time > 2.5:
				if score[0] >= GAME_TO or score[1] >= GAME_TO:
					set_phase(Phase.OVER)
					var w := 0 if score[0] > score[1] else 1
					say("%s win %d-%d" % [names[w], score[w], score[1 - w]])
					return
				# The scoring team stays in that end zone and pulls: both teams change ends.
				dir[0] = -dir[0]
				dir[1] = -dir[1]
				start_point(offence)                    # the team that scored pulls
				return
	_move_players(dt)


# ---------------------------------------------------------------- throws

func _throw_pull() -> void:
	var puller: PlayerState = teams[pulling_team()][3]
	var d: int = dir[pulling_team()]
	# A women's pull: 40-58 m on the old disc; on the rigid disc 35-45 m (its calibrated pulls, 6 s or more in the
	# air), from the puller's goal line to past midfield.
	var near := Field.GOAL_LINE - (29.0 if DiscFlight.rigid else 24.0)
	var far := Field.GOAL_LINE - (19.0 if DiscFlight.rigid else 6.0)
	var target := Vector3(d * rng.randf_range(near, far), 0.0, rng.randf_range(-9.0, 9.0))
	release = ThrowSolver.solve(puller.pos, target, "pull", false, false)
	release.path = DiscFlight.simulate(release.state, ThrowSolver.SOLVE_DT, 0.0, 12.0, wind)
	release.arrival = release.path[-1][1]
	_release(puller, release, null)
	is_pull = true
	stats.pulls += 1
	set_phase(Phase.PULL)
	for p: PlayerState in teams[pulling_team()]:
		p.role = "cover"                          # run down on the pull
	for p: PlayerState in teams[offence]:
		p.role = "wait"
	_receiver_for_pull()


func _receiver_for_pull() -> void:
	var land := Vector3(release.arrival.x, 0, release.arrival.z)
	var best := 1e9
	for p: PlayerState in teams[offence]:
		var dd := p.pos.distance_to(land)
		if dd < best:
			best = dd
			receiver = p
	receiver.role = "receive"
	receiver.goal = Field.restart_point(land)


func _release(p: PlayerState, r: ThrowSolver.Release, to: PlayerState) -> void:
	disc = r.state.copy()
	disc.time = 0.0
	thrower = p
	receiver = to
	holder = null
	last_in = Vector3(disc.pos.x, 0, disc.pos.z)
	recv_closest = 1e9
	recv_closest_at = [0.0, 0.0, 0.0, 0.0]
	aim_spot = Vector3(r.arrival.x, 0, r.arrival.z)
	stall = 0.0
	stall_called = 0


## Whether a long throw's low stretch (LANE_FROM to LANE_TO m along the line) is clear: no defender (the mark
## aside) could reach a point of it, after reacting, by the time the disc is there (`w`: the wind-up).
func lane_open(from: Vector3, to: Vector3, w: float) -> bool:
	var v := Vector3(to.x - from.x, 0, to.z - from.z)
	var n := v.length()
	if n < 0.1:
		return true
	v /= n
	for q: PlayerState in teams[1 - offence]:
		if q.role == "mark":
			continue
		var s := LANE_FROM
		while s <= minf(LANE_TO, n - 5.0):
			var t := w + s / LANE_SPEED
			var reach := q.speed * maxf(t - float(tune.react), 0.0) + float(tune.def_reach)
			if q.pos.distance_to(from + v * s) <= reach:
				return false
			s += 1.0
	return true


## Whether a throw's flight is clear of defenders (the mark aside) while it is low enough to reach: from LANE_FROM m
## out until 3 m short of its target, no defender could get within reach of the disc, after reacting, in time.
func path_open(from: Vector3, r: ThrowSolver.Release, w: float) -> bool:
	var target := Vector3(r.arrival.x, 0, r.arrival.z).distance_to(Vector3(from.x, 0, from.z))
	for e in r.path:
		var q: Vector3 = e[1]
		var out := Vector3(q.x - from.x, 0, q.z - from.z).length()
		if out < LANE_FROM or q.y > CATCH_TOP:
			continue
		if out > target - 3.0:
			break
		var t: float = w + e[0]
		for d: PlayerState in teams[1 - offence]:
			if d.role == "mark":
				continue
			var reach := d.speed * maxf(t - float(tune.react), 0.0) + float(tune.def_reach)
			if Vector3(d.pos.x - q.x, 0, d.pos.z - q.z).length() <= reach:
				return false
	return true


## The human's throw: to a spot on the field. kind: any of ThrowSolver.KINDS.
func user_throw(target: Vector3, kind: String, inside_out: bool = false, huck: bool = false) -> bool:
	if phase != Phase.HOLD or offence != human_team or holder == null or windup_left > 0.0:
		return false
	var r := ThrowSolver.solve(holder.pos, target, kind, huck, inside_out) if huck \
			else ThrowSolver.solve_auto(holder.pos, target, kind, inside_out)
	_start_throw(r, _nearest(offence, target, holder))
	return true


## The side the marker takes away: the mark stands on it (the force sends throws to the other, open side).
func mark_side() -> Vector3:
	return Vector3(dir[offence] * 0.6, 0, -1.4).normalized()


## A throw towards the marked side, past a close mark: a break.
func is_break(from: Vector3, to: Vector3) -> bool:
	var m := _marker()
	if m == null or m.pos.distance_to(from) > COUNT_RANGE:
		return false
	var v := Vector3(to.x - from.x, 0, to.z - from.z)
	var side := Vector3(0, 0, signf(mark_side().z))      # across the field, towards the mark
	return v.length() > 0.1 and v.normalized().dot(side) > 0.45


func _throw(r: ThrowSolver.Release, to: PlayerState) -> void:
	# Execution: a little error in every throw, more under a close mark, most for a break past it.
	var pressure := 1.0
	var marker := _marker()
	var breaking := is_break(holder.pos, r.arrival)
	if marker != null and marker.pos.distance_to(holder.pos) < COUNT_RANGE:
		pressure = 2.2 if breaking else 1.6
	if r.kind == "lefty_forehand":
		pressure *= LEFTY_ERROR                              # the off hand
	pressure *= holder.inner.shake()                         # nerves (ULTIMATE-6)
	var yaw_err := rng.randfn(0.0, deg_to_rad(1.0) * pressure)
	var speed_err := 1.0 + rng.randfn(0.0, 0.015 * pressure)
	var aimed := r.arrival.distance_to(holder.pos)          # the throw's length to its target (for the stats)
	var aimed_at := Vector3(r.arrival.x, 0, r.arrival.z)
	var s := r.state
	s.turn(yaw_err)
	s.vel *= speed_err
	r.path = DiscFlight.simulate(s, ThrowSolver.SOLVE_DT, 0.0, 12.0, wind)   # all the way down, in the wind now
	r.arrival = r.path[-1][1]
	var who := holder
	release = r
	_release(who, r, to)
	aim_spot = aimed_at
	if to != null:
		last_aim = {"recv_d": to.pos.distance_to(aimed_at), "recv_v": to.vel.length(), "flight": r.flight_time}
	stats.throws += 1
	stats["throws%d" % offence] = stats.get("throws%d" % offence, 0) + 1
	stats["k%d_%s" % [offence, r.kind]] = stats.get("k%d_%s" % [offence, r.kind], 0) + 1
	var band := "len%d_%s" % [offence, "short" if aimed < 15.0 else ("medium" if aimed < 30.0 else "long")]
	stats[band] = stats.get(band, 0) + 1
	stats["hold%d" % offence] = stats.get("hold%d" % offence, 0.0) + hold_time
	if defence[1 - offence] == "zone":
		# Against a zone the danger is throwing through the cup: a throw that passes a cup defender within reach,
		# low enough, can be blocked; a swing round the cup is safe from it.
		var cup := cup_blocker(who.pos, r.path)
		if cup != null and rng.randf() < float(tune.cup_block):
			stats.blocks += 1
			say("%s #%d blocks it in the cup" % [names[1 - offence], cup.number])
			_turnover(Vector3(cup.pos.x, 0, cup.pos.z), "cup block")
			return
	# A break past the mark: a zone's marker stands among a cup and is beaten round the edge more often than a
	# tight person-to-person mark (tune.zone_hand of the chance).
	var hand := float(tune.hand_block) * (float(tune.zone_hand) if defence[1 - offence] == "zone" else 1.0)
	if r.kind.begins_with("high_") or r.kind == "cloud" or r.kind == "scoober":
		hand *= HIGH_RELEASE                                 # over the mark's hands
	elif r.kind == "lefty_forehand":
		hand *= LEFTY_HAND                                   # round the mark, wide of its reach
	if breaking and rng.randf() < hand:
		stats.blocks += 1
		say("%s #%d gets a hand to the break throw" % [names[1 - offence], marker.number])
		_turnover(Vector3(who.pos.x, 0, who.pos.z) + mark_side(), "hand block")
		return
	set_phase(Phase.FLIGHT)
	if to != null:
		to.role = "receive"
		to.goal = _catch_spot(to, r)
	say("%s #%d %s to #%d" % [names[offence], who.number, r.kind if r.speed < ThrowSolver.HUCK_OVER else r.kind + " huck",
			to.number if to else 0])


## A zone defender near the thrower (the cup, not the marker: a break past the mark is the hand block's) whom a
## throw passes within reach of, low enough to get a hand or a foot to it
## (path: [[time, position], ...] from the release); null if the throw goes round the cup.
func cup_blocker(from: Vector3, path: Array) -> PlayerState:
	for q: PlayerState in teams[1 - offence]:
		if q.role == "mark" or q.pos.distance_to(from) > CUP_RANGE:
			continue
		for e in path:
			var at: Vector3 = e[1]
			var flat := Vector3(at.x, 0, at.z)
			if flat.distance_to(Vector3(from.x, 0, from.z)) > CUP_RANGE + CUP_REACH:
				break
			if at.y < 2.4 and flat.distance_to(q.pos) < CUP_REACH:
				return q
	return null


## The same test on a straight line from the thrower to a spot (the AI's quick look before choosing a throw).
func through_cup(from: Vector3, spot: Vector3) -> bool:
	var a := Vector3(from.x, 0, from.z)
	var v := Vector3(spot.x, 0, spot.z) - a
	var n := v.length()
	if n < 0.1:
		return false
	for q: PlayerState in teams[1 - offence]:
		if q.role == "mark" or q.pos.distance_to(a) > CUP_RANGE:
			continue
		var along := clampf((q.pos - a).dot(v / n), 0.0, minf(n, CUP_RANGE))
		if (a + v / n * along).distance_to(q.pos) < CUP_REACH + 0.3:
			return true
	return false


## Where a runner should go to meet the disc in the air: the first point still ahead on its flight,
## low enough to catch, that they can reach before it does (0.3 s to get going from a standstill); else
## where it comes down. Re-aimed every tick, so a runner attacks the disc rather than waiting.
func _catch_spot(p: PlayerState, r: ThrowSolver.Release) -> Vector3:
	var now := disc.time if phase in [Phase.FLIGHT, Phase.PULL] else 0.0
	var start_lag := 0.3 * (1.0 - clampf(p.vel.length() / p.speed, 0.0, 1.0))
	for e in r.path:
		var t: float = e[0] - now
		var q: Vector3 = e[1]
		if t < 0.05 or q.y > CATCH_TOP - 0.2:
			continue
		var flat := Vector3(q.x, 0, q.z)
		if p.pos.distance_to(flat) - REACH * 0.6 <= p.speed * maxf(t - start_lag, 0.0):
			return flat
	return Vector3(r.arrival.x, 0, r.arrival.z)


# ---------------------------------------------------------------- the disc in the air

func _fly(dt: float) -> void:
	var prev := disc.pos
	DiscFlight.step(disc, dt, wind)
	if Field.in_bounds(disc.pos):
		last_in = Vector3(disc.pos.x, 0, disc.pos.z)
	if receiver != null and disc.pos.y < CATCH_TOP and disc.time > 0.25:
		var rd := Vector2(receiver.pos.x - disc.pos.x, receiver.pos.z - disc.pos.z).length()
		if rd < recv_closest:
			recv_closest = rd
			recv_closest_at = [disc.pos.y, disc.time, receiver.vel.length(), disc.vel.length()]
	# Catches and blocks: the offence wins a simultaneous catch.
	if disc.time > 0.25 and disc.pos.y < CATCH_TOP and disc.pos.y > 0.05:
		var off_c := _catcher(offence)
		var def_c: PlayerState = null if is_pull else _catcher(1 - offence)
		if off_c == null and disc.vel.y < 0.0 and disc.pos.y < LAYOUT_TOP:
			off_c = _layout(offence, LAYOUT_CHANCE)
			if off_c != null:
				say("Layout! #%d" % off_c.number)
		if off_c == null and receiver != null and not is_pull and disc.pos.y < CATCH_TOP - 0.3 \
				and Vector2(receiver.pos.x - disc.pos.x, receiver.pos.z - disc.pos.z).length() < BID_REACH \
				and rng.randf() < BID_CHANCE:
			off_c = receiver                     # a stretch for a pass flying by
		if def_c == null and not is_pull and disc.vel.y < 0.0 and disc.pos.y < LAYOUT_TOP:
			def_c = _layout(1 - offence, LAYOUT_CHANCE * 0.5)
		if off_c != null:
			_caught(off_c)
			return
		if def_c != null:
			_defended(def_c)
			return
	if disc.pos.y <= 0.0:
		disc.pos.y = 0.0
		_grounded(prev)


## A dive for a disc out of reach: within LAYOUT_REACH, low, coming down; a chance per tick.
func _layout(t: int, chance: float) -> PlayerState:
	for p: PlayerState in teams[t]:
		if p == thrower and not is_pull:
			continue
		var d := Vector2(p.pos.x - disc.pos.x, p.pos.z - disc.pos.z).length()
		if d < LAYOUT_REACH and rng.randf() < chance:
			return p
	return null


## A player close enough to the disc to catch it (the offence) or get a hand to it (the defence). A
## catch at full stretch takes a few tries; a defender, reaching across the receiver, gets fewer.
func _catcher(t: int) -> PlayerState:
	var best: PlayerState = null
	var on_d := t != offence
	var best_d: float = tune.def_reach if on_d else REACH
	for p: PlayerState in teams[t]:
		if p == thrower and not is_pull:
			continue
		var d := Vector2(p.pos.x - disc.pos.x, p.pos.z - disc.pos.z).length()
		var sure := DEF_SURE if on_d else 0.6
		var chance: float = tune.def_chance if on_d else 0.35
		if d < best_d and (d < sure or rng.randf() < chance):
			best_d = d
			best = p
	return best


func _caught(p: PlayerState) -> void:
	if not is_pull and rng.randf() < DROP * (1.0 + DROP_NERVES * p.inner.nerves):
		_turnover(Field.restart_point(Vector3(disc.pos.x, 0, disc.pos.z)), "#%d drops it" % p.number, p)
		return
	stats.catches += 1
	if not is_pull:
		p.inner.touch()
		if thrower != null:
			thrower.inner.touch()
	if not is_pull:
		stats["air%d" % offence] = stats.get("air%d" % offence, 0.0) + disc.time      # a completed throw's time in the air
		stats["airn%d" % offence] = stats.get("airn%d" % offence, 0) + 1
	if not Field.in_bounds(p.pos):
		_turnover(Field.restart_point(p.pos), "caught out of bounds")
		return
	if is_pull:
		is_pull = false
		say("%s #%d catches the pull" % [names[offence], p.number])
		_take(p)
		return
	if Field.in_attacking_endzone(p.pos, dir[offence]):
		score[offence] += 1
		stats.goals += 1
		for q: PlayerState in teams[offence]:
			q.inner.touch()
			q.inner.touch()
		stats["goals%d" % offence] = stats.get("goals%d" % offence, 0) + 1
		_end_possession()
		say("GOAL %s #%d (from #%d).  %s %d, %s %d" % [names[offence], p.number, thrower.number,
				names[0], score[0], names[1], score[1]])
		holder = p
		disc.pos = p.pos + Vector3(0, 1, 0)
		set_phase(Phase.GOAL)
		return
	say("#%d catches" % p.number)
	_take(p)


func _defended(p: PlayerState) -> void:
	stats.blocks += 1
	# For tracing (tests/probe_blocks.gd): who got it, how far through the flight, where the receiver was.
	var dv := Vector3(disc.vel.x, 0, disc.vel.z).normalized()
	last_block = {"marks_receiver": receiver != null and p.mark == receiver, "role": p.role, "zone_role": p.zone_role,
			"frac": disc.time / maxf(release.path[-1][0], 0.01) if release != null and release.path.size() > 0 else 0.0,
			"flight": release.path[-1][0] if release != null and release.path.size() > 0 else 0.0,
			"recv_d": Vector2(receiver.pos.x - disc.pos.x, receiver.pos.z - disc.pos.z).length() if receiver != null else -1.0,
			"def_d": Vector2(p.pos.x - disc.pos.x, p.pos.z - disc.pos.z).length(),
			"from_behind": (Vector3(p.pos.x - disc.pos.x, 0, p.pos.z - disc.pos.z)).dot(dv) < 0.0,
			"height": disc.pos.y, "length": thrower.pos.distance_to(release.arrival) if thrower != null and release != null else 0.0,
			"kind": release.kind if release != null else "", "hold": hold_time, "stall": stall}
	var spot := Field.clamp_restart(Vector3(p.pos.x, 0, p.pos.z), dir[1 - offence])
	if rng.randf() < 0.4 and Field.in_bounds(p.pos):
		say("%s #%d intercepts" % [names[1 - offence], p.number])
		_count_turnover("interception")
		if thrower != null:
			thrower.inner.own_error()
		offence = 1 - offence
		_take(p)
		_pick_human()
	else:
		say("%s #%d blocks it" % [names[1 - offence], p.number])
		_turnover(spot, "block")


func _grounded(prev: Vector3) -> void:
	var spot := Vector3(disc.pos.x, 0, disc.pos.z)
	if is_pull:
		is_pull = false
		if not Field.in_bounds(spot):
			spot = Field.brick(dir[offence])
			say("Pull out of bounds: brick")
		disc.pos = spot
		disc.vel = Vector3.ZERO
		_pickup_by(offence, spot)
		return
	last_miss = {"out": not Field.in_bounds(spot), "recv_closest": recv_closest, "kind": release.kind if release else "",
			"aim_len": thrower.pos.distance_to(aim_spot) if thrower else 0.0, "aim_in": Field.in_bounds(aim_spot),
			"aim_edge": Field.HALF_W - absf(aim_spot.z), "past": (spot - aim_spot).length(), "time": disc.time,
			"wind": wind.length(), "at": recv_closest_at, "aim": last_aim.duplicate()}
	if not Field.in_bounds(spot):
		_turnover(Field.restart_point(last_in), "out of bounds")
	else:
		_turnover(spot, "dropped" if _near_any(offence, spot, 2.0) else "on the ground")


## Turnovers, counted by cause, overall and for the team losing the disc (tN_cause); each ends a possession.
func _count_turnover(cause: String) -> void:
	stats.turnovers += 1
	stats["t_team%d" % offence] = stats.get("t_team%d" % offence, 0) + 1
	stats["t_" + cause] = stats.get("t_" + cause, 0) + 1
	stats["t%d_%s" % [offence, cause]] = stats.get("t%d_%s" % [offence, cause], 0) + 1
	_end_possession()


func _end_possession() -> void:
	var k := "poss%d" % offence
	stats[k] = stats.get(k, 0) + 1


func _turnover(spot: Vector3, why: String, culprit: PlayerState = null) -> void:
	_count_turnover(why.get_slice(" ", 0) if not why.begins_with("#") else "drop")
	var c := culprit if culprit != null else thrower
	if c != null and c.team == offence:
		c.inner.own_error()                           # her own mistake stirs the exile
	offence = 1 - offence
	spot = Field.clamp_restart(spot, dir[offence])
	say("Turnover (%s): %s's disc" % [why, names[offence]])
	disc.pos = spot
	disc.vel = Vector3.ZERO
	_pickup_by(offence, spot)
	_pick_human()


# ---------------------------------------------------------------- possession

func _pickup_by(t: int, spot: Vector3) -> void:
	holder = null
	receiver = _nearest(t, spot, null)
	receiver.role = "fetch"
	receiver.goal = spot
	for q: PlayerState in teams[t]:
		if q != receiver:
			q.role = "stack"
			q.timer = rng.randf_range(1.0, 3.0)
	for q: PlayerState in teams[1 - t]:
		q.role = "zone" if defence[1 - t] == "zone" else "guard"
	set_phase(Phase.PICKUP)


func _pickup(_dt: float) -> void:
	if receiver.pos.distance_to(Vector3(disc.pos.x, 0, disc.pos.z)) < 0.5:
		_take(receiver)


func _take(p: PlayerState) -> void:
	holder = p
	receiver = null
	p.role = "hold"
	p.steer = Vector3.ZERO
	disc.vel = Vector3.ZERO
	stall = 0.0
	stall_called = 0
	hold_time = 0.0
	look_again = 0.0
	set_phase(Phase.HOLD)
	for q: PlayerState in teams[offence]:
		if q != p:
			q.role = "stack"
			q.timer = rng.randf_range(0.5, 2.5)
	if defence[1 - offence] == "zone":
		# The cup player nearest the thrower marks; the other two form the cup; the rest hold their zones.
		var nearest: PlayerState = null
		for q: PlayerState in teams[1 - offence]:
			q.role = "zone"
			if q.zone_role == "cup" and (nearest == null or q.pos.distance_to(p.pos) < nearest.pos.distance_to(p.pos)):
				nearest = q
		nearest.role = "mark"
		return
	for q: PlayerState in teams[1 - offence]:
		q.role = "mark" if q.mark == p else "guard"


func _marker() -> PlayerState:
	for q: PlayerState in teams[1 - offence]:
		if q.role == "mark" or (q.mark == holder and defence[1 - offence] == "person"):
			return q
	return null


func _hold(dt: float) -> void:
	hold_time += dt
	disc.pos = holder.pos + Vector3(0.3, 1.0, 0.0)
	var m := _marker()
	if m != null and m.pos.distance_to(holder.pos) < COUNT_RANGE and hold_time > 0.8:
		stall += dt
		var n := int(stall)
		if n > stall_called and n >= 1:
			stall_called = n
			if n >= STALL:
				stats.stalls += 1
				say("\"Ten\": stall")
				_turnover(holder.pos, "stall", holder)
				return
			say("Stalling %d" % n)
	if windup_left > 0.0:
		windup_left -= dt
		if windup_left <= 0.0:
			var r := pending
			var to := pending_to
			pending = null
			pending_to = null
			_throw(r, to)
		return
	if offence != human_team:
		_ai_throw()


## A throw is decided, then released WINDUP[kind] seconds later: the wind-up (the view plays it). The count
## goes on meanwhile: a throw started at nine can still be stalled.
func _start_throw(r: ThrowSolver.Release, to: PlayerState) -> void:
	pending = r
	pending_to = to
	windup_kind = r.kind
	windup_by = holder
	windup_left = float(WINDUP.get(r.kind, 0.35))
	windups += 1


## The AI thrower: for each team-mate, a spot where they will be (or the space ahead of them) and the
## race to it: when the disc gets there, when the receiver does, and when the nearest defender does
## (the marker aside). Throws to the best margin, once a receiver is clearly first; late in the count,
## takes the best there is.
func _ai_throw() -> void:
	# Her protectors (ULTIMATE-6): a blended firefighter cannot bear to wait (she throws sooner and reaches for the
	# long throw); a blended manager plays it safe (breaks feel riskier, ground matters less, she swings sooner).
	var fire := holder.inner.firefighter
	var mgr := holder.inner.manager
	var hurried := fire > 0.1
	if hold_time < (0.3 if hurried else 1.0):
		return
	if look_again > 0.0:
		look_again -= DT
		return
	var d: int = dir[offence]
	var zone := defence[1 - offence] == "zone"
	# The wind-up: everyone runs for this long before the disc flies (the backhand's and forehand's, averaged).
	var w := 0.5 * (float(WINDUP.backhand) + float(WINDUP.forehand))
	var best: PlayerState = null
	var best_score := -1e9
	var best_margin := -1e9
	var best_spot := Vector3.ZERO
	var best_kind := ""                    # "" a flat backhand or forehand; else cloud, high (release) or lefty
	var safe: PlayerState = null           # late in the count: the throw with the most time to spare, anywhere
	var safe_margin := -1e9
	var safe_spot := Vector3.ZERO
	for p: PlayerState in teams[offence]:
		if p == holder:
			continue
		for into_space in [false, true]:
			var spot := p.pos
			var t := 0.8 + w
			for _k in 2:
				# Where the runner will be: along their run towards their goal, at their current pace
				# (a cutter slows at the end of the cut), or into the space past it.
				var to_goal := Vector3(p.goal.x - p.pos.x, 0, p.goal.z - p.pos.z)
				var ahead := Vector3.ZERO
				if to_goal.length() > 0.1:
					ahead = to_goal.normalized() * minf(to_goal.length(), maxf(p.vel.length(), 2.0) * t)
				if into_space:
					ahead += Vector3(d * 4.0, 0, 0)
				spot = p.pos + ahead
				spot = Vector3(clampf(spot.x, -Field.HALF_L + 1.0, Field.HALF_L - 1.0), 0,
						clampf(spot.z, -Field.HALF_W + 1.5, Field.HALF_W - 1.5))
				t = w + 0.3 + spot.distance_to(holder.pos) / 16.0
			var dist := spot.distance_to(holder.pos)
			if dist < 5.0 or dist > ThrowSolver.MAX_REACH:
				continue
			var r_t := p.pos.distance_to(spot) / (p.speed * 0.85) + 0.45
			var d_t := 1e9
			for q: PlayerState in teams[1 - offence]:
				if q.role == "mark":
					continue
				d_t = minf(d_t, maxf(q.pos.distance_to(spot) - tune.def_reach, 0.0) / (q.speed * 0.85) + 0.25)
			var breaking := is_break(holder.pos, spot)
			var lane_shut := (dist >= LANE_MIN or not zone) and not lane_open(holder.pos, spot, w)
			var cup := zone and through_cup(holder.pos, spot)
			var cand_kind := ""
			if cup and not breaking and dist <= CLOUD_RANGE:
				# Over the cup: a cloud, slower (about 2 s for 10 m), so raced on its own time.
				cand_kind = "cloud"
				cup = false
				t = w + 0.2 + dist / 5.5
			elif breaking and holder.idx < HANDLERS and dist <= LEFTY_RANGE \
					and (spot - holder.pos).dot(Vector3(d, 0, 0).cross(Vector3.UP)) < 0.0:
				cand_kind = "lefty"                            # a handler's break on the backhand side: the off hand
			elif breaking:
				cand_kind = "high"                             # a break goes over the mark
			var margin := d_t - maxf(t, r_t)
			var blocked := breaking or cup or lane_shut
			if margin > safe_margin and not blocked:
				safe_margin = margin
				safe = p
				safe_spot = spot
			if r_t > t + float(tune.late) + (3.0 * fire if dist >= 30.0 else 0.0):
				continue                                      # they would not get there in time (a firefighter
				                                              # throws the huck anyway: a hope, not a read)
			var progress := (spot.x - holder.pos.x) * d
			var wind_cost := WIND_RISK * wind_base.length() * maxf(t - w, 0.0)     # floaty throws in wind
			var sc := clampf(margin, -2.0, 2.0) * 3.0 + 0.06 * (1.0 - 0.6 * mgr) * progress \
					- (1.0 if dist > 40.0 else 0.0) - wind_cost
			if dist >= 30.0:
				sc += HUCK_URGE * fire                          # the firefighter's huck
			if blocked:
				# Throw to the open side (round the cup) if you can; a high release over the mark halves the cost.
				sc -= float(tune.break_penalty) * (0.5 if cand_kind in ["high", "lefty"] else 1.0) * (1.0 + mgr)
			if lane_shut:
				sc -= float(tune.lane_penalty) * (1.0 - minf(1.0, 3.0 * fire))   # a defender in the low stretch
			if Field.in_attacking_endzone(spot, d):
				sc += 2.0
			if sc > best_score:
				best_score = sc
				best = p
				best_margin = margin
				best_spot = spot
				best_kind = cand_kind
	# Swing it (the dump, the safest look) when nothing better is on: from stall 4 against a person defence, sooner
	# against a zone, which is beaten by moving the disc side to side.
	var swing_at := (float(tune.zone_swing) if zone else float(tune.swing)) - 2.0 * mgr
	var swinging := false
	if stall >= swing_at and (best == null or best_margin < tune.margin) and safe != null \
			and safe_margin >= float(tune.swing_margin):
		best = safe
		best_spot = safe_spot
		best_margin = safe_margin
		best_kind = ""
		swinging = true
	if best == null:
		return
	if best_margin < tune.margin - 4.0 * fire and stall < 8.0 and not swinging:
		return
	var right := Vector3(d, 0, 0).cross(Vector3.UP)
	var side := (best_spot - holder.pos).dot(right)
	var flat := "forehand" if side > 0.0 else "backhand"
	var kind := flat
	if best_kind == "cloud":
		kind = "cloud"
	elif best_kind == "high":
		kind = "high_" + kind
	elif best_kind == "lefty":
		kind = "lefty_forehand"
	var r := ThrowSolver.solve_auto(holder.pos, best_spot, kind)
	if not r.reachable and kind != flat:
		kind = flat                                              # the special release does not get there: a flat one
		r = ThrowSolver.solve_auto(holder.pos, best_spot, kind)
	# Lead the receiver: with the throw's real flight time, where will they be? If that is off the spot, throw there.
	var t_real := float(WINDUP.get(kind, 0.35)) + r.flight_time
	var to_goal := Vector3(best.goal.x - best.pos.x, 0, best.goal.z - best.pos.z)
	if to_goal.length() > 0.1 and best.vel.length() > 1.0:
		var lead := best.pos + to_goal.normalized() * minf(to_goal.length(), best.vel.length() * t_real)
		lead = Vector3(clampf(lead.x, -Field.HALF_L + 1.0, Field.HALF_L - 1.0), 0,
				clampf(lead.z, -Field.HALF_W + 1.5, Field.HALF_W - 1.5))
		if lead.distance_to(best_spot) > 1.0 and lead.distance_to(holder.pos) > 5.0:
			var r2 := ThrowSolver.solve_auto(holder.pos, lead, kind)
			if r2.reachable:
				r = r2
	# The receiver must get to where the throw crosses catch height by the time it does (traced: short passes to a
	# fast cutter, thrown at 17-19 m/s, got there 0.3 s after release with the receiver still 3-5 m away, and flew
	# on out of bounds). If not, wait for a better look unless the count is late. Against a person defence only:
	# against a zone the receivers mostly stand in holes and out of bounds is rare.
	var meet := Vector3(r.arrival.x, 0, r.arrival.z)
	var r_meet := best.pos.distance_to(meet) / (best.speed * 0.85) + 0.45
	if not zone and not hurried and stall < 7.0 and r_meet > float(WINDUP.get(kind, 0.35)) + r.flight_time - float(tune.late):
		stats["late_waits"] = stats.get("late_waits", 0) + 1
		look_again = LOOK_AGAIN
		return
	# Against a person defence, look along the throw's real flight (it curves, and it is led): if a defender is in
	# its low stretch, wait for a better look unless the count is late.
	if not zone and not hurried and stall < 7.0 and not path_open(holder.pos, r, float(WINDUP.get(kind, 0.35))):
		stats["lane_waits"] = stats.get("lane_waits", 0) + 1
		look_again = LOOK_AGAIN
		return
	if fire > 0.1 and best_spot.distance_to(holder.pos) >= 30.0:
		say("#%d can't wait: the huck" % holder.number)
	elif mgr > 0.3 and swinging:
		say("#%d plays it safe" % holder.number)
	_start_throw(r, best)


# ---------------------------------------------------------------- movement

func _move_players(dt: float) -> void:
	for t in 2:
		for p: PlayerState in teams[t]:
			if p == holder:
				p.stop(dt)
				continue
			if p.steer.length_squared() < 0.01:
				_ai_goal(p, dt)
			p.move(dt)


func _ai_goal(p: PlayerState, dt: float) -> void:
	var on_o: bool = p.team == offence
	var d: int = dir[offence]
	match p.role:
		"line":
			p.goal = p.pos
		"wait":
			p.goal = p.pos + Vector3(d * 0.2, 0, 0)
		"cover":
			# Run down on the pull towards the person you will mark.
			p.goal = p.mark.pos + Vector3(d * 2.0, 0, 0)
		"receive":
			if phase in [Phase.FLIGHT, Phase.PULL] and release != null:
				p.goal = _catch_spot(p, release)
				p.sprint = true
		"fetch":
			pass
		"hold":
			p.goal = p.pos
		"mark":
			# Stand a disc space and a bit from the thrower, on the side that forces the forehand to one sideline.
			var hp := holder.pos if holder != null else Vector3(disc.pos.x, 0, disc.pos.z)
			p.goal = hp + Vector3(d * 0.6, 0, -1.4).normalized() * MARK_DIST
		"guard", "chase":
			_defend(p)
		"zone":
			_zone(p)
		_:
			if on_o:
				_offence_goal(p, dt)
			else:
				_defend(p)


## Person-to-person defence. A defender reacts to a cut late (REACT seconds: they follow where their
## attacker was going, not where they are going), and to a throw late too.
func _defend(p: PlayerState) -> void:
	var a: PlayerState = p.mark
	var d: int = dir[offence]
	if phase == Phase.FLIGHT and release != null and disc.time > tune.react:
		if a == receiver:
			p.goal = _catch_spot(p, release)           # go for the disc with the receiver
			p.sprint = true
			return
		var land := Vector3(release.arrival.x, 0, release.arrival.z)
		if p.pos.distance_to(land) < 6.0:
			p.goal = land
			return
	# Goal side of the attacker, a step towards the disc: deep threats are taken away first.
	var seen := a.pos - a.vel * float(tune.react)
	var to_disc := (Vector3(disc.pos.x, 0, disc.pos.z) - seen)
	var lean := to_disc.normalized() * float(tune.lean) if to_disc.length() > 0.5 else Vector3.ZERO
	p.goal = seen + Vector3(d * float(tune.goal_side), 0, 0) + lean


## Zone defence: each defender holds a spot set by where the disc is, not by an attacker. The cup (the mark and
## two beside and a little ahead of the thrower, taking away the middle), a middle 9 m downfield, two wings 12 m
## downfield shading to the disc's side, and a deep about 26 m downfield. After CLAMP_AFTER s of a hold the cup
## closes in ("clamping"). In the air, a defender who can get to where the disc comes down in time goes for it; the others reset
## round where it will land, after the reaction time.
func _zone(p: PlayerState) -> void:
	var d: int = dir[offence]
	var base := holder.pos if holder != null else Vector3(disc.pos.x, 0, disc.pos.z)
	if phase == Phase.FLIGHT and release != null:
		var land := Vector3(release.arrival.x, 0, release.arrival.z)
		var left: float = release.path[-1][0] - disc.time if release.path.size() > 0 else 0.0
		var reach_t := maxf(p.pos.distance_to(land) - tune.def_reach, 0.0) / p.speed
		if (p.pos.distance_to(land) < 7.0 or reach_t < left + 0.3) and disc.time > tune.react * 0.5:
			p.goal = _catch_spot(p, release)
			p.sprint = true
			return
		if disc.time < tune.react:
			return                                         # still reading the throw: keep going where you were
		base = land
	p.goal = zone_spot(p, base, d)


## Where a zone defender stands with the disc at `base`, the offence attacking towards `d`.
func zone_spot(p: PlayerState, base: Vector3, d: int) -> Vector3:
	var clamp_k := 0.75 if holder != null and hold_time > CLAMP_AFTER else 1.0
	var shade := clampf(base.z, -Field.HALF_W, Field.HALF_W)
	var spot := base
	match p.zone_role:
		"cup":
			# The two cup players who are not marking: either side of the thrower, a step downfield.
			var cups: Array = []
			for q: PlayerState in teams[p.team]:
				if q.zone_role == "cup" and q.role != "mark":
					cups.append(q)
			var side := -1.0 if cups.find(p) == 0 else 1.0
			spot = base + Vector3(d * 2.8 * clamp_k, 0, side * 3.2 * clamp_k)
		"middle":
			spot = base + Vector3(d * 9.0, 0, 0)
			spot.z = shade * 0.5
		"wing_l", "wing_r":
			var side := -1.0 if p.zone_role == "wing_l" else 1.0
			spot = base + Vector3(d * 12.0, 0, 0)
			spot.z = side * 11.0 + shade * 0.35
		"deep":
			spot = base + Vector3(d * 26.0, 0, 0)
			spot.z = shade * 0.3
	# Behind the cup, a zone is not empty space: each defender closes on the attacker in their area (the most
	# downfield one within tune.zone_area m), standing goal-side of them, part of the way (tune.zone_shade: 0 holds
	# the spot, 1 marks them).
	if p.zone_role != "cup":
		var threat: PlayerState = null
		for a: PlayerState in teams[1 - p.team]:
			if a == holder or a.pos.distance_to(spot) > float(tune.zone_area):
				continue
			if threat == null or a.pos.x * d > threat.pos.x * d:
				threat = a
		if threat != null:
			var guard := threat.pos + Vector3(d * 1.5, 0, 0) + (base - threat.pos).normalized() * 1.0
			spot = spot.lerp(guard, float(tune.zone_shade))
	# Inside the field, and no deeper than the back of the attacked end zone.
	var back := Field.HALF_L - 1.5
	spot.x = clampf(spot.x, -back, back)
	spot.z = clampf(spot.z, -Field.HALF_W + 1.0, Field.HALF_W - 1.0)
	return spot


func _offence_goal(p: PlayerState, dt: float) -> void:
	var d: int = dir[offence]
	var base := holder.pos if holder != null else Vector3(disc.pos.x, 0, disc.pos.z)
	if phase == Phase.PULL or phase == Phase.LINE_UP:
		return
	if phase == Phase.FLIGHT and release != null:
		# Get ready for the next throw: drift to the stack around the landing spot.
		base = Vector3(release.arrival.x, 0, release.arrival.z)
	p.timer -= dt
	if defence[1 - offence] == "zone" and p.role in ["stack", "cut", "clear"]:
		# Handlers hold the swing line; the others look for the holes every HOLE_EVERY s.
		var spot := _zone_offence_spot(p, base, d)
		if _is_zone_handler(p):
			p.goal = spot
		elif p.timer <= 0.0 or phase == Phase.FLIGHT:
			p.goal = _hole_near(spot, d)
			p.timer = HOLE_EVERY
		return
	match p.role:
		"stack":
			p.goal = _stack_spot(p, base, d)
			if p.timer <= 0.0 and holder != null and _cutters() < 2:
				p.role = "cut"
				p.timer = rng.randf_range(1.8, 2.6)
				var deep := rng.randf() < 0.3
				var side := 1.0 if rng.randf() < 0.65 else -1.0     # mostly to the open side (away from the mark)
				var ahead := rng.randf_range(28.0, 40.0) if deep else rng.randf_range(7.0, 15.0)
				var x := clampf(base.x + d * ahead, -Field.HALF_L + 2.0, Field.HALF_L - 2.0)
				p.goal = Vector3(x, 0, clampf(base.z + side * rng.randf_range(6.0, 12.0), -Field.HALF_W + 2.0, Field.HALF_W - 2.0))
		"cut":
			if p.timer <= 0.0:
				p.role = "clear"
				p.timer = 1.5
		"clear":
			p.goal = _stack_spot(p, base, d)
			if p.timer <= 0.0:
				p.role = "stack"
				p.timer = rng.randf_range(2.0, 4.0)
		"dump":
			p.goal = base + Vector3(-d * 4.0, 0, 5.0)


## Against a zone: spread the field and move the disc. Two handlers level with the thrower across the field
## (with the thrower, a line to swing along, losing no ground); two poppers in the seams between the cup and the
## wings, stepping up in turn; two deep in the seams between the wings and the deep.
func _zone_offence_spot(p: PlayerState, base: Vector3, d: int) -> Vector3:
	var others: Array = []
	for q: PlayerState in teams[offence]:
		if q != holder:
			others.append(q)
	var k := others.find(p)
	var spot := base
	var pop := fmod(clock + 1.3 * k, 4.0) < 2.0           # each popper steps up for two seconds in four
	match k:
		0, 1:
			# Handlers: 9 m either side of the thrower and a step back; near a sideline, both to the open side
			# (9 and 17 m away).
			var offs := [-10.0, 10.0]
			if base.z + 10.0 > Field.HALF_W - 2.0:
				offs = [-10.0, -18.0]
			elif base.z - 10.0 < -Field.HALF_W + 2.0:
				offs = [10.0, 18.0]
			spot = Vector3(base.x - d * 0.5, 0, base.z + float(offs[k]))
		2, 3:
			var side := -1.0 if k == 2 else 1.0
			spot = base + Vector3(d * (5.5 if pop else 7.5), 0, side * 6.5)
		_:
			var side := -1.0 if k == 4 else 1.0
			spot = Vector3(base.x + d * 19.0, 0, clampf(base.z * 0.3, -6.0, 6.0) + side * 7.0)
	var back := Field.HALF_L - 1.5
	spot.x = clampf(spot.x, -back, back)
	spot.z = clampf(spot.z, -Field.HALF_W + 1.5, Field.HALF_W - 1.5)
	return spot


## Against a zone, the first two team-mates (by number order, the holder aside) are the handlers.
func _is_zone_handler(p: PlayerState) -> bool:
	var k := 0
	for q: PlayerState in teams[offence]:
		if q == p:
			return k < 2
		if q != holder:
			k += 1
	return false


## The biggest gap in the defence near a spot: candidates up to HOLE_SEARCH m away, scored by the distance to the
## nearest defender, less a little for straying from the spot.
func _hole_near(spot: Vector3, d: int) -> Vector3:
	var best := spot
	var best_score := -1e9
	var steps := 4
	for i in range(-steps, steps + 1):
		for j in range(-steps, steps + 1):
			var c := spot + Vector3(i, 0, j) * (HOLE_SEARCH / steps)
			if absf(c.z) > Field.HALF_W - 1.5 or absf(c.x) > Field.HALF_L - 1.5:
				continue
			var near := 1e9
			for q: PlayerState in teams[1 - offence]:
				near = minf(near, q.pos.distance_to(c))
			var sc := minf(near, 8.0) - 0.2 * c.distance_to(spot) + 0.05 * (c.x - spot.x) * d
			if sc > best_score:
				best_score = sc
				best = c
	return best


func _stack_spot(p: PlayerState, base: Vector3, d: int) -> Vector3:
	# A vertical stack down the middle, starting 10 m ahead of the disc; the first player is the dump.
	var others: Array = []
	for q: PlayerState in teams[offence]:
		if q != holder:
			others.append(q)
	var k := others.find(p)
	if k == 0:
		return Vector3(clampf(base.x - d * 4.0, -Field.HALF_L + 1, Field.HALF_L - 1), 0,
				clampf(base.z + 5.0, -Field.HALF_W + 1.5, Field.HALF_W - 1.5))
	var room := (Field.HALF_L - 2.0) - base.x * d             # metres ahead of the disc, to the back line
	var start := clampf(room * 0.25, 3.0, 8.0)
	var gap := clampf((room - start) / float(maxi(others.size() - 1, 1)), 1.8, 3.5)
	var x := clampf(base.x + d * (start + gap * (k - 1)), -Field.HALF_L + 1.0, Field.HALF_L - 1.0)
	return Vector3(x, 0, clampf(base.z * 0.3, -6.0, 6.0))


func _cutters() -> int:
	var n := 0
	for q: PlayerState in teams[offence]:
		if q.role == "cut":
			n += 1
	return n


func _nearest(t: int, spot: Vector3, skip: PlayerState) -> PlayerState:
	var best: PlayerState = null
	var bd := 1e9
	for p: PlayerState in teams[t]:
		if p == skip:
			continue
		var dd := p.pos.distance_to(Vector3(spot.x, 0, spot.z))
		if dd < bd:
			bd = dd
			best = p
	return best


func _near_any(t: int, spot: Vector3, r: float) -> bool:
	for p: PlayerState in teams[t]:
		if p.pos.distance_to(spot) < r:
			return true
	return false
