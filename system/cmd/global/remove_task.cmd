@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{$_.readcount -gt 2})-join\"`n\");&$s" %*
@exit /b %errorlevel%

<#
  .SYNOPSIS
    remove_task
  .DESCRIPTION
    不要なタスクの削除を行う
  .INPUTS
    - mode: "register": タスク登録, "main": 処理実行
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change : 2025/02/22 16:20:19.
#>
param([string]$mode = "register")
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
$version = "20250222_162019"
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
    $startTime = Get-Date
    . "C:\ProgramData\spyrun\core\cfg\common.ps1"

    $app = [PSCustomObject](Start-Init $mode $version)
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
        <Interval>PT3H</Interval>
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
      <Command>$($app.cmdFile)</Command>
      <Arguments>main</Arguments>
      <WorkingDirectory>$($app.cmdDir)</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

    if ($app.mode -eq "register") {
      Ensure-ScheduledTask $app $xmlStr | Out-Null
      exit $app.cnst.SUCCESS
    }
    if ((Check-ModifiedCmd ([PSCustomObject]@{
            path = $app.cmdFile
            xml = $xmlStr
          })) -ne 0) {
      return $app.cnst.ERROR
    }

    # Execute main.
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
        $cmdPath = [System.IO.Path]::Combine($app.baseLocal, "$($cmdPath -replace '^\\spyrun\\system', 'system\cmd')")
      }
      if ($cmdPath -match "^\\spyrun\\user") {
        $cmdPath = [System.IO.Path]::Combine($app.baseLocal, "$($cmdPath -replace '^\\spyrun\\user', 'user\cmd')")
      }
      if ($cmdPath -match "\\local\\") {
        $cmdPath = [System.IO.Path]::Combine($app.baseLocal, "$($cmdPath -replace '\\local\\(.*)', `"\local\${env:COMPUTERNAME}\`$1`")")
      }
      $cmdPath += ".cmd"
      log "target cmdPath: [${cmdPath}]"
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
    $endTime = Get-Date
    $span = $endTime - $startTime
    log ("Elapsed time: {0} {1:00}:{2:00}:{3:00}.{4:000}" -f $span.Days, $span.Hours, $span.Minutes, $span.Seconds, $span.Milliseconds)
    log "[Start-Main] End"
    Stop-Transcript
  }
}

# Call main.
exit Start-Main

# vim: ft=ps1
