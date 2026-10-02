import Cocoa

struct LyricWord: Decodable {
    let time: Double
    let duration: Double
    let text: String
}
struct LyricRow: Decodable {
    let time: Double
    let text: String
    var words: [LyricWord]? = nil
    var end: Double? = nil
}
struct WordHighlight {
    let range: NSRange
    let progress: Double
}
enum WordTiming {
    static func isValid(text: String, words: [LyricWord]) -> Bool {
        !words.isEmpty && words.map({ $0.text }).joined() == text &&
        words.allSatisfy({ $0.time.isFinite && $0.duration.isFinite && $0.duration >= 0 })
    }
    static func highlights(text: String, words: [LyricWord], time: Double) -> [WordHighlight] {
        guard isValid(text:text,words:words) else { return [] }
        var offset=0
        return words.map { word in
            let count=(word.text as NSString).length
            let progress=word.duration > 0 ? min(1,max(0,(time-word.time)/word.duration)) : (time >= word.time ? 1.0:0.0)
            defer { offset += count }
            return WordHighlight(range:NSRange(location:offset,length:count),progress:progress)
        }
    }
}
struct LyricResult: Decodable { let key: String; let source: String; let entries: [LyricRow] }
struct LyricFrame {
    var id: String
    var text: String
    var next: String = ""
    var progress: Double? = nil
    var highlights: [WordHighlight] = []
}
enum LyricTimeline {
    static func frame(rows:[LyricRow],time:Double,duration:Double,identity:String,fallback:String,maxFillDuration:Double = 8,estimateProgress:Bool = true) -> LyricFrame {
        func hasText(_ row:LyricRow) -> Bool { !row.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }
        // Empty timed entries mark instrumental gaps. Keep the last real lyric
        // and its identity so gaps neither show the title nor trigger a slide.
        let index=rows.lastIndex(where: { $0.time <= time && hasText($0) })
        guard let i=index else {
            return LyricFrame(id:identity+"/intro",text:fallback,next:fallback.isEmpty ? "" : rows.first(where:hasText)?.text ?? "")
        }
        let row=rows[i]
        let following=rows.dropFirst(i+1)
        let next=following.first(where:hasText)?.text ?? ""
        let highlights=WordTiming.highlights(text:row.text,words:row.words ?? [],time:time)
        if !highlights.isEmpty {
            return LyricFrame(id:identity+"/\(i)",text:row.text,next:next,highlights:highlights)
        }
        // A blank still ends the sung line: finish its tint at the gap, then
        // hold the completed tint rather than stretching it across the silence.
        let boundary=following.first(where: { $0.time > row.time })?.time ?? duration
        // Line-start-only LRC cannot tell a sustained note from an instrumental
        // gap. Bound the visual estimate; do not include an entire long silence.
        let limit=maxFillDuration.isFinite ? min(15,max(2,maxFillDuration)):8
        let end=min(boundary,row.time+limit)
        let progress = estimateProgress && end>row.time ? min(1,max(0,(time-row.time)/(end-row.time))) : nil
        return LyricFrame(id:identity+"/\(i)",text:row.text,next:next,progress:progress)
    }
}

struct Playback: Decodable {
    var title: String?; var artist: String?; var album: String?
    var bundleIdentifier: String?; var durationMicros: Double?
    var elapsedTimeMicros: Double?; var timestampEpochMicros: Double?
    var elapsedTimeNowMicros: Double?; var playbackRate: Double?; var playing: Bool?
    var duration: Double { (durationMicros ?? 0) / 1_000_000 }
    var paused: Bool { playing == false || playbackRate == 0 }
    var identity: String { [bundleIdentifier ?? "", title ?? "", artist ?? "", album ?? ""].joined(separator: "\u{1f}") }
    func position(at date: Date = Date()) -> Double {
        let anchor = (elapsedTimeMicros ?? 0) / 1_000_000
        let rate = playing == false ? 0 : (playbackRate ?? (playing == true ? 1 : 0))
        let delta = timestampEpochMicros.map { date.timeIntervalSince1970 - $0 / 1_000_000 } ?? 0
        let value = anchor + max(0, delta) * rate
        return max(0, duration > 0 ? min(duration, value) : value)
    }
}

