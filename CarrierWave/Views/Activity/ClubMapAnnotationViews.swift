import CarrierWaveData
@preconcurrency import MapKit
import UIKit

// MARK: - MemberAnnotation

final class MemberAnnotation: NSObject, MKAnnotation {
    // MARK: Lifecycle

    nonisolated init(location: MemberLocation) {
        callsign = location.callsign
        status = location.status
        coordinate = location.coordinate
        title = location.callsign
        super.init()
    }

    // MARK: Internal

    let callsign: String
    let status: MemberOnlineStatus?
    @objc nonisolated(unsafe) var coordinate: CLLocationCoordinate2D
    @objc nonisolated(unsafe) var title: String?
}

// MARK: - MemberAnnotationView

final class MemberAnnotationView: MKAnnotationView {
    // MARK: Lifecycle

    override init(
        annotation: MKAnnotation?,
        reuseIdentifier: String?
    ) {
        super.init(
            annotation: annotation,
            reuseIdentifier: reuseIdentifier
        )
        clusteringIdentifier = "clubMember"
        collisionMode = .circle
        configure()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: Internal

    override func prepareForReuse() {
        super.prepareForReuse()
        configure()
    }

    // MARK: Private

    private static func renderPinImage(
        size: CGFloat,
        color: UIColor
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: size, height: size)
        )
        return renderer.image { ctx in
            color.setFill()
            ctx.cgContext.fillEllipse(
                in: CGRect(
                    x: 0, y: 0, width: size, height: size
                )
            )
            let icon = UIImage(
                systemName: "person.fill",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 14,
                    weight: .medium
                )
            )?.withTintColor(.white, renderingMode: .alwaysOriginal)
            let iconSize = icon?.size ?? .zero
            icon?.draw(
                at: CGPoint(
                    x: (size - iconSize.width) / 2,
                    y: (size - iconSize.height) / 2
                )
            )
        }
    }

    private func configure() {
        guard let member = annotation as? MemberAnnotation
        else {
            return
        }

        let color: UIColor = switch member.status {
        case .onAir: .systemGreen
        case .recentlyActive: .systemYellow
        case .inactive,
             .none: .systemBlue
        }

        let size: CGFloat = 32
        image = Self.renderPinImage(size: size, color: color)

        let label = UILabel()
        label.text = member.callsign
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.sizeToFit()
        label.frame.origin = CGPoint(
            x: (size - label.frame.width) / 2,
            y: size + 2
        )
        subviews.forEach { $0.removeFromSuperview() }
        addSubview(label)

        frame.size = CGSize(
            width: max(size, label.frame.width),
            height: size + label.frame.height + 2
        )
        centerOffset = CGPoint(x: 0, y: -size / 2)
    }
}

// MARK: - ClusterAnnotationView

final class ClusterAnnotationView: MKAnnotationView {
    // MARK: Lifecycle

    override init(
        annotation: MKAnnotation?,
        reuseIdentifier: String?
    ) {
        super.init(
            annotation: annotation,
            reuseIdentifier: reuseIdentifier
        )
        collisionMode = .circle
        configure()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: Internal

    override func prepareForReuse() {
        super.prepareForReuse()
        configure()
    }

    // MARK: Private

    private func configure() {
        guard let cluster = annotation as? MKClusterAnnotation
        else {
            return
        }

        let count = cluster.memberAnnotations.count
        let size: CGFloat = count > 9 ? 44 : 36

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: size, height: size)
        )
        image = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.cgContext.fillEllipse(
                in: CGRect(
                    x: 0, y: 0, width: size, height: size
                )
            )
            let text = "\(count)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(
                    ofSize: count > 9 ? 16 : 14,
                    weight: .bold
                ),
                .foregroundColor: UIColor.white,
            ]
            let textSize = text.size(withAttributes: attrs)
            text.draw(
                at: CGPoint(
                    x: (size - textSize.width) / 2,
                    y: (size - textSize.height) / 2
                ),
                withAttributes: attrs
            )
        }
    }
}
