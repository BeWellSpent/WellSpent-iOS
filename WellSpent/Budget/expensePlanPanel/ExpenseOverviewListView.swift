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
                    // Orange and semibold, like web: unattributed spend is a
                    // thing to go and fix, not a neutral line item.
                    LabeledContent {
                        Text(overviewText(uncategorized))
                            .foregroundStyle(.orange)
                            .fontWeight(.semibold)
                    } label: {
                        Text("Uncategorized")
                            .foregroundStyle(.secondary)
                    }
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
                LabeledContent("Actual", value: overviewText(actual))
                    .accessibilityIdentifier("overviewActualTotal")
                LabeledContent("Planned", value: displayText(planned))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("overviewPlannedTotal")
                if income.units != 0 || income.nanos != 0 {
                    // isNegative, not `units < 0`: a -$0.50 remainder has
                    // units == 0 and would otherwise read green.
                    LabeledContent("Remaining (actual)", value: displayText(actualRemainder))
                        .foregroundStyle(MoneyFormatting.isNegative(units: actualRemainder.units, nanos: actualRemainder.nanos) ? .red : .green)
                        .accessibilityIdentifier("overviewActualRemainderTotal")
                    LabeledContent("Remaining (planned)", value: displayText(plannedRemainder))
                        .foregroundStyle(MoneyFormatting.isNegative(units: plannedRemainder.units, nanos: plannedRemainder.nanos) ? .red : .green)
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
        let groups = viewModel.transactionGroups(for: category)
        return DisclosureGroup {
            ForEach(viewModel.people, id: \.id) { person in
                personRow(category, person, viewModel: viewModel)
                transactionList(groups.byPerson[person.id] ?? [], category: category, owner: person.userName)
            }
            // Spending that belongs to nobody — cash, or a payment method with
            // no person. It counts toward the category total but toward no
            // person's, so it cannot sit under a name without making that
            // person's rows contradict their own figure.
            if !groups.unclaimed.isEmpty {
                if viewModel.people.count > 1 {
                    Text("Unattributed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                transactionList(groups.unclaimed, category: category, owner: "unattributed")
            }
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
            Text(category.displayName)
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
        let tone = OverviewAmountFormatting.tone(actual: actual, planned: planned, isOver: isOver)
        return VStack(alignment: .trailing, spacing: 0) {
            Text(overviewText(actual))
                .foregroundStyle(Self.style(for: tone))
            if planned.units != 0 || planned.nanos != 0 {
                Text("of \(displayText(planned)) planned")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// One owner's transactions, flat and newest-first, sitting directly under
    /// that owner's row.
    ///
    /// This used to render every transaction in the category, day-grouped,
    /// which is what made it impossible to tell who had spent what (issue #62).
    /// The day headers went with the change: the person is the grouping this
    /// view is about, and person → day → transaction is a lot of nesting on a
    /// phone. The Transactions tab is still where you browse by day.
    @ViewBuilder
    private func transactionList(
        _ transactions: [Wellspent_V1_Transaction],
        category: Wellspent_V1_Category,
        owner: String
    ) -> some View {
        if !transactions.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(transactions, id: \.id) { transaction in
                    HStack {
                        Text(transaction.name)
                            .font(.caption)
                        Spacer()
                        Text(transaction.date.dateOnly.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        // A transaction row, so it reads exactly as it does on
                        // the Transactions tab: -$X out, +$X in. It showed an
                        // unsigned magnitude here, so the same row disagreed
                        // with itself across tabs.
                        Text(TransactionAmountFormatting.displayText(
                            units: transaction.amount.units,
                            nanos: transaction.amount.nanos,
                            currencyCode: currencyCode,
                            localeIdentifier: localeIdentifier
                        ))
                        .font(.caption)
                        .foregroundStyle(
                            TransactionAmountFormatting.isReceived(
                                units: transaction.amount.units,
                                nanos: transaction.amount.nanos
                            ) ? .green : .secondary
                        )
                    }
                }
            }
            .padding(.leading, 24)
            .padding(.vertical, 2)
            .accessibilityIdentifier("overviewTransactionList_\(category.name)_\(owner)")
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

    /// How each tone paints. Kept beside the view rather than in the pure
    /// helper so `OverviewAmountFormatting` needn't import SwiftUI.
    private static func style(for tone: OverviewAmountFormatting.Tone) -> AnyShapeStyle {
        switch tone {
        case .received, .withinPlan: AnyShapeStyle(Color.green)
        case .over: AnyShapeStyle(Color.red)
        case .unplanned: AnyShapeStyle(HierarchicalShapeStyle.secondary)
        case .zero: AnyShapeStyle(HierarchicalShapeStyle.tertiary)
        }
    }

    /// Actual-spend amounts, which are the only ones here that can net
    /// negative. `displayText` still serves the amounts that can't — planned,
    /// income, over-budget, unplanned — and the remainders, where a negative
    /// means "past your income" rather than "received".
    private func overviewText(_ amount: (units: Int64, nanos: Int32)) -> String {
        OverviewAmountFormatting.text(amount, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
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
