param(
    [string]$ExePath,
    [switch]$TrustCurrentUser
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ExePath)) {
    $sameFolder = Join-Path $PSScriptRoot 'CLM-Windows-Toolkit.exe'
    $distFolder = Join-Path $PSScriptRoot 'dist\CLM-Windows-Toolkit.exe'
    if (Test-Path -LiteralPath $sameFolder -PathType Leaf) { $ExePath = $sameFolder }
    elseif (Test-Path -LiteralPath $distFolder -PathType Leaf) { $ExePath = $distFolder }
    else { throw 'CLM-Windows-Toolkit.exe was not found beside this script or in the dist folder.' }
}

$ExePath = (Resolve-Path -LiteralPath $ExePath).Path

$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
    Where-Object { $_.Subject -like '*Mena Dynamics*' -and $_.HasPrivateKey } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

if (-not $cert) {
    throw 'No CurrentUser code-signing certificate for Mena Dynamics, LLC with a private key was found.'
}

Write-Host 'Using certificate:' -ForegroundColor Cyan
$cert | Select-Object Subject, Thumbprint, NotBefore, NotAfter, HasPrivateKey | Format-List

if ($TrustCurrentUser) {
    $tempCer = Join-Path $env:TEMP 'Mena-Dynamics-CodeSigning.cer'
    try {
        Export-Certificate -Cert $cert -FilePath $tempCer -Force | Out-Null
        Import-Certificate -FilePath $tempCer -CertStoreLocation 'Cert:\CurrentUser\Root' | Out-Null
        Import-Certificate -FilePath $tempCer -CertStoreLocation 'Cert:\CurrentUser\TrustedPublisher' | Out-Null
        Write-Host 'Public certificate trusted for the current user.' -ForegroundColor Green
    } finally {
        Remove-Item -LiteralPath $tempCer -Force -ErrorAction SilentlyContinue
    }
}

$signature = Set-AuthenticodeSignature -FilePath $ExePath -Certificate $cert -HashAlgorithm SHA256
$signature | Format-List Status, StatusMessage, SignerCertificate

if ($signature.Status -ne 'Valid') {
    Write-Warning "The signature was written, but Windows reports status '$($signature.Status)'."
}

Write-Host ''
Write-Host 'SHA256 after signing:' -ForegroundColor Cyan
Get-FileHash -LiteralPath $ExePath -Algorithm SHA256 | Format-Table -AutoSize
Write-Host ''
Write-Host "Signed: $ExePath" -ForegroundColor Green
