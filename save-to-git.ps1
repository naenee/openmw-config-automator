# This script automates staging, committing, and pushing your changes to GitHub.

# Clear the screen for a clean start
Clear-Host

Write-Host "========================================" -ForegroundColor Green
Write-Host "   🚀 Git Upload Automation Script   "
Write-Host "========================================" -ForegroundColor Green

# --- 1. Prompt for the commit message ---
# Ask the user to describe the changes they made.
Write-Host "`nPlease enter a short description of the changes you made." -ForegroundColor Cyan
$commitMessage = Read-Host "Commit Message"

# Check if the user just pressed Enter without typing anything.
if ([string]::IsNullOrWhiteSpace($commitMessage)) {
    Write-Host "`n❌ Commit message cannot be empty. Aborting script." -ForegroundColor Red
    Read-Host "Press Enter to exit."
    exit # Stops the script
}

Write-Host "`n-------------------------------------------`n" -ForegroundColor Gray

# --- 2. Stage all files ---
Write-Host "STEP 1: Staging all changed files (git add .)..." -ForegroundColor Yellow
git add .
Write-Host "✅ Files staged." -ForegroundColor Green

# --- 3. Commit the changes ---
Write-Host "`nSTEP 2: Committing with your message..." -ForegroundColor Yellow
# The $commitMessage variable is used here.
git commit -m "$commitMessage"

# Check if the commit was successful. If not, it might be because there were no changes.
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n⚠️  No changes were committed. This usually means everything was already saved." -ForegroundColor Yellow
    Read-Host "Press Enter to exit."
    exit
}
Write-Host "✅ Changes committed." -ForegroundColor Green


# --- 4. Push to the remote repository ---
Write-Host "`nSTEP 3: Pushing changes to GitHub (git push)..." -ForegroundColor Yellow
git push
Write-Host "✅ Pushed to remote repository." -ForegroundColor Green


# --- Final Message ---
Write-Host "`n-------------------------------------------`n" -ForegroundColor Gray
Write-Host "🎉 Success! All changes have been uploaded to GitHub." -ForegroundColor Magenta
Write-Host "`n"
Read-Host "Press Enter to close this window."
