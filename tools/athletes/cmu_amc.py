"""Read CMU Graphics Lab ASF/AMC motion capture and run forward kinematics (numpy only, so it works both in
Blender's Python and outside it).

CMU convention: Y up, the subject faces +Z, left is +X. Lengths are in ASF units: metres = units / 0.45 * 0.0254.
For each segment, local = C * M * C^-1 with C the segment's axis rotation and M the AMC rotation (both applied
X first, then Y, then Z); global = parent_global * local. A segment runs from its parent's end along
global * direction * length, where direction is given in the rest frame.
"""
import numpy as np

UNIT_M = 0.0254 / 0.45


def rot_xyz(ax, ay, az):
    """Rotation applying X, then Y, then Z (degrees): Rz @ Ry @ Rx."""
    x, y, z = np.radians([ax, ay, az])
    cx, sx, cy, sy, cz, sz = np.cos(x), np.sin(x), np.cos(y), np.sin(y), np.cos(z), np.sin(z)
    rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return rz @ ry @ rx


class Skeleton:
    def __init__(self, path):
        self.bones = {}          # name -> dict(direction, length, axis(C), dof)
        self.children = {}
        self.parent = {}
        self.root_order = []
        self.root_axis = np.eye(3)
        section = None
        cur = None
        for raw in open(path):
            line = raw.strip()
            if not line or line.startswith('#'):
                continue
            if line.startswith(':'):
                parts = line.split()
                section = parts[0][1:]
                continue
            parts = line.split()
            if section == 'root':
                if parts[0] == 'order':
                    self.root_order = [p.lower() for p in parts[1:]]
                elif parts[0] == 'orientation':
                    self.root_axis = rot_xyz(*map(float, parts[1:4]))
            elif section == 'bonedata':
                if parts[0] == 'begin':
                    cur = {'dof': [], 'axis': np.eye(3)}
                elif parts[0] == 'end':
                    self.bones[cur['name']] = cur
                    cur = None
                elif parts[0] == 'name':
                    cur['name'] = parts[1]
                elif parts[0] == 'direction':
                    cur['direction'] = np.array(list(map(float, parts[1:4])))
                elif parts[0] == 'length':
                    cur['length'] = float(parts[1])
                elif parts[0] == 'axis':
                    cur['axis'] = rot_xyz(*map(float, parts[1:4]))
                elif parts[0] == 'dof':
                    cur['dof'] = [p.lower() for p in parts[1:]]
            elif section == 'hierarchy':
                if parts[0] in ('begin', 'end'):
                    continue
                self.children[parts[0]] = parts[1:]
                for c in parts[1:]:
                    self.parent[c] = parts[0]
        self.order = []          # parents before children
        stack = ['root']
        while stack:
            n = stack.pop(0)
            self.order.append(n)
            stack.extend(self.children.get(n, []))


def read_amc(path, skel):
    """Frames as dicts: segment -> list of values (root: tx ty tz rx ry rz)."""
    frames = []
    cur = None
    for raw in open(path):
        line = raw.strip()
        if not line or line.startswith('#') or line.startswith(':'):
            continue
        parts = line.split()
        if parts[0].isdigit() and len(parts) == 1:
            cur = {}
            frames.append(cur)
            continue
        if cur is not None:
            cur[parts[0]] = list(map(float, parts[1:]))
    return frames


def fk(skel, frame):
    """Global rotations (3x3, delta from the rest pose, CMU frame), segment end positions and the root position,
    all in metres."""
    g = {}
    end = {}
    vals = frame.get('root', [0.0] * 6)
    root_vals = dict(zip(skel.root_order, vals))
    pos = np.array([root_vals.get('tx', 0.0), root_vals.get('ty', 0.0), root_vals.get('tz', 0.0)]) * UNIT_M
    m = rot_xyz(root_vals.get('rx', 0.0), root_vals.get('ry', 0.0), root_vals.get('rz', 0.0))
    c = skel.root_axis
    g['root'] = c @ m @ c.T
    end['root'] = pos
    for name in skel.order[1:]:
        b = skel.bones[name]
        v = dict(zip(b['dof'], frame.get(name, [])))
        m = rot_xyz(v.get('rx', 0.0), v.get('ry', 0.0), v.get('rz', 0.0))
        c = b['axis']
        p = skel.parent[name]
        g[name] = g[p] @ c @ m @ c.T
        end[name] = end[p] + g[name] @ (b['direction'] * b['length'] * UNIT_M)
    return g, end, pos


def clip_fk(skel, frames, step=1):
    return [fk(skel, f) for f in frames[::step]]


if __name__ == '__main__':
    # Analysis: per quarter second, root speed (m/s), heading of travel and of the pelvis, root height, and the
    # right and left wrist speeds (throws show as wrist peaks).
    import sys, math
    asf, amc = sys.argv[1], sys.argv[2]
    sk = Skeleton(asf)
    fr = read_amc(amc, sk)
    res = clip_fk(sk, fr)
    hz = 120.0
    print(f'{amc}: {len(fr)} frames, {len(fr) / hz:.2f} s')
    q = 30
    for i in range(0, len(res) - q, q):
        p0, p1 = res[i][2], res[i + q][2]
        d = (p1 - p0) * hz / q
        speed = math.hypot(d[0], d[2])
        travel = math.degrees(math.atan2(d[0], d[2]))
        f = res[i][0]['root'] @ np.array([0, 0, 1.0])
        face = math.degrees(math.atan2(f[0], f[2]))
        rw = np.linalg.norm(res[i + q][1]['rwrist'] - res[i][1]['rwrist']) * hz / q
        lw = np.linalg.norm(res[i + q][1]['lwrist'] - res[i][1]['lwrist']) * hz / q
        print(f'  t={i / hz:5.2f}  speed={speed:4.2f}  travel={travel:7.1f}  face={face:7.1f}  h={p0[1]:.2f}'
              f'  rwrist={rw:5.2f}  lwrist={lw:5.2f}')
