param(
    [string]$IMG_EXT = "jpg"
)

function Grab-First($in,$out) {
    ffmpeg -nostdin -hide_banner -loglevel error -y -i $in -vf "select=eq(n\,0)" -vframes 1 -map 0:v:0 $out
}

function Grab-Last($in,$out) {
    $offsets = "-0.001","-0.01","-0.05","-0.1","-0.5","-1"
    foreach ($o in $offsets) {
        Remove-Item $out -ErrorAction Ignore
        ffmpeg -nostdin -hide_banner -loglevel error -y -sseof $o -i $in -map 0:v:0 -frames:v 1 $out
        if ((Test-Path $out) -and (Get-Item $out).Length -gt 0) { return $true }
    }
    $frames = ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 $in
    if ($frames -match '^[0-9]+$' -and [int]$frames -gt 0) {
        $idx = [int]$frames - 1
        Remove-Item $out -ErrorAction Ignore
        ffmpeg -nostdin -hide_banner -loglevel error -y -i $in -vf "select=eq(n\,$idx)" -vframes 1 -map 0:v:0 $out
        if ((Test-Path $out) -and (Get-Item $out).Length -gt 0) { return $true }
    }
    $dur = ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 $in
    if ($dur -match '^[0-9]+(\.[0-9]+)?$') {
        $EPS = if ($env:EPS) { [double]$env:EPS } else { 0.1 }
        $ss = [math]::Max([double]$dur - $EPS,0)
        Remove-Item $out -ErrorAction Ignore
        ffmpeg -nostdin -hide_banner -loglevel error -y -ss $ss -i $in -map 0:v:0 -frames:v 1 $out
        if ((Test-Path $out) -and (Get-Item $out).Length -gt 0) { return $true }
    }
    return $false
}

$found = $false
Get-ChildItem -Filter *.mp4 | ForEach-Object {
    $found = $true
    $stem = $_.BaseName
    $imgFirst = "$stem.$IMG_EXT"
    $txtFirst = "$stem.txt"
    $imgLast = "${stem}_lastFrame.$IMG_EXT"
    $txtLast = "${stem}_lastFrame.txt"

    if (Test-Path $imgFirst) {
        Write-Host "SKIP  image exists: $imgFirst"
    } else {
        Write-Host "→  $($_.Name)  →  first →  $imgFirst"
        Grab-First $_.FullName $imgFirst
        if (-not (Test-Path $imgFirst) -or (Get-Item $imgFirst).Length -eq 0) {
            Write-Host "ERR  first-frame empty: $imgFirst"
            exit 2
        }
    }
    if (-not (Test-Path $txtFirst)) {
        New-Item -ItemType File -Path $txtFirst | Out-Null
        Write-Host "made $txtFirst"
    }

    if (Test-Path $imgLast) {
        Write-Host "SKIP  image exists: $imgLast"
    } else {
        Write-Host "→  $($_.Name)  →  last  →  $imgLast"
        if (-not (Grab-Last $_.FullName $imgLast)) {
            Write-Host "ERR  could not extract last frame for: $($_.Name)" -ForegroundColor Yellow
        }
    }
    if (-not (Test-Path $txtLast)) {
        New-Item -ItemType File -Path $txtLast | Out-Null
        Write-Host "made $txtLast"
    }
}

if (-not $found) {
    Write-Host "No .mp4 files found in: $(Get-Location)"
}
