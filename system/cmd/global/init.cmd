@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{$_.readcount -gt 2})-join\"`n\");&$s" %*
@exit /b %errorlevel%

<#
  .SYNOPSIS
    init
  .DESCRIPTION
    初期処理を実行する
  .INPUTS
    - mode: "register": タスク登録, "main": 処理実行
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change: 2025/04/27 18:16:39.
#>
param([string]$mode = "register")
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
$version = "20250427_181639"
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
    $initFlg = [System.IO.Path]::Combine($app.baseLocal, "flg", $app.cmdName, $app.version)

    if (Test-Path $initFlg) {
      log "${initFlg} is exist ! so skip !"
      return $app.cnst.SUCCESS
    }

    # core/cmd/local
    $initSrc = [System.IO.Path]::Combine($app.datRemote, "init", $env:COMPUTERNAME.Substring(0, 4), "core", "cmd", "local")
    $initDst = [System.IO.Path]::Combine($app.baseRemote, "core", "cmd", "local", $env:COMPUTERNAME)
    New-Item -Force -ItemType Directory $initDst | Out-Null
    Sync-FS ([PSCustomObject]@{
        src = $initDst
        dst = $initSrc
        type = "directory"
        option = "/e /xf *.*"
      })

    log "[${initSrc}] -> [${initDst}] is start ..."
    $result = Sync-FS ([PSCustomObject]@{
        src = $initSrc
        dst = $initDst
        type = "directory"
        option = "/e"
      })

    if ($result -ne 0) {
      log "[${initSrc}] -> [${initDst}] is failed ... result: [${result}]" "Red"
      return $app.cnst.ERROR
    }
    log "[${initSrc}] -> [${initDst}] is end. result: [${result}]"

    # system/cmd/local
    $initSrc = [System.IO.Path]::Combine($app.datRemote, "init", $env:COMPUTERNAME.Substring(0, 4), "system", "cmd", "local")
    $initDst = [System.IO.Path]::Combine($app.baseRemote, "system", "cmd", "local", $env:COMPUTERNAME)
    New-Item -Force -ItemType Directory $initDst | Out-Null
    Sync-FS ([PSCustomObject]@{
        src = $initDst
        dst = $initSrc
        type = "directory"
        option = "/e /xf *.*"
      })

    log "[${initSrc}] -> [${initDst}] is start ..."
    $result = Sync-FS ([PSCustomObject]@{
        src = $initSrc
        dst = $initDst
        type = "directory"
        option = "/e"
      })

    if ($result -ne 0) {
      log "[${initSrc}] -> [${initDst}] is failed ... result: [${result}]" "Red"
      return $app.cnst.ERROR
    }
    log "[${initSrc}] -> [${initDst}] is end. result: [${result}]"

    # user/cmd/local
    $initSrc = [System.IO.Path]::Combine($app.datRemote, "init", $env:COMPUTERNAME.Substring(0, 4), "user", "cmd", "local")
    $initDst = [System.IO.Path]::Combine($app.baseRemote, "user", "cmd", "local", $env:COMPUTERNAME)
    New-Item -Force -ItemType Directory $initDst | Out-Null
    Sync-FS ([PSCustomObject]@{
        src = $initDst
        dst = $initSrc
        type = "directory"
        option = "/e /xf *.*"
      })

    log "[${initSrc}] -> [${initDst}] is start ..."
    $result = Sync-FS ([PSCustomObject]@{
        src = $initSrc
        dst = $initDst
        type = "directory"
        option = "/e"
      })

    if ($result -ne 0) {
      log "[${initSrc}] -> [${initDst}] is failed ... result: [${result}]" "Red"
      return $app.cnst.ERROR
    }
    log "[${initSrc}] -> [${initDst}] is end. result: [${result}]"

    New-Item -Force -ItemType Directory (Split-Path -Parent $initFlg) | Out-Null
    New-Item -Force -ItemType File $initFlg | Out-Null

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
