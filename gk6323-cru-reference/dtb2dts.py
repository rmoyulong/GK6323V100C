import struct, sys

def fmt(name, val):
    if len(val) > 0 and val.endswith(b'\0'):
        try:
            s = val[:-1].decode('utf-8')
            if all(32 <= ord(c) < 127 or c == '\0' for c in s):
                parts = s.split('\0')
                if len(parts) == 1:
                    return '%s = "%s";' % (name, s)
                return '%s = %s;' % (name, ', '.join('"%s"' % x for x in parts))
        except Exception:
            pass
    if len(val) % 4 == 0 and len(val) > 0:
        n = len(val) // 4
        vals = struct.unpack('>%dI' % n, val)
        return '%s = <%s>;' % (name, ' '.join('0x%x' % v for v in vals))
    return '%s = [%s];' % (name, ' '.join('%02x' % b for b in val))

def parse(path, out):
    data = open(path, 'rb').read()
    hdr = struct.unpack('>10I', data[:40])
    magic, totalsize, off_struct, off_strings, off_rsv, ver, lastver, bootcpu, sz_str, sz_struct = hdr
    assert magic == 0xd00dfeed, hex(magic)
    strings = data[off_strings:off_strings + sz_str]
    def gets(off):
        e = strings.index(b'\0', off)
        return strings[off:e].decode('utf-8', 'replace')
    p = off_struct
    lines = []
    depth = 0
    while True:
        tok = struct.unpack('>I', data[p:p + 4])[0]; p += 4
        if tok == 1:
            e = data.index(b'\0', p)
            name = data[p:e].decode('utf-8', 'replace'); p = e + 1
            p = (p + 3) & ~3
            lines.append('\t' * depth + (name if name else '/') + ' {')
            depth += 1
        elif tok == 2:
            depth -= 1
            lines.append('\t' * depth + '};')
        elif tok == 3:
            ln, nameoff = struct.unpack('>II', data[p:p + 8]); p += 8
            val = data[p:p + ln]; p = (p + ln + 3) & ~3
            lines.append('\t' * depth + fmt(gets(nameoff), val))
        elif tok == 4:
            pass
        elif tok == 9:
            break
        else:
            raise Exception('bad token %d at %d' % (tok, p))
    open(out, 'w').write('\n'.join(lines) + '\n')
    print('totalsize=%d  lines=%d -> %s' % (totalsize, len(lines), out))

parse(sys.argv[1], sys.argv[2])
