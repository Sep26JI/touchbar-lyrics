import Cocoa
import ObjectiveC
import Darwin

// System symbol names have no suffix. LyricsX's trailing underscores belong to
// its own C wrappers, not to the symbols exported by Apple's framework.
enum DFR {
    static let handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW | RTLD_GLOBAL)
    static var available: Bool {
        handle != nil && dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier") != nil &&
        class_getClassMethod(NSTouchBar.self, NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")) != nil
    }
    static func presence(_ id: String, _ visible: Bool) {
        guard let h = handle, let symbol = dlsym(h, "DFRElementSetControlStripPresenceForIdentifier") else { return }
        typealias F = @convention(c) (NSString, Bool) -> Void
        unsafeBitCast(symbol, to: F.self)(id as NSString, visible)
    }
    static func tray(_ item: NSTouchBarItem, add: Bool) {
        let sel = NSSelectorFromString(add ? "addSystemTrayItem:" : "removeSystemTrayItem:")
        guard let method = class_getClassMethod(NSTouchBarItem.self, sel) else { return }
        typealias F = @convention(c) (AnyClass, Selector, NSTouchBarItem) -> Void
        unsafeBitCast(method_getImplementation(method), to: F.self)(NSTouchBarItem.self, sel, item)
    }
    static func present(_ bar: NSTouchBar, id: String) {
        let sel = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        guard let method = class_getClassMethod(NSTouchBar.self, sel) else { return }
        typealias F = @convention(c) (AnyClass, Selector, NSTouchBar, NSString) -> Void
        unsafeBitCast(method_getImplementation(method), to: F.self)(NSTouchBar.self, sel, bar, id as NSString)
    }
    static func dismiss(_ bar: NSTouchBar) {
        let sel = NSSelectorFromString("dismissSystemModalTouchBar:")
        guard let method = class_getClassMethod(NSTouchBar.self, sel) else { return }
        typealias F = @convention(c) (AnyClass, Selector, NSTouchBar) -> Void
        unsafeBitCast(method_getImplementation(method), to: F.self)(NSTouchBar.self, sel, bar)
    }
}
