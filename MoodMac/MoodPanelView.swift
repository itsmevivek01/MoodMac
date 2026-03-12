//
//  MoosPanelView.swift
//  MoodMac
//
//  Created by Vivek Krishnan on 12/03/26.
//
import SwiftUI

// MARK: - Main Dropdown Panel

struct MoodPanelView: View {
    @ObservedObject var engine: MoodEngine
    @ObservedObject var monitor: ActivityMonitor
    weak var appDelegate: AppDelegate?

    // Mirror the AppDelegate toggle locally for SwiftUI binding
    @State private var showMoodText: Bool = false
    @State private var animateBrain = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider().padding(.horizontal, 16)
            streakSection
            Divider().padding(.horizontal, 16)
            signalsSection
            Divider().padding(.horizontal, 16)
            timelineSection
            Divider().padding(.horizontal, 16)
            toggleSection
            Divider().padding(.horizontal, 16)
            footerSection
        }
        .frame(width: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            showMoodText = appDelegate?.showMoodText ?? false
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(engine.currentMood.color.opacity(0.15))
                    .frame(width: 54, height: 54)
                    .scaleEffect(animateBrain ? 1.09 : 1.0)
                BrainIconView(mood: engine.currentMood)
                    .frame(width: 34, height: 34)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    animateBrain = true
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Current State")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Text(engine.currentMood.rawValue)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(engine.currentMood.color)
                Text(engine.currentMood.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Focus Streak

    private var streakSection: some View {
        HStack {
            Image(systemName: "flame.fill")
                .foregroundColor(.orange)
                .font(.system(size: 13))
            Text("Focus streak:")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text(formatStreak(engine.focusStreakMinutes))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(engine.currentMood.color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Activity Signals

    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Accessibility warning
            if !monitor.hasAccessibility {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text("Accessibility off — typing won't be detected")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
                .padding(6)
                .background(Color.orange.opacity(0.10))
                .cornerRadius(6)
            }

            Text("Live Signals (12s window)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.bottom, 2)

            // Show actual numbers so you can see what's being measured
            SignalRow(icon: "keyboard",
                      label: "Typing",
                      value: String(format: "%.0f kpm", monitor.signals.typingRate * 60.0),
                      intensity: min(1.0, monitor.signals.typingRate / 120.0),
                      color: .blue)

            SignalRow(icon: "arrow.left.arrow.right",
                      label: "Switching",
                      value: String(format: "%.1f /min", monitor.signals.appSwitchRate * 10.0),
                      intensity: min(1.0, monitor.signals.appSwitchRate / 6.0),
                      color: .orange)

            SignalRow(icon: "cursorarrow.motionlines",
                      label: "Mouse speed",
                      value: String(format: "%.0f%%", monitor.signals.mouseActivity * 100),
                      intensity: monitor.signals.mouseActivity,
                      color: .purple)

            SignalRow(icon: "arrow.triangle.2.circlepath",
                      label: "Mouse erratic",
                      value: String(format: "%.0f%%", monitor.signals.mouseErratic * 100),
                      intensity: monitor.signals.mouseErratic,
                      color: .orange)

            HStack {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                Text("Idle:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                let idle = monitor.signals.idleSeconds
                Text(idle < 60 ? String(format: "%.0fs", idle) : String(format: "%.0fm", idle/60))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(idle > 60 ? .purple : .secondary)
            }

            if !monitor.currentApp.isEmpty {
                HStack {
                    Image(systemName: "app.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    Text("App:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(monitor.currentApp)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            // Mood score bars — shows exactly why current mood was chosen
            if !engine.debugScores.isEmpty {
                Divider()
                HStack {
                    Text("Mood Scores")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    // Show when engine is confirming a candidate change
                    if engine.candidateMood != engine.currentMood {
                        Text("→ \(engine.candidateMood.rawValue) (\(engine.candidateCount)/3)")
                            .font(.system(size: 9))
                            .foregroundColor(engine.candidateMood.color)
                    }
                }
                ForEach(MoodState.allCases.filter { $0 != .idle }, id: \.self) { state in
                    let s = engine.debugScores[state] ?? 0
                    HStack(spacing: 8) {
                        Circle()
                            .fill(state.color)
                            .frame(width: 8, height: 8)
                        Text(state.rawValue)
                            .font(.system(size: 11))
                            .foregroundColor(state == engine.currentMood ? state.color : .secondary)
                            .frame(width: 78, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.secondary.opacity(0.12))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(state.color.opacity(0.75))
                                    .frame(width: geo.size.width * CGFloat(s))
                                    .animation(.easeInOut(duration: 0.4), value: s)
                            }
                        }
                        .frame(height: 5)
                        Text(String(format: "%.0f%%", s * 100))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(state.color)
                            .frame(width: 35, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Mood Timeline")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)

            MoodTimelineView(history: engine.todayHistory(), currentMood: engine.currentMood)
                .frame(height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // Legend
            HStack(spacing: 8) {
                ForEach(MoodState.allCases, id: \.self) { state in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(state.color)
                            .frame(width: 8, height: 8)
                        Text(state.rawValue.components(separatedBy: " ").first ?? "")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Dynamic Island Toggle

    private var toggleSection: some View {
        HStack(spacing: 10) {
            // Mini preview of what the pill looks like
            DynamicIslandPreview(mood: engine.currentMood, enabled: showMoodText)

            VStack(alignment: .leading, spacing: 1) {
                Text("Show mood in menu bar")
                    .font(.system(size: 12, weight: .medium))
                Text("Dynamic Island style pill with color")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $showMoodText)
                .toggleStyle(.switch)
                .scaleEffect(0.85)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // Compatible with macOS 13 and 14+
        .onChange(of: showMoodText, perform: { newVal in
            appDelegate?.showMoodText = newVal
        })
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Text("MoodMac")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func formatStreak(_ minutes: Int) -> String {
        if minutes < 1 { return "Just started" }
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    private func typingLabel(_ rate: Double) -> String {
        switch rate {
        case ..<5:  return "idle"
        case ..<30: return "light"
        case ..<60: return "steady"
        case ..<90: return "fast"
        default:    return "intense"
        }
    }

    private func switchLabel(_ rate: Double) -> String {
        switch rate {
        case ..<1:  return "low"
        case ..<3:  return "moderate"
        case ..<6:  return "high"
        default:    return "very high"
        }
    }

    private func mouseLabel(_ intensity: Double) -> String {
        switch intensity {
        case ..<0.2:  return "calm"
        case ..<0.5:  return "moderate"
        case ..<0.75: return "active"
        default:      return "rapid"
        }
    }
}

// MARK: - Dynamic Island Preview

struct DynamicIslandPreview: View {
    let mood: MoodState
    let enabled: Bool
    @State private var pulse = false

    private var label: String {
        switch mood {
        case .deepFocus:  return "⚡ Focus"
        case .normalFlow: return "😊 Flow"
        case .distracted: return "✳︎ Dizzy"
        case .overloaded: return "🔥 Stressed"
        case .idle:       return "💤 Rest"
        }
    }

    var body: some View {
        ZStack {
            // Pill background
            Capsule()
                .fill(enabled ? mood.color : Color.secondary.opacity(0.25))
                .frame(height: 20)
                .scaleEffect(pulse && enabled ? 1.04 : 1.0)

            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(enabled ? .white : .secondary)
                .padding(.horizontal, 7)
        }
        .frame(width: 80, height: 20)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .animation(.easeInOut(duration: 0.3), value: enabled)
        .animation(.easeInOut(duration: 0.3), value: mood)
    }
}

// MARK: - Signal Row

struct SignalRow: View {
    let icon: String
    let label: String
    let value: String
    let intensity: Double
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 78, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.75))
                        .frame(width: geo.size.width * CGFloat(intensity))
                        .animation(.easeInOut(duration: 0.4), value: intensity)
                }
            }
            .frame(height: 5)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
                .frame(width: 48, alignment: .trailing)
        }
    }
}

// MARK: - Mood Timeline View

struct MoodTimelineView: View {
    let history: [MoodSnapshot]
    let currentMood: MoodState

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                if history.isEmpty {
                    Capsule()
                        .fill(currentMood.color.opacity(0.8))
                        .frame(maxWidth: .infinity)
                } else {
                    let total = max(1.0, history.reduce(0.0) { $0 + $1.duration })
                    ForEach(history) { snap in
                        let frac = CGFloat(snap.duration / total)
                        Rectangle()
                            .fill(snap.mood.color.opacity(0.85))
                            .frame(width: max(2, geo.size.width * frac))
                    }
                    // Live current state — slightly brighter
                    let liveDuration = max(0, Date().timeIntervalSince(
                        (history.last?.timestamp ?? Date()).addingTimeInterval(history.last?.duration ?? 0)
                    ))
                    if liveDuration > 30 {
                        let liveFrac = CGFloat(liveDuration / (total + liveDuration))
                        Rectangle()
                            .fill(currentMood.color)
                            .frame(width: max(4, geo.size.width * liveFrac))
                            .overlay(
                                Rectangle()
                                    .fill(Color.white.opacity(0.25))
                            )
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}
