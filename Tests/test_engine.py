import sys, unittest, tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Resources'))
from lyrics_engine import parse_lrc,compatible,key,atomic_write

class EngineTests(unittest.TestCase):
    def test_multi_stamp_and_blank_break(self):
        self.assertEqual(parse_lrc('[00:10.5][01:12.05]一句\n[00:15.00]\n[00:00.10]作词：作者'),[{'time':.1,'text':''},{'time':10.5,'text':'一句'},{'time':15,'text':''},{'time':72.05,'text':'一句'}])
    def test_offset_advances_positive(self):
        self.assertEqual(parse_lrc('[offset:500]\n[00:10.00]歌词')[0]['time'],9.5)
    def test_html_and_word_tags(self):
        self.assertEqual(parse_lrc('[00:10.00]A &amp; B <00:10.50>test')[0]['text'],'A & B test')
    def test_versions_and_artists_are_not_interchangeable(self):
        self.assertFalse(compatible('龙卷风 (Live)','邓紫棋',271,'龙卷风','邓紫棋',271))
        self.assertFalse(compatible('龙卷风','邓紫棋',271,'龙卷风','周杰伦',271))
        self.assertFalse(compatible('龙卷风','邓紫棋',271,'龙卷风','邓紫棋',220))
        self.assertTrue(compatible('龙卷风（Live）','G.E.M.邓紫棋',271,'龙卷风 (Live)','G.E.M. 邓紫棋',272))
    def test_album_cache_identity(self):
        self.assertNotEqual(key('歌','歌手','专辑一'),key('歌','歌手','专辑二'))
    def test_atomic_write_replaces_complete_file(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'a.json';atomic_write(p,'old');atomic_write(p,'new')
            self.assertEqual(p.read_text(),'new'); self.assertEqual(len(list(Path(d).iterdir())),1)
if __name__=='__main__': unittest.main()
