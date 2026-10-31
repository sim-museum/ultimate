# ultimate

A women's ultimate frisbee game: seven against seven, self-refereed, in 3D. Built with Godot 4.

An early playable version: motion-captured athletes in team kits on a regulation field, playing full points
from the pull to a goal, under a high broadcast camera or a camera behind the play.

## Running it

Install Godot 4.7 (the standard build, not .NET) from godotengine.org, then from this folder:

    godot --path .

To watch the AI play both teams:

    godot --path . -- --autoplay

## Controls

You play White.

- **On offence:** click a spot on the field to throw there.
  - `1` backhand, `2` forehand, `3` hammer, `4` blade, `5` scoober, `6` push pass, `7` cloud (a floater over a
    zone's cup). `H` releases backhands and forehands high, over the mark.
  - Hold `Shift` for inside-out, hold `Space` to huck.
  - The marker counts to ten.
- **On defence:** `WASD` or the arrow keys steer the highlighted player. `Tab` switches to the player
  nearest the disc. `Z` calls your team's defence, zone or person to person, from the next pull.
- `C` switches the camera: the whole field from high up; a tower behind the sideline (high and wide); a lower,
  tighter camera on the sideline that follows the disc; or behind the play at head height.
- `F1` toggles autoplay. `Esc` quits.
- `godot --path . -- --wind=6,90` plays in a 6 m/s wind blowing across the field (degrees: 0 along it). The wind
  gusts; throwers allow for its steady part.

## What's in it

- **Rules (after the WFDF Rules of Ultimate 2025-2028):**
  - the pull, with the brick for an out-of-bounds pull;
  - no running with the disc;
  - the marker's stall count to ten;
  - turnovers for a drop, a block, an interception, out of bounds or a stall;
  - a goal for a catch in the attacked end zone, then the teams change ends and the scoring team pulls;
  - first to 15.
- **The field:** 100 m by 37 m, 18 m end zones, brick marks 18 m from the goal lines.
- **Disc flight:** a spinning rigid disc, after S. A. Hummel's six-degree-of-freedom frisbee model (M.S. thesis,
  UC Davis, 2003): lift, drag, the pitching moment and its damping, roll damping and spin-down, with the lift,
  drag and pitch coefficients Potts and Crowther (2002) measured in a wind tunnel. The disc's attitude moves in
  flight, so a slowing backhand fades, a fast one turns, and a hyzer release draws an S. The hammer flies upside
  down.
- **Throws:** a throw solver finds the release (speed, direction, nose angle and bank, from a calibrated table of
  a good thrower's releases) that brings the disc past the chosen spot at a catchable height; pulls hang six
  seconds.
- **The AI:**
  - offence runs a vertical stack with cuts under and deep;
  - the thrower picks the receiver who wins the race to the disc;
  - defence is person to person, with a reaction lag, or a zone: a cup of three round the thrower, a middle,
    two wings and a deep, sliding with the disc and closing on attackers in their area (Maroon plays zone);
  - against a zone the offence swings the disc along a line of handlers and looks for the holes;
  - players chase the disc, and catch, block or lay out for it.

- **The players:** women athletes with skeletons, in jerseys and shorts tinted to the team (White and
  Maroon), some with dark undershirt sleeves, knee sleeves or headbands, with numbers on their backs. Two
  observers in orange keep level with the play on the sidelines. Substitutes watch from the far sideline,
  in front of the boards, tents and a full stand. The White team is mostly East Asian
  players, the Maroon team mixed. They run, jog, backpedal, shuffle sideways and idle from motion capture, with their planted feet held
  still by foot locking, blended by each player's speed
  and direction, face the way they run or the disc, and carry the disc in the throwing hand. Each throw winds
  up before the disc leaves the hand: two captured backhands, and a forehand and a hammer keyed by hand.

## Layout

- `scripts/sim/`: the game itself, with no rendering: field, disc flight, throw solver, players, match
  rules and AI.
- `scripts/view/`: the 3D view, input and HUD.
- `scenes/main.tscn`: the main scene.
- `assets/players/`: the athletes (GLB, four body variants) and `clips.json`, which describes their clips.
- `tools/athletes/`: how the athletes are built (Blender, MPFB, CMU motion capture).

## Credits

- **Bodies, skins, hair and clothes:** made with MakeHuman / MPFB; models exported from MakeHuman are CC0.
- **Motion:** the CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu). "The collection of the data in
  this database was supported by NSF Grant #0196217." Its terms: the data "may be copied, modified, or
  redistributed without permission."

The licence is still to be decided.
