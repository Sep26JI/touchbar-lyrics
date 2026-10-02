"""QQ's QRC 3DES variant, ported from WXRIW/QQMusicDecoder (MIT).

Original: https://github.com/WXRIW/QQMusicDecoder/blob/master/QQMusicDecoder/DESHelper.cs
Copyright (c) 2023 WXRIW. See QQMusicDecoder-LICENSE.txt distributed alongside it.

QQ reverses bytes within each 32-bit word and uses a different key permutation
and two S-box values. A standard DES/3DES library does not decode this format.
This implementation uses only Python's standard library.
"""
import zlib

_KEY = b'!@#)(*$%123ZXC!@!@#)(NHL'
_IP = (57,49,41,33,25,17,9,1,59,51,43,35,27,19,11,3,
       61,53,45,37,29,21,13,5,63,55,47,39,31,23,15,7,
       56,48,40,32,24,16,8,0,58,50,42,34,26,18,10,2,
       60,52,44,36,28,20,12,4,62,54,46,38,30,22,14,6)
_FP = tuple(_IP.index(i) for i in range(64))
_E = (31,0,1,2,3,4,3,4,5,6,7,8,7,8,9,10,11,12,
      11,12,13,14,15,16,15,16,17,18,19,20,19,20,21,22,23,24,
      23,24,25,26,27,28,27,28,29,30,31,0)
_P = (15,6,19,20,28,11,27,16,0,14,22,25,4,17,30,9,
      1,7,23,13,31,26,2,8,18,12,29,5,21,10,3,24)
_PC1 = (56,48,40,32,24,16,8,0,57,49,41,33,25,17,9,1,
        58,50,42,34,26,18,10,2,59,51,43,35,
        62,54,46,38,30,22,14,6,61,53,45,37,29,21,
        13,5,60,52,44,36,28,20,12,4,27,19,11,3)
_PC2 = (13,16,10,23,0,4,2,27,14,5,20,9,22,18,11,3,25,7,15,6,26,19,12,1,
        40,51,30,36,46,54,29,39,50,44,32,47,43,48,38,55,33,52,45,41,49,35,28,31)
_SHIFTS = (1,1,2,2,2,2,2,2,1,2,2,2,2,2,2,1)
_SBOX = (
 (14,4,13,1,2,15,11,8,3,10,6,12,5,9,0,7,0,15,7,4,14,2,13,1,10,6,12,11,9,5,3,8,4,1,14,8,13,6,2,11,15,12,9,7,3,10,5,0,15,12,8,2,4,9,1,7,5,11,3,14,10,0,6,13),
 (15,1,8,14,6,11,3,4,9,7,2,13,12,0,5,10,3,13,4,7,15,2,8,15,12,0,1,10,6,9,11,5,0,14,7,11,10,4,13,1,5,8,12,6,9,3,2,15,13,8,10,1,3,15,4,2,11,6,7,12,0,5,14,9),
 (10,0,9,14,6,3,15,5,1,13,12,7,11,4,2,8,13,7,0,9,3,4,6,10,2,8,5,14,12,11,15,1,13,6,4,9,8,15,3,0,11,1,2,12,5,10,14,7,1,10,13,0,6,9,8,7,4,15,14,3,11,5,2,12),
 (7,13,14,3,0,6,9,10,1,2,8,5,11,12,4,15,13,8,11,5,6,15,0,3,4,7,2,12,1,10,14,9,10,6,9,0,12,11,7,13,15,1,3,14,5,2,8,4,3,15,0,6,10,10,13,8,9,4,5,11,12,7,2,14),
 (2,12,4,1,7,10,11,6,8,5,3,15,13,0,14,9,14,11,2,12,4,7,13,1,5,0,15,10,3,9,8,6,4,2,1,11,10,13,7,8,15,9,12,5,6,3,0,14,11,8,12,7,1,14,2,13,6,15,0,9,10,4,5,3),
 (12,1,10,15,9,2,6,8,0,13,3,4,14,7,5,11,10,15,4,2,7,12,9,5,6,1,13,14,0,11,3,8,9,14,15,5,2,8,12,3,7,0,4,10,1,13,11,6,4,3,2,12,9,5,15,10,11,14,1,7,6,0,8,13),
 (4,11,2,14,15,0,8,13,3,12,9,7,5,10,6,1,13,0,11,7,4,9,1,10,14,3,5,12,2,15,8,6,1,4,11,13,12,3,7,14,10,15,6,8,0,5,9,2,6,11,13,8,1,4,10,7,9,5,0,15,14,2,3,12),
 (13,2,8,4,6,15,11,1,10,9,3,14,5,0,12,7,1,15,13,8,10,3,7,4,12,5,6,11,0,14,9,2,7,11,4,1,9,12,14,2,0,6,10,13,15,3,5,8,2,1,14,7,4,10,8,13,15,12,9,0,3,5,6,11))


