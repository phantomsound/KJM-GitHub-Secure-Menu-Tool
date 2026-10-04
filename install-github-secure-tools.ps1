# ==============================================================================
# Project: KJM GitHub Secure Menu Tool (Miko's GitHub Security Toolkit)
# Script : install-github-secure-tools.ps1
# Description: Generates the modular PowerShell suite for secure GitHub repo
#              creation, branch protection, rule import/export, and interactive menu.
# ==============================================================================

$ErrorActionPreference = "Stop"

$targetDir =$PSScriptRoot
if (-not $targetDir) {$targetDir = Get-Location }

Write-Host "Unpacking KJM GitHub Secure Menu Tool into: $targetDir" -ForegroundColor Cyan

$auth = @'
function Initialize-GitHubAuth {
  if ($env:GITHUB_TOKEN) { return "token" }

  if (Get-Command gh -ErrorAction SilentlyContinue) {
    try {
      Write-Host "Logging in with GitHub CLI..."
      gh auth login -p https -w | Out-Null
      $token = gh auth token
      if ($token) {
        $script:SessionGitHubToken =$token
        return "gh"
      }
    } catch {}
  }

  Write-Host "Choose auth method:"
  Write-Host "1) Browser login with GitHub CLI"
  Write-Host "2) Paste token for this session only"
  $choice = Read-Host "Select"

  switch ($choice) {
    "1" {
      if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI not installed."
      }
      gh auth login -p https -w | Out-Null
      $token = gh auth token
      if (-not $token) { throw "No token returned." }
      $script:SessionGitHubToken =$token
      return "gh"
    }
    "2" {
      $token = Read-Host "Paste GitHub token"
      if (-not $token) { throw "No token provided." }
      $script:SessionGitHubToken =$token
      return "manual"
    }
    default { throw "Invalid auth choice." }
  }
}

function Get-GitHubHeaders {
  if ($env:GITHUB_TOKEN) {
    $token =$env:GITHUB_TOKEN
  } elseif ($script:SessionGitHubToken) {
    $token =$script:SessionGitHubToken
  } else {
    Initialize-GitHubAuth | Out-Null
    $token = if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else {$script:SessionGitHubToken }
  }

  @{
    Authorization = "Bearer $token"
    Accept = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
  }
}
'@

