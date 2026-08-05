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
                    AlertRow(type: type, viewModel: viewModel)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
    }
}

/// A single alert type's row. This must be its own `View` (not a
/// `@ViewBuilder` function on the parent) so `draftThresholdPct` can hold
/// local `@State` — SwiftUI's function-based view builders can't own state.
private struct AlertRow: View {
    let type: AlertType
    let viewModel: AlertsViewModel

    // Slider's Binding `set` fires continuously during drag (many times per
    // second), not just on release — wiring the network call straight to it
    // flooded the backend's rate limiter and disabled the slider mid-drag on
    // every one of those in-flight requests (mirrors the same bug just fixed
    // on WellSpent-web). This local draft tracks the thumb during drag; the
    // network call only fires once, in onEditingChanged when dragging ends.
    @State private var draftThresholdPct: Float = 80

    var body: some View {
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
                        Text("Threshold: \(Int(draftThresholdPct))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: $draftThresholdPct,
                            in: 10...100,
                            step: 5,
                            onEditingChanged: { editing in
                                if !editing {
                                    Task { await viewModel.updateThreshold(type, pct: draftThresholdPct) }
                                }
                            }
                        )
                        .accessibilityIdentifier("alertThresholdSlider")
                    }
                    .onAppear { draftThresholdPct = subscription.thresholdPct }
                    .onChange(of: subscription.thresholdPct) { _, newValue in
                        draftThresholdPct = newValue
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

                    if ThresholdScope(rawValue: subscription.thresholdScope) == .category {
                        ColorDotPickerField(
                            title: "Category",
                            selection: Binding(
                                get: { subscription.categoryID },
                                set: { newValue in Task { await viewModel.updateCategory(type, categoryID: newValue) } }
                            ),
                            options: viewModel.categories.map { ColorDotOption(id: $0.id, name: $0.name, hex: $0.color) },
                            accessibilityIdentifier: "alertCategoryPicker"
                        )
                    }
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
