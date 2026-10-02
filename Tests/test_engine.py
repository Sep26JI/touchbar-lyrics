import sys, unittest, tempfile, json, time
from unittest.mock import patch
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Resources'))
import lyrics_engine as engine
from lyrics_engine import parse_lrc, parse_qrc, compatible, key, atomic_write, filter_track_headers, lookup


class EngineTests(unittest.TestCase):
    def test_multi_stamp_and_blank_break(self):
        self.assertEqual(parse_lrc('[00:10.5][01:12.05]一句\n[00:15.00]\n[00:00.10]作词：作者'), [{'time': .1, 'text': ''}, {'time': 10.5, 'text': '一句'}, {'time': 15, 'text': ''}, {'time': 72.05, 'text': '一句'}])

    def test_offset_advances_positive(self):
        self.assertEqual(parse_lrc('[offset:500]\n[00:10.00]歌词')[0]['time'], 9.5)

    def test_html_and_word_tags(self):
        self.assertEqual(parse_lrc('[00:10.00]A &amp; B <00:10.50>test')[0]['text'], 'A & B test')

    def test_versions_and_artists_are_not_interchangeable(self):
        self.assertFalse(compatible('龙卷风 (Live)', '邓紫棋', 271, '龙卷风', '邓紫棋', 271))
        self.assertFalse(compatible('龙卷风', '邓紫棋', 271, '龙卷风', '周杰伦', 271))
        self.assertFalse(compatible('龙卷风', '邓紫棋', 271, '龙卷风', '邓紫棋', 220))
        self.assertTrue(compatible('龙卷风（Live）', 'G.E.M.邓紫棋', 271, '龙卷风 (Live)', 'G.E.M. 邓紫棋', 272))

    def test_album_language_versions_must_match(self):
        self.assertFalse(compatible('Hell', 'G.E.M.邓紫棋', 247, 'Hell', 'G.E.M.邓紫棋', 247, 'Revelación', '启示录'))
        self.assertFalse(compatible('Hell', 'G.E.M.邓紫棋', 247, 'Hell', 'G.E.M.邓紫棋', 247, 'Revelación', ''))
        self.assertTrue(compatible('Hell', 'G.E.M.邓紫棋', 247, 'Hell', 'G.E.M.邓紫棋', 247, 'Revelación', 'Revelacio\u0301n'))

    def test_album_cache_identity(self):
        self.assertNotEqual(key('歌', '歌手', '专辑一'), key('歌', '歌手', '专辑二'))

    def test_atomic_write_replaces_complete_file(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'a.json'
            atomic_write(p, 'old')
            atomic_write(p, 'new')
            self.assertEqual(p.read_text(), 'new')
            self.assertEqual(len(list(Path(d).iterdir())), 1)

    def test_opening_title_artist_header_is_not_a_lyric(self):
        for header in ['情人 (Live) - G.E.M. 邓紫棋', '情人（Live）—邓紫棋', '情人 / 邓紫棋', 'G.E.M.邓紫棋 – 情人 (Live)']:
            rows = parse_lrc('[00:00.00]' + header + '\n[00:01.00]作曲：作者\n[00:10.00]测试正文')
            result = filter_track_headers(rows, '情人 (Live)', 'G.E.M.邓紫棋')
            self.assertEqual([r['text'] for r in result], ['', '', '测试正文'])
            self.assertEqual(result[0]['time'], 0)

    def test_preserves_title_only_and_later_real_lyrics(self):
        rows = parse_lrc('[00:00.00]龙卷风 - 周杰伦\n[00:10.00]龙卷风\n[00:20.00]龙卷风 - 周杰伦')
        self.assertEqual([r['text'] for r in filter_track_headers(rows, '龙卷风', '周杰伦')], ['', '龙卷风', '龙卷风 - 周杰伦'])
        other = parse_lrc('[00:00.00]龙卷风 - 邓紫棋')
        self.assertEqual(filter_track_headers(other, '龙卷风', '周杰伦'), other)

    def test_qrc_has_nonuniform_real_word_times(self):
        rows = parse_qrc('[10000,5000]我(10000,200)爱(10400,1500)你(12300,2700)')
        self.assertEqual(rows, [{'time': 10, 'text': '我爱你', 'end': 15,
                               'words': [{'time': 10, 'duration': .2, 'text': '我'},
                                         {'time': 10.4, 'duration': 1.5, 'text': '爱'},
                                         {'time': 12.3, 'duration': 2.7, 'text': '你'}]}])

    def test_qrc_whitespace_extends_held_word_and_preserves_spacing(self):
        row = parse_qrc('[1000,3000]Love(1000,100) (1100,1400)you(2700,1300)')[0]
        self.assertEqual(row['text'], 'Love you')
        self.assertEqual(row['words'][0], {'time': 1, 'duration': 1.5, 'text': 'Love '})
        self.assertEqual(''.join(w['text'] for w in row['words']), row['text'])
        tail = parse_qrc('[1000,4000]啊(1000,100) (1100,3900)')[0]
        self.assertEqual(tail['text'], '啊')
        self.assertEqual(tail['words'][0]['duration'], 4)

    def test_qrc_quotes_parentheses_and_multiple_xml_tracks(self):
        xml = '<QrcInfos><Lyric_1 LyricType="1" LyricContent="[1000,1000]Say "hi"(1000,500) (&amp;)(1500,500)"/>\n<Lyric_2 LyricContent="[1000,1000]译文(1000,1000)"/></QrcInfos>'
        rows = parse_qrc(xml)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['text'], 'Say "hi" (&)')
        self.assertEqual(''.join(w['text'] for w in rows[0]['words']), rows[0]['text'])

    def test_qrc_headers_and_credits_clear_word_highlights(self):
        rows = parse_qrc('[0,500]情人 - 邓紫棋(0,500)\n[1000,1000]Composed by：作者(1000,1000)\n[10000,1000]正文(10000,1000)')
        rows = filter_track_headers(rows, '情人', '邓紫棋')
        self.assertEqual([r['text'] for r in rows], ['', '', '正文'])
        self.assertNotIn('words', rows[0])
        self.assertNotIn('words', rows[1])
        self.assertIn('words', rows[2])

    def test_english_spanish_credits_and_copyright_never_become_lyrics(self):
        metadata = ['Music & Lyrics：G.E.M.邓紫棋', 'Music and Lyrics: G.E.M.',
                    'Música y letra: G.E.M.', 'Letra：G.E.M.',
                    '版权所有，翻版必究。本专辑涉及的任何作品，未经权利人授权不得使用。',
                    'Copyright 2026 All rights reserved.', '版權所有，翻版必究。']
        for text in metadata:
            with self.subTest(text=text):
                self.assertEqual(parse_lrc('[00:04.00]' + text)[0]['text'], '')
                row = parse_qrc('[4000,1000]' + text + '(4000,1000)')[0]
                self.assertEqual(row['text'], '')
                self.assertNotIn('words', row)
                # A cache created before this filter is cleaned on every read.
                stale = [{'time': 4, 'text': text, 'words': [{'time': 4, 'duration': 1, 'text': text}]}]
                cleaned = filter_track_headers(stale, 'Hell', 'G.E.M.邓紫棋')[0]
                self.assertEqual(cleaned['text'], '')
                self.assertNotIn('words', cleaned)
        self.assertEqual(parse_lrc('[00:01.00]Music is my life')[0]['text'], 'Music is my life')

    def test_search_uses_client_endpoint_and_numeric_id_with_exact_album(self):
        songs = [
            {'id': 1, 'mid': 'wrong', 'title': 'Hell', 'singer': [{'name': 'G.E.M.邓紫棋'}], 'album': {'name': '启示录'}, 'interval': 247},
            {'id': 417357352, 'mid': '003NtxvN3nFxT2', 'title': 'Hell', 'singer': [{'name': 'G.E.M.邓紫棋'}], 'album': {'name': 'Revelacio\u0301n'}, 'interval': 247}]
        with patch('lyrics_engine.request', return_value={'code': 0, 'data': {'song': {'list': songs}}}) as request:
            matched = engine._qq_search('Hell', 'G.E.M.邓紫棋', 'Revelación', 247)
        self.assertEqual(len(matched), 1)
        self.assertEqual(matched[0]['id'], 417357352)
        self.assertIn('client_search_cp', request.call_args[0][0])
        self.assertIn('new_json=1', request.call_args[0][0])

    def test_qrc_api_uses_anonymous_session_and_current_song_id(self):
        track = {'id': 417357352, 'mid': 'mid', 'title': 'Hell', 'artist': 'G.E.M.邓紫棋', 'album': 'Revelación', 'duration': 247}
        responses = [{'session': {'uid': '0', 'sid': 'anonymous', 'userip': '127.0.0.1'}}, {'qrc_t': 1, 'lyric': 'cipher'}]
        with patch('lyrics_engine.qq_post', side_effect=responses) as post, patch('lyrics_engine.decrypt_qrc', return_value='[1000,2000]test(1000,2000)'):
            rows = engine.qq_word_rows(track)
        self.assertEqual(len(rows), 1)
        method, module, params, comm = post.call_args[0]
        self.assertEqual(method, 'GetPlayLyricInfo')
        self.assertEqual(module, 'music.musichallSong.PlayLyricInfo')
        self.assertEqual(params['songID'], 417357352)
        self.assertEqual(params['qrc'], 1)
        self.assertEqual(comm['sid'], 'anonymous')

    def test_qq_word_rows_are_preferred_to_line_only(self):
        track = {'id': 1, 'mid': 'mid', 'title': 'song', 'artist': 'artist', 'album': 'album', 'duration': 20}
        rows = parse_qrc('[1000,1000]word(1000,1000)')
        with patch('lyrics_engine._qq_search', return_value=[track]), patch('lyrics_engine.qq_word_rows', return_value=rows), patch('lyrics_engine.request', side_effect=AssertionError('word result should return immediately')):
            result = engine.fetch('song', 'artist', 'album', 20)
        self.assertEqual(result['entries'], rows)
        self.assertEqual(result['source'], 'QQ音乐 · 逐字时间')
        self.assertEqual(result['track'], track)

    def test_unavailable_qrc_keeps_only_matched_qq_lines(self):
        track = {'id': 1, 'mid': 'mid', 'title': 'song', 'artist': 'artist', 'album': 'album', 'duration': 20}
        with patch('lyrics_engine._qq_search', return_value=[track]), patch('lyrics_engine.qq_word_rows', return_value=[]), patch('lyrics_engine.request', return_value={'lyric': '[00:01]line'}):
            result = engine.fetch('song', 'artist', 'album', 20)
        self.assertEqual(result['source'], 'QQ音乐')
        self.assertEqual(result['entries'][0]['text'], 'line')
        self.assertNotIn('words', result['entries'][0])

    def test_all_fallback_sources_reject_wrong_album(self):
        wrong_song = {'id': 2, 'name': 'Hell', 'artists': [{'name': 'G.E.M.邓紫棋'}], 'album': {'name': '启示录'}, 'duration': 247000}
        wrong_lrclib = {'trackName': 'Hell', 'artistName': 'G.E.M.邓紫棋', 'albumName': '启示录', 'duration': 247, 'syncedLyrics': '[00:01]错误正文'}
        def request(url, referer=None):
            if 'api/search/get/web' in url:
                return {'result': {'songs': [wrong_song]}}
            if 'lrclib.net/api/get' in url:
                return wrong_lrclib
            if 'lrclib.net/api/search' in url:
                return [wrong_lrclib]
            raise AssertionError('wrong album must not be fetched')
        with patch('lyrics_engine._qq_search', return_value=[]), patch('lyrics_engine.request', side_effect=request):
            self.assertEqual(engine.fetch('Hell', 'G.E.M.邓紫棋', 'Revelación', 247)['entries'], [])

    def test_verified_cache_and_import_filtered_without_network(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            cache, custom = root / 'cache', root / 'custom'
            title, artist, album = '情人', '邓紫棋', '专辑'
            ident = key(title, artist, album)
            rows = parse_lrc('[00:00.00]情人 - 邓紫棋\n[00:10.00]正文')
            saved = {'key': ident, 'schema': engine.SCHEMA, 'source': '缓存', 'entries': rows,
                     'track': {'title': title, 'artist': artist, 'album': album, 'duration': 100},
                     'retry_after': time.time() + 1000}
            atomic_write(cache / (ident + '.json'), json.dumps(saved))
            with patch('lyrics_engine.CACHE', cache), patch('lyrics_engine.CUSTOM', custom), patch('lyrics_engine.fetch', side_effect=AssertionError('should use local lyrics')):
                self.assertEqual(lookup(title, artist, album, 100)['entries'][0]['text'], '')
                atomic_write(custom / (ident + '.lrc'), '[00:00.00]情人 - 邓紫棋\n[00:10.00]导入正文')
                result = lookup(title, artist, album, 100)
                self.assertEqual([r['text'] for r in result['entries']], ['', '导入正文'])

    def test_old_unverified_cache_is_requeried_not_kept_on_failure(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            cache, custom = root / 'cache', root / 'custom'
            title, artist, album = 'Test-only-track', 'TestArtist', 'ExactAlbum'
            ident = key(title, artist, album)
            saved = {'key': ident, 'source': 'QQ音乐', 'entries': [{'time': 1, 'text': 'wrong version'}]}
            atomic_write(cache / (ident + '.json'), json.dumps(saved))
            fresh = {'source': '暂无匹配歌词', 'entries': [], 'track': None}
            with patch('lyrics_engine.CACHE', cache), patch('lyrics_engine.CUSTOM', custom), patch('lyrics_engine.fetch', return_value=fresh) as fetch:
                result = lookup(title, artist, album, 100)
            fetch.assert_called_once_with(title, artist, album, 100)
            self.assertEqual(result['entries'], [])
            self.assertEqual(result['schema'], engine.SCHEMA)

    def test_line_cache_is_upgraded_once_then_word_cache_is_immediate(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            cache, custom = root / 'cache', root / 'custom'
            title, artist, album = 'Test-only-track', 'TestArtist', 'ExactAlbum'
            ident = key(title, artist, album)
            track = {'title': title, 'artist': artist, 'album': album, 'duration': 100}
            saved = {'key': ident, 'schema': engine.SCHEMA, 'source': 'QQ音乐', 'entries': [{'time': 1, 'text': 'word'}], 'track': track, 'retry_after': 0}
            atomic_write(cache / (ident + '.json'), json.dumps(saved))
            fresh = {'source': 'QQ音乐 · 逐字时间', 'entries': parse_qrc('[1000,1000]word(1000,1000)'), 'track': track}
            with patch('lyrics_engine.CACHE', cache), patch('lyrics_engine.CUSTOM', custom), patch('lyrics_engine.fetch', return_value=fresh) as fetch:
                first = lookup(title, artist, album, 100)
                second = lookup(title, artist, album, 100)
            self.assertEqual(fetch.call_count, 1)
            self.assertEqual(first['entries'], second['entries'])
            self.assertIn('words', second['entries'][0])

    def test_failed_word_upgrade_preserves_verified_album_cache_with_retry(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            cache, custom = root / 'cache', root / 'custom'
            title, artist, album = 'Test-only-track', 'TestArtist', 'ExactAlbum'
            ident = key(title, artist, album)
            saved = {'key': ident, 'schema': engine.SCHEMA, 'source': 'QQ音乐', 'entries': [{'time': 1, 'text': 'verified line'}],
                     'track': {'title': title, 'artist': artist, 'album': album, 'duration': 100}, 'retry_after': 0}
            atomic_write(cache / (ident + '.json'), json.dumps(saved))
            with patch('lyrics_engine.CACHE', cache), patch('lyrics_engine.CUSTOM', custom), patch('lyrics_engine.fetch', return_value={'source': '暂无匹配歌词', 'entries': [], 'track': None}) as fetch:
                result = lookup(title, artist, album, 100)
                again = lookup(title, artist, album, 100)
            self.assertEqual(fetch.call_count, 1)
            self.assertEqual(result['entries'][0]['text'], 'verified line')
            self.assertEqual(again['entries'], result['entries'])
            self.assertGreater(result['retry_after'], time.time() + 23 * 60 * 60)

    def test_request_timeout_obeys_overall_deadline(self):
        with patch('lyrics_engine._deadline', time.monotonic() - 1):
            with self.assertRaises(TimeoutError):
                engine._timeout()
        with patch('lyrics_engine._deadline', time.monotonic() + .1):
            self.assertLessEqual(engine._timeout(), .1)


if __name__ == '__main__':
    unittest.main()
