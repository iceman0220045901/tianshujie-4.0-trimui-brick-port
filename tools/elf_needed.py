"""读 ELF 的 DT_NEEDED（依赖库名）+ RPATH/RUNPATH，并打印 PT_INTERP。

用法: python elf_needed.py <file> [<file> ...]
"""
import struct
import sys

for path in sys.argv[1:]:
    b = open(path, 'rb').read()
    if b[:4] != b'\x7fELF':
        print('%s: NOT ELF' % path)
        continue
    is64 = b[4] == 2
    endian = '<' if b[5] == 1 else '>'
    if is64:
        e_shoff, = struct.unpack_from(endian + 'Q', b, 0x28)
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from(endian + 'HHH', b, 0x3A)
        e_phoff, = struct.unpack_from(endian + 'Q', b, 0x20)
        e_phentsize, e_phnum = struct.unpack_from(endian + 'HH', b, 0x36)
        e_type, e_machine = struct.unpack_from(endian + 'HH', b, 0x10)
    else:
        e_shoff, = struct.unpack_from(endian + 'I', b, 0x20)
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from(endian + 'HHH', b, 0x2E)
        e_phoff, = struct.unpack_from(endian + 'I', b, 0x1C)
        e_phentsize, e_phnum = struct.unpack_from(endian + 'HH', b, 0x2A)
        e_type, e_machine = struct.unpack_from(endian + 'HH', b, 0x10)

    print('==== %s' % path)
    print('  ELF%d  type=%d  machine=0x%X' % (64 if is64 else 32, e_type, e_machine))

    # PT_INTERP
    interp = None
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type, = struct.unpack_from(endian + 'I', b, off)
        if p_type == 3:  # PT_INTERP
            if is64:
                p_offset, = struct.unpack_from(endian + 'Q', b, off + 8)
                p_filesz, = struct.unpack_from(endian + 'Q', b, off + 32)
            else:
                p_offset, = struct.unpack_from(endian + 'I', b, off + 4)
                p_filesz, = struct.unpack_from(endian + 'I', b, off + 16)
            interp = b[p_offset:p_offset + p_filesz].split(b'\x00')[0].decode()
    if interp:
        print('  interp: %s' % interp)

    # section headers
    secs = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        if is64:
            name, stype = struct.unpack_from(endian + 'II', b, off)
            s_offset, s_size = struct.unpack_from(endian + 'QQ', b, off + 24)
            s_link, = struct.unpack_from(endian + 'I', b, off + 40)
            s_entsize, = struct.unpack_from(endian + 'Q', b, off + 56)
        else:
            name, stype = struct.unpack_from(endian + 'II', b, off)
            s_offset, s_size = struct.unpack_from(endian + 'II', b, off + 16)
            s_link, = struct.unpack_from(endian + 'I', b, off + 24)
            s_entsize, = struct.unpack_from(endian + 'I', b, off + 36)
        secs.append({'type': stype, 'off': s_offset, 'size': s_size,
                     'link': s_link, 'entsize': s_entsize})
    for s in secs:
        if s['type'] in (5, 6):  # SHT_STRTAB / SHT_DYNAMIC
            pass

    # dynamic section
    dyn = next((s for s in secs if s['type'] == 6), None)
    strtab = secs[dyn['link']] if dyn else None
    needed, rpath, runpath = [], None, None
    if dyn and strtab:
        step = 16 if is64 else 8
        fmt = endian + ('qQ' if is64 else 'iI')
        for off in range(dyn['off'], dyn['off'] + dyn['size'], step):
            tag, val = struct.unpack_from(fmt, b, off)
            if tag == 0:
                break
            if tag in (1, 15, 29):  # NEEDED, RPATH, RUNPATH
                e = strtab['off'] + val
                s = b[e:b.index(b'\x00', e)].decode('utf-8', 'replace')
                if tag == 1:
                    needed.append(s)
                elif tag == 15:
                    rpath = s
                else:
                    runpath = s
    for n in needed:
        print('  NEEDED %s' % n)
    if rpath:
        print('  RPATH %s' % rpath)
    if runpath:
        print('  RUNPATH %s' % runpath)
