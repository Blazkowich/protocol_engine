[CmdletBinding()]
param(
    [switch]$All
)

$python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $python) {
    Write-Error "Python was not found on PATH. Install Python 3 and retry."
    exit 127
}

$runner = Join-Path $PSScriptRoot "run_tests.py"
$runnerArgs = @($runner)
if ($All) {
    $runnerArgs += "--all"
}

& $python.Source @runnerArgs
exit $LASTEXITCODE