import SwiftUI
import WellSpentAPI
import WellSpentREST

struct IncomeListView: View {
    let budgetProfileID: String
    let budgetCountryCode: String
    let authenticatedRESTClient: WellSpentREST.Client
    let currencyCode: String
    let localeIdentifier: String
    let canEdit: Bool

    @Environment(SessionStore.self) private var session
    @State private var viewModel: IncomeViewModel?
    @State private var isAddSheetPresented = false
    @State private var editingJob: IncomeJobGrouping.Job?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Income")
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddSheetPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(viewModel?.isAtLimit ?? false)
                    .accessibilityIdentifier("addIncomeSourceButton")
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = IncomeViewModel(
                    budgetProfileID: budgetProfileID,
                    currentUserID: session.userID,
                    restClient: authenticatedRESTClient
                )
            }
            await viewModel?.load()
        }
        .refreshable {
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(viewModel: IncomeViewModel) -> some View {
        List {
            if viewModel.isAtLimit {
                Section {
                    Text("Free plan: income sources are limited to 2. Upgrade to Pro for unlimited sources.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("incomeLimitMessage")
                }
            }

            let jobs = IncomeJobGrouping.group(sources: viewModel.visibleSources, schedules: viewModel.scheduleByIncomeSourceID)
            if jobs.isEmpty && viewModel.isLoading {
                ProgressView()
            } else if jobs.isEmpty {
                Text("No income sources yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(jobs) { job in
                    jobRow(job, viewModel: viewModel)
                }
                .onDelete(perform: canEdit ? { offsets in
                    for index in offsets {
                        let job = jobs[index]
                        Task { await viewModel.deleteJob(job) }
                    }
                } : nil)
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .sheet(isPresented: $isAddSheetPresented) {
            AddEditIncomeView(
                mode: .add,
                budgetProfileID: budgetProfileID,
                countryCode: budgetCountryCode,
                currencyCode: currencyCode,
                people: viewModel.people,
                restClient: authenticatedRESTClient
            ) {
                // Every save — single or multi-payday — always reloads:
                // editing a schedule forks new row ids server-side, and a
                // multi-payday save issues several sequential calls that
                // may only partially land, so local optimistic state can't
                // be trusted either way.
                Task { await viewModel.load() }
            }
        }
        .sheet(isPresented: Binding(
            get: { editingJob != nil },
            set: { if !$0 { editingJob = nil } }
        )) {
            if let editingJob {
                AddEditIncomeView(
                    mode: .edit(editingJob),
                    budgetProfileID: budgetProfileID,
                    countryCode: budgetCountryCode,
                    currencyCode: currencyCode,
                    people: viewModel.people,
                    restClient: authenticatedRESTClient
                ) {
                    Task { await viewModel.load() }
                }
            }
        }
    }

    private func jobRow(_ job: IncomeJobGrouping.Job, viewModel: IncomeViewModel) -> some View {
        let firstSource = job.rows[0].source
        let total = job.totalAmount
        let jobContent = VStack(alignment: .leading, spacing: 2) {
            Text(firstSource.name)
                .font(.headline)
                .foregroundStyle(.primary)
            HStack(spacing: 4) {
                Text(MoneyFormatting.format(
                    units: total.units,
                    nanos: total.nanos,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier
                ))
                Text("· \(RecurringTypeLabel.text(for: firstSource.paymentFrequency))")
                if job.payDateCount > 1 {
                    Text("· Paid \(job.payDateCount)x")
                        .accessibilityIdentifier("incomePayDateCountBadge")
                }
                if let personName = viewModel.personName(for: firstSource.budgetPersonID) {
                    Text("·")
                    ColorDotView(hex: viewModel.personColor(for: firstSource.budgetPersonID), diameter: 8)
                    Text(personName)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        return Group {
            if canEdit {
                Button {
                    editingJob = job
                } label: {
                    jobContent
                }
                .buttonStyle(.plain)
            } else {
                jobContent
            }
        }
        .accessibilityIdentifier("incomeRow_\(firstSource.name)")
    }
}

#Preview {
    NavigationStack {
        IncomeListView(
            budgetProfileID: "preview-budget",
            budgetCountryCode: "US",
            authenticatedRESTClient: RESTClient.makePublicClient(baseURL: "http://localhost:1"),
            currencyCode: "USD",
            localeIdentifier: "en",
            canEdit: true
        )
    }
}
