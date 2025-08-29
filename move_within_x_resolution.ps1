param(
    [int]$X = 512,
    [switch]$DryRun,
    [switch]$Overwrite
)
$dest = "within_${X}_resolution"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

function Avg-Dim {
    param([string]$File)
    $wh = ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x $File 2>$null | Select-Object -First 1
    if (-not $wh) { return $null }
    $parts = $wh -split 'x'
    if ($parts.Length -ne 2) { return $null }
    return [int](([int]$parts[0] + [int]$parts[1]) / 2)
}

$processed=0; $moved=0; $kept=0; $warned=0
Get-ChildItem -Path . -Filter *.mp4 -File | ForEach-Object {
    $processed++
    $ad = Avg-Dim $_.FullName
    if (-not ($ad -is [int])) { Write-Host "WARN  $($_.Name): could not read resolution"; $warned++; return }
    if ($ad -le $X) {
        Write-Host "MOVE  $($_.Name)  (avg_dim=$ad <= $X) -> $dest/"
        if (-not $DryRun) {
            $moveArgs = @{}
            if ($Overwrite) { $moveArgs.Force = $true }
            Move-Item -LiteralPath $_.FullName -Destination $dest @moveArgs
        }
        $moved++
    } else {
        Write-Host "KEEP  $($_.Name)  (avg_dim=$ad > $X)"
        $kept++
    }
}
Write-Host "Done. processed=$processed moved=$moved kept=$kept warned=$warned dest=$dest"
