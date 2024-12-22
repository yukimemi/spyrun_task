@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{$_.readcount -gt 2})-join\"`n\");&$s" %*
@exit /b %errorlevel%

<#
  .SYNOPSIS
    archive
  .DESCRIPTION
    古いものを archive する
  .INPUTS
    - mode: "register": タスク登録, "main": 処理実行
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change: 2024/12/10 14:35:05.
#>
param([string]$mode = "register")
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
$version = "20241210_143505"
# Enable-RunspaceDebug -BreakAll

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
    log "Remove: $($_.FullName)"
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
        <Interval>PT6H</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>2023-10-01T00:00:00+09:00</StartBoundary>
      <Enabled>true</Enabled>
      <RandomDelay>PT6H</RandomDelay>
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
    # Archive log files.
    $src = [System.IO.Path]::Combine($app.baseRemote, "log", $env:COMPUTERNAME)
    if (Test-Path $src) {
      Sync-FS ([PSCustomObject]@{
          src = $src
          dst = [System.IO.Path]::Combine($app.baseRemote, "archive", "log", $env:COMPUTERNAME)
          type = "directory"
          option = "/e /move /minage:${thresold} /r:1 /w:1"
          async = $true
        })
    }
    $src = [System.IO.Path]::Combine($app.baseRemote, "core", "log", $env:COMPUTERNAME)
    if (Test-Path $src) {
      Sync-FS ([PSCustomObject]@{
          src = $src
          dst = [System.IO.Path]::Combine($app.baseRemote, "archive", "core", "log", $env:COMPUTERNAME)
          type = "directory"
          option = "/e /move /minage:${thresold} /r:1 /w:1"
          async = $true
        })
    }
    $src = [System.IO.Path]::Combine($app.baseRemote, "system", "log", $env:COMPUTERNAME)
    if (Test-Path $src) {
      Sync-FS ([PSCustomObject]@{
          src = $src
          dst = [System.IO.Path]::Combine($app.baseRemote, "archive", "system", "log", $env:COMPUTERNAME)
          type = "directory"
          option = "/e /move /minage:${thresold} /r:1 /w:1"
          async = $true
        })
    }
    $src = [System.IO.Path]::Combine($app.baseRemote, "user", "log", $env:COMPUTERNAME)
    if (Test-Path $src) {
      Sync-FS ([PSCustomObject]@{
          src = $src
          dst = [System.IO.Path]::Combine($app.baseRemote, "archive", "user", "log", $env:COMPUTERNAME)
          type = "directory"
          option = "/e /move /minage:${thresold} /r:1 /w:1"
          async = $true
        })
    }

    # Remove old archive.
    $archive = [System.IO.Path]::Combine($app.baseRemote, "archive", "log", $env:COMPUTERNAME)
    $coreArchive = [System.IO.Path]::Combine($app.baseRemote, "archive", "core", "log", $env:COMPUTERNAME)
    $systemArchive = [System.IO.Path]::Combine($app.baseRemote, "archive", "system", "log", $env:COMPUTERNAME)
    $userArchive = [System.IO.Path]::Combine($app.baseRemote, "archive", "user", "log", $env:COMPUTERNAME)
    $thresold = -3
    $s = @"
@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "`$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{`$_.readcount -gt 2})-join\"``n\");&`$s" %*
@exit /b %errorlevel%
function log { ${Function:log} }
function Remove-OldFiles { ${Function:Remove-OldFiles} }
Remove-OldFiles $archive $thresold
Remove-OldFiles $coreArchive $thresold
Remove-OldFiles $systemArchive $thresold
Remove-OldFiles $userArchive $thresold
Remove-Item -Force ([System.IO.Path]::GetFullPath(`$env:__SCRIPTPATH))
"@

    $scriptPath = "${env:tmp}\$($app.cmdName).cmd"
    [System.IO.File]::WriteAllText($scriptPath, $s)
    Sync-FS ([PSCustomObject]@{
        src = $scriptPath
        dst = [System.IO.Path]::Combine($app.baseRemote, "core", "cmd", "local", $env:COMPUTERNAME, $app.cmdFileName)
        type = "file"
        async = $true
      })

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
