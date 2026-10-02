#!/usr/bin/env python3
"""Bounded lyric lookup. The native app owns the playback clock and rendering."""
import argparse, base64, hashlib, html, json, os, re, tempfile, time, unicodedata
from pathlib import Path
from urllib.parse import urlencode
import urllib.request
from qrc_decoder import decrypt_qrc

CACHE = Path.home() / 'Library/Caches/TouchBarLyrics/lyrics'
CUSTOM = Path.home() / 'Library/Application Support/TouchBarLyrics/lyrics'
SCHEMA = 3
WORD_RETRY_SECONDS = 24 * 60 * 60
_deadline = None
TS = re.compile(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]')
ROLE = re.compile(
    r'^(?:作词|作詞|作曲|词曲|詞曲|编曲|編曲|制作人|製作人|制作|製作|录音|錄音|混音|母带|母帶|监制|監製|和声|和聲|出品|发行|發行|OP|SP|词|詞|曲)'
    r'(?:[/／](?:作词|作詞|作曲|编曲|編曲|词|詞|曲))?\s*[:：]|'
    r'^(?:music\s*(?:&|and|/)\s*lyrics?|words\s*(?:&|and|/)\s*music|'
    r'music(?:\s+by)?|lyrics?(?:\s+by)?|composed\s+by|written\s+by|'
    r'produced\s+by|arranged\s+by|composer|lyricist|songwriter|producer|'
    r'música(?:\s+y\s+letra)?|letra(?:\s+y\s+música)?)\s*[:：]', re.I)
COPYRIGHT = re.compile(r'^(?:版权所有|版權所有|版权声明|版權聲明|Copyright\b|All rights reserved\b|©)', re.I)
QRC_LINE = re.compile(r'^\[(-?\d+),(\d+)\](.*)$')
QRC_WORD = re.compile(r'\((\d+),(\d+)\)')


def _metadata(text):
    text = text.strip()
    return text.startswith('[') or bool(ROLE.match(text) or COPYRIGHT.match(text))


def _timeout():
    remaining = _deadline - time.monotonic() if _deadline else 3
    if remaining <= 0:
        raise TimeoutError('lyric lookup deadline reached')
    return min(3, remaining)


def http_get(url, referer=None):
    req = urllib.request.Request(url, headers={
        'User-Agent': 'Mozilla/5.0 TouchBarLyrics/4.6', 'Referer': referer or url})
    with urllib.request.urlopen(req, timeout=_timeout()) as response:
        return response.read(2_000_000).decode('utf-8', 'replace')


def request(url, referer=None):
    return json.loads(http_get(url, referer))


def key(title, artist, album):
    return hashlib.sha256(json.dumps([title, artist, album], ensure_ascii=False).encode()).hexdigest()[:24]


def parse_lrc(text):
    text = html.unescape(text or '')
    offset = re.search(r'\[offset:([+-]?\d+)\]', text, re.I)
    offset = int(offset[1]) / 1000 if offset else 0
    entries = {}
    for raw in text.splitlines():
        stamps = list(TS.finditer(raw))
        if not stamps:
            continue
        content = re.sub(r'<\d+:\d+(?:\.\d+)?>', '', raw[stamps[-1].end():]).strip()
        if _metadata(content):
            content = ''
        for stamp in stamps:
            t = int(stamp[1]) * 60 + int(stamp[2]) + float('0.' + (stamp[3] or '0')) - offset
            entries[t] = content
    return [{'time': t, 'text': entries[t]} for t in sorted(entries)]


