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
    zone's cup), `8` lefty forehand (the off-hand flick, a quick break round the mark on the backhand side).
    `H` releases backhands and forehands high, over the mark.
  - Hold `Shift` for inside-out, hold `Space` to huck.
  - The marker counts to ten.
- **On defence:** `WASD` or the arrow keys steer the highlighted player. `Tab` switches to the player
  nearest the disc. `Z` calls your team's defence, zone or person to person, from the next pull.
- `C` switches the camera: the whole field from high up; a tower behind the sideline (high and wide); a lower,
  tighter camera on the sideline that follows the disc; or behind the play at head height.
- `I` shows or hides the player card: the disc holder's (or your player's) Self, nerves and whether a protector
  has taken over. The HUD names the moment (the opening, game point, universe point); `--score=14,14` starts at
  universe point; `--stakes=0.5` makes it pool play instead of a final.
- `L` switches the light: a clear midday or a low late-afternoon sun with long shadows (`--light=late` starts
  with it).
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
  - the thrower picks the receiver who wins the race to the disc, and holds a throw whose low early stretch a
    defender could cut off, until the count runs late (so hucks are rare: mostly a late-count hail mary);
  - defence is person to person, with a reaction lag, or a zone: a cup of three round the thrower, a middle,
    two wings and a deep, sliding with the disc and closing on attackers in their area (Maroon plays zone);
  - against a zone the offence swings the disc along a line of handlers and looks for the holes;
  - players chase the disc, and catch, block or lay out for it.
- **The players' inner worlds** (after the Internal Family Systems model): each player has her own Self-energy,
  nerves (an exile's fear of failing the team) and two protectors, a careful manager and a firefighter who cannot
  bear the tension. The game is a final: the pressure is highest in the opening points and at universe point,
  lowest mid-game. Nerves shake throws and loosen catches; a blended manager plays it safe; a blended firefighter
  hurries and throws the huck nobody tried all game. A mistake stirs her nerves; a completed pass, a goal and the
  huddle between points settle them, and a calm team-mate close by helps her settle. It shows: stirred nerves raise the shoulders and quicken the breath, and after
  her own mistake a player's head drops for a moment.

- **The players:** women athletes with skeletons, in jerseys and shorts tinted to the team (White and Maroon),
  some with dark undershirt sleeves, knee sleeves or headbands, with numbers on their backs. Two observers in
  orange keep level with the play on the sidelines. Substitutes watch from the far sideline, in front of the
  boards, tents and a full stand. The White team is mostly East Asian players, the Maroon team mixed. They run,
  jog, backpedal, shuffle sideways and idle from motion capture, mark low with their arms out, reach out with both hands to catch, lay out full length, with their planted feet held still by foot
  locking, blended by each player's speed and direction, face the way they run or the disc, and carry the disc in
  the throwing hand. Each throw winds up before the disc leaves the hand: two captured backhands, and a forehand
  and a hammer keyed by hand, and the lefty forehand (the forehand mirrored).

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
