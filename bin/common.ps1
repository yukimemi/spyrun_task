<#
  .SYNOPSIS
    common
  .DESCRIPTION
    共通処理
  .INPUTS
    - None
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change : 2024/09/15 00:35:23.
#>
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
# Enable-RunspaceDebug -BreakAll

<#
  .SYNOPSIS
    log
  .DESCRIPTION
    log message
  .INPUTS
    - msg
    - color
  .OUTPUTS
    - None
#>
function log {

  [CmdletBinding()]
  [OutputType([void])]
  param([string]$msg, [string]$color)
  trap {
    Write-Host "[log] Error $_"
    throw $_
  }

  $now = Get-Date -f "yyyy/MM/dd HH:mm:ss.fff"
  if ($color) {
    Write-Host -ForegroundColor $color "${now} ${msg}"
  } else {
    Write-Host "${now} ${msg}"
  }
}

<#
  .SYNOPSIS
    New-Mutex
  .DESCRIPTION
    ミューテックスを作成して返却する
  .INPUTS
    - app
  .OUTPUTS
    - $mutex: 成功
    - $null: 失敗
#>
function New-Mutex {

  [CmdletBinding()]
  [OutputType([void])]
  param([PSCustomObject]$app)
  trap {
    log "[New-Mutex] Error $_" "Red"
    throw $_
  }

  $mutexName = "Global¥$($app.cmdName)_$($app.isLocal)_$($app.mode)"
  log "Create mutex name: [${mutexName}]"
  $mutex = New-Object System.Threading.Mutex($false, $mutexName)

  return $mutex
}

<#
  .SYNOPSIS
    Execute-Process
  .DESCRIPTION
    外部コマンドを実行する
  .INPUTS
    - cmd
    - arg
    - dir
    - timeout
    - enc
    - wait
  .OUTPUTS
    - output
#>
function Execute-Process {

  [CmdletBinding()]
  [OutputType([object])]
  param(
    [string]$cmd,
    [string]$arg,
    [string]$dir = ".",
    [int]$timeout = 0,
    [string]$enc,
    [bool]$wait = $true
  )
  trap {
    log "[Execute-Process] Error $_"
    throw $_
  }

  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.LoadUserProfile = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    if ($wait) {
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
    }
    $psi.FileName = $cmd
    $psi.Arguments = $arg
    $psi.WorkingDirectory = $dir
    if ($enc) {
      $psi.StandardOutputEncoding = [System.Text.Encoding]::GetEncoding($enc)
      $psi.StandardErrorEncoding = [System.Text.Encoding]::GetEncoding($enc)
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    # Runspace
    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $minPoolSize = $maxPoolSize = 10
    $runspacePool = [runspacefactory]::CreateRunspacePool($minPoolSize, $maxPoolSize, $sessionState, $Host)
    $runspacePool.ApartmentState = "STA"
    $runspacePool.Open()

    Write-Host "[Execute-Process] cmd: [${cmd}], arg: [${arg}]"
    [void]$process.Start()

    $script = {
      [CmdletBinding()]
      param([object]$std)
      while ($null -ne ($line = $std.ReadLine())) {
        Write-Host $line
        $line
      }
    }

    # For StdOut.
    $stdOutPs = [powershell]::Create().AddScript($script).AddArgument($process.StandardOutput)
    $stdOutPs.RunspacePool = $runspacePool
    $stdOutRun = New-Object PSObject -Property @{
      runspace   = $stdOutPs.BeginInvoke()
      powershell = $stdOutPs
    }
    # For StdErr.
    $stdErrPs = [powershell]::Create().AddScript($script).AddArgument($process.StandardError)
    $stdErrPs.RunspacePool = $runspacePool
    $stdErrRun = New-Object PSObject -Property @{
      runspace   = $stdErrPs.BeginInvoke()
      powershell = $stdErrPs
    }

    if ($wait) {
      if ($timeout) {
        $isTimeout = $false
        if (!$process.WaitForExit($timeout)) {
          $isTimeout = $true
          Write-Host "タイムアウトです。プロセスをKillします。"
          [void]$process.Kill()
        }
      }

      # Check exit.
      while ((@($stdOutRun.runspace, $stdErrRun.runspace) | Sort-Object IsCompleted -Unique).IsCompleted -ne $true) {
        Start-Sleep -Milliseconds 5
      }
      $process.WaitForExit()
    }

    $exitCode = $process.ExitCode
    $stdOut = $stdOutRun.powershell.EndInvoke($stdOutRun.runspace) -join "`r`n"
    $stdErr = $stdErrRun.powershell.EndInvoke($stdErrRun.runspace) -join "`r`n"

    return [PSCustomObject]@{
      cmd = $cmd
      arg = $arg
      code = $exitCode
      stdout = & {
        if ($stdOut) {
          $stdOut.TrimEnd()
        } else {
          $stdOut
        }
      }
      stderr = & {
        if ($stdErr) {
          $stdErr.TrimEnd()
        } else {
          $stdErr
        }
      }
      isTimeout = & {
        if ($isTimeout) {
          $isTimeout
        } else {
          $false
        }
      }
    }
  } finally {
    if ($process) {
      $process.Dispose()
    }
    if ($stdOutRun) {
      $stdOutRun.powershell.Dispose()
    }
    if ($stdErrRun) {
      $stdErrRun.powershell.Dispose()
    }
    if ($runspacePool) {
      $runspacePool.Dispose()
    }
  }
}

