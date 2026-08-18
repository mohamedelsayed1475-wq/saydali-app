@echo off
echo ========================================================
echo Building AppBundle for Google Play Store...
echo ========================================================
flutter build appbundle --release ^
  --dart-define=DEV_PASS=dev@saydali2026 ^
  --dart-define=ADMIN_CODE_1=ADMIN2026 ^
  --dart-define=ADMIN_CODE_2=DEV@SAYDALI2026

echo.
echo ========================================================
echo Build Completed! 
echo You can find the AppBundle (.aab) file at:
echo build\app\outputs\bundle\release\app-release.aab
echo ========================================================
pause
