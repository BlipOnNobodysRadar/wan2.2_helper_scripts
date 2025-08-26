param(
    [Parameter(Mandatory = $true)][string]$Input
)

if (-not (Test-Path $Input)) {
    Write-Error "Input not found: $Input"
    exit 1
}

$duration = ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 -- $Input 2>$null
if (-not $duration -or $duration -eq "N/A") {
    $duration = ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=nw=1:nk=1 -- $Input 2>$null
}
if (-not $duration -or $duration -eq "N/A") {
    Write-Error "Could not determine video duration for: $Input"
    exit 1
}

$filename = [IO.Path]::GetFileName($Input)
$dir = [IO.Path]::GetDirectoryName($Input)
$base = [IO.Path]::GetFileNameWithoutExtension($filename)

$N = 5
for ($i = 1; $i -le $N; $i++) {
    $ts = [string]::Format("{0:N3}", [double]$duration * ($i/($N+1)))
    $out = Join-Path $dir "${base}_frame${i}.jpg"
    ffmpeg -hide_banner -loglevel error -y -ss $ts -i $Input -frames:v 1 -q:v 2 $out
    Write-Host "✓ Wrote $out at t=${ts}s"
}

Write-Host "Done."
