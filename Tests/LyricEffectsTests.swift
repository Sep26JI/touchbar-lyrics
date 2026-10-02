import Cocoa
@main struct LyricEffectsTests {
    static func main() throws {
        let rows=[LyricRow(time:10,text:"第一句"),LyricRow(time:14,text:"第二句"),LyricRow(time:20,text:""),LyricRow(time:23,text:"最后一句")]
        func frame(_ time:Double)->LyricFrame { LyricTimeline.frame(rows:rows,time:time,duration:30,identity:"song",fallback:"间奏") }
        assert(frame(9).progress==nil)
        assert(frame(10).progress==0)
        assert(frame(12).progress==0.5)
        assert(frame(14).text=="第二句" && frame(14).progress==0)
        assert(frame(20).progress==1 && frame(20).text=="第二句")
        assert(frame(20).id==frame(19).id && frame(22.99).id==frame(19).id)
        assert(frame(19).next=="最后一句" && frame(21).next=="最后一句")
        assert(frame(23).text=="最后一句" && frame(23).progress==0)
        assert(frame(12).text=="第一句") // seeking back never retains a future line
        let gaps=[LyricRow(time:0,text:""),LyricRow(time:5,text:"开场"),LyricRow(time:8,text:""),LyricRow(time:15,text:"  "),LyricRow(time:50,text:"下一句"),LyricRow(time:55,text:"")]
        func gap(_ t:Double)->LyricFrame { LyricTimeline.frame(rows:gaps,time:t,duration:80,identity:"long-gap",fallback:"歌名") }
        assert(gap(3).text=="歌名" && gap(3).next=="开场")
        for t in [8.0,15,30,49.99] { assert(gap(t).text=="开场" && gap(t).id==gap(6).id && gap(t).progress==1) }
        assert(gap(50).text=="下一句" && gap(50).id != gap(49).id)
        assert(gap(70).text=="下一句" && gap(70).progress==1)
        assert(frame(26.5).progress==0.5)
        assert(frame(50).progress==1)
        assert(frame(12).id != frame(14).id)
        let noGapMarker=[LyricRow(time:10,text:"本句"),LyricRow(time:50,text:"下一句")]
        func capped(_ t:Double,_ limit:Double=8)->LyricFrame {
            LyricTimeline.frame(rows:noGapMarker,time:t,duration:100,identity:"no-marker",fallback:"歌名",maxFillDuration:limit)
        }
        assert(capped(14).progress==0.5)
        for t in [18.0,25,49.99] { assert(capped(t).progress==1 && capped(t).text=="本句" && capped(t).id==capped(10).id) }
        assert(capped(50).text=="下一句" && capped(50).progress==0)
        assert(capped(12,4).progress==0.5 && capped(14,4).progress==1)
        assert(capped(16,12).progress==0.5)
        assert(capped(11,8).progress==0.125) // seek back recalculates the fill
        // A final lyric must not stretch its fill over a long instrumental outro.
        assert(capped(58).progress==1 && capped(95).text=="下一句")
        let repeated=[LyricRow(time:0,text:"同一句"),LyricRow(time:2,text:"同一句")]
        assert(LyricTimeline.frame(rows:repeated,time:1,duration:4,identity:"s",fallback:"").id != LyricTimeline.frame(rows:repeated,time:3,duration:4,identity:"s",fallback:"").id)
        for origin:CGFloat in [0,64] {
            for controls in [true,false] {
                let area=LyricLayout.area(width:685,height:30,center:502-origin,controls:controls)
                assert(area.midX+origin==502)
                assert(area.minX >= (controls ? 224:4)); assert(area.maxX<=681)
            }
        }
        print("Lyric progress boundaries, repeated lines, and physical centering passed")
        var song=Playback(title:"歌名",artist:"歌手",bundleIdentifier:"com.tencent.QQMusicMac",durationMicros:100_000_000,playing:true)
        var pause=PauseDisplayState()
        let now=Date(timeIntervalSince1970:1000)
        func display(_ rows:[LyricRow],_ time:Double,_ date:Date)->LyricFrame {
            LyricPresentation.frame(playback:song,rows:rows,time:time,showPausedTitle:pause.showsTitle(for:song,at:date),maxFillDuration:8)
        }
        pause.update(song,at:now)
        assert(display([],0,now).text.isEmpty) // track loading
        assert(display(rows,1,now).text.isEmpty && display(rows,1,now).next.isEmpty) // intro, also in two-line style
        assert(display(rows,12,now).text=="第一句")
        song.playing=false; pause.update(song,at:now)
        assert(display(rows,12,now.addingTimeInterval(0.5)).text=="第一句") // transient paused signal
        let caption=display(rows,12,now.addingTimeInterval(1.3))
        assert(caption.text=="歌名 · 歌手" && caption.progress==nil && caption.next.isEmpty)
        song.title="新歌";pause.update(song,at:now.addingTimeInterval(1.4))
        assert(display([],0,now.addingTimeInterval(1.5)).text.isEmpty) // new track resets pause delay
        song.playing=true;pause.update(song,at:now.addingTimeInterval(1.6))
        assert(display([],0,now.addingTimeInterval(5)).text.isEmpty)
        assert(display(rows,12,now.addingTimeInterval(5)).text=="第一句") // resume restores timeline
        print("Loading, intro, pause, resume, and track-transition display passed")
        _=NSApplication.shared
        // NSArgumentDomain is volatile: give rendering a deterministic palette
        // and font without writing to the user's saved app preferences.
        let defaults=UserDefaults.standard
        let originalArguments=defaults.volatileDomain(forName:UserDefaults.argumentDomain)
        var testArguments=originalArguments
        for (key,value) in ["style":0,"font":"System","fontSize":20.0,"color":"#FFFFFF","accent":"#00FF00","controls":false,"scroll":false,"lineProgress":true,"horizontalOffset":0.0,"lead":1.3,"wordLead":0.0] as [String:Any] { testArguments[key]=value }
        defaults.setVolatileDomain(testArguments,forName:UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(originalArguments,forName:UserDefaults.argumentDomain) }
        let prefs=Preferences(); let model=PlayerModel(prefs,resources:URL(fileURLWithPath:"/tmp"))
        assert(model.lyricFrame.text.isEmpty)
        let rhythmicWords=[LyricWord(time:10,duration:0.5,text:"快"),LyricWord(time:12,duration:3,text:"慢"),LyricWord(time:15,duration:0.5,text:"!")]
        let rhythmic=LyricRow(time:10,text:"快慢!",words:rhythmicWords,end:15.5)
        model.rows=[LyricRow(time:0,text:"",words:[]),rhythmic]
        assert(model.hasWordTiming && model.lead==prefs.wordLead && model.lead==0,"True word timing must not reuse the old +1.3 second line offset")
        model.rows=rows
        assert(!model.hasWordTiming && model.lead==prefs.lead && model.lead==1.3)
        model.rows=[LyricRow(time:0,text:"",words:[])]
        assert(!model.hasWordTiming && model.lead==prefs.lead)
        func sung(_ t:Double)->LyricFrame { LyricTimeline.frame(rows:[rhythmic],time:t,duration:30,identity:"rhythm",fallback:"",estimateProgress:false) }
        assert(sung(10.25).highlights.map({ $0.progress }) == [0.5,0,0])
        assert(sung(11.5).highlights.map({ $0.progress }) == [1,0,0]) // rest between words holds
        assert(sung(13.5).highlights.map({ $0.progress }) == [1,0.5,0]) // long sustained syllable
        assert(sung(16).highlights.map({ $0.progress }) == [1,1,1])
        assert(sung(10).highlights.map({ $0.progress }) == [0,0,0]) // seek backward
        assert(sung(13.5).progress == nil) // no linear line-wide gradient
        let unicode=WordTiming.highlights(text:"A🙂慢",words:[LyricWord(time:0,duration:1,text:"A🙂"),LyricWord(time:1,duration:1,text:"慢")],time:1.5)
        assert(unicode[0].range==NSRange(location:0,length:3) && unicode[1].range==NSRange(location:3,length:1))
        let accentedText="e\u{301}🙂慢"
        let accentedWords=[LyricWord(time:0,duration:1,text:"e\u{301}"),LyricWord(time:1,duration:1,text:"🙂"),LyricWord(time:2,duration:1,text:"慢")]
        let accentedHighlights=WordTiming.highlights(text:accentedText,words:accentedWords,time:2.5)
        assert(accentedHighlights.map({ $0.range }) == [NSRange(location:0,length:2),NSRange(location:2,length:2),NSRange(location:4,length:1)])
        assert(accentedHighlights.map({ $0.progress }) == [1,1,0.5])
        assert(WordTiming.highlights(text:"正文",words:[LyricWord(time:0,duration:1,text:"错误")],time:1).isEmpty)
        assert(LyricTimeline.frame(rows:rows,time:12,duration:30,identity:"lrc",fallback:"",estimateProgress:false).progress==nil)
        let decoded=try JSONDecoder().decode(LyricRow.self,from:Data(#"{"time":10,"text":"快慢!","words":[{"time":10,"duration":0.5,"text":"快"},{"time":12,"duration":3,"text":"慢"},{"time":15,"duration":0.5,"text":"!"}],"end":15.5}"#.utf8))
        assert(decoded.words?.count==3 && decoded.end==15.5)
        print("Rhythmic word timing, rests, sustained notes, Unicode ranges, seek, and plain-LRC fallback passed")
        let view=LyricView(model:model); view.frame=NSRect(x:0,y:0,width:1004,height:30)
        let window=NSWindow(contentRect:view.frame,styleMask:.borderless,backing:.buffered,defer:false);window.contentView=view
        view.visibleFrame=LyricFrame(id:"test",text:"歌词在整个 Touch Bar 的正中间",progress:0.5)
        view.lineBegan=ProcessInfo.processInfo.systemUptime
        for (name,phase) in [("rest",-1.0),("slide-start",0.0),("slide-middle",0.5),("slide-end",1.0)] {
            if phase<0 { view.outgoing=nil }
            else {
                view.outgoing=LyricFrame(id:"old",text:"上一句歌词向上滑出",progress:1)
                view.transitionBegan=ProcessInfo.processInfo.systemUptime-view.transitionDuration*phase
            }
            let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
            view.cacheDisplay(in:view.bounds,to:rep)
            try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"Tests/effects-\(name).png"))
        }
        print("Four deterministic rendering frames exported")
        view.visibleFrame=sung(13.5); view.outgoing=nil
        let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
        view.cacheDisplay(in:view.bounds,to:rep)
        try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"Tests/effects-word-rhythm.png"))

        // Inspect real rendered glyph pixels, rather than only the timeline's
        // numeric progress. Controls and scrolling are absent for stable frames.
        let pixelView=LyricView(model:model,controls:false)
        pixelView.frame=NSRect(x:0,y:0,width:360,height:30)
        let pixelWindow=NSWindow(contentRect:pixelView.frame,styleMask:.borderless,backing:.buffered,defer:false)
        pixelWindow.contentView=pixelView
        struct Rendered {
            let rgb:Data
            let tintPixels:Int
        }
        func renderPixels(_ frame:LyricFrame,width:CGFloat=360)->Rendered {
            pixelView.frame=NSRect(x:0,y:0,width:width,height:30)
            pixelView.visibleFrame=frame; pixelView.outgoing=nil
            pixelView.lineBegan=ProcessInfo.processInfo.systemUptime
            let bitmap=pixelView.bitmapImageRepForCachingDisplay(in:pixelView.bounds)!
            pixelView.cacheDisplay(in:pixelView.bounds,to:bitmap)
            var rgb=Data(capacity:bitmap.pixelsWide*bitmap.pixelsHigh*3)
            var tint=0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let color=bitmap.colorAt(x:x,y:y)!.usingColorSpace(.sRGB)!
                    let r=color.redComponent,g=color.greenComponent,b=color.blueComponent
                    rgb.append(contentsOf:[UInt8((min(1,max(0,r))*255).rounded()),UInt8((min(1,max(0,g))*255).rounded()),UInt8((min(1,max(0,b))*255).rounded())])
                    if g>0.25 && g-r>0.12 && g-b>0.12 { tint += 1 }
                }
            }
            return Rendered(rgb:rgb,tintPixels:tint)
        }
        func timedFrame(_ row:LyricRow,_ time:Double)->LyricFrame {
            LyricTimeline.frame(rows:[row],time:time,duration:30,identity:"pixels",fallback:"",estimateProgress:false)
        }
        let sustained=LyricRow(time:0,text:"MMMMMMMM",words:[LyricWord(time:0,duration:4,text:"MMMMMMMM")],end:4)
        let fills=[0.0,1,2,3,4].map { renderPixels(timedFrame(sustained,$0)).tintPixels }
        assert(fills[0]==0 && zip(fills,fills.dropFirst()).allSatisfy({ $0 < $1 }),"A sustained word must gain tinted glyph pixels throughout its own duration: \(fills)")
        let restA=renderPixels(sung(11)),restB=renderPixels(sung(11.75))
        assert(restA.tintPixels>0 && restA.rgb==restB.rgb,"A rest between timed words must not keep advancing the rendered tint")

        // Most of this token is offscreen. Half of the full token's duration is
        // already beyond the visible prefix, so that prefix must be fully tinted.
        // Scaling progress by the truncated prefix's width would fail this test.
        let longText=String(repeating:"W",count:40)
        let longWord=LyricRow(time:0,text:longText,words:[LyricWord(time:0,duration:10,text:longText)],end:10)
        let early=renderPixels(timedFrame(longWord,0.5),width:180)
        let hiddenTail=renderPixels(timedFrame(longWord,5),width:180)
        let finished=renderPixels(timedFrame(longWord,10),width:180)
        assert(early.tintPixels>0 && early.tintPixels<hiddenTail.tintPixels)
        assert(hiddenTail.rgb==finished.rgb,"A hidden token tail must not slow the visible prefix's true-time tint")

        let accentedRow=LyricRow(time:0,text:accentedText,words:accentedWords,end:3)
        let beforeAccentTail=renderPixels(timedFrame(accentedRow,2))
        let partialAccentTail=renderPixels(timedFrame(accentedRow,2.5))
        let completeAccentTail=renderPixels(timedFrame(accentedRow,3))
        assert(beforeAccentTail.tintPixels<partialAccentTail.tintPixels && partialAccentTail.tintPixels<completeAccentTail.tintPixels,"Glyph tint after a combining accent and emoji must follow the UTF-16 word range")
        print("Rendered word tint advances, rests hold, truncated hidden tails retain timing, and combining-accent/emoji boundaries passed")
    }
}
