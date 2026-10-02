import Cocoa
import ServiceManagement
import UniformTypeIdentifiers

final class AppDelegate:NSObject,NSApplicationDelegate,NSTouchBarDelegate,NSWindowDelegate {
    let prefs=Preferences()
    lazy var model=PlayerModel(prefs,resources:Bundle.main.resourceURL!)
    lazy var canvas=LyricView(model:model,physicalBarWidth:1004)
    lazy var preview=LyricView(model:model)
    lazy var overlayView=LyricView(model:model,controls:false)
    let bar=NSTouchBar()
    let contentID=NSTouchBarItem.Identifier("local.touchbar.lyrics.canvas")
    let trayID=NSTouchBarItem.Identifier("local.touchbar.lyrics.tray")
    var tray:NSCustomTouchBarItem!
    var status:NSStatusItem!
    var settings:NSWindow?
    var overlay:NSPanel?
    var animation:Timer?
    var active=true
    var statusLabel:NSTextField?
    var leadLabel:NSTextField?
    var leadSlider:NSSlider?
    var sizeLabel:NSTextField?
    var fontButton:NSPopUpButton?
    var lastStatus = ""
    var fillDurationLabel:NSTextField?
    var positionLabel:NSTextField?
    var positionSlider:NSSlider?

    func applicationDidFinishLaunching(_ notification:Notification) {
        bar.delegate=self; bar.defaultItemIdentifiers=[contentID]; bar.principalItemIdentifier=contentID
        tray=NSCustomTouchBarItem(identifier:trayID)
        tray.view=NSButton(title:"♪",target:self,action:#selector(showBar))
        DFR.tray(tray,add:true); DFR.presence(trayID.rawValue,true)
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        status.button?.image=NSImage(systemSymbolName:"music.note",accessibilityDescription:"Touch Bar 歌词")
        let menu=NSMenu()
        for (title,sel) in [("显示 Touch Bar 歌词",#selector(showBar)),("收起 Touch Bar 歌词",#selector(hideBar)),("外观与歌词设置…",#selector(openSettings)),("重新查找歌词",#selector(reloadLyrics)),("导入当前歌曲的 LRC…",#selector(importLRC)),("退出",#selector(quit))] {
            let item=NSMenuItem(title:title,action:sel,keyEquivalent:""); item.target=self; menu.addItem(item)
        }
        status.menu=menu
        let main=NSMenu(); let root=NSMenuItem(); main.addItem(root); root.submenu=NSMenu()
        let settingsItem=NSMenuItem(title:"设置…",action:#selector(openSettings),keyEquivalent:","); settingsItem.target=self
        root.submenu?.addItem(settingsItem)
        root.submenu?.addItem(NSMenuItem(title:"隐藏歌词程序",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h"))
        root.submenu?.addItem(NSMenuItem(title:"退出",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"))
        NSApp.mainMenu=main
        model.changed={ [weak self] in self?.refresh() }
        model.start()
        animation=Timer(timeInterval:1.0/30,repeats:true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(animation!,forMode:.common)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(wake),name:NSWorkspace.didWakeNotification,object:nil)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.8) { self.showBar() }
        updateOverlay()
        if CommandLine.arguments.contains("--settings") { openSettings() }
    }
    func touchBar(_ touchBar:NSTouchBar,makeItemForIdentifier identifier:NSTouchBarItem.Identifier)->NSTouchBarItem? {
        guard identifier==contentID else { return nil }
        let item=NSCustomTouchBarItem(identifier:identifier); item.view=canvas
        canvas.translatesAutoresizingMaskIntoConstraints=false
        let width=canvas.widthAnchor.constraint(equalToConstant:685); width.priority = .defaultLow; width.isActive=true
        canvas.widthAnchor.constraint(greaterThanOrEqualToConstant:400).isActive=true
        canvas.heightAnchor.constraint(equalToConstant:30).isActive=true
        return item
    }
    @objc func showBar() { active=true; DFR.present(bar,id:trayID.rawValue) }
    @objc func hideBar() { active=false; DFR.dismiss(bar) }
    @objc func wake() { if active { DispatchQueue.main.asyncAfter(deadline:.now()+1) { if self.active { self.showBar() } } }; model.poll() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification:Notification) {
        animation?.invalidate(); model.stop(); DFR.dismiss(bar); DFR.presence(trayID.rawValue,false); DFR.tray(tray,add:false)
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool { openSettings(); return true }
    func refresh() {
        canvas.refresh()
        if settings?.isVisible == true { preview.refresh() }
        if overlay?.isVisible == true { overlayView.refresh() }
        let p=model.playback
        let timingStatus=model.timingStatus
        let timing=timingStatus.isEmpty || model.source.contains(timingStatus) ? "" : " · "+timingStatus
        let newStatus="\(p?.title ?? "等待播放") · \(p?.artist ?? "QQ 音乐")\n\(model.source)\(timing) · \(model.isQQ && model.fresh ? "已连接 QQ 音乐" : "等待 QQ 音乐")\nTouch Bar 接口：\(DFR.available ? "已加载" : "不可用")"
        if newStatus != lastStatus {
            lastStatus=newStatus; statusLabel?.stringValue=newStatus
            leadSlider?.doubleValue=model.lead; leadLabel?.stringValue=leadDescription()
        }
    }
    @objc func reloadLyrics() { model.source="正在查找歌词…"; model.lookup() }
    @objc func importLRC() {
        guard !model.lyricKey.isEmpty,model.isQQ else { message("请先在 QQ 音乐播放歌曲，等待一次歌词查找完成。"); return }
        let key=model.lyricKey
        let panel=NSOpenPanel(); panel.allowedContentTypes=[UTType(filenameExtension:"lrc") ?? .plainText]; panel.allowsMultipleSelection=false
        NSApp.activate(ignoringOtherApps:true)
        guard panel.runModal() == .OK,let url=panel.url else { return }
        do {
            let data=try Data(contentsOf:url)
            guard String(data:data,encoding:.utf8) != nil else { message("请使用 UTF-8 编码的 LRC 文件。"); return }
            let root=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TouchBarLyrics/lyrics")
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            try data.write(to:root.appendingPathComponent(key+".lrc"),options:.atomic)
            if model.lyricKey==key { model.lookup() }
        } catch { message("导入失败：\(error.localizedDescription)") }
    }
    func message(_ text:String) { let alert=NSAlert(); alert.messageText=text; alert.runModal() }
    @objc func openSettings() {
        if settings==nil { buildSettings() }
        settings?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func label(_ text:String,size:CGFloat=13)->NSTextField {
        let l=NSTextField(labelWithString:text); l.font = .systemFont(ofSize:size); return l
    }
    func row(_ title:String,_ control:NSView)->NSStackView {
        let l=label(title); l.widthAnchor.constraint(equalToConstant:96).isActive=true
        let row=NSStackView(views:[l,control]); row.orientation = .horizontal; row.spacing=14; row.alignment = .centerY
        return row
    }
    func buildSettings() {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:740),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title="Touch Bar 歌词 · 设置"; window.isReleasedWhenClosed=false; window.center(); settings=window
        let stack=NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=17; stack.translatesAutoresizingMaskIntoConstraints=false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:28),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-28),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:24)])
        stack.addArrangedSubview(label("让歌词留在指尖",size:24))
        stack.addArrangedSubview(label("QQ 音乐后台同步 · 无需 BetterTouchTool",size:12))
        preview.translatesAutoresizingMaskIntoConstraints=false
        preview.widthAnchor.constraint(equalToConstant:704).isActive=true; preview.heightAnchor.constraint(equalToConstant:40).isActive=true
        stack.addArrangedSubview(preview)
        let styles=NSPopUpButton(); styles.addItems(withTitles:["简洁 · 纯色文字","胶囊 · 柔和底色","双行 · 当前句与下一句"]); styles.selectItem(at:prefs.style); styles.target=self; styles.action=#selector(styleChanged(_:))
        stack.addArrangedSubview(row("显示风格",styles))
        let fonts=NSPopUpButton(); fonts.addItem(withTitle:"System")
        fonts.addItems(withTitles:NSFontManager.shared.availableFontFamilies.sorted()); fonts.selectItem(withTitle:prefs.fontName); fonts.target=self; fonts.action=#selector(fontChanged(_:)); fontButton=fonts
        fonts.widthAnchor.constraint(equalToConstant:220).isActive=true
        let size=NSSlider(value:prefs.fontSize,minValue:11,maxValue:23,target:self,action:#selector(sizeChanged(_:))); size.widthAnchor.constraint(equalToConstant:145).isActive=true
        sizeLabel=label(String(format:"%.0f pt",prefs.fontSize))
        let fontRow=NSStackView(views:[fonts,size,sizeLabel!]); fontRow.spacing=10
        stack.addArrangedSubview(row("字体与大小",fontRow))
        let foreground=NSColorWell(); foreground.color=prefs.color("color"); foreground.target=self; foreground.action=#selector(colorChanged(_:)); foreground.tag=0
        let accent=NSColorWell(); accent.color=prefs.color("accent"); accent.target=self; accent.action=#selector(colorChanged(_:)); accent.tag=1
        let colorRow=NSStackView(views:[label("文字"),foreground,label("强调色"),accent]); colorRow.spacing=14
        stack.addArrangedSubview(row("颜色",colorRow))
        let position=NSSlider(value:prefs.horizontalOffset,minValue:-120,maxValue:120,target:self,action:#selector(positionChanged(_:)))
        position.widthAnchor.constraint(equalToConstant:240).isActive=true; position.isContinuous=true; positionSlider=position
        positionLabel=label(positionDescription()); positionLabel!.widthAnchor.constraint(equalToConstant:76).isActive=true
        let centerButton=NSButton(title:"重置到中点",target:self,action:#selector(resetPosition))
        let positionRow=NSStackView(views:[position,positionLabel!,centerButton]); positionRow.spacing=12
        stack.addArrangedSubview(row("水平位置",positionRow))
        let lead=NSSlider(value:model.lead,minValue:-5,maxValue:5,target:self,action:#selector(leadChanged(_:))); lead.widthAnchor.constraint(equalToConstant:270).isActive=true; leadSlider=lead
        leadLabel=label(leadDescription())
        let leadRow=NSStackView(views:[lead,leadLabel!]); leadRow.spacing=12
        stack.addArrangedSubview(row("歌词时间",leadRow))
        stack.addArrangedSubview(label("正值提前，负值延后；逐字与逐句分别保存偏移。逐字默认 0 秒，逐句保留原来的校准。",size:11))
        let controls=NSButton(checkboxWithTitle:"显示进度和播放按钮",target:self,action:#selector(controlsChanged(_:))); controls.state=prefs.controls ? .on:.off
        let scroll=NSButton(checkboxWithTitle:"长句平滑滚动",target:self,action:#selector(scrollChanged(_:))); scroll.state=prefs.scroll ? .on:.off
        let options=NSStackView(views:[controls,scroll]); options.spacing=20; stack.addArrangedSubview(options)
        let progress=NSButton(checkboxWithTitle:"逐字进度染色",target:self,action:#selector(progressChanged(_:))); progress.state=prefs.lineProgress ? .on:.off
        let slide=NSButton(checkboxWithTitle:"切句向上滑动",target:self,action:#selector(slideChanged(_:))); slide.state=prefs.slideLyrics ? .on:.off
        let estimate=NSButton(checkboxWithTitle:"无逐字时间时使用估算",target:self,action:#selector(estimateChanged(_:))); estimate.state=prefs.estimateProgress ? .on:.off
        let effects=NSStackView(views:[progress,slide,estimate]); effects.spacing=20; stack.addArrangedSubview(effects)
        let fillDuration=NSSlider(value:prefs.maxFillDuration,minValue:2,maxValue:15,target:self,action:#selector(fillDurationChanged(_:)))
        fillDuration.widthAnchor.constraint(equalToConstant:240).isActive=true; fillDuration.isContinuous=true
        fillDurationLabel=label(String(format:"最多 %.1f 秒",prefs.maxFillDuration))
        let fillRow=NSStackView(views:[fillDuration,fillDurationLabel!]); fillRow.spacing=12
        stack.addArrangedSubview(row("估算上限",fillRow))
        stack.addArrangedSubview(label("逐字歌词按真实字词时间染色；仅估算模式使用此上限。没有逐字时间时默认显示纯色。",size:11))
        let desktop=NSButton(checkboxWithTitle:"同时显示桌面悬浮歌词（鼠标可穿透）",target:self,action:#selector(desktopChanged(_:))); desktop.state=prefs.desktop ? .on:.off
        stack.addArrangedSubview(desktop)
        let login=NSButton(checkboxWithTitle:"登录时启动",target:self,action:#selector(loginChanged(_:))); login.state=SMAppService.mainApp.status == .enabled ? .on:.off
        stack.addArrangedSubview(login)
        statusLabel=label("",size:11); statusLabel?.textColor = .secondaryLabelColor; statusLabel?.maximumNumberOfLines=3
        stack.addArrangedSubview(statusLabel!)
        let buttons=NSStackView(); buttons.spacing=12
        for (title,sel) in [("显示 Touch Bar",#selector(showBar)),("收起",#selector(hideBar)),("导入 LRC…",#selector(importLRC)),("重试歌词",#selector(reloadLyrics))] { buttons.addArrangedSubview(NSButton(title:title,target:self,action:sel)) }
        stack.addArrangedSubview(buttons); lastStatus=""; refresh()
    }
    @objc func styleChanged(_ s:NSPopUpButton) { prefs.style=s.indexOfSelectedItem; refresh() }
    @objc func fontChanged(_ s:NSPopUpButton) { prefs.fontName=s.titleOfSelectedItem ?? "System"; refresh() }
    @objc func sizeChanged(_ s:NSSlider) { prefs.fontSize=s.doubleValue.rounded(); sizeLabel?.stringValue=String(format:"%.0f pt",prefs.fontSize); refresh() }
    @objc func colorChanged(_ s:NSColorWell) { prefs.setColor(s.color,key:s.tag==0 ? "color":"accent"); refresh() }
    func positionDescription() -> String {
        let value=Int(prefs.horizontalOffset)
        return value == 0 ? "整条中点" : "\(value < 0 ? "左移" : "右移") \(abs(value))"
    }
    @objc func positionChanged(_ s:NSSlider) {
        prefs.horizontalOffset=s.doubleValue.rounded(); positionLabel?.stringValue=positionDescription(); refresh()
    }
    @objc func resetPosition() {
        prefs.horizontalOffset=0; positionSlider?.doubleValue=0; positionLabel?.stringValue=positionDescription(); refresh()
    }
    func leadDescription() -> String { String(format:"%@ %+.1f 秒",model.hasWordTiming ? "逐字":"逐句",model.lead) }
    @objc func leadChanged(_ s:NSSlider) {
        let value=(s.doubleValue*10).rounded()/10
        if model.hasWordTiming { prefs.wordLead=value } else { prefs.lead=value }
        leadLabel?.stringValue=leadDescription(); refresh()
    }
    @objc func controlsChanged(_ s:NSButton) { prefs.controls=s.state == .on; refresh() }
    @objc func scrollChanged(_ s:NSButton) { prefs.scroll=s.state == .on; refresh() }
    @objc func fillDurationChanged(_ s:NSSlider) {
        prefs.maxFillDuration=(s.doubleValue*2).rounded()/2
        fillDurationLabel?.stringValue=String(format:"最多 %.1f 秒",prefs.maxFillDuration); refresh()
    }
    @objc func progressChanged(_ s:NSButton) { prefs.lineProgress=s.state == .on; refresh() }
    @objc func estimateChanged(_ s:NSButton) { prefs.estimateProgress=s.state == .on; refresh() }
    @objc func slideChanged(_ s:NSButton) { prefs.slideLyrics=s.state == .on; refresh() }
    @objc func desktopChanged(_ s:NSButton) { prefs.desktop=s.state == .on; updateOverlay() }
    @objc func loginChanged(_ s:NSButton) {
        do { if s.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { s.state=SMAppService.mainApp.status == .enabled ? .on:.off; message("登录启动设置未完成：\(error.localizedDescription)") }
    }
    func updateOverlay() {
        if !prefs.desktop { overlay?.orderOut(nil); return }
        if overlay==nil {
            let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:720,height:46),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.level = .floating; panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]; panel.ignoresMouseEvents=true; panel.isOpaque=false; panel.backgroundColor = .clear; panel.hasShadow=true
            panel.contentView=overlayView
            if let screen=NSScreen.main { panel.setFrameOrigin(NSPoint(x:screen.visibleFrame.midX-360,y:screen.visibleFrame.minY+40)) }
            overlay=panel
        }
        overlay?.orderFrontRegardless()
    }
}

@main struct Main {
    static func main() {
        let app=NSApplication.shared
        if let id=Bundle.main.bundleIdentifier,NSRunningApplication.runningApplications(withBundleIdentifier:id).count>1 { return }
        app.setActivationPolicy(.accessory)
        let delegate=AppDelegate(); app.delegate=delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
