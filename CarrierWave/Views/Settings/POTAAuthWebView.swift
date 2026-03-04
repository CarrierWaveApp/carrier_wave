// POTA authentication WebView UI components
//
// SwiftUI wrapper for WKWebView used in POTA Cognito login flow.

import CarrierWaveData
import SwiftUI
import WebKit

// MARK: - POTAAuthWebView

struct POTAAuthWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No updates needed
    }
}

// MARK: - POTALoginSheet

struct POTALoginSheet: View {
    // MARK: Internal

    @ObservedObject var authService: POTAAuthService

    var body: some View {
        NavigationStack {
            Group {
                if let webView = authService.webView {
                    POTAAuthWebView(webView: webView)
                } else {
                    ProgressView("Loading...")
                }
            }
            .navigationTitle("POTA Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        authService.cancelAuthentication()
                        dismiss()
                    }
                }
            }
        }
        .task {
            do {
                _ = try await authService.authenticate()
                // Authentication succeeded, dismiss the sheet
                dismiss()
            } catch POTAAuthError.authenticationCancelled {
                // User cancelled, already handled by cancel button
            } catch {
                // Other errors - the webView may still be showing error state
                // User can cancel manually
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}
