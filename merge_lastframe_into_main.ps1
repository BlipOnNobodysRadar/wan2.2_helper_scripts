Get-ChildItem -Filter *_lastFrame.txt | ForEach-Object {
    $base = $_.Name -replace '_lastFrame.txt$',''
    $main = "$base.txt"
    if (-not (Test-Path $main)) {
        Write-Host "SKIP  no main caption for: $base (expected $main)"
        return
    }
    $tmpMain = New-TemporaryFile
    $tmpLf = New-TemporaryFile
    try {
        (Get-Content $main -Raw) -replace "\n+$","" | Set-Content $tmpMain -NoNewline
        (Get-Content $_.FullName -Raw) -replace "^\n+","" | Set-Content $tmpLf -NoNewline
        $contentMain = Get-Content $tmpMain -Raw
        $contentLf = Get-Content $tmpLf -Raw
        $merged = New-TemporaryFile
        if ($contentMain -and $contentLf) {
            "$contentMain`n`n$contentLf" | Set-Content $merged
        } elseif ($contentMain) {
            $contentMain | Set-Content $merged
        } else {
            $contentLf | Set-Content $merged
        }
        $fixed = New-TemporaryFile
        (Get-Content $merged -Raw) -replace ', ', "`n`n", 1 | Set-Content $fixed
        Move-Item -Force $fixed $main
    } finally {
        Remove-Item $tmpMain,$tmpLf,$merged -ErrorAction Ignore
    }
    Write-Host "MERGED → $main  (+$($_.Name))"
}
