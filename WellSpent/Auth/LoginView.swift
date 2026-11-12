import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel = LoginViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Image("BrandLockup")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 56, alignment: .leading)
                    .padding(.leading, -6)
                    .padding(.bottom, 14)
                    .accessibilityLabel("WellSpent")

                OnboardingHeading(title: Text("Welcome back"), subtitle: Text("Plan your money before you spend it."))
                    .padding(.bottom, 8)

                credentialsCard
                divider
                SocialSignInButtons()
                registerLink
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("loginView")
    }

    private var credentialsCard: some View {
        HomeCard {
            VStack(spacing: 14) {
                LabeledFieldBox(label: Text("Email")) {
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("emailField")
                }

                LabeledFieldBox(label: Text("Password")) {
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
                        .accessibilityIdentifier("passwordField")
                }

                Toggle(isOn: $viewModel.rememberMe) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Keep me signed in")
                        Text("For 90 days on this phone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.green)
                .accessibilityIdentifier("rememberMeToggle")

                if let errorMessage = viewModel.errorMessage {
                    InlineErrorBanner(message: errorMessage)
                        .accessibilityIdentifier("loginErrorMessage")
                }

                Button {
                    Task { await viewModel.submit(session: session) }
                } label: {
                    if viewModel.isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Log In")
                    }
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(!viewModel.canSubmit)
                .accessibilityIdentifier("loginButton")
            }
        }
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color(.separator)).frame(height: 1)
            Text("or").font(.footnote).foregroundStyle(.secondary)
            Rectangle().fill(Color(.separator)).frame(height: 1)
        }
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }

    private var registerLink: some View {
        HStack(spacing: 4) {
            Text("New to WellSpent?")
                .foregroundStyle(.secondary)
            NavigationLink("Create an account") {
                RegisterView(publicRESTClient: session.publicRESTClient)
            }
            .fontWeight(.semibold)
            .frame(minHeight: 44)
            .accessibilityIdentifier("goToRegisterLink")
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
    .environment(SessionStore())
}
