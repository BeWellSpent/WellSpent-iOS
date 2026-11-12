import SwiftUI
import WellSpentREST

struct RegisterView: View {
    @Environment(SessionStore.self) private var session
    @Bindable private var viewModel: RegisterViewModel

    init(publicRESTClient: WellSpentREST.Client) {
        _viewModel = Bindable(wrappedValue: RegisterViewModel(publicRESTClient: publicRESTClient))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                OnboardingHeading(
                    title: Text("Create your account"),
                    subtitle: Text("Takes a minute. Then we'll set up your first budget together.")
                )
                .padding(.bottom, 8)

                HomeSectionHeader(title: Text("About you"))
                aboutYouCard

                HomeSectionHeader(title: Text("Where you live"))
                locationCard
                Text(viewModel.isUnitedStates
                     ? "Sets your currency and lets WellSpent estimate taxes on before-tax income."
                     : "Sets your currency. You can change it later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                if let errorMessage = viewModel.errorMessage {
                    InlineErrorBanner(message: errorMessage)
                        .accessibilityIdentifier("registerErrorMessage")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image("BrandMark")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
            }
        }
        .pinnedActionBar {
            Button {
                Task { await viewModel.submit(session: session) }
            } label: {
                if viewModel.isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text("Create Account")
                }
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("registerButton")
        }
        .accessibilityIdentifier("registerView")
        .task {
            await viewModel.loadCountries()
        }
    }

    private var aboutYouCard: some View {
        HomeCard {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    LabeledFieldBox(label: Text("First name")) {
                        TextField("First name", text: $viewModel.firstName)
                            .textContentType(.givenName)
                            .accessibilityIdentifier("firstNameField")
                    }
                    LabeledFieldBox(label: Text("Last name")) {
                        TextField("Last name", text: $viewModel.lastName)
                            .textContentType(.familyName)
                            .accessibilityIdentifier("lastNameField")
                    }
                }

                LabeledFieldBox(label: Text("Email"), footnote: Text("We'll send a link to confirm it.")) {
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("registerEmailField")
                }

                VStack(alignment: .leading, spacing: 10) {
                    LabeledFieldBox(label: Text("Password")) {
                        // .password, not .newPassword: the latter's "Use Strong Password?" sheet steals keystrokes under XCUITest.
                        SecureField("Password", text: $viewModel.password)
                            .textContentType(.password)
                            .accessibilityIdentifier("registerPasswordField")
                    }
                    PasswordRuleChecklist(password: viewModel.password)
                }
            }
        }
    }

    private var locationCard: some View {
        HomeCard {
            VStack(spacing: 0) {
                pickerRow(Text("Country")) {
                    Picker("Country", selection: $viewModel.countryCode) {
                        Text("Select a country").tag("")
                        ForEach(viewModel.countries, id: \.code) { country in
                            Text(country.name).tag(country.code)
                        }
                    }
                    .accessibilityIdentifier("countryPicker")
                }

                if viewModel.isUnitedStates {
                    Divider()
                    pickerRow(Text("State")) {
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
        }
    }

    private func pickerRow<P: View>(_ label: Text, @ViewBuilder picker: () -> P) -> some View {
        HStack {
            label
            Spacer()
            picker()
                .labelsHidden()
                .pickerStyle(.menu)
        }
        .frame(minHeight: 48)
    }
}

/// The four password rules, each ticked as it's met, instead of an error after submitting.
private struct PasswordRuleChecklist: View {
    let password: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
            ForEach(PasswordRule.allCases, id: \.self) { rule in
                let met = rule.isMet(by: password)
                Label {
                    Text(rule.label)
                } icon: {
                    Image(systemName: met ? "checkmark.circle.fill" : "circle")
                }
                .font(.footnote)
                .foregroundStyle(met ? Color.green : Color.secondary)
                .accessibilityValue(met ? Text("Done") : Text("Missing"))
            }
        }
    }
}

#Preview {
    NavigationStack {
        RegisterView(publicRESTClient: RESTClient.makePublicClient(baseURL: "http://localhost:1"))
    }
    .environment(SessionStore())
}