<#
  .SYNOPSIS
    Ensure-ScheduledTask
  .DESCRIPTION
    タスクスケジューラ未登録の場合は登録する
  .INPUTS
    - app
    - xml (タスクスケジューラ情報)
  .OUTPUTS
    - $true: 登録した場合
    - $false: 登録済の場合
#>
function Ensure-ScheduledTask {
  [CmdletBinding()]
  [OutputType([bool])]
  param([PSCustomObject]$app, [string]$xmlStr)

  trap {
    log "[Ensure-ScheduledTask] Error $_" "Red"
    throw $_
  }

  $xml = [xml]$xmlStr

  Get-ScheduledTask | Where-Object {
    $_.URI -eq $xml.Task.RegistrationInfo.URI
  } | Set-Variable exists

  if ($null -eq $exists -or !(Test-Path $app.registerFlg)) {
    New-Item -Force -ItemType Directory $app.cmdLocalDir | Out-Null
    Copy-Item -Force $app.cmdFile $app.cmdLocalFile
    $part = $xml.Task.RegistrationInfo.URI -split "\\"
    $taskpath = $part[0..($part.Length - 2)] -join "\"
    $taskname = $part[-1]
    log "${taskpath}\${taskname} is not registered, or $($app.registerFlg) is not found, so Register-ScheduledTask !"
    Register-ScheduledTask -Force -TaskPath $taskpath -TaskName $taskname -Xml $xmlStr | Out-Null
    New-Item -Force -ItemType Directory (Split-Path -Parent $app.registerFlg) | Out-Null
    New-Item -Force -ItemType File $app.registerFlg | Out-Null
    $app.cmdFile | Set-Content -Force -Encoding utf8 $app.registerFlg
    return $true
  }

  log "$($xml.Task.RegistrationInfo.URI) is already registered."
  $false
}

<#
  .SYNOPSIS
    Remove-ScheduledTask
  .DESCRIPTION
    タスクスケジューラを削除する
  .INPUTS
    - app
    - xml (タスクスケジューラ情報)
  .OUTPUTS
    - None
