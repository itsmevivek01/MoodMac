//
//  MoodEngine.swift
//  MoodMac
//
//  Created by Vivek Krishnan on 12/03/26.
//

import Foundation
import Combine

// MARK: - MoodEngine
//
// CALIBRATED from real log values:
//
//   Mouse speed during vigorous shaking: 83–100% (50–80 events/sec)
//   Mouse speed during normal movement:  25–50% (15–30 events/sec)
//   Typing at 60kpm = 100% (after fixing normalization)
//   App switching: 1 switch in 12s = 5/min = 50%
//
// DESIGN: No complex scoring formulas. Direct thresholds + shake accumulator.
// The accumulator is what makes shake-based modes feel natural —
// brief mouse movement doesn't trigger, but sustained shaking does.
//
// MODES:
//   REST        idle >= 90s
//   DEEP FOCUS  typing >= 33% (20kpm) AND switches < 20% (2/min) — sustained
//   DISTRACTED  (shakeSecs >= 5s)  OR  (switches >= 50% = 5/min)
//   OVERLOADED  (shakeSecs >= 12s) OR  (switches >= 80% = 8/min)
//               OR (typing >= 80% AND mouse >= 50% simultaneously)
//   NORMAL FLOW everything else

class MoodEngine: ObservableObject {

    @Published private(set) var currentMood:       MoodState = .normalFlow
    @Published private(set) var previousMood:       MoodState = .normalFlow
    @Published private(set) var focusStreakMinutes: Int = 0
    @Published private(set) var moodHistory:        [MoodSnapshot] = []
    @Published private(set) var stateStartTime:     Date = Date()
    @Published private(set) var debugScores:        [MoodState: Double] = [:]
    @Published private(set) var candidateMood:      MoodState = .normalFlow
    @Published private(set) var candidateCount:     Int = 0

    weak var activityMonitor: ActivityMonitor?

    // Shake accumulator — counts seconds where mouse speed is TRULY HIGH
    // Threshold: 0.78 = 47 events/sec
    // From logs: normal fast movement = 39–70% (24–42/s), vigorous shaking = 80–100% (48–60/s)
    // Raising from 0.60 to 0.78 means only real vigorous movement accumulates shake
    // Capped at 20s so drain time stays predictable (max ~7s to clear after stopping)
    private var shakeSecs: Double = 0
    private let shakeThreshold: Double = 0.78
    private let shakeMax: Double = 20.0

    // Confirmation: 2 × 2s = 4s. Prevents single-eval spikes from switching mode.
    private let confirmNeeded = 2

    private var evalTimer:   Timer?
    private var streakTimer: Timer?
    private var focusStart:  Date?

