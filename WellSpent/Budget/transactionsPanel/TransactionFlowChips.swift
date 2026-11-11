import SwiftUI

/// "What was it?": one chip per flow, and what the chosen one means. Shared by the
/// transaction and fixed-expense forms.
struct TransactionFlowChips: View {
    let choices: [TransactionFlowKind]
    @Binding var selection: TransactionFlowKind

    var body: some View {
        Section {
            if choices.count > 1 {
                HStack(spacing: 8) {
                    ForEach(choices, id: \.self) { kind in
                        let selected = selection == kind
                        Button {
                            selection = kind
                        } label: {
                            Text(kind.label)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(selected ? Color.accentColor : .primary)
                                .background(selected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : Color(.separator), lineWidth: selected ? 1.5 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("transactionFlow_\(kind.rawValue)")
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Text(selection.hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("transactionFlowHint")
        } header: {
            Text("What was it?")
        }
    }
}
