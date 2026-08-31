#!/usr/bin/env python3
"""Extract the object reference graph from an hprof heap dump.

Outputs (in the dump's directory):
  edges.bin    - little-endian u64 pairs (src_id, dst_id); class statics use
                 the class object id as src
  objclass.bin - u64 pairs (obj_id, class_id) for instances + object arrays
  classes.tsv  - class_id \t class_name
  roots.tsv    - root_kind \t obj_id
"""
import struct, sys, os, array

path = sys.argv[1]
outdir = os.path.dirname(os.path.abspath(path))
data = open(path, 'rb').read()
n = len(data)

# header
hdrend = data.index(b'\0') + 1
idsize, = struct.unpack_from('>I', data, hdrend)
assert idsize == 8, idsize
pos = hdrend + 4 + 8

TYPE_SIZE = {2: idsize, 4: 1, 5: 2, 6: 4, 7: 8, 8: 1, 9: 2, 10: 4, 11: 8}

strings = {}          # string_id -> bytes
loadclass = {}        # class_obj_id -> name_string_id
class_fields = {}     # class_id -> (super_id, [field types this class])
roots = []            # (kind, id)
heap_segments = []    # (start, end) of heap dump segment bodies

# ---- pass 1: top-level records ----
p = pos
while p < n:
    tag = data[p]
    length, = struct.unpack_from('>I', data, p + 5)
    body = p + 9
    if tag == 0x01:
        sid, = struct.unpack_from('>Q', data, body)
        strings[sid] = data[body + 8: body + length]
    elif tag == 0x02:
        cid, = struct.unpack_from('>Q', data, body + 4)
        nameid, = struct.unpack_from('>Q', data, body + 4 + 8 + 4)
        loadclass[cid] = nameid
    elif tag in (0x0C, 0x1C):
        heap_segments.append((body, body + length))
    p = body + length

# ---- pass 2: heap subrecords, classes + roots first ----
for (s, e) in heap_segments:
    p = s
    while p < e:
        sub = data[p]; p += 1
        if sub == 0xFF or sub == 0x05 or sub == 0x07:
            oid, = struct.unpack_from('>Q', data, p); p += 8
            roots.append((sub, oid))
        elif sub == 0x01:
            oid, = struct.unpack_from('>Q', data, p); p += 16
            roots.append((sub, oid))
        elif sub == 0x02 or sub == 0x03 or sub == 0x08:
            oid, = struct.unpack_from('>Q', data, p); p += 16
            roots.append((sub, oid))
        elif sub == 0x04 or sub == 0x06:
            oid, = struct.unpack_from('>Q', data, p); p += 12
            roots.append((sub, oid))
        elif sub == 0x20:
            cid, = struct.unpack_from('>Q', data, p)
            sup, = struct.unpack_from('>Q', data, p + 12)
            q = p + 12 + 8 * 6 + 4
            cpsize, = struct.unpack_from('>H', data, q); q += 2
            for _ in range(cpsize):
                t = data[q + 2]; q += 3 + TYPE_SIZE[t]
            nstat, = struct.unpack_from('>H', data, q); q += 2
            statics = []
            for _ in range(nstat):
                t = data[q + 8]
                if t == 2:
                    dst, = struct.unpack_from('>Q', data, q + 9)
                    if dst: statics.append(dst)
                q += 9 + TYPE_SIZE[t]
            nfields, = struct.unpack_from('>H', data, q); q += 2
            ftypes = []
            fnames = []
            for _ in range(nfields):
                fnames.append(struct.unpack_from('>Q', data, q)[0])
                ftypes.append(data[q + 8]); q += 9
            class_fields[cid] = (sup, ftypes, statics, fnames)
            p = q
        elif sub == 0x21:
            nb, = struct.unpack_from('>I', data, p + 16)
            p += 20 + nb
        elif sub == 0x22:
            cnt, = struct.unpack_from('>I', data, p + 12)
            p += 24 + 8 * cnt
        elif sub == 0x23:
            cnt, = struct.unpack_from('>I', data, p + 12)
            t = data[p + 16]
            p += 17 + cnt * TYPE_SIZE[t]
        else:
            raise SystemExit(f'unknown subrecord 0x{sub:02x} at {p-1}')

