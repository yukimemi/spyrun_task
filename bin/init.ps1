<#
  .SYNOPSIS
    init.ps1
  .DESCRIPTION
    init
  .INPUTS
    - None
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change : 2024/11/12 22:10:35.
#>
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue"

$base = "C:\Users\yukimemi\src\github.com\yukimemi\spyrun_task"
$base | Set-Content -Encoding utf8 "C:\ProgramData\spyrun\bin\base.txt"
$base

