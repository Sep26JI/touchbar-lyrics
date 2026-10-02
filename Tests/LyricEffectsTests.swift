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
        _=NSApplication.shared
        let prefs=Preferences(); let model=PlayerModel(prefs,resources:URL(fileURLWithPath:"/tmp"))
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
    }
}
