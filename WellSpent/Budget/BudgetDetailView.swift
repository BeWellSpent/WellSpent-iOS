import Foundation
import SwiftUI
import WellSpentAPI

/// Budget hub — deliberately a grouped list, not a tab bar. There's no
/// Transactions/Expense Plan content to put in tabs until Phase 2B/2C; a real
/// tab shell lands once those screens exist, matching web's current IA.
struct BudgetDetailView: View {
    @Environment(\.dismiss) private var dismiss
    private let authenticatedClient: ProtocolClient?
    private let currencyCode: String
    private let localeIdentifier: String
    private let onUpdated: (Wellspent_V1_BudgetProfile) -> Void
    private let onDeleted: () -> Void

    @State private var viewModel: BudgetDetailViewModel?
    @State private var isEditSheetPresented = false
    @State private var isDeleteConfirmationPresented = false

    init(
        profile: Wellspent_V1_BudgetProfile,
        authenticatedClient: ProtocolClient?,
        currencyCode: String,
        localeIdentifier: String,
        onUpdated: @escaping (Wellspent_V1_BudgetProfile) -> Void,
        onDeleted: @escaping () -> Void
    ) {
        self.authenticatedClient = authenticatedClient
        self.currencyCode = currencyCode
        self.localeIdentifier = localeIdentifier
        self.onUpdated = onUpdated
        self.onDeleted = onDeleted
        _viewModel = State(initialValue: authenticatedClient.map { BudgetDetailViewModel(profile: profile, authenticatedClient: $0) })
    }

    var body: some View {
        Group {
            if let viewModel {
                detail(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private func detail(viewModel: BudgetDetailViewModel) -> some View {
        List {
            Section {
                LabeledContent("Cycle", value: BudgetCycleLabel.text(for: viewModel.profile.cycle))
                if let period = viewModel.currentPeriod {
                    LabeledContent("Current period", value: periodRangeText(period))
                } else if viewModel.isLoading {
                    ProgressView()
                }
            }

            Section {
                if let authenticatedClient {
                    NavigationLink("People") {
                        PeopleListView(
                            budgetProfileID: viewModel.profile.id,
                            budgetOwnerUserID: viewModel.profile.userID,
                            authenticatedClient: authenticatedClient
                        )
                    }
                    .accessibilityIdentifier("peopleNavLink")

                    NavigationLink("Income") {
                        IncomeListView(
                            budgetProfileID: viewModel.profile.id,
                            budgetCountryCode: viewModel.profile.countryCode,
                            authenticatedClient: authenticatedClient,
                            currencyCode: currencyCode,
                            localeIdentifier: localeIdentifier
                        )
                    }
                    .accessibilityIdentifier("incomeNavLink")
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(viewModel.profile.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit Budget") { isEditSheetPresented = true }
                    Button("Delete Budget", role: .destructive) { isDeleteConfirmationPresented = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("budgetDetailMenu")
            }
        }
        .sheet(isPresented: $isEditSheetPresented) {
            if let authenticatedClient {
                EditBudgetSheet(profile: viewModel.profile, authenticatedClient: authenticatedClient) { updated in
                    viewModel.applyUpdatedProfile(updated)
                    onUpdated(updated)
                }
            }
        }
        .confirmationDialog("Delete this budget?", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    if await viewModel.delete() {
                        onDeleted()
                        dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.loadPeriod()
        }
    }

    private func periodRangeText(_ period: Wellspent_V1_BudgetPeriod) -> String {
        let start = period.startDate.date.formatted(date: .abbreviated, time: .omitted)
        let end = period.endDate.date.formatted(date: .abbreviated, time: .omitted)
        return "\(start) – \(end)"
    }
}
