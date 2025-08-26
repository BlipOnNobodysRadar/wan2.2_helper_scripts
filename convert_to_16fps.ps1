param(
    [int]$FPS = 16,
    [int]$CRF = 18,
    [string]$PRESET = "slow",
    [string]$OUTDIR = "16fps",
    [int]$EVEN = 2,
    [switch]$GPU
)

New-Item -ItemType Directory -Force -Path $OUTDIR | Out-Null

$scaleFilter = "scale=trunc(iw/$EVEN)*$EVEN:trunc(ih/$EVEN)*$EVEN:flags=lanczos"
$vf = "fps=$FPS:round=near,$scaleFilter"

Get-ChildItem -Path . -Include *.mp4,*.webm,*.mkv,*.mov,*.avi -File | ForEach-Object {
    $stem = $_.BaseName.ToLower()
    $out = Join-Path $OUTDIR ("${stem}_16fps.mp4")
    if (Test-Path $out) {
        Write-Host "SKIP  $out"
        return
    }
    Write-Host "→  $($_.Name)  →  $out"
    if ($GPU) {
        ffmpeg -hide_banner -loglevel error -y -i $_.FullName `
            -vf $vf -r $FPS -vsync cfr -an `
            -movflags +faststart -pix_fmt yuv420p `
            -c:v h264_nvenc -cq $CRF -preset p5 -tune hq -rc vbr -bf 3 -spatial_aq 1 -temporal_aq 1 `
            $out
    } else {
        ffmpeg -hide_banner -loglevel error -y -i $_.FullName `
            -vf $vf -r $FPS -vsync cfr -an `
            -movflags +faststart -pix_fmt yuv420p `
            -c:v libx264 -preset $PRESET -crf $CRF -profile:v high -level 4.1 `
            -x264opts "keyint=$($FPS*2):min-keyint=$FPS:no-scenecut" `
            $out
    }
}
