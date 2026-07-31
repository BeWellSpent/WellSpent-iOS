import SwiftUI
import WellSpentAPI

struct ExpensePlanView: View {
    let budgetPeriodID: String
    let budgetProfileID: String
    let authenticatedClient: ProtocolClient
    let currencyCode: String
    let localeIdentifier: String

    @State private var viewModel: ExpensePlanViewModel?
    @State private var isAddCategoryPresented = false
    @State private var allocatingCategory: Wellspent_V1_Category?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Expense Plan")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddCategoryPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addPlanCategoryButton")
            }
        }
        .task {
            guard viewModel == nil else { return }
            let model = ExpensePlanViewModel(
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
                        categoryRow(category, viewModel: viewModel)
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

    private func categoryRow(_ category: Wellspent_V1_Category, viewModel: ExpensePlanViewModel) -> some View {
        Button {
            allocatingCategory = category
        } label: {
            HStack {
                Text(category.name)
                    .foregroundStyle(.primary)
                Spacer()
                Text(displayText(viewModel.plannedTotal(for: category)))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
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
            localeIdentifier: "en"
        )
    }
}
