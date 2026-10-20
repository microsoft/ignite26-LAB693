IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY;

-- once you create the database master key, do not drop it.

SELECT name, algorithm_desc
FROM sys.symmetric_keys
WHERE name = N'##MS_DatabaseMasterKey##'

GO
-- STUDENT INPUT: Copy your Foundry resource endpoint from Lab 06.
-- Example: https://foundry-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx-workshop-cu.services.ai.azure.com
DECLARE @Endpoint NVARCHAR(4000) = N'__FOUNDRY_ENDPOINT__';

-- -------------------------------------------------------------------------

SET NOCOUNT ON;

SET @Endpoint = TRIM(@Endpoint);

IF RIGHT(@Endpoint, 1) = N'/'
    SET @Endpoint = LEFT(@Endpoint, LEN(@Endpoint) - 1);

IF @Endpoint IS NULL
    OR @Endpoint NOT LIKE N'https://foundry-%-cu.services.ai.azure.com'
    OR LEN(@Endpoint) > 128
    OR @Endpoint COLLATE Latin1_General_100_BIN2 LIKE N'%[^-a-zA-Z0-9:/.]%'
    OR CHARINDEX(N'/', @Endpoint, 9) > 0
    OR CHARINDEX(N':', @Endpoint, 7) > 0
    THROW 51000, 'Provide your Foundry endpoint from Lab 06.', 1;

IF EXISTS (
    SELECT 1
    FROM sys.database_scoped_credentials
    WHERE name = @Endpoint AND credential_identity <> N'Managed Identity'
)
    THROW 51000, 'The endpoint credential uses a different identity. Review dependencies before explicitly recreating it.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = @Endpoint)
BEGIN
    DECLARE @SQL NVARCHAR(MAX) = N'CREATE DATABASE SCOPED CREDENTIAL ' + QUOTENAME(@Endpoint)
        + N' WITH IDENTITY = ''Managed Identity'',
            SECRET = ''{"resourceid":"https://cognitiveservices.azure.com"}'';';

    EXEC sys.sp_executesql @SQL;
END;

SELECT name, credential_identity
FROM sys.database_scoped_credentials
WHERE name = @Endpoint;
