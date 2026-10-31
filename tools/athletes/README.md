# Building the athletes

The players in `assets/players/` are built with Blender 4.2+ (tested with 5.2.3) and the MPFB 2 add-on with the
MakeHuman system assets pack (CC0), from CMU motion capture:

    tools/athletes/fetch_cmu.sh
    blender -b --python tools/athletes/build_athletes.py -- assets/players a b c d

- `build_athletes.py`: the four body variants (MPFB, the `cmu_mb` skeleton), the kit (a T-shirt and jeans cut
  into a jersey and shorts, white so the game tints them), the clips retargeted from CMU, and `clips.json`.
- `cmu_amc.py`: reads CMU ASF/AMC and does the forward kinematics. Run on its own, it prints a trial's speed,
  heading and wrist speeds per quarter second (for choosing clips).
- `render_clips.py`: renders frames of clips from an exported GLB, for checking by eye.

Retargeting: each frame, every bone takes the rotation its CMU segment has made away from the CMU rest pose,
after a one-time turn of the MPFB rest direction onto the CMU one. Loops are cut where the pose best repeats; the
root's travel is removed (the game moves the player); each clip's speed on each body is measured from its planted
foot and stored in `clips.json`.
