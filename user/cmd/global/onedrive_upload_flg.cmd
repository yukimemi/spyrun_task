@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{$_.readcount -gt 2})-join\"`n\");&$s" %*
@exit /b %errorlevel%

<#
  .SYNOPSIS
    onedrive_upload_flg
  .DESCRIPTION
    OneDrive のパス情報を記録する
  .INPUTS
    - mode: "register": タスク登録, "main": 処理実行
    - async: "true": 非同期実行, "false": 同期実行
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change: 2025/04/06 09:15:41.
#>
param([string]$mode = "register", [bool]$async = $false)
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
$version = "20250406_091541"
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
        <Interval>PT10H</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>2023-10-01T00:00:00+09:00</StartBoundary>
      <Enabled>true</Enabled>
      <RandomDelay>PT10H</RandomDelay>
    </TimeTrigger>
    <LogonTrigger>
      <Enabled>true</Enabled>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <GroupId>S-1-5-32-545</GroupId>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
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
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>3</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>C:\Windows\system32\wscript.exe</Command>
      <Arguments>"$($app.spyrunBase)\core\cfg\launch.js" "$($app.cmdFile)" main</Arguments>
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
    if ([string]::IsNullOrEmpty($env:ONEDRIVE)) {
      log "%ONEDRIVE% is Null or Empty !"
      exit $app.cnst.ERROR
    }
    $oneDrivePathFlg = [System.IO.Path]::Combine($app.flgLocal, "onedrive_upload.flg")
    New-Item -Force -ItemType Directory (Split-Path -Parent $oneDrivePathFlg) | Out-Null
    log "${env:ONEDRIVE} -> ${oneDrivePathFlg}"
    $env:ONEDRIVE | Set-Content -Encoding utf8 $oneDrivePathFlg

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
