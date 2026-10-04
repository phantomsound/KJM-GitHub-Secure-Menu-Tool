function Initialize-GitHubAuth {
  if ($env:GITHUB_TOKEN) { return "token" }

  # If gh is installed and already logged in, automatically reuse token
  if (Get-Command gh -ErrorAction SilentlyContinue) {
    try {
      $existingToken = (gh auth token 2>$null)
      if ($existingToken -and $LASTEXITCODE -eq 0) {
        $global:SessionGitHubToken = $existingToken.Trim()
        Write-Host "Authenticated via active GitHub CLI session." -ForegroundColor Green
        return "gh"
      }
    } catch {}
  }

  Write-Host "`n=== GitHub Authentication ===" -ForegroundColor Cyan
  Write-Host "1) Browser login (GitHub CLI)"
  Write-Host "2) Terminal login (Username & Personal Access Token)"
  Write-Host "3) Quick-paste Personal Access Token"
  $choice = Read-Host "Select option (1-3)"

  switch ($choice) {
    "1" {
      if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI ('gh') is not installed or not in PATH."
      }
      # Run interactively without suppressing device code output
      gh auth login -p https -w
      $token = (gh auth token 2>$null)
      if (-not $token) { throw "No token returned from GitHub CLI." }
      $global:SessionGitHubToken = $token.Trim()
      return "gh"
    }
    "2" {
      $user = Read-Host "GitHub Username"
      $cred = Read-Host "GitHub Password / Personal Access Token" -AsSecureString
      $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred)
      try {
        $rawToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
      } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
      }
      if (-not $rawToken) { throw "No token/password provided." }
      
      $global:SessionGitHubUser  = $user
      $global:SessionGitHubToken = $rawToken.Trim()
      return "basic_pat"
    }
    "3" {
      $token = Read-Host "Paste GitHub Token"
      if (-not $token) { throw "No token provided." }
      $global:SessionGitHubToken = $token.Trim()
      return "token"
    }
    default {
      throw "Invalid choice selected."
    }
  }
}

function Get-GitHubHeaders {
  if ($env:GITHUB_TOKEN) {
    $token = $env:GITHUB_TOKEN
  } elseif ($global:SessionGitHubToken) {
    $token = $global:SessionGitHubToken
  } else {
    Initialize-GitHubAuth | Out-Null
    $token = if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { $global:SessionGitHubToken }
  }

  @{
    Authorization          = "Bearer $token"
    Accept                 = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
  }
}
