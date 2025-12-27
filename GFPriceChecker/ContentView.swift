//
//  ContentView.swift
//  GFPriceChecker
//
//  Created by Curtis Williams on 2025-12-27.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Text("Capture")
                .tabItem {
                    Label("Capture", systemImage: "camera")
                }
            
            Text("Library")
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
            
            Text("Reports")
                .tabItem {
                    Label("Reports", systemImage: "chart.bar")
                }
        }
    }
}

#Preview {
    ContentView()
}
