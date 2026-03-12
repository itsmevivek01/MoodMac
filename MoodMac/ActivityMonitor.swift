//
//  ActivityMonitor.swift
//  MoodMac
//
//  Created by Vivek Krishnan on 12/03/26.
//
import AppKit
import Foundation
import Combine
import CoreGraphics

// MARK: - ActivityMonitor
//
// LESSONS FROM LOGS:
//
// 1. Virtual-position shake (accumulating deltaX/Y) produces near-zero values
//    because OS-smoothed deltas are tiny — dropping it entirely.
//
// 2. Mouse SPEED (event rate) IS the reliable signal:
//    - Idle/reading:       0–15 events/sec  → 0–25%
//    - Normal work:        15–30 events/sec → 25–50%
//    - Fast movement:      30–50 events/sec → 50–83%
//    - Vigorous shaking:   50–80 events/sec → 83–100%
//    Speed alone distinguishes calm from frantic mouse use.
//    We report it as BOTH mouseActivity AND mouseErratic so the engine
//    can use it for shake detection directly.
//
// 3. Typing normalization: use 60kpm as 100% (normal fast typing).
//    Previous 120kpm ceiling meant even 100kpm only showed as 83%.
//
// 4. Keyboard: CGEvent tap needs Accessibility. Without it (ax=✗),
//    only local monitor works (keys while MoodMac is frontmost).
//    We display ax status clearly and still count what we can.

class ActivityMonitor: ObservableObject {

    @Published var signals: ActivitySignals = .zero
    @Published var currentApp: String = ""
    @Published var hasAccessibility: Bool = false

    private let q = DispatchQueue(label: "com.moodmac.monitor", qos: .userInteractive)

    private var _keyTimes:    [Date] = []
    private var _bsTimes:     [Date] = []
    private var _switchTimes: [Date] = []
    private var _mouseEvents: [Date] = []   // movement events — count = speed
    private var _clickEvents: [Date] = []   // click events — rapid clicking = distracted
    private var _lastInputTime: Date = Date()

    private var _kbTap:    CFMachPort?
    private var _kbSrc:    CFRunLoopSource?
    private var _mouseMon: Any?
    private var _appObs:   NSObjectProtocol?
    private var _timer:    Timer?

    private let signalWindow: TimeInterval = 12.0  // full window once warmed up
    private let mouseWindow:  TimeInterval = 3.0
    private let pruneAge:     TimeInterval = 60.0
    private let launchTime:   Date = Date()         // used to warm up window size

