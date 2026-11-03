#!/usr/bin/env python3
"""Windows kaynaklarını (simge, uygulama bildirimi, sürüm bilgisi) Go bağlayıcısının okuduğu bir
COFF nesnesine (.syso) yazar. Ek araç ya da kütüphane gerekmez.

Kullanım: gen_syso.py <çıktı.syso> <simge.ico> <açıklama> <dosya adı> <derleme no> <sürüm etiketi>
"""
import struct
import sys

out, ico_path, desc, orig, build, label = sys.argv[1:7]
build = int(build)

# ---------------------------------------------------------------- simge (.ico → RT_ICON + RT_GROUP_ICON)
ico = open(ico_path, 'rb').read()
_, kind, count = struct.unpack_from('<HHH', ico, 0)
assert kind == 1 and count > 0, 'geçersiz .ico'
images, grp_entries = [], []
for i in range(count):
    w, h, colors, _, planes, bits, size, offset = struct.unpack_from('<BBBBHHII', ico, 6 + 16 * i)
    images.append(ico[offset:offset + size])
    grp_entries.append((w, h, colors, planes, bits, size, i + 1))
grp = struct.pack('<HHH', 0, 1, count)
for w, h, colors, planes, bits, size, ident in grp_entries:
    grp += struct.pack('<BBBBHHIH', w, h, colors, 0, planes, bits, size, ident)

MANIFEST = b'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity type="win32" name="MelCapital.Kurulum" version="1.0.0.0" processorArchitecture="amd64"/>
  <description>Mel Capital</description>
  <dependency><dependentAssembly><assemblyIdentity type="win32" name="Microsoft.Windows.Common-Controls" version="6.0.0.0" processorArchitecture="*" publicKeyToken="6595b64144ccf1df" language="*"/></dependentAssembly></dependency>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges><requestedExecutionLevel level="asInvoker" uiAccess="false"/></requestedPrivileges></security></trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1"><application><supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/></application></compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3"><windowsSettings><dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware><dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness></windowsSettings></application>
</assembly>
'''


def u16z(s):
    return s.encode('utf-16-le') + b'\0\0'


def pad4(b):
    return b + bytes((-len(b)) % 4)


def vs_block(key, value=b'', children=b'', vtype=1, vlen=None):
    """VS_VERSIONINFO yapı bloğu."""
    head_wo_len = struct.pack('<HH', vlen if vlen is not None else (len(value) // 2 if vtype == 1 else len(value)), vtype) + u16z(key)
    head_wo_len = pad4(struct.pack('<H', 0) + head_wo_len)[2:]
    body = pad4(value) + children if value else children
    total = 2 + len(head_wo_len) + len(body)
    return struct.pack('<H', total) + head_wo_len + body


def version_info():
    ver = (1, 0, min(build, 65535), 0)
    ms, ls = (ver[0] << 16) | ver[1], (ver[2] << 16) | ver[3]
    fixed = struct.pack('<IIIIIIIIIIIII', 0xFEEF04BD, 0x00010000, ms, ls, ms, ls, 0x3F, 0, 0x40004, 1, 0, 0, 0)
    dotted = '%d.%d.%d.%d' % ver
    strings = [('CompanyName', 'Melih Durmaz'), ('FileDescription', desc), ('FileVersion', dotted),
               ('InternalName', desc), ('OriginalFilename', orig), ('ProductName', 'Mel Capital'),
               ('ProductVersion', label), ('LegalCopyright', '© Melih Durmaz')]
    st = b''.join(pad4(vs_block(k, u16z(v))) for k, v in strings)
    sfi = vs_block('StringFileInfo', children=vs_block('040904B0', children=st, vtype=1, vlen=0), vtype=1, vlen=0)
    vfi = vs_block('VarFileInfo', children=vs_block('Translation', struct.pack('<HH', 0x0409, 0x04B0), vtype=0), vtype=1, vlen=0)
    return vs_block('VS_VERSION_INFO', fixed, pad4(sfi) + vfi, vtype=0, vlen=len(fixed))


# Kaynak ağacı: tür → kimlik → dil → veri
RT_ICON, RT_VERSION, RT_GROUP_ICON, RT_MANIFEST = 3, 16, 14, 24
LANG = 0x0409
tree = {RT_ICON: {i: data for i, data in enumerate(images, start=1)},
        RT_GROUP_ICON: {1: grp},
        RT_VERSION: {1: version_info()},
        RT_MANIFEST: {1: MANIFEST}}
types = sorted(tree)

# Yerleşim: kök dizin, tür dizinleri, kimlik dizinleri, veri girdileri, veriler
DIR, ENT = 16, 8
off = DIR + ENT * len(types)
type_dir_off = {}
for t in types:
    type_dir_off[t] = off
    off += DIR + ENT * len(tree[t])
name_dir_off = {}
for t in types:
    for n in sorted(tree[t]):
        name_dir_off[(t, n)] = off
        off += DIR + ENT * 1
data_entry_off = {}
for t in types:
    for n in sorted(tree[t]):
        data_entry_off[(t, n)] = off
        off += 16
data_off = {}
for t in types:
    for n in sorted(tree[t]):
        off = (off + 7) & ~7
        data_off[(t, n)] = off
        off += len(tree[t][n])
total = (off + 7) & ~7

sec = bytearray(total)


def put(o, b):
    sec[o:o + len(b)] = b


put(0, struct.pack('<IIHHHH', 0, 0, 4, 0, 0, len(types)))
for i, t in enumerate(types):
    put(DIR + ENT * i, struct.pack('<II', t, 0x80000000 | type_dir_off[t]))
for t in types:
    names = sorted(tree[t])
    put(type_dir_off[t], struct.pack('<IIHHHH', 0, 0, 4, 0, 0, len(names)))
    for i, n in enumerate(names):
        put(type_dir_off[t] + DIR + ENT * i, struct.pack('<II', n, 0x80000000 | name_dir_off[(t, n)]))
relocs = []
for t in types:
    for n in sorted(tree[t]):
        put(name_dir_off[(t, n)], struct.pack('<IIHHHH', 0, 0, 4, 0, 0, 1))
        put(name_dir_off[(t, n)] + DIR, struct.pack('<II', LANG, data_entry_off[(t, n)]))
        put(data_entry_off[(t, n)], struct.pack('<IIII', data_off[(t, n)], len(tree[t][n]), 0, 0))
        relocs.append(data_entry_off[(t, n)])
        put(data_off[(t, n)], tree[t][n])

# COFF
nrel = len(relocs)
hdr_size = 20 + 40
raw_ptr = hdr_size
rel_ptr = raw_ptr + total
sym_ptr = rel_ptr + 10 * nrel
coff = struct.pack('<HHIIIHH', 0x8664, 1, 0, sym_ptr, 1, 0, 0)
coff += struct.pack('<8sIIIIIIHHI', b'.rsrc', 0, 0, total, raw_ptr, rel_ptr, 0, nrel, 0, 0x40000040)
coff += bytes(sec)
for r in relocs:
    coff += struct.pack('<IIH', r, 0, 3)  # IMAGE_REL_AMD64_ADDR32NB
coff += struct.pack('<8sIhHBB', b'.rsrc', 0, 1, 0, 3, 0)
coff += struct.pack('<I', 4)
open(out, 'wb').write(coff)
print('syso:', len(coff), 'bayt,', nrel, 'kaynak')
