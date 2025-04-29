@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{$_.readcount -gt 2})-join\"`n\");&$s" %*
@exit /b %errorlevel%

<#
  .SYNOPSIS
    swinfo
  .DESCRIPTION
    ソフトウェア情報取得を行う
  .INPUTS
    - mode: "register": タスク登録, "main": 処理実行
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change: 2025/04/29 21:08:26.
#>
param([string]$mode = "register")
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
$version = "20250429_210826"
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

    # Execute main.
    $clctLocal = [System.IO.Path]::Combine($app.clctLocal, $app.cmdName)
    $collectJsonLatest = [System.IO.Path]::Combine($clctLocal, "latest", "${env:COMPUTERNAME}.json")
    New-Item -Force -ItemType Directory (Split-Path -Parent $collectJsonLatest) | Out-Null
    $today = Get-Date -f "yyyyMMdd"
    $collectJsonToday = [System.IO.Path]::Combine($clctLocal, $today, "${env:COMPUTERNAME}.json")
    New-Item -Force -ItemType Directory (Split-Path -Parent $collectJsonToday) | Out-Null
    $swMasterCfgRemote = [System.IO.Path]::Combine($app.datRemote, $app.cmdName, "sw_master.json")
    $term = $env:COMPUTERNAME.Substring(0, 4)
    $swTermCfgRemote = [System.IO.Path]::Combine($app.datRemote, $app.cmdName, "sw_${term}.json")
    $swLocalCfgRemote = [System.IO.Path]::Combine($app.datRemote, $app.cmdName, "sw_${env:COMPUTERNAME}.json")
    $swMasterCfgLocal = $swMasterCfgRemote.Replace($app.datRemote, $app.datLocal)
    $swTermCfgLocal = $swTermCfgRemote.Replace($app.datRemote, $app.datLocal)
    $swLocalCfgLocal = $swLocalCfgRemote.Replace($app.datRemote, $app.datLocal)
    $flg = [System.IO.Path]::Combine($app.flgLocal, "$($app.cmdName).flg")

    if (!(Test-Path $flg)) {
      $s = @"
@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "`$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{`$_.readcount -gt 2})-join\"``n\");&`$s" %*
@exit /b %errorlevel%

`$ErrorActionPreference = "Stop"
trap { log `$_ "Red"; throw `$_ }
function log { ${Function:log} }

if (!(Test-Path "${swMasterCfgRemote}")) {
  New-Item -Force -ItemType Directory (Split-Path -Parent "${swMasterCfgRemote}") | Out-Null
  "[]" | Set-Content -Encoding utf8 "${swMasterCfgRemote}"
}
if (!(Test-Path "${swTermCfgRemote}")) {
  New-Item -Force -ItemType Directory (Split-Path -Parent "${swTermCfgRemote}") | Out-Null
  "[]" | Set-Content -Encoding utf8 "${swTermCfgRemote}"
}
if (!(Test-Path "${swLocalCfgRemote}")) {
  New-Item -Force -ItemType Directory (Split-Path -Parent "${swLocalCfgRemote}") | Out-Null
  "[]" | Set-Content -Encoding utf8 "${swLocalCfgRemote}"
}

New-Item -Force -ItemType Directory (Split-Path -Parent "${flg}") | Out-Null
Get-Date | Set-Content -Encoding utf8 "${flg}"

Remove-Item -Force ([System.IO.Path]::GetFullPath(`$env:__SCRIPTPATH))
"@

      $scriptPath = "${env:tmp}\$($app.cmdName).cmd"
      [System.IO.File]::WriteAllText($scriptPath, $s)
      Sync-FS ([PSCustomObject]@{
          src = $scriptPath
          dst = [System.IO.Path]::Combine($app.baseRemote, "core", "cmd", "local", $env:COMPUTERNAME, $app.cmdFileName)
          type = "file"
        })
      return $app.cnst.SUCCESS
    }

    $resultSyncMaster = Sync-FS ([PSCustomObject]@{
        src = $swMasterCfgRemote
        dst = $swMasterCfgLocal
        type = "file"
        option = "-Force"
      })
    log "resultSyncMaster: [${resultSyncMaster}]"
    $resultSyncTerm = Sync-FS ([PSCustomObject]@{
        src = $swTermCfgRemote
        dst = $swTermCfgLocal
        type = "file"
        option = "-Force"
      })
    log "resultSyncTerm: [${resultSyncTerm}]"
    $resultSyncLocal = Sync-FS ([PSCustomObject]@{
        src = $swLocalCfgRemote
        dst = $swLocalCfgLocal
        type = "file"
        option = "-Force"
      })
    log "resultSyncLocal: [${resultSyncLocal}]"

    $resultDate = ""
    if (Test-Path $collectJsonLatest) {
      $resultDate = (Get-Content -Encoding utf8 $collectJsonLatest | ConvertFrom-Json).resultDate
    }
    if ($resultSyncMaster -eq $app.cnst.SUCCESS -and $resultSyncTerm -eq $app.cnst.SUCCESS -and $resultSyncLocal -eq $app.cnst.SUCCESS) {
      log "Result sync are all clear !"
      $resultDate = Get-Date -Format "yyyy/MM/dd HH:mm:ss.fff"
    }

    $swMaster = Get-Content -Encoding utf8 $swMasterCfgLocal | ConvertFrom-Json
    $swTerm = Get-Content -Encoding utf8 $swTermCfgLocal | ConvertFrom-Json
    $swLocal = Get-Content -Encoding utf8 $swLocalCfgLocal | ConvertFrom-Json

    @($swMaster, $swTerm, $swLocal) | ForEach-Object {
      $sws = $_
      $sws | ForEach-Object {
        $sw = $_
        $actual = Invoke-Expression $sw.actualcmd
        $expected = $sw.expected
        $assert = Invoke-Expression $sw.assertcmd
        $sw | Add-Member -MemberType NoteProperty -Name "actual" -Value $actual
        $sw | Add-Member -MemberType NoteProperty -Name "assert" -Value $assert
        log "------------------------------"
        log "sw: $($sw | ConvertTo-Json)"
        log "------------------------------"
        $sw
      }
    } | Set-Variable sws

    [PSCustomObject]@{
      time = [PSCustomObject]@{
        in = $startTime.ToString("yyyy/MM/dd HH:mm:ss.fff")
        out = $resultDate
      }
      sws = @($sws)
    } | ConvertTo-Json | Set-Content -Encoding utf8 $collectJsonLatest
    Copy-Item -Force $collectJsonLatest $collectJsonToday

    Get-ChildItem -Force -Recurse -File $clctLocal | ForEach-Object {
      $src = $_.FullName
      $dst = $src.Replace($app.clctLocal, $app.clctRemote)
      Sync-FS ([PSCustomObject]@{
          src = $src
          dst = $dst
          type = "file"
          option = "-Force"
          remove = $_.FullName -notmatch "latest"
        })
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
