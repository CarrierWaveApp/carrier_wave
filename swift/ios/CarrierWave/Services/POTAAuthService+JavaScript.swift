// POTA Auth JavaScript helpers
//
// Contains JavaScript code strings used for POTA WebView authentication

import CarrierWaveData
import Foundation

// MARK: - POTAAuthJavaScript

/// JavaScript code strings for POTA authentication
enum POTAAuthJavaScript {
    /// JavaScript to extract token from cookies/localStorage
    static let extractToken = """
    (function() {
        // Check cookies first
        const cookies = document.cookie.split(';');
        for (const cookie of cookies) {
            const trimmed = cookie.trim();
            if (trimmed.includes('idToken=')) {
                const eqIdx = trimmed.indexOf('=');
                if (eqIdx > 0) {
                    const val = trimmed.substring(eqIdx + 1);
                    if (val && val.startsWith('eyJ')) {
                        return val;
                    }
                }
            }
        }

        // Try localStorage
        for (let i = 0; i < localStorage.length; i++) {
            const key = localStorage.key(i);
            if (key && key.includes('idToken')) {
                const val = localStorage.getItem(key);
                if (val && val.startsWith('eyJ')) {
                    return val;
                }
            }
        }

        // Check sessionStorage
        for (let i = 0; i < sessionStorage.length; i++) {
            const key = sessionStorage.key(i);
            if (key && key.includes('idToken')) {
                const val = sessionStorage.getItem(key);
                if (val && val.startsWith('eyJ')) {
                    return val;
                }
            }
        }

        // Try Amplify auth data
        for (let i = 0; i < localStorage.length; i++) {
            const key = localStorage.key(i);
            if (key && (key.includes('amplify') || key.includes('Cognito') || key.includes('auth'))) {
                try {
                    const val = localStorage.getItem(key);
                    const parsed = JSON.parse(val);
                    if (parsed && parsed.idToken) {
                        return parsed.idToken;
                    }
                    if (parsed && parsed.signInUserSession && parsed.signInUserSession.idToken) {
                        return parsed.signInUserSession.idToken.jwtToken;
                    }
                } catch (e) {}
            }
        }

        return null;
    })()
    """

    /// JavaScript to wait for the Sign In button to appear
    static let waitForSignInButton = """
    (function() {
        const buttons = document.querySelectorAll('button, a, [role="button"]');
        for (const btn of buttons) {
            const text = btn.textContent.toLowerCase().trim();
            if (text === 'sign in' || text === 'login' || text === 'log in') {
                return true;
            }
        }
        return false;
    })()
    """

    /// JavaScript to click the Sign In button
    static let clickSignInButton = """
    (function() {
        const buttons = document.querySelectorAll('button, a, [role="button"]');
        for (const btn of buttons) {
            const text = btn.textContent.toLowerCase().trim();
            if (text === 'sign in' || text === 'login' || text === 'log in') {
                btn.click();
                return { success: true, text: text };
            }
        }
        return { success: false, error: 'Sign in button not found' };
    })()
    """

    /// JavaScript to check if the Cognito form is ready
    static let checkCognitoForm = """
    (function() {
        const usernameInput = document.querySelector('#signInFormUsername');
        const passwordInput = document.querySelector('#signInFormPassword');
        return usernameInput !== null && passwordInput !== null;
    })()
    """

    /// JavaScript to check for error messages on the login page
    static let checkLoginError = """
    (function() {
        // Look for error message elements
        const errorEl = document.querySelector(
            '.error-message, .errorMessage, #loginErrorMessage, ' +
            '[class*="error"], [id*="error"], .alert-danger'
        );
        if (errorEl && errorEl.textContent.trim()) {
            return { hasError: true, message: errorEl.textContent.trim() };
        }
        return { hasError: false };
    })()
    """

    /// JavaScript helper function to check element visibility (for embedding in other scripts)
    static let visibilityHelperFunction = """
    function isVisible(el) {
        if (!el) return false;
        const style = window.getComputedStyle(el);
        return style.display !== 'none' &&
               style.visibility !== 'hidden' &&
               style.opacity !== '0' &&
               el.offsetParent !== null;
    }
    """

    /// JavaScript to find visible input fields in the Cognito form
    static let findVisibleFormFields = """
    const allUserInputs = document.querySelectorAll('#signInFormUsername');
    let usernameInput = null;
    for (const inp of allUserInputs) {
        if (isVisible(inp)) {
            usernameInput = inp;
            break;
        }
    }

    const allPwdInputs = document.querySelectorAll('#signInFormPassword');
    let passwordInput = null;
    for (const inp of allPwdInputs) {
        if (isVisible(inp)) {
            passwordInput = inp;
            break;
        }
    }
    """

    /// JavaScript to simulate typing into an input field
    static let simulateTypingFunction = """
    function simulateTyping(input, value) {
        input.focus();
        input.value = '';
        for (let i = 0; i < value.length; i++) {
            input.value += value[i];
            input.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true }));
            input.dispatchEvent(new KeyboardEvent('keypress', { bubbles: true }));
            input.dispatchEvent(new Event('input', { bubbles: true }));
            input.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));
        }
        input.dispatchEvent(new Event('change', { bubbles: true }));
    }
    """

    /// JavaScript to submit the Cognito login form
    static let submitForm = """
    (function() {
        \(visibilityHelperFunction)

        \(findVisibleFormFields)

        if (!usernameInput) {
            return { success: false, error: 'Cannot find form' };
        }

        const form = usernameInput.closest('form');
        if (!form) {
            return { success: false, error: 'No form found' };
        }

        const submitBtns = form.querySelectorAll(
            'input[name="signInSubmitButton"], input[type="submit"]'
        );
        for (const btn of submitBtns) {
            if (isVisible(btn)) {
                btn.click();
                return { success: true, method: 'button-click' };
            }
        }

        form.submit();
        return { success: true, method: 'form-submit' };
    })()
    """

    /// Generates JavaScript to fill the Cognito login form
    static func fillCredentialsForm(username: String, password: String) -> String {
        """
        (function() {
            \(visibilityHelperFunction)
            \(simulateTypingFunction)
            \(findVisibleFormFields)

            if (!usernameInput || !passwordInput) {
                return {
                    success: false,
                    error: 'Visible form fields not found',
                    totalUserInputs: allUserInputs.length,
                    totalPwdInputs: allPwdInputs.length
                };
            }

            simulateTyping(usernameInput, '\(username.escapedForJS)');
            simulateTyping(passwordInput, '\(password.escapedForJS)');

            return { success: true };
        })()
        """
    }
}
