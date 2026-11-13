// POTA Auth Headless Authentication
//
// Contains headless authentication methods for POTA using stored credentials

import CarrierWaveData
import Foundation
import WebKit

// MARK: - Headless Authentication

extension POTAAuthService {
    /// Performs headless login with provided credentials.
    /// - Parameter persist: when `false`, the resulting token is decoded but not saved to the
    ///   Keychain or set as `currentToken` — used to verify credentials without storing a token.
    func performHeadlessLogin(
        username: String,
        password: String,
        persist: Bool = true
    ) async throws -> POTAToken {
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let headlessWebView = try await createHeadlessWebView()

            // 1. Navigate to the POTA login page. On the rebuilt site this page
            //    starts the Cognito redirect by itself.
            guard let loginURL = URL(string: Self.potaLoginURL) else {
                throw POTAAuthError.tokenExtractionFailed
            }

            headlessWebView.load(URLRequest(url: loginURL))

            // 2. Wait for initial page load
            try await waitForPageLoad(webView: headlessWebView, timeout: 30)

            // 3. If the site did not redirect on its own, click a Sign In button
            try await clickSignInButtonIfNeeded(webView: headlessWebView)

            // 4. Wait for Cognito redirect
            try await waitForCognitoPage(webView: headlessWebView, timeout: 15)

            // 5. Fill Cognito credentials and submit
            try await fillAndSubmitCredentials(
                webView: headlessWebView, username: username, password: password
            )

            // 6. Wait for redirect back to POTA
            try await waitForPOTARedirect(webView: headlessWebView, timeout: 30)

            // 7. Extract token
            let token = try await extractTokenFromWebView(headlessWebView, persist: persist)
            // A successful login confirms the credentials.
            credentialsVerified = true
            return token
        } catch let error as POTAAuthError {
            // Only credential-rejection failures invalidate verification; transient
            // network/timeout errors leave the existing verified state untouched.
            switch error {
            case .credentialsRejected,
                 .loginFailed,
                 .profileIncomplete:
                credentialsVerified = false
            default:
                break
            }
            throw error
        }
    }

    // MARK: - Helper Methods

    func createHeadlessWebView() async throws -> WKWebView {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        // Clear the non-persistent store before use
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dataStore.removeData(ofTypes: dataTypes, modifiedSince: .distantPast) {
                continuation.resume()
            }
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore

        return WKWebView(frame: .zero, configuration: config)
    }

    func waitForPageLoad(webView: WKWebView, timeout: TimeInterval) async throws {
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            let readyState = try? await webView.evaluateJavaScript("document.readyState") as? String
            if readyState == "complete" {
                // Give the SPA more time to initialize (Vue/React apps need this)
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw POTAAuthError.cognitoRedirectTimeout
    }

    /// Fallback for a POTA page that shows a Sign In button instead of redirecting
    /// to Cognito on its own. Returns as soon as the web view is already on Cognito.
    func clickSignInButtonIfNeeded(webView: WKWebView) async throws {
        // Poll for either the Cognito redirect or a button to appear
        let startTime = Date()
        var buttonFound = false
        while Date().timeIntervalSince(startTime) < 10 {
            if isOnCognito(webView) {
                return
            }
            await buttonFound =
                (try? webView.evaluateJavaScript(
                    POTAAuthJavaScript.waitForSignInButton
                ) as? Bool) ?? false
            if buttonFound {
                break
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        guard buttonFound, !isOnCognito(webView) else {
            return
        }

        _ = try await webView.evaluateJavaScript(POTAAuthJavaScript.clickSignInButton)

        // Wait a moment for the redirect to start
        try await Task.sleep(nanoseconds: 2_000_000_000)
    }

    func isOnCognito(_ webView: WKWebView) -> Bool {
        guard let url = webView.url?.absoluteString else {
            return false
        }
        return url.contains("cognito") || url.contains("amazoncognito")
    }

    func waitForCognitoPage(webView: WKWebView, timeout: TimeInterval) async throws {
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            if isOnCognito(webView) {
                // Wait for page to fully load and form to appear
                try await waitForCognitoForm(webView: webView, timeout: 10)
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw POTAAuthError.cognitoRedirectTimeout
    }

    func waitForCognitoForm(webView: WKWebView, timeout: TimeInterval) async throws {
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            let formReady =
                try? await webView.evaluateJavaScript(
                    POTAAuthJavaScript.checkCognitoForm
                ) as? Bool
            if formReady == true {
                // Extra delay to ensure form is fully interactive
                try await Task.sleep(nanoseconds: 500_000_000)
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw POTAAuthError.formFieldsNotFound
    }

    func fillAndSubmitCredentials(
        webView: WKWebView,
        username: String,
        password: String
    ) async throws {
        // Fill the form
        let fillFormJS = POTAAuthJavaScript.fillCredentialsForm(
            username: username, password: password
        )
        let fillResult = try await webView.evaluateJavaScript(fillFormJS)

        // Check if fill succeeded
        if let resultDict = fillResult as? [String: Any],
           let success = resultDict["success"] as? Bool,
           !success
        {
            let error = resultDict["error"] as? String ?? "Unknown error"
            throw POTAAuthError.loginFailed(error)
        }

        // Small delay before submitting
        try await Task.sleep(nanoseconds: 500_000_000)

        // Submit the form
        _ = try await webView.evaluateJavaScript(POTAAuthJavaScript.submitForm)

        // Wait for form submission to process
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Check for error messages on the page
        try await checkForLoginErrors(webView: webView)
    }

    func checkForLoginErrors(webView: WKWebView) async throws {
        let errorResult = try await webView.evaluateJavaScript(POTAAuthJavaScript.checkLoginError)

        if let errorDict = errorResult as? [String: Any],
           let hasError = errorDict["hasError"] as? Bool,
           hasError,
           let message = errorDict["message"] as? String
        {
            let lowerMessage = message.lowercased()
            // Cognito returns generic credential errors for both wrong passwords
            // and accounts that only exist via social login (Google, Apple, etc.)
            if lowerMessage.contains("incorrect username or password")
                || lowerMessage.contains("user does not exist")
            {
                throw POTAAuthError.credentialsRejected
            }
            throw POTAAuthError.loginFailed(message)
        }
    }

    func waitForPOTARedirect(webView: WKWebView, timeout: TimeInterval) async throws {
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            if let url = webView.url?.absoluteString,
               url.contains("pota.app"), !url.contains("cognito"), !url.contains("login")
            {
                // Extra wait for token to be stored in browser
                try await Task.sleep(nanoseconds: 3_000_000_000)
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw POTAAuthError.potaRedirectTimeout
    }

    func extractTokenFromWebView(_ webView: WKWebView, persist: Bool = true) async throws -> POTAToken {
        // Check if we ended up on signup page - this means the account needs profile completion
        if let url = webView.url?.absoluteString, url.contains("signup") {
            throw POTAAuthError.profileIncomplete
        }

        // Try multiple times with delay
        for _ in 0 ..< 5 {
            let result = try await webView.evaluateJavaScript(POTAAuthJavaScript.extractToken)
            if let tokenString = result as? String, !tokenString.isEmpty {
                return persist
                    ? try decodeAndSaveToken(tokenString)
                    : try decodeTokenWithoutSaving(tokenString)
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        throw POTAAuthError.tokenExtractionFailed
    }
}
