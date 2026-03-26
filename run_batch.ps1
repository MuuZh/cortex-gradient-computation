wbLog$ErrorActionPreference = "Stop"

$wb = "E:\resarch_data\fMRI\workbench-windows64-v2.1.0\workbench\bin_windows64\wb_command.exe"

$dtseriesdir = "E:\resarch_data\fMRI\fMRI_DMT\dtseries\DMT_DMT_dtseries"
$outDir = "F:\research\dconn\results\DMT\group_dconn"

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$tmpDir = Join-Path $outDir "tmp"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$transcriptLog = Join-Path $outDir "transcript_$stamp.log"
$wbLog         = Join-Path $outDir "wb_$stamp.log"

Start-Transcript -Path $transcriptLog -Append | Out-Null
Write-Host "Transcript: $transcriptLog" -ForegroundColor Yellow
Write-Host "WB log:     $wbLog" -ForegroundColor Yellow

function Invoke-WBCommand {
    param(
        [Parameter(Mandatory=$true)][string[]]$Args,
        [Parameter(Mandatory=$true)][string]$StepName
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] >>> $StepName" -ForegroundColor Cyan
    Write-Host "    $wb $($Args -join ' ')" -ForegroundColor DarkGray

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $wb @Args 2>&1 | Tee-Object -FilePath $wbLog -Append | Out-Host
    $exit = $LASTEXITCODE
    $sw.Stop()

    if ($exit -ne 0) { throw "wb_command failed (exit=$exit) at step: $StepName" }

    $ts2 = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts2] <<< DONE $StepName in $([math]::Round($sw.Elapsed.TotalMinutes,2)) min" -ForegroundColor Green
}

# ---- collect inputs (include recurse if needed) ----
$files = Get-ChildItem -Path $dtseriesdir -Filter "*dtseries.nii" -File | Sort-Object Name
if ($files.Count -lt 2) { throw "No dtseries found under: $dtseriesdir" }

Write-Host ("Found {0} dtseries files" -f $files.Count) -ForegroundColor Yellow

$LzList = @()
$RzList = @()

for ($i=0; $i -lt $files.Count; $i++) {
    $f = $files[$i]
    $pct = [int](100.0*($i+1)/$files.Count)

    Write-Progress -Activity "Per-subject dconn pipeline (L/R cortex)" `
        -Status ("{0}/{1}: {2}" -f ($i+1), $files.Count, $f.Name) `
        -PercentComplete $pct

    $in = $f.FullName
    $base = $f.BaseName -replace "\.dtseries$", ""

    # put all intermediates into ONE tmpDir (created once)
    $Lfunc = Join-Path $tmpDir "${base}_L.func.gii"
    $Rfunc = Join-Path $tmpDir "${base}_R.func.gii"
    $Ldt   = Join-Path $tmpDir "${base}_L.dtseries.nii"
    $Rdt   = Join-Path $tmpDir "${base}_R.dtseries.nii"
    $Lr    = Join-Path $tmpDir "${base}_L_r.dconn.nii"
    $Rr    = Join-Path $tmpDir "${base}_R_r.dconn.nii"
    $Lz    = Join-Path $tmpDir "${base}_L_z.dconn.nii"
    $Rz    = Join-Path $tmpDir "${base}_R_z.dconn.nii"

    Invoke-WBCommand -Args @("-cifti-separate", $in, "COLUMN", "-metric", "CORTEX_LEFT", $Lfunc, "-metric", "CORTEX_RIGHT", $Rfunc) `
           -StepName "SEPARATE (L/R cortex) $($f.Name)"

    Invoke-WBCommand -Args @("-cifti-create-dense-timeseries", $Ldt, "-left-metric",  $Lfunc) `
           -StepName "CREATE_L_DT $($f.Name)"
    Invoke-WBCommand -Args @("-cifti-create-dense-timeseries", $Rdt, "-right-metric", $Rfunc) `
           -StepName "CREATE_R_DT $($f.Name)"

    Invoke-WBCommand -Args @("-cifti-correlation", $Ldt, $Lr) -StepName "CORR_L $($f.Name)"
    Invoke-WBCommand -Args @("-cifti-correlation", $Rdt, $Rr) -StepName "CORR_R $($f.Name)"

    Invoke-WBCommand -Args @("-cifti-math", "atanh(max(min(x,0.999999),-0.999999))", $Lz, "-var", "x", $Lr) `
           -StepName "FISHER_Z_L $($f.Name)"
    Invoke-WBCommand -Args @("-cifti-math", "atanh(max(min(x,0.999999),-0.999999))", $Rz, "-var", "x", $Rr) `
           -StepName "FISHER_Z_R $($f.Name)"

    $LzList += $Lz
    $RzList += $Rz

    # cleanup per subject intermediates (keep z for group average)
    Remove-Item $Lfunc,$Rfunc,$Ldt,$Rdt,$Lr,$Rr -ErrorAction SilentlyContinue
}

Write-Progress -Activity "Per-subject dconn pipeline (L/R cortex)" -Completed

# ---- group outputs (DO NOT overwrite these with relative paths) ----
$groupL   = Join-Path $outDir "group_L_zcorr.dconn.nii"
$groupR   = Join-Path $outDir "group_R_zcorr.dconn.nii"
$groupL_r = Join-Path $outDir "group_L_r.dconn.nii"
$groupR_r = Join-Path $outDir "group_R_r.dconn.nii"

# group average
$cmdL = @("-cifti-average", $groupL) + ($LzList | ForEach-Object { @("-cifti", $_) })
$cmdR = @("-cifti-average", $groupR) + ($RzList | ForEach-Object { @("-cifti", $_) })

Invoke-WBCommand -Args $cmdL -StepName "GROUP_AVERAGE_L_Z"
Invoke-WBCommand -Args $cmdR -StepName "GROUP_AVERAGE_R_Z"

# optional: tanh back to r
Invoke-WBCommand -Args @("-cifti-math", "tanh(x)", $groupL_r, "-var", "x", $groupL) -StepName "GROUP_L_Z_TO_R"
Invoke-WBCommand -Args @("-cifti-math", "tanh(x)", $groupR_r, "-var", "x", $groupR) -StepName "GROUP_R_Z_TO_R"

# delete per-subject z if you only want group-level outputs
Remove-Item -Path ($LzList + $RzList) -ErrorAction SilentlyContinue

# optional: remove tmpDir entirely (comment out if you want to keep it)
# Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

Stop-Transcript | Out-Null
Write-Host "Transcript log: $transcriptLog"
Write-Host "WB log:         $wbLog" 
Write-Host "Done." -ForegroundColor Yellow
Write-Host "Outputs:" -ForegroundColor Yellow
Write-Host "  $groupL"
Write-Host "  $groupR"
Write-Host "  $groupL_r"
Write-Host "  $groupR_r"