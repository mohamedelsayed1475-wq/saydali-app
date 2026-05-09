@echo off
echo ========================================================
echo Building AppBundle for Google Play Store...
echo ========================================================
flutter build appbundle --release ^
  --dart-define=SUPABASE_URL=https://kmrszdvsdqfaaksqhnqf.supabase.co/rest/v1 ^
  --dart-define=SUPABASE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImttcnN6ZHZzZHFmYWFrc3FobnFmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc0OTYwNTIsImV4cCI6MjA5MzA3MjA1Mn0.ac8p574OhOG9OPuHzCDOxeHNdEiUkFEtFG_l535Pl3A ^
  --dart-define=DEV_PASS=dev@saydali2026 ^
  --dart-define=ADMIN_CODE_1=ADMIN2026 ^
  --dart-define=ADMIN_CODE_2=DEV@SAYDALI2026 ^
  --dart-define=WEB_PORTAL_URL=https://mohamedelsayed1475-wq.github.io/saydali-app1

echo.
echo ========================================================
echo Build Completed! 
echo You can find the AppBundle (.aab) file at:
echo build\app\outputs\bundle\release\app-release.aab
echo ========================================================
pause