def parse_qrc(text):
    """Parse QQ line/word milliseconds without distributing time evenly.

    QRC puts each word's timestamp after its text. Pure whitespace tokens can
    carry a held note; attach them to the preceding word, retaining its end.
    """
    if not text:
        return []
    if 'LyricContent="' in text:
        segment = text.split('LyricContent="', 1)[1]
        segment = segment.split('<Lyric_', 1)[0]
        end = segment.rfind('"')
        if end < 0:
            return []
        text = html.unescape(segment[:end])
    else:
        text = html.unescape(text)
    rows = []
    for raw in text.splitlines():
        line = QRC_LINE.match(raw.strip())
        if not line:
            continue
        start, length = int(line[1]) / 1000, int(line[2]) / 1000
        body = line[3]
        words, previous_end = [], 0
        for stamp in QRC_WORD.finditer(body):
            word_text = body[previous_end:stamp.start()]
            word_time, word_duration = int(stamp[1]) / 1000, int(stamp[2]) / 1000
            previous_end = stamp.end()
            if words and not word_text.strip():
                words[-1]['text'] += word_text
                words[-1]['duration'] = max(words[-1]['duration'], word_time + word_duration - words[-1]['time'])
            elif word_text:
                words.append({'time': word_time, 'duration': word_duration, 'text': word_text})
        tail = body[previous_end:]
        if tail and words:
            words[-1]['text'] += tail
        elif tail:
            words = []
        if words:
            words[0]['text'] = words[0]['text'].lstrip()
            words[-1]['text'] = words[-1]['text'].rstrip()
            words = [w for w in words if w['text']]
            content = ''.join(w['text'] for w in words)
        else:
            content = QRC_WORD.sub('', body).strip()
        row = {'time': start, 'text': content, 'end': start + length}
        if words and all(w['duration'] >= 0 for w in words) and all(
                b['time'] >= a['time'] for a, b in zip(words, words[1:])):
            row['words'] = words
            row['end'] = max(row['end'], max(w['time'] + w['duration'] for w in words))
        if _metadata(content):
            row['text'] = ''
            row.pop('words', None)
        rows.append(row)
    return sorted(rows, key=lambda row: row['time'])


def canonical(text):
    return re.sub(r'[^\w]', '', unicodedata.normalize('NFKC', text or '').casefold())


def filter_track_headers(entries, title, artist):
    """Blank opening title/artist metadata, retaining its timed boundary."""
    titles = {canonical(title), canonical(re.sub(
        r'\s*[（(](?:live|现场版|现场)[）)]\s*$', '', title, flags=re.I))}
    titles.discard('')
    singer = canonical(artist)
    opening, result = True, []
    for row in entries:
        text = row['text'].strip()
        header = False
        if opening and text and titles and singer:
            normalized = canonical(text)
            header = any(normalized in (t + singer, singer + t) for t in titles)
            for parts in [re.split(r'\s*[-–—]\s*', text, maxsplit=1),
                          re.split(r'\s*[\/／|｜]\s*', text, maxsplit=1)]:
                if len(parts) != 2:
                    continue
                for name, performer in [parts, parts[::-1]]:
                    candidate = canonical(performer)
                    if canonical(name) in titles and len(candidate) >= 2 and (candidate in singer or singer in candidate):
                        header = True
        metadata = _metadata(text)
        if text and not header and not metadata:
            opening = False
        cleaned = dict(row, text='' if header or metadata else row['text'])
        if header or metadata:
            cleaned.pop('words', None)
        result.append(cleaned)
    return result


def compatible(title, artist, duration, candidate_title, candidate_artist, candidate_duration,
               album='', candidate_album=''):
    # Match recording and album, rather than silently substituting another language/version.
    if canonical(title) != canonical(candidate_title):
        return False
    a, b = canonical(artist), canonical(candidate_artist)
    if not a or not b or not (a in b or b in a):
        return False
    if album and canonical(album) != canonical(candidate_album):
        return False
    if duration and candidate_duration and abs(duration - candidate_duration) > 5:
        return False
    return True


def _track_matches(track, title, artist, album, duration):
    return isinstance(track, dict) and compatible(
        title, artist, duration, track.get('title', ''), track.get('artist', ''),
        track.get('duration', 0), album, track.get('album', ''))


QQ_COMM = {'ct': 11, 'cv': '1003006', 'v': '1003006', 'os_ver': '15',
           'phonetype': '24122RKC7C',
           'rom': 'Redmi/miro/miro:15/AE3A.240806.005/OS2.0.105.0.VOMCNXM:user/release-keys',
           'tmeAppID': 'qqmusiclight', 'nettype': 'NETWORK_WIFI', 'udid': '0'}


def qq_post(method, module, param, comm):
    payload = json.dumps({'comm': comm, 'request': {
        'method': method, 'module': module, 'param': param}}).encode()
    last_error = None
    for host in ['u.y.qq.com', 'u6.y.qq.com', 'shu.y.qq.com']:
        try:
            req = urllib.request.Request('https://' + host + '/cgi-bin/musicu.fcg', data=payload,
                                         headers={'Content-Type': 'application/json',
                                                  'Cookie': 'tmeLoginType=-1;',
                                                  'User-Agent': 'okhttp/3.14.9'})
            with urllib.request.urlopen(req, timeout=_timeout()) as response:
                result = json.loads(response.read(2_000_000))
            answer = result.get('request') or {}
            if result.get('code') != 0 or answer.get('code') != 0:
                return {}
            return answer.get('data') or {}
        except (OSError, ValueError, TimeoutError) as error:
            last_error = error
    if last_error:
        raise last_error
    return {}


