<#
.SYNOPSIS
    A robust script to automatically stash, pull, commit, and push changes to a Git repository.
.DESCRIPTION
    This script is designed to be called by the main automator. It safely synchronizes
    the local and remote repositories by stashing local changes before pulling,
    and intelligently handles cases where there are no local changes to stash.
.NOTES
    This is a personal script, tailored for a specific workflow. It is provided as-is
    and is not a community project. No support will be provided.
#>

# --- Script Body ---

# Get the directory of the currently running script.
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location -Path $scriptPath

Write-Host "--- Starting Git Synchronization ---" -ForegroundColor White

# --- STEP 1: Stash any uncommitted local changes ---
Write-Host "STEP 1: Stashing local changes for a clean pull (git stash)..." -ForegroundColor Cyan
# Capture the output to see if a stash was actually created.
$stashResult = git stash
$didStash = $stashResult -notmatch "No local changes to save"

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ ERROR: 'git stash' failed. Cannot proceed." -ForegroundColor Red
    exit 1
}
Write-Host "✅ Stash step complete." -ForegroundColor Green

# --- STEP 2: Pull changes from the remote repository ---
Write-Host "`nSTEP 2: Pulling latest changes from remote (git pull)..." -ForegroundColor Cyan
git pull
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ ERROR: 'git pull' failed. Please check your connection and credentials." -ForegroundColor Red
    # If pull fails, try to restore the stash so the user's work isn't hidden.
    if ($didStash) {
        Write-Host "  Attempting to restore stashed changes..." -ForegroundColor Yellow
        git stash pop
    }
    exit 1
}
Write-Host "✅ Pulled from remote repository." -ForegroundColor Green

# --- STEP 3: Re-apply stashed changes (if any) ---
if ($didStash) {
    Write-Host "`nSTEP 3: Re-applying stashed local changes (git stash pop)..." -ForegroundColor Cyan
    git stash pop
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ ERROR: 'git stash pop' failed. This is likely due to a merge conflict." -ForegroundColor Red
        Write-Host "  Please resolve the conflicts manually in your code editor, then run 'git add .' and 'git commit' before trying again." -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Stashed changes re-applied." -ForegroundColor Green
} else {
    Write-Host "`nSTEP 3: No local changes were stashed, skipping re-application." -ForegroundColor Gray
}

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

