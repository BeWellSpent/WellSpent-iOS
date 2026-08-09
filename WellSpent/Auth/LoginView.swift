import SwiftUI
import WellSpentAPI

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @Bindable private var viewModel: LoginViewModel

    init(publicClient: ProtocolClient) {
        _viewModel = Bindable(wrappedValue: LoginViewModel(publicClient: publicClient))
    }

    var body: some View {
        Form {
            credentialsSection
            errorSection
            actionsSection
            registerLinkSection
        }
        .navigationTitle("Log In")
        .accessibilityIdentifier("loginView")
    }

    // Split out of `body` so SwiftUI's result-builder type checker only ever
    // has to solve one small, explicitly-typed expression at a time instead
    // of one giant chained Form — avoids "Cannot infer contextual base"-style
    // timeouts in Xcode's live type checker on larger forms.
    @ViewBuilder
    private var credentialsSection: some View {
        Section {
            TextField("Email", text: $viewModel.email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("emailField")

            SecureField("Password", text: $viewModel.password)
                .textContentType(.password)
                .accessibilityIdentifier("passwordField")

            Toggle("Remember me", isOn: $viewModel.rememberMe)
                .accessibilityIdentifier("rememberMeToggle")
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = viewModel.errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("loginErrorMessage")
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
                    Text("Log In")
                    if viewModel.isSubmitting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("loginButton")

            SocialSignInButtons(publicClient: session.publicClient)
        }
    }

    @ViewBuilder
    private var registerLinkSection: some View {
        Section {
            NavigationLink("Don't have an account? Register") {
                RegisterView(publicClient: session.publicClient)
            }
            .accessibilityIdentifier("goToRegisterLink")
        }
    }
}

#Preview {
    NavigationStack {
        LoginView(publicClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
    }
    .environment(SessionStore())
}
