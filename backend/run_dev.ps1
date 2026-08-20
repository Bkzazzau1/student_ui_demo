param(
  [string]$Token = 'local-student-token',
  [string]$StudentId = 'KASU/STU/2026/001'
)

$ErrorActionPreference = 'Stop'
$env:KSLAS_API_TOKENS_JSON = @{ $Token = $StudentId } | ConvertTo-Json -Compress
$env:KSLAS_IDENTITY_DB = Join-Path $PSScriptRoot 'data\identity.sqlite3'
$env:KSLAS_BACKEND_HOST = '127.0.0.1'
$env:KSLAS_BACKEND_PORT = '8080'
Set-Location (Split-Path $PSScriptRoot -Parent)
python -m backend.main
