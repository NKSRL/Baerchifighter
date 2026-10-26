# Gibt einen Teilbaum eines binaeren .rbxl (Instanzen + wichtige Eigenschaften) als Text und JSON aus.
# Aufruf: python -I rbxl_dump_subtree.py <place.rbxl> <Pfad-Praefix> <out-basis>  (schreibt <out-basis>.txt und .json)
import sys, struct, os, json, site, math
sys.path.append(site.getusersitepackages())
import zstandard

ROT = {0x02:(1,0,0,0,1,0,0,0,1),0x03:(1,0,0,0,0,-1,0,1,0),0x05:(1,0,0,0,-1,0,0,0,-1),0x06:(1,0,0,0,0,1,0,-1,0),
0x07:(0,1,0,1,0,0,0,0,-1),0x09:(0,0,1,1,0,0,0,1,0),0x0a:(0,-1,0,1,0,0,0,0,1),0x0c:(0,0,-1,1,0,0,0,-1,0),
0x0d:(0,1,0,0,0,1,1,0,0),0x0e:(0,0,-1,0,1,0,1,0,0),0x10:(0,-1,0,0,0,-1,1,0,0),0x11:(0,0,1,0,-1,0,1,0,0),
0x14:(-1,0,0,0,1,0,0,0,-1),0x15:(-1,0,0,0,0,1,0,1,0),0x17:(-1,0,0,0,-1,0,0,0,1),0x18:(-1,0,0,0,0,-1,0,-1,0),
0x19:(0,1,0,-1,0,0,0,0,1),0x1b:(0,0,-1,-1,0,0,0,1,0),0x1c:(0,-1,0,-1,0,0,0,0,-1),0x1e:(0,0,1,-1,0,0,0,-1,0),
0x1f:(0,1,0,0,0,-1,-1,0,0),0x20:(0,0,1,0,1,0,-1,0,0),0x22:(0,-1,0,0,0,1,-1,0,0),0x23:(0,0,-1,0,-1,0,-1,0,0)}
MAT = {256:'Plastic',272:'SmoothPlastic',288:'Neon',512:'Wood',528:'WoodPlanks',784:'Marble',800:'Slate',816:'Concrete',832:'Granite',848:'Brick',864:'Pebble',880:'Cobblestone',896:'Rock',1040:'CorrodedMetal',1056:'DiamondPlate',1072:'Foil',1088:'Metal',1280:'Grass',1296:'Sand',1312:'Fabric',1536:'Ice',1568:'Glass',1584:'ForceField',1600:'Air',1792:'Asphalt',1808:'Snow',1824:'Mud',1856:'Basalt',1872:'CrackedLava',1920:'Pavement',2048:'Water',2560:'Cardboard',2576:'Carpet',2592:'CeramicTiles',2608:'ClayRoofTiles',2624:'RoofShingles',2640:'Leather',2656:'Plaster',2672:'Rubber'}
SHAPE = {0:'Ball',1:'Block',2:'Cylinder',3:'Wedge',4:'CornerWedge'}

def decompress(data, clen, ulen):
    if clen == 0:
        return data
    return zstandard.ZstdDecompressor().decompress(data, max_output_size=max(ulen, 1))

def rd_str(buf, pos):
    (n,) = struct.unpack_from('<I', buf, pos)
    pos += 4
    return buf[pos:pos+n], pos + n

def il_u32(buf, pos, count):
    out = []
    for i in range(count):
        out.append((buf[pos+i] << 24) | (buf[pos+count+i] << 16) | (buf[pos+2*count+i] << 8) | buf[pos+3*count+i])
    return out, pos + 4*count

def il_i32(buf, pos, count):
    u, pos = il_u32(buf, pos, count)
    return [(v >> 1) ^ (-(v & 1)) for v in u], pos

