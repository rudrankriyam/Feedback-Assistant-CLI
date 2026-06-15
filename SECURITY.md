# Security Policy

xcfb handles local Feedback Assistant metadata, may pass local attachment paths to the native Feedback Assistant app, and can store an experimental Feedback Assistant web session in an owner-only local file or macOS Keychain.

Do not report security issues publicly if they expose:

- private Apple account information
- unpublished feedback contents
- local file paths that reveal confidential projects
- logs or attachments containing credentials
- Feedback Assistant web cookies, CSRF values, or Apple Account session material

Open a private security advisory on GitHub when possible.

## Project Boundary

xcfb does not accept contributions that bypass Apple entitlements, disable platform security, forge Apple credentials, inject into Apple-signed processes, or submit feedback without explicit confirmation.

The stable native workflow uses the signed-in Feedback Assistant app, its local draft store, and explicit native Submit action. The isolated `xcfb web` experiment may use Apple's password-based SRP authentication and undocumented Appleseed endpoints for inspection and confirmed draft mutations. Passwords and verification codes must remain transient and must never be stored or logged. Web cookies and the one-way account identifier hash may be stored in the owner-only file cache or macOS Keychain, and cookie values must never be logged. Submission must require `--confirm`, pass schema-driven validation, and verify Apple's returned feedback identifier through a server read.