struct PauseDisplayState {
    private var identity: String?
    private var began: Date?
    mutating func update(_ playback: Playback, at date: Date = Date()) {
        if playback.paused {
            if identity != playback.identity || began == nil { began = date }
        } else { began = nil }
        identity = playback.identity
    }
    func showsTitle(for playback: Playback, at date: Date = Date()) -> Bool {
        // Media sessions can briefly report paused while changing songs.
        playback.paused && identity == playback.identity && began.map { date.timeIntervalSince($0) >= 1.2 } == true
    }
}

enum LyricPresentation {
    static func frame(playback: Playback, rows: [LyricRow], time: Double, showPausedTitle: Bool, maxFillDuration: Double, estimateProgress: Bool = false) -> LyricFrame {
        if playback.paused && showPausedTitle {
            let caption = [playback.title, playback.artist].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            return LyricFrame(id:playback.identity+"/paused",text:caption)
        }
        return LyricTimeline.frame(rows:rows,time:time,duration:playback.duration,
                                   identity:playback.identity,fallback:"",maxFillDuration:maxFillDuration,estimateProgress:estimateProgress)
    }
}

struct PlaybackClock {
    var snapshot: Playback?
    var frozen: Double?
    mutating func update(_ next: Playback, at date: Date = Date()) {
        let same = snapshot?.identity == next.identity
        let unchangedAnchor = same && snapshot?.elapsedTimeMicros == next.elapsedTimeMicros && snapshot?.timestampEpochMicros == next.timestampEpochMicros
        let paused = next.playing == false || next.playbackRate == 0
        if paused {
            // QQ can publish playing=false while retaining the *old playing*
            // anchor and playbackRate=1. Freeze where we were, not at that anchor.
            if unchangedAnchor, let previous = snapshot {
                frozen = frozen ?? previous.position(at: date)
            } else {
                frozen = next.position(at: date)
            }
        } else { frozen = nil }
        snapshot = next
    }
    func position(at date: Date = Date()) -> Double { frozen ?? snapshot?.position(at: date) ?? 0 }
}

final class Preferences {
    let defaults = UserDefaults.standard
    init() { defaults.register(defaults: ["style":0,"font":"System","fontSize":17.0,"color":"#FFFFFF","accent":"#47DBC0","lead":1.7,"wordLead":0.0,"desktop":false,"controls":true,"scroll":true,"lineProgress":true,"slideLyrics":true,"horizontalOffset":-24.0,"maxFillDuration":8.0,"estimateProgress":false]) }
    var style: Int { get { defaults.integer(forKey:"style") } set { defaults.set(newValue,forKey:"style") } }
    var fontName: String { get { defaults.string(forKey:"font") ?? "System" } set { defaults.set(newValue,forKey:"font") } }
    var fontSize: Double { get { defaults.double(forKey:"fontSize") } set { defaults.set(newValue,forKey:"fontSize") } }
    var lead: Double { get { defaults.double(forKey:"lead") } set { defaults.set(newValue,forKey:"lead") } }
    var wordLead: Double { get { defaults.double(forKey:"wordLead") } set { defaults.set(newValue,forKey:"wordLead") } }
    var desktop: Bool { get { defaults.bool(forKey:"desktop") } set { defaults.set(newValue,forKey:"desktop") } }
    var controls: Bool { get { defaults.bool(forKey:"controls") } set { defaults.set(newValue,forKey:"controls") } }
    var scroll: Bool { get { defaults.bool(forKey:"scroll") } set { defaults.set(newValue,forKey:"scroll") } }
    var lineProgress: Bool { get { defaults.bool(forKey:"lineProgress") } set { defaults.set(newValue,forKey:"lineProgress") } }
    var estimateProgress: Bool { get { defaults.bool(forKey:"estimateProgress") } set { defaults.set(newValue,forKey:"estimateProgress") } }
    var slideLyrics: Bool { get { defaults.bool(forKey:"slideLyrics") } set { defaults.set(newValue,forKey:"slideLyrics") } }
    var maxFillDuration: Double {
        get { min(15,max(2,defaults.double(forKey:"maxFillDuration"))) }
        set { defaults.set(min(15,max(2,newValue)),forKey:"maxFillDuration") }
    }
    var horizontalOffset: Double {
        get { min(120,max(-120,defaults.double(forKey:"horizontalOffset"))) }
        set { defaults.set(min(120,max(-120,newValue)),forKey:"horizontalOffset") }
    }
    func color(_ key: String) -> NSColor {
        let hex = defaults.string(forKey:key) ?? "#FFFFFF"
        let n = UInt32(hex.replacingOccurrences(of:"#",with:""),radix:16) ?? 0xFFFFFF
        return NSColor(srgbRed:CGFloat((n >> 16)&255)/255,green:CGFloat((n >> 8)&255)/255,blue:CGFloat(n&255)/255,alpha:1)
    }
    func setColor(_ color: NSColor, key: String) {
        guard let c = color.usingColorSpace(.sRGB) else { return }
        defaults.set(String(format:"#%02X%02X%02X",Int(c.redComponent*255),Int(c.greenComponent*255),Int(c.blueComponent*255)),forKey:key)
    }
    func font(size: CGFloat? = nil) -> NSFont {
        let s = size ?? fontSize
        return (fontName == "System" ? nil : NSFont(name:fontName,size:s)) ?? NSFont.systemFont(ofSize:s,weight:.medium)
    }
}