#>
function Remove-ScheduledTask {
  [CmdletBinding()]
  [OutputType([void])]
  param([PSCustomObject]$app, [string]$xmlStr)

  trap {
    log "[Remove-ScheduledTask] Error $_" "Red"
    throw $_
  }

  $xml = [xml]$xmlStr

  Get-ScheduledTask | Where-Object {
    $_.URI -eq $xml.Task.RegistrationInfo.URI
  } | Set-Variable exists

  if ($null -eq $exists) {
    log "$($xml.Task.RegistrationInfo.URI) is already removed !"
    return
  }

  $part = $xml.Task.RegistrationInfo.URI -split "\\"
  $taskpath = ($part[0..($part.Length - 2)] -join "\")
  $taskname = $part[-1]
  log "Unregister-ScheduledTask ${taskpath}\${taskname}"

  $removeTasks = {
    param([object]$folder)

    if (![string]::IsNullOrEmpty($taskname)) {
      $folder.GetTasks(1) | Where-Object {
        $folder.Path -eq $taskpath -and $_.Name -eq $taskname
      } | ForEach-Object {
        log "Remove taskpath: [${taskpath}], taskname: [${taskname}]"
        [void]$folder.DeleteTask($_.Name, $null)
      }
    }
    if ([string]::IsNullOrEmpty($taskname)) {
      $folder.GetFolders(1) | ForEach-Object {
        & $removeTasks $_
      }
      $folder.GetTasks(1) | ForEach-Object {
        [void]$folder.DeleteTask($_.Name, $null)
      }
      if ($folder.Path -eq $taskpath -and $taskpath -ne "\") {
        log "Remove taskpath folder: [$taskpath]"
        $sch = New-Object -ComObject Schedule.Service
        [void]$sch.connect()
        $rootFolder = $sch.GetFolder("\")
        [void]$rootFolder.DeleteFolder($taskpath, $null)
      }
    }
  }

  $sch = New-Object -ComObject Schedule.Service
  [void]$sch.connect()
  $folder = $sch.GetFolder($taskpath)
  & $removeTasks $folder
}

<#
  .SYNOPSIS
    Get-Env
  .DESCRIPTION
    環境変数ファイルの読み込み
  .INPUTS
    - path: 環境変数file (default: .env)
  .OUTPUTS
    - None
#>
function Get-Env {
  [CmdletBinding()]
  [OutputType([string])]
  param([string]$path)
  trap {
    log "[Get-Env] Error $_" "Red"
    throw $_
  }

  if (Test-Path $path) {
    . $path
    return
  }

  throw "${path} is not found !"
}

<#
  .SYNOPSIS
    Encrypt-Plain
  .DESCRIPTION
    平文暗号化
  .INPUTS
    - text: 暗号化対象文字列
  .OUTPUTS
    - 暗号化文字列
#>
function Encrypt-Plain {
  [CmdletBinding()]
  [OutputType([string])]
  param([object]$text)
  trap {
    log "[Encrypt-Plain] Error $_" "Red"
    throw $_
  }

  $key = [byte[]]@(0x63, 0x72, 0x79, 0x70, 0x74, 0x6f, 0x65, 0x6e, 0x63, 0x64, 0x65, 0x63)
  $key += $key

  $secure = ConvertTo-SecureString -String $text -AsPlainText -Force
  return ConvertFrom-SecureString -SecureString $secure -Key $key
}

<#
  .SYNOPSIS
    Decrypt-Secure
  .DESCRIPTION
    復号化
  .INPUTS
    - secure: 暗号文字列
  .OUTPUTS
    - 復号文字列
#>
function Decrypt-Secure {
  [CmdletBinding()]
  [OutputType([string])]
  param([object]$secure)
  trap {
    log "[Decrypt-Secure] Error $_" "Red"
    throw $_
  }

  log "[Decrypt-Secure] decrypt: ${secure}"

  $key = [byte[]]@(0x63, 0x72, 0x79, 0x70, 0x74, 0x6f, 0x65, 0x6e, 0x63, 0x64, 0x65, 0x63)
  $key += $key

  $sec = $secure | ConvertTo-SecureString -Key $key

  $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
}

<#
  .SYNOPSIS
    Convert-ArrayPropertyToString
  .DESCRIPTION
    オブジェクトのプロトタイプで配列型のものを , で join して返す
  .INPUTS
    - $PSObject
  .OUTPUTS
    - $PSObject
#>
function Convert-ArrayPropertyToString {
  [CmdletBinding()]
  [OutputType([PSObject])]
  param(
    [Parameter(ValueFromPipeline=$true)]
    [psobject]$InputObject
  )

  process {
    $m = $_
    $m.PSObject.Properties.Name | ForEach-Object {
      if (($null -ne $m.$_) -and ($m.$_.GetType().Name -match ".*\[\]")) {
        $m.$_ = $m.$_ -join ","
      }
    }
    $m
  }
}

<#
  .SYNOPSIS
    Test-PathRemoteCmd
  .DESCRIPTION
    リモートファイルが存在するか
    リモートファイルとローカルファイルの差分確認
  .INPUTS
    - app
  .OUTPUTS
    - $true: 存在する / 一致
    - $false: 存在しない / 一致しない
#>
function Test-PathRemoteCmd {
  [CmdletBinding()]
  [OutputType([bool])]
  param([PSCustomObject]$app)

  trap {
    log "[Test-PathRemoteCmd] Error $_" "Red"
    throw $_
  }

  # リモートファイルの場合は存在するので true
  if (!$app.isLocal) {
    return $true
  }

  # タスク登録フラグが存在しない場合かつ、ローカル実行の場合は想定外
  if (!(Test-Path $app.registerFlg)) {
    throw "unreachable !!"
  }

  if (Test-Path $app.cmdRemoteFile) {
    log "$($app.cmdRemoteFile) is found !"
    # ハッシュチェック
    $localHash = (Get-FileHash $app.cmdLocalFile).Hash
    $remoteHash = (Get-FileHash $app.cmdRemoteFile).Hash
    if ($localHash -ne $remoteHash) {
      log "Mismatch hash ! local: [${localHash}], remote: [${remoteHash}]"
      return $false
    }
    return $true
  }

  log "$($app.cmdRemoteFile) is not found !"
  return $false
}

<#
  .SYNOPSIS
    Wait-Spyrun
  .DESCRIPTION
    spyrun.exe のプロセス起動待ち
  .INPUTS
    - userType
  .OUTPUTS
    - None
#>
function Wait-Spyrun {
  [CmdletBinding()]
  [OutputType([void])]
  param([string]$userType)

  trap {
    log "[Wait-Spyrun] Error $_" "Red"
    throw $_
  }

  while ($true) {
    Get-CimInstance -ClassName Win32_Process | Where-Object {
      $_.Name -eq "spyrun.exe" -and $_.CommandLine -match $userType
    } | Set-Variable spyrun
    if ($null -ne $spyrun) {
      log "Process spyrun.exe is Found !"
      return
    } else {
      log "Process spyrun.exe is not found ..."
      Start-Sleep -Seconds 1
    }
  }
}

<#
  .SYNOPSIS
    Start-Init
  .DESCRIPTION
    Init 処理
  .INPUTS
    - version
    - mode
  .OUTPUTS
    - $app
#>
function Start-Init {

  [CmdletBinding()]
  [OutputType([object])]
  param([string]$version, [string]$mode, [string]$base)
  trap {
    log "[Start-Init] Error $_" "Red"
    throw $_
  }

  log "[Start-Init] Start"

  $app = @{}

  $cmdFullPath = & {
    if ($env:__SCRIPTPATH) {
      return [System.IO.Path]::GetFullPath($env:__SCRIPTPATH)
    } else {
      return [System.IO.Path]::GetFullPath($script:MyInvocation.MyCommand.Path)
    }
  }

  $app.Add("version", $version)
  $app.Add("mode", $mode)
  $app.Add("lock", $false)

  $app.Add("cmdFile", $cmdFullPath)
  $app.Add("cmdDir", [System.IO.Path]::GetDirectoryName($app.cmdFile))
  $app.Add("cmdName", [System.IO.Path]::GetFileNameWithoutExtension($app.cmdFile))
  $app.Add("cmdFileName", [System.IO.Path]::GetFileName($app.cmdFile))
  $app.Add("pwd", [System.IO.Path]::GetFullPath((Get-Location).Path))
  $app.Add("now", (Get-Date -Format "yyyyMMddTHHmmssfffffff"))

  $sp = $app.cmdFile -split "\\" | Where-Object { $_ -ne $env:COMPUTERNAME -and $_ -ne "cmd" }
  $app.Add("userType", $sp[-4])
  $app.Add("scope", $sp[-3])
  $app.Add("watchMode", $sp[-2])

  $app.Add("spyrunFile", "C:\ProgramData\spyrun\bin\spyrun.exe")
  $app.Add("spyrunDir", [System.IO.Path]::GetDirectoryName($app.spyrunFile))
  $app.Add("spyrunName", [System.IO.Path]::GetFileNameWithoutExtension($app.spyrunFile))
  $app.Add("spyrunFileName", [System.IO.Path]::GetFileName($app.spyrunFile))
  $app.Add("spyrunBase", [System.IO.Path]::GetDirectoryName($app.spyrunDir))
  $app.Add("registerFlg", [System.IO.Path]::Combine($app.spyrunBase, $app.userType, "flg", $app.scope, $app.watchMode, "$($app.cmdName)_${version}.flg"))
  $app.Add("cmdLocalFile", [System.IO.Path]::Combine($app.spyrunBase, $app.userType, "cmd", $app.scope, $app.watchMode, $app.cmdFileName))
  $app.Add("cmdLocalDir", [System.IO.Path]::GetDirectoryName($app.cmdLocalFile))
  $app.Add("kickFile",  [System.IO.Path]::Combine($app.spyrunBase, $app.userType, "kick", $app.scope, $app.watchMode, "$($app.cmdName).flg"))
  $app.Add("kickedFile",  [System.IO.Path]::Combine($app.spyrunBase, $app.userType, "kicked", $app.scope, $app.watchMode, "$($app.cmdName).flg"))
  $app.Add("isLocal", ($app.cmdFile -eq $app.cmdLocalFile))
  $app.Add("stopFile", [System.IO.Path]::Combine($app.spyrunBase, $app.userType, "stop.flg"))
  $app.Add("stopForceFile", [System.IO.Path]::Combine($app.spyrunBase, $app.userType, "stop_force.flg"))

  # log
  $app.Add("logDir", [System.IO.Path]::Combine($app.spyrunBase, $app.userType, "log"))
  $app.Add("logFile", [System.IO.Path]::Combine($app.logDir, "$($app.cmdName)_$($app.now).log"))
  $app.Add("logName", [System.IO.Path]::GetFileNameWithoutExtension($app.logFile))
  $app.Add("logFileName", [System.IO.Path]::GetFileName($app.logFile))
  New-Item -Force -ItemType Directory $app.logDir | Out-Null

  Start-Transcript $app.logFile

  # remote
  if (Test-Path $app.registerFlg) {
    $app.Add("cmdRemoteFile", (Get-Content -First 1 -Encoding utf8 $app.registerFlg))
    $app.Add("cmdRemoteDir", [System.IO.Path]::GetDirectoryName($app.cmdRemoteFile))
  }
  if ($base) {
    $app.Add("base", $base)
    $app.Add("dat", [System.IO.Path]::Combine($app.base, "dat"))
    $app.Add("clct", [System.IO.Path]::Combine($app.base, "clct"))
    $app.Add("resultDir", [System.IO.Path]::Combine($app.clct, $app.cmdName, "result"))
    $app.Add("resultPrefixFile", [System.IO.Path]::Combine($app.resultDir, "${env:COMPUTERNAME}_$($app.cmdName)"))
  }

  # const value.
  $app.Add("cnst", @{
      SUCCESS = 0
      ERROR   = 1
    })

  # Update kickedFile.
  if ($app.mode -eq "main") {
    New-Item -Force -ItemType Directory (Split-Path -Parent $app.kickedFile) | Out-Null
    Get-Date -f "yyyyMMddHHmmssfff" | Set-Content -Encoding utf8 $app.kickedFile
  }

  # mutex check
  $app.Add("mutex", (New-Mutex $app))
  if (!$app.mutex.WaitOne(0, $false)) {
    log "2重起動です！終了します。" "Yellow"
    exit $app.cnst.SUCCESS
  }
  $app.lock = $true

  log "[Start-Init] End"

  return $app
}

function Start-MainBefore {

  [CmdletBinding()]
  [OutputType([int])]
  param([PSCustomObject]$app, [string]$xmlStr)
  trap {
    log "[Start-MainBefore] Error $_" "Red"
    throw $_
  }

  log "[Start-MainBefore] Start"

  if (!$app.isLocal -and $app.mode -eq "register") {
    Ensure-ScheduledTask $app $xmlStr | Out-Null
    exit $app.cnst.SUCCESS
  }

  if (![string]::IsNullorEmpty($app.cmdRemoteFile) -and !(Test-Path $app.cmdRemoteFile)) {
    Remove-ScheduledTask $app $xmlStr
    exit $app.cnst.SUCCESS
  }

  if ($app.mode -ne "main") {
    log "Wait spyrun.exe ..."
    Wait-Spyrun $app.userType
    log "mode: [$($app.mode)], so create kick file."
    $now = Get-Date -f "yyyyMMddHHmmssfff"
    New-Item -Force -ItemType File $app.kickFile | Out-Null
    Start-Sleep -Seconds 10
    # Check kickedFile.
    if (!(Test-Path $app.kickedFile)) {
      return Start-MainBefore $app $xmlStr
    }
    $kickedTime = (Get-Content -Encoding utf8 $app.kickedFile).Trim()
    if ($now -gt $kickedTime) {
      return Start-MainBefore $app $xmlStr
    }
    exit $app.cnst.SUCCESS
  }

  log "[Start-MainBefore] End"
  return $app.cnst.SUCCESS

}





