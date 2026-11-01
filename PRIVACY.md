# Privacy and Data Handling

MacPanel currently has **no built-in analytics, tracking, or clipboard upload service**. It is developed as an offline-first utility, and the source code may be reviewed. This document describes pre-release 0.9.3, tested on one Mac but not independently audited.

## Clipboard storage

- The app samples the macOS general pasteboard while running and stores up to **15 copy operations** on disk (text, supported images, optional rich text and file references).
- Full-size copied images may consume storage. Thumbnails and an index are saved in `~/Library/Application Support/MacPanel/Clipboard/`.
- Copying a file stores a reference, not the contents of the file.
- Old entries are deleted when the cap is exceeded. Clipboard history can be paused or cleared in Settings.
- Items marked concealed/transient by their origin may be skipped, **but this does not reliably prevent passwords or private information from entering history**. Be cautious with credentials and disable tracking when handling secrets.
- Disk persistence does not mean disk encryption by this app. Protection relies on macOS account permissions and storage protection such as FileVault if enabled.

## Permissions and risks

- Keep Awake uses local IOKit power assertions. It does not change global power settings or require an administrator password; MacBook lid closure is not reliably overridden.
- User-defined shell commands open in Apple's Terminal on the user's Mac. They may access the network or local files according to their content; only run commands you trust. A temporary executable command file is created with user-only permissions; forced exits may leave it behind.
- Sensor helpers read available local system APIs and do not change fan control.

## Donations

The optional donation button opens a configured HTTPS page in the default browser. Any payment processing is done by the third-party provider and governed by its terms. MacPanel does not collect payment details.

## Data removal

Delete clipboard history using the app's Settings. For complete removal after quitting the app, inspect `~/Library/Application Support/MacPanel/` for clipboard history and saved application/command configuration. Removing the application bundle alone does not necessarily remove that directory.

User commands, launched apps and an optional donation website have their own data handling. MacPanel does not encrypt its local clipboard store or guarantee the exclusion of secrets.
