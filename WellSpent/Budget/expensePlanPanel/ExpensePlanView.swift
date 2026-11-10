import os
import SwiftUI
import WellSpentAPI
import WellSpentREST

/// Plan's two sub-tabs — Categories (per-category planned amounts, the
/// screen's original content) and Fixed Expenses (recurring-bill template
/// management, added in Stage 3 of
/// docs/features/overview-plan-navigation-rework.md). Not private: the
/// toolbar "+" in `BudgetDetailView` needs to know which is active to decide
/// whether it opens Add Category or Add Fixed Expense.
enum PlanSubTab: Hashable, CaseIterable {
    case categories
    case fixedExpenses

    var title: String {
        let locale = AppLanguageStore.currentLocale
        switch self {
        case .categories: return String(localized: "Categories", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .fixedExpenses: return String(localized: "Fixed expenses", bundle: AppLanguageStore.currentBundle, locale: locale)
        }
    }
}

struct ExpensePlanView: View {
    let budgetPeriodID: String
    let budgetProfileID: String
    let authenticatedRESTClient: WellSpentREST.Client
    let currencyCode: String
    let localeIdentifier: String
    @Binding var isAddCategoryPresented: Bool
    @Binding var isAddFixedExpensePresented: Bool
    @Binding var selectedSubTab: PlanSubTab
    /// True while the Plan tab is the selected `BudgetSection` in
    /// `BudgetDetailView`. `TabView` keeps every tab's content mounted, so
    /// `.task` only fires once on first mount — this drives a reload every
    /// time the tab becomes active again, not just on first appearance.
    let isActive: Bool
    let canEdit: Bool

    @State private var viewModel: ExpensePlanViewModel?
    @State private var fixedExpensesViewModel: FixedExpenseTemplatesViewModel?
    @State private var activeSheet: ActiveSheet?
    /// Defaults to pie, matching web's `ExpensesPanel.tsx` (Overview's chart
    /// defaults to bar instead — see `ExpenseOverviewChartListView`).
    /// nil until the person's saved preference has loaded, so the chart isn't
    /// drawn as a pie and then snapped to a bar a moment later. Set from the
    /// toggle too, which overrides the saved default for this visit only —
    /// Preferences is the only place that writes one.
    @State private var chartTypeOverride: ExpenseChartView.ChartType?
    @Environment(SessionStore.self) private var session

    /// Every locally-triggered sheet on this view — the Add sheets stay
    /// their own `.sheet(isPresented:)` modifiers, since their bindings are
    /// owned by `BudgetDetailView`'s toolbar (same split `TransactionsListView`
    /// already established, see its `ActiveSheet` doc comment).
    private enum ActiveSheet: Identifiable {
        case allocate(Wellspent_V1_Category)
        case editFixedExpense(Wellspent_V1_FixedExpense)

        var id: String {
            switch self {
            case .allocate(let category): return "allocate-\(category.id)"
            case .editFixedExpense(let expense): return "editFixedExpense-\(expense.id)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedSubTab) {
                Text(PlanSubTab.categories.title).tag(PlanSubTab.categories)
                Text(PlanSubTab.fixedExpenses.title).tag(PlanSubTab.fixedExpenses)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])
            .accessibilityIdentifier("planSubTabPicker")

