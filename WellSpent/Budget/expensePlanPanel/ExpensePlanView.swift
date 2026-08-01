import SwiftUI
import WellSpentAPI

struct ExpensePlanView: View {
    /// Local to this file, not a `Shared/` enum — mirrors `TransactionKind`
    /// in `TransactionsListView.swift`, UI-local tab state rather than a
    /// reusable domain concept.
    enum PlanKind: Hashable {
        case plan
        case overview
    }

    let budgetPeriodID: String
    let budgetProfileID: String
    let authenticatedClient: ProtocolClient
    let currencyCode: String
    let localeIdentifier: String
    /// Owned by `BudgetDetailView`, not locally — the visible nav bar belongs
    /// to the *outer* `NavigationStack` this view is nested two levels
    /// inside (per-tab stack → pushed budget detail screen), and neither
    /// `.toolbar` items nor this picker's selection reliably surface from
    /// here on their own. `BudgetDetailView` needs `selectedKind` itself to
    /// decide which toolbar button to show, so it owns the state and this
    /// view just binds to it.
    @Binding var selectedKind: PlanKind
    @Binding var isAddCategoryPresented: Bool
    /// True while the Plan tab is the selected `BudgetSection` in
    /// `BudgetDetailView`. `TabView` keeps every tab's content mounted, so
    /// `.task` only fires once on first mount — this drives a reload every
    /// time the tab becomes active again, not just on first appearance.
    let isActive: Bool
    let canEdit: Bool

    @State private var viewModel: ExpensePlanViewModel?
    @State private var allocatingCategory: Wellspent_V1_Category?

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedKind) {
                Text("Overview").tag(PlanKind.overview)
                Text("Plan").tag(PlanKind.plan)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])
            .accessibilityIdentifier("planKindPicker")

            switch selectedKind {
            case .plan:
                Group {
                    if let viewModel {
                        content(viewModel: viewModel)
                    } else {
                        ProgressView()
                    }
                }
            case .overview:
                ExpenseOverviewListView(
                    budgetPeriodID: budgetPeriodID,
                    budgetProfileID: budgetProfileID,
                    authenticatedClient: authenticatedClient,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier
                )
            }
        }
        .navigationTitle("Expense Plan")
        .task {
            if viewModel == nil {
                viewModel = ExpensePlanViewModel(
                    budgetPeriodID: budgetPeriodID,
                    budgetProfileID: budgetProfileID,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier,
                    authenticatedClient: authenticatedClient
                )
            }
            await viewModel?.load()
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                Task { await viewModel?.load() }
            }
        }
        .refreshable {
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(viewModel: ExpensePlanViewModel) -> some View {
        List {
            Section {
                if viewModel.categories.isEmpty && viewModel.isLoading {
                    ProgressView()
                } else if viewModel.visibleCategories.isEmpty {
                    Text("No categories planned yet. Tap + to add one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.visibleCategories, id: \.id) { category in
                        categoryRow(category, viewModel: viewModel, canEdit: canEdit)
                    }
                }
            }

            Section {
                let income = viewModel.incomeTotal
                let committed = viewModel.committedTotal
                let remainder = viewModel.remainderTotal

                LabeledContent("Income", value: displayText(income))
                    .accessibilityIdentifier("planIncomeTotal")
                LabeledContent("Committed", value: displayText(committed))
                    .accessibilityIdentifier("planCommittedTotal")
                LabeledContent("Remaining", value: displayText(remainder))
                    .foregroundStyle(remainder.units < 0 ? .red : .primary)
                    .accessibilityIdentifier("planRemainderTotal")
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .sheet(isPresented: $isAddCategoryPresented) {
            let visibleIDs = Set(viewModel.visibleCategories.map(\.id))
            AddPlanCategoryView(categories: viewModel.categories.filter { !visibleIDs.contains($0.id) }) { category in
                allocatingCategory = category
            }
        }
        .sheet(isPresented: Binding(
            get: { allocatingCategory != nil },
            set: { if !$0 { allocatingCategory = nil } }
        )) {
            if let allocatingCategory {
                AllocateCategoryView(
                    category: allocatingCategory,
                    people: viewModel.people,
                    existingAllocations: viewModel.allocations(for: allocatingCategory.id),
                    currencyCode: currencyCode
                ) { upserted, deletedIDs in
                    Task { await viewModel.applyAllocationChanges(upserted: upserted, deletedIDs: deletedIDs) }
                }
            }
        }
    }

    private func categoryRow(_ category: Wellspent_V1_Category, viewModel: ExpensePlanViewModel, canEdit: Bool) -> some View {
        let row = HStack {
            Text(category.name)
                .foregroundStyle(.primary)
            Spacer()
            Text(displayText(viewModel.plannedTotal(for: category)))
                .foregroundStyle(.secondary)
        }
        return Group {
            if canEdit {
                Button {
                    allocatingCategory = category
                } label: {
                    row
                }
                .buttonStyle(.plain)
            } else {
                row
            }
        }
        .accessibilityIdentifier("planCategoryRow_\(category.name)")
    }

    private func displayText(_ amount: (units: Int64, nanos: Int32)) -> String {
        MoneyFormatting.format(units: amount.units, nanos: amount.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }
}

#Preview {
    NavigationStack {
        ExpensePlanView(
            budgetPeriodID: "preview-period",
            budgetProfileID: "preview-budget",
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
            currencyCode: "USD",
            localeIdentifier: "en",
            selectedKind: .constant(.plan),
            isAddCategoryPresented: .constant(false),
            isActive: true,
            canEdit: true
        )
    }
}
