import AppKit
import CoreGraphics
import Carbon
import ApplicationServices

let moonlightID = "com.moonlight-stream.Moonlight"
let stopNotification = Notification.Name("de.mlemors.Moonlight4K.stop")
let returnNotification = Notification.Name("de.mlemors.Moonlight4K.return")
let resolutionNotification = Notification.Name("de.mlemors.Moonlight4K.resolution")
let endStreamNotification = Notification.Name("de.mlemors.Moonlight4K.endStream")
let mainWindowNotification = Notification.Name("de.mlemors.Moonlight4K.mainWindow")
let permissionNotification = Notification.Name("de.mlemors.Moonlight4K.requestShortcutPermission")

func makeMenuIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
        NSColor.black.setStroke()
        NSColor.black.setFill()
        let frame = NSBezierPath(roundedRect: NSRect(x: 1, y: 2, width: 18, height: 14),
                                 xRadius: 2.2, yRadius: 2.2)
        frame.lineWidth = 1.6
        frame.stroke()

        // Crescent inside the screen. Clip the cutout to the outer disk so
        // the icon remains a clean alpha template in both menu-bar appearances.
        NSGraphicsContext.saveGraphicsState()
        let crescent = NSBezierPath(ovalIn: NSRect(x: 5.6, y: 4.6, width: 8.8, height: 8.8))
        crescent.addClip()
        crescent.append(NSBezierPath(ovalIn: NSRect(x: 8.1, y: 7.0, width: 8.35, height: 8.35)))
        crescent.windingRule = .evenOdd
        crescent.fill()
        NSGraphicsContext.restoreGraphicsState()
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "MoonDock"
    return image
}

func sideButtonMouseEvent(keyCode: Int64, type: CGEventType, location: CGPoint, flags: CGEventFlags) -> CGEvent? {
    let buttonNumber: Int64
    switch keyCode {
    case Int64(kVK_F13): buttonNumber = 3
    case Int64(kVK_F14): buttonNumber = 4
    default: return nil
    }
    guard type == .keyDown || type == .keyUp else { return nil }
    let mouseType: CGEventType = type == .keyDown ? .otherMouseDown : .otherMouseUp
    guard let event = CGEvent(mouseEventSource: nil, mouseType: mouseType,
        mouseCursorPosition: location, mouseButton: CGMouseButton(rawValue: UInt32(buttonNumber))!) else { return nil }
    event.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
    event.setIntegerValueField(.mouseEventClickState, value: 1)
    event.flags = flags
    return event
}

func runningMoonlight() -> [NSRunningApplication] {
    NSRunningApplication.runningApplications(withBundleIdentifier: moonlightID).filter { !$0.isTerminated }
}

func moonlightIsStreaming(_ app: NSRunningApplication) -> Bool {
    func inspect(_ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        } catch { return "" }
    }
    let pid = String(app.processIdentifier)
    // Main-window discovery only binds mDNS sockets. Connected UDP sockets
    // belong to the streaming transport; no keyboard or mouse input is read.
    let sockets = inspect(["-nP", "-a", "-p", pid, "-iUDP", "-Fn"])
    if sockets.split(separator: "\n").contains(where: { $0.hasPrefix("n") && $0.contains("->") }) { return true }
    // The process-owned log also distinguishes live streams from the main UI,
    // including transports whose UDP sockets are unconnected.
    let files = inspect(["-nP", "-p", pid, "-Fn"])
    for line in files.split(separator: "\n") where line.hasPrefix("n/") {
        let url = URL(fileURLWithPath: String(line.dropFirst()))
        guard url.lastPathComponent.hasPrefix("Moonlight-"), url.pathExtension == "log",
              let handle = try? FileHandle(forReadingFrom: url) else { continue }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { continue }
        try? handle.seek(toOffset: size > 262144 ? size - 262144 : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        let log = String(decoding: data, as: UTF8.self)
        let start = log.range(of: "Starting video stream...", options: .backwards)
            ?? log.range(of: "Initializing video stream...", options: .backwards)
        let stop = log.range(of: "Stopping video stream...", options: .backwards)
            ?? log.range(of: "Cleaning up video stream...", options: .backwards)
        if let start = start, stop == nil || start.lowerBound > stop!.lowerBound { return true }
    }
    // When the stream state cannot be established, favor raising the existing
    // app rather than closing a window unnecessarily.
    return false
}

