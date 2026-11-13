// Keyboard Accessory Builder — Prefix Row
//
// The callsign prefix hot-key row (CAR-290), split out to keep the main
// builder under SwiftLint type-length limits.

import UIKit

extension KeyboardAccessoryBuilder {
    static func createPrefixRow(
        prefixes: [String],
        action: Selector,
        target: AnyObject
    ) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        for prefix in prefixes {
            let button = createPrefixButton(title: prefix, action: action, target: target)
            stack.addArrangedSubview(button)
        }

        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 8
            ),
            stack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -8
            ),
            stack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 6
            ),
            stack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -6
            ),
            scrollView.frameLayoutGuide.heightAnchor.constraint(equalToConstant: 48),
        ])

        return scrollView
    }

    static func createPrefixButton(
        title: String,
        action: Selector,
        target: AnyObject
    ) -> UIButton {
        let button = UIButton(type: .system)

        var config = UIButton.Configuration.plain()
        config.title = title
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var modified = attrs
            let base = UIFont.monospacedSystemFont(ofSize: 16, weight: .medium)
            modified.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
            modified.foregroundColor = UIColor.label
            return modified
        }
        button.configuration = config

        button.backgroundColor = .tertiarySystemBackground
        button.layer.cornerRadius = 6
        button.accessibilityLabel = "Prefix \(title)"
        button.accessibilityIdentifier = title
        button.addTarget(target, action: action, for: .touchUpInside)
        return button
    }
}
