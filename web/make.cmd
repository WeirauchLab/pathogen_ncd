:: substitute for `make` on Windows using the Invoke Python module
@echo off

:: %~1 is the first argument with quotes removed
if not "%~1" == "" goto :invoke
python -m invoke help 
goto :EOF

:invoke
python -m invoke %1 %2 %3 %4 %5 %6 %7 %8 %9
