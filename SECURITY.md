# Security

Glimpse views local files using Apple's ImageIO/AppKit. It has no third-party runtime dependencies and performs no automatic network requests. Selected custom actions can launch trusted programs or HTTPS URLs and therefore can access the network. Do not put secrets in actions files.

The app uses hardened runtime, but **App Sandbox is not enabled**. Navigation reads image siblings in the selected directory; configured commands run with the user's privileges after confirmation. A future sandboxed edition would need security-scoped folder access and a different command design. Image byte/pixel/frame limits and metadata budgets reduce resource abuse, but do not isolate native decoder vulnerabilities or impose a process-wide memory ceiling. Keep macOS updated.

## Development checks

- `bash scripts/check.sh`: core unit tests plus Debug and Release builds, strict Swift concurrency and compiler warnings as errors.
- `GLIMPSE_TEST_SANITIZER=address bash scripts/check.sh`: unit tests with AddressSanitizer, then ordinary app builds.
- `bash scripts/check_secrets.sh`: full Git history/all refs, redacted findings. Gitleaks version/checksums are pinned in `tools/security-tools.json`; downloads are verified before execution and remain in the ignored build directory. The history scan includes only committed content; scan the working tree separately before committing unfamiliar changes.
- `.github/workflows/codeql.yml`: Swift and Actions security analysis on GitHub. Public repositories can use CodeQL; for private repositories confirm eligibility before setting repository variable `ENABLE_CODEQL=true`. Adding the workflow does not mean an analysis has already run.

No Snyk subscription is required for these checks. Review any new runtime package before adding it, and add dependency scanning if dependencies are introduced. Keep development-tool versions/pins current through reviewed changes. Automated scanners complement code review; a clean scan does not certify absence of vulnerabilities.

For a suspected vulnerability, contact the repository maintainer privately (or use GitHub private vulnerability reporting if enabled). Avoid putting exploits against real users, sensitive image metadata, credentials or secrets in public issues. No specific private reporting channel or response SLA has been configured yet.

See [Architecture and audit](docs/ARCHITECTURE-AUDIT.md) and [Distribution](docs/DISTRIBUTION.md).