# java/lang/ref/Reference's referent field is a weak edge: the collector
# ignores it, so path analysis must too (all Reference subclasses).
name_to_cid = {}
for cid, nameid in loadclass.items():
    name_to_cid[strings.get(nameid, b'')] = cid
REF_CID = name_to_cid.get(b'java/lang/ref/Reference')
referent_idx = -1
if REF_CID and REF_CID in class_fields:
    for i, nid in enumerate(class_fields[REF_CID][3]):
        if strings.get(nid) == b'referent':
            referent_idx = i

# per-class object-field offsets over the full super chain
ref_offsets = {}
def offsets_for(cid):
    if cid in ref_offsets: return ref_offsets[cid]
    offs = []
    off = 0
    c = cid
    chain = []
    while c and c in class_fields:
        chain.append(c)
        c = class_fields[c][0]
    for c in chain:
        for i, t in enumerate(class_fields[c][1]):
            if t == 2 and not (c == REF_CID and i == referent_idx):
                offs.append(off)
            off += TYPE_SIZE[t]
    ref_offsets[cid] = offs
    return offs

edges = open(os.path.join(outdir, 'edges.bin'), 'wb')
objclass = open(os.path.join(outdir, 'objclass.bin'), 'wb')
ebuf = array.array('Q')
obuf = array.array('Q')

def flush():
    global ebuf, obuf
    ebuf.tofile(edges); ebuf = array.array('Q')
    obuf.tofile(objclass); obuf = array.array('Q')

# class static edges
for cid, (_, _, statics, _) in class_fields.items():
    for dst in statics:
        ebuf.append(cid); ebuf.append(dst)
flush()

# ---- pass 3: instances and object arrays ----
count = 0
for (s, e) in heap_segments:
    p = s
    while p < e:
        sub = data[p]; p += 1
        if sub == 0xFF or sub == 0x05 or sub == 0x07:
            p += 8
        elif sub == 0x01 or sub == 0x02 or sub == 0x03 or sub == 0x08:
            p += 16
        elif sub == 0x04 or sub == 0x06:
            p += 12
        elif sub == 0x20:
            cid, = struct.unpack_from('>Q', data, p)
            q = p + 12 + 8 * 6 + 4
            cpsize, = struct.unpack_from('>H', data, q); q += 2
            for _ in range(cpsize):
                t = data[q + 2]; q += 3 + TYPE_SIZE[t]
            nstat, = struct.unpack_from('>H', data, q); q += 2
            for _ in range(nstat):
                t = data[q + 8]; q += 9 + TYPE_SIZE[t]
            nfields, = struct.unpack_from('>H', data, q); q += 2
            q += 9 * nfields
            p = q
        elif sub == 0x21:
            oid, cls = struct.unpack_from('>Q', data, p)[0], struct.unpack_from('>Q', data, p + 12)[0]
            nb, = struct.unpack_from('>I', data, p + 20)
            base = p + 24
            obuf.append(oid); obuf.append(cls)
            for off in offsets_for(cls):
                dst, = struct.unpack_from('>Q', data, base + off)
                if dst:
                    ebuf.append(oid); ebuf.append(dst)
            p = base + nb
            count += 1
            if count % 2000000 == 0:
                flush(); print(f'{count} instances', flush=True)
        elif sub == 0x22:
            oid, = struct.unpack_from('>Q', data, p)
            cnt, = struct.unpack_from('>I', data, p + 12)
            acls, = struct.unpack_from('>Q', data, p + 16)
            obuf.append(oid); obuf.append(acls)
            base = p + 24
            for i in range(cnt):
                dst, = struct.unpack_from('>Q', data, base + 8 * i)
                if dst:
                    ebuf.append(oid); ebuf.append(dst)
            p = base + 8 * cnt
        elif sub == 0x23:
            cnt, = struct.unpack_from('>I', data, p + 12)
            t = data[p + 16]
            p += 17 + cnt * TYPE_SIZE[t]
flush()
edges.close(); objclass.close()

with open(os.path.join(outdir, 'classes.tsv'), 'w') as f:
    for cid, nameid in loadclass.items():
        f.write(f'{cid}\t{strings.get(nameid, b"?").decode("utf-8", "replace")}\n')
with open(os.path.join(outdir, 'roots.tsv'), 'w') as f:
    for kind, oid in roots:
        f.write(f'{kind}\t{oid}\n')
print(f'done: {count} instances')
