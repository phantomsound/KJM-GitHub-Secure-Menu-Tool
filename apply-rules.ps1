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
    Import-RepoRules -FullName $repo.full_name -Path$ImportPath
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
