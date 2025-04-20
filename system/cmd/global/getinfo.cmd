@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{$_.readcount -gt 2})-join\"`n\");&$s" %*
@exit /b %errorlevel%

<#
  .SYNOPSIS
    getinfo
  .DESCRIPTION
    情報取得を行う
  .INPUTS
    - mode: "register": タスク登録, "main": 処理実行
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change: 2025/04/14 00:08:27.
#>
param([string]$mode = "register")
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
$version = "20250414_000827"
# Enable-RunspaceDebug -BreakAll

<#
  .SYNOPSIS
    Get-InfoByPsCommand
  .DESCRIPTION
    PowerShell コマンドを実行して情報を採取する
  .INPUTS
    - command: 実行コマンド
    - collect: 収集先パス
    - csvName: 保存csv名
  .OUTPUTS
    - None
#>
function Get-InfoByPsCommand {
  [CmdletBinding()]
  [OutputType([void])]
  param([PSCustomObject]$arg)

  trap {
    log "[Get-InfoByPsCommand] Error $_" "Red"
    throw $_
  }
  log "[Get-InfoByPsCommand] arg: $([PSCustomObject]$arg | ConvertTo-Json)"

  $s = Get-Date
  log "Execute [$($arg.command)] start ..."
  $today = Get-Date -f "yyyyMMdd"
  $csvName = & {
    if ([string]::IsNullOrEmpty($arg.csvName)) {
      return $arg.command
    }
    return $arg.csvName
  }
  log "csvName: [${csvName}]"
  $collectLatest = [System.IO.Path]::Combine($arg.collect, $csvName, "latest", "${env:COMPUTERNAME}_${csvName}.csv")
  $collectToday = [System.IO.Path]::Combine($arg.collect, $csvName, $today, "${env:COMPUTERNAME}_${csvName}_${today}.csv")
  New-Item -Force -ItemType Directory (Split-Path -Parent $collectLatest) | Out-Null
  New-Item -Force -ItemType Directory (Split-Path -Parent $collectToday) | Out-Null
  Invoke-Expression $arg.command | Select-Object * | Convert-ArrayPropertyToString | Export-Csv -NoTypeInformation -Encoding utf8 $collectLatest
  Copy-Item -Force $collectLatest $collectToday
  $e = Get-Date
  $span = $e - $s
  log ("Execute [$($arg.command)] end ! Elaps: {0} {1:00}:{2:00}:{3:00}.{4:000}" -f $span.Days, $span.Hours, $span.Minutes, $span.Seconds, $span.Milliseconds)
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
    $collect = [System.IO.Path]::Combine($app.clctLocal, $app.cmdName)
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-ComputerInfo"
        collect = $collect
      })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-NetIPAddress"
        collect = $collect
      })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-NetIPConfiguration"
        collect = $collect
      })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-NetRoute"
        collect = $collect
      })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-DnsClientServerAddress"
        collect = $collect
      })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-HotFix"
        collect = $collect
      })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-CimInstance Win32_BIOS"
        collect = $collect
      })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-CimInstance Win32_Processor"
        collect = $collect
      })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-CimInstance Win32_PhysicalMemory"
        collect = $collect
      })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-CimInstance Win32_Process"
        collect = $collect
      })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-CimInstance Win32_DiskDrive"
        collect = $collect
      })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-CimInstance Win32_LogicalDisk"
        collect = $collect
      })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-CimInstance Win32_OperatingSystem"
        collect = $collect
      })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-CimInstance Win32_ComputerSystem"
        collect = $collect
      })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-CimInstance Win32_NetworkAdapter"
        collect = $collect
      })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-CimInstance Win32_Service"
        collect = $collect
      })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-CimInstance Win32_Product"
        collect = $collect
      })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-CimInstance Win32_ComputerSystemProduct"
        collect = $collect
      })
    # Get-InfoByPsCommand ([PSCustomObject]@{
    #     command = "Get-CimInstance Win32_UserAccount"
    #     collect = $collect
    #   })
    Get-InfoByPsCommand ([PSCustomObject]@{
        command = "Get-WinEvent -FilterXml @'
<QueryList>
  <Query Id='0' Path='System'>
    <Select Path='System'>*[System[Provider[@Name='Microsoft-Windows-Kernel-General'] and (EventID=12 or EventID=13)]]</Select>
    <Select Path='System'>*[System[Provider[@Name='Microsoft-Windows-Winlogon'] and (EventID=7001 or EventID=7002)]]</Select>
  </Query>
</QueryList>
'@ | Select-Object RecordId, TimeCreated, Id, ProviderName, MachineName, UserId, Message"
        collect = $collect
        csvName =  "sign"
      })

    Get-ChildItem -Force -Recurse -File $app.clctLocal | ForEach-Object {
      $src = $_.FullName
      $dst = $src.Replace($app.clctLocal, $app.clctRemote)
      Sync-FS ([PSCustomObject]@{
          src = $src
          dst = $dst
          type = "file"
          option = "-Force"
          remove = $true
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
