# KJM GitHub Secure Menu Tool (Miko's GitHub Security Toolkit)

A modular PowerShell toolkit to securely manage repositories, enforce branch protections, and migrate protection rule configurations.

## Features
- **Interactive Console Menu:** Unified control hub via `menu.ps1`.
- **Repository Provisioning:** Quick creation of private/public repos with auto-init.
- **Security Hardening:** Automatic branch protection enforcement (Code owner reviews, linear history, enforce admins, block deletions/force-pushes).
- **Configuration Portability:** Export and import repository protection settings via JSON snapshots.
- **Flexible Auth:** Supports GitHub CLI web OAuth, ephemeral token input, or `$env:GITHUB_TOKEN`.

## Generated Files
- `auth.ps1`: Handles GitHub token and header management.
- `create-repo.ps1`: Creates public or private repositories via REST API.
- `apply-rules.ps1`: Applies branch rules, exports/imports rule snapshots, and configures CODEOWNERS.
- `menu.ps1`: Main interactive terminal interface.
- `README.md`: Project documentation.

## Getting Started
1. Run `.\install-github-secure-tools.ps1` to generate all files.
2. Launch `.\menu.ps1`.
