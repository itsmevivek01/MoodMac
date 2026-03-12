//
//  BrainIconView.swift
//  MoodMac
//
//  Created by Vivek Krishnan on 12/03/26.
//

import SwiftUI
import AppKit

// MARK: - Brain Icon Views

struct BrainIconView: View {
    let mood: MoodState
    @State private var animate = false
    @State private var sparkleOffset: CGFloat = 0
    @State private var glowOpacity: Double = 0.5
    @State private var zOffset: CGFloat = 0
    @State private var steamOffset: CGFloat = 0
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        ZStack {
            switch mood {
            case .deepFocus:    DeepFocusBrain(animate: animate, glowOpacity: glowOpacity)
            case .normalFlow:   NormalFlowBrain(animate: animate)
            case .distracted:   DistractedBrain(animate: animate, rotationAngle: rotationAngle)
            case .overloaded:   OverloadedBrain(animate: animate, steamOffset: steamOffset)
            case .idle:         IdleBrain(animate: animate, zOffset: zOffset)
            }
        }
        .frame(width: 20, height: 20)
        .onAppear { startAnimations() }
        .onChange(of: mood) { _ in startAnimations() }
    }
    
    private func startAnimations() {
        animate = false
        glowOpacity = 0.5
        
        switch mood {
        case .deepFocus:
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                animate = true
                glowOpacity = 1.0
            }
        case .normalFlow:
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                animate = true
            }
        case .distracted:
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        case .overloaded:
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                animate = true
                steamOffset = -4
            }
        case .idle:
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                zOffset = -3
            }
        }
    }
}

// MARK: - Deep Focus Brain (Blue + lightning)
struct DeepFocusBrain: View {
    let animate: Bool
    let glowOpacity: Double
    let color = Color(red: 0.2, green: 0.5, blue: 1.0)
    
    var body: some View {
        ZStack {
            // Glow
            Image(systemName: "brain.head.profile")
                .resizable()
                .scaledToFit()
                .foregroundColor(color)
                .opacity(animate ? 0.4 : 0.1)
                .blur(radius: 3)
                .scaleEffect(animate ? 1.15 : 1.0)
            
            // Brain
            Image(systemName: "brain.head.profile")
                .resizable()
                .scaledToFit()
                .foregroundColor(color)
            
            // Lightning bolt
            Image(systemName: "bolt.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 6, height: 8)
                .foregroundColor(.yellow)
                .offset(x: 7, y: -6)
                .opacity(animate ? 1.0 : 0.3)
        }
    }
}

// MARK: - Normal Flow Brain (Green + smile)
struct NormalFlowBrain: View {
    let animate: Bool
    let color = Color(red: 0.2, green: 0.8, blue: 0.4)
    
    var body: some View {
        ZStack {
            Image(systemName: "brain.head.profile")
                .resizable()
                .scaledToFit()
                .foregroundColor(color)
                .scaleEffect(animate ? 1.05 : 1.0)
            
            // Smile indicator
            Image(systemName: "face.smiling")
                .resizable()
                .scaledToFit()
                .frame(width: 7, height: 7)
                .foregroundColor(color.opacity(0.9))
                .offset(x: 6, y: 5)
        }
    }
}

// MARK: - Distracted Brain (Yellow + spinning stars)
struct DistractedBrain: View {
    let animate: Bool
    let rotationAngle: Double
    let color = Color(red: 1.0, green: 0.75, blue: 0.1)
    
    var body: some View {
        ZStack {
            Image(systemName: "brain.head.profile")
                .resizable()
                .scaledToFit()
                .foregroundColor(color)
            
            // Spinning star
            Image(systemName: "sparkle")
                .resizable()
                .scaledToFit()
                .frame(width: 6, height: 6)
                .foregroundColor(.orange)
                .rotationEffect(.degrees(rotationAngle))
                .offset(x: 6, y: -6)
            
            Image(systemName: "sparkle")
                .resizable()
                .scaledToFit()
                .frame(width: 4, height: 4)
                .foregroundColor(.yellow)
                .rotationEffect(.degrees(-rotationAngle))
                .offset(x: -7, y: 5)
        }
    }
}

// MARK: - Overloaded Brain (Red + steam)
struct OverloadedBrain: View {
    let animate: Bool
    let steamOffset: CGFloat
    let color = Color(red: 0.95, green: 0.2, blue: 0.2)
    
    var body: some View {
        ZStack {
            // Pulse glow
            Image(systemName: "brain.head.profile")
                .resizable()
                .scaledToFit()
                .foregroundColor(color)
                .opacity(animate ? 0.3 : 0.0)
                .blur(radius: 2)
                .scaleEffect(animate ? 1.2 : 1.0)
            
            Image(systemName: "brain.head.profile")
                .resizable()
                .scaledToFit()
                .foregroundColor(color)
            
            // Steam lines
            VStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: 2, height: 4)
                    .foregroundColor(Color.orange.opacity(0.8))
                    .offset(y: steamOffset)
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: 2, height: 3)
                    .foregroundColor(Color.red.opacity(0.6))
                    .offset(y: steamOffset * 0.7)
            }
            .offset(x: 3, y: -8)
        }
    }
}

// MARK: - Idle Brain (Purple + floating Z)
struct IdleBrain: View {
    let animate: Bool
    let zOffset: CGFloat
    let color = Color(red: 0.6, green: 0.5, blue: 0.85)
    
