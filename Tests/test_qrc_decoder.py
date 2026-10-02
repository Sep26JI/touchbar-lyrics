"""QQ QRC compatibility vectors contain synthetic text, never song lyrics."""
import sys
import unittest
import zlib
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Resources'))
from qrc_decoder import decrypt_qrc


class QRCDecoderTests(unittest.TestCase):
    # Generated with the original WXRIW/QQMusicDecoder DESHelper algorithms,
    # independently compiled as C, using zlib + zero padding and ENCRYPT mode.
    # The expected value and ciphertext are fixed; no decoder code produces
    # either at test time. This exercises QQ's byte order, key schedule, changed
    # S-box values, the three DES stages, and UTF-8/decompression together.
    SYNTHETIC_QRC = (
        '[0,2400]节(0,200)奏(1000,1200)\n'
        '[4000,1600]hola(4000,100) mundo(4200,1300)'
    )
    CIPHER = (
        '43b95f530d24510b3e0f3d4b21ad49b8a52ff723f81901c3516dce43c26db534'
        '346059b8cbb8ea1b3ca941a079974566054b19403220768a305861c196033e02'
        'ee737b326feea60f'
    )

    def test_fixed_independent_qq_cipher_vector(self):
        self.assertEqual(decrypt_qrc(self.CIPHER), self.SYNTHETIC_QRC)

    def test_uppercase_hex_and_transport_whitespace(self):
        spaced = '\n'.join(self.CIPHER[i:i + 16].upper()
                           for i in range(0, len(self.CIPHER), 16))
        self.assertEqual(decrypt_qrc(spaced), self.SYNTHETIC_QRC)

    def test_malformed_ciphertext_returns_empty(self):
        for value in [None, 1, [], b'12345678', '', 'GG', '0', '00',
                      '00010203040506', '000102030405060708']:
            with self.subTest(value=value):
                self.assertEqual(decrypt_qrc(value), '')

    def test_ciphertext_size_limit_is_checked_before_decryption(self):
        with patch('qrc_decoder._crypt') as crypt:
            self.assertEqual(decrypt_qrc('00' * 1_000_001), '')
            crypt.assert_not_called()

    def test_valid_hex_that_decrypts_to_invalid_zlib_returns_empty(self):
        # Independently encrypted 8-byte plaintext b'not-zlib'.
        self.assertEqual(decrypt_qrc('f77f08554317bc5b'), '')

    def test_corrupt_compressed_checksum_returns_empty(self):
        # A valid encrypted block followed by corrupt encrypted data cannot
        # yield partially decoded lyric text.
        damaged = self.CIPHER[:-16] + '0000000000000000'
        self.assertEqual(decrypt_qrc(damaged), '')

    def test_incomplete_compressed_stream_returns_empty(self):
        # Independently encrypted zlib stream with its checksum removed.
        self.assertEqual(decrypt_qrc(
            'ea83624029814b3fe8c28922f4b7a96741d14a4ef0e934a8'), '')

    def test_invalid_utf8_plaintext_returns_empty(self):
        # Independently encrypted zlib.compress(b'\xff\xfe') + zero padding.
        self.assertEqual(decrypt_qrc(
            'e8cbe1211622d999e3a86d4098b9baec'), '')

    def test_compressed_output_size_limit(self):
        # Isolate decompression bounds by making the block transform a pass
        # through. Keeping the cryptographic known-vector test independent
        # avoids a circular encrypt/decrypt test.
        for size in [2_000_000, 2_000_001]:
            compressed = zlib.compress(b'x' * size)
            padded = compressed + b'\0' * (-len(compressed) % 8)
            with self.subTest(size=size), patch(
                    'qrc_decoder._crypt', side_effect=lambda block, keys: block):
                result = decrypt_qrc(padded.hex())
                self.assertEqual(len(result), size if size == 2_000_000 else 0)


if __name__ == '__main__':
    unittest.main()