def qq_word_rows(song):
    session = qq_post('GetSession', 'music.getSession.session',
                      {'caller': 0, 'uid': '0', 'vkey': 0}, QQ_COMM).get('session') or {}
    if not session.get('sid'):
        return []
    comm = dict(QQ_COMM)
    for name in ['uid', 'sid', 'userip']:
        comm[name] = session.get(name, '')
    encode = lambda value: base64.b64encode(value.encode()).decode()
    result = qq_post('GetPlayLyricInfo', 'music.musichallSong.PlayLyricInfo', {
        'songID': song['id'], 'songName': encode(song['title']),
        'singerName': encode(song['artist']), 'albumName': encode(song['album']),
        'interval': int(song['duration']), 'crypt': 1, 'ct': 19, 'cv': 2111,
        'qrc': 1, 'qrc_t': 0, 'lrc_t': 0, 'roma': 0, 'roma_t': 0,
        'trans': 0, 'trans_t': 0, 'type': 0}, comm)
    if not result.get('lyric') or not (result.get('qrc_t') or result.get('lrc_t')):
        return []
    return parse_qrc(decrypt_qrc(result['lyric']))


def _qq_search(title, artist, album, duration):
    queries = [title + ' ' + artist]
    if album:
        queries.append(title + ' ' + artist + ' ' + album)
    for query in queries:
        data = None
        for host in ['shc.y.qq.com', 'c.y.qq.com']:
            try:
                data = request('https://' + host + '/soso/fcgi-bin/client_search_cp?' + urlencode({
                    'format': 'json', 'new_json': 1, 't': 0, 'aggr': 1, 'cr': 1,
                    'p': 1, 'n': 12, 'w': query}), 'https://y.qq.com/')
                if data.get('code') == 0:
                    break
            except (OSError, ValueError, TimeoutError):
                pass
        songs = (((data or {}).get('data') or {}).get('song') or {}).get('list') or []
        matches = []
        for song in songs:
            track = {'provider': 'QQ音乐', 'id': song.get('id'), 'mid': song.get('mid'),
                     'title': song.get('title', ''),
                     'artist': ' / '.join(s.get('name', '') for s in song.get('singer', [])),
                     'album': (song.get('album') or {}).get('name', ''),
                     'duration': song.get('interval', 0)}
            if track['id'] and track['mid'] and _track_matches(track, title, artist, album, duration):
                matches.append(track)
        if matches:
            return matches[:3]
    return []


def _usable(rows):
    return any(row.get('text', '').strip() for row in rows)


