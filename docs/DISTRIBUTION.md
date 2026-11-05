# Distributing Glimpse

Use **Developer ID signing and Apple notarization** for direct downloads. A ZIP containing the stapled app is sufficient: people unzip it and drag Glimpse into Applications. A DMG is optional presentation, not a requirement for trust. No installer package is needed.

## One-time Apple setup

1. Join the [Apple Developer Program](https://developer.apple.com/programs/) (currently US$99/year; regional prices vary). A free development account cannot supply Developer ID distribution signing/notarization. Some qualifying organizations have [fee waivers](https://developer.apple.com/help/account/membership/fee-waivers/).
2. In Xcode → Settings → Accounts, select your paid team and Manage Certificates. Create a **Developer ID Application** certificate, or follow Apple's [certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates). The certificate **and its private key** must be in your keychain. An Apple Development certificate is insufficient. Developer ID Installer is unnecessary for our ZIP.
3. Configure a notarization keychain profile locally. For an Apple Account with an app-specific password, use `xcrun notarytool store-credentials "Glimpse-notary"` and answer its prompts. Apple also supports App Store Connect API credentials. Follow [Apple's custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow). Do not commit or paste passwords, private keys, or API keys into chat/configuration files.
4. Confirm the identity with `security find-identity -v -p codesigning`. Use its full **Developer ID Application: … (TEAMID)** name below. Keep a secure private backup of the certificate/private key.

On the reviewed Mac, only an **Apple Development** identity was available. No Developer ID release has been signed or notarized yet.

## Release workflow

Start from a clean checkout of the intended commit, with no untracked files. Run:

```bash
bash scripts/check.sh
bash scripts/check_secrets.sh
GLIMPSE_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
GLIMPSE_NOTARY_PROFILE='Glimpse-notary' \
GLIMPSE_VERSION='1.0.0' \
bash scripts/package_release.sh --public
```

Choose the intended version; the example does not reserve or publish 1.0.0. The build number defaults to the commit count; set `GLIMPSE_BUILD_NUMBER` to a monotonically increasing number for your release process. `GLIMPSE_RELEASE_DIR` changes the output root (default `build/releases`). The script creates a fresh directory each run and never overwrites a prior release.

The script builds **arm64 + x86_64**, verifies both architectures, signs with hardened runtime and a secure timestamp, uploads to Apple, requires an Accepted result, saves the notary log, staples/validates the app's ticket, checks its signature and Gatekeeper assessment, and makes the final ZIP and SHA-256 checksum. It includes LICENSE and a matching committed source archive. Check notarization-log.json for warnings even after acceptance. If embedded executable dependencies are added later, the script stops until their signing order is implemented.

It uploads only to Apple's notary service; it does **not** publish anything to GitHub or a website. Publish the final ZIP and checksum with release notes after testing. Preserve logs and the source commit. Keep the GPL license and corresponding source available with the binary.

Test the actual browser-downloaded ZIP on a clean Mac or VM, ideally on Apple silicon and Intel. Leave quarantine intact. Test first launch, offline launch (stapled ticket), image associations, navigation, metadata and actions. `spctl` on the build machine is useful but does not replace this distribution test.

## Local testing

```bash
bash scripts/package_release.sh --local
```

This exercises the universal build and archive format with an **ad-hoc signature**. Its filename and contents explicitly identify it as a local test. It skips notarization and does not pass public Gatekeeper trust checks. When the working tree has changes, its included source archive reflects HEAD, so use it only for local testing. It needs no paid Apple account.

## What users will see

A valid Developer ID signature and notarization ticket avoid the unidentified/unverified-developer block under normal Gatekeeper settings. macOS can still show a normal first-open internet-download confirmation, privacy prompts, or later security alerts if a signature/certificate is revoked or malware is detected. No packaging workflow can promise absolutely zero dialogs. Do not remove quarantine, disable Gatekeeper, or tell users to bypass security as an installation step.

Direct distribution fits the current app: folder navigation and explicitly configured commands run outside App Sandbox, with hardened runtime enabled. A Mac App Store release would need a separate sandbox/security-scoped-access design and App Review. Notarization is Apple's automated security check, not an architecture review or a guarantee that the app has no bugs. See [Apple's notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
