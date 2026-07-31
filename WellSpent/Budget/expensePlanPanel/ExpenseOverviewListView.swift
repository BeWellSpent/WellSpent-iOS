import Charts
import SwiftUI
import WellSpentAPI

struct ExpenseOverviewListView: View {
    let budgetPeriodID: String
    let budgetProfileID: String
    let authenticatedClient: ProtocolClient
    let currencyCode: String
    let localeIdentifier: String

    @State private var viewModel: ExpenseOverviewViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            let model = ExpenseOverviewViewModel(
                budgetPeriodID: budgetPeriodID,
                budgetProfileID: budgetProfileID,
                currencyCode: currencyCode,
                localeIdentifier: localeIdentifier,
                authenticatedClient: authenticatedClient
            )
            viewModel = model
            await model.load()
        }
    }

    @ViewBuilder
    private func content(viewModel: ExpenseOverviewViewModel) -> some View {
        List {
            if !viewModel.visibleCategories.isEmpty {
                Section {
                    Chart(viewModel.visibleCategories, id: \.id) { category in
                        BarMark(
                            x: .value("Actual", amountValue(viewModel.actualTotal(for: category))),
                            y: .value("Category", category.name)
                        )
                        .foregroundStyle(viewModel.isOver(for: category) ? Color.red : Color.accentColor)
                    }
                    .frame(height: CGFloat(viewModel.visibleCategories.count) * 32 + 20)
                    .accessibilityIdentifier("overviewChart")
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
                let remainder = viewModel.remainderTotal

                LabeledContent("Income", value: displayText(income))
                    .accessibilityIdentifier("overviewIncomeTotal")
                LabeledContent("Actual", value: displayText(actual))
                    .accessibilityIdentifier("overviewActualTotal")
                LabeledContent("Remaining", value: displayText(remainder))
                    .foregroundStyle(remainder.units < 0 ? .red : .primary)
                    .accessibilityIdentifier("overviewRemainderTotal")
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
            Text(category.name)
            Spacer()
            overspendChip(actual: actual, planned: planned, isOver: isOver)
            Text(displayText(actual))
                .foregroundStyle(isOver ? .red : .secondary)
        }
    }

    private func personRow(_ category: Wellspent_V1_Category, _ person: Wellspent_V1_BudgetPerson, viewModel: ExpenseOverviewViewModel) -> some View {
        let actual = viewModel.actualTotal(for: category, person: person)
        let planned = viewModel.plannedTotal(for: category, person: person)
        let isOver = viewModel.isOver(for: category, person: person)

        return HStack {
            Text(person.userName)
                .foregroundStyle(.secondary)
            Spacer()
            overspendChip(actual: actual, planned: planned, isOver: isOver)
            Text(displayText(actual))
                .foregroundStyle(isOver ? .red : .secondary)
        }
        .accessibilityIdentifier("overviewPersonRow_\(category.name)_\(person.userName)")
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

    private func amountValue(_ amount: (units: Int64, nanos: Int32)) -> Double {
        Double(amount.units) + Double(amount.nanos) / 1_000_000_000
    }

    private func displayText(_ amount: (units: Int64, nanos: Int32)) -> String {
        MoneyFormatting.format(units: amount.units, nanos: amount.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
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
