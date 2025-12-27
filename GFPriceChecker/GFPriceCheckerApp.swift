//
//  GFPriceCheckerApp.swift
//  GFPriceChecker
//
//  Created by Curtis Williams on 2025-12-27.
//

import SwiftUI
import SwiftData

@main
struct GFPriceCheckerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            ProductPair.self
        ])
    }
}
