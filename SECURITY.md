# Security policy

Version 0.9.3 is a pre-release tested on a single Apple Silicon Mac, not an independently audited or Apple-notarized product. No stable security-support window is promised yet. Please use the latest published pre-release.

Do not post vulnerabilities containing secrets, clipboard contents, private commands or access tokens in public issues. Use GitHub's private vulnerability reporting if the repository exposes that option; otherwise request a private contact method without disclosing exploit details or user data.

MacPanel intentionally reads the system pasteboard. It must not be assumed to exclude all passwords. User-authored commands run under the current user's account without sandbox isolation. The distributed build uses ad-hoc signing, without Developer ID or notarization. Never commit signing certificates, private keys, personal configuration or clipboard history.
