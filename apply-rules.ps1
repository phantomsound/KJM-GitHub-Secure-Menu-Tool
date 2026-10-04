param(
  [switch]$Apply,
  [string]$Filter,
  [switch]$ToggleVisibilityOnly,
  [string]$SetVisibility, # "public" or "private"
  [switch]$CopyRulesInteractive,
  [string]$CopyFromRepo,
  [switch]$ExportRules,
  [string]$ExportPath = ".\github-rules-backup.json",
  [switch]$ImportRules,
  [string]$ImportPath = ".\github-rules-backup.json",
  [string]$SecurityPreset = "Strict", # Strict, Standard, LockedReadOnly, Custom
  [int]$Reviews = 1,
  [switch]$RequireCodeOwnerReviews =$true,
  [switch]$AllowForcePushes =$false,
  [switch]$AllowDeletions =$false,
  [switch]$BlockCreations =$true,
  [switch]$RequiredLinearHistory =$true,
  [switch]$EnforceAdmins =$true,
  [switch]$AddCodeowners =$false,
  [string]$CodeownersPath = ".github/CODEOWNERS",
  [string]$CodeownersContent = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\auth.ps1"

$headers = Get-GitHubHeaders

function Invoke-GHGet($url) { Invoke-RestMethod -Method Get -Uri $url -Headers$headers }
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
  param([string]$PromptText = "Enter repo numbers separated by commas, or * for all")
  $repos = Invoke-GHGet "https://api.github.com/user/repos?per_page=100&affiliation=owner"
  if ($Filter) { $repos =$repos | Where-Object { $_.full_name -like "*$Filter*" -or $_.name -like "*$Filter*" } }
  if (-not $repos) { throw "No repositories found." }

  Write-Host "`n--- Repositories ---" -ForegroundColor Cyan
  for ($i = 0; $i -lt $repos.Count; $i++) {
    $vis = if ($repos[$i].private) { "private" } else { "public" }
    Write-Host "[$i] $($repos[$i].full_name) | $vis | branch: $($repos[$i].default_branch)"
  }

  $pick = Read-Host "`n$PromptText"
  if ($pick -eq "*") { return $repos }

  $indexes =$pick.Split(",") | ForEach-Object { [int]$_.Trim() }$selected = @()
  foreach ($idx in$indexes) {
    if ($idx -ge 0 -and$idx -lt $repos.Count) {$selected += $repos[$idx] }
  }
  if (-not $selected) { throw "No valid repos selected." }
  return $selected
}

# --- Visibility Only Flow ---
if ($ToggleVisibilityOnly) {$targetRepos = Select-Repos -PromptText "Select repo(s) to change visibility"
  foreach ($r in$targetRepos) {
    $targetVis =$SetVisibility
    if (-not $targetVis) {
      Write-Host "`nSelected: $($r.full_name) (Current: $(if ($r.private) {'private'} else {'public'}))"
      Write-Host "1) Make Public"
      Write-Host "2) Make Private"
      $vChoice = Read-Host "Select (1-2)"
      $targetVis = if ($vChoice -eq "1") { "public" } else { "private" }
    }
    $isPrivate = ($targetVis -eq "private")
    Write-Host "Updating $($r.full_name) to $targetVis..." -ForegroundColor Yellow
    Invoke-GHPatch "https://api.github.com/repos/$($r.full_name)" @{ private = $isPrivate }
    Write-Host "Done!" -ForegroundColor Green
  }
  return
}

# --- Interactive Copy Rules Flow ---
if ($CopyRulesInteractive) {
  Write-Host "`nSelect SOURCE repository to copy branch protection FROM:" -ForegroundColor Cyan
  $src = Select-Repos -PromptText "Select ONE source repo index"
  $srcRepo =$src[0]
  
  $sourceProtection =$null
  try {
    $sourceProtection = Invoke-GHGet "https://api.github.com/repos/$($srcRepo.full_name)/branches/$($srcRepo.default_branch)/protection"
  } catch {
    throw "Source repo $($srcRepo.full_name) has no branch protection configured on branch '$($srcRepo.default_branch)'."
  }

  Write-Host "`nSelect TARGET repository/repositories to apply these rules to:" -ForegroundColor Cyan
  $destRepos = Select-Repos -PromptText "Select target repo numbers, or * for all"

  foreach ($d in $destRepos) {
    if ($d.full_name -eq $srcRepo.full_name) { continue }
    Write-Host "Copying protection from $($srcRepo.full_name) to $($d.full_name)..." -ForegroundColor Yellow
    Invoke-GHPut "https://api.github.com/repos/$($d.full_name)/branches/$($d.default_branch)/protection" $sourceProtection
    Write-Host "Successfully protected $($d.full_name)." -ForegroundColor Green
  }
  return
}

