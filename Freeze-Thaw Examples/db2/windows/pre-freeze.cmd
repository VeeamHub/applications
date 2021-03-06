:: set log file name and path
set scriptlog=%temp%\freeze_thaw.log

:: check DB2 environment
if "%db2path%"=="" goto init
goto run

:init
:: initialize environment and restart this script
db2cmdadmin -c -i -w %~f0
:: return result to Veeam job
echo %errorlevel%
exit /b %errorlevel%

:: create db2 script
:run
:: log current date/time
echo %date% %time% - executing %~f0>>%scriptlog%
:: add command to redirect all db2 command outputs to log file
echo update command options using z on %scriptlog%>%temp%\pre-freeze.txt
:: remove first 3 characters from envvar 'db2instance' to retrieve instance name
:: and add command to connect to this instance
echo connect to %db2instance:~3%>>%temp%\pre-freeze.txt
:: add command to suspend the database
echo set write suspend for database>>%temp%\pre-freeze.txt

:: execute db2 script
db2 -f %temp%\pre-freeze.txt

:: return result to Veeam job
echo %errorlevel%
exit /b %errorlevel%
