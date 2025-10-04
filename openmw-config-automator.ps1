<#
.SYNOPSIS
    Performs a self-backup, cleans mod folder names, interactively handles nested mod options,
    generates a momw-customizations.toml file, and intelligently backs up to GitHub only on success.

.DESCRIPTION
    This script provides a full end-to-end automation for a custom mod folder.
    01. Backs up itself, adding a header with the date and number of lines changed.
    02. Clears the console and starts a log file in a dedicated working directory.
    03. Sanitizes top-level folder names in the mod directory.
    04. Scans a custom mod folder and intelligently auto-selects "00 Core" folders.
    05. Saves choices to individual files for persistence.
    06. Generates the momw-customizations.toml file.
    07. Manages backups of the previous customization file.
    08. Runs the MOMW configurator with a native PowerShell progress bar.
    09. Rearranges a specific line within the final openmw.cfg for load order optimization.
    10. Conditionally calls the 'save-to-git.ps1' script based on content hash changes or time.
#>

# --- Clear Screen ---
Clear-Host

# --- Configuration ---
# The root directory to search for your mods.
$ModRootDirectory = "D:\modding\Morrowind\custom"

# The relative path for the tool executables.
$ToolsDirectory = "..\momw-tools-pack"

# The relative path for logs and saved choices.
$WorkingDirectory = "..\openmw-config-automator.working"

# The directory where the final .toml file will be saved.
$UserDocumentsPath = [Environment]::GetFolderPath('MyDocuments')
$OutputDirectory = Join-Path -Path $UserDocumentsPath -ChildPath "My Games\openmw"

# The name of the output file.
$OutputFilename = "momw-customizations.toml"
$OutputFile = Join-Path -Path $OutputDirectory -ChildPath $OutputFilename

# The number of backup files to keep.
$BackupVersionsToKeep = 7


# --- Script Body ---

# --- 1. Resolve Working Directory ---
$ResolvedWorkingDirectory = $null
if ($PSScriptRoot) {
    $ResolvedWorkingDirectory = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath $WorkingDirectory)
    if (-not (Test-Path $ResolvedWorkingDirectory)) {
        Write-Host "Creating new working directory at: $ResolvedWorkingDirectory" -ForegroundColor DarkGray
        New-Item -ItemType Directory -Path $ResolvedWorkingDirectory | Out-Null
    }
} else {
    Write-Warning "Could not determine script location. Logging and choice saving will be disabled."
}


# --- 2. Self-Backup and Versioning ---
Write-Host "Performing self-backup and versioning..." -ForegroundColor Cyan

$thisScriptPath = $MyInvocation.MyCommand.Path
$thisScriptName = Split-Path -Path $thisScriptPath -Leaf
$contentHasChanged = $false
$timeSinceLastBackup = $null

if ($ResolvedWorkingDirectory) {
    $selfBackupDir = Join-Path -Path $ResolvedWorkingDirectory -ChildPath "script_backups"
    if (-not (Test-Path $selfBackupDir)) {
        New-Item -ItemType Directory -Path $selfBackupDir | Out-Null
    }

    $latestBackup = Get-ChildItem -Path $selfBackupDir -Filter "$thisScriptName.backup.*.ps1" | Sort-Object CreationTime -Descending | Select-Object -First 1
    $currentScriptContent = Get-Content -Path $thisScriptPath
    
    $headerDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $header = ""

    # Hash comparison logic
    $currentHash = (Get-FileHash -Path $thisScriptPath -Algorithm SHA256).Hash
    $hashFilePath = Join-Path -Path $selfBackupDir -ChildPath "latest_hash.txt"
    $oldHash = if (Test-Path $hashFilePath) { Get-Content $hashFilePath } else { "" }

    if ($currentHash -ne $oldHash) {
        $contentHasChanged = $true
    }

    if ($latestBackup) {
        $timeSinceLastBackup = (Get-Date) - $latestBackup.CreationTime
        $diff = Compare-Object -ReferenceObject (Get-Content $latestBackup.FullName) -DifferenceObject $currentScriptContent
        $linesChanged = ($diff | Measure-Object).Count
        $header = "<# .VERSION_INFO`n    Backup Date: $headerDate`n    Lines Changed Since Last Backup: $linesChanged`n#>"
    } else {
        $header = "<# .VERSION_INFO`n    Backup Date: $headerDate`n    Initial Backup.`n#>"
        $contentHasChanged = $true # Always treat the first run as a change
    }

    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $newBackupName = "$thisScriptName.backup.$timestamp.ps1"
    $newBackupPath = Join-Path -Path $selfBackupDir -ChildPath $newBackupName
    
    ($header + "`n" + ($currentScriptContent | Out-String)) | Set-Content -Path $newBackupPath
    Set-Content -Path $hashFilePath -Value $currentHash

    Write-Host "  Successfully created backup: $newBackupName" -ForegroundColor Green

    $allBackups = Get-ChildItem -Path $selfBackupDir -Filter "$thisScriptName.backup.*.ps1" | Sort-Object CreationTime -Descending
    if ($allBackups.Count -gt $BackupVersionsToKeep) {
        $allBackups | Select-Object -Skip $BackupVersionsToKeep | ForEach-Object {
            Write-Host "  Removing old backup: $($_.Name)" -ForegroundColor Magenta
            Remove-Item -Path $_.FullName -Force
        }
    }
}


