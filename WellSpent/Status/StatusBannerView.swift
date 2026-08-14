import SwiftUI
import WellSpentAPI

/// The operator-authored status strip pinned above the whole app.
///
/// Lives outside the authenticated tree on purpose — it renders above the login
/// screen, the verification gate, and the budget list alike.
struct StatusBannerView: View {
    @Bindable var viewModel: StatusBannerViewModel

    var body: some View {
        if let banner = viewModel.visibleBanner {
            let severity = banner.severity
            let foreground = StatusBannerPresentation.foreground(for: severity)
            let message = StatusBannerPresentation.message(for: banner)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: StatusBannerPresentation.systemImage(for: severity))
                        .accessibilityHidden(true)

                    Text(message)
                        // Collapsed to one line with a "learn more" toggle,
                        // rather than letting a 300-character notice push the
                        // app itself off a phone screen.
                        .lineLimit(viewModel.isExpanded ? nil : 1)
                        .fixedSize(horizontal: false, vertical: viewModel.isExpanded)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("statusBannerMessage")

                    if StatusBannerPresentation.isDismissible(severity) {
                        Button {
                            withAnimation { viewModel.dismiss() }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Dismiss", comment: "Status banner close button"))
                        .accessibilityIdentifier("statusBannerDismissButton")
                    }
                }

                // Shown whenever the text could plausibly need it. SwiftUI
                // gives no reliable "was this truncated" signal without a
                // second layout pass, so this leans on the length instead —
                // over-offering the toggle is harmless, hiding it behind a
                // wrong guess is not.
                if message.count > Self.singleLineCharacterEstimate || viewModel.isExpanded {
                    Button {
                        withAnimation { viewModel.toggleExpanded() }
                    } label: {
                        Text(viewModel.isExpanded
                             ? String(localized: "Show less", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
                             : String(localized: "Learn more", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale))
                            .font(.footnote.weight(.semibold))
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("statusBannerExpandButton")
                }
            }
            .font(.footnote)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StatusBannerPresentation.background(for: severity))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("statusBanner")
        }
    }

    /// Roughly what fits on one line at footnote size on the narrowest
    /// supported device. Deliberately conservative.
    private static let singleLineCharacterEstimate = 40
}

#Preview {
    let viewModel = StatusBannerViewModel(publicClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
    return VStack(spacing: 0) {
        StatusBannerView(viewModel: viewModel)
        Spacer()
    }
    .task {
        viewModel.setStateForTesting(banner: .with {
            $0.id = "preview"
            $0.severity = .warning
            $0.messageEn = "Bank syncing is delayed while we work with our provider on a fix."
        })
    }
}