# --- Export Rules Flow ---
if ($ExportRules) {
  $targets = Select-Repos -PromptText "Select repo to export protection from"
  $r = $targets[0]
  $repoData = Invoke-GHGet "https://api.github.com/repos/$($r.full_name)"
  $bp = $null
  try { $bp = Invoke-GHGet "https://api.github.com/repos/$($r.full_name)/branches/$($repoData.default_branch)/protection" } catch {}
  $snapshot = [ordered]@{ repo = @{ private = $repoData.private; default_branch = $repoData.default_branch }; branch_protection = $bp }
  $snapshot | ConvertTo-Json -Depth 40 | Set-Content -Path $ExportPath -Encoding UTF8
  Write-Host "Exported rules for $($r.full_name) to $ExportPath" -ForegroundColor Green
  return
}

# --- Import Rules Flow ---
if ($ImportRules) {
  if (-not (Test-Path $ImportPath)) { throw "Snapshot file not found at $ImportPath" }
  $data = Get-Content $ImportPath -Raw | ConvertFrom-Json
  $targets = Select-Repos -PromptText "Select target repos to restore/import protection to"
  foreach ($r in $targets) {
    Write-Host "Restoring configuration onto $($r.full_name)..." -ForegroundColor Yellow
    Invoke-GHPut "https://api.github.com/repos/$($r.full_name)/branches/$($r.default_branch)/protection" $data.branch_protection
    Write-Host "Import complete for $($r.full_name)." -ForegroundColor Green
  }
  return
}

# --- Standard / Preset Rule Configuration Flow ---
$repos = Select-Repos

# Apply security profile definitions
switch ($SecurityPreset) {
  "LockedReadOnly" {
    # Locked/Archived style: Block creations, force push, deletions, require 2 reviews, strict admin enforcement
    $Reviews = 2
    $RequireCodeOwnerReviews = $true
    $AllowForcePushes = $false
    $AllowDeletions = $false
    $BlockCreations = $true
    $RequiredLinearHistory = $true
    $EnforceAdmins = $true
  }
  "Standard" {
    # Typical team collaboration
    $Reviews = 1
    $RequireCodeOwnerReviews = $false
    $AllowForcePushes = $false
    $AllowDeletions = $false
    $BlockCreations = $false
    $RequiredLinearHistory = $false
    $EnforceAdmins = $false
  }
  "Strict" {
    # Full hardening
    $Reviews = 1
    $RequireCodeOwnerReviews = $true
    $AllowForcePushes = $false
    $AllowDeletions = $false
    $BlockCreations = $true
    $RequiredLinearHistory = $true
    $EnforceAdmins = $true
  }
}

foreach ($repo in $repos) {
  $defaultBranch = $repo.default_branch
  Write-Host "Configuring protection on $($repo.full_name) ($defaultBranch) using preset: $SecurityPreset" -ForegroundColor Cyan

  $protectionPayload = @{
    required_status_checks = $null
    enforce_admins = $EnforceAdmins
    required_pull_request_reviews = @{
      required_approving_review_count = $Reviews
      dismiss_stale_reviews = $true
      require_code_owner_reviews = $RequireCodeOwnerReviews
    }
    restrictions = $null
    allow_force_pushes = $AllowForcePushes
    allow_deletions = $DeletionsAllowed
    block_creations = $BlockCreations
    required_linear_history = $RequiredLinearHistory
  }

  Invoke-GHPut "https://api.github.com/repos/$($repo.full_name)/branches/$defaultBranch/protection" $protectionPayload
  Write-Host "Protection applied to $($repo.full_name)." -ForegroundColor Green
}
