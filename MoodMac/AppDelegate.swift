//
//  AppDelegate.swift
//  MoodMac
//
//  Created by Vivek Krishnan on 12/03/26.
//
import AppKit
import SwiftUI
import Combine

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var activityMonitor: ActivityMonitor?
    private var moodEngine: MoodEngine?
    private var iconUpdateTimer: Timer?
    private var animationPhase: Int = 0
    private var cancellables = Set<AnyCancellable>()

    // Persisted toggle: show mood text label next to icon
    var showMoodText: Bool = false {
        didSet {
            UserDefaults.standard.set(showMoodText, forKey: "showMoodText")
            refreshIcon()
            // NOTE: do NOT rebuild popover here — causes cursor/focus chaos
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showMoodText = UserDefaults.standard.bool(forKey: "showMoodText")
        if !ActivityMonitor.checkAccessibilityPermission() {
            showAccessibilityAlert()
        }
        setupEngine()
        setupStatusItem()
        setupPopover()
        setupIconAnimation()
    }

    // MARK: - Setup

    private func setupEngine() {
        activityMonitor = ActivityMonitor()
        moodEngine = MoodEngine()
        moodEngine?.activityMonitor = activityMonitor
        moodEngine?.$currentMood
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.action = #selector(togglePopover)
            button.target = self
            button.imagePosition = .imageLeft
        }
        refreshIcon()
    }

    func setupPopover() {
        guard let engine = moodEngine, let monitor = activityMonitor else { return }
        let wasShown = popover?.isShown ?? false
        popover?.close()
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 520)
        popover?.behavior = .transient
        popover?.animates = true
        popover?.contentViewController = NSHostingController(
            rootView: MoodPanelView(engine: engine, monitor: monitor, appDelegate: self)
        )
        if wasShown, let button = statusItem?.button {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func setupIconAnimation() {
        // Update every 0.5s for smooth animation
        iconUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.animationPhase = (self.animationPhase + 1) % 20
            self.refreshIcon()
        }
    }

    // MARK: - Icon Rendering

    func refreshIcon() {
        guard let mood = moodEngine?.currentMood,
              let button = statusItem?.button else { return }

        let phase = animationPhase
        let pulse = (sin(Double(phase) * .pi / 10.0) + 1.0) / 2.0

        let brainImage = renderBrainIcon(mood: mood, pulse: pulse)
        brainImage.isTemplate = false

        DispatchQueue.main.async {
            if self.showMoodText {
                // Combine brain + pill into one single image — avoids all title/attributed hacks
                let combined = self.renderCombinedBarImage(mood: mood, pulse: pulse)
                combined.isTemplate = false
                button.image = combined
                button.title = ""
                button.attributedTitle = NSAttributedString(string: "")
                button.imagePosition = .imageOnly
            } else {
                button.image = brainImage
                button.title = ""
                button.attributedTitle = NSAttributedString(string: "")
                button.imagePosition = .imageOnly
            }
        }
    }

    // MARK: - Combined brain + Dynamic Island pill image

    private func renderCombinedBarImage(mood: MoodState, pulse: Double) -> NSImage {
        let label: String
        switch mood {
        case .deepFocus:  label = "⚡ Focus"
        case .normalFlow: label = "😊 Flow"
        case .distracted: label = "✳︎ Dizzy"
        case .overloaded: label = "🔥 Stressed"
        case .idle:       label = "💤 Rest"
        }

        // Measure text size
        let font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        let textAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let textSize = (label as NSString).size(withAttributes: textAttrs)

        let pillPadH: CGFloat = 10   // horizontal padding inside pill
        let pillPadV: CGFloat = 2
        let pillW = textSize.width + pillPadH * 2
        let pillH: CGFloat = 20
        let brainW: CGFloat = 26
        let gap: CGFloat = 4
        let totalW = brainW + gap + pillW
        let totalH: CGFloat = 22

        let scale: CGFloat = 2.0
        let drawSize = NSSize(width: totalW * scale, height: totalH * scale)

        let image = NSImage(size: drawSize, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.scaleBy(x: scale, y: scale)

            // --- Draw brain on the left ---
            let brainImage = self.renderBrainIcon(mood: mood, pulse: pulse)
            let brainRect = NSRect(x: 0, y: (totalH - 22) / 2, width: 26, height: 22)
            brainImage.draw(in: brainRect)

            // --- Draw capsule pill on the right ---
            let pillX = brainW + gap
            let pillY = (totalH - pillH) / 2
            let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
            let cornerRadius = pillH / 2   // full pill = height/2 corner radius

            let moodColor = mood.nsColor
            let bgAlpha = CGFloat(0.82 + pulse * 0.12)

            // Pill background (true capsule)
            let pillPath = CGPath(roundedRect: pillRect,
                                  cornerWidth: cornerRadius,
                                  cornerHeight: cornerRadius,
                                  transform: nil)
            ctx.setFillColor(moodColor.withAlphaComponent(bgAlpha).cgColor)
            ctx.addPath(pillPath)
            ctx.fillPath()

            // Subtle inner highlight at top edge
            let highlightRect = CGRect(x: pillX + 2, y: pillY + pillH * 0.62,
                                       width: pillW - 4, height: pillH * 0.28)
            let highlightPath = CGPath(roundedRect: highlightRect,
                                       cornerWidth: highlightRect.height / 2,
                                       cornerHeight: highlightRect.height / 2,
                                       transform: nil)
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.18).cgColor)
            ctx.addPath(highlightPath)
            ctx.fillPath()

            // Draw text centered in pill
            let textX = pillX + (pillW - textSize.width) / 2
            let textY = pillY + (pillH - textSize.height) / 2 + pillPadV * 0.3
            NSGraphicsContext.current?.saveGraphicsState()
            (label as NSString).draw(at: CGPoint(x: textX, y: textY), withAttributes: textAttrs)
            NSGraphicsContext.current?.restoreGraphicsState()

            ctx.restoreGState()
            return true
        }

        image.size = NSSize(width: totalW, height: totalH)
        return image
    }

    // MARK: - Brain Icon Renderer

    private func renderBrainIcon(mood: MoodState, pulse: Double) -> NSImage {
        // Draw at 2× for Retina, display at 1×
        let logicalSize = NSSize(width: 26, height: 22)
        let scale: CGFloat = 2.0
        let drawSize = NSSize(width: logicalSize.width * scale, height: logicalSize.height * scale)

        let image = NSImage(size: drawSize, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.scaleBy(x: scale, y: scale)

            let w = logicalSize.width
            let h = logicalSize.height
            let moodColor = mood.nsColor

            // Outer glow for focus / overload
            if mood == .deepFocus || mood == .overloaded {
                let blur = CGFloat(2.0 + pulse * 4.0)
                ctx.setShadow(offset: .zero, blur: blur,
                              color: moodColor.withAlphaComponent(0.80).cgColor)
            }

            // Fill the brain shape
            let alpha: CGFloat = mood == .idle ? CGFloat(0.50 + pulse * 0.30) : 0.93
            ctx.setFillColor(moodColor.withAlphaComponent(alpha).cgColor)
            let brainPath = AppDelegate.makeBrainPath(w: w, h: h)
            ctx.addPath(brainPath)
            ctx.fillPath()

            // Kill shadow before detail lines
            ctx.setShadow(offset: .zero, blur: 0, color: nil)

            // Interhemispheric fissure (center line)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.18).cgColor)
            ctx.setLineWidth(0.7)
            let fissure = CGMutablePath()
            fissure.move(to:    CGPoint(x: w * 0.50, y: h * 0.84))
            fissure.addCurve(to: CGPoint(x: w * 0.50, y: h * 0.20),
                             control1: CGPoint(x: w * 0.44, y: h * 0.64),
                             control2: CGPoint(x: w * 0.56, y: h * 0.40))
            ctx.addPath(fissure)
            ctx.strokePath()

            // Cortical sulci — left hemisphere
            Self.strokeCurve(ctx, color: NSColor.black.withAlphaComponent(0.16),
                             lw: 0.6,
                             from: CGPoint(x: w*0.14, y: h*0.55),
                             to:   CGPoint(x: w*0.36, y: h*0.44),
                             c1:   CGPoint(x: w*0.16, y: h*0.48),
                             c2:   CGPoint(x: w*0.26, y: h*0.44))
            Self.strokeCurve(ctx, color: NSColor.black.withAlphaComponent(0.14),
                             lw: 0.55,
                             from: CGPoint(x: w*0.13, y: h*0.37),
                             to:   CGPoint(x: w*0.34, y: h*0.28),
                             c1:   CGPoint(x: w*0.16, y: h*0.30),
                             c2:   CGPoint(x: w*0.26, y: h*0.27))
            Self.strokeCurve(ctx, color: NSColor.black.withAlphaComponent(0.14),
                             lw: 0.55,
                             from: CGPoint(x: w*0.17, y: h*0.68),
                             to:   CGPoint(x: w*0.38, y: h*0.62),
                             c1:   CGPoint(x: w*0.22, y: h*0.63),
                             c2:   CGPoint(x: w*0.30, y: h*0.62))

            // Cortical sulci — right hemisphere (mirror)
            Self.strokeCurve(ctx, color: NSColor.black.withAlphaComponent(0.16),
                             lw: 0.6,
                             from: CGPoint(x: w*0.86, y: h*0.55),
                             to:   CGPoint(x: w*0.64, y: h*0.44),
                             c1:   CGPoint(x: w*0.84, y: h*0.48),
                             c2:   CGPoint(x: w*0.74, y: h*0.44))
            Self.strokeCurve(ctx, color: NSColor.black.withAlphaComponent(0.14),
                             lw: 0.55,
                             from: CGPoint(x: w*0.87, y: h*0.37),
                             to:   CGPoint(x: w*0.66, y: h*0.28),
                             c1:   CGPoint(x: w*0.84, y: h*0.30),
                             c2:   CGPoint(x: w*0.74, y: h*0.27))
            Self.strokeCurve(ctx, color: NSColor.black.withAlphaComponent(0.14),
                             lw: 0.55,
                             from: CGPoint(x: w*0.83, y: h*0.68),
                             to:   CGPoint(x: w*0.62, y: h*0.62),
                             c1:   CGPoint(x: w*0.78, y: h*0.63),
                             c2:   CGPoint(x: w*0.70, y: h*0.62))

            // Mood decoration on top
            Self.drawDecoration(ctx: ctx, mood: mood, pulse: pulse, w: w, h: h)

            ctx.restoreGState()
            return true
        }

        image.size = logicalSize
        return image
    }

    // MARK: - Brain Bezier (anatomical shape)

    static func makeBrainPath(w: CGFloat, h: CGFloat) -> CGPath {
        let p = CGMutablePath()

        // Bottom center — brain stem connection
        p.move(to: CGPoint(x: w * 0.44, y: h * 0.12))

        // --- Left hemisphere ---
        // Bottom-left sweep
        p.addCurve(to: CGPoint(x: w * 0.10, y: h * 0.36),
                   control1: CGPoint(x: w * 0.22, y: h * 0.11),
                   control2: CGPoint(x: w * 0.08, y: h * 0.22))
        // Left side — parietal bulge
        p.addCurve(to: CGPoint(x: w * 0.10, y: h * 0.62),
                   control1: CGPoint(x: w * 0.04, y: h * 0.44),
                   control2: CGPoint(x: w * 0.04, y: h * 0.54))
        // Left occipital — lower back
        p.addCurve(to: CGPoint(x: w * 0.22, y: h * 0.78),
                   control1: CGPoint(x: w * 0.08, y: h * 0.70),
                   control2: CGPoint(x: w * 0.12, y: h * 0.76))
        // Left top — parietal to frontal
        p.addCurve(to: CGPoint(x: w * 0.36, y: h * 0.88),
                   control1: CGPoint(x: w * 0.28, y: h * 0.84),
                   control2: CGPoint(x: w * 0.32, y: h * 0.88))

        // Corpus callosum / bottom bridge
        p.addCurve(to: CGPoint(x: w * 0.50, y: h * 0.90),
                   control1: CGPoint(x: w * 0.40, y: h * 0.93),
                   control2: CGPoint(x: w * 0.46, y: h * 0.93))
        p.addCurve(to: CGPoint(x: w * 0.64, y: h * 0.88),
                   control1: CGPoint(x: w * 0.54, y: h * 0.93),
                   control2: CGPoint(x: w * 0.60, y: h * 0.93))

        // --- Right hemisphere (mirror) ---
        p.addCurve(to: CGPoint(x: w * 0.78, y: h * 0.78),
                   control1: CGPoint(x: w * 0.68, y: h * 0.88),
                   control2: CGPoint(x: w * 0.72, y: h * 0.84))
        p.addCurve(to: CGPoint(x: w * 0.90, y: h * 0.62),
                   control1: CGPoint(x: w * 0.88, y: h * 0.76),
                   control2: CGPoint(x: w * 0.92, y: h * 0.70))
        p.addCurve(to: CGPoint(x: w * 0.90, y: h * 0.36),
                   control1: CGPoint(x: w * 0.96, y: h * 0.54),
                   control2: CGPoint(x: w * 0.96, y: h * 0.44))
        p.addCurve(to: CGPoint(x: w * 0.56, y: h * 0.12),
                   control1: CGPoint(x: w * 0.92, y: h * 0.22),
                   control2: CGPoint(x: w * 0.78, y: h * 0.11))

        // Close at bottom center
        p.addCurve(to: CGPoint(x: w * 0.44, y: h * 0.12),
                   control1: CGPoint(x: w * 0.52, y: h * 0.08),
                   control2: CGPoint(x: w * 0.47, y: h * 0.08))
        p.closeSubpath()
        return p
    }

    // MARK: - Helper: stroke a bezier curve

    static func strokeCurve(_ ctx: CGContext, color: NSColor, lw: CGFloat,
                             from: CGPoint, to: CGPoint, c1: CGPoint, c2: CGPoint) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lw)
        let p = CGMutablePath()
        p.move(to: from)
        p.addCurve(to: to, control1: c1, control2: c2)
        ctx.addPath(p)
        ctx.strokePath()
    }

    // MARK: - Mood Decorations

    static func drawDecoration(ctx: CGContext, mood: MoodState, pulse: Double, w: CGFloat, h: CGFloat) {
        switch mood {

        case .deepFocus:
            // ⚡ Yellow lightning bolt, top-right of brain, pulses
            let alpha = CGFloat(0.80 + pulse * 0.20)
            ctx.setFillColor(NSColor(red: 1.0, green: 0.92, blue: 0.10, alpha: alpha).cgColor)
            // Add strong shadow to the bolt
            ctx.setShadow(offset: .zero, blur: CGFloat(2 + pulse * 3),
                          color: NSColor.yellow.withAlphaComponent(0.8).cgColor)
            let bolt = CGMutablePath()
            bolt.move(to:    CGPoint(x: w * 0.62, y: h * 0.88))
            bolt.addLine(to: CGPoint(x: w * 0.54, y: h * 0.60))
            bolt.addLine(to: CGPoint(x: w * 0.60, y: h * 0.58))
            bolt.addLine(to: CGPoint(x: w * 0.52, y: h * 0.32))
            bolt.addLine(to: CGPoint(x: w * 0.63, y: h * 0.58))
            bolt.addLine(to: CGPoint(x: w * 0.57, y: h * 0.60))
            bolt.closeSubpath()
            ctx.addPath(bolt)
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)

        case .normalFlow:
            // 😊 Friendly face on the brain
            // Eyes
            let eyeAlpha = CGFloat(0.82)
            ctx.setFillColor(NSColor.white.withAlphaComponent(eyeAlpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: w*0.33, y: h*0.53, width: w*0.07, height: h*0.09))
            ctx.fillEllipse(in: CGRect(x: w*0.60, y: h*0.53, width: w*0.07, height: h*0.09))
            // Smile arc
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(1.1)
            let smile = CGMutablePath()
            smile.move(to: CGPoint(x: w*0.34, y: h*0.43))
            smile.addCurve(to: CGPoint(x: w*0.66, y: h*0.43),
                           control1: CGPoint(x: w*0.40, y: h*0.34),
                           control2: CGPoint(x: w*0.60, y: h*0.34))
            ctx.addPath(smile)
            ctx.strokePath()

        case .distracted:
            // ✳︎ 4 spinning orange dots in a circle
            ctx.translateBy(x: w * 0.50, y: h * 0.54)
            let angle = CGFloat(pulse * 2.0 * .pi)
            ctx.rotate(by: angle)
            for i in 0..<4 {
                let a = CGFloat(i) * .pi / 2.0
                let r = w * 0.17
                let px = cos(a) * r
                let py = sin(a) * r
                let dotR = w * CGFloat(i % 2 == 0 ? 0.045 : 0.032)
                let c: NSColor = i % 2 == 0
                    ? NSColor(red: 1, green: 0.60, blue: 0.10, alpha: 0.92)
                    : NSColor(red: 1, green: 0.85, blue: 0.20, alpha: 0.80)
                ctx.setFillColor(c.cgColor)
                ctx.fillEllipse(in: CGRect(x: px-dotR, y: py-dotR, width: dotR*2, height: dotR*2))
            }
            // Centre
            ctx.setFillColor(NSColor.orange.withAlphaComponent(0.90).cgColor)
            ctx.fillEllipse(in: CGRect(x: -w*0.045, y: -h*0.045, width: w*0.09, height: h*0.09))

        case .overloaded:
            // 💢 Three animated steam plumes + red vein
            let rise = CGFloat(pulse * h * 0.10)
            let steamAlpha = CGFloat(0.50 + pulse * 0.40)

            let steamColumns: [(xf: Double, rf: Double)] = [(0.36, 0.030), (0.50, 0.040), (0.64, 0.033)]
            for (i, col) in steamColumns.enumerated() {
                let delay = CGFloat(i) * h * 0.03
                let y = h * 0.92 + rise - delay
                ctx.setFillColor(NSColor.white.withAlphaComponent(steamAlpha - CGFloat(i)*0.08).cgColor)
                ctx.fillEllipse(in: CGRect(x: w*CGFloat(col.xf) - w*CGFloat(col.rf),
                                           y: y,
                                           width: w*CGFloat(col.rf)*2,
                                           height: h * 0.10))
            }
            // Red stress flash on top
            ctx.setFillColor(NSColor(red: 1, green: 0.25, blue: 0.25,
                                     alpha: CGFloat(0.65 + pulse * 0.30)).cgColor)
            ctx.setShadow(offset: .zero, blur: CGFloat(pulse * 4),
                          color: NSColor.red.withAlphaComponent(0.6).cgColor)
            ctx.fillEllipse(in: CGRect(x: w*0.42, y: h*0.68, width: w*0.16, height: h*0.12))
            ctx.setShadow(offset: .zero, blur: 0, color: nil)

        case .idle:
            // 💤 Two floating Zs, size + position pulses
            let floatY = CGFloat(pulse * h * 0.07)
            let bigAlpha = CGFloat(0.55 + pulse * 0.40)
            let smallAlpha = CGFloat(0.35 + pulse * 0.30)
            let bigFont = NSFont.boldSystemFont(ofSize: w * 0.30)
            let smallFont = NSFont.boldSystemFont(ofSize: w * 0.20)
            NSAttributedString(string: "Z", attributes: [
                .font: bigFont,
                .foregroundColor: NSColor.white.withAlphaComponent(bigAlpha)
            ]).draw(at: CGPoint(x: w * 0.53, y: h * 0.56 + floatY))
            NSAttributedString(string: "z", attributes: [
                .font: smallFont,
                .foregroundColor: NSColor.white.withAlphaComponent(smallAlpha)
            ]).draw(at: CGPoint(x: w * 0.66, y: h * 0.66 + floatY * 0.5))
        }
    }

    // MARK: - Popover Toggle

    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Accessibility Alert

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "MoodMac needs Accessibility access to observe your typing and app switching patterns. Grant permission in System Settings › Privacy & Security › Accessibility."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}
