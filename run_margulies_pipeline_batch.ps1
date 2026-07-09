param(
    [string]$PythonExe = "python",
    [string]$PipelineScript = (Join-Path $PSScriptRoot "margulies_pipeline_merged.py"),
    [Parameter(Mandatory = $true)][string]$JobConfig,
    [switch]$ContinueOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# JobConfig must be a CSV with columns:
# dconn,header_ref,surf_gii,out_basedir,hemi
if (-not (Test-Path -LiteralPath $JobConfig)) {
    throw "Job config not found: $JobConfig"
}
$Jobs = @(Import-Csv -LiteralPath $JobConfig)

if (-not (Test-Path -LiteralPath $PipelineScript)) {
    throw "Pipeline script not found: $PipelineScript"
}

if ($Jobs.Count -eq 0) {
    throw "No jobs configured in: $JobConfig"
}

Write-Host "Total jobs: $($Jobs.Count)"
Write-Host "Pipeline : $PipelineScript"
Write-Host "Python   : $PythonExe"

for ($i = 0; $i -lt $Jobs.Count; $i++) {
    $job = $Jobs[$i]
    $jobIndex = $i + 1

    foreach ($key in @("dconn", "header_ref", "surf_gii", "out_basedir", "hemi")) {
        if ($key -notin $job.PSObject.Properties.Name -or [string]::IsNullOrWhiteSpace([string]$job.$key)) {
            throw "Job #$jobIndex missing required key: $key"
        }
    }

    Write-Host ""
    Write-Host "=== Job $jobIndex/$($Jobs.Count) ==="
    Write-Host "dconn      : $($job.dconn)"
    Write-Host "header_ref : $($job.header_ref)"
    Write-Host "surf_gii   : $($job.surf_gii)"
    Write-Host "out_basedir: $($job.out_basedir)"
    Write-Host "hemi       : $($job.hemi)"

    if (-not (Test-Path -LiteralPath $job.dconn)) { throw "dconn not found: $($job.dconn)" }
    if (-not (Test-Path -LiteralPath $job.header_ref)) { throw "header_ref not found: $($job.header_ref)" }
    if (-not (Test-Path -LiteralPath $job.surf_gii)) { throw "surf_gii not found: $($job.surf_gii)" }

    New-Item -ItemType Directory -Force -Path $job.out_basedir | Out-Null

    $cmdArgs = @(
        $PipelineScript
        "--dconn", $job.dconn
        "--header-ref", $job.header_ref
        "--surf-gii", $job.surf_gii
        "--out-basedir", $job.out_basedir
        "--hemi", $job.hemi
    )

    & $PythonExe @cmdArgs
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        $msg = "Job #$jobIndex failed with exit code $exitCode."
        if ($ContinueOnError) {
            Write-Warning $msg
            continue
        }
        throw $msg
    }

    [GC]::Collect()
}

Write-Host ""
Write-Host "All jobs finished."
