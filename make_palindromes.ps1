param(
    [int]$MaxFrames = 101,
    [int]$TargetFrames = 101,
    [int]$FPS = 16,
    [int]$CRF = 18,
    [string]$PRESET = "slow",
    [string]$CODEC = "libx264",
    [switch]$EnforceTarget,
    [switch]$KeepAudio,
    [switch]$Overwrite,
    [switch]$DryRun
)
$outDir = "palindromes"
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

function Speed-For {
    param([int]$FramesIn,[int]$Target)
    if ($Target -le 0) { return 1.0 }
    return [double]$FramesIn / [double]$Target
}

$ffw = '-n'; if ($Overwrite) { $ffw = '-y' }
$processed=0; $made=0; $skipped=0; $warned=0
Get-ChildItem -Path . -Filter *.mp4 -File | ForEach-Object {
    $processed++
    $frames = Count-Frames $_.FullName
    if (-not ($frames -is [int])) { Write-Host "WARN  $($_.Name): could not read frame count"; $warned++; return }
    if ($frames -gt $MaxFrames) { Write-Host "SKIP  $($_.Name)  ($frames > $MaxFrames)"; $skipped++; return }
    $palFrames = 2*$frames - 1
    $speed = 1.0
    if ($palFrames -gt $TargetFrames) { $speed = Speed-For $palFrames $TargetFrames }
    elseif ($EnforceTarget -and $palFrames -lt $TargetFrames) { $speed = Speed-For $palFrames $TargetFrames }
    $out = Join-Path $outDir ("$($_.BaseName)_pal.mp4")
    Write-Host "MAKE  $($_.Name)  in=$frames  pal=$palFrames  speed=${speed}x  -> $out"
    if ($DryRun) { $made++; return }
    if ($KeepAudio) {
        $fc = "[0:v]split=2[fwd][r0];[r0]reverse,trim=start_frame=1[rev];[fwd][rev]concat=n=2:v=1:a=0,setpts=PTS/$speed,fps=$FPS[v];[0:a]areverse,atrim=start=0.00002[ar];[0:a][ar]concat=n=2:v=0:a=1,asetpts=N/SR/TB[a]"
        ffmpeg $ffw -hide_banner -loglevel error -i $_.FullName -filter_complex $fc -map "[v]" -map "[a]" -frames:v $TargetFrames -c:v $CODEC -preset $PRESET -crf $CRF -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart $out
    } else {
        $fc = "[0:v]split=2[fwd][r0];[r0]reverse,trim=start_frame=1[rev];[fwd][rev]concat=n=2:v=1:a=0,setpts=PTS/$speed,fps=$FPS[v]"
        ffmpeg $ffw -hide_banner -loglevel error -i $_.FullName -filter_complex $fc -map "[v]" -an -frames:v $TargetFrames -c:v $CODEC -preset $PRESET -crf $CRF -pix_fmt yuv420p -movflags +faststart $out
    }
    $made++
}
Write-Host "Done. processed=$processed made=$made skipped=$skipped warned=$warned outdir=$outDir"
