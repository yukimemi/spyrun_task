@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{$_.readcount -gt 2})-join\"`n\");&$s" %*
@exit /b %errorlevel%

<#
  .SYNOPSIS
    remove_log
  .DESCRIPTION
    古いログを削除する
  .INPUTS
    - mode: "register": タスク登録, "main": 処理実行
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change: 2024/10/12 16:38:54.
#>
param([string]$mode = "register")
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
$version = "20241012_163854"
# Enable-RunspaceDebug -BreakAll

<#
.SYNOPSIS
  Remove-OldFile
.DESCRIPTION
  Remove old file
.INPUTS
  - path: 削除パス
  - thresold: 削除閾値
.OUTPUTS
  - None
#>
function Remove-OldFile {
  [CmdletBinding()]
  param([string]$path, [datetime]$thresold)

  log "[Remove-OldFile] path: [${path}]"

  Get-ChildItem -Force -Recurse -File $path -ea Continue | Where-Object {
    trap {
      log $_ "Red"
    }
    $_.LastWriteTime -lt $thresold
  } | ForEach-Object {
    trap {
      log $_ "Red"
    }
    log "Remove: $($_.FullName)"
    Remove-Item -Force $_.FullName -ea Continue
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

    . "C:\ProgramData\spyrun\bin\common.ps1"

    $app = [PSCustomObject](Start-Init $mode $version)
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

    # Execute main.
    $thresold = (Get-Date).AddHours(-2)
    $baseLogDir = [System.IO.Path]::Combine($app.baseLocal, "log")
    Remove-OldFile $baseLogDir $thresold
    $systemLogDir = [System.IO.Path]::Combine($app.baseLocal, "system", "log")
    Remove-OldFile $systemLogDir $thresold
    $userLogDir = [System.IO.Path]::Combine($app.baseLocal, "user", "log")
    Remove-OldFile $userLogDir $thresold

    # Remove logDir files.
    Remove-OldFile $app.logDir $thresold

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
