//
//  MoodMacApp.swift
//  MoodMac
//
//  Created by Vivek Krishnan on 12/03/26.
//

import SwiftUI
import AppKit

@main
struct MoodMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
