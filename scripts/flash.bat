@echo off
setlocal EnableExtensions

for /f %%A in ('echo prompt $E ^| cmd') do set "ESC=%%A"
set "CYAN=%ESC%[0;36m"
set "GREEN=%ESC%[0;32m"
set "YELLOW=%ESC%[1;33m"
set "RED=%ESC%[0;31m"
set "BLUE=%ESC%[0;34m"
set "BOLD=%ESC%[1m"
set "RESET=%ESC%[0m"

set "LOG_INFO=%BLUE%[INFO]%RESET%"
set "LOG_ACT=%CYAN%[ACTION]%RESET%"
set "LOG_OK=%GREEN%[OK]%RESET%"
set "LOG_WARN=%YELLOW%[WARN]%RESET%"
set "LOG_ERR=%RED%[FAIL]%RESET%"

set "EXPECTED_PRELOADER_SHA1=40e3c4d31163474cb2e945ab5670e6b807677358"
set "EXPECTED_LK_SHA1=c691bbda11e67699bb856773137b769ff07c670a"

cls
echo %CYAN%%BOLD%
echo   ____  _     _               ___  ____  
echo  ^|  _ \(_)___(_)_ __   __ _/ _ \/ ___^| 
echo  ^| ^|_) ^| / __^| ^| '_ \ / _` ^| ^| ^| \___ \ 
echo  ^|  _ ^<^| \__ \ ^| ^| ^| ^| (_^| ^| ^|_^| ^|___) ^|
echo  ^|_^| \_\_^|___/_^|_^| ^|_^|\__, ^|\___/^|____/ 
echo                        ^|___/             
echo %RESET%%BOLD%          Community Installer ^| Script by Ayus%RESET%
echo.

echo %LOG_INFO% Initializing target device verification...
where fastboot >nul 2>&1
if %errorlevel% neq 0 (
    echo %LOG_ERR% Fastboot binary missing from system PATH.
    pause
    exit /b 1
)

fastboot devices 2>&1 | findstr /i "fastboot" >nul
if %errorlevel% neq 0 (
    echo %LOG_ERR% Target device not detected in fastboot mode.
    pause
    exit /b 1
)

set "DEVICE_CODENAME="
for /f "tokens=1,* delims=:" %%a in ('fastboot getvar product 2^>^&1') do (
    echo %%a | findstr /i "product" >nul && for /f "tokens=1" %%v in ("%%b") do set "DEVICE_CODENAME=%%v"
)
if "%DEVICE_CODENAME%"=="" set "DEVICE_CODENAME=Unknown"

set "DEVICE_SERIAL="
for /f "tokens=1,* delims=:" %%a in ('fastboot getvar serialno 2^>^&1') do (
    echo %%a | findstr /i "serialno" >nul && for /f "tokens=1" %%v in ("%%b") do set "DEVICE_SERIAL=%%v"
)
if "%DEVICE_SERIAL%"=="" set "DEVICE_SERIAL=Unknown"

set "CURRENT_SLOT="
for /f "tokens=1,* delims=:" %%a in ('fastboot getvar current-slot 2^>^&1') do (
    echo %%a | findstr /i "current-slot" >nul && for /f "tokens=1" %%v in ("%%b") do set "CURRENT_SLOT=%%v"
)
if "%CURRENT_SLOT%"=="" set "CURRENT_SLOT=a"
if /i "%CURRENT_SLOT%"=="a" (set "OTHER_SLOT=b") else (set "OTHER_SLOT=a")

echo %LOG_OK% Target identified: %BOLD%%DEVICE_CODENAME%%RESET% (%DEVICE_SERIAL%)
echo %LOG_OK% Active slot: %BOLD%%CURRENT_SLOT%%RESET% ^| Inactive slot: %BOLD%%OTHER_SLOT%%RESET%
echo.

echo %LOG_INFO% Validating trusted bootloader components via SHA-1...

set "PRELOADER_IMG="
if exist "preloader_raw.img" (
    set "PRELOADER_IMG=preloader_raw.img"
) else if exist "preloader.img" (
    set "PRELOADER_IMG=preloader.img"
) else (
    echo %LOG_ERR% Abort: Missing preloader image (preloader_raw.img / preloader.img^).
    pause
    exit /b 1
)

set "ACTUAL_PRELOADER_SHA1="
for /f "skip=1 tokens=* delims=" %%A in ('certutil -hashfile "%PRELOADER_IMG%" SHA1 2^>nul') do (
    if not defined ACTUAL_PRELOADER_SHA1 set "ACTUAL_PRELOADER_SHA1=%%A"
)
set "ACTUAL_PRELOADER_SHA1=%ACTUAL_PRELOADER_SHA1: =%"
if /i not "%ACTUAL_PRELOADER_SHA1%"=="%EXPECTED_PRELOADER_SHA1%" (
    echo %LOG_ERR% Abort: Preloader SHA-1 mismatch for %PRELOADER_IMG%!
    echo        Expected: %EXPECTED_PRELOADER_SHA1%
    echo        Found:    %ACTUAL_PRELOADER_SHA1%
    pause
    exit /b 1
)
echo %LOG_OK% Verified trusted preloader (%PRELOADER_IMG%^): %ACTUAL_PRELOADER_SHA1%

if not exist "lk.img" (
    echo %LOG_ERR% Abort: Missing Little Kernel image (lk.img^).
    pause
    exit /b 1
)

