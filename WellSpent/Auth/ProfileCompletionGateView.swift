import Observation
import SwiftUI
import WellSpentAPI
import WellSpentREST

/// Whether an account has the profile information the app needs to work.
///
/// Only the country is checked, and only because it is the one field a sign-up
/// can complete without: the registration form collects it, but
/// `ExchangeGoogleCode` and `SignInWithApple` never receive one, so every
/// social sign-up lands with it empty. That silently disables before-tax
/// income and the tax reserve, and propagates into `budget_profile.country_code`
/// at creation, so a budget made in the meantime inherits the gap for good.
///
/// State and filing status are deliberately *not* required: both are US-only,
/// and a non-US account has no valid answer to either.
///
/// Mirrors web's `profileCompletionGate/isProfileComplete.ts`.
nonisolated enum ProfileCompletion {
    static func isComplete(countryCode: String) -> Bool {
        !countryCode.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

@MainActor
@Observable
final class ProfileCompletionGateViewModel {
    /// `.unknown` is the pre-first-load state: the app renders through it, so
    /// a complete account never gets a form flashed at it on launch. Same
    /// posture as `VerifyEmailGateViewModel`.
    enum State: Equatable {
        case unknown
        case complete
        case incomplete
    }

    private(set) var state: State = .unknown
    private(set) var countries: [Country] = []
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    var countryCode = ""
    var stateCode = ""
    var filingStatus: Wellspent_V1_FilingStatus = .unspecified

    /// Carried through `UpdateMe` untouched. The RPC replaces the whole
    /// profile, so omitting a field it already holds would blank it.
    private var firstName = ""
    private var lastName = ""
    private var language = "en"
    private var currency = "USD"

    var isUnitedStates: Bool { countryCode == "US" }
    var canSubmit: Bool { !countryCode.isEmpty && !isSubmitting }

    private let userClient: Wellspent_V1_UserServiceClient
    private let restClient: WellSpentREST.Client

    init(authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client) {
        self.userClient = Wellspent_V1_UserServiceClient(client: authenticatedClient)
        self.restClient = restClient
    }

    func refresh() async {
        let response = await userClient.getMe(request: .init())
        guard case .success(let message) = response.result else { return }
        let user = message.user
        firstName = user.firstName
        lastName = user.lastName
        language = user.language
        currency = user.currency
        state = ProfileCompletion.isComplete(countryCode: user.countryCode) ? .complete : .incomplete
        if state == .incomplete, countries.isEmpty {
            await loadCountries()
        }
    }

    /// The public REST client even here, on an authenticated screen: the
    /// endpoint takes no token, and sending one would make the response look
    /// user-specific to a cache that cannot know otherwise.
    private func loadCountries() async {
        do {
            countries = try await restClient.enabledCountries()
        } catch {
            errorMessage = String(localized: "Couldn't load the country list. Check your connection and try again.",
                                  bundle: AppLanguageStore.currentBundle,
                                  locale: AppLanguageStore.currentLocale)
        }
    }

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let request = Wellspent_V1_UpdateMeRequest.with {
            $0.firstName = firstName
            $0.lastName = lastName
            $0.countryCode = countryCode
            $0.stateCode = isUnitedStates ? stateCode : ""
            $0.filingStatus = isUnitedStates ? filingStatus : .unspecified
            $0.language = language
            $0.currency = currency
        }
        let response = await userClient.updateMe(request: request)
        switch response.result {
        case .success:
            state = .complete
        case .failure(let error):
            errorMessage = error.message ?? String(localized: "Couldn't save that. Please try again.",
                                                   bundle: AppLanguageStore.currentBundle,
                                                   locale: AppLanguageStore.currentLocale)
        }
    }
}

/// Blocks the app until the account has a country.
///
/// Replaces the app outright rather than covering it, for the same reason
/// `VerifyEmailGateView` does: a sheet can be swiped away, and `RootView`
/// already presents the invite cover — a second presentation modifier on one
/// view is the footgun behind the Plaid double-tap bug.
struct ProfileCompletionGateView: View {
    @Bindable var viewModel: ProfileCompletionGateViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Signing in with Google or Apple doesn't tell us where you are, and WellSpent needs that to handle your currency and taxes correctly.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Country", selection: $viewModel.countryCode) {
                        Text("Select a country").tag("")
                        ForEach(viewModel.countries, id: \.code) { country in
                            Text(country.name).tag(country.code)
                        }
                    }
                    .accessibilityIdentifier("completeProfileCountryPicker")

                    if viewModel.isUnitedStates {
                        Picker("State", selection: $viewModel.stateCode) {
                            Text("Select a state").tag("")
                            ForEach(USState.all, id: \.code) { state in
                                Text(state.name).tag(state.code)
                            }
                        }
                        .accessibilityIdentifier("completeProfileStatePicker")

                        Picker("Filing status", selection: $viewModel.filingStatus) {
                            Text(FilingStatusLabel.text(for: .unspecified)).tag(Wellspent_V1_FilingStatus.unspecified)
                            ForEach(FilingStatusLabel.selectable, id: \.self) { status in
                                Text(FilingStatusLabel.text(for: status)).tag(status)
                            }
                        }
                        .accessibilityIdentifier("completeProfileFilingStatusPicker")
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("completeProfileErrorMessage")
                    }
                }

                Section {
                    Button {
                        Task { await viewModel.submit() }
                    } label: {
                        HStack {
                            Text("Continue")
                            if viewModel.isSubmitting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("completeProfileButton")
                }
            }
            .navigationTitle("One more thing")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
