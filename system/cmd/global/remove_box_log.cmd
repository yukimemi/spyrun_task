@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{$_.readcount -gt 2})-join\"`n\");&$s" %*
@exit /b %errorlevel%

<#
  .SYNOPSIS
    remove_box_log
  .DESCRIPTION
    Box のログを削除する
  .INPUTS
    - mode: "register": タスク登録, "main": 処理実行
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change: 2025/02/22 16:20:40.
#>
param([string]$mode = "register")
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
$version = "20250222_162040"
# Enable-RunspaceDebug -BreakAll

<#
  .SYNOPSIS
    Gets the file size in a human-readable format (KB, MB, GB).

  .DESCRIPTION
    This function takes a file path as input and returns the file size in the most appropriate unit (bytes, KB, MB, or GB), rounded to two decimal places.
    It handles errors if the file is not found.

  .PARAMETER Path
    The path to the file.

  .EXAMPLE
    Get-HumanReadableFileSize -Path "C:\path\to\your\file.txt"

  .EXAMPLE
    $size = Get-HumanReadableFileSize -Path "C:\temp\largefile.dat"
    Write-Host "File size: $size"
#>
function Get-HumanReadableFileSize {
  param([string]$path)
  $file = Get-ChildItem -Path $path
  $sizeInBytes = $file.Length
  if ($sizeInBytes -lt 1KB) {
    return "$($sizeInBytes) bytes"
  } elseif ($sizeInBytes -lt 1MB) {
    return "${[math]::Round(($sizeInBytes / 1KB), 2)} KB"
  } elseif ($sizeInBytes -lt 1GB) {
    return "${[math]::Round(($sizeInBytes / 1MB), 2)} MB"
  } else {
    return "${[math]::Round(($sizeInBytes / 1GB), 2)} GB"
  }
}

<#
  .SYNOPSIS
    Remove-OldFiles
  .DESCRIPTION
    古いファイルを削除する
  .INPUTS
    - path: 削除対象パス
    - thresold: 閾値 (日)
  .OUTPUTS
    - None
#>
function Remove-OldFiles {
  [CmdletBinding()]
  [OutputType([void])]
  param([string]$path, [int]$thresold)

  Get-ChildItem -Force -Recurse -File "${path}" | Where-Object {
    $_.LastWriteTime -lt (Get-Date).AddDays($thresold)
  } | ForEach-Object {
    $sizeHr = Get-HumanReadableFileSize $_.FullName
    log "Remove: $($_.FullName), size: ${sizeHr}"
    Remove-Item -Force $_.FullName
  }

  Get-ChildItem -Force -Recurse -Directory "${path}" | Where-Object {
    (Get-ChildItem -Force $_.FullName | Measure-Object).Count -eq 0
  } | ForEach-Object {
    Remove-Item -Force -Recurse $_.FullName
  }
}

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
        <Interval>PT1H</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>2023-10-01T00:00:00+09:00</StartBoundary>
      <Enabled>true</Enabled>
      <RandomDelay>PT1H</RandomDelay>
    </TimeTrigger>
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
    $thresold = 1
    # move log files.
    $boxLogPath = [System.IO.Path]::Combine($env:LOCALAPPDATA, "Box\Box\logs")
    if (Test-Path $boxLogPath) {
      Remove-OldFiles $boxLogPath $thresold
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
