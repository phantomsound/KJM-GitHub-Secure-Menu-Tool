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
    "6" { . .\auth.ps1; Initialize-GitHubAuth | Out-Null; Read-Host "Auth ready. Press Enter to continue" }
    "0" { break }
    default { Write-Host "Invalid choice"; Read-Host "Press Enter to continue" }
  }
}
