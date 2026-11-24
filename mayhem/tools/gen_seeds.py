#!/usr/bin/env python3
"""Synthesize the seed/known-answer inputs for the PSF and unself targets.

Run once by hand (`python3 -I mayhem/tools/gen_seeds.py`); the outputs are committed, so the
build never runs this. The expected unself output is computed here independently of unself.cpp.
"""
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def psf(entries):
    """entries: list of (key, fmt, value bytes, max_len)"""
    keys = b''
    data = b''
    index = b''
    for key, fmt, value, max_len in entries:
        index += struct.pack('<HHIII', len(keys), fmt, len(value), max_len, len(data))
        keys += key.encode() + b'\0'
        data += value.ljust(max_len, b'\0')
    while len(keys) % 4:
        keys += b'\0'
    key_start = 20 + len(index)
    data_start = key_start + len(keys)
    hdr = struct.pack('<4sIIII', b'\0PSF', 0x101, key_start, data_start, len(entries))
    return hdr + index + keys + data


def write(path, blob):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, 'wb') as f:
        f.write(blob)


game = psf([
    ('APP_VER', 0x0204, b'01.00\0', 8),
    ('ATTRIBUTE', 0x0404, struct.pack('<I', 0x20), 4),
    ('CATEGORY', 0x0204, b'DG\0', 4),
    ('PARENTAL_LEVEL', 0x0404, struct.pack('<I', 3), 4),
    ('TITLE', 0x0204, b'Mayhem Test Game\0', 128),
    ('TITLE_ID', 0x0204, b'BLUS00001\0', 16),
    ('VERSION', 0x0204, b'01.00\0', 8),
])
save = psf([
    ('ACCOUNT_ID', 0x0004, b'0123456789abcdef', 16),
    ('CATEGORY', 0x0204, b'SD\0', 4),
    ('DETAIL', 0x0204, b'Chapter 2\0', 1024),
    ('SAVEDATA_DIRECTORY', 0x0204, b'BLUS00001-SAVE0\0', 64),
])
write('fuzz_psf/testsuite/game.sfo', game)
write('fuzz_psf/testsuite/save.sfo', save)
write('tests/psf/game.sfo', game)

# PS4 SELF: header, one segment table entry, ELF64 header + one phdr, segment payload.
payload = b'MAYHEM-UNSELF-PAYLOAD-0123456789'
seg_count = 1
elf_off = 0x20 + 0x20 * seg_count
phoff = 64
ehdr = bytearray(64)
ehdr[0:4] = b'\x7fELF'
ehdr[4] = 2  # ELFCLASS64
ehdr[5] = 1  # little endian
ehdr[6] = 1
struct.pack_into('<HHIQQQIHHHHHH', ehdr, 16, 2, 0x3e, 1, 0x400000, phoff, 0, 0, 64, 56, 1, 0, 0, 0)
p_offset = 0x100
phdr = struct.pack('<IIQQQQQQ', 1, 5, p_offset, 0x400000, 0x400000, len(payload), len(payload), 0x1000)
seg_data_off = elf_off + 64 + 56
seg_data_off = (seg_data_off + 15) & ~15
flags = 0x800 | (0 << 20)
segment = struct.pack('<QQQQ', flags, seg_data_off, len(payload), len(payload))
body = bytes(ehdr) + phdr
image = bytearray(struct.pack('<IIBBHHHIIHHI', 0x1D3D154F, 0x12010002, 1, 1, 0, 0x20, 0, 0, 0, seg_count, 0x22, 0))
image += segment + body
image += b'\0' * (seg_data_off - len(image)) + payload
write('unself/testsuite/sample.self', bytes(image))
write('tests/unself/sample.self', bytes(image))

expected = bytearray(p_offset + len(payload))
expected[0:64] = ehdr
expected[64:64 + 56] = phdr
expected[p_offset:] = payload
write('tests/unself/expected.elf', bytes(expected))

# PS3 PUP: SCEUF header, file table, hash table (HMAC-SHA1 with the public PUP_KEY from
# rpcs3/Crypto/key_vault.h), then the entry payloads.
import hashlib
import hmac
PUP_KEY = bytes([
    0xF4, 0x91, 0xAD, 0x94, 0xC6, 0x81, 0x10, 0x96, 0x91, 0x5F, 0xD5, 0xD2, 0x44, 0x81, 0xAE, 0xDC, 0xED, 0xED, 0xBE, 0x6B,
    0xE5, 0x13, 0x72, 0x4D, 0xD8, 0xF7, 0xB6, 0x91, 0xE8, 0x8A, 0x38, 0xF4, 0xB5, 0x16, 0x2B, 0xFB, 0xEC, 0xBE, 0x3A, 0x62,
    0x18, 0x5D, 0xD7, 0xC9, 0x4D, 0xA2, 0x22, 0x5A, 0xDA, 0x3F, 0xBF, 0xCE, 0x55, 0x5B, 0x9E, 0xA9, 0x64, 0x98, 0x29, 0xEB,
    0x30, 0xCE, 0x83, 0x66])


