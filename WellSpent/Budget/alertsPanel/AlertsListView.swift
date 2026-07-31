import SwiftUI
import WellSpentAPI

struct AlertsListView: View {
    let budgetProfileID: String
    let authenticatedClient: ProtocolClient

    @State private var viewModel: AlertsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Alert Settings")
        .task {
            if viewModel == nil {
                viewModel = AlertsViewModel(budgetProfileID: budgetProfileID, authenticatedClient: authenticatedClient)
            }
            await viewModel?.load()
        }
        .refreshable {
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(viewModel: AlertsViewModel) -> some View {
        List {
            if viewModel.isFree {
                Section {
                    Text("Free plan: up to 2 alerts, and \"New Transaction\" alerts aren't available. Upgrade to Pro for unlimited alerts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(viewModel.visibleAlertTypes, id: \.self) { type in
                    alertRow(type, viewModel: viewModel)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func alertRow(_ type: AlertType, viewModel: AlertsViewModel) -> some View {
        let subscription = viewModel.subscription(for: type)
        let isEnabled = subscription != nil
        let isLocked = viewModel.isAtLimit && !isEnabled

        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { isEnabled },
                set: { newValue in Task { await viewModel.toggle(type, on: newValue) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.label)
                    Text(type.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isLocked)
            .accessibilityIdentifier("alertToggle_\(type.rawValue)")

            if let subscription {
                Picker("Channel", selection: Binding(
                    get: { AlertChannel(rawValue: subscription.channel) ?? .inApp },
                    set: { newValue in Task { await viewModel.updateChannel(type, channel: newValue) } }
                )) {
                    ForEach(AlertChannel.allCases, id: \.self) { channel in
                        Text(channel.label).tag(channel)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("alertChannelPicker_\(type.rawValue)")

                if type == .spendingThreshold {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Threshold: \(Int(subscription.thresholdPct))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { subscription.thresholdPct },
                                set: { newValue in Task { await viewModel.updateThreshold(type, pct: newValue) } }
                            ),
                            in: 10...100,
                            step: 5
                        )
                        .accessibilityIdentifier("alertThresholdSlider")
                    }

                    Picker("Scope", selection: Binding(
                        get: { ThresholdScope(rawValue: subscription.thresholdScope) ?? .budget },
                        set: { newValue in Task { await viewModel.updateScope(type, scope: newValue) } }
                    )) {
                        ForEach(ThresholdScope.allCases, id: \.self) { scope in
                            Text(scope.label).tag(scope)
                        }
                    }
                    .accessibilityIdentifier("alertScopePicker")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        AlertsListView(
            budgetProfileID: "preview-budget",
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }
}
