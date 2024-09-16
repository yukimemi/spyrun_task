<#
  .SYNOPSIS
    common
  .DESCRIPTION
    共通処理
  .INPUTS
    - None
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change : 2024/09/16 19:25:06.
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

  $mutexName = "Global¥$($app.cmdName)_$($app.isLocal)"
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

  New-Item -Force -ItemType Directory $app.cmdLocalDir | Out-Null
  Copy-Item -Force $app.cmdFile $app.cmdLocalFile

  $registerXmlFile = [System.IO.Path]::Combine($app.spyrunBase, "task", "register", "$($app.cmdName).xml")
  $xmlStr | Set-Content -Encoding utf8 $registerXmlFile

  while ($true) {
    if (Test-Path $registerXmlFile) {
      log "Task is not registered ! so wait ..."
      Start-Sleep -Seconds 1
    } else {
      break
    }
  }
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

  $unRegisterXmlFile = [System.IO.Path]::Combine($app.spyrunBase, "task", "unregister", "$($app.cmdName).xml")
  $xmlStr | Set-Content -Encoding utf8 $unRegisterXmlFile

  while ($true) {
    if (Test-Path $unRegisterXmlFile) {
      log "Task is not unregistered ! so wait ..."
      Start-Sleep -Seconds 1
    } else {
      break
    }
  }
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
  .OUTPUTS
    - $app
#>
function Start-Init {

  [CmdletBinding()]
  [OutputType([object])]
  param([string]$version)
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
  $app.Add("initFile", [System.IO.Path]::Combine($app.spyrunDir, "init.ps1"))
  $app.Add("base", (. $app.initFile))
  $app.Add("cmdLocalFile", [System.IO.Path]::Combine($app.spyrunBase, $app.userType, "cmd", $app.scope, $app.watchMode, $app.cmdFileName))
  $app.Add("cmdLocalDir", [System.IO.Path]::GetDirectoryName($app.cmdLocalFile))
  if ($app.scope -eq "all") {
    $app.Add("cmdRemoteFile", [System.IO.Path]::Combine($app.base, $app.userType, "cmd", $app.scope, $app.watchMode, $app.cmdFileName))
    $app.Add("cmdRemoteDir", [System.IO.Path]::GetDirectoryName($app.cmdRemoteFile))
  } else {
    $app.Add("cmdRemoteFile", [System.IO.Path]::Combine($app.base, $app.userType, "cmd", $app.scope, $app.watchMode, $env:COMPUTERNAME, $app.cmdFileName))
    $app.Add("cmdRemoteDir", [System.IO.Path]::GetDirectoryName($app.cmdRemoteFile))
  }
  $app.Add("isLocal", ($app.cmdFile -eq $app.cmdLocalFile))
  $app.Add("dat", [System.IO.Path]::Combine($app.base, "dat"))
  $app.Add("clct", [System.IO.Path]::Combine($app.base, $app.userType, "clct"))
  $app.Add("resultDir", [System.IO.Path]::Combine($app.base, $app.userType, "result", $app.cmdName))
  $app.Add("resultPrefixFile", [System.IO.Path]::Combine($app.resultDir, "${env:COMPUTERNAME}_$($app.cmdName)"))
  $app.Add("logDir", [System.IO.Path]::Combine($app.base, $app.userType, "log", $app.scope, $app.watchMode, $app.cmdName, $env:COMPUTERNAME))
  $app.Add("logFile", [System.IO.Path]::Combine($app.logDir, "$($app.cmdName)_$($app.now).log"))
  $app.Add("logName", [System.IO.Path]::GetFileNameWithoutExtension($app.logFile))
  $app.Add("logFileName", [System.IO.Path]::GetFileName($app.logFile))
  New-Item -Force -ItemType Directory $app.logDir | Out-Null
  Start-Transcript $app.logFile

  log "[Start-Init] base = $($app.base)"
  log "[Start-Init] clct = $($app.clct)"
  log "[Start-Init] resultDir = $($app.resultDir)"

  # const value.
  $app.Add("cnst", @{
      SUCCESS = 0
      ERROR   = 1
    })

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

  if (!$app.isLocal) {
    Ensure-ScheduledTask $app $xmlStr | Out-Null
    exit $app.cnst.SUCCESS
  }

  if (!(Test-Path $app.cmdRemoteFile)) {
    log "$($app.cmdRemoteFile) is not found !" "Red"
    Remove-ScheduledTask $app $xmlStr
    exit $app.cnst.SUCCESS
  }

  log "[Start-MainBefore] End"
  return $app.cnst.SUCCESS
}