            Group {
                switch selectedSubTab {
                case .categories:
                    if let viewModel {
                        categoriesContent(viewModel: viewModel)
                    } else {
                        ProgressView()
                    }
                case .fixedExpenses:
                    fixedExpensesContent
                }
            }
            .frame(maxHeight: .infinity)
        }
        .navigationTitle("Expense Plan")
        .task {
            if viewModel == nil {
                viewModel = ExpensePlanViewModel(
                    budgetPeriodID: budgetPeriodID,
                    budgetProfileID: budgetProfileID,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier,
                    currentUserID: session.userID,
                    restClient: authenticatedRESTClient
                )
            }
            if fixedExpensesViewModel == nil {
                fixedExpensesViewModel = FixedExpenseTemplatesViewModel(
                    budgetProfileID: budgetProfileID,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier,
                    currentUserID: session.userID,
                    restClient: authenticatedRESTClient
                )
            }
            await viewModel?.load()
            await fixedExpensesViewModel?.load()
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                Task {
                    await viewModel?.load()
                    await fixedExpensesViewModel?.load()
                }
            }
        }
        .sheet(isPresented: $isAddCategoryPresented) {
            if let viewModel {
                let visibleIDs = Set(viewModel.visibleCategories.map(\.id))
                AddPlanCategoryView(categories: viewModel.categories.filter { !visibleIDs.contains($0.id) }) { category in
                    activeSheet = .allocate(category)
                }
            }
        }
        .sheet(isPresented: $isAddFixedExpensePresented) {
            if let fixedExpensesViewModel {
                AddFixedExpenseView(
                    budgetProfileID: budgetProfileID,
                    currencyCode: currencyCode,
                    categories: fixedExpensesViewModel.categories,
                    paymentMethods: fixedExpensesViewModel.paymentMethods,
                    restClient: authenticatedRESTClient
                ) { expense, _ in
                    // The spawned transaction is irrelevant here — this list
                    // is profile-level, not period-scoped.
                    fixedExpensesViewModel.addTemplate(expense)
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .allocate(let category):
                if let viewModel {
                    AllocateCategoryView(
                        category: category,
                        people: viewModel.people,
                        existingAllocations: viewModel.allocations(for: category.id),
                        currencyCode: currencyCode
                    ) { upserted, deletedIDs in
                        Task { await viewModel.applyAllocationChanges(upserted: upserted, deletedIDs: deletedIDs) }
                    }
                }
            case .editFixedExpense(let expense):
                if let fixedExpensesViewModel {
                    EditFixedExpenseView(
                        expense: expense,
                        currencyCode: currencyCode,
                        categories: fixedExpensesViewModel.categories,
                        paymentMethods: fixedExpensesViewModel.paymentMethods,
                        remainingBalance: fixedExpensesViewModel.remainingBalance(for: expense.id),
                        restClient: authenticatedRESTClient
                    ) { updated in
                        fixedExpensesViewModel.replaceTemplate(updated)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func categoriesContent(viewModel: ExpensePlanViewModel) -> some View {
        List {
            Section {
                let income = viewModel.incomeTotal
                let committed = viewModel.committedTotal
                let committedWithSavings = viewModel.committedIncludingSavingsTotal
                let remainder = viewModel.remainderTotal

                LabeledContent("Planned income", value: displayText(income))
                    .accessibilityIdentifier("planIncomeTotal")
                LabeledContent("Committed (with savings)", value: displayText(committedWithSavings))
                    .accessibilityIdentifier("planCommittedIncludingSavingsTotal")
                LabeledContent("Committed (without savings)", value: displayText(committed))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("planCommittedTotal")
                // isNegative, not `units < 0`: a -$0.50 remainder has
                // units == 0 and would otherwise read as in the black.
                if let remainderWithSavings = viewModel.remainderIncludingSavingsTotal {
                    LabeledContent("Remaining (with savings)", value: displayText(remainderWithSavings))
                        .foregroundStyle(MoneyFormatting.isNegative(units: remainderWithSavings.units, nanos: remainderWithSavings.nanos) ? .red : .primary)
                        .accessibilityIdentifier("planRemainderIncludingSavingsTotal")
                }
                LabeledContent("Remaining (without savings)", value: displayText(remainder))
                    .foregroundStyle(MoneyFormatting.isNegative(units: remainder.units, nanos: remainder.nanos) ? .red : .secondary)
                    .accessibilityIdentifier("planRemainderTotal")
            }

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

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .refreshable {
            await viewModel.load()
        }
    }

    private func categoryRow(_ category: Wellspent_V1_Category, viewModel: ExpensePlanViewModel, canEdit: Bool) -> some View {
        let total = ExpensePlanCalculations.categoryTotal(
            planned: viewModel.plannedTotal(for: category),
            notDue: viewModel.notDuePlannedTotal(for: category)
        )
        let dueText = viewModel.nextDueText(for: category)
        let allocated = viewModel.allocatedTotal(for: category)
        let fixedDue = viewModel.fixedDueTotal(for: category)
        let source = ExpensePlanCalculations.source(allocated: allocated, fixedDue: fixedDue)
        let row = HStack {
            ColorDotView(hex: category.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.displayName)
                    .foregroundStyle(.primary)
                planSourceLabel(source, allocated: allocated, fixedDue: fixedDue, categoryName: category.name)
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
                    activeSheet = .allocate(category)
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

    @ViewBuilder
    private var fixedExpensesContent: some View {
        Group {
            if let fixedExpensesViewModel {
                List {
                    if fixedExpensesViewModel.fixedExpenses.isEmpty && fixedExpensesViewModel.isLoading {
                        ProgressView()
                    } else if fixedExpensesViewModel.fixedExpenses.isEmpty {
                        Text("No fixed expenses yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(fixedExpensesViewModel.fixedExpenses, id: \.id) { expense in
                            fixedExpenseRow(expense, viewModel: fixedExpensesViewModel)
                        }
                    }

                    if let errorMessage = fixedExpensesViewModel.errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
                .refreshable {
                    await fixedExpensesViewModel.load()
                }
            } else {
                ProgressView()
            }
        }
    }

    private static let logger = AppLogger.logger("ExpensePlan")

    private func fixedExpenseRow(_ expense: Wellspent_V1_FixedExpense, viewModel: FixedExpenseTemplatesViewModel) -> some View {
        UpcomingFixedExpenseRow(
            expense: expense,
            viewModel: viewModel,
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier,
            canEdit: canEdit,
            onEdit: {
                Self.logger.info("fixedExpenseRow: edit tapped for \(expense.id, privacy: .public) canEdit=\(self.canEdit, privacy: .public)")
                activeSheet = .editFixedExpense(expense)
            }
        )
        .swipeActions {
            if canEdit {
                Button(role: .destructive) {
                    Task { await viewModel.deleteTemplate(expense) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityIdentifier("deleteFixedExpenseTemplate_\(expense.name)")
            }
        }
    }

    /// Says whether the amount on the right is a manual plan, derived from
    /// fixed expenses, or both — the server never adds the two, so with both
    /// the manual amount is the figure and this line shows what fixed bills
    /// already take out of it.
    @ViewBuilder
    private func planSourceLabel(
        _ source: ExpensePlanCalculations.PlanAmountSource,
        allocated: (units: Int64, nanos: Int32),
        fixedDue: (units: Int64, nanos: Int32),
        categoryName: String
    ) -> some View {
        switch source {
        case .none:
            EmptyView()
        case .manual:
            sourceTag(Text("Manual"), id: "planCategorySource_\(categoryName)")
        case .fixed:
            sourceTag(Text("From fixed expenses"), id: "planCategorySource_\(categoryName)")
        case .manualAndFixed:
            let room = ExpensePlanCalculations.roomLeft(allocated: allocated, fixedDue: fixedDue)
            let over = MoneyFormatting.isNegative(units: room.units, nanos: room.nanos)
            let fixedText = displayText(fixedDue)
            let roomText = displayText(over ? (-room.units, -room.nanos) : room)
            HStack(spacing: 6) {
                sourceTag(Text("Manual"), id: "planCategorySource_\(categoryName)")
                (over
                    ? Text("\(fixedText) fixed · \(roomText) over the manual amount")
                    : Text("\(fixedText) fixed · \(roomText) other spending"))
                    .font(.caption)
                    .foregroundStyle(over ? .orange : .secondary)
                    .accessibilityIdentifier("planCategoryBreakdown_\(categoryName)")
            }
        }
    }

    private func sourceTag(_ text: Text, id: String) -> some View {
        text
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
            .accessibilityIdentifier(id)
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
            authenticatedRESTClient: RESTClient.makePublicClient(baseURL: "http://localhost:1"),
            currencyCode: "USD",
            localeIdentifier: "en",
            isAddCategoryPresented: .constant(false),
            isAddFixedExpensePresented: .constant(false),
            selectedSubTab: .constant(.categories),
            isActive: true,
            canEdit: true
        )
    }

}
