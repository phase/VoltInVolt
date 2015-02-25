@echo off


echo VOLT volta.exe
if exist volta.exe del volta.exe
volt %* -o volta src\*.volt src\volt\*.volt src\volt\token\*.volt src\volt\util\string.volt src\volt\ir\*.volt src\volt\parser\*.volt
if not %ERRORLEVEL% equ 0 exit /b

echo VOLTA
volta src\*.volt src\volt\*.volt src\volt\token\*.volt src\volt\util\string.volt src\volt\ir\*.volt src\volt\parser\*.volt
