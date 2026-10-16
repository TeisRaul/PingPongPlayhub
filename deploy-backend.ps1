# Publica backend-ul Playhub: secrete, reguli Firestore si Cloud Functions.
# Rulare (din folderul proiectului, in PowerShell):
#   powershell -ExecutionPolicy Bypass -File .\deploy-backend.ps1
# Cere planul Blaze activ pe proiectul pingpongplayhub1.
# Valorile secretelor le scrii tu cand Firebase ti le cere; scriptul nu le salveaza nicaieri.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Step($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }

Step "Verific Firebase CLI"
if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
    Write-Host "Firebase CLI lipseste. Instaleaza-l cu: npm install -g firebase-tools" -ForegroundColor Red
    exit 1
}
firebase login --reuse  # daca nu esti logat, deschide browserul
firebase use pingpongplayhub1

Step "Secrete (scrie valoarea cand ti se cere; Enter pe 'n' ca sa sari peste unul deja setat)"
$secrets = @(
    @{ Name = "STRIPE_SECRET_KEY";     Hint = "cheia de TEST din Stripe > Developers > API keys (sk_test_...)" },
    @{ Name = "SMTP_URL";              Hint = "ex: smtps://adresa%40gmail.com:parolaaplicatie@smtp.gmail.com:465" },
    @{ Name = "STRIPE_WEBHOOK_SECRET"; Hint = "deocamdata orice text; il inlocuiesti dupa ce creezi webhook-ul in Stripe (whsec_...)" }
)
foreach ($s in $secrets) {
    Write-Host "`n$($s.Name): $($s.Hint)" -ForegroundColor Yellow
    $answer = Read-Host "Setezi $($s.Name) acum? (d/n)"
    if ($answer -match '^[dDyY]') {
        firebase functions:secrets:set $s.Name
    }
}

Step "Instalez dependintele functiilor"
Push-Location functions
npm install
npm test
Pop-Location

Step "Public regulile si functiile"
firebase deploy --only firestore:rules,functions

Write-Host "`nGata. Adresa functiei de webhook Stripe e in output-ul de mai sus (sau in Firebase Console > Functions)." -ForegroundColor Green
Write-Host "Dupa ce creezi webhook-ul in Stripe: firebase functions:secrets:set STRIPE_WEBHOOK_SECRET, apoi ruleaza din nou scriptul (raspunde 'n' la celelalte secrete)." -ForegroundColor Green
