#!/usr/bin/env python3
"""Relocate only pinned VNDK30 passthrough search literals, both ABIs."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--vndk-root', type=Path, required=True)
p.add_argument('--output-dir', type=Path, required=True)
a = p.parse_args()
a.output_dir.mkdir(parents=True, exist_ok=True)
pins = {'lib': '902bf57682dc9ecbe799524ec9a7ffe566898175912014d019f46cfd338dfe61',
        'lib64': '7bfbd57ee8afbde1c1be2ff7a710a56afad1e7f4e6501660d8074c8e8493aba5'}
paths = {b'/apex/com.android.vndk.v%s/lib/hw/': b'/apex/com.android.runtime/hw32/',
         b'/apex/com.android.vndk.v%s/lib64/hw/': b'/apex/com.android.runtime/hw64/'}
records = {}
for lib, expected in pins.items():
    original = (a.vndk_root/lib/'libhidlbase.so').read_bytes()
    assert hashlib.sha256(original).hexdigest() == expected
    bits = 32 if lib == 'lib' else 64
    assert original[:6] == b'\x7fELF' + bytes([1 if bits==32 else 2, 1])
    assert struct.unpack_from('<H', original, 18)[0] == (40 if bits==32 else 183)
    phoff = struct.unpack_from('<I' if bits==32 else '<Q', original, 28 if bits==32 else 32)[0]
    count = struct.unpack_from('<H', original, 44 if bits==32 else 56)[0]
    loads = []
    for i in range(count):
        h = struct.unpack_from('<IIIIIIII' if bits==32 else '<IIQQQQQQ', original, phoff+i*(32 if bits==32 else 56))
        if h[0]==1:
            loads.append((h[1],h[4],h[6]) if bits==32 else (h[2],h[5],h[1]))
    changed = bytearray(original)
    regions = []
    for before, after in paths.items():
        assert original.count(before+b'\0') == 1 and len(after)<=len(before)
        at = original.index(before+b'\0')
        assert any(start<=at and at+len(before)+1<=start+size and flags==4 for start,size,flags in loads)
        replacement = after+b'\0'*(len(before)+1-len(after))
        changed[at:at+len(before)+1] = replacement
        regions.append(dict(offset=at,before=before.decode(),after=after.decode()))
    assert len(changed)==len(original)
    changed_offsets={i for i,(x,y) in enumerate(zip(original,changed)) if x!=y}
    assert all(any(r['offset']<=i<r['offset']+len(r['before'])+1 for r in regions) for i in changed_offsets)
    output=a.output_dir/f'libhidlbase{bits}.so'
    output.write_bytes(changed)
    records[lib]=dict(source_sha256=expected,sha256=hashlib.sha256(changed).hexdigest(),regions=regions,
        original_file_size_preserved=True,only_readonly_literals_changed=True,
        code_addresses_symbols_relocations_and_unwind_unchanged=True)
(a.output_dir/'hidl-paths-build.json').write_text(json.dumps(records,indent=2)+'\n')
print(json.dumps(records,indent=2))
