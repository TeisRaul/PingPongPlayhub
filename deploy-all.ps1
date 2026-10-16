# Publică versiunea nouă a Playhub: reguli, funcții și aplicația web.
#
#   powershell -ExecutionPolicy Bypass -File .\deploy-all.ps1           # tot
#   powershell -ExecutionPolicy Bypass -File .\deploy-all.ps1 -WebOnly  # doar aplicația web
#   powershell -ExecutionPolicy Bypass -File .\deploy-all.ps1 -BackendOnly  # doar reguli + funcții
#
# Se oprește la prima eroare (analiză, teste, build sau deploy), ca să nu publici o versiune stricată.
param(
    [switch]$WebOnly,
    [switch]$BackendOnly
)

Set-Location $PSScriptRoot

function Step($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Run($cmd) {
    Write-Host "> $cmd" -ForegroundColor DarkGray
    Invoke-Expression $cmd
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`nOprit: '$cmd' a eșuat (cod $LASTEXITCODE). Nimic nu s-a publicat după acest pas." -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Step "Dependențe"
Run "flutter pub get"

if (-not $BackendOnly) {
    Step "Verificare cod (flutter analyze)"
    Run "flutter analyze --no-fatal-infos"
}

if (-not $WebOnly) {
    Step "Teste funcții"
    Push-Location functions
    Run "npm install --no-audit --no-fund"
    Run "npm test"
    Pop-Location

    Step "Public reguli + funcții"
    Run "firebase deploy --only firestore:rules,functions"
}

if (-not $BackendOnly) {
    Step "Build web"
    Run "flutter build web --release"

    Step "Public aplicația web"
    Run "firebase deploy --only hosting"
}

Write-Host "`nGata. Deschide https://pingpongplayhub1.web.app și reîncarcă pagina (F5) ca să vezi versiunea nouă." -ForegroundColor Green
