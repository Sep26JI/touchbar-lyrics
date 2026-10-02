import Cocoa

final class LyricView: NSView {
    let model: PlayerModel
    let prefs: Preferences
    var includeControls = true
    var lastLine = ""
    var lineBegan = ProcessInfo.processInfo.systemUptime
    var mediaButtons: [NSButton] = []
    var lastVisualState = ""
    let physicalBarWidth: CGFloat?
    var visibleFrame: LyricFrame?
    var outgoing: LyricFrame?
    var outgoingBegan: Double = 0
    var transitionBegan: Double = 0
    let transitionDuration: Double = 0.32
    init(model: PlayerModel, controls: Bool = true, physicalBarWidth: CGFloat? = nil) {
        self.physicalBarWidth=physicalBarWidth
        self.model=model; self.prefs=model.prefs; includeControls=controls
        super.init(frame:NSRect(x:0,y:0,width:685,height:30))
        if controls {
            for (i,symbol) in ["backward.fill","playpause.fill","forward.fill"].enumerated() {
                let button=NSButton(image:NSImage(systemSymbolName:symbol,accessibilityDescription:["上一首","播放或暂停","下一首"][i])!,target:self,action:#selector(control(_:)))
                button.tag=i; button.isBordered=false; button.isTransparent=true; button.image=nil; button.title=""
                button.setAccessibilityLabel(["上一首","播放或暂停","下一首"][i])
                addSubview(button); mediaButtons.append(button)
            }
        }
        setAccessibilityElement(true); setAccessibilityRole(.group)
    }
    required init?(coder:NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width:685,height:30) }
    @objc func control(_ sender:NSButton) { model.command(["previous-track","toggle-play-pause","next-track"][sender.tag]) }
    override func layout() {
        super.layout()
        for (i,button) in mediaButtons.enumerated() {
            button.isHidden = !prefs.controls
            button.frame=NSRect(x:112+CGFloat(i)*35,y:(bounds.height-28)/2,width:32,height:28)
        }
    }
    // A2338's physical strip is 1004 pt. The system's legacy DFR size reports
    // 1085 pt even on this hardware, so it cannot be used for its physical center.
    // convert(to:nil) includes the actual system close-button/left inset.
    var lyricArea: NSRect {
        let baseCenter=physicalBarWidth.map { $0/2-convert(bounds,to:nil).minX } ?? bounds.midX
        let center=baseCenter + (includeControls ? prefs.horizontalOffset:0)
        return LyricLayout.area(width:bounds.width,height:bounds.height,center:center,controls:includeControls && prefs.controls)
    }
    func refresh() {
        let now=ProcessInfo.processInfo.systemUptime
        let frame=model.lyricFrame
        if visibleFrame?.id != frame.id || visibleFrame?.text != frame.text {
            outgoing=prefs.slideLyrics ? visibleFrame:nil
            outgoingBegan=lineBegan
            transitionBegan=now
            lineBegan=now
            lastLine=frame.text
            setAccessibilityLabel(frame.text)
        }
        visibleFrame=frame
        if now-transitionBegan >= transitionDuration || !prefs.slideLyrics {
            if outgoing != nil { needsDisplay=true }
            outgoing=nil
        }
        let state="\(frame.id)|\(frame.text)|\(frame.next)|\(Int(model.position))|\(model.playback?.playing ?? false)|\(model.fresh)|\(prefs.controls)|\(prefs.style)|\(prefs.fontName)|\(prefs.fontSize)|\(prefs.horizontalOffset)|\(prefs.lineProgress)|\(prefs.maxFillDuration)|\(prefs.slideLyrics)|\(prefs.scroll)|\(prefs.defaults.string(forKey:"color") ?? "")|\(prefs.defaults.string(forKey:"accent") ?? "")"
        if state != lastVisualState {
            lastVisualState=state
            for b in mediaButtons { b.isEnabled=model.isQQ && model.fresh }
            needsLayout=true; needsDisplay=true
        }
        let moving=model.playback?.playing != false && model.playback?.playbackRate != 0
        if outgoing != nil || (prefs.lineProgress && moving && frame.progress != nil) { needsDisplay=true }
        if prefs.scroll && (frame.text as NSString).size(withAttributes:[.font:prefs.font()]).width>lyricArea.width-20 { needsDisplay=true }
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.black.setFill(); bounds.fill()
        let hasControls=includeControls && prefs.controls
        if hasControls {
            drawProgress(NSRect(x:6,y:2,width:99,height:bounds.height-4))
            let paused=model.playback?.playing == false || model.playback?.playbackRate == 0
            for i in 0..<3 {
                let box=NSRect(x:112+CGFloat(i)*35,y:(bounds.height-28)/2,width:32,height:28)
                NSColor(white:0.16,alpha:1).setFill(); NSBezierPath(roundedRect:box,xRadius:5,yRadius:5).fill()
                NSColor.white.setFill()
                if i==1 && !paused {
                    NSRect(x:box.midX-5,y:box.midY-6,width:3,height:12).fill()
                    NSRect(x:box.midX+2,y:box.midY-6,width:3,height:12).fill()
                } else {
                    let direction:CGFloat=i==0 ? -1:1
                    let triangle=NSBezierPath()
                    triangle.move(to:NSPoint(x:box.midX+direction*5,y:box.midY))
                    triangle.line(to:NSPoint(x:box.midX-direction*4,y:box.midY+6))
                    triangle.line(to:NSPoint(x:box.midX-direction*4,y:box.midY-6))
                    triangle.close(); triangle.fill()
                    if i != 1 { NSRect(x:box.midX+direction*7-1,y:box.midY-6,width:2,height:12).fill() }
                }
            }
        }
        let area=lyricArea
        let accent=prefs.color("accent")
        if prefs.style == 1 {
            accent.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect:area,xRadius:7,yRadius:7).fill()
        }
        let inset=area.insetBy(dx:10,dy:0)
        let current=visibleFrame ?? model.lyricFrame
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect:inset).addClip()
        if let old=outgoing {
            let u=min(1,max(0,(ProcessInfo.processInfo.systemUptime-transitionBegan)/transitionDuration))
            let eased=u*u*(3-2*u)
            let distance=inset.height+3
            render(old,in:inset.offsetBy(dx:0,dy:distance*eased),began:outgoingBegan)
            render(current,in:inset.offsetBy(dx:0,dy:-distance*(1-eased)),began:lineBegan)
        } else { render(current,in:inset,began:lineBegan) }
        NSGraphicsContext.restoreGraphicsState()
    }
    private func render(_ frame:LyricFrame,in inset:NSRect,began:Double) {
        let color=prefs.color("color")
        let progress=prefs.lineProgress ? frame.progress:nil
        if prefs.style == 2 && !frame.next.isEmpty {
            drawLine(frame.text,in:NSRect(x:inset.minX,y:inset.midY-1,width:inset.width,height:inset.height/2+1),font:prefs.font(size:min(prefs.fontSize,15)),color:color,scroll:prefs.scroll,began:began,progress:progress)
            drawLine(frame.next,in:NSRect(x:inset.minX,y:inset.minY,width:inset.width,height:inset.height/2-1),font:prefs.font(size:10),color:color.withAlphaComponent(0.5),scroll:false,began:began,progress:nil)
        } else {
            drawLine(frame.text,in:inset,font:prefs.font(),color:color,scroll:prefs.scroll,began:began,progress:progress)
        }
    }
    private func drawLine(_ text:String,in rect:NSRect,font:NSFont,color:NSColor,scroll:Bool,began:Double,progress:Double?) {
        let attrs:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:color]
        var displayed=text
        // Measure the actual truncated string so centering and tint clips agree.
        if !scroll && (displayed as NSString).size(withAttributes:attrs).width>rect.width {
            while !displayed.isEmpty && ((displayed+"…") as NSString).size(withAttributes:attrs).width>rect.width { displayed.removeLast() }
            displayed += "…"
        }
        let string=NSAttributedString(string:displayed,attributes:attrs)
        let size=string.size()
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect:rect).addClip()
        var x=rect.midX-size.width/2
        if size.width>rect.width && scroll {
            let distance=size.width-rect.width
            let travel=distance/26
            let period=4+travel*2
            let phase=(ProcessInfo.processInfo.systemUptime-began).truncatingRemainder(dividingBy:period)
            let offset:CGFloat
            if phase<2 { offset=0 }
            else if phase<2+travel { offset=(phase-2)*26 }
            else if phase<4+travel { offset=distance }
            else { offset=max(0,distance-(phase-4-travel)*26) }
            x=rect.minX-offset
        }
        let point=NSPoint(x:x,y:rect.midY-size.height/2)
        string.draw(at:point)
        if let progress=progress,progress>0 {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect:NSRect(x:x,y:rect.minY,width:size.width*min(1,progress),height:rect.height)).addClip()
            var highlighted=attrs; highlighted[.foregroundColor]=prefs.color("accent")
            NSAttributedString(string:displayed,attributes:highlighted).draw(at:point)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    private func drawProgress(_ rect:NSRect) {
        let elapsed=model.position, duration=model.playback?.duration ?? 0
        func time(_ value:Double)->String { let n=max(0,Int(value)); return String(format:"%d:%02d",n/60,n%60) }
        let label=model.isQQ && model.fresh ? "\(time(elapsed)) / \(time(duration))" : "--:-- / --:--"
        let font=NSFont.monospacedDigitSystemFont(ofSize:10,weight:.medium)
        let s=NSAttributedString(string:label,attributes:[.font:font,.foregroundColor:NSColor.lightGray])
        s.draw(at:NSPoint(x:rect.midX-s.size().width/2,y:rect.minY+11))
        let track=NSRect(x:rect.minX,y:rect.minY+5,width:rect.width,height:2)
        NSColor.white.withAlphaComponent(0.22).setFill(); NSBezierPath(roundedRect:track,xRadius:1,yRadius:1).fill()
        if duration>0 && model.isQQ && model.fresh {
            var fill=track; fill.size.width *= min(1,max(0,elapsed/duration))
            prefs.color("accent").setFill(); NSBezierPath(roundedRect:fill,xRadius:1,yRadius:1).fill()
        }
    }
}

// Symmetric available space around the physical center prevents either side's
// buttons or the macOS Control Strip from shifting the text's center.
enum LyricLayout {
    static func area(width:CGFloat,height:CGFloat,center:CGFloat,controls:Bool) -> NSRect {
        let left:CGFloat=controls ? 224:4
        let radius=max(0,min(center-left,width-4-center))
        return NSRect(x:center-radius,y:1,width:radius*2,height:max(0,height-2))
    }
}