func describe(_ mode: CGDisplayMode) -> [String: Any] {
    ["width": mode.width, "height": mode.height, "pixelWidth": mode.pixelWidth,
     "pixelHeight": mode.pixelHeight, "hz": mode.refreshRate, "modeID": mode.ioDisplayModeID]
}

func displayPlan() throws -> (CGDirectDisplayID, CGDisplayMode, CGDisplayMode) {
    let display = CGMainDisplayID()
    guard CGDisplayIsBuiltin(display) == 0 else {
        throw NSError(domain: "Moonlight4K", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "Bitte den externen 4K-Monitor als Hauptbildschirm verwenden. Das MacBook-Display wird nicht umgestellt."])
    }
    guard let original = CGDisplayCopyDisplayMode(display),
          let modes = CGDisplayCopyAllDisplayModes(display,
            [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary) as? [CGDisplayMode],
          let native = modes.first(where: {
              $0.width == 3840 && $0.height == 2160 && $0.pixelWidth == 3840 && $0.pixelHeight == 2160
                  && abs($0.refreshRate - 120) < 1
          }) else {
        throw NSError(domain: "Moonlight4K", code: 2, userInfo: [NSLocalizedDescriptionKey:
            "Auf dem Hauptbildschirm ist natives 4K bei 120 Hz nicht verfügbar. Es wurde nichts umgestellt."])
    }
    return (display, original, native)
}

struct ResolutionChoice {
    let key: String
    let title: String
    let mode: CGDisplayMode
}

