class_name Inner
extends RefCounted
## A player's inner world (ULTIMATE-6), after the published Internal Family Systems model (R. C. Schwartz): parts and
## Self. PO: "The woman's game is more dependent on psychology ... women feel nerves more strongly"; in the 2025
## final "both sides made lots of bad throws and drops [when] the pressure was highest - at the beginning ... and at
## the end - universe point ... where both sides immediately tried a huck despite never chancing that earlier".
##
## Each player has:
##   - Self-energy (`self_energy`, 0-1): calm, clear, confident; her own steadiness, which pressure does not move;
##   - an exile carrying the fear of failing the team; how much it is stirred is `nerves` (0-1);
##   - two protectors that step in when the exile is stirred and Self is not there to hold it: a manager (control:
##     the safe throw, holding on) and a firefighter (end the unbearable tension now: the hurried throw, the huck).
##     `manager` and `firefighter` (0-1) are how blended with each she is now; `firefighter_lean` (0-1) is which of
##     the two tends to step in for her, and acute pressure (universe point) brings the firefighter.
##
## The match sets the pressure of the moment (stakes, the opening points, a close score late, universe point, the
## count, the crowd); nerves follow it (stirred fast, settling slowly), buffered by Self-energy; a mistake of her own
## stirs the exile, a completed touch or a goal settles it, and so does the huddle between points.

const RISE := 1.5              # per s: how fast nerves rise towards what the moment stirs
const SETTLE := 0.08           # per s: how fast they settle when the moment eases
const BUFFER := 0.7            # how much of the stirring a fully Self-led player holds (Self-energy 1)
const BLEND_AT := 0.35         # nerves past this, with Self not holding them, and a protector takes over
const ACUTE := 0.8             # pressure past this brings the firefighter whoever she is
const OWN_ERROR := 0.25        # nerves added by a mistake of her own (a drop, a throw away)
const TOUCH := 0.06            # nerves eased by a completed throw or catch
const HUDDLE := 0.5            # the share of nerves left after the huddle between points

var self_energy := 0.7
var sensitivity := 1.0         # how strongly pressure reaches her exile
var firefighter_lean := 0.3
var nerves := 0.0
var manager := 0.0
var firefighter := 0.0
var pressure := 0.0            # the last pressure the match set


func _init(rng: RandomNumberGenerator) -> void:
	self_energy = rng.randf_range(0.5, 0.85)
	sensitivity = rng.randf_range(0.8, 1.2)
	firefighter_lean = rng.randf_range(0.1, 0.6)


## Each tick: nerves move towards what the moment stirs (pressure x sensitivity, less what Self holds); a protector
## blends in as far as the nerves pass what Self can hold.
func update(dt: float, p: float) -> void:
	pressure = p
	var stirred := clampf(p * sensitivity * (1.0 - BUFFER * self_energy), 0.0, 1.0)
	nerves = move_toward(nerves, stirred, (RISE if stirred > nerves else SETTLE) * dt)
	var over := clampf((nerves - BLEND_AT) / (1.0 - BLEND_AT), 0.0, 1.0)
	var lean := 1.0 if p >= ACUTE else firefighter_lean
	firefighter = over * lean
	manager = over * (1.0 - lean)


func own_error() -> void:
	nerves = minf(1.0, nerves + OWN_ERROR)


func touch() -> void:
	nerves = maxf(0.0, nerves - TOUCH)


func huddle() -> void:
	nerves *= HUDDLE


## How shaky her hands are now: 1 Self-led, more as the exile is stirred.
func shake() -> float:
	return 1.0 + 1.5 * nerves
