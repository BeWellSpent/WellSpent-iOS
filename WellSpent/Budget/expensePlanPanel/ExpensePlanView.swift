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
    /// Defaults to pie, matching web's `ExpensesPanel.tsx` (Overview's chart
    /// defaults to bar instead — see `ExpenseOverviewListView`).
    /// nil until the person's saved preference has loaded, so the chart isn't
    /// drawn as a pie and then snapped to a bar a moment later. Set from the
    /// toggle too, which overrides the saved default for this visit only —
    /// Preferences is the only place that writes one.
    @State private var chartTypeOverride: ExpenseChartView.ChartType?
    @Environment(SessionStore.self) private var session

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
            if !viewModel.visibleCategories.isEmpty {
                Section {
                    ExpenseChartView(
                        data: viewModel.chartData,
                        chartType: chartTypeBinding(viewModel.people),
                        currencyCode: currencyCode,
                        localeIdentifier: localeIdentifier
                    )
                }
            }

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
                    // isNegative, not `units < 0`: a -$0.50 remainder has
                    // units == 0 and would otherwise read as in the black.
                    .foregroundStyle(MoneyFormatting.isNegative(units: remainder.units, nanos: remainder.nanos) ? .red : .primary)
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
        let total = ExpensePlanCalculations.categoryTotal(
            planned: viewModel.plannedTotal(for: category),
            notDue: viewModel.notDuePlannedTotal(for: category)
        )
        let dueText = viewModel.nextDueText(for: category)
        let row = HStack {
            ColorDotView(hex: category.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .foregroundStyle(.primary)
                // Only on a not-due row, so an amount that counts toward
                // nothing always says so rather than looking like a plan.
                if total.isNotDue && !dueText.isEmpty {
                    Text("Not due this period — next due \(dueText)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityIdentifier("planCategoryNotDue_\(category.name)")
                }
            }
            Spacer()
            Text(displayText(total.amount))
                .foregroundStyle(total.isNotDue ? .tertiary : .secondary)
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


    /// Saved preference for this tab, falling back to the shared default when
    /// the person hasn't chosen or isn't a linked member. Read from `people`,
    /// which the view model already loads — no extra request.
    private func savedChartType(_ people: [Wellspent_V1_BudgetPerson]) -> ExpenseChartView.ChartType {
        let me = ChartPreference.myPerson(currentUserID: session.userID, people: people)
        return ChartPreference.chartType(for: me?.planChartType ?? .unspecified)
    }

    private func chartTypeBinding(_ people: [Wellspent_V1_BudgetPerson]) -> Binding<ExpenseChartView.ChartType> {
        Binding(
            get: { chartTypeOverride ?? savedChartType(people) },
            set: { chartTypeOverride = $0 }
        )
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
