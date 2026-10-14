Add-Type -AssemblyName System.Windows.Forms
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Information
$notify.BalloonTipTitle = 'Claude Code'
$notify.BalloonTipText = 'Done — ready for input'
$notify.Visible = $true
$notify.ShowBalloonTip(8000)
Start-Sleep -Seconds 3
$notify.Dispose()
