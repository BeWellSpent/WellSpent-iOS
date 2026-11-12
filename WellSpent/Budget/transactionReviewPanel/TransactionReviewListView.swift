import SwiftUI
import WellSpentAPI
import WellSpentREST

/// The Review tab: every pending match, from any period, grouped under a
/// collapsible header per period and filterable by period, strength and source.
///
/// The view model is owned by `BudgetDetailView`, since the pending count backs
/// the tab's badge on every other tab too.
struct TransactionReviewListView: View {
    let viewModel: TransactionReviewViewModel?
    let periods: [Wellspent_V1_BudgetPeriod]
    let currentPeriodID: String?
    let currencyCode: String
    let localeIdentifier: String
    /// Reloads when the tab is selected again, since `TabView` keeps every tab mounted.
    let isActive: Bool
    let canEdit: Bool
    /// Lets the caller force a Transactions reload after a confirm.
    var onConfirmed: () -> Void = {}

    @State private var filter = ReviewFilter()
    @State private var collapsed: Set<String> = []

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: isActive) { _, newValue in
            if newValue {
                Task { await viewModel?.load() }
            }
        }
        .refreshable {
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(viewModel: TransactionReviewViewModel) -> some View {
        let groups = ReviewGrouping.group(viewModel.pendingReviews)
        let sections = ReviewPeriodSections.build(groups: groups, periods: periods, currentPeriodID: currentPeriodID, filter: filter)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if groups.isEmpty && viewModel.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if groups.isEmpty {
                    emptyState
                } else {
                    header(groups: groups, sections: sections)
                    filterBar(groups: groups)
                    if sections.isEmpty {
                        Text("No matches fit these filters.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                    ForEach(sections) { section in
                        periodSection(section, viewModel: viewModel)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    InlineErrorBanner(message: errorMessage)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: Header and filters

    private func header(groups: [ReviewGroup], sections: [ReviewPeriodSection]) -> some View {
        let periodCount = Set(groups.compactMap { $0.reviews.first?.budgetPeriodID }).count
        let anyOpen = sections.contains { !collapsed.contains($0.periodID) }
        return HStack(alignment: .firstTextBaseline) {
            Text("\(groups.count) matches waiting across \(periodCount) periods")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button(anyOpen ? "Collapse all" : "Expand all") {
                collapsed = anyOpen ? Set(sections.map(\.periodID)) : []
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .accessibilityIdentifier("reviewToggleAllButton")
        }
        .padding(.horizontal, 4)
    }

    private func filterBar(groups: [ReviewGroup]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Period", selection: $filter.periodID) {
                        Text("All periods").tag(String?.none)
                        ForEach(ReviewPeriodSections.periodsWithMatches(groups: groups, periods: periods), id: \.id) { period in
                            Text(verbatim: periodName(period)).tag(Optional(period.id))
                        }
                    }
                } label: {
                    FilterChipLabel(
                        title: filter.periodID.flatMap { id in periods.first { $0.id == id }.map(periodName) } ?? String(localized: "All periods", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale),
                        systemImage: "calendar",
                        isOn: filter.periodID != nil,
                        showsMenuIndicator: true
                    )
                }
                .accessibilityIdentifier("reviewPeriodFilter")

                chip(Text("Strong matches"), isOn: filter.strength == .strong, id: "reviewStrongFilter") {
                    filter.strength = filter.strength == .strong ? .any : .strong
                }
                chip(Text("Possible"), isOn: filter.strength == .possible, id: "reviewPossibleFilter") {
                    filter.strength = filter.strength == .possible ? .any : .possible
                }
                chip(Text("Bank only"), isOn: filter.bankOnly, id: "reviewBankOnlyFilter") {
                    filter.bankOnly.toggle()
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: Text, isOn: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            FilterChipLabel(title: title, isOn: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityIdentifier(id)
    }

    // MARK: Sections

    private func periodName(_ period: Wellspent_V1_BudgetPeriod) -> String {
        period.startDate.dateOnly.formatted(Date.FormatStyle(locale: Locale(identifier: localeIdentifier)).month(.wide).year())
    }

    @ViewBuilder
    private func periodSection(_ section: ReviewPeriodSection, viewModel: TransactionReviewViewModel) -> some View {
        let isOpen = !collapsed.contains(section.periodID)
        Button {
            if isOpen { collapsed.insert(section.periodID) } else { collapsed.remove(section.periodID) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        if let period = section.period {
                            Text(verbatim: periodName(period)).font(.headline)
                        } else {
                            Text("Other").font(.headline)
                        }
                        periodTag(section)
                    }
                    if let period = section.period {
                        Text(verbatim: PeriodGrouping.label(for: period, localeIdentifier: localeIdentifier))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Spacer()
                Text(verbatim: "\(section.groups.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(Color.accentColor, in: Capsule())
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOpen ? Text("Expanded") : Text("Collapsed"))
        .accessibilityIdentifier("reviewPeriodHeader_\(section.periodID)")

        if isOpen {
            ForEach(section.groups) { group in
                ReviewMatchCard(
                    group: group,
                    spansOutsideMyView: viewModel.spansOutsideMyView(group),
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier,
                    canEdit: canEdit,
                    onDismiss: { Task { await viewModel.dismissGroup(group) } },
                    onConfirm: {
                        Task {
                            await viewModel.confirmGroup(group)
                            onConfirmed()
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func periodTag(_ section: ReviewPeriodSection) -> some View {
        let isClosed = section.period?.isArchived ?? false
        if section.isCurrent || isClosed {
            (section.isCurrent ? Text("Current") : Text("Closed"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(section.isCurrent ? Color.accentColor : .secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(section.isCurrent ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill), in: Capsule())
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.title2.weight(.bold))
                .foregroundStyle(.green)
                .frame(width: 52, height: 52)
                .background(Color.green.opacity(0.14), in: Circle())
            Text("Nothing to review").font(.headline)
            Text("When a bank import or a transaction you type looks like one of your bills, it waits here so it isn't counted twice.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .padding(.top, 40)
        .accessibilityIdentifier("transactionReviewEmptyState")
    }
}

/// A filter pill: outlined when off, tinted when on.
private struct FilterChipLabel: View {
    let title: Text
    var systemImage: String?
    let isOn: Bool
    var showsMenuIndicator = false

    init(title: Text, systemImage: String? = nil, isOn: Bool, showsMenuIndicator: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.isOn = isOn
        self.showsMenuIndicator = showsMenuIndicator
    }

    init(title: String, systemImage: String? = nil, isOn: Bool, showsMenuIndicator: Bool = false) {
        self.init(title: Text(verbatim: title), systemImage: systemImage, isOn: isOn, showsMenuIndicator: showsMenuIndicator)
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            title
            if showsMenuIndicator { Image(systemName: "chevron.down").font(.caption2.weight(.bold)) }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(isOn ? Color.accentColor : .primary)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(isOn ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground), in: Capsule())
        .overlay(Capsule().strokeBorder(isOn ? Color.accentColor : Color(.separator)))
    }
}

#Preview {
    NavigationStack {
        TransactionReviewListView(
            viewModel: TransactionReviewViewModel(
                budgetProfileID: "preview-budget",
                restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
            ),
            periods: [],
            currentPeriodID: nil,
            currencyCode: "USD",
            localeIdentifier: "en",
            isActive: true,
            canEdit: true
        )
    }
}
