import CarrierWaveCore
import SwiftUI

// MARK: - ClubLogoView

/// Displays a club logo loaded from the server, falling back to initials.
struct ClubLogoView: View {
    // MARK: Internal

    let club: FfiClub
    var size: CGFloat = 40

    var body: some View {
        if club.hasLogo {
            AsyncImage(
                url: logoURL
            ) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
                case .failure:
                    initialsView
                default:
                    ProgressView()
                        .frame(width: size, height: size)
                }
            }
        } else {
            initialsView
        }
    }

    // MARK: Private

    private var logoURL: URL? {
        let base = ActivitiesClient.normalizeBase(ActivitiesClient.resolvedBaseURL)
        return URL(
            string: "\(base)/v1/clubs/\(club.id)/logo"
        )
    }

    private var initials: String {
        let words = club.name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(club.name.prefix(2)).uppercased()
    }

    private var initialsView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(Color(.systemGray5))
            Text(initials)
                .font(.system(size: size * 0.35, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
    }
}