func resolutionChoices(for display: CGDirectDisplayID) -> [ResolutionChoice] {
    let modes = CGDisplayCopyAllDisplayModes(display,
        [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary) as? [CGDisplayMode] ?? []
    let at120 = modes.filter { abs($0.refreshRate - 120) < 1 }
    var result: [ResolutionChoice] = []
    if let standard = at120.first(where: { $0.width == 2560 && $0.height == 1440
        && $0.pixelWidth == 5120 && $0.pixelHeight == 2880 }) {
        result.append(ResolutionChoice(key: "hidpi:2560x1440",
            title: "Standard – 2560 × 1440 (HiDPI)", mode: standard))
    }
    if let native = at120.first(where: { $0.width == 3840 && $0.height == 2160
        && $0.pixelWidth == 3840 && $0.pixelHeight == 2160 }) {
        result.append(ResolutionChoice(key: "native4k", title: "4K nativ – 3840 × 2160", mode: native))
    }
    for width in [1920, 2048, 2304, 3008, 3200, 3360] {
        if let mode = at120.first(where: { $0.width == width && $0.height * 16 == width * 9
            && $0.pixelWidth == width * 2 && $0.pixelHeight == $0.height * 2 }) {
            result.append(ResolutionChoice(key: "hidpi:\(mode.width)x\(mode.height)",
                title: "\(mode.width) × \(mode.height) – HiDPI", mode: mode))
        }
    }
    return result
}

func sameMode(_ a: CGDisplayMode, _ b: CGDisplayMode) -> Bool {
    a.width == b.width && a.height == b.height && a.pixelWidth == b.pixelWidth
        && a.pixelHeight == b.pixelHeight && abs(a.refreshRate - b.refreshRate) < 1
}

func apply(_ mode: CGDisplayMode, to display: CGDirectDisplayID) throws {
    var config: CGDisplayConfigRef?
    let start = CGBeginDisplayConfiguration(&config)
    guard start == .success, let config = config else {
        throw NSError(domain: "Moonlight4K", code: Int(start.rawValue),
            userInfo: [NSLocalizedDescriptionKey: "Die Anzeige-Konfiguration konnte nicht geöffnet werden."])
    }
    let result = CGConfigureDisplayWithDisplayMode(config, display, mode, nil)
    guard result == .success else {
        CGCancelDisplayConfiguration(config)
        throw NSError(domain: "Moonlight4K", code: Int(result.rawValue),
            userInfo: [NSLocalizedDescriptionKey: "Der Anzeigemodus konnte nicht eingestellt werden."])
    }
    // Menu changes belong to this launcher. macOS also rolls them back
    // if this process crashes; startup itself never changes the display.
    let completed = CGCompleteDisplayConfiguration(config, .forAppOnly)
    guard completed == .success else {
        throw NSError(domain: "Moonlight4K", code: Int(completed.rawValue),
            userInfo: [NSLocalizedDescriptionKey: "macOS hat den Anzeigewechsel abgelehnt."])
    }
}

if CommandLine.arguments.contains("--inspect") {
    do {
        let (display, original, native) = try displayPlan()
        let data = try JSONSerialization.data(withJSONObject:
            ["display": display, "current": describe(original), "target": describe(native),
             "moonlightRunning": !runningMoonlight().isEmpty,
             "frontmostBundle": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""], options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        exit(0)
    } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--list-resolutions") {
    let modes = resolutionChoices(for: CGMainDisplayID()).map { choice -> [String: Any] in
        ["key": choice.key, "title": choice.title, "mode": describe(choice.mode)]
    }
    let data = try JSONSerialization.data(withJSONObject: modes, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--resolution"), index + 1 < CommandLine.arguments.count {
    let key = CommandLine.arguments[index + 1]
    guard resolutionChoices(for: CGMainDisplayID()).contains(where: { $0.key == key }) else {
        fputs("Dieser HiDPI-/4K-Modus ist nicht verfügbar.\n", stderr); exit(1)
    }
    DistributedNotificationCenter.default().postNotificationName(resolutionNotification, object: key,
        userInfo: nil, deliverImmediately: true)
    exit(0)
}
if CommandLine.arguments.contains("--stop") {
    DistributedNotificationCenter.default().postNotificationName(stopNotification, object: nil,
        userInfo: nil, deliverImmediately: true)
    exit(0)
}
if CommandLine.arguments.contains("--return") {
    DistributedNotificationCenter.default().postNotificationName(returnNotification, object: nil,
        userInfo: nil, deliverImmediately: true)
    exit(0)
}
if CommandLine.arguments.contains("--moonlight-state") {
    for app in runningMoonlight() {
        print("pid=\(app.processIdentifier) streaming=\(moonlightIsStreaming(app)) hidden=\(app.isHidden)")
    }
    exit(0)
}
if CommandLine.arguments.contains("--end-stream") {
    DistributedNotificationCenter.default().postNotificationName(endStreamNotification, object: nil,
        userInfo: nil, deliverImmediately: true)
    exit(0)
}
if CommandLine.arguments.contains("--main-window") {
    DistributedNotificationCenter.default().postNotificationName(mainWindowNotification, object: nil,
        userInfo: nil, deliverImmediately: true)
    exit(0)
}
if CommandLine.arguments.contains("--hotkey-status") {
    print("Last Option-Command-Tab registration status: \(UserDefaults.standard.integer(forKey: "returnHotKeyStatus"))")
    print("Pre-capture shortcut filter ready: \(UserDefaults.standard.bool(forKey: "shortcutFilterReady"))")
    exit(0)
}
if CommandLine.arguments.contains("--request-shortcut-permission") {
    DistributedNotificationCenter.default().postNotificationName(permissionNotification, object: nil,
        userInfo: nil, deliverImmediately: true)
    exit(0)
}

final class Launcher: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var item: NSStatusItem?
    var timer: Timer?
    var display: CGDirectDisplayID?
    var initialMode: CGDisplayMode?
    var didChangeResolution = false
    var displayUUID: CFUUID?
    var finishing = false
    var stopping = false
    var launching = false
    var returningToMain = false
    var mainWindowOpening = false
    var pendingResolutionKey: String?
    var resolutionApplying = false
    var resolutionMenu: NSMenu?
    var openMenuItem: NSMenuItem?
    var endStreamMenuItem: NSMenuItem?
    var returnHotKey: EventHotKeyRef?
    var returnEventHandler: EventHandlerRef?
    var previousMacApp: NSRunningApplication?
    var shortcutTap: CFMachPort?
    var shortcutTapSource: CFRunLoopSource?
    var moonlightFocused = false
    var focusedMoonlightPID: pid_t?
    var heldSideButtonKeys: [Int64: pid_t] = [:]
    var swallowTabUp = false
    var nextPermissionCheck = Date.distantPast

    func message(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title; alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        previousMacApp = NSWorkspace.shared.frontmostApplication
        // Never reconfigure while Moonlight already owns a window or a stream.
        if let existing = runningMoonlight().first {
            existing.activate(options: [.activateAllWindows])
            message("Moonlight läuft bereits", "Beende Moonlight vollständig und öffne dann MoonDock erneut. Während einer laufenden Sitzung wird die Anzeige nicht umgestellt.")
            NSApp.terminate(nil); return
        }
        do {
            let (id, before, _) = try displayPlan()
            initialMode = before
            display = id; displayUUID = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
        } catch {
            message("MoonDock konnte nicht starten", error.localizedDescription)
            NSApp.terminate(nil); return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item?.button?.title = ""
        item?.button?.image = makeMenuIcon()
        item?.button?.imagePosition = .imageOnly
        item?.button?.imageScaling = .scaleProportionallyDown
        item?.button?.setAccessibilityLabel("MoonDock")
        item?.button?.toolTip = "MoonDock – manuelle Auflösungswahl wird beim Beenden zurückgesetzt"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        let settings = NSMenuItem(title: "Moonlight öffnen", action: #selector(showMainWindow), keyEquivalent: "")
        settings.target = self; menu.addItem(settings)
        openMenuItem = settings
        let endStream = NSMenuItem(title: "Stream beenden", action: #selector(endCurrentStream), keyEquivalent: "")
        endStream.target = self
        endStream.isEnabled = false
        endStream.toolTip = "Stream trennen und das Hauptfenster öffnen. MoonDock und die aktuelle Mac-Auflösung bleiben erhalten."
        endStreamMenuItem = endStream
        menu.addItem(endStream)
        menu.addItem(.separator())
        let resolutions = NSMenuItem(title: "Mac-Auflösung", action: nil, keyEquivalent: "")
        let choicesMenu = NSMenu(title: "Mac-Auflösung")
        choicesMenu.autoenablesItems = false
        choicesMenu.delegate = self
        if let display = display {
            for (index, choice) in resolutionChoices(for: display).enumerated() {
                if index > 0 && choice.key.hasPrefix("hidpi:") && choice.key != "hidpi:2560x1440"
                    && !choicesMenu.items.contains(where: { $0.isSeparatorItem }) {
                    choicesMenu.addItem(.separator())
                }
                let option = NSMenuItem(title: choice.title, action: #selector(selectResolution(_:)), keyEquivalent: "")
                option.target = self
                option.representedObject = choice.key
                option.toolTip = "120 Hz. Mac-Oberfläche: \(choice.mode.width) × \(choice.mode.height); intern gerendert: \(choice.mode.pixelWidth) × \(choice.mode.pixelHeight). Der Stream wird vor dem Wechsel getrennt."
                choicesMenu.addItem(option)
            }
        }
        resolutions.submenu = choicesMenu
        resolutionMenu = choicesMenu
        menu.addItem(resolutions)
        refreshResolutionMenu()
        menu.addItem(.separator())
        let stop = NSMenuItem(title: "MoonDock beenden", action: #selector(stopMoonlight), keyEquivalent: "")
        stop.target = self
        stop.toolTip = "Moonlight und MoonDock schließen und eine im Menü geänderte Mac-Auflösung zurückstellen."
        menu.addItem(stop)
        item?.menu = menu
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(stopMoonlight),
            name: stopNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(returnToMac),
            name: returnNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(requestShortcutPermission),
            name: permissionNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showMainWindow),
            name: mainWindowNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(requestResolution(_:)),
            name: resolutionNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(endCurrentStream),
            name: endStreamNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(moonlightTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        let frontmost = NSWorkspace.shared.frontmostApplication
        moonlightFocused = frontmost?.bundleIdentifier == moonlightID
        focusedMoonlightPID = moonlightFocused ? frontmost?.processIdentifier : nil
        registerReturnShortcut()
        installShortcutFilter()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.check() }
        launching = true
        // Start Moonlight after the launcher menu is ready; keep the current display mode.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self, !self.finishing else { return }
            if let index = CommandLine.arguments.firstIndex(of: "--desktop"), index + 1 < CommandLine.arguments.count {
                let host = CommandLine.arguments[index + 1]
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/Applications/Moonlight.app/Contents/MacOS/Moonlight")
                process.arguments = ["stream", host, "Desktop"]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do { try process.run(); self.launching = false }
                catch {
                    self.launching = false
                    self.message("Moonlight konnte nicht geöffnet werden", error.localizedDescription)

                }
                return
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Moonlight.app"),
                configuration: config) { [weak self] app, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.launching = false
                    if let error = error {
                        self.message("Moonlight konnte nicht geöffnet werden", error.localizedDescription)

                    }
                }
            }
        }
    }

    @objc func showMoonlight() {
        runningMoonlight().first?.activate(options: [.activateAllWindows])
    }

    func registerReturnShortcut() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let install = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event = event, let userData = userData else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard result == noErr, key.signature == 0x4D4C344B, key.id == 1 else { return OSStatus(eventNotHandledErr) }
            Unmanaged<Launcher>.fromOpaque(userData).takeUnretainedValue().returnToMac()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &returnEventHandler)
        guard install == noErr else {
            UserDefaults.standard.set(Int(install), forKey: "returnHotKeyStatus")
            message("Rückweg zum Mac", "Die Tastenkombination konnte nicht eingerichtet werden. Das 4K-Menü bleibt verfügbar.")
            return
        }
        let result = RegisterEventHotKey(UInt32(kVK_Tab), UInt32(cmdKey | optionKey),
            EventHotKeyID(signature: 0x4D4C344B, id: 1), GetApplicationEventTarget(), 0, &returnHotKey)
        UserDefaults.standard.set(Int(result), forKey: "returnHotKeyStatus")
        if result != noErr {
            message("Rückweg zum Mac", "⌥⌘Tab konnte nicht registriert werden (Code \(result)). Du kannst weiterhin das 4K-Menü verwenden.")
        }
    }

    @objc func returnToMac() {
        for app in runningMoonlight() { _ = app.hide() }
        if let previous = previousMacApp, !previous.isTerminated,
           previous.bundleIdentifier != moonlightID, previous.bundleIdentifier != Bundle.main.bundleIdentifier {
            previous.activate(options: [.activateAllWindows])
        } else {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?
                .activate(options: [.activateAllWindows])
        }
    }

    func releaseSideButtons() {
        let location = CGEvent(source: nil)?.location ?? .zero
        for (key, pid) in heldSideButtonKeys {
            sideButtonMouseEvent(keyCode: key, type: .keyUp, location: location, flags: [])?.postToPid(pid)
        }
        heldSideButtonKeys.removeAll()
    }

    func forwardSideButton(_ event: CGEvent, type: CGEventType, key: Int64) -> Bool {
        if type == .keyUp, let pid = heldSideButtonKeys.removeValue(forKey: key) {
            sideButtonMouseEvent(keyCode: key, type: type, location: event.location, flags: event.flags)?.postToPid(pid)
            return true
        }
        guard type == .keyDown, moonlightFocused, let pid = focusedMoonlightPID else { return false }
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            guard let mouse = sideButtonMouseEvent(keyCode: key, type: type, location: event.location, flags: event.flags) else { return false }
            heldSideButtonKeys[key] = pid
            // Target only Moonlight. Other mouse utilities keep normal scrolling.
            mouse.postToPid(pid)
        }
        return true
    }

    @objc func activeAppChanged(_ notification: Notification) {
        let active = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let isMoonlight = active?.bundleIdentifier == moonlightID
        if !isMoonlight { releaseSideButtons() }
        moonlightFocused = isMoonlight
        focusedMoonlightPID = isMoonlight ? active?.processIdentifier : nil
    }

    @objc func requestShortcutPermission() {
        // Standard macOS consent request. No permission database is modified.
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func installShortcutFilter() {
        UserDefaults.standard.set(false, forKey: "shortcutFilterReady")
        guard AXIsProcessTrusted() else { return }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        shortcutTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, userData in
                guard let userData = userData else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<Launcher>.fromOpaque(userData).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = owner.shortcutTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                // Only Tab and the two reserved side-button keys are handled.
                // No typed text or input history is retained.
                let key = event.getIntegerValueField(.keyboardEventKeycode)
                if key == Int64(kVK_F13) || key == Int64(kVK_F14) {
                    return owner.forwardSideButton(event, type: type, key: key) ? nil : Unmanaged.passUnretained(event)
                }
                guard key == Int64(kVK_Tab) else { return Unmanaged.passUnretained(event) }
                if type == .keyUp && owner.swallowTabUp {
                    owner.swallowTabUp = false
                    return nil
                }
                let flags = event.flags
                if type == .keyDown && owner.moonlightFocused && flags.contains(.maskCommand)
                    && flags.contains(.maskAlternate) && !flags.contains(.maskControl) && !flags.contains(.maskShift) {
                    owner.swallowTabUp = true
                    if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                        DispatchQueue.main.async { owner.returnToMac() }
                    }
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap = shortcutTap else { return }
        shortcutTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = shortcutTapSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            UserDefaults.standard.set(true, forKey: "shortcutFilterReady")
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshResolutionMenu()
        refreshWorkflowMenu()
    }

    func refreshWorkflowMenu() {
        let streaming = runningMoonlight().contains(where: { moonlightIsStreaming($0) })
        let available = !returningToMain && !stopping && !finishing && !launching
        openMenuItem?.title = streaming ? "Stream anzeigen" : "Moonlight öffnen"
        openMenuItem?.isEnabled = available
        endStreamMenuItem?.isEnabled = available && streaming
    }

    func refreshResolutionMenu() {
        guard let display = display, let current = CGDisplayCopyDisplayMode(display), let menu = resolutionMenu else { return }
        let choices = resolutionChoices(for: display)
        for option in menu.items {
            guard let key = option.representedObject as? String,
                  let choice = choices.first(where: { $0.key == key }) else { continue }
            option.state = sameMode(current, choice.mode) ? .on : .off
            option.isEnabled = !returningToMain && !stopping && !finishing
        }
    }

    @objc func selectResolution(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        beginResolutionChange(key)
    }

    @objc func requestResolution(_ notification: Notification) {
        guard let key = notification.object as? String else { return }
        beginResolutionChange(key)
    }

    func beginResolutionChange(_ key: String) {
        guard !finishing, !stopping, !returningToMain, let display = display,
              let choice = resolutionChoices(for: display).first(where: { $0.key == key }),
              let current = CGDisplayCopyDisplayMode(display) else { return }
        if sameMode(current, choice.mode) { refreshResolutionMenu(); return }
        pendingResolutionKey = key
        UserDefaults.standard.removeObject(forKey: "lastResolutionError")
        prepareMainWindow()
        refreshResolutionMenu()
    }

    func applyPendingResolution() {
        guard !resolutionApplying, let key = pendingResolutionKey else { return }
        resolutionApplying = true
        pendingResolutionKey = nil
        // Allow Moonlight's GPU resources to settle after its process exits.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self, self.returningToMain, !self.stopping, !self.finishing else { return }
            do {
                guard runningMoonlight().isEmpty, let display = self.display,
                      CGDisplayIsOnline(display) != 0, let savedUUID = self.displayUUID,
                      let currentUUID = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue(),
                      CFEqual(savedUUID, currentUUID),
                      let choice = resolutionChoices(for: display).first(where: { $0.key == key }) else {
                    throw NSError(domain: "Moonlight4K", code: 3, userInfo: [NSLocalizedDescriptionKey:
                        "Die Anzeige oder die Moonlight-Sitzung hat sich geändert. Die Auflösung wurde nicht umgestellt."])
                }
                try apply(choice.mode, to: display)
                self.didChangeResolution = true
                guard let current = CGDisplayCopyDisplayMode(display), sameMode(current, choice.mode) else {
                    throw NSError(domain: "Moonlight4K", code: 4, userInfo: [NSLocalizedDescriptionKey:
                        "macOS hat den gewünschten Anzeigemodus nicht bestätigt."])
                }
                UserDefaults.standard.set(key, forKey: "lastResolutionSelection")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self = self, self.returningToMain, !self.stopping, !self.finishing else { return }
                    self.resolutionApplying = false
                    self.openMainWindow()
                }
            } catch {
                self.resolutionApplying = false
                UserDefaults.standard.set(error.localizedDescription, forKey: "lastResolutionError")
                self.message("Mac-Auflösung", error.localizedDescription)
                self.openMainWindow()
            }
        }
    }

    @objc func showMainWindow() {
        guard !finishing, !stopping, !returningToMain else { return }
        if let stream = runningMoonlight().first(where: { moonlightIsStreaming($0) }) {
            // Opening/showing is non-destructive. Disconnecting has its own action.
            _ = stream.unhide()
            stream.activate(options: [.activateAllWindows])
            return
        }
        prepareMainWindow()
    }

    @objc func endCurrentStream() {
        guard !finishing, !stopping, !returningToMain,
              runningMoonlight().contains(where: { moonlightIsStreaming($0) }) else { return }
        prepareMainWindow()
    }

    func prepareMainWindow() {
        guard !finishing, !stopping, !returningToMain else { return }
        returningToMain = true
        UserDefaults.standard.set(false, forKey: "mainWindowOpened")
        let apps = runningMoonlight()
        if apps.isEmpty {
            if pendingResolutionKey != nil { applyPendingResolution() } else { openMainWindow() }
            return
        }
        if pendingResolutionKey == nil && !apps.contains(where: { moonlightIsStreaming($0) }) {
            // Reuse an already open main window, including a hidden or covered app.
            apps.forEach { _ = $0.unhide(); $0.activate(options: [.activateAllWindows]) }
            openMainWindow()
            return
        }
        // A live stream (or an explicit display-mode change) must end first.
        // End only the local client, never the remote Windows application.
        apps.forEach { _ = $0.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self, self.returningToMain else { return }
            for app in apps where !app.isTerminated { _ = app.forceTerminate() }
        }
    }

    func openMainWindow() {
        guard returningToMain, !mainWindowOpening, !finishing, !stopping else { return }
        mainWindowOpening = true
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        // A fresh normal launch shows Moonlight's settings-capable main window,
        // including when this launcher originally started a stream via --desktop.
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Moonlight.app"),
            configuration: config) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.mainWindowOpening = false
                self.returningToMain = false
                self.refreshResolutionMenu()
                if self.stopping || self.finishing {
                    if let app = app {
                        _ = app.terminate()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if !app.isTerminated { _ = app.forceTerminate() } }
                    }
                    return
                }
                if let error = error {
                    self.message("Moonlight-Hauptfenster", error.localizedDescription)

                } else if let app = app {
                    _ = app.unhide()
                    app.activate(options: [.activateAllWindows])
                    if AXIsProcessTrusted() {
                        let element = AXUIElementCreateApplication(app.processIdentifier)
                        var value: CFTypeRef?
                        if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
                           let windows = value as? [AXUIElement] {
                            for window in windows {
                                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                            }
                        }
                    }
                    UserDefaults.standard.set(true, forKey: "mainWindowOpened")
                }
            }
        }
    }

    @objc func stopMoonlight() {
        guard !stopping else { return }
        stopping = true
        releaseSideButtons()
        returningToMain = false
        pendingResolutionKey = nil
        let apps = runningMoonlight()
        if apps.isEmpty { if !mainWindowOpening { finish() }; return }
        apps.forEach { _ = $0.terminate() }
        // Qt may refuse a normal quit while a stream owns the keyboard. The user
        // explicitly selected full termination. Only the same Moonlight PIDs are targeted.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            for app in apps where !app.isTerminated { _ = app.forceTerminate() }
        }
    }

    @objc func moonlightTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == moonlightID else { return }
        // Closing Moonlight leaves MoonDock available for reopening it.
        // Only an explicit stop request closes this menu-bar companion.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.finishing else { return }
            if self.returningToMain { self.check(); return }
            if self.stopping && !self.launching && !self.mainWindowOpening && runningMoonlight().isEmpty { self.finish() }
        }
    }

    func check() {
        guard !finishing else { return }
        if shortcutTap == nil && Date() >= nextPermissionCheck {
            nextPermissionCheck = Date().addingTimeInterval(5)
            installShortcutFilter()
        }
        if returningToMain {
            if runningMoonlight().isEmpty && !resolutionApplying {
                if pendingResolutionKey != nil { applyPendingResolution() }
                else { openMainWindow() }
            }
            return
        }
        if stopping && !launching && !mainWindowOpening && runningMoonlight().isEmpty {
            // Fallback for a missed workspace event, without an additional delay.
            finish()
        }
    }

    func finish() {
        guard !finishing, runningMoonlight().isEmpty else { return }
        finishing = true; timer?.invalidate()
        // Only undo changes made through this launcher's resolution menu.
        if didChangeResolution, let id = display, CGDisplayIsOnline(id) != 0,
           let before = initialMode, let saved = displayUUID,
           let currentUUID = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
           CFEqual(saved, currentUUID) {
            if let current = CGDisplayCopyDisplayMode(id), !sameMode(current, before) {
                do { try apply(before, to: id) }
                catch { message("Anzeige zurückstellen", "macOS übernimmt beim Beenden die Wiederherstellung der temporären Auflösungswahl.\n\n" + error.localizedDescription) }
            }
        }
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !runningMoonlight().isEmpty && display != nil && !finishing {
            stopMoonlight(); return .terminateCancel
        }
        return .terminateNow
    }
}

let application = NSApplication.shared
let delegate = Launcher()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
