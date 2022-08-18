# Veeam generic pre-/post-scripts 

These scripts are generic pre-freeze and post-thaw sripts written for the use in Veeam Backup and Replication.

These scripts are placed on the VBR server and configured as pre- and post-scripts within backup jobs. 
As they don't contain any specific handling for an application, they are generic and can be used on any system.

The scripts will, when executed before the OS freeze, execute scripts in alphabetical order from a configured directory on the client OS which needs to be freezed.
That way the application owner administrating this system has highest control over the actions necessary to make the applications on the own system consistent for backup.

## License

These scripts are released under the MIT license.

## Linux
Please ensure that the file endings are in Unix format (linefeed only = `\n`) so that the file can be executed in Linux.

### Synchronous and asynchronous mode
The scripts are configurable to run either synchronous or asynchronous.
In synchrounous mode the pre-/post-scripts will wait for the scripts they called to finish and return an RC.
In asynchrounous mode, however, the script will just be called and the operation will directly return.

The asynchronous mode is useful when an application should run in the background while a freeze operation is happening.

The behavior of the scripts can be adjusted by modifing the header variable `ASYNC_MODE`.

`ASYNC_SLEEP` helps to give the asynchrounous scripts some time to startup and run before the actual external freeze (e.g. a VMware snapshot) happens.