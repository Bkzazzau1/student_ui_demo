$ErrorActionPreference = 'Stop'

$flutter = 'C:\Users\user\development\flutter\bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutter)) {
    throw "Flutter was not found at $flutter"
}

Write-Warning 'Starting K-SLAS in DEBUG TEST OVERRIDE mode. Do not use this build for a real examination.'

& $flutter run -d windows --debug `
    --dart-define=KSLAS_ALLOW_EXAM_OVERRIDE=true `
    --dart-define=KSLAS_ALLOW_AUDIO_REVIEW_OVERRIDE=true `
    --dart-define=KSLAS_ALLOW_SYSTEM_REVIEW_OVERRIDE=true `
    --dart-define=KSLAS_ALLOW_LOCAL_START_APPROVAL=true `
    --dart-define=KSLAS_ALLOW_LIVE_AUDIO_MONITOR_OVERRIDE=true `
    --dart-define=KSLAS_ALLOW_MONITORING_REVIEW_OVERRIDE=true `
    --dart-define=KSLAS_RELIEVE_SYSTEM_LOCKDOWN=true `
    --dart-define=KSLAS_REAL_EXAM_MODE=false

