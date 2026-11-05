#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
scanner="$(python3 scripts/install_security_tools.py)"
report="${GLIMPSE_SECRETS_REPORT:-$repo_root/build/security/gitleaks.json}"
mkdir -p "$(dirname "$report")"
"$scanner" git . --log-opts=--all --redact=100 --no-banner --report-format=json --report-path="$report"
