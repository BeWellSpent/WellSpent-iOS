import SwiftUI
import WellSpentAPI

struct PaymentMethodsListView: View {
    let budgetProfileID: String
    let authenticatedClient: ProtocolClient
    let canEdit: Bool

    @State private var viewModel: PaymentMethodsViewModel?
    @State private var isAddSheetPresented = false
    @State private var editingMethod: Wellspent_V1_PaymentMethod?
    @State private var deletingMethod: Wellspent_V1_PaymentMethod?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Payment Methods")
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddSheetPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("addPaymentMethodButton")
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = PaymentMethodsViewModel(budgetProfileID: budgetProfileID, authenticatedClient: authenticatedClient)
            }
            await viewModel?.load()
        }
        .refreshable {
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(viewModel: PaymentMethodsViewModel) -> some View {
        List {
            if viewModel.methods.isEmpty && viewModel.isLoading {
                ProgressView()
            } else if viewModel.methods.isEmpty {
                Text("No payment methods yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.methods, id: \.id) { method in
                    methodRow(method, viewModel: viewModel)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .sheet(isPresented: $isAddSheetPresented) {
            AddPaymentMethodView(people: viewModel.people, authenticatedClient: authenticatedClient) { method in
                viewModel.addMethod(method)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingMethod != nil },
            set: { if !$0 { editingMethod = nil } }
        )) {
            if let editingMethod {
                EditPaymentMethodView(method: editingMethod, authenticatedClient: authenticatedClient) { updated in
                    viewModel.replaceMethod(updated)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { deletingMethod != nil },
            set: { if !$0 { deletingMethod = nil } }
        )) {
            if let deletingMethod {
                DeletePaymentMethodView(
                    method: deletingMethod,
                    otherMethods: viewModel.methods.filter { $0.id != deletingMethod.id },
                    personName: { viewModel.personName(for: $0) }
                ) { replacementID in
                    Task { await viewModel.delete(id: deletingMethod.id, replacementID: replacementID) }
                }
            }
        }
    }

    private func methodRow(_ method: Wellspent_V1_PaymentMethod, viewModel: PaymentMethodsViewModel) -> some View {
        HStack {
            ColorDotView(hex: method.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(method.alias.isEmpty ? method.name : method.alias)
                HStack(spacing: 4) {
                    Text(PaymentTypeLabel.text(for: method.type))
                    if let ownerName = viewModel.personName(for: method.budgetPersonID) {
                        Text("· \(ownerName)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if canEdit {
                Button {
                    editingMethod = method
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editPaymentMethod_\(method.name)")

                Button {
                    deletingMethod = method
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canDelete)
                .accessibilityIdentifier("deletePaymentMethod_\(method.name)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        PaymentMethodsListView(
            budgetProfileID: "preview-budget",
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
            canEdit: true
        )
    }
}