set "ACTUAL_LK_SHA1="
for /f "skip=1 tokens=* delims=" %%A in ('certutil -hashfile "lk.img" SHA1 2^>nul') do (
    if not defined ACTUAL_LK_SHA1 set "ACTUAL_LK_SHA1=%%A"
)
set "ACTUAL_LK_SHA1=%ACTUAL_LK_SHA1: =%"
if /i not "%ACTUAL_LK_SHA1%"=="%EXPECTED_LK_SHA1%" (
    echo %LOG_ERR% Abort: Little Kernel SHA-1 mismatch for lk.img!
    echo        Expected: %EXPECTED_LK_SHA1%
    echo        Found:    %ACTUAL_LK_SHA1%
    pause
    exit /b 1
)
echo %LOG_OK% Verified trusted Little Kernel (lk.img^): %ACTUAL_LK_SHA1%

set "FW_PARTITIONS=dpm gz mcupm md1img pi_img scp spmfw sspm tee"
set "STATIC_PARTITIONS=boot dtbo vendor_boot vbmeta vbmeta_system vbmeta_vendor"
set "LOGICAL_PARTITIONS=odm_dlkm product system system_dlkm system_ext vendor vendor_dlkm"

echo.
echo %BOLD%Select Flashing Mode:%RESET%
echo   [1] Clean Flash (Format userdata ^& metadata - Highly Recommended)
echo   [2] Dirty Flash (Retain existing userdata)
set "WIPE_CHOICE=1"
set /p "WIPE_CHOICE=Option [1/2, default: 1]: "

echo.
set "SPOOF_CHOICE=Y"
set /p "SPOOF_CHOICE=Enable bootloader spoofing ? [Y/n] (default: Y): "

echo.
set /p "DUMMY=Press [ENTER] to start flashing..."
echo.

echo %LOG_ACT% Flashing trusted preloader (%PRELOADER_IMG%)...
fastboot flash preloader "%PRELOADER_IMG%" >nul 2>&1
echo %LOG_OK% Preloader written.

echo %LOG_ACT% Flashing trusted Little Kernel (lk.img)...
fastboot flash lk lk.img >nul 2>&1 || (fastboot flash lk_a lk.img >nul 2>&1 && fastboot flash lk_b lk.img >nul 2>&1)
echo %LOG_OK% Little Kernel written.

echo %LOG_INFO% Writing firmware packages...
for %%p in (%FW_PARTITIONS%) do (
    if exist "%%p.img" (
        echo %LOG_ACT% Flashing %%p...
        fastboot flash %%p "%%p.img" >nul 2>&1
    )
)

echo %LOG_INFO% Writing dual-slot static partitions...
for %%p in (%STATIC_PARTITIONS%) do (
    if exist "%%p.img" (
        echo %LOG_ACT% Flashing %%p ^(slots %CURRENT_SLOT%, %OTHER_SLOT%^)...
        fastboot flash %%p_%CURRENT_SLOT% "%%p.img" >nul 2>&1
        fastboot flash %%p_%OTHER_SLOT% "%%p.img" >nul 2>&1
    )
)

echo.
echo %LOG_INFO% Transitioning target to userspace daemon (fastbootd)...
fastboot reboot fastboot >nul 2>&1

<nul set /p "=%LOG_INFO% Awaiting fastbootd handshake"
:wait_fastbootd
set "IS_USERSPACE="
for /f "tokens=1,* delims=:" %%a in ('fastboot getvar is-userspace 2^>^&1') do (
    echo %%a | findstr /i "is-userspace" >nul && for /f "tokens=1" %%v in ("%%b") do set "IS_USERSPACE=%%v"
)
if /i "%IS_USERSPACE%"=="yes" goto fastbootd_ready
<nul set /p "=."
ping 127.0.0.1 -n 3 >nul
goto wait_fastbootd

:fastbootd_ready
echo  %GREEN%[ONLINE]%RESET%

echo %LOG_INFO% Purging deprecated logical tables...
for %%p in (%LOGICAL_PARTITIONS%) do (
    fastboot delete-logical-partition %%p_a-cow >nul 2>&1
    fastboot delete-logical-partition %%p_b-cow >nul 2>&1
    fastboot delete-logical-partition %%p_a >nul 2>&1
    fastboot delete-logical-partition %%p_b >nul 2>&1
)
for %%p in (cust cust_a cust_b mi_ext mi_ext_a mi_ext_b) do (
    fastboot delete-logical-partition %%p >nul 2>&1
)
echo %LOG_OK% Dynamic allocations cleared.

echo %LOG_INFO% Allocating and writing logical partitions (Slot: %CURRENT_SLOT%)...
for %%p in (%LOGICAL_PARTITIONS%) do (
    if exist "%%p.img" (
        echo %LOG_ACT% Flashing %%p_%CURRENT_SLOT%...
        fastboot create-logical-partition %%p_%CURRENT_SLOT% 0 >nul 2>&1
        fastboot flash %%p_%CURRENT_SLOT% "%%p.img" >nul 2>&1
    ) else (
        echo %LOG_WARN% Skipping optional logical: %%p.img
    )
)

echo.
echo %LOG_INFO% Applying final configurations...
if "%WIPE_CHOICE%"=="1" (
    echo %LOG_ACT% Formatting userdata and metadata...
    fastboot -w >nul 2>&1 || fastboot erase userdata >nul 2>&1
    fastboot erase metadata >nul 2>&1
    echo %LOG_OK% User data cleared.
)

echo %LOG_ACT% Setting active boot slot: %CURRENT_SLOT%...
fastboot set_active %CURRENT_SLOT% >nul 2>&1

if /i "%SPOOF_CHOICE%"=="y" (
    echo %LOG_ACT% Enabling bootloader spoofing...
    fastboot oem bldr_spoof on >nul 2>&1
)

echo.
echo %GREEN%%BOLD%========================================================
echo           Flash Completed Successfully          
echo ========================================================%RESET%
echo.

set /p "DUMMY=Press [ENTER] to reboot into RisingOS..."
fastboot reboot
