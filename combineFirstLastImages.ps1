param(
    [string]$IMG_EXT = "jpg",
    [string]$OUTDIR = "pairs",
    [int]$SEP = 2,
    [int]$PAD = 6,
    [string]$SPACE_COLOR = "white",
    [switch]$FORCE
)

function Need($cmd) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "Missing: $cmd"
        exit 1
    }
}

if (Get-Command magick -ErrorAction SilentlyContinue) {
    $IM = "magick"
    $IDENT = "magick identify"
} else {
    Need "convert"
    Need "identify"
    $IM = "convert"
    $IDENT = "identify"
}

New-Item -ItemType Directory -Force -Path $OUTDIR | Out-Null

$combined = 0
$skipped = 0

Get-ChildItem -Filter "*.$IMG_EXT" | Where-Object { $_.Name -notlike "*_lastFrame.$IMG_EXT" } | ForEach-Object {
    $stem = $_.BaseName
    $last = "${stem}_lastFrame.$IMG_EXT"
    if (-not (Test-Path $last)) {
        Write-Host "SKIP  no last frame for: $stem"
        $skipped++
        return
    }
    $out = Join-Path $OUTDIR ("${stem}_first_last.$IMG_EXT")
    if ((Test-Path $out) -and -not $FORCE) {
        Write-Host "SKIP  exists: $out (use -FORCE to overwrite)"
        $skipped++
        return
    }
    $w1h1 = & $IDENT -format "%w %h" $_.FullName
    $w1,$h1 = $w1h1.Split()
    $w2h2 = & $IDENT -format "%w %h" $last
    $w2,$h2 = $w2h2.Split()
    $W = [int]([Math]::Max([int]$w1,[int]$w2))
    $tmp1 = New-TemporaryFile
    $tmp2 = New-TemporaryFile
    $spacer = New-TemporaryFile
    try {
        & $IM $_.FullName -background $SPACE_COLOR -gravity center -extent "${W}x$h1" $tmp1
        & $IM $last -background $SPACE_COLOR -gravity center -extent "${W}x$h2" $tmp2
        $total_h = 2*$PAD + $SEP
        & $IM -size "${W}x$total_h" "xc:$SPACE_COLOR" -fill black -draw "rectangle 0,$PAD $($W-1),$($PAD+$SEP-1)" $spacer
        & $IM $tmp1 $spacer $tmp2 -append -strip $out
    } finally {
        Remove-Item $tmp1,$tmp2,$spacer -ErrorAction Ignore
    }
    Write-Host "MADE  $out"
    $combined++
}

Write-Host "Done. Combined: $combined  |  Skipped: $skipped"
