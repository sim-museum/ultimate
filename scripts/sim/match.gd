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
const REACT := 0.35            # s: a defender's reaction to a cut or a throw
const HAND_BLOCK := 0.25       # a break throw past a close mark: the marker's chance of a hand on it
const DROP := 0.03             # a catchable disc dropped (about one catch in thirty)
const CATCH_TOP := 2.7         # m: the highest catch, jumping
const MARK_DIST := 1.6         # m: the marker stands this far from the thrower (disc space)
const COUNT_RANGE := 3.0       # m: the marker counts only within this distance
const DT := 1.0 / 120.0
const WINDUP := {"backhand": 0.4, "forehand": 0.3, "hammer": 0.45, "pull": 0.6}   # s from decision to release

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
var is_pull := false
var last_in := Vector3.ZERO    # the disc's last in-bounds spot over the ground (out-of-bounds restarts)
var stall := 0.0
var stall_called := 0
var hold_time := 0.0
var wind := Vector3.ZERO

var tune := {"margin": 0.5, "react": REACT, "def_chance": DEF_CHANCE, "def_reach": DEF_REACH,
		"hand_block": HAND_BLOCK, "break_penalty": 2.0, "late": -0.15, "swing": 4.0, "lean": 0.0, "goal_side": 2.5}   # the AI's knobs; ULT_TUNE (JSON) overrides them
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
	var numbers := [[4, 7, 10, 12, 21, 23, 88], [2, 5, 9, 14, 17, 31, 44]]
	for t in 2:
		for i in PLAYERS:
			var p := PlayerState.new(t, i, numbers[t][i])
			p.speed = PlayerState.SPRINT * rng.randf_range(0.93, 1.0)
			teams[t].append(p)
	start_point(1)                              # Maroon pulls first (the toss)


func say(text: String) -> void:
	events.append({"t": clock, "text": text})
	if events.size() > 60:
		events.pop_front()


func pulling_team() -> int:
	return 1 - offence


# ---------------------------------------------------------------- the point

## Both lines on their goal lines: the pulling team on the line of the end zone it defends.
func start_point(puller: int) -> void:
	offence = 1 - puller
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
	# Person-to-person: defender i takes attacker i, both ways.
	for t in 2:
		for i in PLAYERS:
			teams[t][i].mark = teams[1 - t][i]
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
	# A women's pull: 40-58 m, from the puller's goal line to between midfield and the receiving goal line.
	var target := Vector3(d * rng.randf_range(Field.GOAL_LINE - 24.0, Field.GOAL_LINE - 6.0), 0.0,
			rng.randf_range(-9.0, 9.0))
	release = ThrowSolver.solve(puller.pos, target, "pull", false, false)
	release.path = DiscFlight.simulate(release.state, ThrowSolver.SOLVE_DT, 0.0)
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
	stall = 0.0
	stall_called = 0


## The human's throw: to a spot on the field. kind: backhand, forehand or hammer.
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
	var yaw_err := rng.randfn(0.0, deg_to_rad(1.0) * pressure)
	var speed_err := 1.0 + rng.randfn(0.0, 0.015 * pressure)
	var s := r.state
	s.vel = s.vel.rotated(Vector3.UP, yaw_err) * speed_err
	s.normal = s.normal.rotated(Vector3.UP, yaw_err)
	r.path = DiscFlight.simulate(s, ThrowSolver.SOLVE_DT, 0.0)       # all the way down: runners chase it
	r.arrival = r.path[-1][1]
	var who := holder
	release = r
	_release(who, r, to)
	stats.throws += 1
	if breaking and rng.randf() < float(tune.hand_block):
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
	# Catches and blocks: the offence wins a simultaneous catch.
	if disc.time > 0.25 and disc.pos.y < CATCH_TOP and disc.pos.y > 0.05:
		var off_c := _catcher(offence)
		var def_c: PlayerState = null if is_pull else _catcher(1 - offence)
		if off_c == null and disc.vel.y < 0.0 and disc.pos.y < LAYOUT_TOP:
			off_c = _layout(offence, LAYOUT_CHANCE)
			if off_c != null:
				say("Layout! #%d" % off_c.number)
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
	if not is_pull and rng.randf() < DROP:
		_turnover(Field.restart_point(Vector3(disc.pos.x, 0, disc.pos.z)), "#%d drops it" % p.number)
		return
	stats.catches += 1
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
	var spot := Field.clamp_restart(Vector3(p.pos.x, 0, p.pos.z), dir[1 - offence])
	if rng.randf() < 0.4 and Field.in_bounds(p.pos):
		say("%s #%d intercepts" % [names[1 - offence], p.number])
		offence = 1 - offence
		stats.turnovers += 1
		stats["t_interception"] = stats.get("t_interception", 0) + 1
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
	if not Field.in_bounds(spot):
		_turnover(Field.restart_point(last_in), "out of bounds")
	else:
		_turnover(spot, "dropped" if _near_any(offence, spot, 2.0) else "on the ground")


