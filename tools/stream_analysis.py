#!/usr/bin/env python3
"""分析 InstallShield Suite 引导器 exe 尾部载荷流结构。

用法: python stream_analysis.py <S-NXSTDO-xxxx.exe>
输出: 明文文件名目录（UTF-16）、zlib/gzip 候选、LZMA 属性字节候选。
结论: 文件名是明文，文件内容被私有压缩，所以无法对 exe 做等长字节替换。
"""
import re, struct, sys, zlib

if len(sys.argv) < 2:
    print(__doc__)
    sys.exit(1)

PATH = sys.argv[1]
data = open(PATH, 'rb').read()
N = len(data)

# PE 段落表 → overlay 起点
pe = struct.unpack_from('<I', data, 0x3C)[0]
numsec = struct.unpack_from('<H', data, pe + 6)[0]
optsize = struct.unpack_from('<H', data, pe + 20)[0]
sh = pe + 24 + optsize
raw_end = 0
for i in range(numsec):
    o = sh + i * 40
    _, _, _, roff, rsize = struct.unpack_from('<IIII', data, o + 8)
    raw_end = max(raw_end, roff + rsize)
print(f"file {N:,} bytes; overlay starts 0x{raw_end:X} ({N-raw_end:,} bytes)")

print("\n[UTF-16 明文文件名目录]")
names = [(m.start(), m.group().decode('utf-16le'))
         for m in re.finditer(rb'(?:[\x20-\x7e]\x00){4,}', data[raw_end:])]
print(f"  total {len(names)}")
for off, s in names[:40]:
    print(f"  0x{raw_end+off:08X}  {s}")

print("\n[zlib/gzip 候选]")
for sig, kind in ((b'\x78\xda', 'zlib'), (b'\x78\x9c', 'zlib'), (b'\x1f\x8b\x08', 'gzip')):
    st, cnt = raw_end, 0
    while cnt < 10:
        i = data.find(sig, st)
        if i < 0:
            break
        st = i + 1
        try:
            d = zlib.decompressobj(16 + zlib.MAX_WBITS if kind == 'gzip' else zlib.MAX_WBITS)
            out = d.decompress(data[i:i + 3_000_000], 200_000)
            info = f"-> {len(out)} B"
        except Exception as e:
            info = f"fail {type(e).__name__}"
        print(f"  0x{i:08X} {kind} {info}")
        cnt += 1