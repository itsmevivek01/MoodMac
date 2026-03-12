//
//  MoodState.swift
//  MoodMac
//
//  Created by Vivek Krishnan on 12/03/26.
//
import SwiftUI

// MARK: - Mood State Model

enum MoodState: String, CaseIterable, Codable {
    case deepFocus    = "Deep Focus"
    case normalFlow   = "Normal Flow"
    case distracted   = "Distracted"
    case overloaded   = "Overloaded"
    case idle         = "Rest / Idle"
    
    var color: Color {
        switch self {
        case .deepFocus:  return Color(red: 0.2, green: 0.5, blue: 1.0)
        case .normalFlow: return Color(red: 0.2, green: 0.8, blue: 0.4)
        case .distracted: return Color(red: 1.0, green: 0.7, blue: 0.1)
        case .overloaded: return Color(red: 0.95, green: 0.2, blue: 0.2)
        case .idle:       return Color(red: 0.6, green: 0.5, blue: 0.85)
        }
    }
    
    var nsColor: NSColor {
        switch self {
        case .deepFocus:  return NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1)
        case .normalFlow: return NSColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1)
        case .distracted: return NSColor(red: 1.0, green: 0.7, blue: 0.1, alpha: 1)
        case .overloaded: return NSColor(red: 0.95, green: 0.2, blue: 0.2, alpha: 1)
        case .idle:       return NSColor(red: 0.6, green: 0.5, blue: 0.85, alpha: 1)
        }
    }
    
    var emoji: String {
        switch self {
        case .deepFocus:  return "🧠⚡"
        case .normalFlow: return "🧠😊"
        case .distracted: return "🧠✨"
        case .overloaded: return "🧠💢"
        case .idle:       return "🧠💤"
        }
    }
    
    var description: String {
        switch self {
        case .deepFocus:  return "You're locked in and crushing it!"
        case .normalFlow: return "Working steadily at a good pace."
        case .distracted: return "Jumping between tasks frequently."
        case .overloaded: return "High intensity — take a breath."
        case .idle:       return "Taking a well-deserved break."
        }
    }
    
    var iconName: String {
        switch self {
        case .deepFocus:  return "brain.deepfocus"
        case .normalFlow: return "brain.normalflow"
        case .distracted: return "brain.distracted"
        case .overloaded: return "brain.overloaded"
        case .idle:       return "brain.idle"
        }
    }
    
    // SF Symbol fallback names
    var sfSymbol: String {
        switch self {
        case .deepFocus:  return "brain.head.profile"
        case .normalFlow: return "brain"
        case .distracted: return "arrow.triangle.2.circlepath"
        case .overloaded: return "flame"
        case .idle:       return "moon.zzz"
        }
    }
}

// MARK: - Mood Snapshot for timeline

struct MoodSnapshot: Identifiable, Codable {
    let id: UUID
    let mood: MoodState
    let timestamp: Date
    let duration: TimeInterval // seconds in this state
    
    init(mood: MoodState, timestamp: Date = Date(), duration: TimeInterval = 0) {
        self.id = UUID()
        self.mood = mood
        self.timestamp = timestamp
        self.duration = duration
    }
}

// MARK: - Activity Signals

struct ActivitySignals {
    var typingRate: Double          // keystrokes per minute (requires Accessibility)
    var appSwitchRate: Double       // app switches per minute
    var mouseActivity: Double       // average mouse speed, normalized 0-1
    var mouseErratic: Double        // direction-change rate 0-1 (shaking/nervous)
    var idleSeconds: Double         // seconds since last any input
    var keystrokeVariance: Double   // typing rhythm irregularity 0-1
    var errorRate: Double           // backspace ratio 0-1

    static var zero: ActivitySignals {
        ActivitySignals(typingRate: 0, appSwitchRate: 0, mouseActivity: 0,
                        mouseErratic: 0, idleSeconds: 0, keystrokeVariance: 0, errorRate: 0)
    }
}
