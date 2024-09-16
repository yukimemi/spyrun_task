@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{$_.readcount -gt 2})-join\"`n\");&$s" %*
@exit /b %errorlevel%

<#
  .SYNOPSIS
    remove_task
  .DESCRIPTION
    不要なタスクの削除を行う
  .INPUTS
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change : 2024/09/17 00:17:31.
#>
param()
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
$version = "20240917_001731"
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

    . "C:\ProgramData\spyrun\bin\common.ps1"

    $app = [PSCustomObject](Start-Init $version)
    log "[Start-Main] Start"

    $xmlStr = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <URI>\spyrun\$($app.userType)\$($app.scope)\$($app.watchMode)\$($app.cmdName)</URI>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <Repetition>
        <Interval>PT15M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>2023-10-01T00:00:00+09:00</StartBoundary>
      <Enabled>true</Enabled>
      <RandomDelay>PT3H</RandomDelay>
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

    $sch = New-Object -ComObject Schedule.Service
    [void]$sch.connect()

    $removeTasks = {
      param([string]$taskPath, [string]$taskName)
      $taskPath = $taskPath -replace '^\\', ''
      $taskPath = $taskPath -replace '\\$', ''

      $folder = $sch.GetFolder($taskPath)
      if (![string]::IsNullOrEmpty($taskName)) {
        $folder.GetTasks(1) | Where-Object {
          $folder.Path -eq $taskPath -and $_.Name -eq $taskName
        } | ForEach-Object {
          log "Remove taskpath: [${taskPath}], taskname: [${taskName}]"
          [void]$folder.DeleteTask($_.Name, $null)
        }
      }
      if ([string]::IsNullOrEmpty($taskName)) {
        $folder.GetFolders(1) | ForEach-Object {
          & $removeTasks $_ $taskPath $taskName
        }
        $folder.GetTasks(1) | ForEach-Object {
          [void]$folder.DeleteTask($_.Name, $null)
        }
        if ($folder.Path -eq $taskPath -and $taskPath -ne "\") {
          log "Remove taskpath folder: [$taskPath]"
          $sch = New-Object -ComObject Schedule.Service
          [void]$sch.connect()
          $rootFolder = $sch.GetFolder("\")
          [void]$rootFolder.DeleteFolder($taskPath, $null)
        }
      }
    }

    # Execute main.
    Get-ScheduledTask | Where-Object {
      $_.URI -match "^\\spyrun"
    } | Where-Object {
      $_.URI -notmatch "^\\spyrun\\spyrun"
    } | Where-Object {
      $_.URI -notmatch "^\\spyrun\\system\\spyrun"
    } | Where-Object {
      $_.URI -notmatch "^\\spyrun\\user\\spyrun"
    } | ForEach-Object {
      log $_.URI
      $cmdPath = $_.URI
      if ($cmdPath -match "^\\spyrun\\system") {
        $cmdPath = [System.IO.Path]::Combine($app.base, "$($cmdPath -replace '^\\spyrun\\system', 'system\cmd')")
      }
      if ($cmdPath -match "^\\spyrun\\user") {
        $cmdPath = [System.IO.Path]::Combine($app.base, "$($cmdPath -replace '^\\spyrun\\user', 'user\cmd')")
      }
      if ($cmdPath -match "\\host\\") {
        $cmdPath = [System.IO.Path]::Combine($app.base, "$($cmdPath -replace '\\host\\([^\\]+)\\', `"\host\`$1\${env:COMPUTERNAME}\`")")
      }
      $cmdPath += ".cmd"
      if (Test-Path $cmdPath) {
        log "${cmdPath} is exist !"
      } else {
        log "Remove $($_.URI) task."
        & $removeTasks $_.TaskPath $_.TaskName
      }
    }

    return $app.cnst.SUCCESS

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

# vim: ft=ps1
