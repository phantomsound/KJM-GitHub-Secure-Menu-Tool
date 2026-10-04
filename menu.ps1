function Show-HelpGuide {
  Clear-Host
  Write-Host "==========================================================" -ForegroundColor Cyan
  Write-Host "        KJM GitHub Secure Menu Tool - Help & Guide        " -ForegroundColor Cyan
  Write-Host "==========================================================" -ForegroundColor Cyan
  Write-Host "OVERVIEW:" -ForegroundColor Yellow
  Write-Host "  This tool manages GitHub repositories via the GitHub REST API and GitHub CLI."
  Write-Host "  It hardens branch rules, copies policies between repos, and controls repo access.`n"

  Write-Host "FEATURE GUIDE:" -ForegroundColor Yellow
  Write-Host "  1) Create Repo"
  Write-Host "     Provisions a new remote repo (Private by default) and pushes auto-init.`n"

  Write-Host "  2) Manage Repo Visibility"
  Write-Host "     Toggles any existing repository between Public and Private with zero data loss.`n"

  Write-Host "  3) Apply Protection Rules (Presets)"
  Write-Host "     - Strict: PR review required, Code Owner required, Admins enforced, Linear history."
  Write-Host "     - Standard: PR review required (1 approval), team flexible, force pushes blocked."
  Write-Host "     - Locked / Read-Only: 2 required reviews, admin restrictions, locked against force writes.`n"

  Write-Host "  4) Copy Protection Rules"
  Write-Host "     Pick an existing hardened repo as a template and copy its exact protection rules"
  Write-Host "     to any other repo(s) instantly.`n"

  Write-Host "  5) Export / Import Rules"
  Write-Host "     Backs up protection configurations to JSON or imports them to new repositories.`n"

  Write-Host "  6) Auth Setup"
  Write-Host "     Logs in via GitHub CLI (browser OAuth) or sets an in-memory Personal Access Token.`n"

  Read-Host "Press Enter to return to main menu"
}

while ($true) {
  Clear-Host
  Write-Host "==========================================================" -ForegroundColor Cyan
  Write-Host "               KJM GitHub Secure Menu Tool                " -ForegroundColor Cyan
  Write-Host "==========================================================" -ForegroundColor Cyan
  Write-Host "1) Create repository"
  Write-Host "2) Change repository visibility (Public / Private)"
  Write-Host "3) Apply protection rules (Strict / Standard / Locked)"
  Write-Host "4) Copy protection rules from another repository"
  Write-Host "5) Export rules to JSON"
  Write-Host "6) Import rules from JSON"
  Write-Host "7) Dry-run protection rules"
  Write-Host "8) Authentication setup"
  Write-Host "9) Help & security guide"
  Write-Host "0) Exit"
  $choice = Read-Host "`nChoose an option"

  switch ($choice) {
    "1" {
      .\create-repo.ps1
      Read-Host "`nPress Enter to continue"
    }
    "2" {
      .\apply-rules.ps1 -Apply -ToggleVisibilityOnly
      Read-Host "`nPress Enter to continue"
    }
    "3" {
      Write-Host "`nSelect Security Preset:" -ForegroundColor Cyan
      Write-Host "1) Strict (Admin Enforced, Codeowners, Linear History, 1 Review)"
      Write-Host "2) Standard (1 Review required, force pushes blocked, flexible)"
      Write-Host "3) Locked / Read-Only (High security archive: 2 Reviews, strict lock)"
      $pChoice = Read-Host "Select preset (1-3)"
      $preset = switch ($pChoice) {
        "2" { "Standard" }
        "3" { "LockedReadOnly" }
        default { "Strict" }
      }
      .\apply-rules.ps1 -Apply -SecurityPreset $preset
      Read-Host "`nPress Enter to continue"
    }
    "4" {
      .\apply-rules.ps1 -Apply -CopyRulesInteractive
      Read-Host "`nPress Enter to continue"
    }
    "5" {
      .\apply-rules.ps1 -ExportRules
      Read-Host "`nPress Enter to continue"
    }
    "6" {
      .\apply-rules.ps1 -ImportRules -Apply
      Read-Host "`nPress Enter to continue"
    }
    "7" {
      .\apply-rules.ps1 -SecurityPreset "Strict"
      Read-Host "`nPress Enter to continue"
    }
    "8" {
      . .\auth.ps1
      Initialize-GitHubAuth | Out-Null
      Read-Host "`nAuth ready. Press Enter to continue"
    }
    "9" {
      Show-HelpGuide
    }
    "0" {
      break
    }
    default {
      Write-Host "Invalid choice"
      Read-Host "Press Enter to continue"
    }
  }
}
