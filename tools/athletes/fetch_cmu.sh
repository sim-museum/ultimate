#!/bin/bash
# Fetch the CMU Graphics Lab motion capture trials the athletes use (ASF skeleton + AMC motion per trial) into
# $CMU_DIR (default ~/ultimate_re/cmu). Terms (mocap.cs.cmu.edu): "may be copied, modified, or redistributed
# without permission."
set -e
D=${CMU_DIR:-~/ultimate_re/cmu}
mkdir -p "$D"
cd "$D"
for t in 09_01 16_35 35_17 76_11 79_92 102_24 102_25; do
    s=${t%%_*}
    [ -f "$s.asf" ] || curl -sSf -o "$s.asf" "http://mocap.cs.cmu.edu/subjects/$s/$s.asf"
    [ -f "$t.amc" ] || curl -sSf -o "$t.amc" "http://mocap.cs.cmu.edu/subjects/$s/$t.amc"
done
echo "CMU trials in $D"