def pup(files, tamper=False):
    n = len(files)
    header_length = 0x30 + 0x20 * n + 0x20 * n
    ftab = b''
    htab = b''
    data = b''
    for entry_id, payload in files:
        ftab += struct.pack('>QQQ', entry_id, header_length + len(data), len(payload)) + b'\0' * 8
        digest = hmac.new(PUP_KEY, payload, hashlib.sha1).digest()
        if tamper:
            digest = bytes([digest[0] ^ 1]) + digest[1:]
        htab += struct.pack('>Q', entry_id) + digest + b'\0' * 4
        data += payload
    hdr = b'SCEUF\0\0\0' + struct.pack('>QQQQQ', 1, 0x10000, n, header_length, len(data))
    return hdr + ftab + htab + data


fw = [(0x100, b'4.91\n'), (0x101, b'license'), (0x300, b'update_files.tar placeholder')]
write('fuzz_pup/testsuite/fw.pup', pup(fw))
write('tests/pup/fw.pup', pup(fw))
write('tests/pup/tampered.pup', pup(fw, tamper=True))


# Small ISO9660 seeds for fuzz_iso. iso_dev reads the volume descriptors from sector 16 on, so an
# image needs at least 17 sectors (34 KB) before the parser does anything; these hand-built images
# are 16 empty sectors + PVD (+ Joliet SVD) + terminator + directory/file sectors (~44-50 KB), so
# mutations land on the descriptors and directory records rather than on file data.
SECTOR = 2048


def both32(v):
    return struct.pack('<I', v) + struct.pack('>I', v)


def both16(v):
    return struct.pack('<H', v) + struct.pack('>H', v)


def dirent(name, lba, size, is_dir):
    rec = (bytes([0, 0]) + both32(lba) + both32(size) + bytes([124, 1, 2, 3, 4, 5, 0])
           + bytes([2 if is_dir else 0, 0, 0]) + both16(1) + bytes([len(name)]) + name)
    if len(rec) % 2:
        rec += b'\0'
    return bytes([len(rec)]) + rec[1:]


def vd(vtype, root, total, escape=b''):
    d = bytearray(SECTOR)
    d[0:7] = bytes([vtype]) + b'CD001\x01'
    d[8:40] = b'MAYHEM'.ljust(32)
    d[40:72] = b'RPCSX_SEED'.ljust(32)
    d[80:88] = both32(total)
    d[88:88 + len(escape)] = escape
    d[120:124] = both16(1)
    d[124:128] = both16(1)
    d[128:132] = both16(SECTOR)
    d[156:156 + len(root)] = root
    d[881] = 1
    return bytes(d)


def iso(tree, joliet):
    """tree: {name: bytes | dict}; returns an image with one directory or file per sector."""
    enc = (lambda n: n.encode('utf-16-be')) if joliet else (lambda n: n.encode())
    sectors = {}
    nxt = [19]

    def place(node):
        lba = nxt[0]
        if isinstance(node, dict):
            nxt[0] += 1
            kids = [(k, place(v)) for k, v in sorted(node.items())]
            body = b''
            for k, (klba, ksize, kdir) in kids:
                body += dirent(enc(k) if kdir else enc(k + ';1'), klba, ksize, kdir)
            sectors[lba] = (dirent(b'\0', lba, SECTOR, True) + dirent(b'\1', lba, SECTOR, True) + body).ljust(SECTOR, b'\0')
            return lba, SECTOR, True
        n = max(1, (len(node) + SECTOR - 1) // SECTOR)
        nxt[0] += n
        sectors[lba] = node.ljust(n * SECTOR, b'\0')
        return lba, len(node), False

    root_lba, _, _ = place(tree)
    total = nxt[0]
    root = dirent(b'\0', root_lba, SECTOR, True)
    img = bytearray(b'\0' * (16 * SECTOR))
    img += vd(1, root, total)
    if joliet:
        img += vd(2, root, total, escape=b'%/E')
    img += bytes([255]) + b'CD001\x01' + b'\0' * (SECTOR - 7)
    img = img.ljust(19 * SECTOR, b'\0')
    for lba in sorted(sectors):
        img = img.ljust(lba * SECTOR, b'\0') + sectors[lba]
    return bytes(img)


ps3 = {'PS3_DISC.SFB': b'PS3LICDA', 'PS3_GAME': {'PARAM.SFO': game, 'USRDIR': {'EBOOT.BIN': b'hello eboot\n'}}}
write('fuzz_iso/testsuite/small_plain.iso', iso(ps3, joliet=False))
write('fuzz_iso/testsuite/small_joliet.iso', iso(ps3, joliet=True))
# iso_dev skips a record whose name length is odd and has no pad byte (filename_end rounds up), so
# EBOOT.BIN;1 is invisible in the plain images; this one uses even-length names so the plain walk
# reaches file reads.
write('fuzz_iso/testsuite/min_root.iso', iso({'README.TXT': b'readme\n', 'DIR1': {'DATA.BIN': b'\x01' * 3000}}, joliet=False))
