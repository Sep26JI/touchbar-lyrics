import Foundation
@main struct ClockTests {
    static func main() throws {
        func snapshot(_ elapsed:Double,_ rate:Double,_ playing:Bool=true)->Playback {
            Playback(title:"歌",artist:"歌手",album:"专辑",bundleIdentifier:"com.tencent.QQMusicMac",durationMicros:100_000_000,elapsedTimeMicros:elapsed*1_000_000,timestampEpochMicros:1_000_000_000,playbackRate:rate,playing:playing)
        }
        let at=Date(timeIntervalSince1970:1010)
        assert(snapshot(20,1).position(at:at)==30)
        assert(snapshot(20,0).position(at:at)==20)
        assert(snapshot(20,1,false).position(at:at)==20)
        assert(snapshot(3,1).position(at:at)==13) // seek backwards resets anchor
        assert(snapshot(99,1).position(at:at)==100) // no invented repeat
        assert(snapshot(20,2).position(at:at)==40)
        var a=snapshot(20,1);var b=a;b.album="别的专辑";assert(a.identity != b.identity)
        a.timestampEpochMicros=nil; assert(a.position(at:at)==20)
        var clock = PlaybackClock()
        let playing=snapshot(20,1)
        clock.update(playing,at:Date(timeIntervalSince1970:1005))
        var paused=playing; paused.playing=false
        clock.update(paused,at:at)
        assert(clock.position(at:Date(timeIntervalSince1970:1020))==30)
        clock.update(paused,at:Date(timeIntervalSince1970:1030))
        assert(clock.position(at:Date(timeIntervalSince1970:1040))==30)
        var seek=paused; seek.elapsedTimeMicros=5_000_000; seek.timestampEpochMicros=1_030_000_000
        clock.update(seek,at:Date(timeIntervalSince1970:1030)); assert(clock.position()==5)
        seek.playing=true
        clock.update(seek,at:Date(timeIntervalSince1970:1030))
        assert(clock.position(at:Date(timeIntervalSince1970:1035))==10)
        print("12 playback clock checks passed")
    }
}
