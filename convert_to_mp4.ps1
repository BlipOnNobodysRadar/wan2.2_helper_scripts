param(
    [string[]]$Paths,
    [string]$CRF = "14",
    [string]$PRESET = "slow",
    [string]$OUTDIR = "converted",
    [int]$AudioKbps = 320,
    [switch]$Overwrite
)

if (-not $Paths) { $Paths = "." }

New-Item -ItemType Directory -Force -Path $OUTDIR | Out-Null

$ffOverwrite = if ($Overwrite) { "-y" } else { "-n" }
$videoExts = "*.webm","*.avi","*.mkv","*.mov","*.m4v","*.flv","*.ts","*.mts","*.m2ts","*.mpg","*.mpeg","*.3gp","*.ogv","*.mxf","*.wmv","*.mp4","*.gif","*.webp"

$inputs = foreach ($p in $Paths) {
    if (Test-Path $p) {
        if ((Get-Item $p).PSIsContainer) {
            Get-ChildItem $p -File -Include $videoExts
        } else {
            Get-Item $p
        }
    } else {
        Write-Host "Skipping non-existent path: $p" -ForegroundColor Yellow
    }
}

foreach ($in in $inputs) {
    $relDir = $in.DirectoryName
    $outDir = if ($relDir -eq (Get-Location).Path) { $OUTDIR } else { Join-Path $OUTDIR (Split-Path $relDir -Leaf) }
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $out = Join-Path $outDir ($in.BaseName + ".mp4")
    if ((Test-Path $out) -and -not $Overwrite) {
        Write-Host "• already exists, skipping: $out"
        continue
    }
    ffmpeg -hide_banner -loglevel warning $ffOverwrite -i $in.FullName -c:v libx264 -preset $PRESET -crf $CRF -c:a aac -b:a ${AudioKbps}k -movflags +faststart -pix_fmt yuv420p $out
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ wrote $out"
    } else {
        Write-Host "✗ failed on $($in.FullName)"
    }
}
