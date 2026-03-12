//
//  TypetexApp.swift
//  Typetex
//

import SwiftUI
import SwiftData

@main
struct TypetexApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([LaTeXDocument.self, LaTeXWorkspace.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        // If schema migration fails (e.g. after renaming models), wipe and recreate the store.
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return container
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeDir = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Typetex")
        try? FileManager.default.removeItem(at: storeDir)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)

#if os(macOS)
        Settings {
            SettingsView()
        }
#endif
    }
}
