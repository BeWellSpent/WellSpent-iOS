import SwiftUI
import WellSpentAPI

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SettingsViewModel
    @State private var isDeleteConfirmationPresented = false
    /// Same storage key as `WellSpentApp`'s `@AppStorage("themeMode")` — a
    /// pure local preference, no network round trip through `SettingsViewModel`.
    @AppStorage("themeMode") private var themeMode: ThemePreference = .system
    private let authenticatedClient: ProtocolClient
    private let onUpdated: (Wellspent_V1_User) -> Void

    init(authenticatedClient: ProtocolClient, onUpdated: @escaping (Wellspent_V1_User) -> Void) {
        _viewModel = State(initialValue: SettingsViewModel(authenticatedClient: authenticatedClient))
        self.authenticatedClient = authenticatedClient
        self.onUpdated = onUpdated
    }

    var body: some View {
        Form {
            profileSection
            appearanceSection
            if viewModel.isUnitedStates {
                plaidSection
            }
            subscriptionSection
            passwordSection
            helpSection
            accountManagementSection
        }
        .navigationTitle("Settings")
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
        .alert("Delete your account?", isPresented: $isDeleteConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                Task {
                    if await viewModel.deleteAccount() {
                        session.endSession()
                    }
                }
            }
        } message: {
            Text("This will immediately deactivate your account. You will be signed out and will not be able to log back in. Contact support within 30 days if you want to recover it.")
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        Section("Profile") {
            TextField("First name", text: $viewModel.firstName)
                .accessibilityIdentifier("settingsFirstNameField")
            TextField("Last name", text: $viewModel.lastName)
                .accessibilityIdentifier("settingsLastNameField")

            // A "Hide My Email" account's address is a machine-generated relay
            // alias (a1b2c3@privaterelay.appleid.com) — showing it tells the
            // user nothing, so name the sign-in method instead.
            if viewModel.hasApplePrivateEmail {
                LabeledContent("Email", value: String(localized: "Signed with Apple", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settingsEmailField")
            } else {
                LabeledContent("Email", value: viewModel.email)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settingsEmailField")
            }

            Picker("Country", selection: $viewModel.countryCode) {
                Text("Select a country").tag("")
                ForEach(viewModel.countries, id: \.code) { country in
                    Text(country.name).tag(country.code)
                }
            }
            .accessibilityIdentifier("settingsCountryPicker")

            if viewModel.isUnitedStates {
                Picker("State", selection: $viewModel.stateCode) {
                    Text("Select a state").tag("")
                    ForEach(USState.all, id: \.code) { state in
                        Text(state.name).tag(state.code)
                    }
                }
                .accessibilityIdentifier("settingsStateField")

                Picker("Filing status", selection: $viewModel.filingStatus) {
                    ForEach(FilingStatusLabel.selectable, id: \.self) { status in
                        Text(FilingStatusLabel.text(for: status)).tag(status)
                    }
                }
                .accessibilityIdentifier("settingsFilingStatusPicker")

                Picker("Tax payment frequency", selection: $viewModel.taxPaymentFrequency) {
                    ForEach(TaxPaymentFrequencyLabel.selectable, id: \.self) { frequency in
                        Text(TaxPaymentFrequencyLabel.text(for: frequency)).tag(frequency)
                    }
                }
                .accessibilityIdentifier("settingsTaxFrequencyPicker")
            }

            Picker("Language", selection: $viewModel.language) {
                Text("English").tag("en")
                Text("Español").tag("es")
            }
            .accessibilityIdentifier("settingsLanguagePicker")

            Picker("Currency", selection: $viewModel.currency) {
                Text("USD").tag("USD")
                Text("ARS").tag("ARS")
                Text("EUR").tag("EUR")
            }
            .accessibilityIdentifier("settingsCurrencyPicker")

            if let profileErrorMessage = viewModel.profileErrorMessage {
                Text(profileErrorMessage)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settingsProfileErrorMessage")
            }

            Button {
                Task {
                    if let user = await viewModel.saveProfile() {
                        onUpdated(user)
                    }
                }
            } label: {
                HStack {
                    Text("Save changes")
                    if viewModel.isSavingProfile {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.isSavingProfile)
            .accessibilityIdentifier("saveProfileButton")
        }
    }

    /// Help — deliberately somewhere you have to go looking for, per issue #59.
    /// For now it holds one thing: the changelog, browsable per component
    /// including web, which an iOS reader cannot see any other way.
    @ViewBuilder
    private var helpSection: some View {
        Section("Help") {
            NavigationLink {
                ChangelogView(
                    authenticatedClient: authenticatedClient,
                    localeIdentifier: AppLanguageStore.currentLocale.identifier
                )
            } label: {
                Label("What's new", systemImage: "sparkles")
            }
            .accessibilityIdentifier("changelogNavLink")
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $themeMode) {
                ForEach(ThemePreference.allCases, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            }
            .accessibilityIdentifier("themePicker")
        }
    }

    @ViewBuilder
    private var plaidSection: some View {
        Section("Connected Bank Accounts") {
            PlaidConnectionsView(authenticatedClient: authenticatedClient, plan: viewModel.plan)
        }
    }

    @ViewBuilder
    private var subscriptionSection: some View {
        Section("Subscription") {
            HStack {
                Label(PlanLabel.text(for: viewModel.plan), systemImage: PlanLabel.systemImage(for: viewModel.plan))
                    .foregroundStyle(PlanLabel.tint(for: viewModel.plan))
                    .accessibilityIdentifier("subscriptionPlanBadge")
                Spacer()
            }

            if viewModel.plan == .unspecified || viewModel.plan == .free {
                Text("Upgrade to Pro for unlimited people, income sources, and alerts, plus Plaid bank sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Upgrade to Pro — Coming Soon") {}
                    .disabled(true)
                    .accessibilityIdentifier("upgradeToProButton")
            }
        }
    }

    @ViewBuilder
    private var passwordSection: some View {
        Section("Change Password") {
            SecureField("Current password", text: $viewModel.currentPassword)
                .textContentType(.password)
                .accessibilityIdentifier("currentPasswordField")

            SecureField("New password", text: $viewModel.newPassword)
                .textContentType(.newPassword)
                .accessibilityIdentifier("newPasswordField")

            if let passwordHint = RegisterViewModel.passwordError(for: viewModel.newPassword), !viewModel.newPassword.isEmpty {
                Text(passwordHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.passwordChangeSucceeded {
                Text("Password updated.")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("passwordChangeSuccessMessage")
            }
            if let passwordErrorMessage = viewModel.passwordErrorMessage {
                Text(passwordErrorMessage)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("passwordChangeErrorMessage")
            }

            Button {
                Task { await viewModel.changePassword() }
            } label: {
                HStack {
                    Text("Update password")
                    if viewModel.isChangingPassword {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!viewModel.canSubmitPassword)
            .accessibilityIdentifier("changePasswordButton")
        }
    }

    @ViewBuilder
    private var accountManagementSection: some View {
        Section("Account Management") {
            Button("Delete Account", role: .destructive) {
                isDeleteConfirmationPresented = true
            }
            .accessibilityIdentifier("deleteAccountButton")
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")) { _ in }
    }
    .environment(SessionStore())
}
