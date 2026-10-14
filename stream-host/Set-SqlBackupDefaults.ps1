# Set-SqlBackupDefaults.ps1 -- turn backup compression on by default and set the default backup folder to
# C:\DBBackups for the default SQL Server instance (MSSQL16.MSSQLSERVER) on this machine.
# Run ON CORPVM17 in an ELEVATED pwsh 7, as a login that is sysadmin on the instance:
#   pwsh -NoProfile -ExecutionPolicy Bypass -File C:\tmp\stream-host\Set-SqlBackupDefaults.ps1
# Safe to re-run. No SQL Server restart is needed: both settings apply to the next BACKUP.
param(
    [string] $BackupDir = 'C:\DBBackups',
    [string] $Server = '.'
)
$ErrorActionPreference = 'Stop'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Run this from an elevated pwsh 7 (Run as administrator).' }

# 1. The folder, writable by the account the SQL Server service runs as (BACKUP is written by the service, not by you).
$svc = Get-CimInstance Win32_Service -Filter "Name='MSSQLSERVER'"
if (-not $svc) { throw 'Service MSSQLSERVER (default instance) not found.' }
$acct = $svc.StartName
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null; "created $BackupDir" } else { "ok: $BackupDir exists" }
icacls $BackupDir /grant "${acct}:(OI)(CI)M" | Out-Null
if ($LASTEXITCODE) { throw "icacls grant to $acct failed ($LASTEXITCODE)" }
"granted Modify on $BackupDir to $acct"

# 2. Compression on by default, and the default backup folder (stored in the instance's registry key).
$sql = @'
SET NOCOUNT ON;
EXEC sys.sp_configure N'backup compression default', 1;
RECONFIGURE;
EXEC master.dbo.xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'BackupDirectory', REG_SZ, N'__DIR__';
SELECT 'compression' = CAST(value_in_use AS int) FROM sys.configurations WHERE name = N'backup compression default';
SELECT 'backupdir' = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(260));
'@.Replace('__DIR__', $BackupDir.Replace("'", "''"))
sqlcmd -S $Server -E -b -C -Q $sql
if ($LASTEXITCODE) { throw "sqlcmd failed ($LASTEXITCODE)" }
"`nDone. Expect compression = 1 and backupdir = $BackupDir above."
