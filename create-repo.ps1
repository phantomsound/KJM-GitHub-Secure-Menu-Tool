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
Write-Host "Creating repository as $visibility: $NewRepoName"

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
