param(
    [string]$ExePath = (Join-Path $PSScriptRoot 'dist\CLM-Windows-Toolkit.exe'),
    [switch]$TrustCurrentUser
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) {
    throw "Executable not found: $ExePath"
}

$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
    Where-Object { $_.Subject -like '*Mena Dynamics*' -and $_.HasPrivateKey } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

if (-not $cert) {
    throw 'No CurrentUser code-signing certificate for Mena Dynamics, LLC with a private key was found.'
}

Write-Host "Using certificate:" -ForegroundColor Cyan
$cert | Select-Object Subject, Thumbprint, NotBefore, NotAfter, HasPrivateKey | Format-List

if ($TrustCurrentUser) {
    $tempCer = Join-Path $env:TEMP 'Mena-Dynamics-CodeSigning.cer'
    try {
        Export-Certificate -Cert $cert -FilePath $tempCer -Force | Out-Null
        Import-Certificate -FilePath $tempCer -CertStoreLocation 'Cert:\CurrentUser\Root' | Out-Null
        Import-Certificate -FilePath $tempCer -CertStoreLocation 'Cert:\CurrentUser\TrustedPublisher' | Out-Null
        Write-Host 'Public certificate trusted for the current user.' -ForegroundColor Green
    }
    finally {
        Remove-Item -LiteralPath $tempCer -Force -ErrorAction SilentlyContinue
    }
}

$signature = Set-AuthenticodeSignature -FilePath $ExePath -Certificate $cert -HashAlgorithm SHA256
$signature | Format-List Status, StatusMessage, SignerCertificate

if ($signature.Status -ne 'Valid') {
    Write-Warning "The signature was written, but Windows reports status '$($signature.Status)'. If this is a self-signed certificate, run again with -TrustCurrentUser."
}

Write-Host ''
Write-Host 'SHA256 after signing:' -ForegroundColor Cyan
Get-FileHash -LiteralPath $ExePath -Algorithm SHA256 | Format-Table -AutoSize

Write-Host ''
Write-Host "Signed: $ExePath" -ForegroundColor Green