    var body: some View {
        ZStack {
            Image(systemName: "brain.head.profile")
                .resizable()
                .scaledToFit()
                .foregroundColor(color)
                .opacity(0.7)
            
            // Floating Z
            Text("z")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(color)
                .offset(x: 6, y: zOffset - 5)
                .opacity(0.9)
            
            Text("z")
                .font(.system(size: 5, weight: .medium))
                .foregroundColor(color.opacity(0.6))
                .offset(x: 9, y: zOffset - 9)
        }
    }
}

// MARK: - NSImage generator for menu bar

class BrainIconRenderer {
    
    static func makeMenuBarImage(for mood: MoodState, size: CGSize = CGSize(width: 18, height: 18)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }
        
        let color = mood.nsColor
        ctx.setFillColor(color.cgColor)
        ctx.setStrokeColor(color.cgColor)
        
        // Draw a stylized brain shape using bezier
        drawBrainShape(ctx: ctx, bounds: CGRect(origin: .zero, size: size), color: color, mood: mood)
        
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
    
    private static func drawBrainShape(ctx: CGContext, bounds: CGRect, color: NSColor, mood: MoodState) {
        let w = bounds.width
        let h = bounds.height
        
        ctx.saveGState()
        
        // Brain silhouette - simplified bezier path
        let path = CGMutablePath()
        path.move(to: CGPoint(x: w*0.5, y: h*0.15))
        path.addCurve(to: CGPoint(x: w*0.85, y: h*0.4),
                     control1: CGPoint(x: w*0.75, y: h*0.1),
                     control2: CGPoint(x: w*0.95, y: h*0.25))
        path.addCurve(to: CGPoint(x: w*0.75, y: h*0.75),
                     control1: CGPoint(x: w*0.95, y: h*0.55),
                     control2: CGPoint(x: w*0.9, y: h*0.65))
        path.addCurve(to: CGPoint(x: w*0.5, y: h*0.85),
                     control1: CGPoint(x: w*0.6, y: h*0.85),
                     control2: CGPoint(x: w*0.55, y: h*0.85))
        path.addCurve(to: CGPoint(x: w*0.25, y: h*0.75),
                     control1: CGPoint(x: w*0.45, y: h*0.85),
                     control2: CGPoint(x: w*0.35, y: h*0.82))
        path.addCurve(to: CGPoint(x: w*0.15, y: h*0.4),
                     control1: CGPoint(x: w*0.1, y: h*0.65),
                     control2: CGPoint(x: w*0.05, y: h*0.55))
        path.addCurve(to: CGPoint(x: w*0.5, y: h*0.15),
                     control1: CGPoint(x: w*0.05, y: h*0.25),
                     control2: CGPoint(x: w*0.25, y: h*0.1))
        path.closeSubpath()
        
        // Fill with mood color
        ctx.setFillColor(color.withAlphaComponent(0.9).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        
        // Draw decorative element based on mood
        switch mood {
        case .deepFocus:
            // Lightning bolt
            ctx.setFillColor(NSColor.yellow.withAlphaComponent(0.9).cgColor)
            let bolt = CGMutablePath()
            bolt.move(to: CGPoint(x: w*0.65, y: h*0.25))
            bolt.addLine(to: CGPoint(x: w*0.55, y: h*0.5))
            bolt.addLine(to: CGPoint(x: w*0.65, y: h*0.5))
            bolt.addLine(to: CGPoint(x: w*0.5, y: h*0.75))
            bolt.addLine(to: CGPoint(x: w*0.6, y: h*0.52))
            bolt.addLine(to: CGPoint(x: w*0.5, y: h*0.52))
            bolt.closeSubpath()
            ctx.addPath(bolt)
            ctx.fillPath()
            
        case .normalFlow:
            // Smile arc
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(1.0)
            ctx.addArc(center: CGPoint(x: w*0.5, y: h*0.55),
                      radius: w*0.15, startAngle: 0.2, endAngle: CGFloat.pi - 0.2, clockwise: false)
            ctx.strokePath()
            
        case .distracted:
            // X mark or swirl
            ctx.setStrokeColor(NSColor.orange.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: w*0.38, y: h*0.38))
            ctx.addLine(to: CGPoint(x: w*0.62, y: h*0.62))
            ctx.move(to: CGPoint(x: w*0.62, y: h*0.38))
            ctx.addLine(to: CGPoint(x: w*0.38, y: h*0.62))
            ctx.strokePath()
            
        case .overloaded:
            // Stress lines
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
            ctx.setLineWidth(1.0)
            for i in 0..<3 {
                let xOff = CGFloat(i) * w * 0.12 + w * 0.3
                ctx.move(to: CGPoint(x: xOff, y: h*0.18))
                ctx.addLine(to: CGPoint(x: xOff + w*0.04, y: h*0.08))
            }
            ctx.strokePath()
            
        case .idle:
            // Z letter
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 6),
                .foregroundColor: NSColor.white.withAlphaComponent(0.8)
            ]
            let zStr = NSAttributedString(string: "z", attributes: attrs)
            zStr.draw(at: CGPoint(x: w*0.62, y: h*0.18))
        }
        
        ctx.restoreGState()
    }
}
