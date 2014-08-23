:: Purpose:       Runs a series of cleaners and anti-virus engines to clean up/disinfect a PC
::                  Kevin Flynn:  "Who's that guy?"
::                  Program:      "That's Tron. He fights for the Users."
:: Requirements:  1. Administrator access
::                2. Safe mode is strongly recommended
:: Author:        vocatus on reddit.com/r/sysadmin ( vocatus.gate@gmail.com ) // PGP key ID: 0x82A211A2
:: Version:       3.0.0 + wrap-up:           Add collection of Vipre and MBAM logs (deposit them in LOGPATH directory). Thanks to reddit.com/user/swtester
::                      + tron.bat:          Add rudimentary automatic update check. Will notify you if a newer version is on the official repo server
::                      - tron.bat:          Remove outdated reference to Emsisoft's a2cmd in welcome screen. Thanks to reddit.com/user/swtester
::                      / tron.bat:          Rename SCRIPT_UPDATED to SCRIPT_DATE
::                      * prep and checks:   Beefed up OS detection routine to support various improvements
::                      * stage_2_disinfect: Switch order of Vipre and Sophos to avoid Sophos deleting Vipre's quarantine, preventing recovery. Thanks to reddit.com/user/swtester
::                      + stage_3_de-bloat:  Add removal of default Metro apps (Windows 8/8.1 only)
::
:: Usage:         Run this script in Safe Mode as an Administrator and reboot when finished. That's it.
::
::                Optional command-line flags (can be combined):
::                      -a  Automatic/silent mode (no welcome screen)
::                      -c  Config dump (display current config. Can be used with other flags
::                          to see what WOULD happen, but script will never execute if this 
::                          flag is used)
::                      -d  Dry run (run through script without executing any jobs)
::                      -h  Display help text
::                      -p  Preserve power settings (don't reset power settings to default)
::                      -r  Reboot (auto-reboot 30 seconds after Tron completes)
::                      -s  Skip defrag (force Tron to ALWAYS skip Stage 5 defrag)
::
::                If you don't like the defaults and don't want to use the command-line, edit the variables below to change the script defaults. All command-line flags override their respective default settings.

::                Godspeed
SETLOCAL


:::::::::::::::
:: VARIABLES :: --------------- These are the defaults. Change them if you so desire. -------- ::
:::::::::::::::
:: Rules for variables:
::  * NO quotes!                       (bad:  "c:\directory\path"       )
::  * NO trailing slashes on the path! (bad:   c:\directory\            )
::  * Spaces are okay                  (okay:  c:\my folder\with spaces )
::  * Network paths are okay           (okay:  \\server\share name      )
::                                     (       \\172.16.1.5\share name  )

:: ! All variables specified here are overridden if their respective command-line flag is used

:: Log settings
set LOGPATH=%SystemDrive%\Logs
set LOGFILE=tron.log

:: Post-run delay (in seconds) before rebooting. Set to 0 to disable auto-reboot.
set AUTO_REBOOT_DELAY=0

:: Set to anything but "no" in order to skip defrag regardless whether the system drive is an SSD or not.
:: Leave as "no" to let the script auto-detect SSDs
set SKIP_DEFRAG=no

:: AUTORUN = automatic/silent execution (no welcome screen)
:: DRY_RUN = run through script but skip all actual actions (test mode)
:: PRESERVE_POWER_SCHEME = Preserve the active power scheme. Default is to reset power scheme to Windows defaults at the end of Tron.
set AUTORUN=no
set DRY_RUN=no
set PRESERVE_POWER_SCHEME=no




:: --------------------------- Don't edit anything below this line --------------------------- ::




:::::::::::::::::::::
:: PREP AND CHECKS ::
:::::::::::::::::::::
@echo off && cls && echo. && echo  Loading...
color 0f
set SCRIPT_VERSION=3.0.0
set SCRIPT_DATE=2014-08-23
title TRON v%SCRIPT_VERSION% (%SCRIPT_DATE%)

:: Get the date into ISO 8601 standard date format (yyyy-mm-dd) so we can use it 
FOR /f %%a in ('WMIC OS GET LocalDateTime ^| find "."') DO set DTS=%%a
set CUR_DATE=%DTS:~0,4%-%DTS:~4,2%-%DTS:~6,2%

:: Preload variables for use and comparison later
set REPO_SCRIPT_VERSION=0
set REPO_SCRIPT_DATE=0
set HELP=no
set CONFIG_DUMP=no
set REPO_URL=http://bmrf.org/repos/tron/
set REPO_SYNC_KEY=BYQYYECDOJPXYA2ZNUDWDN34O2GJHBM47

:: Get in the correct drive (~d0). This is sometimes needed when running from a thumb drive
%~d0 2>NUL
:: Get in the correct path (~dp0). This is useful if we start from a network share. This converts CWD to a drive letter
pushd %~dp0 2>NUL

:: Force WMIC location in case the system PATH is messed up
set WMIC=%WINDIR%\system32\wbem\wmic.exe

:: PREP JOB: Detect the version of Windows we're on. This determines a few things later in the script, such as which versions of SFC and powercfg.exe we run, as well as whether or not to attempt removal of Windows 8/8.1 metro apps
:detect_os
set WIN_VER=undetected
for /f "tokens=3*" %%i IN ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v ProductName ^| Find "ProductName"') DO set WIN_VER=%%i %%j

:: PREP JOB: Detect Solid State hard drives (determines if post-run defrag executes or not)
:: Basically we use a trick to set the global SSD_DETECTED variable outside of the setlocal block by stacking it on the same line so it gets executed along with ENDLOCAL
:: Method by /u/Suddenly_Engineer and /u/Aberu. Big time thanks for helping with this.
:detect_ssd
pushd resources\stage_5_optimize\defrag
set SSD_DETECTED=no
setlocal enabledelayedexpansion
for /f "tokens=1" %%i in ('smartctl --scan') do (
	smartctl %%i -a | find /i "Solid State" >NUL
	if "!ERRORLEVEL!"=="0" endlocal disabledelayedexpansion && set SSD_DETECTED=yes&& goto detect_safe_mode
	)

for /f "tokens=1" %%i in ('smartctl --scan') do (
	smartctl %%i -a | find /i "SSD" >NUL
	if "!ERRORLEVEL!"=="0" endlocal disabledelayedexpansion && set SSD_DETECTED=yes&& goto detect_safe_mode
	)

for /f "tokens=1" %%i in ('smartctl --scan') do (
	smartctl %%i -a | find /i "RAID" >NUL
	if "!ERRORLEVEL!"=="0" endlocal disabledelayedexpansion && set SSD_DETECTED=yes&& goto detect_safe_mode
	)
endlocal disabledelayedexpansion


:: PREP JOB: Detect if the system is in Safe Mode
:detect_safe_mode
popd
set SAFE_MODE=no
if /i "%SAFEBOOT_OPTION%"=="MINIMAL" set SAFE_MODE=yes
if /i "%SAFEBOOT_OPTION%"=="NETWORK" set SAFE_MODE=yes


:: PREP JOB: Make the log directory and file if they don't already exist
if not exist %LOGPATH% mkdir %LOGPATH%
if not exist %LOGPATH%\%LOGFILE% echo. > %LOGPATH%\%LOGFILE%


:: PREP JOB: Check and parse command-line arguments
for %%i in (%*) do (
	if /i %%i==-a set AUTORUN=yes
	if /i %%i==-c set CONFIG_DUMP=yes
	if /i %%i==-d set DRY_RUN=yes
	if /i %%i==-h set HELP=yes
	if /i %%i==-p set PRESERVE_POWER_SCHEME=yes
	if /i %%i==-r set AUTO_REBOOT_DELAY=30
	if /i %%i==-s set SKIP_DEFRAG=yes
	)


:: PREP JOB: Execute help if requested
if %HELP%==yes (
	cls
	echo. 
	echo  Tron v%SCRIPT_VERSION% ^(%SCRIPT_DATE%^)
	echo  Author: vocatus on reddit.com/r/sysadmin
	echo.
	echo   Usage: %0%.bat ^[-a -c -d -p -r -s^] ^| ^[-h^]
	echo.
	echo   Optional flags ^(can be combined^):
	echo    -a  Automatic/silent mode ^(no welcome screen^)
 	echo    -c  Config dump ^(display current config. Can be used with other
	echo        flags to see what WOULD happen, but script will never execute
	echo        if this flag is used^)
	echo    -d  Dry run ^(run through script but don't execute any jobs^)
	echo    -p  Preserve power settings ^(don't reset power settings to default^)
	echo    -r  Reboot ^(auto-reboot 30 seconds after Tron completes^)
	echo    -s  Skip defrag ^(force Tron to ALWAYS skip Stage 5 defrag^)
 	echo.
	echo   Misc flags ^(must be used alone^)
	echo    -h  Display this help text
	echo.
	exit /b 0
	)


:: PREP JOB: Update check (check if we're running the latest version)
pushd resources\stage_0_prep\check_update
:: Skip this job if we're doing a dry run
if "%DRY_RUN%"=="yes" goto skip_update_check

:: We use wget to fetch md5sums.txt from the repo and parse through it, extracting the latest version number and release date from last line of the file (which is always the latest release)
:: Get the file from the repo
wget %REPO_URL%/md5sums.txt 2>NUL
:: Assuming there was no error, go ahead and extract version number into REPO_SCRIPT_VERSION, and release date into REPO_SCRIPT_DATE
if %ERRORLEVEL%==0 (
	for /f "tokens=1,2,3 delims= " %%a in (md5sums.txt) do set WORKING=%%c
	for /f "tokens=1,2,3,4 delims= " %%a in (md5sums.txt) do set WORKING2=%%d
	)
set REPO_SCRIPT_VERSION=%WORKING:~1,6%
set REPO_SCRIPT_DATE=%WORKING2:~1,10%

:: clean up
if exist md5sum* del md5sum*

:: reset the window title since wget clobbers it
title TRON v%SCRIPT_VERSION% (%SCRIPT_DATE%)

:: Notify if an update was found
if %SCRIPT_VERSION% LSS %REPO_SCRIPT_VERSION% (
	color 8a
	cls
	echo.
	echo  ! A newer version of Tron is available on the official repo.
	echo.
	echo    Your version:   %SCRIPT_VERSION% ^(%SCRIPT_DATE%^)
	echo    Latest version: %REPO_SCRIPT_VERSION% ^(%REPO_SCRIPT_DATE%^)
	echo.
	echo    Strongly recommend grabbing latest version before continuing.
	echo.
	echo    Option 1: Sync directly from the BT Sync repo using this 
	echo    read-only key:
	echo     %REPO_SYNC_KEY%
	echo.
	echo    Option 2: Download the latest .7z static pack here:
	echo     %REPO_URL%
	echo.
	pause
	color 0f
	)
	
:skip_update_check
popd


:: PREP JOB: Execute config dump if requested
if %CONFIG_DUMP%==yes (
	cls
	echo.
	echo   Tron v%SCRIPT_VERSION% ^(%SCRIPT_DATE%^) config dump
	echo.
	echo   Command-line arguments:
	echo    %*
	echo.
	echo   Variable values ^(user-set^):
	echo    AUTORUN:                %AUTORUN%
	echo    AUTO_REBOOT_DELAY:      %AUTO_REBOOT_DELAY%
	echo    CONFIG_DUMP:            %CONFIG_DUMP%
	echo    DRY_RUN:                %DRY_RUN%
	echo    LOGPATH:                %LOGPATH%
	echo    LOGFILE:                %LOGFILE%
	echo    PRESERVE_POWER_SCHEME:  %PRESERVE_POWER_SCHEME%
	echo    SKIP_DEFRAG:            %SKIP_DEFRAG%
	echo.
	echo   Variable values ^(script-internal^):
	echo    CUR_DATE:               %CUR_DATE%
	echo    DTS:                    %DTS%
	echo    HELP:                   %HELP%
	echo    SAFE_MODE:              %SAFE_MODE%
	echo    SAFEBOOT_OPTION:        %SAFEBOOT_OPTION%
	echo    SSD_DETECTED:           %SSD_DETECTED% 
	echo    TEMP:                   %TEMP%
	echo    TIME:                   %TIME%
	echo    PROCESSOR_ARCHITECTURE: %PROCESSOR_ARCHITECTURE%
	echo    REPO_SCRIPT_DATE:       %REPO_SCRIPT_DATE%
	echo    REPO_SCRIPT_VERSION:    %REPO_SCRIPT_VERSION%
	echo    REPO_SYNC_KEY:          %REPO_SYNC_KEY%
	echo    REPO_URL:               %REPO_URL%
	echo    SCRIPT_VERSION:         %SCRIPT_VERSION%
	echo    SCRIPT_DATE:            %SCRIPT_DATE%
	echo    WIN_VER:                %WIN_VER%
	echo    WMIC:                   %WMIC%
	echo.
	exit /b 0
	)


:: PREP JOB: Act on autorun flag if it got set. Basically just skip the menu
if /i %AUTORUN%==yes goto execute_jobs


::::::::::::::::::::
:: WELCOME SCREEN ::
::::::::::::::::::::
color 0f
cls
echo  *****************  TRON v%SCRIPT_VERSION% (%SCRIPT_DATE%)  ****************
echo  * Script to automate a series of cleanup/disinfect tools.   *
echo  * Author: vocatus on reddit.com/r/sysadmin                  *
echo  *                                                           *
echo  * Stage:         Tools:                                     *
echo  * --------------------------------------------------------- *
echo  *  0 Prep:       rkill, WMI repair, sysrestore clean        *
echo  *  1 TempClean:  BleachBit, CCleaner                        *
echo  *  2 Disinfect:  Sophos, Vipre, MBAM, sfc /scannow          *
echo  *  3 De-bloat:   Remove OEM bloatware apps (inc. Metro)     *
echo  *  4 Patch:      Update 7-Zip/Java/Flash/Windows            *
echo  *  5 Optimize:   chkdsk, defrag %SystemDrive% (non-SSD only)           *
echo  *                                                           *
echo  * \resources\stage_6_manual_tools contains additional tools *
echo  * which may be run manually if necessary.                   *
echo  *************************************************************
echo.
:: So ugly it makes me cry
echo  Current settings (edit script to change):
echo     Log location:            %LOGPATH%\%LOGFILE%
if not "%AUTO_REBOOT_DELAY%"=="0" echo     Post-clean reboot delay: %AUTO_REBOOT_DELAY% seconds
if "%AUTO_REBOOT_DELAY%"=="0" echo     Post-clean reboot delay: disabled
if "%SSD_DETECTED%"=="yes" echo     SSD detected?            %SSD_DETECTED% (stage_5 skipped)
if "%SSD_DETECTED%"=="no" echo     SSD detected?            %SSD_DETECTED%
if "%SAFEBOOT_OPTION%"=="MINIMAL" echo     Safe mode?               %SAFE_MODE%, without Networking
if "%SAFEBOOT_OPTION%"=="NETWORK" echo     Safe mode?               %SAFE_MODE%, with Networking (ideal)
if not "%SAFE_MODE%"=="yes" echo     Safe mode?               %SAFE_MODE% (not ideal)
if not "%SKIP_DEFRAG%"=="no" (
	echo   ! SKIP_DEFRAG set^; skipping stage_5_optimize ^(defrag^)
	echo     Runtime estimate:        4-6 hours
	goto welcome_screen_trailer
	)
if "%SSD_DETECTED%"=="yes" echo     Runtime estimate:        4-6 hours
if not "%SSD_DETECTED%"=="yes" echo     Runtime estimate:        6-8 hours
if %DRY_RUN%==yes echo   ! DRY_RUN set; will not execute any jobs
echo.
:welcome_screen_trailer
pause

:::::::::::::::::::::
:: SAFE MODE CHECK ::
:::::::::::::::::::::
:: Check if we're in safe mode
if not "%SAFE_MODE%"=="yes" (
		color 0c
		cls
		echo.
		echo  WARNING
		echo.
		echo  The system is not in safe mode. Tron functions best
		echo  in "Safe Mode with Networking" in order to download
		echo  Windows and anti-virus updates.
		echo.
		echo  Tron will still function, but rebooting to "Safe Mode
		echo  with Networking" is STRONGLY recommended.
		echo.
		pause
		cls
		)

:: Check if we have network support
if /i  "%SAFEBOOT_OPTION%"=="MINIMAL" (
		color 0e
		cls
		echo.
		echo  NOTE
		echo.
		echo  The system is in Safe Mode without Network support.
		echo  Tron functions best in "Safe Mode with Networking" in
		echo  order to download Windows and anti-virus updates.
		echo.
		echo  Tron will still function, but rebooting to "Safe Mode
		echo  with Networking" is recommended.
		echo.
		pause
		cls
		)
		
::::::::::::::::::::::::
:: ADMIN RIGHTS CHECK ::
::::::::::::::::::::::::
:: thanks to /u/agent-squirrel
:: Because command prompts always start with Admin rights when the system is in Safe Mode, we skip this check if we're in Safe Mode
if not "%SAFE_MODE%"=="yes" (
	net session >nul 2>&1
	if not "%ERRORLEVEL%"=="0" (
		color cf
		cls
		echo.
		echo  ERROR
		echo.
		echo  Tron doesn't think it is running as an Administrator.
		echo  Tron MUST be run with full Administrator rights to 
		echo  function correctly.
		echo.
		pause
	)
)

::::::::::::::::::
:: EXECUTE JOBS ::
::::::::::::::::::
:execute_jobs
cls
color 0f
title TRON v%SCRIPT_VERSION% [stage_0_prep]
:: Create the log header for this job
echo ------------------------------------------------------------------------------->> %LOGPATH%\%LOGFILE%
echo -------------------------------------------------------------------------------
echo  %CUR_DATE% %TIME%  TRON v%SCRIPT_VERSION% (%SCRIPT_DATE%), %PROCESSOR_ARCHITECTURE% architecture detected>> %LOGPATH%\%LOGFILE%
echo  %CUR_DATE% %TIME%  TRON v%SCRIPT_VERSION% (%SCRIPT_DATE%), %PROCESSOR_ARCHITECTURE% architecture detected
echo                          Executing as %USERDOMAIN%\%USERNAME% on %COMPUTERNAME%>> %LOGPATH%\%LOGFILE%
echo                          Executing as %USERDOMAIN%\%USERNAME% on %COMPUTERNAME%
echo ------------------------------------------------------------------------------->> %LOGPATH%\%LOGFILE%
echo -------------------------------------------------------------------------------


:::::::::::::::::::
:: STAGE 0: PREP ::
:::::::::::::::::::
:stage_0_prep
pushd resources\stage_0_prep
echo %CUR_DATE% %TIME%   Launching stage_0_prep jobs...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching stage_0_prep jobs...

:: JOB: rkill
echo %CUR_DATE% %TIME%    Launching job 'rkill'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Launching job 'rkill'...
pushd rkill
	if %DRY_RUN%==yes goto skip_rkill
	if '%PROCESSOR_ARCHITECTURE%'=='AMD64' rkill64.exe -s -l "%LOGPATH%\tron_rkill.log"
	if '%PROCESSOR_ARCHITECTURE%'=='x86' rkill.exe -s -l "%LOGPATH%\tron_rkill.log"
	type "%LOGPATH%\tron_rkill.log" >> "%LOGPATH%\%LOGFILE%"
	del "%LOGPATH%\tron_rkill.log"
	if exist "%HOMEDRIVE%\%HOMEPATH%\Desktop\Rkill.txt" del "%HOMEDRIVE%\%HOMEPATH%\Desktop\Rkill.txt" 2>NUL
:skip_rkill
popd
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

:: JOB: Disable sleep mode
echo %CUR_DATE% %TIME%    Disabling Sleep mode...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Disabling Sleep mode...
pushd disable_sleep
if %DRY_RUN%==yes goto skip_disable_sleep

echo %CUR_DATE% %TIME%    Exporting current power scheme and switching to Always On...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Exporting current power scheme and switching to Always On...

:: Export the current power scheme to a file. Thanks to reddit.com/user/GetOnMyAmazingHorse
setlocal enabledelayedexpansion
:: Windows XP version
if "%WIN_VER%"=="Microsoft Windows XP" (
	:: Extract the line containing the current power GUID
	for /f "delims=^T" %%i in ('powercfg -query ^| find /i "Name"') do (set t=%%i)
	:: Parse out just the name and stash it in a variable
	set POWER_SCHEME=!t:~27!
	:: Export the power scheme based on this GUID
	powercfg /EXPORT "!POWER_SCHEME!" /FILE %LOGPATH%\tron_power_config_backup.pow
	:: Set the "High Performance" scheme active
	powercfg /SETACTIVE "Always On"
	) 

:: Windows Server 2003 version
if "%WIN_VER%"=="Microsoft Windows Server 2003" (
	:: Extract the line containing the current power GUID
	for /f "delims=^T" %%i in ('powercfg -query ^| find /i "Name"') do (set t=%%i)
	:: Parse out just the name and stash it in a variable
	set POWER_SCHEME=!t:~27!
	:: Export the power scheme based on this GUID
	powercfg /EXPORT "!POWER_SCHEME!" /FILE %LOGPATH%\tron_power_config_backup.pow
	:: Set the "High Performance" scheme active
	powercfg /SETACTIVE "Always On"
) else (
	:: This version of the command executes if we're not on XP or Server 2003
	:: Extract the line containing the current power GUID
	for /f "delims=" %%i in ('powercfg -list ^| find "*"') do (set t=%%i)
	:: Parse out just the GUID and stash it in a variable
	set POWER_SCHEME=!t:~19,36!
	:: Export the power scheme based on this GUID
	powercfg /EXPORT %LOGPATH%\tron_power_config_backup.pow !POWER_SCHEME!
	:: Set the "High Performance" scheme active
	powercfg /SETACTIVE 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
	)

:: This cheats a little bit by stacking the set command on the same line as the endlocal so it executes immediately after ENDLOCAL but before the variable gets wiped out by the endlocal. Kind of a little trick to get a SETLOCAL-internal variable exported to a global script-wide variable.
:: We need the POWER_SCHEME GUID for later when we re-import everything
endlocal disabledelayedexpansion && set POWER_SCHEME=%POWER_SCHEME%

echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

:skip_disable_sleep
popd
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

:: JOB: Check and Repair WMI if it's broken
echo %CUR_DATE% %TIME%    Checking WMI...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Checking WMI...
pushd repair_wmi
if %DRY_RUN%==yes goto skip_repair_wmi

:: Do a quick check to make sure WMI is working, and if not, repair it
wmic timezone >NUL
if not %ERRORLEVEL%==0 (
    echo %CUR_DATE% %TIME% !  WMI appears to be broken. Running WMI repair. This might take a minute, please be patient...>> "%LOGPATH%\%LOGFILE%"
    echo %CUR_DATE% %TIME% !  WMI appears to be broken. Running WMI repair. This might take a minute, please be patient...
    net stop winmgmt
    pushd %WINDIR%\system32\wbem
    for %%i in (*.dll) do RegSvr32 -s %%i
    :: Kill this random window that pops up
    tskill wbemtest /a 2>NUL
    scrcons.exe /RegServer
    unsecapp.exe /RegServer
    start "" wbemtest.exe /RegServer
    tskill wbemtest /a 2>NUL
    tskill wbemtest /a 2>NUL
    :: winmgmt.exe /resetrepository       -- optional; forces full rebuild instead of a repair like the line below this. Enable if you're feeling REAAAALLY crazy
    winmgmt.exe /salvagerepository /resyncperf
    wmiadap.exe /RegServer
    wmiapsrv.exe /RegServer
    wmiprvse.exe /RegServer
    net start winmgmt
    popd
    )

:skip_repair_wmi
popd
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

:: JOB: Reduce SysRestore space
echo %CUR_DATE% %TIME%    Reducing System Restore space...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Reducing System Restore space...
pushd reduce_system_restore
if "%DRY_RUN%"=="no" reg add "\\%COMPUTERNAME%\HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" /v DiskPercent /t REG_DWORD /d 00000005 /f
if "%DRY_RUN%"=="no" reg add "\\%COMPUTERNAME%\HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore\Cfg" /v DiskPercent /t REG_DWORD /d 00000005 /f
popd
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.


popd
echo %CUR_DATE% %TIME%   Completed stage_0_prep jobs.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Completed stage_0_prep jobs.


::::::::::::::::::::::::
:: STAGE 1: TEMPCLEAN ::
::::::::::::::::::::::::
:stage_1_tempclean
title TRON v%SCRIPT_VERSION% [stage_1_tempclean]
pushd resources\stage_1_tempclean
echo %CUR_DATE% %TIME%   Launching stage_1_tempclean jobs...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching stage_1_tempclean jobs...

:: JOB: CCLeaner
echo %CUR_DATE% %TIME%    Launching job 'CCleaner'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Launching job 'CCleaner'...
pushd ccleaner
if "%DRY_RUN%"=="no" ccleaner.exe /auto>> "%LOGPATH%\%LOGFILE%" 2>NUL
popd
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

:: JOB: BleachBit
echo %CUR_DATE% %TIME%    Launching job 'BleachBit'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Launching job 'BleachBit'...
pushd bleachbit
if "%DRY_RUN%"=="no" bleachbit_console.exe --preset -c>> "%LOGPATH%\%LOGFILE%" 2>NUL
popd
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

:: JOB: Clear Windows event logs
echo %CUR_DATE% %TIME%    Launching job 'Clear Windows event logs'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Launching job 'Clear Windows event logs'...
pushd clear_windows_event_logs
if "%DRY_RUN%"=="no" for /f %%x in ('wevtutil el') do wevtutil cl "%%x" 2>NUL
popd
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

popd
echo %CUR_DATE% %TIME%   Completed stage_1_tempclean jobs.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Completed stage_1_tempclean jobs.


::::::::::::::::::::::::
:: STAGE 2: Disinfect ::
::::::::::::::::::::::::
:stage_2_disinfect
title TRON v%SCRIPT_VERSION% [stage_2_disinfect]
pushd resources\stage_2_disinfect
echo %CUR_DATE% %TIME%   Launching stage_2_disinfect jobs...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching stage_2_disinfect jobs...

:: JOB: Sophos Virus Remover
echo %CUR_DATE% %TIME%    Launching job 'Sophos Virus Removal Tool' (takes a LONG time)...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Launching job 'Sophos Virus Removal Tool' (takes a LONG time)...
echo %CUR_DATE% %TIME%    Logging to console instead of logfile for this job...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Logging to console instead of logfile for this job...
pushd sophos_virus_remover
if "%DRY_RUN%"=="no" svrtcli.exe -yes
popd
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

:: JOB: VIPRE Rescue
echo %CUR_DATE% %TIME%    Launching job 'Vipre rescue scanner' (takes a LONG time)...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Launching job 'Vipre rescue scanner' (takes a LONG time)...
echo %CUR_DATE% %TIME%    Logging to console instead of logfile for this job...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Logging to console instead of logfile for this job...
pushd vipre_rescue
if "%DRY_RUN%"=="no" VipreRescueScanner.exe
popd
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

:: JOB: MBAM (MalwareBytes Anti-Malware)
echo %CUR_DATE% %TIME%    Launching job 'Malwarebytes Anti-Malware', continuing other jobs..."%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Launching job 'Malwarebytes Anti-Malware', continuing other jobs...
pushd mbam

:: Install & remove the desktop icon
if %DRY_RUN%==yes goto skip_mbam
"Malwarebytes Anti-Malware v2.0.2.1012.exe" /verysilent
if exist "%PUBLIC%\Desktop\Malwarebytes Anti-Malware.lnk" del "%PUBLIC%\Desktop\Malwarebytes Anti-Malware.lnk"
if exist "%USERPROFILE%\Desktop\Malwarebytes Anti-Malware.lnk" del "%USERPROFILE%\Desktop\Malwarebytes Anti-Malware.lnk"

:: Scan for and launch appropriate architecture version
if exist "%ProgramFiles(x86)%\Malwarebytes Anti-Malware" (
    pushd "%ProgramFiles(x86)%\Malwarebytes Anti-Malware"
) else (
    pushd "%ProgramFiles%\Malwarebytes Anti-Malware"
  )
start "" "mbam.exe"
popd

:skip_mbam
popd
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

:: JOB: System File Checker scan
echo %CUR_DATE% %TIME%    Launching job 'System File Checker'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Launching job 'System File Checker'...
pushd sfc
if %DRY_RUN%==yes goto skip_sfc
:: Basically this says "If OS is NOT XP or 2003, go ahead and run system file checker
if "%WIN_VER%"=="Microsoft Windows XP" goto skip_sfc
if "%WIN_VER%"=="Microsoft Windows Server 2003" goto skip_sfc
sfc /scannow
:: Dump the SFC log into the Tron log. Thanks to reddit.com/user/adminhugh
findstr /c:"[SR]" %WinDir%\logs\cbs\cbs.log>> "%LOGPATH%\%LOGFILE%"
:skip_sfc
popd
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.


popd
echo %CUR_DATE% %TIME%   Completed stage_2_disinfect jobs.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Completed stage_2_disinfect jobs.


:::::::::::::::::::::::
:: STAGE 3: De-Bloat ::
:::::::::::::::::::::::
:stage_3_de-bloat
title TRON v%SCRIPT_VERSION% [stage_3_de-bloat]
pushd resources\stage_3_de-bloat
echo %CUR_DATE% %TIME%   Launching stage_3_de-bloat jobs...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching stage_3_de-bloat jobs...

:: JOB: Remove crapware programs
echo %CUR_DATE% %TIME%    Searching for and removing common crapware programs...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Searching for and removing common crapware programs...
echo %CUR_DATE% %TIME%    Customize list here: \resources\stage_3_de-bloat\programs_to_target.txt>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Customize list here: \resources\stage_3_de-bloat\programs_to_target.txt
:: This searches through the list of programs in "programs_to_target.txt" file and uninstalls them one-by-one
if "%DRY_RUN%"=="no" FOR /F "tokens=*" %%i in (programs_to_target.txt) DO echo   %%i && echo   %%i...>> "%LOGPATH%\%LOGFILE%" && wmic product where "name like '%%i'" uninstall /nointeractive>> "%LOGPATH%\%LOGFILE%"

echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.


:: JOB: Remove default Metro apps (Windows 8/8.1 only)
pushd win8_metro_apps

:: Read nine characters into the WIN_VER variable (starting at position 0 on the left) and check for Windows 8
if "%WIN_VER:~0,9%"=="Windows 8" (
	echo %CUR_DATE% %TIME%    Windows 8/8.1 detected, removing default Metro apps...>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%    Windows 8/8.1 detected, removing default Metro apps...
	:: Call powershell
	if %DRY_RUN%==no powershell "Set-ExecutionPolicy Unrestricted -force 2>&1 | Out-Null"
	:: Run the commands
	if %DRY_RUN%==no powershell "Get-AppXProvisionedPackage -online | Remove-AppxProvisionedPackage -online 2>&1 | Out-Null"
	if %DRY_RUN%==no powershell "Get-AppxPackage -AllUsers | Remove-AppxPackage 2>&1 | Out-Null"
	echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%    Done.	
	)

popd


popd
echo %CUR_DATE% %TIME%   Completed stage_3_de-bloat jobs.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Completed stage_3_de-bloat jobs.


::::::::::::::::::::::
:: STAGE 4: Patches ::
::::::::::::::::::::::
:stage_4_patch
title TRON v%SCRIPT_VERSION% [stage_4_patch]
pushd resources\stage_4_patch
echo %CUR_DATE% %TIME%   Launching stage_4_patch jobs...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching stage_4_patch jobs...

:: Prep task: enable MSI installer in Safe Mode
if "%DRY_RUN%"=="no" start "" "enable_msi_installer\SafeMSI.exe"
ping localhost -n 2 >NUL
taskkill /im SafeMSI.exe /f /t 2>NUL

:: JOB: 7-Zip
echo %CUR_DATE% %TIME%    Launching job '7-Zip'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Launching job '7-Zip'...

:: Check if we're on 32-bit Windows and run the appropriate architecture installer
if %DRY_RUN%==yes goto skip_7-zip
if '%PROCESSOR_ARCHITECTURE%'=='x86' (
	pushd 7-zip\v9.20\x86
	setlocal
	call "7-Zip v9.20 x86.bat"
	endlocal
	popd
) else (
	pushd 7-zip\v9.20\x64
	setlocal
	call "7-Zip v9.20 x64.bat"
	endlocal
	popd
	)
:skip_7-zip
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

:: JOB: Adobe Flash Player
echo %CUR_DATE% %TIME%    Launching job 'Update Adobe Flash Player'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Launching job 'Update Adobe Flash Player'...
if %DRY_RUN%==yes goto skip_adobe_flash
pushd "adobe\flash_player\v14.0.0.176\firefox"
setlocal
call "Adobe Flash Player (Firefox).bat"
endlocal
popd
pushd "adobe\flash_player\v14.0.0.176\internet explorer"
setlocal
call "Adobe Flash Player (IE).bat"
endlocal
popd
:skip_adobe_flash
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

:: JOB: Adobe Reader
echo %CUR_DATE% %TIME%    Launching job 'Update Adobe Reader'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Launching job 'Update Adobe Reader'...
if %DRY_RUN%==yes goto skip_adobe_reader
pushd adobe\reader\v11.0.08\x86
setlocal
call "Adobe Reader.bat"
endlocal
popd
:skip_adobe_reader
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

:: JOB: Remove outdated JRE runtimes (security risk)
echo %CUR_DATE% %TIME%    Checking and removing outdated JRE installations...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Checking and removing outdated JRE installations...
if %DRY_RUN%==yes goto skip_jre_update
:: Okay, so all JRE runtimes (series 4-8) use product GUIDs, with certain numbers that increment with each new update (e.g. Update 25)
:: This makes it easy to catch ALL of them through liberal use of WMI wildcards ("_" is single character, "%" is any number of characters)
:: Additionally, JRE 6 introduced 64-bit runtimes, so in addition to the two-digit Update XX revision number, we also check for the architecture 
:: type, which always equals '32' or '64'. The first wildcard is the architecture, the second is the revision/update number.

:: JRE 8
:: we skip JRE 8 because the JRE 8 updater automatically removes older versions, no need to do it twice

:: JRE 7
echo %CUR_DATE% %TIME%    JRE 7...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    JRE 7...
%WMIC% product where "IdentifyingNumber like '{26A24AE4-039D-4CA4-87B4-2F8__170__FF}'" call uninstall /nointeractive >> "%LOGPATH%\%LOGFILE%"

:: JRE 6
echo %CUR_DATE% %TIME%    JRE 6...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    JRE 6...
:: 1st line is for updates 23-xx, after 64-bit runtimes were introduced.
:: 2nd line is for updates 1-22, before Oracle released 64-bit JRE 6 runtimes
%WMIC% product where "IdentifyingNumber like '{26A24AE4-039D-4CA4-87B4-2F8__160__FF}'" call uninstall /nointeractive>> "%LOGPATH%\%LOGFILE%"
%WMIC% product where "IdentifyingNumber like '{3248F0A8-6813-11D6-A77B-00B0D0160__0}'" call uninstall /nointeractive>> "%LOGPATH%\%LOGFILE%"

:: JRE 5
echo %CUR_DATE% %TIME%    JRE 5...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    JRE 5...
%WMIC% product where "IdentifyingNumber like '{3248F0A8-6813-11D6-A77B-00B0D0150__0}'" call uninstall /nointeractive>> "%LOGPATH%\%LOGFILE%"

:: JRE 4
echo %CUR_DATE% %TIME%    JRE 4...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    JRE 4...
%WMIC% product where "IdentifyingNumber like '{7148F0A8-6813-11D6-A77B-00B0D0142__0}'" call uninstall /nointeractive>> "%LOGPATH%\%LOGFILE%"

echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

:: JOB: Java Runtime 8
echo %CUR_DATE% %TIME%    Launching job 'Update Java Runtime Environment'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Launching job 'Update Java Runtime Environment'...

:: Check if we're on 32-bit Windows and run the appropriate installer
if '%PROCESSOR_ARCHITECTURE%'=='x86' (
	echo %CUR_DATE% %TIME%    x86 architecture detected, installing x86 version...>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%    x86 architecture detected, installing x86 version...
	pushd java\jre\8\u11\x86
	setlocal
	call "jre-8u11-windows-i586.bat"
	endlocal
	popd
) else (
	echo %CUR_DATE% %TIME%    x64 architecture detected, installing x64 version...>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%    x64 architecture detected, installing x64 version...
	pushd java\jre\8\u11\x64
	setlocal
	call "jre-8u11-windows-x64.bat"
	endlocal
	popd
	)

:skip_jre_update
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

:: JOB: Notepad++
echo %CUR_DATE% %TIME%    Launching job 'Update Notepad++'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Launching job 'Update Notepad++'...
pushd notepad++\v6.6.8
if %DRY_RUN%==yes goto skip_notepad
setlocal
call "npp.Installer.bat"
endlocal
:skip_notepad
popd
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

:: JOB: Windows updates
echo %CUR_DATE% %TIME%    Launching job 'Install Windows updates'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Launching job 'Install Windows updates'...
pushd windows_updates
if "%DRY_RUN%"=="no" wuauclt /detectnow /updatenow
popd
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

popd
echo %CUR_DATE% %TIME%   Completed stage_4_patch jobs.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Completed stage_4_patch jobs.


:::::::::::::::::::::::
:: STAGE 5: Optimize ::
:::::::::::::::::::::::
:stage_5_optimize
title TRON v%SCRIPT_VERSION% [stage_5_optimize]
pushd resources\stage_5_optimize
echo %CUR_DATE% %TIME%   Launching stage_5_optimize jobs...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching stage_5_optimize jobs...

:: JOB: chkdsk the system drive
echo %CUR_DATE% %TIME%    Launching job 'chkdsk'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Launching job 'chkdsk'...
pushd chkdsk
echo %CUR_DATE% %TIME%    Checking %SystemDrive% for errors...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Checking %SystemDrive% for errors...

:: Run a read-only scan and look for errors. Schedule a scan at next reboot if errors found
if "%DRY_RUN%"=="no" %WinDir%\System32\chkdsk.exe %SystemDrive%
if not %ERRORLEVEL%==0 ( 
	echo %CUR_DATE% %TIME% !  Errors found on %SystemDrive%. Scheduling full chkdsk for next reboot.>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME% !  Errors found on %SystemDrive%. Scheduling full chkdsk for next reboot.
	if "%DRY_RUN%"=="no" echo y | %WinDir%\System32\chkdsk.exe /x /v %SystemDrive%
) else (
	echo %CUR_DATE% %TIME%    No errors found on %SystemDrive%. Skipping full chkdsk at next reboot.>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%    No errors found on %SystemDrive%. Skipping full chkdsk at next reboot.
	)
	
popd
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.


:: Check if we are supposed to run a defrag before doing this section
if "%SKIP_DEFRAG%"=="yes" (
	echo %CUR_DATE% %TIME%    SKIP_DEFRAG set to "yes". Skipping job.>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%    SKIP_DEFRAG set to "yes". Skipping job.
	popd
	goto :wrap-up
	)

:: Check if a Solid State hard drive was detected before doing this section
if "%SSD_DETECTED%"=="yes" (
	echo %CUR_DATE% %TIME%    Solid State hard drive detected. Skipping job 'Defrag %SystemDrive%'.>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%    Solid State hard drive detected. Skipping job 'Defrag %SystemDrive%'.
	popd
	goto :wrap-up
	)

:: JOB: Defrag the system drive
if "%SSD_DETECTED%"=="no" (
	echo %CUR_DATE% %TIME%    Launching job 'Defrag %SystemDrive%'...>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%    Launching job 'Defrag %SystemDrive%'...
	pushd defrag
	if "%DRY_RUN%"=="no" df.exe %SystemDrive%
	popd
	echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%    Done.
	)

popd
echo %CUR_DATE% %TIME%   Completed stage_5_optimize jobs.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Completed stage_5_optimize jobs.


:::::::::::::
:: Wrap-up ::
:::::::::::::
:wrap-up
echo %CUR_DATE% %TIME%   Wrapping up...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Wrapping up...

:: If selected, import the original power settings, re-activate them, and delete the backup
:: Otherwise, just reset the power settings back to their defaults
if "%PRESERVE_POWER_SCHEME%"=="yes" (
	echo %CUR_DATE% %TIME%    Restoring power settings to previous values...>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%    Restoring power settings to previous values...
	:: Check for Windows XP
	if "%WIN_VER%"=="Microsoft Windows XP" (
		if "%DRY_RUN%"=="no" powercfg /import "%POWER_SCHEME%" /file %LOGPATH%\tron_power_config_backup.pow
		if "%DRY_RUN%"=="no" powercfg /setactive "%POWER_SCHEME%"
	) 
	:: Check for Windows Server 2003
	if "%WIN_VER%"=="Microsoft Windows Server 2003" (
			if "%DRY_RUN%"=="no" powercfg /import "%POWER_SCHEME%" /file %LOGPATH%\tron_power_config_backup.pow
			if "%DRY_RUN%"=="no" powercfg /setactive "%POWER_SCHEME%"
	) else (
		:: if we made it this far we're not on XP or 2k3 and we can run the standard commands
		if "%DRY_RUN%"=="no" powercfg /import %LOGPATH%\tron_power_config_backup.pow %POWER_SCHEME% 2>NUL
		if "%DRY_RUN%"=="no" powercfg /setactive %POWER_SCHEME% 
	)
	:: cleanup
	del %LOGPATH%\tron_power_config_backup.pow 2>NUL
) else (
	echo %CUR_DATE% %TIME%    Resetting Windows power settings to defaults...>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%    Resetting Windows power settings to defaults...
	:: Check for Windows XP
	if "%WIN_VER%"=="Microsoft Windows XP" (
		if "%DRY_RUN%"=="no" powercfg /RestoreDefaultPolicies
	) 
	:: check for Windows Server 2003
	if "%WIN_VER%"=="Microsoft Windows Server 2003" (
		if "%DRY_RUN%"=="no" powercfg /RestoreDefaultPolicies
	) else (
		:: if we made it this far we're not on XP or 2k3 and we can run the standard commands
		if "%DRY_RUN%"=="no" powercfg -restoredefaultschemes
	)
)

echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.

:: Collect misc logs and deposit them in the log folder. Thanks to reddit.com/user/swtester
echo %CUR_DATE% %TIME%    Collecting misc logs and dumping them in "%LOGPATH%"...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Collecting misc logs and dumping them in "%LOGPATH%"
if exist "%ProgramData%\Sophos\Sophos Virus Removal Tool\Logs" copy /Y"%ProgramData%\Sophos\Sophos Virus Removal Tool\Logs\*.l*" %SystemDrive%\Logs\ >NUL
if exist "%ProgramData%\Malwarebytes\Malwarebytes Anti-Malware\Logs" copy /Y "%ProgramData%\Malwarebytes\Malwarebytes Anti-Malware\Logs\*.xml" %SystemDrive%\Logs\ >NUL
echo %CUR_DATE% %TIME%    Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%    Done.
	
title TRON v%SCRIPT_VERSION% (%SCRIPT_DATE%) [DONE]

echo %CUR_DATE% %TIME%   DONE. Use the tools in resources\stage_6_manual_tools if further cleaning is required.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   DONE. Use the tools in resources\stage_6_manual_tools if further cleaning is required.

:: Check if auto-reboot was requested
if "%AUTO_REBOOT_DELAY%"=="0" (
	echo %CUR_DATE% %TIME% ! Auto-reboot disabled. Recommend rebooting as soon as possible.>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME% ! Auto-reboot disabled. Recommend rebooting as soon as possible.
) else (
	echo %CUR_DATE% %TIME% ! Auto-reboot selected. Rebooting in %AUTO_REBOOT_DELAY% seconds.>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME% ! Auto-reboot selected. Rebooting in %AUTO_REBOOT_DELAY% seconds.
	)

:: Log trailer
echo ------------------------------------------------------------------------------->> %LOGPATH%\%LOGFILE%
echo -------------------------------------------------------------------------------
echo  %CUR_DATE% %TIME%  TRON v%SCRIPT_VERSION% (%SCRIPT_DATE%) complete>> %LOGPATH%\%LOGFILE%
echo  %CUR_DATE% %TIME%  TRON v%SCRIPT_VERSION% (%SCRIPT_DATE%) complete
echo                          Executed as %USERDOMAIN%\%USERNAME% on %COMPUTERNAME%>> %LOGPATH%\%LOGFILE%
echo                          Executed as %USERDOMAIN%\%USERNAME% on %COMPUTERNAME%
echo                          Logfile: %LOGPATH%\%LOGFILE%>> %LOGPATH%\%LOGFILE%
echo                          Logfile: %LOGPATH%\%LOGFILE%
echo ------------------------------------------------------------------------------->> %LOGPATH%\%LOGFILE%
echo -------------------------------------------------------------------------------


if %DRY_RUN%==yes goto end_and_skip_shutdown
if not "%AUTO_REBOOT_DELAY%"=="0" shutdown /r /f /t %AUTO_REBOOT_DELAY% /c "Rebooting in %AUTO_REBOOT_DELAY% seconds to finish cleanup."

:end_and_skip_shutdown
pause