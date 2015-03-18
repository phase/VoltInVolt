@echo off


echo VOLT volta.exe
if exist volta.exe del volta.exe
volt %* -o volta src\*.volt src\volt\*.volt src\volt\token\*.volt src\volt\semantic\*.volt src\volt\util\*.volt src\volt\ir\*.volt src\volt\parser\*.volt src\volt\visitor\*.volt src\volt\llvm\*.volt src\lib\llvm\*.volt src\lib\llvm\c\*.volt %VFLAGS%
if not %ERRORLEVEL% equ 0 exit /b

echo VOLTA
volta src\*.volt src\volt\*.volt src\volt\token\*.volt src\volt\util\*.volt src\volt\semantic\*.volt src\volt\ir\*.volt src\volt\parser\*.volt src\volt\visitor\*.volt src\volt\llvm\*.volt src\lib\llvm\*.volt src\lib\llvm\c\*.volt
