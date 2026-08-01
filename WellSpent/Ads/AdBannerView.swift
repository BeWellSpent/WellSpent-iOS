import GoogleMobileAds
import SwiftUI
import UIKit

/// Wraps `GADBannerView` (a `UIView`, not a view controller — plain
/// `UIViewRepresentable` is the right fit). Confirmed directly against the
/// resolved SPM package's Objective-C headers (no `NS_SWIFT_NAME` renaming
/// or Swift-native overlay exists in this SDK) that the `GAD`-prefixed
/// names are the real, current Swift-facing API — not a newer unprefixed
/// naming scheme some other Google SDKs use.
struct AdBannerView: UIViewRepresentable {
    /// Google's own public test banner ad unit ID — safe to hardcode, not a
    /// secret. Swap for a real ad unit ID once one exists in the AdMob
    /// console (tracked alongside the still-open real-APNs-key situation
    /// from Phase 3C — everything else works regardless).
    static let testAdUnitID = "ca-app-pub-3940256099942544/2934735716"

    var adUnitID: String = AdBannerView.testAdUnitID

    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = adUnitID
        banner.rootViewController = Self.currentRootViewController()
        banner.load(GADRequest())
        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {}

    private static func currentRootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

#Preview {
    AdBannerView()
        .frame(height: 50)
}
