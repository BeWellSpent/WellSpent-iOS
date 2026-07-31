import Foundation
import SwiftUI
import WellSpentAPI

struct BudgetListView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel: BudgetListViewModel?
    @State private var isCreateSheetPresented = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Budgets")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isCreateSheetPresented = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityIdentifier("addBudgetButton")
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Log Out", role: .destructive) {
                            session.endSession()
                        }
                        .accessibilityIdentifier("logoutButton")
                    }
                }
                .sheet(isPresented: $isCreateSheetPresented) {
                    if let authenticatedClient = session.authenticatedClient {
                        CreateBudgetSheet(authenticatedClient: authenticatedClient) { profile in
                            viewModel?.addCreatedProfile(profile)
                        }
                    }
                }
                .task {
                    guard viewModel == nil, let authenticatedClient = session.authenticatedClient else { return }
                    let model = BudgetListViewModel(authenticatedClient: authenticatedClient)
                    viewModel = model
                    await model.load()
                }
                .refreshable {
                    await viewModel?.load()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let viewModel {
            VStack(spacing: 0) {
                if let user = viewModel.currentUser, !user.isVerified {
                    VerifyEmailBannerView(publicClient: session.publicClient, email: user.email)
                        .padding([.horizontal, .top])
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                if viewModel.isLoading && viewModel.profiles.isEmpty {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if viewModel.profiles.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    budgetList(viewModel: viewModel)
                }

                versionFooter
            }
        } else {
            ProgressView()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No budgets yet")
                .font(.headline)
            Text("Tap + to create your first budget.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("emptyBudgetsState")
    }

    private func budgetList(viewModel: BudgetListViewModel) -> some View {
        List {
            ForEach(viewModel.profiles, id: \.id) { profile in
                NavigationLink {
                    BudgetDetailView(
                        profile: profile,
                        authenticatedClient: session.authenticatedClient,
                        currencyCode: viewModel.currencyCode,
                        localeIdentifier: viewModel.localeIdentifier,
                        onUpdated: { updated in viewModel.replaceProfile(updated) },
                        onDeleted: { viewModel.removeProfile(id: profile.id) }
                    )
                } label: {
                    VStack(alignment: .leading) {
                        Text(profile.name)
                            .font(.headline)
                        Text(BudgetCycleLabel.text(for: profile.cycle))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("budgetRow_\(profile.name)")
            }
            .onDelete { offsets in
                for index in offsets {
                    let profile = viewModel.profiles[index]
                    Task { await viewModel.delete(profile) }
                }
            }
        }
        .listStyle(.plain)
    }

    private var versionFooter: some View {
        Group {
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("v\(version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 8)
            }
        }
    }
}
