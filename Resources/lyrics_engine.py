#!/usr/bin/env python3
"""Lyric lookup only. The native app owns the playback clock and rendering."""
import argparse, hashlib, html, json, os, re, tempfile, unicodedata
from pathlib import Path
import urllib.request

def http_get(url, referer=None):
    req=urllib.request.Request(url, headers={"User-Agent":"Mozilla/5.0 TouchBarLyrics/4.0", "Referer":referer or url})
    with urllib.request.urlopen(req,timeout=3) as response:
        return response.read(2_000_000).decode("utf-8", "replace")

CACHE = Path.home() / 'Library/Caches/TouchBarLyrics/lyrics'
CUSTOM = Path.home() / 'Library/Application Support/TouchBarLyrics/lyrics'
TS = re.compile(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]')
ROLE = re.compile(r'^(?:作词|作曲|词曲|编曲|制作人|制作|录音|混音|母带|监制|和声|出品|发行|OP|SP|词|曲)(?:[/／](?:作词|作曲|编曲|词|曲))?\s*[:：]')

def key(title, artist, album):
    return hashlib.sha256(json.dumps([title, artist, album], ensure_ascii=False).encode()).hexdigest()[:24]

def parse_lrc(text):
    text = html.unescape(text or '')
    offset = re.search(r'\[offset:([+-]?\d+)\]', text, re.I)
    offset = int(offset[1])/1000 if offset else 0
    entries = {}
    for raw in text.splitlines():
        stamps = list(TS.finditer(raw))
        if not stamps: continue
        content = re.sub(r'<\d+:\d+(?:\.\d+)?>', '', raw[stamps[-1].end():]).strip()
        if content.startswith('[') or ROLE.match(content): content = ''
        for stamp in stamps:
            t = int(stamp[1])*60 + int(stamp[2]) + float('0.'+(stamp[3] or '0')) - offset
            # Preserve blank lines: they end a lyric during instrumental breaks.
            entries[t] = content
    return [{'time': t, 'text': entries[t]} for t in sorted(entries)]

def canonical(text):
    return re.sub(r'[^\w]', '', unicodedata.normalize('NFKC', text).casefold())

def compatible(title, artist, duration, candidate_title, candidate_artist, candidate_duration):
    # Do not silently substitute studio/live/remastered recordings.
    if canonical(title) != canonical(candidate_title): return False
    a, b = canonical(artist), canonical(candidate_artist)
    if not a or not b or not (a in b or b in a): return False
    if duration and candidate_duration and abs(duration-candidate_duration)>5: return False
    return True

def request(url, referer=None):
    return json.loads(http_get(url, referer))

def fetch(title, artist, album, duration):
    from urllib.parse import urlencode, quote
    # Requests are bounded; app cancels lookups on track changes.
    try:
        data=request('https://c.y.qq.com/soso/fcgi-bin/search_for_qq_cp?'+urlencode({'w':title+' '+artist,'n':12,'format':'json'}),'https://y.qq.com')
        songs=((data.get('data') or {}).get('song') or {}).get('list') or []
        songs.sort(key=lambda x: canonical(x.get('albumname',''))!=canonical(album))
        for s in songs:
            if not compatible(title,artist,duration,s.get('songname',''),' '.join(a.get('name','') for a in s.get('singer',[])),s.get('interval',0)): continue
            d=request('https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?'+urlencode({'format':'json','nobase64':1,'songmid':s['songmid']}),'https://y.qq.com')
            lrc=d.get('lyric','')
            if parse_lrc(lrc): return lrc,'QQ音乐'
    except Exception: pass
    try:
        data=request('https://music.163.com/api/search/get/web?'+urlencode({'s':title+' '+artist,'type':1,'limit':12}),'https://music.163.com')
        songs=(data.get('result') or {}).get('songs') or []
        songs.sort(key=lambda x: canonical((x.get('album') or {}).get('name',''))!=canonical(album))
        for s in songs:
            if not compatible(title,artist,duration,s.get('name',''),' '.join(a.get('name','') for a in s.get('artists',[])),s.get('duration',0)/1000): continue
            d=request('https://music.163.com/api/song/lyric?'+urlencode({'id':s['id'],'lv':1,'kv':1,'tv':-1}),'https://music.163.com')
            lrc=(d.get('lrc') or {}).get('lyric','')
            if parse_lrc(lrc): return lrc,'网易云音乐'
    except Exception: pass
    try:
        data=request('https://lrclib.net/api/get?'+urlencode({'track_name':title,'artist_name':artist,'album_name':album,'duration':round(duration)}))
        if data.get('syncedLyrics'): return data['syncedLyrics'],'LRCLIB'
    except Exception: pass
    try:
        for d in request('https://lrclib.net/api/search?'+urlencode({'q':title+' '+artist})):
            if compatible(title,artist,duration,d.get('trackName',''),d.get('artistName',''),d.get('duration',0)) and d.get('syncedLyrics'):
                return d['syncedLyrics'],'LRCLIB'
    except Exception: pass
    return '', '暂无匹配歌词'

def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd,tmp=tempfile.mkstemp(dir=str(path.parent),prefix='.lyrics-')
    try:
        with os.fdopen(fd,'w',encoding='utf-8') as f: f.write(text)
        os.replace(tmp,path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def lookup(title,artist,album,duration):
    ident=key(title,artist,album)
    custom=CUSTOM/(ident+'.lrc'); cached=CACHE/(ident+'.json')
    if custom.exists():
        return {'key':ident,'source':'本地 LRC','entries':parse_lrc(custom.read_text(encoding='utf-8-sig'))}
    if cached.exists():
        try: return json.loads(cached.read_text())
        except (ValueError,OSError): pass
    # Preserve the user's already working lyrics as a fallback, identified honestly.
    legacy=Path.home()/'Library/Caches/qqmusic-tb-lyrics'/(hashlib.sha1((title+'|'+artist).encode()).hexdigest()[:16]+'.lrc')
    if legacy.exists():
        rows=parse_lrc(legacy.read_text(encoding='utf-8-sig'))
        if any(r['text'] for r in rows): return {'key':ident,'source':'原有歌词缓存','entries':rows}
    lrc,source=fetch(title,artist,album,duration)
    result={'key':ident,'source':source,'entries':parse_lrc(lrc)}
    if result['entries']: atomic_write(cached,json.dumps(result,ensure_ascii=False))
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('--title',required=True); p.add_argument('--artist',default=''); p.add_argument('--album',default=''); p.add_argument('--duration',type=float,default=0)
    a=p.parse_args()
    print(json.dumps(lookup(a.title,a.artist,a.album,a.duration),ensure_ascii=False),flush=True)
