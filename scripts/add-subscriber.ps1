#Requires -Version 5.1
# Usage: .\add-subscriber.ps1 <github_username>
# Adds a subscriber as a collaborator on the aikit-pro-skills repo.

param([Parameter(Mandatory)][string]$Username)

$owner = "henkietenki"
$repo  = "aikit-pro-skills"
$token = $env:GITHUB_TOKEN
if (-not $token) { Write-Error "GITHUB_TOKEN not set"; exit 1 }

$headers = @{
    Authorization        = "Bearer $token"
    Accept               = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
    "Content-Type"       = "application/json"
}

$resp = Invoke-RestMethod `
    -Uri "https://api.github.com/repos/$owner/$repo/collaborators/$Username" `
    -Method PUT `
    -Headers $headers `
    -Body '{"permission":"pull"}'

Write-Host "✓ @$Username invited to $owner/$repo — they'll get an email to accept."
