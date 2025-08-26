param(
    [string]$IMG_EXT = "jpg"
)

$found = $false
Get-ChildItem -Filter *.mp4 | ForEach-Object {
    $found = $true
    $stem = $_.BaseName
    $img = "$stem.$IMG_EXT"
    $txt = "$stem.txt"

    if (-not (Test-Path $img)) {
        Write-Host "→  $($_.Name)  →  $img"
        ffmpeg -hide_banner -loglevel error -y -i $_.FullName -vf "select=eq(n\,0)" -vframes 1 -map 0:v:0 $img
    } else {
        Write-Host "SKIP  image exists: $img"
    }

    if (-not (Test-Path $txt)) {
        New-Item -ItemType File -Path $txt | Out-Null
        Write-Host "made $txt"
    } else {
        Write-Host "SKIP  text exists:  $txt"
    }
}

if (-not $found) {
    Write-Host "No .mp4 files found in: $(Get-Location)"
}
