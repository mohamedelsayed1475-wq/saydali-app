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
flutter build apk --release `
  --dart-define=SUPABASE_URL=https://kmrszdvsdqfaaksqhnqf.supabase.co/rest/v1 `
  --dart-define=SUPABASE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImttcnN6ZHZzZHFmYWFrc3FobnFmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc0OTYwNTIsImV4cCI6MjA5MzA3MjA1Mn0.ac8p574OhOG9OPuHzCDOxeHNdEiUkFEtFG_l535Pl3A `
  --dart-define=DEV_PASS=dev@saydali2026 `
  --dart-define=ADMIN_CODE_1=ADMIN2026 `
  --dart-define=ADMIN_CODE_2=DEV@SAYDALI2026 `
  --dart-define=WEB_PORTAL_URL=https://mohamedelsayed1475-wq.github.io/saydali-app1

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed."
    exit 1
}

Write-Host "Build completed successfully."
