@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{$_.readcount -gt 2})-join\"`n\");&$s" %*
@exit /b %errorlevel%

<#
  .SYNOPSIS
    execute_task
  .DESCRIPTION
    cmd を実行する
  .INPUTS
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change : 2024/09/24 01:02:14.
#>
param([bool]$async = $false)
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
$version = "20240924_010214"
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
      <RandomDelay>PT15M</RandomDelay>
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
      <Arguments>"$($app.spyrunDir)\launch.js" "$($app.cmdLocalFile)"</Arguments>
      <WorkingDirectory>$($app.cmdLocalDir)</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

    Start-MainBefore $app $xmlStr

    # Execute main.
    @(
      ([System.IO.Path]::Combine($app.base, "user", "cmd", "all")),
      ([System.IO.Path]::Combine($app.base, "user", "cmd", "host", "notify", $env:COMPUTERNAME)),
      ([System.IO.Path]::Combine($app.base, "user", "cmd", "host", "poll", $env:COMPUTERNAME))
    ) | ForEach-Object {
      Get-ChildItem -Force -Recurse -File $_ | Where-Object {
        $_.Extension -eq ".cmd"
      } | ForEach-Object {
        log "========== Execute-Process $($_.FullName) =========="
        $ret = Execute-Process $_.FullName
        log "code: $($ret.code)"
        log "stdout: $($ret.stdout)"
        log "stderr: $($ret.stderr)"
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
