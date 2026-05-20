# verify_build.ps1
# Clean and run build using standard ASCII characters only

Write-Host "Starting Flutter clean..."
flutter clean

Write-Host "Fetching dependencies..."
flutter pub get

Write-Host "Running static analysis..."
flutter analyze

if ($LASTEXITCODE -ne 0) {
    Write-Host "Static analysis failed."
    exit 1
}

Write-Host "Building release APK..."
flutter build apk --release

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed."
    exit 1
}

Write-Host "Build completed successfully."
