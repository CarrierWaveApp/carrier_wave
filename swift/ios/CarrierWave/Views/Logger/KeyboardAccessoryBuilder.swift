// Keyboard Accessory Builder
//
// Builds the UIKit input accessory view for the callsign text field.
// Extracted to keep CallsignTextField under SwiftLint line limits.

import CarrierWaveData
import SwiftUI
import UIKit

// MARK: - KeyboardAccessoryActions

/// The tap targets for the accessory rows, bundled to keep
/// `createAccessoryView` under SwiftLint's parameter limit.
struct KeyboardAccessoryActions {
    let numberButton: Selector
    let prefixButton: Selector
    let commandButton: Selector
    let dismiss: Selector
    let submit: Selector
    let target: AnyObject
}

// MARK: - KeyboardAccessoryBuilder

/// Builds the keyboard accessory view with number row and optional command row
enum KeyboardAccessoryBuilder {
    // MARK: Internal

    /// Default symbols for the keyboard row
    static let defaultSymbols = "/"
    /// Default commands for the command row
    static let defaultCommands = "rbn,solar,weather,spot,pota,p2p"

    /// Returns the configured characters for the keyboard row based on user settings
    static func configuredCharacters() -> [String] {
        let rowEnabled =
            UserDefaults.standard.object(forKey: "numberRowEnabled") as? Bool ?? true
        guard rowEnabled else {
            return []
        }
        let showNumbers =
            UserDefaults.standard.object(forKey: "keyboardRowShowNumbers") as? Bool ?? true
        let symbolsString =
            UserDefaults.standard.string(forKey: "keyboardRowSymbols") ?? defaultSymbols

        var characters: [String] = []
        if showNumbers {
            characters += ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        }
        if !symbolsString.isEmpty {
            characters += symbolsString.components(separatedBy: ",")
        }
        return characters
    }

    /// Returns the prefix hot keys for the prefix row (CAR-290): the user's
    /// custom list, or the cached position-local suggestions from Rust.
    @MainActor
    static func configuredPrefixes() -> [String] {
        let enabled =
            UserDefaults.standard.object(forKey: "prefixRowEnabled") as? Bool ?? true
        guard enabled else {
            return []
        }
        let mode = UserDefaults.standard.string(forKey: "prefixRowMode") ?? "suggested"
        if mode == "custom" {
            let custom = UserDefaults.standard.string(forKey: "prefixRowCustom") ?? ""
            return custom.components(separatedBy: ",").filter { !$0.isEmpty }
        }
        return PrefixRowService.shared.suggested
    }

    /// The user-configured row stacking order (top to bottom above the keyboard).
    static func configuredRowOrder() -> [KeyboardRowKind] {
        let raw = UserDefaults.standard.string(forKey: "keyboardRowOrder")
            ?? KeyboardRowKind.defaultOrderRaw
        return KeyboardRowKind.order(from: raw)
    }

    /// Returns the configured commands for the command row based on user settings.
    /// On iPad, always returns commands even if the command row is disabled in
    /// settings — the persistent strip hides when the keyboard is up, so the
    /// accessory is the only command source while typing.
    ///
    /// `allowed` narrows the row to the commands the hosting screen can
    /// actually run (the Hunter Log has no session, so SPOT/P2P/S2S/HUNT are
    /// dropped there); `nil` keeps every configured command.
    static func configuredCommands(allowed: Set<CommandRowItem>? = nil) -> [CommandRowItem] {
        let commandRowEnabled =
            UserDefaults.standard.object(forKey: "commandRowEnabled") as? Bool ?? false
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        if !commandRowEnabled, !isIPad {
            return []
        }

        let commandsString =
            UserDefaults.standard.string(forKey: "commandRowCommands") ?? defaultCommands
        let configured = commandsString.components(separatedBy: ",").compactMap {
            CommandRowItem(rawValue: $0)
        }
        let items = configured.isEmpty && isIPad ? CommandRowItem.allCases : configured
        guard let allowed else {
            return items
        }
        return items.filter { allowed.contains($0) }
    }