    init() {
        evalTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        streakTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.updateStreak()
        }
        loadHistory()
    }

    deinit { evalTimer?.invalidate(); streakTimer?.invalidate() }

    // MARK: - Evaluate

    private func evaluate() {
        guard let mon = activityMonitor else { return }
        let s = mon.signals

        // Update shake accumulator
        // Accumulates while mouse is moving fast, capped at shakeMax
        // Drains faster than it builds — and much faster if typing resumes
        // (typing = focused work, so shake context is no longer relevant)
        if s.mouseActivity >= shakeThreshold {
            shakeSecs = min(shakeMax, shakeSecs + 2.0)
        } else if s.typingRate >= 0.33 {
            // Actively typing: drain shake quickly — you're back in focus
            shakeSecs = max(0, shakeSecs - 6.0)
        } else {
            shakeSecs = max(0, shakeSecs - 3.0)  // normal drain
        }

        let proposed = decide(s)

        if proposed == candidateMood {
            candidateCount += 1
        } else {
            candidateMood  = proposed
            candidateCount = 1
        }

        let cc = candidateCount; let cm = candidateMood
        DispatchQueue.main.async { self.candidateCount = cc; self.candidateMood = cm }

        if candidateCount >= confirmNeeded, proposed != currentMood {
            transition(to: proposed)
        }

        print(String(format:
            "[Engine] shake=%.0fs T=%.0f%% SW=%.0f%% M=%.0f%% → %@ [%d/%d]",
            shakeSecs, s.typingRate*100, s.appSwitchRate*100, s.mouseActivity*100,
            proposed.rawValue, candidateCount, confirmNeeded))
    }

    // MARK: - Decision (direct, readable, no opaque scoring)

    private func decide(_ s: ActivitySignals) -> MoodState {

        // 1. REST
        if s.idleSeconds >= 90 { shakeSecs = 0; return .idle }

        // 2. OVERLOADED — requires COMBINATION of signals, never a single one alone:
        //    a) Very long vigorous shaking (18s+, no typing) — e.g. app totally frozen
        //    b) Typing hard AND moving mouse a lot simultaneously — frantic multitasking
        //    c) Frequent app switching AND mouse activity together — chaotic switching
        //    NOTE: app switching alone does NOT cause overload (log showed this was wrong)
        let longShakeOverload  = shakeSecs >= 18 && s.typingRate < 0.20
        let franticCombo       = s.typingRate >= 0.80 && s.mouseActivity >= 0.60
        let chaoticSwitch      = s.appSwitchRate >= 0.80 && s.mouseActivity >= 0.40
        if longShakeOverload                             { return .overloaded }
        if franticCombo                                  { return .overloaded }
        if chaoticSwitch                                 { return .overloaded }

        // 3. DISTRACTED — one of these single signals is enough:
        //    a) Sustained vigorous mouse for 10s+ without typing — nervous energy
        //       (threshold 0.78 means only real fast shaking counts, not browsing)
        //    b) Frequent app switching alone (5+ per min = 50%+ normalized)
        let pureShakeDistract = shakeSecs >= 10 && s.typingRate < 0.15
        if pureShakeDistract                             { return .distracted }
        if s.appSwitchRate >= 0.50                       { return .distracted }

        // 4. DEEP FOCUS — typing steadily + staying in one app
        //    typing >= 33% means ~20kpm (light but consistent typing)
        //    Switch rate < 20% means < 2 switches/min (very stable)
        if s.typingRate >= 0.33 && s.appSwitchRate < 0.20 { return .deepFocus }

        // 5. NORMAL FLOW — default
        return .normalFlow
    }

    // MARK: - Transition

    private func transition(to mood: MoodState) {
        guard mood != currentMood else { return }
        let dur  = Date().timeIntervalSince(stateStartTime)
        let snap = MoodSnapshot(mood: currentMood, timestamp: stateStartTime, duration: dur)
        DispatchQueue.main.async {
            self.moodHistory.append(snap)
            if self.moodHistory.count > 300 { self.moodHistory.removeFirst() }
            self.previousMood   = self.currentMood
            self.currentMood    = mood
            self.stateStartTime = Date()
            self.candidateCount = 0
            self.saveHistory()
        }
        if mood == .deepFocus {
            if focusStart == nil { focusStart = Date() }
        } else if [MoodState.idle, .distracted, .overloaded].contains(mood) {
            focusStart = nil
            DispatchQueue.main.async { self.focusStreakMinutes = 0 }
        }
        let dbg: [MoodState: Double] = [
            .deepFocus: mood == .deepFocus  ? 1 : 0,
            .normalFlow: mood == .normalFlow ? 1 : 0,
            .distracted: mood == .distracted ? 1 : 0,
            .overloaded: mood == .overloaded ? 1 : 0,
            .idle:       mood == .idle       ? 1 : 0,
        ]
        DispatchQueue.main.async { self.debugScores = dbg }
        print("[Engine] ✓ → \(mood.rawValue)  (shake=\(Int(shakeSecs))s)")
    }

    // MARK: - Streak

    private func updateStreak() {
        guard currentMood == .deepFocus || currentMood == .normalFlow else { return }
        if focusStart == nil { focusStart = Date() }
        DispatchQueue.main.async {
            self.focusStreakMinutes = Int(Date().timeIntervalSince(self.focusStart!) / 60)
        }
    }

    // MARK: - History

    func todayHistory() -> [MoodSnapshot] {
        let start = Calendar.current.startOfDay(for: Date())
        return moodHistory.filter { $0.timestamp >= start }
    }

    private var historyURL: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let a = d.appendingPathComponent("MoodMac")
        try? FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        return a.appendingPathComponent("history.json")
    }
    private func saveHistory() {
        if let d = try? JSONEncoder().encode(moodHistory) { try? d.write(to: historyURL) }
    }
    private func loadHistory() {
        guard let d = try? Data(contentsOf: historyURL),
              let h = try? JSONDecoder().decode([MoodSnapshot].self, from: d) else { return }
        let start = Calendar.current.startOfDay(for: Date())
        moodHistory = h.filter { $0.timestamp >= start }
    }
}