$createRepo = @'
param(
  [string]$NewRepoName,
  [string]$Description = "",
  [switch]$Public,
  [switch]$AutoInit =$true
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\auth.ps1"

$headers = Get-GitHubHeaders

if (-not $NewRepoName) {$NewRepoName = Read-Host "New repo name" }
$visibility = if ($Public) { "public" } else { "private" }
Write-Host "Creating repository as $visibility:$NewRepoName"

$body = @{
  name        = $NewRepoName
  description = $Description
  private     = (-not $Public)
  auto_init   = [bool]$AutoInit
}

Write-Host "Ready to create."
$go = Read-Host "Type YES to continue"
if ($go -ne "YES") { Write-Host "Cancelled."; exit }

Invoke-RestMethod -Method Post -Uri "https://api.github.com/user/repos" -Headers $headers -ContentType "application/json" -Body ($body | ConvertTo-Json -Depth 10)
Write-Host "Repository created successfully."
'@

$applyRules = @'
param(
  [switch]$Apply,
  [switch]$AllRepos,
  [string]$Filter,
  [switch]$Public,
  [switch]$Private,

  [switch]$CreateRepo,
  [string]$NewRepoName,
  [string]$NewRepoDescription = "",
  [switch]$NewRepoAutoInit =$true,

  [switch]$CopyRules,
  [string]$CopyFromRepo,

  [switch]$ExportRules,
  [string]$ExportPath = ".\github-rules-backup.json",

  [switch]$ImportRules,
  [string]$ImportPath = ".\github-rules-backup.json",

  [int]$Reviews = 1,
  [switch]$RequireCodeOwnerReviews =$true,
  [switch]$AllowForcePushes =$false,
  [switch]$AllowDeletions =$false,
  [switch]$BlockCreations =$true,
  [switch]$RequiredLinearHistory =$true,
  [switch]$EnforceAdmins =$true,

  [switch]$AddCodeowners =$true,
  [string]$CodeownersPath = ".github/CODEOWNERS",
  [string]$CodeownersContent = "* @YOUR_GITHUB_USERNAME"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\auth.ps1"

$headers = Get-GitHubHeaders

function Invoke-GHGet($url) { Invoke-RestMethod -Method Get -Uri $url -Headers$headers }
function Invoke-GHPost($url,$obj) {
  $json =$obj | ConvertTo-Json -Depth 30
  if ($Apply) { Invoke-RestMethod -Method Post -Uri$url -Headers $headers -ContentType "application/json" -Body $json }
  else { Write-Host "[DRY RUN] POST $url"; Write-Host $json }
}
function Invoke-GHPatch($url,$obj) {
  $json =$obj | ConvertTo-Json -Depth 30
  if ($Apply) { Invoke-RestMethod -Method Patch -Uri$url -Headers $headers -ContentType "application/json" -Body $json }
  else { Write-Host "[DRY RUN] PATCH $url"; Write-Host $json }
}
function Invoke-GHPut($url,$obj) {
  $json =$obj | ConvertTo-Json -Depth 30
  if ($Apply) { Invoke-RestMethod -Method Put -Uri$url -Headers $headers -ContentType "application/json" -Body $json }
  else { Write-Host "[DRY RUN] PUT $url"; Write-Host $json }
}

function Select-Repos {
  $repos = Invoke-GHGet "https://api.github.com/user/repos?per_page=100&affiliation=owner"
  if ($Filter) { $repos =$repos | Where-Object { $_.full_name -like "*$Filter*" -or $_.name -like "*$Filter*" } }
  if (-not $repos) { throw "No repositories found." }

  Write-Host ""
  for ($i = 0; $i -lt $repos.Count; $i++) {
    Write-Host "[$i]$($repos[$i].full_name)  private=$($repos[$i].private)  default=$($repos[$i].default_branch)"
  }

  $pick = Read-Host "Enter repo numbers separated by commas, or * for all"
  if ($pick -eq "*") { return $repos }

  $indexes =$pick.Split(",") | ForEach-Object { [int]$_.Trim() }$selected = @()
  foreach ($idx in$indexes) {
    if ($idx -ge 0 -and$idx -lt $repos.Count) {$selected += $repos[$idx] }
  }
  if (-not $selected) { throw "No valid repos selected." }
  return $selected
}

function Apply-Codeowners {
  param([string]$FullName, [string]$Branch)

  $contentB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($CodeownersContent))$body = @{
    message = "Add or update CODEOWNERS"
    content = $contentB64
    branch  = $Branch
  }

  try {
    $existing = Invoke-GHGet "https://api.github.com/repos/$FullName/contents/$CodeownersPath?ref=$Branch"
    if ($existing -and$existing.sha) { $body.sha =$existing.sha }
  } catch {}

  Invoke-GHPut "https://api.github.com/repos/$FullName/contents/$CodeownersPath" $body
}

function Apply-RepoRules {
  param(
    [string]$FullName,
    [bool]$MakePublic,
    [int]$ReviewCount,
    [bool]$RequireCodeOwner,
    [bool]$ForcePushesAllowed,
    [bool]$DeletionsAllowed,
    [bool]$CreationsBlocked,
    [bool]$LinearHistoryRequired,
    [bool]$AdminsEnforced,
    [bool]$AddCodeownersNow
  )

  Invoke-GHPatch "https://api.github.com/repos/$FullName" @{ private = (-not $MakePublic) }

  $repoInfo = Invoke-GHGet "https://api.github.com/repos/$FullName"
  $defaultBranch =$repoInfo.default_branch

  $protection = @{
    required_status_checks = $null
    enforce_admins = $AdminsEnforced
    required_pull_request_reviews = @{
      required_approving_review_count = $ReviewCount
      dismiss_stale_reviews = $true
      require_code_owner_reviews = $RequireCodeOwner
    }
    restrictions = $null
    allow_force_pushes = $ForcePushesAllowed
    allow_deletions = $DeletionsAllowed
    block_creations = $CreationsBlocked
    required_linear_history = $LinearHistoryRequired
  }

  Invoke-GHPut "https://api.github.com/repos/$FullName/branches/$defaultBranch/protection" $protection

  if ($AddCodeownersNow) { Apply-Codeowners -FullName $FullName -Branch$defaultBranch }
}

function Export-RepoRules {
  param([string]$FullName, [string]$Path)

  $repo = Invoke-GHGet "https://api.github.com/repos/$FullName"
  $branchProtection =$null
  try { $branchProtection = Invoke-GHGet "https://api.github.com/repos/$FullName/branches/$($repo.default_branch)/protection" } catch {}

  $snapshot = [ordered]@{
    repo = @{
      private = $repo.private
      default_branch = $repo.default_branch
    }
    branch_protection = $branchProtection
  }

  $snapshot \vert{} ConvertTo-Json -Depth 40 \vert{} Set-Content -Path$Path -Encoding UTF8
  Write-Host "Exported rules for $FullName to$Path"
}

function Import-RepoRules {
  param([string]$FullName, [string]$Path)

  $data = Get-Content$Path -Raw | ConvertFrom-Json
  $repo = Invoke-GHGet "https://api.github.com/repos/$FullName"

  Invoke-GHPatch "https://api.github.com/repos/$FullName" @{ private = [bool]$data.repo.private }
  Invoke-GHPut "https://api.github.com/repos/$FullName/branches/$($repo.default_branch)/protection" $data.branch_protection
}

$repos =$null
if (-not $CreateRepo) {$repos = Select-Repos
}

if ($CreateRepo) {
  if (-not $NewRepoName) {$NewRepoName = Read-Host "New repo name" }
  $createBody = @{
    name        = $NewRepoName
    description = $NewRepoDescription
    private     = (-not $Public)
    auto_init   = [bool]$NewRepoAutoInit
  }
  Invoke-GHPost "https://api.github.com/user/repos" $createBody
  return
}

foreach ($repo in$repos) {
  if ($ExportRules) {
    Export-RepoRules -FullName $repo.full_name -Path$ExportPath
    continue
  }

  if ($ImportRules) {
    Import-RepoRules -FullName $repo.full_name -Path$ExportPath
    continue
  }

  if ($CopyRules) {
    if (-not $CopyFromRepo) { throw "Set -CopyFromRepo." }
    $source = Invoke-GHGet "https://api.github.com/repos/$CopyFromRepo"
    $bp = Invoke-GHGet "https://api.github.com/repos/$CopyFromRepo/branches/$($source.default_branch)/protection"
    if ($Apply) {
      Invoke-GHPut "https://api.github.com/repos/$($repo.full_name)/branches/$($repo.default_branch)/protection" $bp
    } else {
      Write-Host "[DRY RUN] Copying rules from $CopyFromRepo to $($repo.full_name)"
    }
    continue
  }

  Apply-RepoRules `
    -FullName $repo.full_name `
    -MakePublic:$Public `
    -ReviewCount $Reviews `
    -RequireCodeOwner:$RequireCodeOwnerReviews `
    -ForcePushesAllowed:$AllowForcePushes `
    -DeletionsAllowed:$AllowDeletions `
    -CreationsBlocked:$BlockCreations `
    -LinearHistoryRequired:$RequiredLinearHistory `
    -AdminsEnforced:$EnforceAdmins `
    -AddCodeownersNow:$AddCodeowners
}

if (-not $Apply) { Write-Host "Dry run complete. Re-run with -Apply to execute." }
'@

$menu = @'
while ($true) {
  Clear-Host
  Write-Host "================================" -ForegroundColor Cyan
  Write-Host "   KJM GitHub Secure Menu Tool  " -ForegroundColor Cyan
  Write-Host "================================" -ForegroundColor Cyan
  Write-Host "1) Create repo"
  Write-Host "2) Apply rules"
  Write-Host "3) Export rules"
  Write-Host "4) Import rules"
  Write-Host "5) Dry-run apply rules"
  Write-Host "6) Auth setup"
  Write-Host "0) Exit"
  $choice = Read-Host "Choose an option"

  switch ($choice) {
    "1" { .\create-repo.ps1; Read-Host "Press Enter to continue" }
    "2" { .\apply-rules.ps1 -Apply; Read-Host "Press Enter to continue" }
    "3" { .\apply-rules.ps1 -ExportRules; Read-Host "Press Enter to continue" }
    "4" { .\apply-rules.ps1 -ImportRules -Apply; Read-Host "Press Enter to continue" }
    "5" { .\apply-rules.ps1; Read-Host "Press Enter to continue" }
    "6" { .\auth.ps1; Initialize-GitHubAuth | Out-Null; Read-Host "Auth ready. Press Enter to continue" }
    "0" { break }
    default { Write-Host "Invalid choice"; Read-Host "Press Enter to continue" }
  }
}
'@

$readme = @'
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
'@

# --- File Deployment ---
Set-Content -Path (Join-Path $targetDir "auth.ps1") -Value $auth -Encoding UTF8
Set-Content -Path (Join-Path $targetDir "create-repo.ps1") -Value $createRepo -Encoding UTF8
Set-Content -Path (Join-Path $targetDir "apply-rules.ps1") -Value $applyRules -Encoding UTF8
Set-Content -Path (Join-Path $targetDir "menu.ps1") -Value $menu -Encoding UTF8
Set-Content -Path (Join-Path $targetDir "README.md") -Value $readme -Encoding UTF8

Write-Host "All files successfully written! Run .\menu.ps1 to launch." -ForegroundColor Green