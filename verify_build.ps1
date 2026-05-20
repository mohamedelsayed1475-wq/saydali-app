# verify_build.ps1
# This script cleans the Flutter project, fetches dependencies, runs static analysis, and builds a release APK.

# Ensure we are in the project root directory
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

Write-Host "🔧 Starting Flutter clean..."
flutter clean

Write-Host "📦 Fetching dependencies..."
flutter pub get

Write-Host "🔍 Running static analysis..."
flutter analyze
if ($LASTEXITCODE -ne 0) {
    Write-Error "Static analysis failed. aborting build."
    exit $LASTEXITCODE
}

Write-Host "🚀 Building release APK..."
flutter build apk --release
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Build completed successfully."
} else {
    Write-Error "Build failed with exit code $LASTEXITCODE."
    exit $LASTEXITCODE
}