def _permute(value, positions, bits):
    result = 0
    for position in positions:
        result = (result << 1) | ((value >> (bits - 1 - position)) & 1)
    return result


def _byte_tables(positions, bits):
    return tuple(tuple(_permute(v << (bits - 8 - 8 * i), positions, bits)
                       for v in range(256)) for i in range(bits // 8))


_IP_TABLE = _byte_tables(_IP, 64)
_FP_TABLE = _byte_tables(_FP, 64)
_E_TABLE = _byte_tables(_E, 32)
_SP = tuple(tuple(_permute(box[(v & 32) | ((v & 31) >> 1) | ((v & 1) << 4)]
                                    << (28 - 4 * i), _P, 32) for v in range(64))
            for i, box in enumerate(_SBOX))


def _scheduled_keys(key):
    # BITNUM in the original implementation treats each 4-byte word as little endian.
    value = (int.from_bytes(key[:4], 'little') << 32) | int.from_bytes(key[4:], 'little')
    c_and_d = _permute(value, _PC1, 64)
    c, d = c_and_d >> 28, c_and_d & 0xfffffff
    keys = []
    for shift in _SHIFTS:
        c = ((c << shift) | (c >> (28 - shift))) & 0xfffffff
        d = ((d << shift) | (d >> (28 - shift))) & 0xfffffff
        # Preserve QQ's D half index (minus 27, rather than standard minus 28).
        round_key = 0
        for index in _PC2[:24]:
            round_key = (round_key << 1) | ((c >> (27 - index)) & 1)
        for index in _PC2[24:]:
            round_key = (round_key << 1) | (((d << 4) >> (31 - (index - 27))) & 1)
        keys.append(round_key)
    return keys


def _crypt(block, keys):
    data = block[3::-1] + block[7:3:-1]
    value = 0
    for i, byte in enumerate(data):
        value |= _IP_TABLE[i][byte]
    left, right = value >> 32, value & 0xffffffff
    for round_key in keys:
        expanded = (_E_TABLE[0][right >> 24] | _E_TABLE[1][(right >> 16) & 255]
                    | _E_TABLE[2][(right >> 8) & 255] | _E_TABLE[3][right & 255]) ^ round_key
        f = (_SP[0][(expanded >> 42) & 63] | _SP[1][(expanded >> 36) & 63]
             | _SP[2][(expanded >> 30) & 63] | _SP[3][(expanded >> 24) & 63]
             | _SP[4][(expanded >> 18) & 63] | _SP[5][(expanded >> 12) & 63]
             | _SP[6][(expanded >> 6) & 63] | _SP[7][expanded & 63])
        left, right = right, left ^ f
    swapped = ((right << 32) | left).to_bytes(8, 'big')
    value = 0
    for i, byte in enumerate(swapped):
        value |= _FP_TABLE[i][byte]
    return (value >> 32).to_bytes(4, 'little') + (value & 0xffffffff).to_bytes(4, 'little')


_KEYS = (tuple(reversed(_scheduled_keys(_KEY[16:]))),
         tuple(_scheduled_keys(_KEY[8:16])), tuple(reversed(_scheduled_keys(_KEY[:8]))))


def decrypt_qrc(cipher_hex):
    """Decode bounded online QRC ciphertext; return empty text for invalid data."""
    try:
        if not isinstance(cipher_hex, str) or len(cipher_hex) > 2_000_000:
            return ''
        data = bytes.fromhex(cipher_hex)
        if not data or len(data) % 8:
            return ''
        decoded = bytearray()
        for i in range(0, len(data), 8):
            block = data[i:i + 8]
            for keys in _KEYS:
                block = _crypt(block, keys)
            decoded.extend(block)
        decompressor = zlib.decompressobj()
        plain = decompressor.decompress(decoded, 2_000_001)
        if len(plain) > 2_000_000 or not decompressor.eof:
            return ''
        return plain.decode('utf-8')
    except (ValueError, TypeError, UnicodeError, zlib.error, OverflowError):
        return ''
