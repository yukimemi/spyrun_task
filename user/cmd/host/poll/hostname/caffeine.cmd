@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{$_.readcount -gt 2})-join\"`n\");&$s" %*
@exit /b %errorlevel%

<#
  .SYNOPSIS
    caffeine
  .DESCRIPTION
    スリーブ抑止する
  .INPUTS
    - $mode: 動作モード
             "register": タスク登録 (デフォルト)
             "main": メイン処理
    - $base: spyrun remote base path
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change : 2024/04/14 16:48:54.
#>
param([string]$mode = "register", [string]$base, [bool]$async = $false)
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
$version = "20240414_164854"
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

    $app = [PSCustomObject](Start-Init $version $mode $base)
    log "[Start-Main] Start"

    $xmlStr = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <URI>\spyrun\$($app.userType)\$($app.scope)\$($app.watchMode)\$($app.cmdName)</URI>
  </RegistrationInfo>
  <Triggers>
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
    if (!$async) {
      $launch = [System.IO.Path]::Combine($app.spyrunDir, "launch.js")
      Start-Process -File "wscript.exe" -ArgumentList $launch, $app.cmdFile, $mode, $base, 1
      return $app.cnst.SUCCESS
    }
    log "[info] Currently ordering a double shot of espresso..."

    $sig = @"
[DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
public static extern void SetThreadExecutionState(uint esFlags);
"@

    $ES_CONTINUOUS = [uint32]"0x80000000"
    $ES_AWAYMODE_REQUIRED = [uint32]"0x00000040"
    $ES_DISPLAY_REQUIRED = [uint32]"0x00000002"
    $ES_SYSTEM_REQUIRED = [uint32]"0x00000001"

    $stes = Add-Type -MemberDefinition $sig -Name System -Namespace Win32 -PassThru

    [void]$stes::SetThreadExecutionState($ES_SYSTEM_REQUIRED -bor $ES_DISPLAY_REQUIRED -bor $ES_CONTINUOUS)

    Read-Host "[info] Enter if you want to exit ..."
    log "[info] No more espressos left behind the counter."

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
