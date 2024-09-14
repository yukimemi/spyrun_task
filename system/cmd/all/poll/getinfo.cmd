@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{$_.readcount -gt 2})-join\"`n\");&$s" %*
@exit /b %errorlevel%

<#
  .SYNOPSIS
    getinfo
  .DESCRIPTION
    情報取得を行う
  .INPUTS
    - $mode: 動作モード
             "register": タスク登録 (デフォルト)
             "main": メイン処理
    - $base: spyrun remote base path
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change : 2023/11/23 22:40:08.
#>
param([string]$mode = "register", [string]$base)
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
$version = "20231123_224008"
# Enable-RunspaceDebug -BreakAll

<#
  .SYNOPSIS
    Get-InfoByPsCommand
  .DESCRIPTION
    PowerShell コマンドを実行して情報を採取する
  .INPUTS
    - command: 実行コマンド
    - collect: 収集先パス
  .OUTPUTS
    - None
#>
function Get-InfoByPsCommand {
  [CmdletBinding()]
  [OutputType([void])]
  param([string]$command, [string]$collect)

  trap {
    log "[Get-InfoByPsCommand] Error $_" "Red"
    throw $_
  }

  $s = Get-Date
  log "Execute [${command}] ... start"
  $today = Get-Date -f "yyyyMMdd"
  $collectLatest = [System.IO.Path]::Combine($collect, $command, "latest", "${env:COMPUTERNAME}_${command}.csv")
  $collectToday = [System.IO.Path]::Combine($collect, $command, $today, "${env:COMPUTERNAME}_${command}_${today}.csv")
  New-Item -Force -ItemType Directory (Split-Path -Parent $collectLatest) | Out-Null
  New-Item -Force -ItemType Directory (Split-Path -Parent $collectToday) | Out-Null
  Invoke-Expression $command | Select-Object * | Convert-ArrayPropertyToString | Export-Csv -NoTypeInformation -Encoding utf8 $collectLatest
  Copy-Item -Force $collectLatest $collectToday
  $e = Get-Date
  $span = $e - $s
  log ("Execute [${command}] end ! Elaps: {0} {1:00}:{2:00}:{3:00}.{4:000}" -f $span.Days, $span.Hours, $span.Minutes, $span.Seconds, $span.Milliseconds)
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

    # Execute main.
    $collect = [System.IO.Path]::Combine($app.clct, $app.cmdName)
    Get-InfoByPsCommand "Get-ComputerInfo" $collect
    Get-InfoByPsCommand "Get-NetIPAddress" $collect
    Get-InfoByPsCommand "Get-NetIPConfiguration" $collect
    Get-InfoByPsCommand "Get-NetRoute" $collect
    Get-InfoByPsCommand "Get-DnsClientServerAddress" $collect
    Get-InfoByPsCommand "Get-HotFix" $collect

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