    init() {
        hasAccessibility = AXIsProcessTrusted()
        setupKeyboardTap()
        setupMouseMonitor()
        setupAppObserver()
        _timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.compute()
        }
    }

    deinit {
        if let t = _kbTap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = _kbSrc { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        if let m = _mouseMon { NSEvent.removeMonitor(m) }
        if let o = _appObs   { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        _timer?.invalidate()
    }

    // MARK: - Keyboard tap

    private func setupKeyboardTap() {
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask,
            callback: { (_, _, cgEvent, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(cgEvent) }
                let self_ = Unmanaged<ActivityMonitor>.fromOpaque(refcon).takeUnretainedValue()
                let now = Date()
                let kc  = cgEvent.getIntegerValueField(.keyboardEventKeycode)
                let del = kc == 51 || kc == 117
                self_.q.async {
                    self_._keyTimes.append(now)
                    self_._lastInputTime = now
                    if del { self_._bsTimes.append(now) }
                }
                return Unmanaged.passUnretained(cgEvent)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) {
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            _kbTap = tap; _kbSrc = src
        } else {
            // Fallback: only catches keys when MoodMac panel is frontmost
            NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] ev in
                guard let self = self else { return }
                let now = Date(); let del = ev.keyCode == 51 || ev.keyCode == 117
                self.q.async {
                    self._keyTimes.append(now); self._lastInputTime = now
                    if del { self._bsTimes.append(now) }
                }
            }
        }
        // Always add local monitor (catches keys when MoodMac popover is open)
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] ev in
            guard let self = self else { return ev }
            let now = Date(); let del = ev.keyCode == 51 || ev.keyCode == 117
            self.q.async {
                self._keyTimes.append(now); self._lastInputTime = now
                if del { self._bsTimes.append(now) }
            }
            return ev
        }
    }

    // MARK: - Mouse monitor (event count = speed signal)

    private func setupMouseMonitor() {
        // Movement events
        _mouseMon = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] ev in
            guard let self = self else { return }
            let dx = Double(ev.deltaX); let dy = Double(ev.deltaY)
            guard abs(dx) + abs(dy) > 0.3 else { return }
            let now = Date()
            self.q.async {
                self._mouseEvents.append(now)
                self._lastInputTime = now
            }
        }
        // Click events — count as mouse activity too.
        // Rapid clicking (e.g. frantically clicking a frozen app) boosts the signal.
        // Each click is worth 3 movement events so even click-only activity registers.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            let now = Date()
            self.q.async {
                // Add 3 synthetic movement timestamps per click to boost event rate
                self._mouseEvents.append(now)
                self._mouseEvents.append(now)
                self._mouseEvents.append(now)
                self._clickEvents.append(now)
                self._lastInputTime = now
            }
        }
    }

    // MARK: - App observer

    private func setupAppObserver() {
        _appObs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            let now  = Date()
            let name = (note.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication)?.localizedName ?? ""
            self.q.async { self._switchTimes.append(now); self._lastInputTime = now }
            if !name.isEmpty { self.currentApp = name }
        }
        currentApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
    }

    // MARK: - Compute (every 2s)

    private func compute() {
        let ax = AXIsProcessTrusted()

        q.async { [weak self] in
            guard let self = self else { return }
            let now = Date()
            self.pruneBuffers(now: now)

            // Warm-up window: grows from 2s → 12s over the first 12s after launch.
            // Prevents the "all zeros" period at startup — first eval uses last 2s
            // of data (which exists immediately) rather than an empty 12s window.
            let age = now.timeIntervalSince(self.launchTime)
            let effectiveWindow = min(self.signalWindow, max(2.0, age))

            // ── Typing rate ───────────────────────────────────────────────────
            // Normalize against 60 kpm = 1.0 (normal productive typing speed)
            // 20kpm = 0.33 (light typing), 60kpm = 1.0, 90kpm+ = capped at 1.0
            let keys   = self._keyTimes.filter { now.timeIntervalSince($0) <= effectiveWindow }
            let kpm    = Double(keys.count) * (60.0 / effectiveWindow)
            let typing = min(1.0, kpm / 60.0)

            // ── Switch rate ───────────────────────────────────────────────────
            // Normalize against 10/min = 1.0
            // 1 switch in 12s = 5/min = 0.5, 2 switches = 10/min = 1.0
            let sws      = self._switchTimes.filter { now.timeIntervalSince($0) <= effectiveWindow }
            let swPM     = Double(sws.count) * (60.0 / effectiveWindow)
            let swRate   = min(1.0, swPM / 10.0)

            // ── Mouse speed ───────────────────────────────────────────────────
            // Events per second in the 3s window, normalized against 60/s
            // From logs: vigorous shaking = 50–80 events/sec (spd 83–100%)
            // Normal movement = 15–30 events/sec (spd 25–50%)
            // This IS the shake signal — high speed = fast erratic movement
            let mEvts    = self._mouseEvents.filter { now.timeIntervalSince($0) <= self.mouseWindow }
            let evtRate  = Double(mEvts.count) / self.mouseWindow
            let mouseSpd = min(1.0, evtRate / 60.0)

            // ── Idle ──────────────────────────────────────────────────────────
            let idle = now.timeIntervalSince(self._lastInputTime)

            // ── Keystroke variance ────────────────────────────────────────────
            let vari = self.computeVariance(timestamps: keys)

            // ── Error rate ────────────────────────────────────────────────────
            let bs      = self._bsTimes.filter { now.timeIntervalSince($0) <= effectiveWindow }
            let errRate = keys.isEmpty ? 0.0 : min(1.0, Double(bs.count) / Double(keys.count))

            // mouseActivity = overall speed (0–1)
            // mouseErratic  = fraction of events that are truly vigorous (above 47/s threshold)
            //                  This makes it meaningfully different from speed in the panel:
            //                  slow movement → speed 20%, erratic 0%
            //                  fast smooth   → speed 80%, erratic 60%
            //                  vigorous shake→ speed 95%, erratic 90%+
            let vigorousThreshold = 47.0  // mirrors engine shakeThreshold 0.78 × 60/s
            // erratic = how much of the current rate exceeds the vigorous floor
            let mouseErratic = evtRate <= vigorousThreshold ? 0.0
                             : min(1.0, (evtRate - vigorousThreshold) / (60.0 - vigorousThreshold))

            let clicks   = self._clickEvents.filter { now.timeIntervalSince($0) <= self.mouseWindow }

            print(String(format:
                "[MM] typing=%.0fkpm(%.0f%%) sw=%.1f/m(%.0f%%) | mouse=%.0f/s spd=%.0f%% erratic=%.0f%% clicks=%d | idle=%.0fs ax=%@",
                kpm, typing*100, swPM, swRate*100, evtRate, mouseSpd*100, mouseErratic*100, clicks.count, idle, ax ? "✓" : "✗"))

            let sig = ActivitySignals(
                typingRate:        typing,
                appSwitchRate:     swRate,
                mouseActivity:     mouseSpd,
                mouseErratic:      mouseErratic,  // now distinct: only vigorous-excess fraction
                idleSeconds:       idle,
                keystrokeVariance: vari,
                errorRate:         errRate
            )
            DispatchQueue.main.async {
                self.signals          = sig
                self.hasAccessibility = ax
            }
        }
    }

    private func computeVariance(timestamps: [Date]) -> Double {
        guard timestamps.count >= 5 else { return 0.2 }
        let s  = timestamps.sorted()
        let iv = zip(s, s.dropFirst()).map { $1.timeIntervalSince($0) }
        let m  = iv.reduce(0, +) / Double(iv.count)
        guard m > 0 else { return 0 }
        return min(1.0, sqrt(iv.map { pow($0-m, 2) }.reduce(0, +) / Double(iv.count)) / m)
    }

    private func pruneBuffers(now: Date) {
        let c = now.addingTimeInterval(-pruneAge)
        _keyTimes    = _keyTimes.filter    { $0 > c }
        _bsTimes     = _bsTimes.filter     { $0 > c }
        _switchTimes = _switchTimes.filter { $0 > c }
        _mouseEvents = _mouseEvents.filter { $0 > c }
        _clickEvents = _clickEvents.filter { $0 > c }
    }

    static func checkAccessibilityPermission() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }
}
