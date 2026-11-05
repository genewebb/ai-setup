-- Outstanding = any monitor activity not in a finished status; quiet = none outstanding and none started recently.
DECLARE @deadline datetime2 = DATEADD(minute, 30, SYSUTCDATETIME());
DECLARE @outstanding int, @lastStart datetime2, @msg nvarchar(2000);
WHILE 1 = 1
BEGIN
    SELECT @outstanding = COUNT(*) FROM monitor.tActivity
    WHERE Status NOT IN (N'Succeeded', N'Failed', N'Canceled', N'Cancelled', N'Completed', N'Warning', N'Skipped');
    SELECT @lastStart = MAX(StartedTime) FROM monitor.tActivity;
    IF @outstanding = 0 AND (@lastStart IS NULL OR @lastStart < DATEADD(second, -{{QuietSeconds}}, SYSUTCDATETIME()))
        BREAK;
    IF SYSUTCDATETIME() > @deadline
    BEGIN
        SELECT @msg = CONCAT(N'Activity Monitor not quiet after 30 minutes; outstanding: ',
            STRING_AGG(CONCAT(Name, N' [', Status, N']'), N'; '))
        FROM monitor.tActivity
        WHERE Status NOT IN (N'Succeeded', N'Failed', N'Canceled', N'Cancelled', N'Completed', N'Warning', N'Skipped');
        SET @msg = ISNULL(@msg, N'Activity Monitor not quiet after 30 minutes: tasks keep starting.');
        THROW 50011, @msg, 1;
    END
    WAITFOR DELAY '00:00:10';
END
PRINT CONCAT(N'Activity Monitor quiet: no outstanding task, last task started ', CONVERT(nvarchar(30), @lastStart, 126), N' UTC.');
