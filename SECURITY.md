# Security Policy

RelatoKit handles local Feedback Assistant metadata, may pass local attachment paths to the native Feedback Assistant app, and can store an experimental Feedback Assistant web session in macOS Keychain.

Do not report security issues publicly if they expose:

- private Apple account information
- unpublished feedback contents
- local file paths that reveal confidential projects
- logs or attachments containing credentials
- Feedback Assistant web cookies, CSRF values, or Apple Account session material

Open a private security advisory on GitHub when possible.

## Project Boundary

RelatoKit does not accept contributions that bypass Apple entitlements, disable platform security, forge Apple credentials, inject into Apple-signed processes, or silently submit feedback.

The stable native workflow must use the signed-in Feedback Assistant app, its local draft store, and explicit native Submit action. The isolated `relato web` experiment may use Apple's password-based SRP authentication and undocumented Appleseed endpoints for read-only inspection. Passwords and verification codes must remain transient and must never be stored or logged. Web cookies and the one-way account identifier hash must stay in Keychain, cookie values must never be logged, and mutation endpoints require separate design and review before they can be added.
