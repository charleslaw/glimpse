# Contributing to Glimpse

Thank you for taking the time to contribute! This document will help you get started.

## Table of contents

- [Code of conduct](#code-of-conduct)
- [Reporting bugs](#reporting-bugs)
- [Suggesting features](#suggesting-features)
- [Development setup](#development-setup)
- [Submitting a pull request](#submitting-a-pull-request)
- [Code style](#code-style)
- [Commit messages](#commit-messages)

---

## Code of conduct

Be kind and respectful. We follow the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).

## Reporting bugs

1. Search [existing issues](https://github.com/glimpse-app/glimpse/issues) first — your bug may already be tracked.
2. If not, open a new issue using the **Bug report** template and fill in all fields.
3. Attach a sample image if the bug is format-specific (anonymised if necessary).

## Suggesting features

Open an issue using the **Feature request** template. Include:

- The problem you're trying to solve
- Your proposed solution
- Any alternatives you considered

Features that stay true to the project's goal — a fast, minimal viewer — are most likely to be accepted.

## Development setup

**Prerequisites**

- macOS 12.0+
- Xcode 15.0+

**Fork and clone**

```bash
git clone https://github.com/<your-username>/glimpse.git
cd glimpse
```

**Optional: local build settings**

```bash
cp LocalDev.xcconfig.template LocalDev.xcconfig
# Edit LocalDev.xcconfig to set your DEVELOPMENT_TEAM etc.
```

**Open in Xcode**

```bash
open Glimpse.xcodeproj
```

Press `⌘R` to build and run.

## Submitting a pull request

1. Fork the repo and create a branch from `main`:
   ```bash
   git checkout -b feat/my-improvement
   ```
2. Make your changes. Keep each commit focused on a single logical change.
3. Verify the project still builds cleanly (`⌘B` in Xcode, or `xcodebuild build …`).
4. Push your branch and open a pull request against `main`.
5. Fill in the PR description explaining *what* changed and *why*.

PRs that touch the `project.pbxproj` file should include a note explaining why the project file was modified.

## Code style

- **Swift 5.9+** idiomatic code; prefer value types and `guard` over nested `if`s.
- Access control: use the most restrictive level that makes sense (`private` > `fileprivate` > `internal`).
- No force-unwrapping (`!`) in production paths; use `guard let` or `if let`.
- Mark leaf classes/structs as `final` when subclassing is not intended.
- Keep files focused: one primary type per file.
- Comments only where the intent is not obvious from the code itself.

There is no auto-formatter requirement, but please follow the existing indentation (tabs, as Xcode defaults).

## Commit messages

Use the conventional format:

```
<type>: <short summary>

<optional body>
```

Types: `feat`, `fix`, `refactor`, `perf`, `docs`, `chore`, `test`.

Examples:

```
feat: wrap-around navigation at folder boundaries
fix: window not resizing when image dimensions are zero
perf: cache sibling URL list instead of re-reading on every keystroke
docs: add HEIF to supported formats table in README
```
