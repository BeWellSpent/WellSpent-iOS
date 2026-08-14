import SwiftUI
import WellSpentAPI

struct ExpenseOverviewListView: View {
    let budgetPeriodID: String
    let budgetProfileID: String
    let authenticatedClient: ProtocolClient
    let currencyCode: String
    let localeIdentifier: String

    @State private var viewModel: ExpenseOverviewViewModel?
    /// Defaults to bar, matching web's `ExpenseOverviewPanel.tsx` (Plan's
    /// chart defaults to pie instead — see `ExpensePlanView`).
    /// nil until the person's saved preference has loaded, so the chart isn't
    /// drawn as a pie and then snapped to a bar a moment later. Set from the
    /// toggle too, which overrides the saved default for this visit only —
    /// Preferences is the only place that writes one.
    @State private var chartTypeOverride: ExpenseChartView.ChartType?
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            if viewModel == nil {
                viewModel = ExpenseOverviewViewModel(
                    budgetPeriodID: budgetPeriodID,
                    budgetProfileID: budgetProfileID,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier,
                    authenticatedClient: authenticatedClient
                )
            }
            await viewModel?.load()
        }
        .refreshable {
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(viewModel: ExpenseOverviewViewModel) -> some View {
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
                    Text("No spending yet this period.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.visibleCategories, id: \.id) { category in
                        categoryDisclosure(category, viewModel: viewModel)
                    }
                }

                let uncategorized = viewModel.uncategorizedTotal
                if uncategorized.units != 0 || uncategorized.nanos != 0 {
                    LabeledContent("Uncategorized", value: displayText(uncategorized))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("overviewUncategorizedTotal")
                }
            }

            Section {
                let income = viewModel.incomeTotal
                let actual = viewModel.totalActual
                let planned = viewModel.totalPlanned
                let actualRemainder = viewModel.remainderTotal
                let plannedRemainder = viewModel.plannedRemainderTotal
                let overBudget = viewModel.totalOverBudgetAmount
                let unplanned = viewModel.totalUnplannedAmount

                LabeledContent("Income", value: displayText(income))
                    .accessibilityIdentifier("overviewIncomeTotal")
                LabeledContent("Actual", value: displayText(actual))
                    .accessibilityIdentifier("overviewActualTotal")
                LabeledContent("Planned", value: displayText(planned))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("overviewPlannedTotal")
                if income.units != 0 || income.nanos != 0 {
                    LabeledContent("Remaining (actual)", value: displayText(actualRemainder))
                        .foregroundStyle(actualRemainder.units < 0 ? .red : .green)
                        .accessibilityIdentifier("overviewActualRemainderTotal")
                    LabeledContent("Remaining (planned)", value: displayText(plannedRemainder))
                        .foregroundStyle(plannedRemainder.units < 0 ? .red : .green)
                        .accessibilityIdentifier("overviewPlannedRemainderTotal")
                }
                if overBudget.units != 0 || overBudget.nanos != 0 {
                    LabeledContent("Over budget", value: displayText(overBudget))
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("overviewOverBudgetTotal")
                }
                if unplanned.units != 0 || unplanned.nanos != 0 {
                    LabeledContent("Unplanned", value: displayText(unplanned))
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("overviewUnplannedTotal")
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
    }

    private func categoryDisclosure(_ category: Wellspent_V1_Category, viewModel: ExpenseOverviewViewModel) -> some View {
        DisclosureGroup {
            ForEach(viewModel.people, id: \.id) { person in
                personRow(category, person, viewModel: viewModel)
            }
            transactionList(for: category, viewModel: viewModel)
        } label: {
            categoryRow(category, viewModel: viewModel)
        }
        .accessibilityIdentifier("overviewCategoryRow_\(category.name)")
    }

    private func categoryRow(_ category: Wellspent_V1_Category, viewModel: ExpenseOverviewViewModel) -> some View {
        let actual = viewModel.actualTotal(for: category)
        let planned = viewModel.plannedTotal(for: category)
        let isOver = viewModel.isOver(for: category)

        return HStack {
            ColorDotView(hex: category.color)
            Text(category.name)
            Spacer()
            overspendChip(actual: actual, planned: planned, isOver: isOver)
            amountColumn(actual: actual, planned: planned, isOver: isOver)
        }
    }

    private func personRow(_ category: Wellspent_V1_Category, _ person: Wellspent_V1_BudgetPerson, viewModel: ExpenseOverviewViewModel) -> some View {
        let actual = viewModel.actualTotal(for: category, person: person)
        let planned = viewModel.plannedTotal(for: category, person: person)
        let isOver = viewModel.isOver(for: category, person: person)

        return HStack {
            ColorDotView(hex: person.color, diameter: 8)
            Text(person.userName)
                .foregroundStyle(.secondary)
            Spacer()
            overspendChip(actual: actual, planned: planned, isOver: isOver)
            amountColumn(actual: actual, planned: planned, isOver: isOver)
        }
        .accessibilityIdentifier("overviewPersonRow_\(category.name)_\(person.userName)")
    }

    /// Actual on top, planned underneath as a caption — shows the
    /// comparison web's separate Planned table column shows, in the space
    /// a single mobile row has available.
    private func amountColumn(actual: (units: Int64, nanos: Int32), planned: (units: Int64, nanos: Int32), isOver: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(displayText(actual))
                .foregroundStyle(isOver ? .red : .secondary)
            if planned.units != 0 || planned.nanos != 0 {
                Text("of \(displayText(planned)) planned")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func transactionList(for category: Wellspent_V1_Category, viewModel: ExpenseOverviewViewModel) -> some View {
        let dayGroups = TransactionDayGrouping.group(viewModel.transactions(for: category))
        if !dayGroups.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(dayGroups) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TransactionDayGrouping.headerText(for: group.id, localeIdentifier: localeIdentifier))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        ForEach(group.transactions, id: \.id) { transaction in
                            HStack {
                                Text(transaction.name)
                                    .font(.caption)
                                Spacer()
                                Text(displayText((units: transaction.amount.units, nanos: transaction.amount.nanos)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.leading, 12)
            .padding(.vertical, 2)
            .accessibilityIdentifier("overviewTransactionList_\(category.name)")
        }
    }

    @ViewBuilder
    private func overspendChip(actual: (units: Int64, nanos: Int32), planned: (units: Int64, nanos: Int32), isOver: Bool) -> some View {
        if isOver {
            let over = TransactionAmountFormatting.sum([actual, (units: -planned.units, nanos: -planned.nanos)])
            Text("+\(displayText(over))")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(Capsule())
        }
    }

    private func displayText(_ amount: (units: Int64, nanos: Int32)) -> String {
        MoneyFormatting.format(units: amount.units, nanos: amount.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }


    /// Saved preference for this tab, falling back to the shared default when
    /// the person hasn't chosen or isn't a linked member. Read from `people`,
    /// which the view model already loads — no extra request.
    private func savedChartType(_ people: [Wellspent_V1_BudgetPerson]) -> ExpenseChartView.ChartType {
        let me = ChartPreference.myPerson(currentUserID: session.userID, people: people)
        return ChartPreference.chartType(for: me?.overviewChartType ?? .unspecified)
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
        ExpenseOverviewListView(
            budgetPeriodID: "preview-period",
            budgetProfileID: "preview-budget",
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
            currencyCode: "USD",
            localeIdentifier: "en"
        )
    }

}
