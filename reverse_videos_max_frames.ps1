param(
    [int]$MaxFrames = 101,
    [int]$CRF = 18,
    [string]$PRESET = "slow",
    [string]$CODEC = "libx264",
    [switch]$KeepAudio,
    [switch]$Overwrite,
    [switch]$DryRun
)
$outDir = "reversed"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Count-Frames {
    param([string]$File)
    $nb = ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of default=nw=1:nk=1 $File 2>$null
    if ($nb -match '^[0-9]+$' -and [int]$nb -gt 0) { return [int]$nb }
    $dur = ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 $File 2>$null
    if (-not $dur) { $dur = 0 }
    $rate = ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=nw=1:nk=1 $File 2>$null
    if (-not $rate) { $rate = '0/1' }
    $parts = $rate -split '/'
    if ($parts.Length -ne 2 -or [int]$parts[1] -eq 0) { return 0 }
    $fps = [double]$parts[0] / [double]$parts[1]
    return [int]([double]$dur * $fps)
}

function Has-Audio {
    param([string]$File)
    $out = ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 $File 2>$null
    return -not [string]::IsNullOrEmpty($out)
}

$ffw = '-n'; if ($Overwrite) { $ffw = '-y' }
$processed=0; $made=0; $skipped=0; $warned=0
Get-ChildItem -Path . -Filter *.mp4 -File | ForEach-Object {
    $processed++
    $frames = Count-Frames $_.FullName
    if (-not ($frames -is [int])) { Write-Host "WARN  $($_.Name): could not determine frame count"; $warned++; return }
    if ($frames -gt $MaxFrames) { Write-Host "SKIP  $($_.Name)  ($frames > $MaxFrames)"; $skipped++; return }
    $out = Join-Path $outDir ("$($_.BaseName)_reversed.mp4")
    Write-Host "MAKE  $($_.Name)  ($frames ≤ $MaxFrames) -> $out"
    if ($DryRun) { $made++; return }
    if ($KeepAudio -and (Has-Audio $_.FullName)) {
        ffmpeg $ffw -hide_banner -loglevel error -i $_.FullName -filter_complex "[0:v]reverse[v];[0:a]areverse[a]" -map "[v]" -map "[a]" -c:v $CODEC -preset $PRESET -crf $CRF -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart $out
    } else {
        ffmpeg $ffw -hide_banner -loglevel error -i $_.FullName -an -vf reverse -c:v $CODEC -preset $PRESET -crf $CRF -pix_fmt yuv420p -movflags +faststart $out
    }
    $made++
}
Write-Host "Done. processed=$processed  made=$made  skipped=$skipped  warnings=$warned  outdir=$outDir"
