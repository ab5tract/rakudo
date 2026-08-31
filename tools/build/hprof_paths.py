#!/usr/bin/env python3
"""Find shortest reference paths from GC roots / class statics to target
instances, walking edges.bin backwards. Prints one path per target."""
import numpy as np, sys, os

d = os.path.dirname(os.path.abspath(__file__))
target_class = sys.argv[1] if len(sys.argv) > 1 else 'org/raku/nqp/runtime/GlobalContext'

classes = {}
for line in open(os.path.join(d, 'classes.tsv')):
    cid, name = line.rstrip('\n').split('\t')
    classes[int(cid)] = name

oc = np.fromfile(os.path.join(d, 'objclass.bin'), dtype='<u8').reshape(-1, 2)
obj_ids, obj_cls = oc[:, 0], oc[:, 1]

# targets: instances of target_class
tcids = [cid for cid, name in classes.items() if name == target_class]
targets = obj_ids[np.isin(obj_cls, np.array(tcids, dtype='<u8'))]
print(f'targets ({target_class}):', [hex(t) for t in targets])

e = np.fromfile(os.path.join(d, 'edges.bin'), dtype='<u8').reshape(-1, 2)
src, dst = e[:, 0], e[:, 1]
order = np.argsort(dst, kind='stable')
src_s, dst_s = src[order], dst[order]

roots = {}
ROOTK = {0xFF:'unknown',1:'JNI global',2:'JNI local',3:'java frame',4:'native stack',5:'sticky class',6:'thread block',7:'monitor',8:'thread object'}
for line in open(os.path.join(d, 'roots.tsv')):
    k, oid = line.split('\t')
    roots.setdefault(int(oid), []).append(ROOTK.get(int(k), k))

class_ids = set(classes.keys())
# obj -> class map for labels
idx = np.argsort(obj_ids, kind='stable')
oid_sorted, cls_sorted = obj_ids[idx], obj_cls[idx]
def label(o):
    if o in class_ids:
        return f'class {classes[o]} (static field)'
    i = np.searchsorted(oid_sorted, o)
    if i < len(oid_sorted) and oid_sorted[i] == o:
        return classes.get(int(cls_sorted[i]), f'cls#{cls_sorted[i]:x}')
    return '?'

# BFS backwards: parent[obj] = child we reached it from (towards target)
for t in targets:
    parent = {int(t): 0}
    frontier = np.array([t], dtype='<u8')
    found = None
    for depth in range(40):
        # find all edges whose dst is in frontier
        lo = np.searchsorted(dst_s, frontier, side='left')
        hi = np.searchsorted(dst_s, frontier, side='right')
        newf = []
        for f, l, h in zip(frontier, lo, hi):
            for s in src_s[l:h]:
                s = int(s)
                if s not in parent:
                    parent[s] = int(f)
                    newf.append(s)
                    if s in roots:
                        found = s
            if found: break
        if found or not newf: break
        frontier = np.unique(np.array(newf, dtype='<u8'))
    print(f'\n=== target {hex(int(t))} depth {depth} ===')
    if not found:
        print('no root path found (frontier exhausted)', len(parent))
        continue
    node = found
    while node:
        r = roots.get(node)
        extra = f'  ROOT:{r}' if r else ''
        print(f'  {hex(node)}  {label(node)}{extra}')
        node = parent[node]
        if node == 0: break
    # print target line
    print(f'  {hex(int(t))}  {label(int(t))}')