def fetch(title, artist, album, duration):
    """Return parsed rows and the verified identity of the selected recording."""
    qq_fallback = None
    try:
        for song in _qq_search(title, artist, album, duration):
            try:
                rows = filter_track_headers(qq_word_rows(song), title, artist)
                if _usable(rows) and any(row.get('words') for row in rows):
                    return {'source': 'QQ音乐 · 逐字时间', 'entries': rows, 'track': song}
            except (OSError, ValueError, TimeoutError):
                pass
            try:
                data = request('https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?' +
                               urlencode({'format': 'json', 'nobase64': 1, 'songmid': song['mid']}),
                               'https://y.qq.com/')
                rows = filter_track_headers(parse_lrc(data.get('lyric', '')), title, artist)
                if _usable(rows) and qq_fallback is None:
                    qq_fallback = {'source': 'QQ音乐', 'entries': rows, 'track': song}
            except (OSError, ValueError, TimeoutError):
                pass
        if qq_fallback:
            return qq_fallback
    except (OSError, ValueError, TimeoutError):
        if qq_fallback:
            return qq_fallback
    try:
        data = request('https://music.163.com/api/search/get/web?' +
                       urlencode({'s': title + ' ' + artist, 'type': 1, 'limit': 12}),
                       'https://music.163.com')
        for song in (data.get('result') or {}).get('songs') or []:
            track = {'provider': '网易云音乐', 'id': song.get('id'),
                     'title': song.get('name', ''),
                     'artist': ' / '.join(s.get('name', '') for s in song.get('artists', [])),
                     'album': (song.get('album') or {}).get('name', ''),
                     'duration': song.get('duration', 0) / 1000}
            if not _track_matches(track, title, artist, album, duration):
                continue
            data = request('https://music.163.com/api/song/lyric?' +
                           urlencode({'id': song['id'], 'lv': 1, 'kv': 1, 'tv': -1}),
                           'https://music.163.com')
            rows = filter_track_headers(parse_lrc((data.get('lrc') or {}).get('lyric', '')), title, artist)
            if _usable(rows):
                return {'source': '网易云音乐', 'entries': rows, 'track': track}
    except (OSError, ValueError, TimeoutError):
        pass
    try:
        data = request('https://lrclib.net/api/get?' + urlencode({
            'track_name': title, 'artist_name': artist, 'album_name': album,
            'duration': round(duration)}))
        candidates = [data]
    except (OSError, ValueError, TimeoutError):
        candidates = []
    try:
        candidates += request('https://lrclib.net/api/search?' + urlencode({'q': title + ' ' + artist}))
    except (OSError, ValueError, TimeoutError):
        pass
    for song in candidates:
        track = {'provider': 'LRCLIB', 'id': song.get('id'), 'title': song.get('trackName', ''),
                 'artist': song.get('artistName', ''), 'album': song.get('albumName', ''),
                 'duration': song.get('duration', 0)}
        if _track_matches(track, title, artist, album, duration):
            rows = filter_track_headers(parse_lrc(song.get('syncedLyrics', '')), title, artist)
            if _usable(rows):
                return {'source': 'LRCLIB', 'entries': rows, 'track': track}
    return {'source': '暂无匹配歌词', 'entries': [], 'track': None}


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix='.lyrics-')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.write(text)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def lookup(title, artist, album, duration):
    global _deadline
    _deadline = time.monotonic() + 30
    ident = key(title, artist, album)
    custom, cached = CUSTOM / (ident + '.lrc'), CACHE / (ident + '.json')
    def filtered(result):
        return dict(result, entries=filter_track_headers(result['entries'], title, artist))
    if custom.exists():
        return filtered({'key': ident, 'schema': SCHEMA, 'source': '本地 LRC',
                         'entries': parse_lrc(custom.read_text(encoding='utf-8-sig'))})
    saved = None
    if cached.exists():
        try:
            candidate = json.loads(cached.read_text())
            if candidate.get('schema') == SCHEMA and candidate.get('key') == ident:
                if _track_matches(candidate.get('track'), title, artist, album, duration):
                    saved = filtered(candidate)
                    if any(row.get('words') for row in saved['entries']) or saved.get('retry_after', 0) > time.time():
                        return saved
                elif not candidate.get('entries') and candidate.get('retry_after', 0) > time.time():
                    return filtered(candidate)
        except (ValueError, OSError, KeyError, TypeError):
            pass
    result = fetch(title, artist, album, duration)
    if not result['entries'] and saved:
        result = saved
    # Legacy line-only caches have no selected-album identity. Only trust an
    # explicit matching [al:] tag, or a request without an album, after lookup.
    if not result['entries']:
        legacy = Path.home() / 'Library/Caches/qqmusic-tb-lyrics' / (
            hashlib.sha1((title + '|' + artist).encode()).hexdigest()[:16] + '.lrc')
        if legacy.exists():
            text = legacy.read_text(encoding='utf-8-sig')
            album_tag = re.search(r'\[al:(.*?)\]', text, re.I)
            if not album or (album_tag and canonical(album_tag[1]) == canonical(album)):
                rows = filter_track_headers(parse_lrc(text), title, artist)
                if _usable(rows):
                    result = {'source': '原有歌词缓存', 'entries': rows,
                              'track': {'title': title, 'artist': artist, 'album': album,
                                        'duration': duration, 'provider': '原有歌词缓存'}}
    result = filtered(dict(result, key=ident, schema=SCHEMA, checked_at=time.time(),
                           retry_after=time.time() + (WORD_RETRY_SECONDS if result['entries'] else 300)))
    atomic_write(cached, json.dumps(result, ensure_ascii=False))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--title', required=True)
    parser.add_argument('--artist', default='')
    parser.add_argument('--album', default='')
    parser.add_argument('--duration', type=float, default=0)
    arguments = parser.parse_args()
    print(json.dumps(lookup(arguments.title, arguments.artist, arguments.album,
                            arguments.duration), ensure_ascii=False), flush=True)
