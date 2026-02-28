//
//  Empy_SwiftApp.swift
//  Empy_Swift
//
//  Created by Aram on 27.02.26.
//

import SwiftUI

@main
struct Empy_SwiftApp: App {
    init() {
        // Log configuration status on startup
        AppConfig.logStartupConfig()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
