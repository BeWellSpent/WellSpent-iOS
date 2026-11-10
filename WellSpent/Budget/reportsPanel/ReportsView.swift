import SwiftUI
import WellSpentAPI
import WellSpentREST

/// The Reports tab: Category trends and the Plan scorecard, with a person filter
/// (docs/features/reports.md). Free sees the current period and the 3 before
/// it; locked content says "Pro — coming soon".
struct ReportsView: View {
    let budgetProfileID: String
    let currencyCode: String
    let localeIdentifier: String
    let authenticatedRESTClient: WellSpentREST.Client

    @State private var viewModel: ReportsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Reports")
        .task {
            if viewModel == nil {
                viewModel = ReportsViewModel(budgetProfileID: budgetProfileID, currencyCode: currencyCode, localeIdentifier: localeIdentifier, restClient: authenticatedRESTClient)
            }
            await viewModel?.load()
        }
    }

    private func content(_ viewModel: ReportsViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    planBadge(isPro: viewModel.isPro)
                }

                // The system control, like every other sub-tab switch in the app (Home, Plan).
                Picker("Report", selection: Binding(get: { viewModel.report }, set: { viewModel.report = $0 })) {
                    Text("Trends").tag(ReportsViewModel.Report.trends)
                    Text("Scorecard").tag(ReportsViewModel.Report.scorecard)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("reportsPicker")

                personChips(viewModel)

                switch viewModel.report {
                case .trends:
                    CategoryTrendsReportView(viewModel: viewModel)
                case .scorecard:
                    PlanScorecardReportView(viewModel: viewModel)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if !viewModel.isPro {
                    AdBannerView()
                        .frame(height: 50)
                        .accessibilityIdentifier("reportsAdBanner")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await viewModel.load() }
        .accessibilityIdentifier("reportsView")
    }

    /// Which plan these reports are drawn for, so locked content has a reason on screen.
    private func planBadge(isPro: Bool) -> some View {
        (isPro ? Text("Pro") : Text("Free"))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isPro ? Color.accentColor : .secondary)
            .background((isPro ? Color.accentColor : Color.secondary).opacity(0.15), in: Capsule())
            .accessibilityIdentifier("reportsPlanBadge")
    }

    private func personChips(_ viewModel: ReportsViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(Text("Everyone"), selected: viewModel.personID == nil, id: "reportsPerson_everyone") {
                    Task { await viewModel.selectPerson(nil) }
                }
                ForEach(viewModel.people, id: \.id) { person in
                    chip(Text(person.userName), selected: viewModel.personID == person.id, id: "reportsPerson_\(person.userName)") {
                        Task { await viewModel.selectPerson(person.id) }
                    }
                }
            }
        }
    }

    private func chip(_ label: Text, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.primary : Color(.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(selected ? Color(.systemBackground) : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// The reports' small in-card switch (range, units): a grey track with the
/// selected option raised on a lighter segment, in both light and dark mode.
struct PillSegmentedControl<Value: Hashable>: View {
    let options: [(Value, Text)]
    @Binding var selection: Value
    var disabled: Set<Value> = []

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.0 == selection
                let isDisabled = disabled.contains(option.0)
                Button {
                    selection = option.0
                } label: {
                    option.1
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(selected ? .primary : (isDisabled ? .tertiary : .secondary))
                        .padding(.horizontal, 10)
                        .frame(minWidth: 40, minHeight: 30)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(pillSelectedFill)
                                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// White in light mode; in dark, lighter than the track so it reads as raised, not sunk.
private let pillSelectedFill = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .systemGray3 : .white })

/// 3, 6 or 12 periods; the longer ranges are locked on Free.
struct ReportRangePicker: View {
    let viewModel: ReportsViewModel

    var body: some View {
        let locked = Set(ReportsCalculations.trendRanges.filter { ReportsCalculations.isRangeLocked($0, isPro: viewModel.isPro) })
        PillSegmentedControl(
            options: ReportsCalculations.trendRanges.map { range in
                (range, locked.contains(range) ? Text("\(range) periods") + Text(verbatim: " ") + Text(Image(systemName: "lock.fill")).font(.caption2) : Text("\(range) periods"))
            },
            selection: Binding(get: { viewModel.range }, set: { newRange in Task { await viewModel.selectRange(newRange) } }),
            disabled: locked
        )
        .accessibilityIdentifier("reportsRangePicker")
    }
}

/// The reports' one-line Free note.
struct ProUpsellNote: View {
    var body: some View {
        Label {
            Text("Older periods and 6–12 period ranges are Pro. Pro is coming soon.")
        } icon: {
            Image(systemName: "lock.fill")
        }
        .font(.footnote)
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("reportsProNote")
    }
}

/// Shown over or instead of Pro-only content until Pro can be bought.
struct ProLockedNote: View {
    let message: Text

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                message.font(.subheadline.weight(.semibold))
                Text("Pro is coming soon").font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "lock.fill").foregroundStyle(Color.accentColor)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opaque underneath, so it stays readable when laid over blurred content.
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
