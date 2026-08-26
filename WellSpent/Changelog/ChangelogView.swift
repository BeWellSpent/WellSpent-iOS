import SwiftUI
import WellSpentREST

/// The Help browser's changelog: every component's full history, including web,
/// which an iOS reader cannot see any other way.
struct ChangelogView: View {
    let authenticatedClient: WellSpentREST.Client
    let localeIdentifier: String

    @State private var viewModel: ChangelogViewModel?
    @State private var selected: ChangelogComponent = .ios

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Changelog")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                viewModel = ChangelogViewModel(authenticatedClient: authenticatedClient)
            }
            await viewModel?.load()
        }
        .refreshable { await viewModel?.load() }
    }

    @ViewBuilder
    private func content(viewModel: ChangelogViewModel) -> some View {
        VStack(spacing: 0) {
            Picker("Component", selection: $selected) {
                Text("iOS").tag(ChangelogComponent.ios)
                Text("Web").tag(ChangelogComponent.web)
                Text("Server").tag(ChangelogComponent.server)
            }
            .pickerStyle(.segmented)
            .padding()
            .accessibilityIdentifier("changelogComponentPicker")

            if viewModel.isLoading && viewModel.releases.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    ReleaseNotesList(
                        releases: viewModel.releases(for: selected),
                        localeIdentifier: localeIdentifier
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ChangelogView(
            authenticatedClient: RESTClient.makePublicClient(baseURL: "http://localhost:1"),
            localeIdentifier: "en"
        )
    }
}
