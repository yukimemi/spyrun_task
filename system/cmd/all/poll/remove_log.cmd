@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{$_.readcount -gt 2})-join\"`n\");&$s" %*
@exit /b %errorlevel%

<#
  .SYNOPSIS
    remove_log
  .DESCRIPTION
    古いログを削除する
  .INPUTS
    - $mode: 動作モード
             "register": タスク登録 (デフォルト)
             "main": メイン処理
    - $base: spyrun remote base path
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change : 2024/04/01 17:19:17.
#>
param([string]$mode = "register", [string]$base)
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
$version = "20240401_171917"
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

    $app = [PSCustomObject](Start-Init $version $mode $base)
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
        <Interval>PT1H</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>2023-10-01T00:00:00+09:00</StartBoundary>
      <Enabled>true</Enabled>
      <RandomDelay>PT1H</RandomDelay>
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
    $thresold = (Get-Date).AddHours(-3)
    $systemLogPath = [System.IO.Path]::Combine($app.spyrunBase, "system", "log")
    Remove-OldFile $systemLogPath $thresold
    $userLogPath = [System.IO.Path]::Combine($app.spyrunBase, "user", "log")
    Remove-OldFile $userLogPath $thresold
    # Remove logDir files.
    log $app.logDir
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