# --- 3. Setup Logging ---
if ($ResolvedWorkingDirectory) {
    $LogFilePath = Join-Path -Path $ResolvedWorkingDirectory -ChildPath "mod_organizer_log.txt"
    Start-Transcript -Path $LogFilePath -Force
}

# --- 4. Sanitize Top-Level Folder Names ---
Write-Host "`nSanitizing top-level folder names in '$ModRootDirectory'..." -ForegroundColor Cyan

$scriptSuccessfullyCompleted = $true # Assume success until an error occurs

if (-Not (Test-Path -Path $ModRootDirectory -PathType Container)) {
    Write-Error "The directory specified does not exist: $ModRootDirectory"
    if ($global:Transcript) { Stop-Transcript }
    exit
}

Get-ChildItem -Path $ModRootDirectory -Directory | ForEach-Object {
    $oldName = $_.Name
    $newName = $oldName -replace "[^a-zA-Z0-9]", ""
    
    if ($oldName -ne $newName) {
        try {
            Rename-Item -Path $_.FullName -NewName $newName -ErrorAction Stop
            Write-Host "  Renamed: $oldName -> $newName" -ForegroundColor Yellow
        }
        catch {
            Write-Warning "Could not rename '$oldName' to '$newName'. It might be in use or a folder with that name already exists."
        }
    }
}


