# MoodMac

A macOS menu bar app that watches your keyboard, mouse, and app-switching behaviour and predicts your current work mood in real time.

![macOS](https://img.shields.io/badge/macOS-13.5%2B-blue) 

---


MoodMac is a lightweight macOS menu bar app that tracks your work mood in real time — no camera, no microphone, no cloud. It watches how you type, move your mouse, and switch apps, then predicts whether you're focused, flowing, distracted, overloaded, or just taking a break.

The mood shows as an animated brain icon in your menu bar, updating every few seconds as you work.

<img width="307" height="614" alt="image" src="https://github.com/user-attachments/assets/486f88ec-9c97-43a6-a972-d773c4df9fd2" />


## Mood States

- **Deep Focus** — You're in the zone. Steady typing, staying in one app.
- **Normal Flow** — Balanced, productive activity.
- **Distracted** — Jumping between apps .
- **Overloaded** — Too much happening at once, or frustrated mouse shaking.
- **Rest** — No activity for a time. 


## Requirements

- macOS 12 Monterey or later
- Xcode 15+
- **Accessibility permission** — required for keyboard monitoring across all apps

## Installation

1. Clone or download the repo
2. Open `MoodMac.xcodeproj` in Xcode
3. Set your signing team under Signing & Capabilities
4. Hit **⌘R** to build and run
5. When prompted, grant Accessibility access — **System Settings → Privacy & Security → Accessibility → enable MoodMac**

> Without Accessibility, typing won't be detected in other apps. Mouse and app switching signals still work fine without it.
