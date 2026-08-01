import SwiftUI
import WellSpentAPI

/// "Coming soon" placeholder — matches web's `ReportsPlaceholder.tsx`.
/// Reachable via `NavigationLink` inside `BudgetManageView` rather than a
/// 5th bottom tab, since it's placeholder-only for now (see
/// `docs/features/tiered-subscriptions.md`); promoting it to a full
/// `BudgetSection` tab is a one-line change once Reports is a real feature.
struct ReportsPlaceholderView: View {
    let authenticatedClient: ProtocolClient

    @State private var viewModel: ReportsPlaceholderViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Reports are coming soon")
                        .font(.headline)
                    Text("Aggregated spending trends across budget periods will land here in a future update.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("reportsPlaceholderCard")

                if viewModel?.isFree == true {
                    AdBannerView()
                        .frame(height: 50)
                        .accessibilityIdentifier("reportsAdBanner")
                }
            }
            .padding()
        }
        .navigationTitle("Reports")
        .task {
            if viewModel == nil {
                viewModel = ReportsPlaceholderViewModel(authenticatedClient: authenticatedClient)
            }
            await viewModel?.load()
        }
    }
}

#Preview {
    NavigationStack {
        ReportsPlaceholderView(authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
    }
}
