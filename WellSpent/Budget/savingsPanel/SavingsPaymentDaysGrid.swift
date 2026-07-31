import SwiftUI

/// A grid of every calendar day in the active period's month; tapping toggles
/// membership in `selectedDays`, capped at `maxSelectable`. The *count* of
/// selected days is the savings source's frequency (1=monthly, 2=bi-weekly,
/// 4=weekly) — there is no separate frequency picker, matching web's
/// `AddSavingsDialog`/`EditSavingsModal`. Shared between Add and Edit since
/// both render the exact same grid.
struct SavingsPaymentDaysGrid: View {
    @Binding var selectedDays: [Int]
    let daysInMonth: Int
    var maxSelectable: Int = 4

    private let columns = Array(repeating: GridItem(.flexible(minimum: 32)), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Payment days")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                let label = SavingsFrequencyLabel.text(forDayCount: selectedDays.count)
                if !label.isEmpty {
                    Text("— \(label)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tint)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(1...daysInMonth, id: \.self) { day in
                    dayButton(day)
                }
            }

            Text("Select 1, 2, or 4 days.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func dayButton(_ day: Int) -> some View {
        let isSelected = selectedDays.contains(day)
        return Button {
            toggle(day)
        } label: {
            Text("\(day)")
                .font(.caption)
                .frame(width: 32, height: 32)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("savingsPaymentDay_\(day)")
    }

    private func toggle(_ day: Int) {
        if let index = selectedDays.firstIndex(of: day) {
            selectedDays.remove(at: index)
        } else {
            guard selectedDays.count < maxSelectable else { return }
            selectedDays.append(day)
            selectedDays.sort()
        }
    }
}

#Preview {
    Form {
        SavingsPaymentDaysGrid(selectedDays: .constant([5, 20]), daysInMonth: 31)
    }
}
