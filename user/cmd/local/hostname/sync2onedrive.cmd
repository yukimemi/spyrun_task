@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{$_.readcount -gt 2})-join\"`n\");&$s" %*
@exit /b %errorlevel%

<#
  .SYNOPSIS
    sync2onedrive
  .DESCRIPTION
    OneDrive へ同期する
  .INPUTS
    - mode: "register": タスク登録, "main": 処理実行
    - async: "true": 非同期実行, "false": 同期実行
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change: 2024/11/12 00:58:37.
#>
param([string]$mode = "register", [bool]$async = $false)
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
$version = "20241112_005837"
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
    if ((Check-ModifiedCmd ([PSCustomObject]@{
            path = $app.cmdFile
            xml = $xmlStr
          })) -ne 0) {
      return $app.cnst.ERROR
    }

    # Execute main.
    $toml = @"
[vars]
version = '${version}'
sync_pattern = '\.ps1$|\.xml$|\.lua$|\.cmd$|\.exe$|\.ini$|\.vim$|\.ts$|\.json$|\.md$|\.py$'

[cfg]
stop_flg = '$($app.cmdFile.Replace("/", "\").Replace($app.baseLocal, $app.baseRemote))'

[log]
path = '$($app.logDir)\$($app.logName)_spyrun.log'
level = 'info'

[init]
cmd = 'powershell'
arg = ['-NoProfile', '-Command', '''& {
  Write-Host "{{ version }}"
}''']

[[spys]]
name = '$($app.cmdName)_dotfiles'
input = '${env:USERPROFILE}\.dotfiles'
output = '$($app.logDir)\dotfiles'
recursive = true
debounce = 10000
[[spys.patterns]]
pattern = '{{ sync_pattern }}'
cmd = 'powershell'
arg = ['-NoProfile', '-Command', '''& {
  `$src = '{{ event_path }}'
  `$dst = [System.IO.Path]::Combine('${env:OneDrive}\sync\${env:COMPUTERNAME}', '{{ event_path }}'.Replace(":", ""))
  New-Item -Force -ItemType Directory (Split-Path -Parent `$dst) | Out-Null
  Write-Host "`${src} -> `${dst}"
  Copy-Item -Force `$src `$dst
}''']

[[spys]]
name = '$($app.cmdName)_src'
input = '${env:USERPROFILE}\src'
output = '$($app.logDir)\src'
recursive = true
debounce = 10000
[[spys.patterns]]
pattern = '{{ sync_pattern }}'
cmd = 'powershell'
arg = ['-NoProfile', '-Command', '''& {
  `$src = '{{ event_path }}'
  `$dst = [System.IO.Path]::Combine('${env:OneDrive}\sync\${env:COMPUTERNAME}', '{{ event_path }}'.Replace(":", ""))
  New-Item -Force -ItemType Directory (Split-Path -Parent `$dst) | Out-Null
  Write-Host "`${src} -> `${dst}"
  Copy-Item -Force `$src `$dst
}''']

[[spys]]
name = '$($app.cmdName)_CraftFiler'
input = '${env:APPDATA}\CraftFiler'
output = '$($app.logDir)\CraftFiler'
recursive = true
debounce = 10000
[[spys.patterns]]
pattern = '{{ sync_pattern }}'
cmd = 'powershell'
arg = ['-NoProfile', '-Command', '''& {
  `$src = '{{ event_path }}'
  `$dst = [System.IO.Path]::Combine('${env:OneDrive}\sync\${env:COMPUTERNAME}', '{{ event_path }}'.Replace(":", ""))
  New-Item -Force -ItemType Directory (Split-Path -Parent `$dst) | Out-Null
  Write-Host "`${src} -> `${dst}"
  Copy-Item -Force `$src `$dst
}''']

[[spys]]
name = '$($app.cmdName)_CraftLaunch'
input = '${env:APPDATA}\CraftLaunch'
output = '$($app.logDir)\CraftLaunch'
recursive = true
debounce = 10000
[[spys.patterns]]
pattern = '{{ sync_pattern }}'
cmd = 'powershell'
arg = ['-NoProfile', '-Command', '''& {
  `$src = '{{ event_path }}'
  `$dst = [System.IO.Path]::Combine('${env:OneDrive}\sync\${env:COMPUTERNAME}', '{{ event_path }}'.Replace(":", ""))
  New-Item -Force -ItemType Directory (Split-Path -Parent `$dst) | Out-Null
  Write-Host "`${src} -> `${dst}"
  Copy-Item -Force `$src `$dst
}''']
"@

    $tomlPath = "${env:tmp}\$($app.cmdName).toml"
    $toml | Set-Content -Encoding utf8 $tomlPath

    $src = "${env:USERPROFILE}\.dotfiles"
    $dst = [System.IO.Path]::Combine("${env:ONEDRIVE}\sync\${env:COMPUTERNAME}", $src.Replace(":", ""))
    $result = Execute-Process ([PSCustomObject]@{ cmd = "robocopy.exe"; arg = "/mir `"${src}`" `"${dst}`" /xf *.log /xd .git"; })
    log "code: $($result.code)"
    log "stdout: $($result.stdout)"
    log "stderr: $($result.stderr)"

    $src = "${env:USERPROFILE}\src"
    $dst = [System.IO.Path]::Combine("${env:ONEDRIVE}\sync\${env:COMPUTERNAME}", $src.Replace(":", ""))
    $result = Execute-Process ([PSCustomObject]@{ cmd = "robocopy.exe"; arg = "/mir `"${src}`" `"${dst}`" /xf *.log /xd .git"; })
    log "code: $($result.code)"
    log "stdout: $($result.stdout)"
    log "stderr: $($result.stderr)"

    $src = "${env:APPDATA}\CraftFiler"
    $dst = [System.IO.Path]::Combine("${env:ONEDRIVE}\sync\${env:COMPUTERNAME}", $src.Replace(":", ""))
    $result = Execute-Process ([PSCustomObject]@{ cmd = "robocopy.exe"; arg = "/mir `"${src}`" `"${dst}`" /xf *.log /xd .git"; })
    log "code: $($result.code)"
    log "stdout: $($result.stdout)"
    log "stderr: $($result.stderr)"

    $src = "${env:APPDATA}\CraftLaunch"
    $dst = [System.IO.Path]::Combine("${env:ONEDRIVE}\sync\${env:COMPUTERNAME}", $src.Replace(":", ""))
    $result = Execute-Process ([PSCustomObject]@{ cmd = "robocopy.exe"; arg = "/mir `"${src}`" `"${dst}`" /xf *.log /xd .git"; })
    log "code: $($result.code)"
    log "stdout: $($result.stdout)"
    log "stderr: $($result.stderr)"

    Get-Date | Set-Content -Encoding utf8 "${env:tmp}\stop_$($app.cmdName)_force.flg"

    $result = Execute-Process ([PSCustomObject]@{ cmd = $app.spyrunFile; arg = "-c `"${tomlPath}`""; enc = "utf-8"; })
    log "code: $($result.code)"
    log "stdout: $($result.stdout)"
    log "stderr: $($result.stderr)"

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