func _turnover(spot: Vector3, why: String) -> void:
	stats.turnovers += 1
	stats["t_team%d" % offence] = stats.get("t_team%d" % offence, 0) + 1
	var cause := why.get_slice(" ", 0) if not why.begins_with("#") else "drop"
	stats["t_" + cause] = stats.get("t_" + cause, 0) + 1
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
		q.role = "guard"
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
	set_phase(Phase.HOLD)
	for q: PlayerState in teams[offence]:
		if q != p:
			q.role = "stack"
			q.timer = rng.randf_range(0.5, 2.5)
	for q: PlayerState in teams[1 - offence]:
		q.role = "mark" if q.mark == p else "guard"


func _marker() -> PlayerState:
	for q: PlayerState in teams[1 - offence]:
		if q.mark == holder:
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
				_turnover(holder.pos, "stall")
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
	if hold_time < 1.0:
		return
	var d: int = dir[offence]
	# The wind-up: everyone runs for this long before the disc flies (the backhand's and forehand's, averaged).
	var w := 0.5 * (float(WINDUP.backhand) + float(WINDUP.forehand))
	var best: PlayerState = null
	var best_score := -1e9
	var best_margin := -1e9
	var best_spot := Vector3.ZERO
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
			var margin := d_t - maxf(t, r_t)
			if margin > safe_margin and not is_break(holder.pos, spot):
				safe_margin = margin
				safe = p
				safe_spot = spot
			if r_t > t + float(tune.late):
				continue                                      # they would not get there in time
			var progress := (spot.x - holder.pos.x) * d
			var sc := clampf(margin, -2.0, 2.0) * 3.0 + 0.06 * progress - (1.0 if dist > 40.0 else 0.0)
			if is_break(holder.pos, spot):
				sc -= float(tune.break_penalty)               # throw to the open side if you can
			if Field.in_attacking_endzone(spot, d):
				sc += 2.0
			if sc > best_score:
				best_score = sc
				best = p
				best_margin = margin
				best_spot = spot
	if stall >= float(tune.swing) and (best == null or best_margin < tune.margin) and safe != null:
		best = safe                                            # swing it: the dump, the safest look
		best_spot = safe_spot
		best_margin = safe_margin
	if best == null:
		return
	if best_margin < tune.margin and stall < 8.0:
		return
	var right := Vector3(d, 0, 0).cross(Vector3.UP)
	var side := (best_spot - holder.pos).dot(right)
	var kind := "forehand" if side > 0.0 else "backhand"
	_start_throw(ThrowSolver.solve_auto(holder.pos, best_spot, kind), best)


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


func _offence_goal(p: PlayerState, dt: float) -> void:
	var d: int = dir[offence]
	var base := holder.pos if holder != null else Vector3(disc.pos.x, 0, disc.pos.z)
	if phase == Phase.PULL or phase == Phase.LINE_UP:
		return
	if phase == Phase.FLIGHT and release != null:
		# Get ready for the next throw: drift to the stack around the landing spot.
		base = Vector3(release.arrival.x, 0, release.arrival.z)
	p.timer -= dt
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