def il_f32(buf, pos, count):
    u, pos = il_u32(buf, pos, count)
    out = []
    for v in u:
        bits = ((v >> 1) | ((v & 1) << 31)) & 0xffffffff
        out.append(round(struct.unpack('<f', struct.pack('<I', bits))[0], 4))
    return out, pos

def refs(buf, pos, count):
    vals, pos = il_i32(buf, pos, count)
    acc = 0
    res = []
    for v in vals:
        acc += v
        res.append(acc)
    return res, pos

KEEP = ('Size', 'size', 'CFrame', 'Color', 'Color3', 'Color3uint8', 'Material', 'Transparency', 'Reflectance', 'Shape', 'MeshId', 'TextureID',
        'TextureId', 'MeshType', 'Anchored', 'CanCollide', 'CastShadow', 'PrimaryPart', 'Texture', 'Brightness', 'Range',
        'Enabled', 'Face', 'LightEmission', 'Width0', 'Width1', 'Rate', 'Lifetime', 'Speed', 'Scale', 'WorldPivotData',
        'Massless', 'Value', 'Attachment0', 'Attachment1', 'Offset', 'Orientation', 'Position')

def main():
    path, prefix, outbase = sys.argv[1], sys.argv[2], sys.argv[3]
    d = open(path, 'rb').read()
    pos = 32
    classes = {}
    props = {}
    parent = {}
    while pos < len(d):
        name = d[pos:pos+4]
        clen, ulen, _ = struct.unpack_from('<III', d, pos+4)
        raw = d[pos+16:pos+16+(clen or ulen)]
        pos += 16 + (clen or ulen)
        if name == b'END\x00':
            break
        buf = decompress(raw, clen, ulen)
        if name == b'INST':
            (cid,) = struct.unpack_from('<I', buf, 0)
            cname, p = rd_str(buf, 4)
            p += 1
            (cnt,) = struct.unpack_from('<I', buf, p)
            p += 4
            rl, p = refs(buf, p, cnt)
            classes[cid] = (cname.decode('utf-8', 'replace'), rl)
        elif name == b'PROP':
            (cid,) = struct.unpack_from('<I', buf, 0)
            pname, p = rd_str(buf, 4)
            tid = buf[p]
            p += 1
            pname = pname.decode('utf-8', 'replace')
            cname, rl = classes[cid]
            n = len(rl)
            vals = None
            try:
                if tid == 0x01:
                    vals = []
                    for _ in range(n):
                        s, p = rd_str(buf, p)
                        vals.append(s.decode('utf-8', 'replace') if len(s) < 200 else '<%d bytes>' % len(s))
                elif tid == 0x02:
                    vals = [bool(buf[p+i]) for i in range(n)]
                elif tid == 0x03:
                    vals, p = il_i32(buf, p, n)
                elif tid == 0x04:
                    vals, p = il_f32(buf, p, n)
                elif tid == 0x05:
                    vals = [round(struct.unpack_from('<d', buf, p+8*i)[0], 4) for i in range(n)]
                elif tid in (0x0B, 0x12):
                    vals, p = il_u32(buf, p, n)
                elif tid == 0x0C:
                    r, p = il_f32(buf, p, n)
                    g, p = il_f32(buf, p, n)
                    b, p = il_f32(buf, p, n)
                    vals = [(round(r[i]*255), round(g[i]*255), round(b[i]*255)) for i in range(n)]
                elif tid == 0x0E:
                    x, p = il_f32(buf, p, n)
                    y, p = il_f32(buf, p, n)
                    z, p = il_f32(buf, p, n)
                    vals = [(x[i], y[i], z[i]) for i in range(n)]
                elif tid == 0x10:
                    rots = []
                    for _ in range(n):
                        rid = buf[p]
                        p += 1
                        if rid == 0:
                            rots.append(tuple(round(v, 3) for v in struct.unpack_from('<9f', buf, p)))
                            p += 36
                        else:
                            rots.append(ROT.get(rid, ('rot?', rid)))
                    x, p = il_f32(buf, p, n)
                    y, p = il_f32(buf, p, n)
                    z, p = il_f32(buf, p, n)
                    vals = [{'pos': (x[i], y[i], z[i]), 'rot': rots[i]} for i in range(n)]
                elif tid == 0x13:
                    vals, p = refs(buf, p, n)
                elif tid == 0x1A:
                    vals = [(buf[p+i], buf[p+n+i], buf[p+2*n+i]) for i in range(n)]
                else:
                    continue
            except Exception:
                continue
            for i, r in enumerate(rl):
                props.setdefault(r, {})[pname] = vals[i]
        elif name == b'PRNT':
            (cnt,) = struct.unpack_from('<I', buf, 1)
            kids, p = refs(buf, 5, cnt)
            pars, p = refs(buf, p, cnt)
            for k, pa in zip(kids, pars):
                parent[k] = pa
    classof = {}
    for cid, (cname, rl) in classes.items():
        for r in rl:
            classof[r] = cname
    children = {}
    for k, pa in parent.items():
        children.setdefault(pa, []).append(k)

    def nm(r):
        return props.get(r, {}).get('Name', '?')

    def fullpath(r):
        parts = []
        s = 0
        while r is not None and r != -1 and s < 64:
            parts.append(nm(r))
            r = parent.get(r, -1)
            s += 1
        return '/'.join(reversed(parts))

    roots = [r for r in classof if fullpath(r) == prefix]
    if not roots:
        print('Pfad nicht gefunden:', prefix)
        sys.exit(1)
    lines = []
    tree = []

    def walk(r, depth, acc):
        pr = props.get(r, {})
        c = classof.get(r, '?')
        info = {}
        for k in KEEP:
            if k in pr:
                v = pr[k]
                if k == 'Material' and isinstance(v, int):
                    v = MAT.get(v, v)
                if k == 'Shape' and isinstance(v, int):
                    v = SHAPE.get(v, v)
                if k == 'PrimaryPart' and isinstance(v, int):
                    v = nm(v) if v != -1 else None
                info[k] = v
        short = ', '.join('%s=%s' % (k, v) for k, v in info.items() if k not in ('CFrame', 'WorldPivotData'))
        cf = info.get('CFrame')
        cfs = (' pos=%s rot=%s' % (cf['pos'], cf['rot'])) if isinstance(cf, dict) else ''
        lines.append('  ' * depth + '%s "%s"' % (c, nm(r)) + ((' [%s]' % short) if short else '') + cfs)
        node = {'class': c, 'name': nm(r), 'props': info, 'children': []}
        acc.append(node)
        for ch in sorted(children.get(r, []), key=nm):
            walk(ch, depth + 1, node['children'])

    for r in roots:
        walk(r, 0, tree)
    mins = [math.inf] * 3
    maxs = [-math.inf] * 3
    nparts = [0]

    def bbox(node):
        p = node['props']
        cf = p.get('CFrame')
        sz = p.get('Size') or p.get('size')
        if isinstance(cf, dict) and sz:
            nparts[0] += 1
            for i in range(3):
                mins[i] = min(mins[i], cf['pos'][i] - sz[i] / 2)
                maxs[i] = max(maxs[i], cf['pos'][i] + sz[i] / 2)
        for ch in node['children']:
            bbox(ch)

    for n in tree:
        bbox(n)
    if nparts[0]:
        lines.insert(0, '# BaseParts: %d, grobe Box (ohne Rotation): min=%s max=%s Hoehe~%s' % (
            nparts[0], tuple(round(v, 2) for v in mins), tuple(round(v, 2) for v in maxs), round(maxs[1] - mins[1], 2)))
    with open(outbase + '.txt', 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    with open(outbase + '.json', 'w', encoding='utf-8') as f:
        json.dump(tree, f, indent=1, default=str)
    print('\n'.join(lines[:400]))
    if len(lines) > 400:
        print('... (%d Zeilen gesamt, siehe %s.txt)' % (len(lines), outbase))

main()
