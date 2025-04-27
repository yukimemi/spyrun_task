@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{$_.readcount -gt 2})-join\"`n\");&$s" %*
@exit /b %errorlevel%

<#
  .SYNOPSIS
    register_spyrun.cmd
  .DESCRIPTION
    spyrun の登録
  .INPUTS
    - None
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change : 2025/04/27 10:13:35.
#>
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
$version = "20250427_101335"
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
    Init
  .DESCRIPTION
    Init
  .INPUTS
    - None
  .OUTPUTS
    - None
#>
function Start-Init {

  [CmdletBinding()]
  [OutputType([void])]
  param()
  trap {
    log "[Start-Init] Error $_"; throw $_
  }

  log "[Start-Init] Start"

  $script:app = @{}

  $cmdFullPath = & {
    if ($env:__SCRIPTPATH) {
      return [System.IO.Path]::GetFullPath($env:__SCRIPTPATH)
    } else {
      return [System.IO.Path]::GetFullPath($script:MyInvocation.MyCommand.Path)
    }
  }
  $app.Add("cmdFile", $cmdFullPath)
  $app.Add("cmdDir", [System.IO.Path]::GetDirectoryName($app.cmdFile))
  $app.Add("cmdName", [System.IO.Path]::GetFileNameWithoutExtension($app.cmdFile))
  $app.Add("cmdFileName", [System.IO.Path]::GetFileName($app.cmdFile))
  $app.Add("pwd", [System.IO.Path]::GetFullPath((Get-Location).Path))
  $app.Add("now", (Get-Date -Format "yyyyMMddTHHmmssfffffff"))

  # const value.
  $app.Add("cnst", @{
      SUCCESS = 0
      ERROR   = 1
    })

  # Init result
  $app.Add("result", $app.cnst.ERROR)

  log "[Start-Init] End"
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

    Start-Init

    log "[Start-Main] Start"

    $spyrunLocal = "C:\ProgramData\spyrun"
    $spyrunRemote = $app.cmdDir

    log "spyrunLocal: ${spyrunLocal}" "Cyan"
    log "spyrunRemote: ${spyrunRemote}" "Green"

    Get-Process | Where-Object {
      $_.ProcessName -eq "spyrun"
    } | ForEach-Object {
      Stop-Process -Force -Id $_.Id
    }

    Execute-Process ([PSCustomObject]@{ cmd = "icacls"; arg = "`"${spyrunLocal}`" /grant EveryOne:F /t" })

    Get-Process | Where-Object {
      $_.ProcessName -eq "spyrun"
    } | ForEach-Object {
      Stop-Process -Force -Id $_.Id
    }

    Remove-Item -Force -Recurse $spyrunLocal -ErrorAction Continue
    Execute-Process ([PSCustomObject]@{ cmd = "robocopy"; arg = "/mir `"${spyrunRemote}\bin`" `"${spyrunLocal}\bin`"" })

    Execute-Process ([PSCustomObject]@{ cmd = "C:\ProgramData\spyrun\bin\spyrun.exe"; dir = "C:\ProgramData\spyrun\bin"; wait = $false })

  } catch {
    log "[Start-Main] Error ! $_" "Red"
    Enable-RunspaceDebug -BreakAll
  } finally {
    $endTime = Get-Date
    $span = $endTime - $startTime
    log ("Elapsed time: {0} {1:00}:{2:00}:{3:00}.{4:000}" -f $span.Days, $span.Hours, $span.Minutes, $span.Seconds, $span.Milliseconds)
    log "[Start-Main] End"
  }
}

# Call main.
Start-Main
exit $app.result

# vim: ft=ps1
