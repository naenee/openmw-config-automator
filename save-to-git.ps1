<#
.SYNOPSIS
    A robust script to automatically stash, pull, commit, and push changes to a Git repository.
.DESCRIPTION
    This script is designed to be called by the main automator. It safely synchronizes
    the local and remote repositories by stashing local changes before pulling,
    ensuring no local work is overwritten. It includes error checking at each step.
#>

# --- Script Body ---

# Get the directory of the currently running script.
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location -Path $scriptPath

Write-Host "--- Starting Git Synchronization ---" -ForegroundColor White

# --- STEP 1: Stash any uncommitted local changes ---
Write-Host "STEP 1: Stashing local changes for a clean pull (git stash)..." -ForegroundColor Cyan
git stash
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ ERROR: 'git stash' failed. Cannot proceed." -ForegroundColor Red
    exit 1
}
Write-Host "✅ Local changes stashed." -ForegroundColor Green

# --- STEP 2: Pull changes from the remote repository ---
Write-Host "`nSTEP 2: Pulling latest changes from remote (git pull)..." -ForegroundColor Cyan
git pull
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ ERROR: 'git pull' failed. Please check your connection and credentials." -ForegroundColor Red
    # Attempt to restore the stash before exiting
    git stash pop
    exit 1
}
Write-Host "✅ Pulled from remote repository." -ForegroundColor Green

# --- STEP 3: Re-apply stashed changes ---
Write-Host "`nSTEP 3: Re-applying stashed local changes (git stash pop)..." -ForegroundColor Cyan
git stash pop
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ ERROR: 'git stash pop' failed. This is likely due to a merge conflict." -ForegroundColor Red
    Write-Host "  Please resolve the conflicts manually in your code editor, then run 'git add .' and 'git commit' before trying again." -ForegroundColor Red
    exit 1
}
Write-Host "✅ Stashed changes re-applied." -ForegroundColor Green


# --- STEP 4: Add all new and modified files to the staging area ---
Write-Host "`nSTEP 4: Staging all changes (git add .)..." -ForegroundColor Cyan
git add .
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ ERROR: 'git add' failed." -ForegroundColor Red
    exit 1
}
Write-Host "✅ Staged all changes." -ForegroundColor Green

# --- STEP 5: Commit the changes ---
Write-Host "`nSTEP 5: Committing changes (git commit)..." -ForegroundColor Cyan
# Check if there's anything to commit
$status = git status --porcelain
if ($status) {
    git commit -m "Automated backup triggered by script."
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ ERROR: 'git commit' failed." -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Committed changes." -ForegroundColor Green
} else {
    Write-Host "  No new changes to commit." -ForegroundColor Gray
}


# --- STEP 6: Push the changes to the remote repository ---
Write-Host "`nSTEP 6: Pushing changes to GitHub (git push)..." -ForegroundColor Cyan
git push
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ ERROR: 'git push' failed. Please check your connection and credentials." -ForegroundColor Red
    exit 1
}
Write-Host "✅ Pushed to remote repository." -ForegroundColor Green

Write-Host "`n--- Git Synchronization Complete ---" -ForegroundColor White

