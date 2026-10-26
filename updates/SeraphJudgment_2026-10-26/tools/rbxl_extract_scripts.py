# Liest eine binaere .rbxl-Datei (Roblox Place, zstd- oder lz4-komprimierte Chunks)
# und schreibt alle Skript-Quelltexte (Script, LocalScript, ModuleScript) als Dateien.
# Aufruf: python -I rbxl_extract_scripts.py <place.rbxl> <ausgabeordner>
import sys, struct, os, hashlib, site
sys.path.append(site.getusersitepackages())
import zstandard

def lz4_block_decompress(src, ulen):
    dst = bytearray(); i = 0; n = len(src)
    while i < n:
        token = src[i]; i += 1
        lit = token >> 4
        if lit == 15:
            while True:
                b = src[i]; i += 1; lit += b
                if b != 255: break
        dst += src[i:i+lit]; i += lit
        if i >= n: break
        off = src[i] | (src[i+1] << 8); i += 2
        ml = token & 15
        if ml == 15:
            while True:
                b = src[i]; i += 1; ml += b
                if b != 255: break
        ml += 4
        start = len(dst) - off
        for k in range(ml):
            dst.append(dst[start + k])
    return bytes(dst)

def decompress(data, clen, ulen):
    if clen == 0:
        return data
    if data[:4] == b'\x28\xb5\x2f\xfd':
        return zstandard.ZstdDecompressor().decompress(data, max_output_size=max(ulen, 1))
    return lz4_block_decompress(data, ulen)

def rd_str(buf, pos):
    (n,) = struct.unpack_from('<I', buf, pos); pos += 4
    return buf[pos:pos+n], pos + n

def interleaved_i32(buf, pos, count):
    out = []
    for i in range(count):
        v = (buf[pos+i] << 24) | (buf[pos+count+i] << 16) | (buf[pos+2*count+i] << 8) | buf[pos+3*count+i]
        out.append((v >> 1) ^ (-(v & 1)))
    return out, pos + 4*count

def referents(buf, pos, count):
    vals, pos = interleaved_i32(buf, pos, count)
    acc = 0; res = []
    for v in vals:
        acc += v; res.append(acc)
    return res, pos

def main():
    path, outdir = sys.argv[1], sys.argv[2]
    d = open(path, 'rb').read()
    assert d[:8] == b'<roblox!', 'kein binaeres rbxl'
    version, nclasses, ninst = struct.unpack_from('<HiI', d, 14)
    pos = 32
    classes = {}      # classId -> (name, [referents])
    names = {}        # referent -> Name
    sources = {}      # referent -> Source (bytes)
    parent = {}       # child referent -> parent referent
    chunks = 0
    while pos < len(d):
        name = d[pos:pos+4]; clen, ulen, _res = struct.unpack_from('<III', d, pos+4)
        raw = d[pos+16:pos+16+(clen or ulen)]
        pos += 16 + (clen or ulen); chunks += 1
        if name == b'END\x00': break
        buf = decompress(raw, clen, ulen)
        if name == b'INST':
            (cid,) = struct.unpack_from('<I', buf, 0); cname, p = rd_str(buf, 4)
            fmt = buf[p]; p += 1; (cnt,) = struct.unpack_from('<I', buf, p); p += 4
            refs, p = referents(buf, p, cnt)
            classes[cid] = (cname.decode('utf-8', 'replace'), refs)
        elif name == b'PROP':
            (cid,) = struct.unpack_from('<I', buf, 0); pname, p = rd_str(buf, 4)
            tid = buf[p]; p += 1
            pname = pname.decode('utf-8', 'replace')
            if tid != 0x01 or pname not in ('Name', 'Source'):
                continue
            cname, refs = classes[cid]
            for r in refs:
                s, p = rd_str(buf, p)
                if pname == 'Name': names[r] = s.decode('utf-8', 'replace')
                else: sources[r] = s
        elif name == b'PRNT':
            (cnt,) = struct.unpack_from('<I', buf, 1)
            kids, p = referents(buf, 5, cnt)
            pars, p = referents(buf, p, cnt)
            for k, pa in zip(kids, pars): parent[k] = pa
    classof = {}
    for cid, (cname, refs) in classes.items():
        for r in refs: classof[r] = cname
    def fullpath(r):
        parts = []
        seen = 0
        while r is not None and r != -1 and seen < 64:
            parts.append(names.get(r, '?')); r = parent.get(r, -1); seen += 1
        return '/'.join(reversed(parts))
    index = []
    for r, src in sources.items():
        cname = classof.get(r, '?')
        if cname not in ('Script', 'LocalScript', 'ModuleScript'): continue
        fp = fullpath(r)
        safe = ''.join(c if (c.isalnum() or c in '._- /') else '_' for c in fp)
        out = os.path.join(outdir, safe + '.luau')
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, 'wb') as f: f.write(src)
        index.append((fp, cname, len(src), hashlib.md5(src).hexdigest()))
    index.sort()
    with open(os.path.join(outdir, '_INDEX.txt'), 'w', encoding='utf-8') as f:
        for fp, cname, n, h in index:
            f.write(f'{cname}\t{n}\t{h}\t{fp}\n')
    print(f'version {version}, {nclasses} classes, {ninst} instances, {chunks} chunks')
    print(f'{len(index)} scripts written to {outdir}')
main()
