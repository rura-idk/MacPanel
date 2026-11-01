import Foundation

/// Public links distributed with the app. No placeholder/dummy payment URL is shipped.
enum ProjectLinks {
    static let donationURL: URL? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MacPanelDonationURL") as? String,
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host != nil else { return nil }
        return url
    }()
}
