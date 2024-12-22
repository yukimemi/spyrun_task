@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{$_.readcount -gt 2})-join\"`n\");&$s" %*
@exit /b %errorlevel%

<#
  .SYNOPSIS
    windows_update
  .DESCRIPTION
    Windows Update を行う
  .INPUTS
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change : 2024/09/16 19:32:45.
#>
param()
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
$version = "20240104_192042"
# Enable-RunspaceDebug -BreakAll


<#
  .SYNOPSIS
    Main
  .DESCRIPTION
    Execute main
  .INPUTS
    - None
  .OUTPUTS
    - Result - 0 (SUCCESS), 1 (ERROR)
#>
function Start-Main {
  [CmdletBinding()]
  [OutputType([int])]
  param()

  try {

    . "C:\ProgramData\spyrun\core\cfg\common.ps1"

    $app = [PSCustomObject](Start-Init $version)
    log "[Start-Main] Start"

    $xmlStr = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <URI>\spyrun\$($app.userType)\$($app.scope)\$($app.cmdName)</URI>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <Repetition>
        <Interval>PT10M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>2023-10-01T00:00:00+09:00</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
    <BootTrigger>
      <Enabled>true</Enabled>
    </BootTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>Parallel</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>false</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>true</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>3</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$($app.cmdLocalFile)</Command>
      <WorkingDirectory>$($app.cmdLocalDir)</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

    Start-MainBefore $app $xmlStr

    # Execute main.
    # Search.
    $searchPattern = "IsInstalled=0 and Type='Software'"
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $searchResult = $updateSearcher.Search($searchPattern)
    log "List of applicable items on the machine."
    if ($searchResult.Updates.Count -eq 0) {
      log "There are no applicable updates."
      Remove-Item -Force $app.cmdRemoteFile
      Remove-ScheduledTask $app $xmlStr
      return $app.cnst.SUCCESS
    }

    # Download.
    $updatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl
    $isDownload = $false
    $searchResult.Updates | ForEach-Object {
      $update = $_
      log "Title: [$($update.Title)], LastDeploymentChangeTime: [$($update.LastDeploymentChangeTime)], MaxDownloadSize: [$($update.MaxDownloadSize)], IsDownloaded: [$($update.IsDownloaded)], Description: [$($update.Description)]"
      if (!$update.IsDownloaded) {
        [void]$updatesToDownload.Add($update)
        $isDownload = $true
      }
    }

    if ($isDownload) {
      log "Downloading updates..."
      $downloader = $updateSession.CreateUpdateDownloader()
      $downloader.Updates = $updatesToDownload
      $result = $downloader.Download()
      log $result
    } else {
      log "All updates are already downloaded."
    }

    # Install.
    $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
    log "Creating collection of downloaded updates to install..."
    $searchResult.Updates | ForEach-Object {
      $update = $_
      log "Title: [$($update.Title)], LastDeploymentChangeTime: [$($update.LastDeploymentChangeTime)], MaxDownloadSize: [$($update.MaxDownloadSize)], IsDownloaded: [$($update.IsDownloaded)], Description: [$($update.Description)]"
      if ($update.IsDownloaded) {
        [void]$updatesToInstall.Add($update)
      }
    }

    if ($updatesToInstall.Count -eq 0 ) {
      log "Not ready for installation."
      return $app.cnst.ERROR
    }

    log "Installing $($updatesToInstall.Count) updates..."
    $installer = $updateSession.CreateUpdateInstaller()
    $installer.Updates = $updatesToInstall
    $result = $installer.Install()

    if ($result.RebootRequired) {
      log "One or more updates are requiring reboot."
      # Restart-Computer -Force
    }

    if ($result.ResultCode -eq 2) {
      log "All updates installed successfully."
      return $app.cnst.SUCCESS
    } else {
      log "Some updates could not installed."
      log "result code: [$($result.ResultCode)]"
      return $app.cnst.ERROR
    }

  } catch {
    Write-Host "[Start-Main] Error ! $_"
    log "[Start-Main] Error ! $_" "Red"
    # Enable-RunSpaceDebug -BreakAll
    return $app.cnst.ERROR
  } finally {
    if ($null -ne $app -and $app.lock) {
      $app.mutex.ReleaseMutex()
      $app.mutex.Close()
      $app.mutex.Dispose()
    }
    log "[Start-Main] End"
    Stop-Transcript
  }
}

# Call main.
exit Start-Main
