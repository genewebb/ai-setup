Add-Type -AssemblyName System.Windows.Forms
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Question
$notify.BalloonTipTitle = 'Claude Code'
$notify.BalloonTipText = 'Waiting for your input...'
$notify.Visible = $true
$notify.ShowBalloonTip(5000)
Start-Sleep -Seconds 3
$notify.Dispose()
