//
//  WellSpentApp.swift
//  WellSpent
//
//  Created by Mauricio Figueroa on 7/30/26.
//

import SwiftUI

@main
struct WellSpentApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session: SessionStore

    init() {
        let tokenStore = KeychainTokenStore()
        // UI tests launch with this argument so each test starts from a
        // known logged-out state instead of inheriting whatever the
        // Simulator's Keychain happens to have from a previous run.
        if ProcessInfo.processInfo.arguments.contains("-uiTestResetSession") {
            tokenStore.deleteToken()
        }
        let sessionStore = SessionStore(tokenStore: tokenStore)
        _session = State(initialValue: sessionStore)

        // Set once at startup rather than held on an AppDelegate instance
        // property — `weak` since `session`/`sessionStore` already outlive
        // this closure for the app's whole lifetime; avoids an unnecessary
        // strong reference from a static var.
        AppDelegate.onDeviceToken = { [weak sessionStore] data in
            Task { @MainActor in
                guard let client = sessionStore?.authenticatedClient else { return }
                await PushNotificationRegistrar.register(deviceToken: data, authenticatedClient: client)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
    }
}
