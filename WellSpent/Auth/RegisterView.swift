import SwiftUI
import WellSpentAPI
import WellSpentREST

struct RegisterView: View {
    @Environment(SessionStore.self) private var session
    @Bindable private var viewModel: RegisterViewModel

    init(publicClient: ProtocolClient, publicRESTClient: WellSpentREST.Client) {
        _viewModel = Bindable(wrappedValue: RegisterViewModel(publicClient: publicClient, publicRESTClient: publicRESTClient))
    }

    var body: some View {
        Form {
            personalInfoSection
            locationSection
            errorSection
            actionsSection
        }
        .navigationTitle("Register")
        .accessibilityIdentifier("registerView")
        .task {
            await viewModel.loadCountries()
        }
    }

    // Split out of `body` so SwiftUI's result-builder type checker only ever
    // has to solve one small, explicitly-typed expression at a time instead
    // of one giant chained Form — avoids "Cannot infer contextual base"-style
    // timeouts in Xcode's live type checker on larger forms.
    @ViewBuilder
    private var personalInfoSection: some View {
        Section {
            TextField("First name", text: $viewModel.firstName)
                .textContentType(.givenName)
                .accessibilityIdentifier("firstNameField")

            TextField("Last name", text: $viewModel.lastName)
                .textContentType(.familyName)
                .accessibilityIdentifier("lastNameField")

            TextField("Email", text: $viewModel.email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("registerEmailField")

            SecureField("Password", text: $viewModel.password)
                // .password, not .newPassword — the latter triggers iOS's
                // "Use Strong Password?" system sheet on focus, which
                // steals keystrokes mid-typeText under XCUITest. .password
                // still enables password-manager autofill, just skips the
                // strong-password-generator interstitial.
                .textContentType(.password)
                .accessibilityIdentifier("registerPasswordField")

            passwordHint
        }
    }

    @ViewBuilder
    private var passwordHint: some View {
        if let passwordError = RegisterViewModel.passwordError(for: viewModel.password), !viewModel.password.isEmpty {
            Text(passwordError)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        Section {
            Picker("Country", selection: $viewModel.countryCode) {
                Text("Select a country").tag("")
                ForEach(viewModel.countries, id: \.code) { country in
                    Text(country.name).tag(country.code)
                }
            }
            .accessibilityIdentifier("countryPicker")

            if viewModel.isUnitedStates {
                Picker("State", selection: $viewModel.stateCode) {
                    Text("Select a state").tag("")
                    ForEach(USState.all, id: \.code) { state in
                        Text(state.name).tag(state.code)
                    }
                }
                .accessibilityIdentifier("stateField")
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = viewModel.errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("registerErrorMessage")
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            Button {
                Task { await viewModel.submit(session: session) }
            } label: {
                HStack {
                    Text("Create Account")
                    if viewModel.isSubmitting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("registerButton")

            SocialSignInButtons(publicClient: session.publicClient)
        }
    }
}

#Preview {
    NavigationStack {
        RegisterView(
            publicClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
            publicRESTClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }
    .environment(SessionStore())
}
