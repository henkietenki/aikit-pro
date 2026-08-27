#Requires -Version 5.1
# Usage: .\remove-subscriber.ps1 <github_username>
# Removes a subscriber's collaborator access from aikit-pro-skills.

param([Parameter(Mandatory)][string]$Username)

$owner = "henkietenki"
$repo  = "aikit-pro-skills"
$token = $env:GITHUB_TOKEN
if (-not $token) { Write-Error "GITHUB_TOKEN not set"; exit 1 }

$headers = @{
    Authorization          = "Bearer $token"
    Accept                 = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

Invoke-RestMethod `
    -Uri "https://api.github.com/repos/$owner/$repo/collaborators/$Username" `
    -Method DELETE `
    -Headers $headers | Out-Null

Write-Host "✓ @$Username removed from $owner/$repo."
