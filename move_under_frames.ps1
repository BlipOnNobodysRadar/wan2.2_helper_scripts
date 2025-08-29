param(
    [int]$Frames = 102,
    [switch]$Recurse,
    [switch]$DryRun,
    [switch]$Overwrite
)
$destRoot = "under_${Frames}_frames"
New-Item -ItemType Directory -Force -Path $destRoot | Out-Null

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

$opts = @{}
if ($Recurse) { $opts.Recurse = $true }
Get-ChildItem -Path . -Filter *.mp4 -File @opts | ForEach-Object {
    $rel = Resolve-Path -LiteralPath $_.FullName -Relative
    if ($rel -like "$destRoot*") { Write-Host "SKIP  $rel (already in $destRoot)"; return }
    $frames = Count-Frames $_.FullName
    if (-not ($frames -is [int])) { Write-Host "WARN  $rel: unable to read frame count"; return }
    if ($frames -lt $Frames) {
        $relDir = Split-Path $rel
        $destDir = Join-Path $destRoot $relDir
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        Write-Host "MOVE  $rel  ($frames < $Frames) -> $destDir/"
        if (-not $DryRun) {
            $moveArgs = @{}
            if ($Overwrite) { $moveArgs.Force = $true }
            Move-Item -LiteralPath $_.FullName -Destination $destDir @moveArgs
        }
    } else {
        Write-Host "KEEP  $rel  ($frames ≥ $Frames)"
    }
}