    /// Creates the input accessory view with the configured rows (numbers,
    /// prefixes, CW keyer, commands) stacked in the user-configured order.
    static func createAccessoryView(
        actions: KeyboardAccessoryActions,
        includeCommands: Bool = true,
        allowedCommands: Set<CommandRowItem>? = nil,
        callsignProvider: (() -> String)? = nil
    ) -> UIView {
        let accessoryView = UIView()
        accessoryView.backgroundColor = .secondarySystemBackground
        accessoryView.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = UIStackView()
        mainStack.axis = .vertical
        mainStack.spacing = 0
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let characters = configuredCharacters()
        let prefixes = configuredPrefixes()
        let commands = includeCommands ? configuredCommands(allowed: allowedCommands) : []

        let rows = buildRows(
            characters: characters,
            prefixes: prefixes,
            commands: commands,
            actions: actions,
            callsignProvider: callsignProvider ?? { "" }
        )
        for row in rows {
            if !mainStack.arrangedSubviews.isEmpty {
                mainStack.addArrangedSubview(createSeparator())
            }
            mainStack.addArrangedSubview(row)
        }

        accessoryView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: accessoryView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: accessoryView.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: accessoryView.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: accessoryView.bottomAnchor),
        ])

        // Use a large width - the system will constrain it to the keyboard width
        accessoryView.frame = CGRect(
            x: 0,
            y: 0,
            width: 10_000,
            height: calculateHeight(characters: characters, prefixes: prefixes, commands: commands)
        )

        return accessoryView
    }

    static func showKeyerRow() -> Bool {
        let service = RadioService.shared
        let hasCWKeyer = service.bridgeHasCWKeyer
        let usbConnected = service.bridgeUSBConnected
        let isCW = service.radioMode == "CW" || service.radioMode == "CW-R"
        let hasSlots = !service.cwKeyer.programmedSlots.isEmpty
        return hasCWKeyer && usbConnected && isCW && hasSlots
    }

    // MARK: Private

    // MARK: - Private Helpers

    private static func buildRows(
        characters: [String],
        prefixes: [String],
        commands: [CommandRowItem],
        actions: KeyboardAccessoryActions,
        callsignProvider: @escaping () -> String
    ) -> [UIView] {
        configuredRowOrder().compactMap { kind in
            switch kind {
            case .numbers:
                characters.isEmpty ? nil : createNumberRow(
                    characters: characters,
                    numberAction: actions.numberButton,
                    dismissAction: actions.dismiss,
                    submitAction: actions.submit,
                    target: actions.target
                )
            case .prefixes:
                prefixes.isEmpty ? nil : createPrefixRow(
                    prefixes: prefixes,
                    action: actions.prefixButton,
                    target: actions.target
                )
            case .keyer:
                showKeyerRow()
                    ? createKeyerHostView(callsignProvider: callsignProvider)
                    : nil
            case .commands:
                commands.isEmpty ? nil : createCommandRow(
                    commands: commands,
                    action: actions.commandButton,
                    target: actions.target
                )
            }
        }
    }

    private static func calculateHeight(
        characters: [String],
        prefixes: [String],
        commands: [CommandRowItem]
    ) -> CGFloat {
        var rowHeights: [CGFloat] = []
        if showKeyerRow() {
            rowHeights.append(70) // status line + buttons
        }
        if !characters.isEmpty {
            rowHeights.append(56)
        }
        if !prefixes.isEmpty {
            rowHeights.append(48)
        }
        if !commands.isEmpty {
            rowHeights.append(40)
        }
        let scale = UITraitCollection.current.displayScale
        let separatorH = 1.0 / (scale > 0 ? scale : 3.0)
        let total = rowHeights.reduce(0, +)
            + CGFloat(max(0, rowHeights.count - 1)) * separatorH
        return max(total, 56)
    }

    private static func createSeparator() -> UIView {
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        // Use trait collection scale, fallback to 3.0 (common retina scale)
        let scale = UITraitCollection.current.displayScale
        separator.heightAnchor.constraint(equalToConstant: 1.0 / (scale > 0 ? scale : 3.0))
            .isActive = true
        return separator
    }

    private static func createCommandRow(
        commands: [CommandRowItem],
        action: Selector,
        target: AnyObject
    ) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        for item in commands {
            let button = createCommandButton(item: item, action: action, target: target)
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
            scrollView.frameLayoutGuide.heightAnchor.constraint(equalToConstant: 40),
        ])

        return scrollView
    }

    private static func createNumberRow(
        characters: [String],
        numberAction: Selector,
        dismissAction: Selector,
        submitAction: Selector,
        target: AnyObject
    ) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        for char in characters {
            let button = createNumberButton(title: char, action: numberAction, target: target)
            stack.addArrangedSubview(button)
        }

        stack.addArrangedSubview(createDismissButton(action: dismissAction, target: target))

        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            stack.heightAnchor.constraint(equalToConstant: 40),
        ])

        return container
    }

    private static func createNumberButton(
        title: String,
        action: Selector,
        target: AnyObject
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        let baseFont = UIFont.monospacedSystemFont(ofSize: 18, weight: .medium)
        button.titleLabel?.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.setTitleColor(.label, for: .normal)
        button.backgroundColor = .tertiarySystemBackground
        button.layer.cornerRadius = 6
        button.addTarget(target, action: action, for: .touchUpInside)
        return button
    }

    private static func createCommandButton(
        item: CommandRowItem,
        action: Selector,
        target: AnyObject
    ) -> UIButton {
        let button = UIButton(type: .system)

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: item.icon)?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        )
        config.title = item.label
        config.imagePadding = 4
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var modified = attrs
            let base = UIFont.systemFont(ofSize: 12, weight: .medium)
            modified.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: base)
            return modified
        }
        button.configuration = config

        button.tintColor = .systemPurple
        button.backgroundColor = UIColor.systemPurple.withAlphaComponent(0.15)
        button.layer.cornerRadius = 14

        button.accessibilityIdentifier = item.rawValue
        button.addTarget(target, action: action, for: .touchUpInside)

        return button
    }

    private static func createDismissButton(action: Selector, target: AnyObject) -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        button.setImage(
            UIImage(systemName: "keyboard.chevron.compact.down", withConfiguration: config),
            for: .normal
        )
        button.tintColor = .secondaryLabel
        button.backgroundColor = .tertiarySystemBackground
        button.layer.cornerRadius = 6
        button.addTarget(target, action: action, for: .touchUpInside)
        return button
    }
}
