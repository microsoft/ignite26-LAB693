SET NOCOUNT ON;
DECLARE @Checks TABLE (
    Sort INT IDENTITY PRIMARY KEY, [Check] NVARCHAR(100),
    Passed BIT NOT NULL, Skipped BIT NOT NULL DEFAULT 0, Details NVARCHAR(2048)
);
DECLARE @DatabaseReady BIT = CASE WHEN DB_NAME() = N'Healthcare' THEN 1 ELSE 0 END;
DECLARE @Passed BIT;
INSERT INTO @Checks ([Check], Passed, Details)
VALUES (N'Workshop database', @DatabaseReady, N'Connect the MSSQL kernel to Healthcare, not master.');

SET @Passed = 0;
IF @DatabaseReady = 1 AND (OBJECT_ID(N'dbo.Cases', N'U') IS NOT NULL)
    EXEC sys.sp_executesql
        N'SELECT @Ok = CASE WHEN (SELECT COUNT(*) FROM dbo.Cases) = 207 THEN 1 ELSE 0 END;',
        N'@Ok BIT OUTPUT', @Ok = @Passed OUTPUT;
INSERT INTO @Checks ([Check], Passed, Skipped, Details)
VALUES (N'Seeded cases', @Passed,
    CASE WHEN @DatabaseReady = 0 OR NOT (OBJECT_ID(N'dbo.Cases', N'U') IS NOT NULL) THEN 1 ELSE 0 END,
    N'Complete prework: original Labs 02 and 03, with all 207 synthetic cases.');

SET @Passed = 0;
IF @DatabaseReady = 1 AND (1 = 1)
    EXEC sys.sp_executesql
        N'SELECT @Ok = CASE WHEN (SELECT COUNT(*) FROM sys.database_scoped_credentials
    WHERE credential_identity = N''Managed Identity'' AND name LIKE N''https://foundry-%-cu.services.ai.azure.com'') = 1 THEN 1 ELSE 0 END;',
        N'@Ok BIT OUTPUT', @Ok = @Passed OUTPUT;
INSERT INTO @Checks ([Check], Passed, Skipped, Details)
VALUES (N'Prepared Foundry credential', @Passed,
    CASE WHEN @DatabaseReady = 0 OR NOT (1 = 1) THEN 1 ELSE 0 END,
    N'Complete original Lab 06 and original Lab 07 Steps 1 and 2 before this session.');

SELECT CONCAT([Check], N': ', CASE
    WHEN Skipped = 1 THEN CONCAT(N'Skipped - ', Details)
    WHEN Passed = 1 THEN N'Yes'
    ELSE CONCAT(N'No - ', Details)
END) AS Result
FROM @Checks ORDER BY Sort;
IF EXISTS (SELECT 1 FROM @Checks WHERE Passed = 0)
    THROW 51000, 'Resolve the failed or skipped required checks above.', 1;
