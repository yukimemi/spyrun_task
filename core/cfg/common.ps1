<#
  .SYNOPSIS
    common
  .DESCRIPTION
    共通処理
  .INPUTS
    - None
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change: 2025/05/05 08:36:43.
#>
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
# Enable-RunspaceDebug -BreakAll

$app = @{}
# const value.
$app.Add("cnst", @{
    SUCCESS = 0
    WARN = 1
    ERROR = 2
  })

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
    - name: ミューテックス名称を指定する場合は設定する
  .OUTPUTS
    - $mutex: 成功
    - $null: 失敗
#>
function New-Mutex {

  [CmdletBinding()]
  [OutputType([object])]
  param([PSCustomObject]$app, [string]$name = "")
  trap {
    log "[New-Mutex] Error $_" "Red"
    throw $_
  }

  $mutexName = "Global¥${name}"
  if ([string]::IsNullOrEmpty($name)) {
    $mutexName = "Global¥$($app.cmdName)_$($app.mode)"
  }
  log "[New-Mutex] Create mutex name: [${mutexName}]"
  $mutex = New-Object System.Threading.Mutex($false, $mutexName)

  return $mutex
}

<#
  .SYNOPSIS
    Execute-Process
  .DESCRIPTION
    外部コマンドを実行する
  .EXAMPLE
    Execute-Process [PSCustomObject]@{ cmd = "cmd"; arg = "/c echo hoge" }

    cmdArg:
      [PSCustomObject]@{
        cmd: string,
        arg: string,
        dir: string,
        timeout: int,
        enc: string,
        wait: bool
      }