# --- 5. Generate TOML File ---
if (-not (Test-Path $OutputDirectory -PathType Container)) {
    Write-Host "`nOutput directory not found. Creating it: $OutputDirectory" -ForegroundColor Yellow
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

Write-Host "`nScanning for mods in: $ModRootDirectory" -ForegroundColor Cyan

$ChoicesDirectoryPath = $null
if ($ResolvedWorkingDirectory) {
    $ChoicesDirectoryPath = Join-Path -Path $ResolvedWorkingDirectory -ChildPath "mod_choices"
    if (-not (Test-Path $ChoicesDirectoryPath)) {
        Write-Host "Creating new choices directory at: $ChoicesDirectoryPath" -ForegroundColor DarkGray
        New-Item -ItemType Directory -Path $ChoicesDirectoryPath | Out-Null
    } else {
        Write-Host "Loading choices from: $ChoicesDirectoryPath" -ForegroundColor DarkGray
    }
}

$finalModPaths = [System.Collections.Generic.List[string]]::new()
$finalPluginFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

$processingQueue = [System.Collections.Queue]::new()
Get-ChildItem -Path $ModRootDirectory -Directory | ForEach-Object {
    $queueObject = [PSCustomObject]@{ TopLevelModName = $_.Name; PathToProcess = $_.FullName }
    $processingQueue.Enqueue($queueObject)
}

while ($processingQueue.Count -gt 0) {
    $currentItem = $processingQueue.Dequeue()
    $currentPath = $currentItem.PathToProcess
    $topLevelModName = $currentItem.TopLevelModName

    $numberedOptions = Get-ChildItem -Path $currentPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^\d{2}" } | Sort-Object Name

    if ($numberedOptions.Count -gt 0) {
        if ($numberedOptions.Count -eq 1 -and $numberedOptions[0].Name -imatch '00 Core*') {
            Write-Host ""
            Write-Host "Options for '$topLevelModName' in '$($currentItem.PathToProcess | Split-Path -Leaf)':" -ForegroundColor Yellow
            Write-Host "  Automatically selecting single '00 Core' option." -ForegroundColor Green
            
            $selectedDir = $numberedOptions[0]
            $queueObject = [PSCustomObject]@{ TopLevelModName = $topLevelModName; PathToProcess = $selectedDir.FullName }
            $processingQueue.Enqueue($queueObject)
        } else {
            Write-Host ""
            Write-Host "Options for '$topLevelModName' in '$($currentItem.PathToProcess | Split-Path -Leaf)':" -ForegroundColor Yellow
            
            $safeChoicePath = $currentPath.Replace($ModRootDirectory, "").Trim("\") -replace '[^a-zA-Z0-9]', '_'
            $folderChoiceKey = "$($topLevelModName)_$($safeChoicePath)"
            $folderChoiceFile = if ($ChoicesDirectoryPath) { Join-Path -Path $ChoicesDirectoryPath -ChildPath "$folderChoiceKey.txt" } else { $null }
            $selectedIndices = @()

            if ($folderChoiceFile -and (Test-Path $folderChoiceFile)) {
                $savedIndices = Get-Content $folderChoiceFile | ForEach-Object { [int]$_ }
                $validatedIndices = $savedIndices | Where-Object { $_ -lt $numberedOptions.Count }
                if ($validatedIndices.Count -eq $savedIndices.Count) {
                    $selectedIndices = $validatedIndices
                    Write-Host "  Using saved choice: $($selectedIndices -join ', ')" -ForegroundColor Green
                } else {
                    Write-Host "  Saved choice was invalid. Please choose again." -ForegroundColor Yellow
                    Remove-Item -Path $folderChoiceFile -Force
                }
            }
            
            if ($selectedIndices.Count -eq 0) {
                Write-Host "  Please choose which components to install:"
                for ($i = 0; $i -lt $numberedOptions.Count; $i++) { Write-Host "    [$i] $($numberedOptions[$i].Name)" }
                $userInput = Read-Host "Enter numbers, separated by commas"
                
                $selectedIndices = $userInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } | Where-Object { $_ -lt $numberedOptions.Count } | Sort-Object -Unique
                
                if ($selectedIndices.Count -gt 0) {
                    if ($folderChoiceFile) {
                        $selectedIndices | Set-Content -Path $folderChoiceFile
                        Write-Host "  Saved choice: $($selectedIndices -join ', ')" -ForegroundColor Green
                    }
                } else {
                    Write-Host "  Invalid selection. Skipping this branch." -ForegroundColor Red
                    continue
                }
            }

            foreach ($index in $selectedIndices) {
                $selectedDir = $numberedOptions[[int]$index]
                $queueObject = [PSCustomObject]@{ TopLevelModName = $topLevelModName; PathToProcess = $selectedDir.FullName }
                $processingQueue.Enqueue($queueObject)
            }
        }
    } else {
        $pluginsInPath = Get-ChildItem -Path $currentPath -Recurse -Include "*.omwscripts", "*.esp", "*.omwaddon" -File -ErrorAction SilentlyContinue
        $dataFolderNames = "Textures", "Meshes", "Icons", "Music", "Sound", "Splash", "Video"
        $dataFoldersInPath = Get-ChildItem -Path $currentPath -Recurse -Directory -Include $dataFolderNames -ErrorAction SilentlyContinue

        if ($pluginsInPath.Count -gt 0 -or $dataFoldersInPath.Count -gt 0) {
            Write-Host "Processing assets for '$topLevelModName' in '$($currentPath | Split-Path -Leaf)'" -ForegroundColor Cyan
            
            $dataDirectories = [System.Collections.Generic.List[string]]::new()
            if ($pluginsInPath.Count -gt 0) {
                $pluginParentDirs = $pluginsInPath | ForEach-Object { $_.Directory.FullName } | Sort-Object -Unique
                foreach ($dir in @($pluginParentDirs)) { $dataDirectories.Add($dir) }
            }
            if ($dataFoldersInPath.Count -gt 0) {
                $dataFolderParentDirs = $dataFoldersInPath | ForEach-Object { $_.Parent.FullName } | Sort-Object -Unique
                foreach ($dir in @($dataFolderParentDirs)) { $dataDirectories.Add($dir) }
            }
            
            $uniqueDataDirs = $dataDirectories | Sort-Object -Unique
            foreach ($dir in @($uniqueDataDirs)) { $finalModPaths.Add($dir) }

            $espFilesInMod = $pluginsInPath | Where-Object { $_.Extension -eq ".esp" }
            if ($espFilesInMod.Count -gt 1) {
                $safeChoicePath = $currentPath.Replace($ModRootDirectory, "").Trim("\") -replace '[^a-zA-Z0-9]', '_'
                $pluginChoiceKey = "$($topLevelModName)_$($safeChoicePath)_plugins"
                $pluginChoiceFile = if ($ChoicesDirectoryPath) { Join-Path -Path $ChoicesDirectoryPath -ChildPath "$pluginChoiceKey.txt" } else { $null }
                $selectedPluginNames = @()

                if ($pluginChoiceFile -and (Test-Path $pluginChoiceFile)) {
                    $savedPluginNames = Get-Content $pluginChoiceFile
                    $currentPluginNames = $pluginsInPath | Select-Object -ExpandProperty Name
                    $validSavedNamesCount = ($savedPluginNames | Where-Object { $currentPluginNames -icontains $_ } | Measure-Object).Count
                    if ($validSavedNamesCount -eq $savedPluginNames.Count) {
                        $selectedPluginNames = $savedPluginNames
                        Write-Host "  Using saved plugin choice: $($selectedPluginNames -join ', ')" -ForegroundColor Green
                    } else {
                        Write-Host "  Saved plugin choice was invalid. Please choose again." -ForegroundColor Yellow
                        Remove-Item -Path $pluginChoiceFile -Force
                    }
                }
                
                if ($selectedPluginNames.Count -eq 0) {
                    Write-Host "  Multiple ESPs found. Please choose:" -ForegroundColor Yellow
                    for ($i = 0; $i -lt $pluginsInPath.Count; $i++) {
                        Write-Host "    [$i] $($pluginsInPath[$i].Name)"
                    }
                    $pluginUserInput = Read-Host "Enter numbers, separated by commas"
                    
                    $selectedPluginIndices = $pluginUserInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' -and [int]$_ -lt $pluginsInPath.Count } | Select-Object -Unique
                    if ($selectedPluginIndices.Count -gt 0) {
                        $selectedPluginNames = @($selectedPluginIndices | ForEach-Object { $pluginsInPath[[int]$_].Name })
                        if ($pluginChoiceFile) {
                            $selectedPluginNames | Set-Content -Path $pluginChoiceFile
                            Write-Host "  Saved plugin choice: $($selectedPluginNames -join ', ')" -ForegroundColor Green
                        }
                    } else {
                        Write-Host "  Invalid plugin selection." -ForegroundColor Red
                    }
                }
                $pluginsInPath | Where-Object { $selectedPluginNames -icontains $_.Name } | ForEach-Object { $finalPluginFiles.Add($_) }
            } else {
                foreach ($plugin in @($pluginsInPath)) { $finalPluginFiles.Add($plugin) }
            }
        } else {
            $subDirectories = Get-ChildItem -Path $currentPath -Directory -ErrorAction SilentlyContinue
            if ($subDirectories.Count -gt 0) {
                foreach ($subDir in $subDirectories) {
                    $queueObject = [PSCustomObject]@{ TopLevelModName = $topLevelModName; PathToProcess = $subDir.FullName }
                    $processingQueue.Enqueue($queueObject)
                }
            }
            else {
                Write-Host "Skipping '$($currentPath | Split-Path -Leaf)' (no assets found)." -ForegroundColor DarkGray
            }
        }
    }
}

if ($finalModPaths.Count -eq 0) {
    Write-Host "`nNo valid mods were selected or found. No TOML file will be generated." -ForegroundColor Yellow
    if ($global:Transcript) { Stop-Transcript }
    exit
}

Write-Host "`n--- Summary of mods to be included ---" -ForegroundColor White
$allModPaths = $finalModPaths | Sort-Object -Unique
$formattedModPaths = $allModPaths | ForEach-Object {
    $relativePath = $_.Replace($ModRootDirectory, "")
    Write-Host "  Path: ...$relativePath"
    $_ -replace '\\', '\\'
}

$modFilenames = $finalPluginFiles.Name | Sort-Object -Unique
if ($modFilenames.Count -gt 0) {
    Write-Host "  Plugins:"
    $modFilenames | ForEach-Object { Write-Host "    - $_" }
}

Write-Host "`nGenerating TOML content..." -ForegroundColor Cyan

$pathsBlock = $formattedModPaths -join "`n"
$filesBlock = $modFilenames -join "`n"

$tomlContent = @"
[[Customizations]]
listName = "expanded-vanilla"
removeFallback = ["Movies_Company_Logo,bethesda logo.bik", "Movies_Morrowind_Logo,mw_logo.bik"]
[[Customizations.insert]]
insertBlock = """
$pathsBlock
"""
before = "Tools\\MOMWToolsPackCustom"

[[Customizations.insert]]
insertBlock = """
$filesBlock
"""
before = "AttendMe.omwscripts"
"@

if (Test-Path $OutputFile) {
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $backupFilename = "$OutputFilename.backup.$timestamp"
    Write-Host "`nExisting file found. Backing up to: $backupFilename" -ForegroundColor Yellow
    Rename-Item -Path $OutputFile -NewName $backupFilename
    
    $backupPattern = "$OutputFilename.backup.*"
    $allBackups = Get-childitem -Path $OutputDirectory -Filter $backupPattern | Sort-Object CreationTime -Descending
    
    if ($allBackups.Count -gt $BackupVersionsToKeep) {
        $backupsToDelete = $allBackups | Select-Object -Skip $BackupVersionsToKeep
        foreach ($file in $backupsToDelete) {
            Write-Host "  Removing old backup: $($file.Name)" -ForegroundColor Magenta
            Remove-Item -Path $file.FullName -Force
        }
    }
}

Write-Host "`nWriting configuration to $OutputFile..." -ForegroundColor Cyan

try {
    Set-Content -Path $OutputFile -Value $tomlContent -Encoding UTF8 -ErrorAction Stop
    Write-Host "Successfully created $OutputFile!" -ForegroundColor Green
}
catch {
    Write-Host "An error occurred while writing to the file: $($_.Exception.Message)" -ForegroundColor Red
    $scriptSuccessfullyCompleted = $false
}

# --- 6. Update OpenMW Configuration ---
if ($scriptSuccessfullyCompleted) {
    Write-Host "`nRunning MOMW Configurator to apply changes..." -ForegroundColor Cyan

    $lastLine = ""
    try {
        $resolvedToolsPath = if ($PSScriptRoot) { Resolve-Path (Join-Path $PSScriptRoot $ToolsDirectory) } else { $ToolsDirectory }
        $configuratorPath = Join-Path -Path $resolvedToolsPath -ChildPath "momw-configurator.exe"
        if (-not (Test-Path $configuratorPath)) { throw "momw-configurator.exe not found at the expected location: $configuratorPath" }

        $job = Start-Job -ScriptBlock { & $using:configuratorPath config expanded-vanilla --verbose 2>&1 }
        
        $spinner = '|', '/', '-', '\'
        $spinnerIndex = 0
        
        while ($job.State -eq 'Running') {
            $statusText = "Processing... " + $spinner[$spinnerIndex]
            Write-Progress -Activity "Running MOMW Configurator" -Status $statusText
            Start-Sleep -Milliseconds 150
            $spinnerIndex = ($spinnerIndex + 1) % $spinner.Length
        }

        Write-Progress -Activity "Running MOMW Configurator" -Completed
        
        $output = Receive-Job $job
        $lastLine = $output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1
        
        $ignorePatterns = @(
            'Skipping record of type SCPT',
            'could not be loaded due to error: Unexpected Tag: LUAL',
            'ignored empty value for key'
        )

        $allWarningsAndErrors = $output | Where-Object { $_ -match 'warning' -or $_ -match 'error' }

        $relevantErrorsAndWarnings = $allWarningsAndErrors
        foreach ($pattern in $ignorePatterns) {
            $relevantErrorsAndWarnings = $relevantErrorsAndWarnings | Where-Object { $_ -notmatch $pattern }
        }

        if ($relevantErrorsAndWarnings.Count -gt 0) {
            $scriptSuccessfullyCompleted = $false
            Write-Host "MOMW Configurator completed with relevant warnings or errors:" -ForegroundColor Red
            $relevantErrorsAndWarnings | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        } else {
             Write-Host "Configuration applied successfully (all benign issues filtered out)." -ForegroundColor Green
        }
    }
    catch {
        $scriptSuccessfullyCompleted = $false
        Write-Host "A critical error occurred while running the configurator: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        if ($job) { Remove-Job $job -Force }
    }

    if (-not $scriptSuccessfullyCompleted) {
        if ($lastLine) {
            if ($lastLine -imatch 'completed') {
                 Write-Host "`nFinal status from configurator: $lastLine" -ForegroundColor Green
            } else {
                 Write-Host "`nFinal status from configurator: $lastLine" -ForegroundColor Red
            }
        } else {
            Write-Host "`nScript finished with errors during configuration." -ForegroundColor Red
        }
    }
}

# --- 7. Final Tweak of openmw.cfg ---
if ($scriptSuccessfullyCompleted) {
    Write-Host "`nPerforming final tweak on openmw.cfg..." -ForegroundColor Cyan
    $cfgPath = Join-Path -Path $OutputDirectory -ChildPath "openmw.cfg"
    $lineToMove = "content=LuaMultiMark.omwaddon"
    $targetLine = "content=AttendMe.omwscripts"

    try {
        if (-not (Test-Path $cfgPath)) { throw "openmw.cfg not found at $cfgPath" }

        $cfgContentArray = @(Get-Content -Path $cfgPath)
        $cfgContentList = [System.Collections.Generic.List[string]]::new()
        foreach ($line in $cfgContentArray) { $cfgContentList.Add($line) }

        if ($cfgContentList.Contains($lineToMove) -and $cfgContentList.Contains($targetLine)) {
            [void]$cfgContentList.Remove($lineToMove)
            $targetIndex = $cfgContentList.IndexOf($targetLine)
            $cfgContentList.Insert($targetIndex, $lineToMove)
            Set-Content -Path $cfgPath -Value $cfgContentList
            Write-Host "Successfully moved '$lineToMove' in openmw.cfg." -ForegroundColor Green
        } else {
            $targetIndex = $cfgContentList.IndexOf($targetLine)
            if ($targetIndex -ge 0) {
                $cfgContentList.Insert($targetIndex, $lineToMove)
                Set-Content -Path $cfgPath -Value $cfgContentList
                Write-Host "Added '$lineToMove' to openmw.cfg as it was missing." -ForegroundColor Green
            } else {
                Write-Host "Could not find target line '$targetLine' in openmw.cfg. Skipping tweak." -ForegroundColor Yellow
            }
        }
    }
    catch {
        $scriptSuccessfullyCompleted = $false
        Write-Host "An error occurred during the openmw.cfg tweak: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- 8. Conditional GitHub Backup ---
if ($scriptSuccessfullyCompleted) {
    Write-Host "`nChecking conditions for GitHub backup..." -ForegroundColor Cyan
    
    $timeThreshold = New-TimeSpan -Hours 24
    $triggerUpload = $false
    $reason = ""

    if ($contentHasChanged) {
        $triggerUpload = $true
        $reason = "Script content has changed since last backup."
    }
    elseif ($timeSinceLastBackup -and ($timeSinceLastBackup -gt $timeThreshold)) {
        $triggerUpload = $true
        $reason = "Daily backup triggered (last backup was $($timeSinceLastBackup.Days)d, $($timeSinceLastBackup.Hours)h ago)."
    }

    if ($triggerUpload) {
        Write-Host "  Upload condition met: $reason" -ForegroundColor Green
        Write-Host "  Calling GitHub save script..." -ForegroundColor Cyan
        
        $githubScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "save-to-git.ps1"
        if (Test-Path $githubScriptPath) {
            & $githubScriptPath
        } else {
            Write-Warning "GitHub save script not found at '$githubScriptPath'. Skipping save."
        }

    } else {
        Write-Host "  Upload conditions not met (no changes and not enough time elapsed). Skipping GitHub backup." -ForegroundColor Gray
    }
} else {
    Write-Host "`nSkipping GitHub backup due to errors encountered during script execution." -ForegroundColor Yellow
}

Write-Host "`nAll steps completed!" -ForegroundColor Green

# --- Stop Logging ---
if ($global:Transcript) {
    Stop-Transcript
}

