// Callsign Text Field
//
// A UITextField wrapper that properly handles cursor position
// when entering mixed letters and numbers with auto-capitalization.

import SwiftUI
import UIKit

// MARK: - CallsignTextField

/// A text field optimized for callsign entry that maintains cursor position
/// when typing numbers (works around iOS bug with textInputAutocapitalization)
struct CallsignTextField: UIViewRepresentable {
    // MARK: Lifecycle

    init(
        _ placeholder: String,
        text: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        onSubmit: @escaping () -> Void
    ) {
        self.placeholder = placeholder
        _text = text
        self.isFocused = isFocused
        self.onSubmit = onSubmit
    }

    // MARK: Internal

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextFieldDelegate {
        // MARK: Lifecycle

        init(_ parent: CallsignTextField) {
            self.parent = parent
        }

        // MARK: Internal

        var parent: CallsignTextField

        /// Track whether we're currently processing a user edit
        /// to avoid re-entrant updates from SwiftUI
        var isUpdatingFromUIKit = false

        @objc
        func textFieldDidChange(_ textField: UITextField) {
            isUpdatingFromUIKit = true
            parent.text = textField.text ?? ""
            // Delay resetting the flag until after SwiftUI has processed the update
            // This ensures updateUIView sees isUpdatingFromUIKit = true
            DispatchQueue.main.async { [weak self] in
                self?.isUpdatingFromUIKit = false
            }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused.wrappedValue = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused.wrappedValue = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return true
        }

        // MARK: - Number Row Actions

        @objc
        func numberButtonTapped(_ sender: UIButton) {
            guard let char = sender.titleLabel?.text else {
                return
            }
            parent.text.append(char)
        }

        @objc
        func dismissKeyboard(_ sender: UIButton) {
            parent.isFocused.wrappedValue = false
        }
    }

    @Binding var text: String

    let placeholder: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.font = UIFont.monospacedSystemFont(ofSize: 20, weight: .regular)
        textField.autocapitalizationType = .allCharacters
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.returnKeyType = .done
        textField.clearButtonMode = .never
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textFieldDidChange(_:)),
            for: .editingChanged
        )

        // Add input accessory view with number row
        textField.inputAccessoryView = createInputAccessoryView(coordinator: context.coordinator)

        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        // Skip updates that originated from user typing to preserve cursor position
        // Only update for programmatic changes (e.g., clearing field after logging)
        if !context.coordinator.isUpdatingFromUIKit, uiView.text != text {
            // Save cursor position relative to end of text
            let cursorOffsetFromEnd: Int
            if let selectedRange = uiView.selectedTextRange {
                let cursorPosition = uiView.offset(
                    from: uiView.endOfDocument, to: selectedRange.end
                )
                cursorOffsetFromEnd = cursorPosition
            } else {
                cursorOffsetFromEnd = 0
            }

            uiView.text = text

            // Restore cursor position relative to end of text
            // This handles cases where text length changed
            if let newPosition = uiView.position(
                from: uiView.endOfDocument,
                offset: cursorOffsetFromEnd
            ) {
                uiView.selectedTextRange = uiView.textRange(from: newPosition, to: newPosition)
            }
        }

        // Handle focus state changes from SwiftUI
        // Only becomeFirstResponder if SwiftUI wants focus and we don't have it
        // Only resignFirstResponder if SwiftUI doesn't want focus AND we're not actively editing
        // The isEditing check prevents focus loss during typing
        if isFocused.wrappedValue, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused.wrappedValue, uiView.isFirstResponder, !uiView.isEditing {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: Private

    // MARK: - Input Accessory View

    private func createInputAccessoryView(coordinator: Coordinator) -> UIView {
        let accessoryView = UIView()
        accessoryView.backgroundColor = .secondarySystemBackground
        accessoryView.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // Number buttons 1-9, 0, ., and dismiss
        let characters = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "."]
        for char in characters {
            let button = createNumberButton(title: char, coordinator: coordinator)
            stackView.addArrangedSubview(button)
        }

        // Dismiss keyboard button
        let dismissButton = UIButton(type: .system)
        dismissButton.setImage(
            UIImage(systemName: "keyboard.chevron.compact.down"),
            for: .normal
        )
        dismissButton.tintColor = .label
        dismissButton.backgroundColor = .tertiarySystemBackground
        dismissButton.layer.cornerRadius = 6
        dismissButton.addTarget(
            coordinator,
            action: #selector(Coordinator.dismissKeyboard(_:)),
            for: .touchUpInside
        )
        stackView.addArrangedSubview(dismissButton)

        accessoryView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: accessoryView.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(
                equalTo: accessoryView.trailingAnchor, constant: -8
            ),
            stackView.topAnchor.constraint(equalTo: accessoryView.topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: accessoryView.bottomAnchor, constant: -8),
            stackView.heightAnchor.constraint(equalToConstant: 40),
        ])

        // Set the frame for the accessory view
        accessoryView.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 56)

        return accessoryView
    }

    private func createNumberButton(title: String, coordinator: Coordinator) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .monospacedSystemFont(ofSize: 18, weight: .medium)
        button.setTitleColor(.label, for: .normal)
        button.backgroundColor = .tertiarySystemBackground
        button.layer.cornerRadius = 6
        button.addTarget(
            coordinator,
            action: #selector(Coordinator.numberButtonTapped(_:)),
            for: .touchUpInside
        )
        return button
    }
}