#>
function Execute-Process {

  [CmdletBinding()]
  [OutputType([object])]
  param([PSCustomObject]$cmdArg)

  try {
    log "[Execute-Process] cmdArg: $([PSCustomObject]$cmdArg | ConvertTo-Json)"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.LoadUserProfile = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $wait = & {
      if ($null -ne $cmdArg.wait) {
        $cmdArg.wait
      } else {
        $true
      }
    }
    if ($wait) {
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
    }
    $psi.FileName = $cmdArg.cmd
    $psi.Arguments = $cmdArg.arg
    $dir = & {
      if ($cmdArg.dir) {
        $cmdArg.dir
      } else {
        "."
      }
    }
    $psi.WorkingDirectory = $dir
    $enc = & {
      if ($cmdArg.enc) {
        $cmdArg.enc
      } else {
        ""
      }
    }
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

    $timeout = & {
      if ($cmdArg.timeout) {
        $cmdArg.timeout
      } else {
        0
      }
    }
    log "[Execute-Process] cmd: [$($cmdArg.cmd)], arg: [$($cmdArg.arg)], dir: [${dir}], timeout: [${timeout}], wait: [${wait}], enc: [${enc}]"
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
          log "[Execute-Process] タイムアウトです。プロセスをKillします。"
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
      cmd = $cmdArg.cmd
      arg = $cmdArg.arg
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
  } catch {
    log "[Execute-Process] Error $_"
    throw $_
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
    Check-FileHash
  .DESCRIPTION
    ハッシュを比較する
  .INPUTS
    - src
    - dst
  .OUTPUTS
    - bool
#>
function Check-FileHash {
  [CmdletBinding()]
  [OutputType([bool])]
  param([string]$src, [string]$dst)

  if (!(Test-Path $src)) {
    return $false
  }
  if (!(Test-Path $dst)) {
    return $false
  }

  $srcHash = (Get-FileHash $src).Hash
  $dstHash = (Get-FileHash $dst).Hash

  return $srcHash -eq $dstHash
}

<#
  .SYNOPSIS
    Copy-File
  .DESCRIPTION
    ハッシュが違う場合はファイルをコピーする
  .INPUTS
    - src
    - dst
  .OUTPUTS
    - None
#>
function Copy-File {
  [CmdletBinding()]
  [OutputType([void])]
  param([string]$src, [string]$dst)

  if (!(Check-FileHash $src $dst)) {
    log "[Copy-File] Copy-File: $src -> $dst"
    New-Item -Force -ItemType Directory ([System.IO.Path]::GetDirectoryName($dst)) | Out-Null
    Copy-Item -Force $src $dst
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
  $registerXmlFile = [System.IO.Path]::Combine($app.spyrunBase, "task", "register", ($xml.Task.RegistrationInfo.URI -replace "^\\spyrun\\", "") + ".xml")

  log "[Ensure-ScheduledTask] xmlStr: ${xmlStr}"
  New-Item -Force -ItemType Directory (Split-Path -Parent $registerXmlFile) | Out-Null
  $xmlStr | Set-Content -Encoding utf8 $registerXmlFile

  $limitTime = (Get-Date).AddMinutes(10)

  while ($true) {
    if ((Get-Date) -gt $limitTime) {
      throw "Time over !!!"
    }
    if (Test-Path $registerXmlFile) {
      log "[Ensure-ScheduledTask] Task is not registered ! so wait ... [${registerXmlFile}]"
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
    - arg: 削除タスク情報 (PSCustomObject)
      xml: 削除タスクxmlstr
      async: $true: 非同期 / $false: 同期 (Default: $false)
  .OUTPUTS
    - result: 0 (成功) / not 0 (失敗)
#>
function Remove-ScheduledTask {
  [CmdletBinding()]
  [OutputType([int])]
  param([PSCustomObject]$arg)

  trap {
    log "[Remove-ScheduledTask] Error $_" "Red"
    throw $_
  }

  log "[Remove-ScheduledTask] arg: $([PSCustomObject]$arg | ConvertTo-Json)"

  $xml = [xml]$arg.xml
  $unRegisterXmlFile = [System.IO.Path]::Combine($app.spyrunBase, "task", "unregister", ($xml.Task.RegistrationInfo.URI -replace "^\\spyrun\\", "") + ".xml")

  log "[Remove-ScheduledTask] Remove task xml: $($arg.xml)"
  New-Item -Force -ItemType Directory (Split-Path -Parent $unRegisterXmlFile) | Out-Null
  $arg.xml | Set-Content -Encoding utf8 $unRegisterXmlFile

  if ($arg.async) {
    return 0
  }

  $limitTime = (Get-Date).AddMinutes(10)

  while ($true) {
    if ((Get-Date) -gt $limitTime) {
      log "[Remove-ScheduledTask] Time over !!!" "Red"
      return $app.cnst.ERROR
    }
    if (Test-Path $unRegisterXmlFile) {
      log "[Remove-ScheduledTask] Task is not unregistered ! so wait ... [${unRegisterXmlFile}]"
      Start-Sleep -Seconds 1
    } else {
      break
    }
  }
  return $app.cnst.SUCCESS
}

<#
  .SYNOPSIS
    Sync-FS
  .DESCRIPTION
    spyrun の sync タスクを利用してファイルを転送する
  .INPUTS
    - arg: 転送情報 (PSCustomObject)
      src: 転送元
      dst: 転送先
      option: コマンドオプション
      type: "file" or "directory"
      async: $true: 非同期 / $false: 同期 (Default: $false)
      fileName: sync 実行ファイル名 (Default: $($app.cmdName)_$((New-Guid).Guid).json)
      remove: 同期完了後、 src を削除するかどうか。削除は spyrun.exe 側で実施される。
              $true: 削除 / $false: 削除しない (Defalut: $false)
      usertype: "core", "system", "user" (Default: "core")
      testdst: dst が存在するかチェックする
  .OUTPUTS
    - result: 0 (成功) / not 0 (失敗)
#>
function Sync-FS {
  [CmdletBinding()]
  [OutputType([int])]
  param([PSCustomObject]$arg)

  trap {
    log "[Sync-FS] Error $_" "Red"
    throw $_
  }

  log "[Sync-FS] arg: $([PSCustomObject]$arg | ConvertTo-Json)"
  $arg | Add-Member -MemberType NoteProperty -Name time -Value ([PSCustomObject]@{ in = Get-Date -Format "yyyy/MM/dd HH:mm:ss.fff"; out = "" })
  $result = $app.cnst.ERROR

  $ifBase = & {
    if (($arg.usertype -eq "system") -or ($arg.usertype -eq "user")) {
      return [System.IO.Path]::Combine($app.spyrunBase, $app.userType)
    }
    return $app.spyrunBase
  }

  $syncFile = [System.IO.Path]::Combine($ifBase, "if", "sync", "$($app.cmdName)_$((New-Guid).Guid).json")
  if (![string]::IsNullOrEmpty($arg.fileName)) {
    $syncFile = [System.IO.Path]::Combine($ifBase, "if", "sync", "$($arg.fileName).json")
  }
  $syncFileResult = $syncFile.Replace("${ifBase}\if\sync", "${ifBase}\if\sync_result")
  $arg | ConvertTo-Json | Set-Content -Encoding utf8 $syncFile

  if ($arg.async) {
    $result = $app.cnst.SUCCESS
    return $result
  }

  $limitTime = (Get-Date).AddMinutes(10)

  while ($true) {
    if ((Get-Date) -gt $limitTime) {
      log "[Sync-FS] Time over !!!" "Red"
      $result = $app.cnst.ERROR
      return $result
    }
    if (Test-Path $syncFile) {
      log "[Sync-FS] Sync is not ended ! so wait ... [${syncFile}]"
      Start-Sleep -Seconds 1
    } else {
      $result = (Get-Content -Encoding utf8 $syncFileResult | ConvertFrom-Json).result
      break
    }
  }
  return $result
}

<#
  .SYNOPSIS
    Remove-FS
  .DESCRIPTION
    spyrun の remove タスクを利用してファイルを削除する
  .INPUTS
    - arg: 削除情報 (PSCustomObject)
      path: 削除パス
      async: $true: 非同期 / $false: 同期 (Default: $false)
      fileName: exec 実行ファイル名 (Default: $($app.cmdName)_$((New-Guid).Guid).json
      usertype: "core", "system", "user" (Default: "core")
  .OUTPUTS
    - result: 0 (成功) / not 0 (失敗)
#>
function Remove-FS {
  [CmdletBinding()]
  [OutputType([int])]
  param([PSCustomObject]$arg)

  trap {
    log "[Remove-FS] Error $_" "Red"
    throw $_
  }

  log "[Remove-FS] arg: $([PSCustomObject]$arg | ConvertTo-Json)"
  $arg | Add-Member -MemberType NoteProperty -Name time -Value ([PSCustomObject]@{ in = Get-Date -Format "yyyy/MM/dd HH:mm:ss.fff"; out = "" })
  $result = $app.cnst.ERROR

  $ifBase = & {
    if (($arg.usertype -eq "system") -or ($arg.usertype -eq "user")) {
      return [System.IO.Path]::Combine($app.spyrunBase, $app.userType)
    }
    return $app.spyrunBase
  }

  $removeFile = [System.IO.Path]::Combine($ifBase, "if", "remove", "$($app.cmdName)_$((New-Guid).Guid).json")
  if (![string]::IsNullOrEmpty($arg.fileName)) {
    $removeFile = [System.IO.Path]::Combine($ifBase, "if", "remove", "$($arg.fileName).json")
  }
  $removeFileResult = $removeFile.Replace("${ifBase}\if\remove", "${ifBase}\if\remove_result")
  $arg | ConvertTo-Json | Set-Content -Encoding utf8 $removeFile

  if ($arg.async) {
    $result = $app.cnst.SUCCESS
    return $result
  }

  $limitTime = (Get-Date).AddMinutes(10)

  while ($true) {
    if ((Get-Date) -gt $limitTime) {
      log "[Remove-FS] Time over !!!" "Red"
      $result = $app.cnst.ERROR
      return $result
    }
    if (Test-Path $removeFile) {
      log "[Remove-FS] Remove is not ended ! so wait ... [${removeFile}]"
      Start-Sleep -Seconds 1
    } else {
      $result = (Get-Content -Encoding utf8 $removeFileResult | ConvertFrom-Json).result
      break
    }
  }
  return $result
}

<#
  .SYNOPSIS
    Exec-FS
  .DESCRIPTION
    spyrun の exec タスクを利用してファイルを実行する
  .INPUTS
    - arg: 実行情報 (PSCustomObject)
      cmd: 実行ファイルパス
      arg: 引数
      dir: 実行ディレクトリ
      async: $true: 非同期 / $false: 同期 (Default: $false)
      fileName: exec 実行ファイル名 (Default: $($app.cmdName)_$((New-Guid).Guid).json
      usertype: "core", "system", "user" (Default: "core")
  .OUTPUTS
    - result: 0 (成功) / not 0 (失敗)
#>
function Exec-FS {
  [CmdletBinding()]
  [OutputType([int])]
  param([PSCustomObject]$arg)

  trap {
    log "[Exec-FS] Error $_" "Red"
    throw $_
  }

  log "[Exec-FS] arg: $([PSCustomObject]$arg | ConvertTo-Json)"
  $arg | Add-Member -MemberType NoteProperty -Name time -Value ([PSCustomObject]@{ in = Get-Date -Format "yyyy/MM/dd HH:mm:ss.fff"; out = "" })
  $result = $app.cnst.ERROR

  $ifBase = & {
    if (($arg.usertype -eq "system") -or ($arg.usertype -eq "user")) {
      return [System.IO.Path]::Combine($app.spyrunBase, $app.userType)
    }
    return $app.spyrunBase
  }

  $execFile = [System.IO.Path]::Combine($ifBase, "if", "exec", "$($app.cmdName)_$((New-Guid).Guid).json")
  if (![string]::IsNullOrEmpty($arg.fileName)) {
    $execFile = [System.IO.Path]::Combine($ifBase, "if", "exec", "$($arg.fileName).json")
  }
  $execFileResult = $execFile.Replace("${ifBase}\if\exec", "${ifBase}\if\exec_result")
  $arg | ConvertTo-Json | Set-Content -Encoding utf8 $execFile

  if ($arg.async) {
    $result = $app.cnst.SUCCESS
    return $result
  }

  $limitTime = (Get-Date).AddMinutes(10)

  while ($true) {
    if ((Get-Date) -gt $limitTime) {
      log "[Exec-FS] Time over !!!" "Red"
      $result = $app.cnst.ERROR
      return $result
    }
    if (Test-Path $execFile) {
      log "[Exec-FS] Exec is not ended ! so wait ... [${execFile}]"
      Start-Sleep -Seconds 1
    } else {
      $result = (Get-Content -Encoding utf8 $execFileResult | ConvertFrom-Json).result
      break
    }
  }
  return $result
}

<#
  .SYNOPSIS
    Invoke-Sync
  .DESCRIPTION
    sync を実行する
  .INPUTS
    - arg: 引数情報 (PSCustomObject)
      path: 情報ファイルパス
  .OUTPUTS
    - result: 0 (成功) / not 0 (失敗)
#>
function Invoke-Sync {
  [CmdletBinding()]
  [OutputType([int])]
  param([PSCustomObject]$arg)

  log "[Invoke-Sync] arg: $([PSCustomObject]$arg | ConvertTo-Json)"
  $result = $app.cnst.ERROR
  $mutex = New-Mutex $app $arg.path
  if (!$mutex.WaitOne(0, $false)) {
    log "[Invoke-Sync] 2重起動です！終了します。" "Yellow"
    return $app.cnst.WARN
  }
  if (!(Test-Path $arg.path)) {
    log "[Invoke-Sync] $($arg.path) は存在しません"
    return $app.cnst.WARN
  }
  try {
    $json = Get-Content -Encoding utf8 $arg.path
    log "[Invoke-Sync] json: ${json}"
    $cfg = $json | ConvertFrom-Json
    log "[Invoke-Sync] src: [$($cfg.src)]"
    log "[Invoke-Sync] dst: [$($cfg.dst)]"
    log "[Invoke-Sync] type: [$($cfg.type)]"
    log "[Invoke-Sync] option: [$($cfg.option)]"
    log "[Invoke-Sync] remove: [$($cfg.remove)]"
    log "[Invoke-Sync] usertype: [$($cfg.usertype)]"
    log "[Invoke-Sync] testdst: [$($cfg.testdst)]"
    if (!(Test-Path $cfg.src)) {
      throw "[Invoke-Sync] $($cfg.src) is not found !"
    }
    if ($cfg.testdst) {
      if (!(Test-Path $cfg.dst)) {
        log "[Invoke-Sync] $($cfg.dst) は存在しません"
        $result = $app.cnst.WARN
        return $result
      }
    }
    if ($cfg.type -eq "directory") {
      $robocopyResult = Execute-Process ([PSCustomObject]@{ cmd = "robocopy.exe"; arg = "`"$($cfg.src)`" `"$($cfg.dst)`" $($cfg.option)"; })
      log "[Invoke-Sync] code: [$($robocopyResult.code)]"
      log "[Invoke-Sync] stdout: [$($robocopyResult.stdout)]"
      log "[Invoke-Sync] stderr: [$($robocopyResult.stderr)]"
      if ($robocopyResult.code -ge 8) {
        throw "[Invoke-Sync] robocopy error !"
      }
    } elseif ($cfg.type -eq "file") {
      New-Item -Force -ItemType Directory (Split-Path -Parent $cfg.dst) | Out-Null
      Invoke-Expression "Copy-Item $($cfg.option) `"$($cfg.src)`" `"$($cfg.dst)`""
    } else {
      throw "[Invoke-Sync] Error `type` must be `file` or `directory` (type: $($cfg.type))"
    }
    Get-ChildItem -Force -Recurse -File $cfg.dst | ForEach-Object {
      Unblock-File $_.FullName
    }
    if ($cfg.remove) {
      log "[Invoke-Sync] Remove flg on, so remove [$($cfg.src)] !"
      Remove-Item -Force -Recurse $cfg.src
    }
    Remove-Item -Force $arg.path
    $result = $app.cnst.SUCCESS
  } catch {
    if (($null -eq $result) -or ($result -eq $app.cnst.SUCCESS)) {
      $result = $app.cnst.ERROR
    }
    log "[Invoke-Sync] Error ! $_"
    Move-ToNg ([PSCustomObject]@{ path = $arg.path })
  } finally {
    $resultFile = $arg.path.Replace("/", "\").Replace("\if\sync", "\if\sync_result")
    [PSCustomObject]@{
      time = [PSCustomObject]@{
        in = $cfg.time.in
        out = Get-Date -f "yyyy/MM/dd HH:mm:ss.fff"
      }
      src = $cfg.src
      dst = $cfg.dst
      type = $cfg.type
      option = $cfg.option
      remove = $cfg.remove
      result = $result
    } | ConvertTo-Json | Set-Content -Encoding utf8 "${resultFile}"
  }
}

<#
  .SYNOPSIS
    Invoke-Remove
  .DESCRIPTION
    remove を実行する
  .INPUTS
    - arg: 引数情報 (PSCustomObject)
      path: 情報ファイルパス
  .OUTPUTS
    - None
#>
function Invoke-Remove {
  [CmdletBinding()]
  [OutputType([void])]
  param([PSCustomObject]$arg)

  log "[Invoke-Remove] arg: $([PSCustomObject]$arg | ConvertTo-Json)"
  $result = $app.cnst.ERROR
  $mutex = New-Mutex $app $arg.path
  if (!$mutex.WaitOne(0, $false)) {
    log "[Invoke-Remove] 2重起動です！終了します。" "Yellow"
    return $app.cnst.WARN
  }
  if (!(Test-Path $arg.path)) {
    log "[Invoke-Remove] $($arg.path) は存在しません"
    return $app.cnst.WARN
  }
  try {
    $json = Get-Content -Encoding utf8 $arg.path
    log "[Invoke-Remove] json: ${json}"
    $cfg = $json | ConvertFrom-Json
    log "[Invoke-Remove] path: [$($cfg.path)]"
    if (Test-Path $cfg.path) {
      log "[Invoke-Remove] Remove: [$($cfg.path)]"
      Remove-Item -Force -Recurse $cfg.path
    } else {
      log "[Invoke-Remove] $($cfg.path) is not found !"
    }
    Remove-Item -Force $arg.path
    $result = $app.cnst.SUCCESS
  } catch {
    if (($null -eq $result) -or ($result -eq $app.cnst.SUCCESS)) {
      $result = $app.cnst.ERROR
    }
    log "[Invoke-Remove] [Invoke-Remove] Error ! $_"
    Move-ToNg ([PSCustomObject]@{ path = $arg.path })
  } finally {
    $resultFile = $arg.path.Replace("/", "\").Replace("\if\remove", "\if\remove_result")
    [PSCustomObject]@{
      time = [PSCustomObject]@{
        in = $cfg.time.in
        out = Get-Date -f "yyyy/MM/dd HH:mm:ss.fff"
      }
      path = $cfg.path
      result = $result
    } | ConvertTo-Json | Set-Content -Encoding utf8 "${resultFile}"
  }
}

<#
  .SYNOPSIS
    Invoke-Exec
  .DESCRIPTION
    exec を実行する
  .INPUTS
    - arg: 引数情報 (PSCustomObject)
      path: 情報ファイルパス
  .OUTPUTS
    - None
#>
function Invoke-Exec {
  [CmdletBinding()]
  [OutputType([void])]
  param([PSCustomObject]$arg)

  log "[Invoke-Exec] arg: $([PSCustomObject]$arg | ConvertTo-Json)"
  $result = $app.cnst.ERROR
  $mutex = New-Mutex $app $arg.path
  if (!$mutex.WaitOne(0, $false)) {
    log "[Invoke-Exec] 2重起動です！終了します。" "Yellow"
    return $app.cnst.WARN
  }
  if (!(Test-Path $arg.path)) {
    log "[Invoke-Exec] $($arg.path) は存在しません"
    return $app.cnst.WARN
  }
  try {
    $json = Get-Content -Encoding utf8 $arg.path
    log "[Invoke-Exec] json: ${json}"
    $cfg = $json | ConvertFrom-Json
    log "[Invoke-Exec] cmd: [$($cfg.cmd)]"
    log "[Invoke-Exec] arg: [$($cfg.arg)]"
    log "[Invoke-Exec] dir: [$($cfg.dir)]"
    $ret = Execute-Process ([PSCustomObject]@{ cmd = $cfg.cmd; arg = $cfg.arg -join " "; dir = $cfg.dir })
    log "[Invoke-Exec] code: [$($ret.code)]"
    log "[Invoke-Exec] stdout: [$($ret.stdout)]"
    log "[Invoke-Exec] stderr: [$($ret.stderr)]"
    Remove-Item -Force $arg.path
    $result = $ret.code
  } catch {
    if (($null -eq $result) -or ($result -eq $app.cnst.SUCCESS)) {
      $result = $app.cnst.ERROR
    }
    log "[Invoke-Exec] Error ! $_"
    Move-ToNg ([PSCustomObject]@{ path = $arg.path })
  } finally {
    $resultFile = $arg.path.Replace("/", "\").Replace("\if\exec", "\if\exec_result")
    [PSCustomObject]@{
      time = [PSCustomObject]@{
        in = $cfg.time.in
        out = Get-Date -f "yyyy/MM/dd HH:mm:ss.fff"
      }
      cmd = $cfg.cmd
      arg = $cfg.arg
      dir = $cfg.dir
      result = $result
    } | ConvertTo-Json | Set-Content -Encoding utf8 "${resultFile}"
  }
}

<#
  .SYNOPSIS
    Move-ToNg
  .DESCRIPTION
    ファイルを NG 領域へ移動する
  .INPUTS
    - arg: 引数情報 (PSCustomObject)
      path: 対象ファイルパス
  .OUTPUTS
    - None
#>
function Move-ToNg {
  [CmdletBinding()]
  [OutputType([int])]
  param([string]$path)
  trap {
    log "[Move-ToNg] Error $_" "Red"
    throw $_
  }

  log "[Move-ToNg] arg: $([PSCustomObject]$arg | ConvertTo-Json)"
  $src = $arg.path
  $dst = $src.Replace("/", "\").Replace("\if\", "\ng\if\").Replace("\task\", "\ng\task\")
  log "[Move-ToNg] [${src}] -> [${dst}]"
  New-Item -Force -ItemType Directory (Split-Path -Parent $dst) | Out-Null
  Move-Item -Force $src $dst
}

<#
  .SYNOPSIS
    Result-Task
  .DESCRIPTION
    タスクの結果ファイルを転送する
  .INPUTS
    - arg: リザルト情報 (PSCustomObject)
      result: 結果サフィックス
      async: $true: 非同期 / $false: 同期 (Default: $false)
  .OUTPUTS
    - result: 0 (成功) / not 0 (失敗)
#>
function Result-Task {
  [CmdletBinding()]
  [OutputType([int])]
  param([PSCustomObject]$arg)
  trap {
    log "[Result-Task] Error $_" "Red"
    throw $_
  }

  log "[Result-Task] arg: $([PSCustomObject]$arg | ConvertTo-Json)"

  log "[Result-Task] Create result file."
  $resultPath = [System.IO.Path]::Combine($app.resultDirRemote, "${env:COMPUTERNAME}_$($app.logName)_$($arg.result).log")
  return Sync-FS ([PSCustomObject]@{
      src = $app.logFile
      dst = $resultPath
      type = "file"
      async = $arg.async
    })
}

<#
  .SYNOPSIS
    Exit-Task
  .DESCRIPTION
    タスクを終了する。
  .INPUTS
    - arg: 終了タスク情報 (PSCustomObject)
      path: 削除タスクファイル
      xml: 削除タスクxmlstr
      result: 結果サフィックス
      async: $true: 非同期 / $false: 同期 (Default: $false)
  .OUTPUTS
    - result: 0 (成功) / not 0 (失敗)
#>
function Exit-Task {
  [CmdletBinding()]
  [OutputType([int])]
  param([PSCustomObject]$arg)
  trap {
    log "[Exit-Task] Error $_" "Red"
    throw $_
  }

  log "[Exit-Task] arg: $([PSCustomObject]$arg | ConvertTo-Json)"

  $result = Result-Task ([PSCustomObject]@{ result = $arg.result; async = $arg.async })
  if ($result -ne $app.cnst.SUCCESS) {
    log "[Exit-Task] Error ! result: [${result}]" "Red"
  }

  log "[Exit-Task] Create del file."
  $result = $app.cnst.SUCCESS
  $app.baseRemotes | ForEach-Object {
    $p = $arg.path.Replace($app.baseLocal, $_)
    $r = New-DelFile ([PSCustomObject]@{
        path = $p
      })
    $r
  } | ForEach-Object {
    $result += $_
  }
  if ($result -ne $app.cnst.SUCCESS) {
    log "[Exit-Task] Error ! result: [${result}]" "Red"
  }

  if ([string]::IsNullOrEmpty($arg.xml)) {
    return $result
  }

  log "[Exit-Task] Remove task xml: $($arg.xml)"
  $result = Remove-ScheduledTask ([PSCustomObject]@{
      xml = $arg.xml
      async = $arg.async
    })

  if ($result -ne $app.cnst.SUCCESS) {
    log "[Exit-Task] Error ! result: [${result}]" "Red"
  }
  return $result
}

<#
  .SYNOPSIS
    Check-ModifiedCmd
  .DESCRIPTION
    現実行ファイルが変更されていないかチェックする
  .INPUTS
    - arg: チェックタスク情報 (PSCustomObject)
      path: チェックタスクファイル
      xml: チェックタスクxmlstr
      result: 結果サフィックス
      async: $true: 非同期 / $false: 同期 (Default: $false)
  .OUTPUTS
    - result: 0 (成功) / not 0 (失敗)
#>
function Check-ModifiedCmd {
  [CmdletBinding()]
  [OutputType([int])]
  param([PSCustomObject]$arg)
  trap {
    log "[Check-ModifiedCmd] Error $_" "Red"
    throw $_
  }

  log "[Check-ModifiedCmd] start"
  log "[Check-ModifiedCmd] arg: $([PSCustomObject]$arg | ConvertTo-Json)"
  $localHashBefore = (Get-FileHash $app.cmdFile).Hash
  log "[Check-ModifiedCmd] sync cmd"
  $result = & {
    if ($app.scope -eq "global") {
      return Sync-FS ([PSCustomObject]@{
          src = ([System.IO.Path]::Combine($app.baseRemote, $app.userType, "cmd", "global"))
          dst = ([System.IO.Path]::Combine($app.baseLocal, $app.userType, "cmd", "global"))
          type = "directory"
          option = "/mir"
        })
    }
    if ($app.scope -eq "local") {
      return Sync-FS ([PSCustomObject]@{
          src = ([System.IO.Path]::Combine($app.baseRemote, $app.userType, "cmd", "local", $env:COMPUTERNAME))
          dst = ([System.IO.Path]::Combine($app.baseLocal, $app.userType, "cmd", "local", $env:COMPUTERNAME))
          type = "directory"
          option = "/mir"
        })
    }
    return $app.cnst.ERROR
  }

  if ($result -ne $app.cnst.SUCCESS) {
    log "[Check-ModifiedCmd] Error ! result: [${result}]" "Red"
    return $result
  }

  if (!(Test-Path $app.cmdFile)) {
    log "[Check-ModifiedCmd] $($app.cmdFile) is not found ! so Exit-Task !"
    return Exit-Task ([PSCustomObject]@{
        path = $arg.path
        xml = $arg.xml
        result = $arg.result
        async = $arg.async
      })
  }

  $localHashAfter = (Get-FileHash $app.cmdFile).Hash

  if ($localHashBefore -ne $localHashAfter) {
    log "[Check-ModifiedCmd] hash chainged !"
    return $app.cnst.ERROR
  }

  log "[Check-ModifiedCmd] end"
  return $app.cnst.SUCCESS
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
    New-DelFile
  .DESCRIPTION
    リモート del ファイルの作成
  .INPUTS
    - arg: 削除情報 (PSCustomObject)
      path: 削除パス
      async: $true: 非同期 / $false: 同期 (Default: $false)
  .OUTPUTS
    - result: 0 (成功) / not 0 (失敗)
#>
function New-DelFile {
  [CmdletBinding()]
  [OutputType([int])]
  param([PSCustomObject]$arg)

  log "[New-DelFile] arg: $([PSCustomObject]$arg | ConvertTo-Json)"

  $guid = (New-Guid).Guid
  $localDelFile = [System.IO.Path]::Combine($app.delLocal, "${env:COMPUTERNAME}_$($app.cmdName)_${guid}.json")
  $remoteDelFile = [System.IO.Path]::Combine($app.delRemote, "${env:COMPUTERNAME}_$($app.cmdName)_${guid}.json")

  log "[New-DelFile] localDelFile: ${localDelFile}"
  log "[New-DelFile] remoteDelFile: ${remoteDelFile}"

  $arg | ConvertTo-Json | Set-Content -Encoding utf8 $localDelFile

  Sync-FS ([PSCustomObject]@{
      src = $localDelFile
      dst = $remoteDelFile
      type = "file"
      async = $arg.async
      remove = $true
    })
}

<#
  .SYNOPSIS
    Wait-Spyrun
  .DESCRIPTION
    spyrun.exe のプロセス起動待ち
  .INPUTS
    - userType
  .OUTPUTS
    - result: 0 (成功) / not 0 (失敗)
#>
function Wait-Spyrun {
  [CmdletBinding()]
  [OutputType([int])]
  param([string]$userType)

  trap {
    log "[Wait-Spyrun] Error $_" "Red"
    throw $_
  }

  $limitTime = (Get-Date).AddMinutes(10)

  while ($true) {
    if ((Get-Date) -gt $limitTime) {
      log "[Wait-Spyrun] Time over !!!" "Red"
      return $app.cnst.ERROR
    }
    Get-CimInstance -ClassName Win32_Process | Where-Object {
      $_.Name -eq "spyrun.exe" -and $_.CommandLine -match $userType
    } | Set-Variable spyrun
    if ($null -ne $spyrun) {
      log "[Wait-Spyrun] Process spyrun.exe is Found !"
      return
    } else {
      log "[Wait-Spyrun] Process spyrun.exe is not found ..."
      Start-Sleep -Seconds 1
    }
  }
  return $app.cnst.SUCCESS
}

<#
  .SYNOPSIS
    Start-Init
  .DESCRIPTION
    Init 処理
  .INPUTS
    - mode: "register": タスク登録, "main": 処理実行
    - version
  .OUTPUTS
    - $app
#>
function Start-Init {

  [CmdletBinding()]
  [OutputType([object])]
  param([string]$mode, [string]$version)
  trap {
    log "[Start-Init] Error $_" "Red"
    throw $_
  }

  log "[Start-Init] Start"

  $cmdFullPath = & {
    if ($env:__SCRIPTPATH) {
      return [System.IO.Path]::GetFullPath($env:__SCRIPTPATH)
    } else {
      return [System.IO.Path]::GetFullPath($script:MyInvocation.MyCommand.Path)
    }
  }

  $app.Add("mode", $mode)
  $app.Add("version", $version)
  $app.Add("lock", $false)

  $app.Add("cmdFile", $cmdFullPath)
  $app.Add("cmdDir", [System.IO.Path]::GetDirectoryName($app.cmdFile))
  $app.Add("cmdName", [System.IO.Path]::GetFileNameWithoutExtension($app.cmdFile))
  $app.Add("cmdFileName", [System.IO.Path]::GetFileName($app.cmdFile))
  $app.Add("pwd", [System.IO.Path]::GetFullPath((Get-Location).Path))
  $app.Add("now", (Get-Date -Format "yyyyMMddTHHmmssfffffff"))

  $sp = $app.cmdFile -split "\\" | Where-Object { $_ -ne $env:COMPUTERNAME -and $_ -ne "cmd" }
  $app.Add("userType", $sp[-3])
  $app.Add("scope", $sp[-2])

  $app.Add("spyrunFile", "C:\ProgramData\spyrun\bin\spyrun.exe")
  $app.Add("spyrunDir", [System.IO.Path]::GetDirectoryName($app.spyrunFile))
  $app.Add("spyrunName", [System.IO.Path]::GetFileNameWithoutExtension($app.spyrunFile))
  $app.Add("spyrunFileName", [System.IO.Path]::GetFileName($app.spyrunFile))
  $app.Add("spyrunBase", [System.IO.Path]::GetDirectoryName($app.spyrunDir))

  $app.Add("baseFilePath", ([System.IO.Path]::Combine($app.spyrunDir, "base.txt")))

  if (!(Test-Path $app.baseFilePath)) {
    throw "base file path: [$($app.baseFilePath)] is not found !"
  }

  $app.Add("baseRemotes", (Get-Content -Encoding utf8 $app.baseFilePath | Where-Object { $_.Trim() -notmatch "^$" }))
  $app.Add("baseRemote", @($app.baseRemotes)[0])
  $app.Add("baseUserTypeRemote", [System.IO.Path]::Combine($app.baseRemote, $app.userType))
  $app.Add("datRemote", [System.IO.Path]::Combine($app.baseRemote, "dat"))
  $app.Add("delRemote", [System.IO.Path]::Combine($app.baseRemote, "del"))
  $app.Add("flgRemote", [System.IO.Path]::Combine($app.baseRemote, "flg"))
  $app.Add("ngRemote", [System.IO.Path]::Combine($app.baseUserTypeRemote, "ng"))
  $app.Add("clctRemote", [System.IO.Path]::Combine($app.baseUserTypeRemote, "clct"))
  $app.Add("resultDirRemote", [System.IO.Path]::Combine($app.baseUserTypeRemote, "result", $app.scope, $app.cmdName))
  $app.Add("resultPrefixFileRemote", [System.IO.Path]::Combine($app.resultDirRemote, "${env:COMPUTERNAME}_$($app.cmdName)"))

  $app.Add("baseLocal", [System.IO.Path]::Combine($app.spyrunBase))
  $app.Add("baseUserTypeLocal", $app.baseUserTypeRemote.Replace($app.baseRemote, $app.baseLocal))
  $app.Add("datLocal", $app.datRemote.Replace($app.baseRemote, $app.baseLocal))
  $app.Add("delLocal", $app.delRemote.Replace($app.baseRemote, $app.baseLocal))
  $app.Add("flgLocal", $app.flgRemote.Replace($app.baseRemote, $app.baseLocal))
  $app.Add("ngLocal", $app.ngRemote.Replace($app.baseRemote, $app.baseLocal))
  $app.Add("clctLocal", $app.clctRemote.Replace($app.baseRemote, $app.baseLocal))
  $app.Add("resultDirLocal", $app.resultDirRemote.Replace($app.baseRemote, $app.baseLocal))
  $app.Add("resultPrefixFileLocal", $app.resultPrefixFileRemote.Replace($app.baseRemote, $app.baseLocal))

  if ($app.userType -eq "core") {
    $app.Add("logDir", [System.IO.Path]::Combine($app.baseRemote, $app.userType, "log", $env:COMPUTERNAME, $app.scope, $app.cmdName))
  } else {
    $app.Add("logDir", [System.IO.Path]::Combine($app.baseLocal, $app.userType, "log", $app.scope, $app.cmdName))
  }
  $app.Add("logFile", [System.IO.Path]::Combine($app.logDir, "$($app.cmdName)_$($app.mode)_$($app.now).log"))
  $app.Add("logName", [System.IO.Path]::GetFileNameWithoutExtension($app.logFile))
  $app.Add("logFileName", [System.IO.Path]::GetFileName($app.logFile))
  New-Item -Force -ItemType Directory $app.logDir | Out-Null
  Start-Transcript $app.logFile

  log "[Start-Init] version: $($app.version)"
  log ([PSCustomObject]$app | ConvertTo-Json)

  # mutex check
  $app.Add("mutex", (New-Mutex $app))
  # TODO: 二重起動を許容するパターンも対応必要
  if (!$app.mutex.WaitOne(0, $false)) {
    log "[Start-Init] 2重起動です！終了します。" "Yellow"
    exit $app.cnst.WARN
  }
  $app.lock = $true

  log "[Start-Init] End"

  return $app
}
