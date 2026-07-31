//
//  WellSpentApp.swift
//  WellSpent
//
//  Created by Mauricio Figueroa on 7/30/26.
//

import SwiftUI

@main
struct WellSpentApp: App {
    @State private var session: SessionStore

    init() {
        let tokenStore = KeychainTokenStore()
        // UI tests launch with this argument so each test starts from a
        // known logged-out state instead of inheriting whatever the
        // Simulator's Keychain happens to have from a previous run.
        if ProcessInfo.processInfo.arguments.contains("-uiTestResetSession") {
            tokenStore.deleteToken()
        }
        _session = State(initialValue: SessionStore(tokenStore: tokenStore))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
    }
}
