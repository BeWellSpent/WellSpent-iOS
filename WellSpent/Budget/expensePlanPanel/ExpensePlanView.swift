import os
import SwiftUI
import WellSpentAPI
import WellSpentREST

/// Plan's two sub-tabs: Commitment (reading the whole plan) and Fixed expenses
/// (maintaining the templates). Not private: the toolbar "+" in
/// `BudgetDetailView` opens Add Category or Add Fixed Expense by which is active.
enum PlanSubTab: Hashable, CaseIterable {
    case commitment
    case fixedExpenses

    var title: String {
        let locale = AppLanguageStore.currentLocale
        switch self {
        case .commitment: return String(localized: "Commitment", bundle: AppLanguageStore.currentBundle, locale: locale)
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
                Text(PlanSubTab.commitment.title).tag(PlanSubTab.commitment)
                Text(PlanSubTab.fixedExpenses.title).tag(PlanSubTab.fixedExpenses)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])
            .accessibilityIdentifier("planSubTabPicker")

            Group {
                switch selectedSubTab {
                case .commitment:
                    if let viewModel, let fixedExpensesViewModel {
                        PlanCommitmentView(
                            viewModel: viewModel,
                            templatesViewModel: fixedExpensesViewModel,
                            currencyCode: currencyCode,
                            localeIdentifier: localeIdentifier,
                            canEdit: canEdit,
                            onAllocate: { activeSheet = .allocate($0) },
                            onEditFixedExpense: { activeSheet = .editFixedExpense($0) }
                        )
                    } else {
                        ProgressView()
                    }
                case .fixedExpenses:
                    if let viewModel, let fixedExpensesViewModel {
                        PlanFixedExpensesView(
                            templatesViewModel: fixedExpensesViewModel,
                            planViewModel: viewModel,
                            currencyCode: currencyCode,
                            localeIdentifier: localeIdentifier,
                            canEdit: canEdit
                        ) { expense in
                            activeSheet = .editFixedExpense(expense)
                        }
                    } else {
                        ProgressView()
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Plan")
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
            selectedSubTab: .constant(.commitment),
            isActive: true,
            canEdit: true
        )
    }

}