// All mutable playback/lyrics state lives on the main thread. One media read at
// a time; lyric lookup has a separate cancellable process with generation guard.
final class PlayerModel {
    let prefs: Preferences
    var playback: Playback?
    var clock = PlaybackClock()
    var pauseDisplay = PauseDisplayState()
    var rows: [LyricRow] = [] {
        didSet { hasWordTiming=rows.contains { WordTiming.isValid(text:$0.text,words:$0.words ?? []) } }
    }
    private(set) var hasWordTiming = false
    var source = "等待 QQ 音乐播放"
    var lyricKey = ""
    var receivedAt = Date.distantPast
    var changed: (() -> Void)?
    var busy = false
    var lookupProcess: Process?
    var lookupToken = UUID()
    var pollingProcess: Process?
    var stopped = false
    var timer: Timer?
    var lastRetry = Date.distantPast
    let resources: URL
    var mediaURL: URL { resources.appendingPathComponent("media-control/bin/media-control") }
    init(_ prefs: Preferences, resources: URL) { self.prefs = prefs; self.resources = resources }
    var isQQ: Bool { playback?.bundleIdentifier == "com.tencent.QQMusicMac" }
    var fresh: Bool { Date().timeIntervalSince(receivedAt) < 5 }
    var position: Double { fresh ? clock.position() : 0 }
    var lead: Double { hasWordTiming ? prefs.wordLead:prefs.lead }
    var timingStatus: String {
        guard !rows.isEmpty else { return "" }
        return hasWordTiming ? "逐字时间" : (prefs.estimateProgress ? "逐句时间 · 染色为估算" : "逐句时间 · 暂无逐字染色")
    }
    var lyricFrame: LyricFrame {
        guard isQQ, fresh, let playback=playback else { return LyricFrame(id:"status",text:"") }
        return LyricPresentation.frame(playback:playback,rows:rows,time:position+lead,
                                       showPausedTitle:pauseDisplay.showsTitle(for:playback),maxFillDuration:prefs.maxFillDuration,estimateProgress:prefs.estimateProgress)
    }
    var current: (String,String) { (lyricFrame.text,lyricFrame.next) }
    func start() {
        poll()
        timer = Timer(timeInterval:1,repeats:true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer!,forMode:.common)
    }
    func stop() { stopped = true; timer?.invalidate(); if let process=lookupProcess, process.isRunning { process.terminate() }; if let process=pollingProcess, process.isRunning { process.terminate() } }
    func poll() {
        guard !busy, !stopped else { return }; busy = true
        let p = Process(); pollingProcess = p
        p.executableURL = mediaURL; p.arguments = ["get","--micros","--no-artwork"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        DispatchQueue.global(qos:.utility).async {
            var data = Data()
            do {
                try p.run()
                DispatchQueue.global().asyncAfter(deadline:.now()+4) { if p.isRunning { p.terminate() } }
                data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            } catch { }
            let value = try? JSONDecoder().decode(Playback.self,from:data)
            DispatchQueue.main.async {
                self.busy = false
                guard !self.stopped else { return }
                guard let value = value, value.title != nil else {
                    if !self.fresh { self.playback = nil; self.rows=[]; self.source="等待 QQ 音乐播放"; self.changed?() }
                    return
                }
                let different = self.playback?.identity != value.identity
                self.clock.update(value); self.pauseDisplay.update(value); self.playback=value; self.receivedAt=Date()
                if different {
                    self.lookupToken=UUID(); if let process=self.lookupProcess, process.isRunning { process.terminate() }; self.rows=[]; self.lyricKey=""
                    self.source = self.isQQ ? "正在查找歌词…" : "请在 QQ 音乐播放歌曲"
                    if self.isQQ { self.lookup() }
                } else if self.isQQ && self.rows.isEmpty && self.lookupProcess == nil && Date().timeIntervalSince(self.lastRetry)>60 { self.lookup() }
                self.changed?()
            }
        }
    }
    func lookup() {
        guard let s=playback, isQQ else { return }
        if let process=lookupProcess, process.isRunning { process.terminate() }; let token=UUID(); lookupToken=token; lastRetry=Date()
        let p=Process(); lookupProcess=p
        p.executableURL=URL(fileURLWithPath:"/usr/bin/python3")
        p.arguments=[resources.appendingPathComponent("lyrics_engine.py").path,"--title",s.title ?? "","--artist",s.artist ?? "","--album",s.album ?? "","--duration",String(s.duration)]
        let pipe=Pipe(); p.standardOutput=pipe; p.standardError=FileHandle.nullDevice
        DispatchQueue.global(qos:.utility).async {
            var data=Data()
            do {
                try p.run()
                DispatchQueue.global().asyncAfter(deadline:.now()+35) { if p.isRunning { p.terminate() } }
                data=pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            } catch { }
            let result=try? JSONDecoder().decode(LyricResult.self,from:data)
            DispatchQueue.main.async {
                guard !self.stopped, self.lookupToken==token else { return }
                self.lookupProcess=nil
                self.rows=result?.entries ?? []; self.lyricKey=result?.key ?? ""
                self.source=result?.source ?? "歌词读取失败，可重试或导入 LRC"
                self.changed?()
            }
        }
    }
    func command(_ command: String) {
        guard isQQ, fresh else { return }
        let url=mediaURL
        DispatchQueue.global(qos:.userInitiated).async {
            // Re-check the active media app immediately before controlling it.
            let probe=Process(); probe.executableURL=url; probe.arguments=["get","--no-artwork"]
            let pipe=Pipe(); probe.standardOutput=pipe; probe.standardError=FileHandle.nullDevice
            do {
                try probe.run()
                DispatchQueue.global().asyncAfter(deadline:.now()+3) { if probe.isRunning { probe.terminate() } }
                let data=pipe.fileHandleForReading.readDataToEndOfFile(); probe.waitUntilExit()
                guard let d=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],d["bundleIdentifier"] as? String == "com.tencent.QQMusicMac" else { return }
                let p=Process(); p.executableURL=url; p.arguments=[command]; p.standardOutput=FileHandle.nullDevice; p.standardError=FileHandle.nullDevice
                try p.run(); DispatchQueue.global().asyncAfter(deadline:.now()+3) { if p.isRunning { p.terminate() } }; p.waitUntilExit()
            } catch { }
        }
    }
}
