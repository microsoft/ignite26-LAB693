CREATE OR ALTER PROCEDURE dbo.AI_GENERATE_RESPONSE
    @Instructions NVARCHAR(MAX),
    @Query NVARCHAR(MAX),
    @Response NVARCHAR(MAX) OUTPUT,
    @JsonMode BIT = 0,
    @DeploymentName NVARCHAR(500) = N'gpt-5-nano'
AS
BEGIN
    SET NOCOUNT ON;

    SET @Response = NULL;

    IF NULLIF(TRIM(@Instructions), N'') IS NULL OR NULLIF(TRIM(@Query), N'') IS NULL
        THROW 51001, 'Instructions and Query must not be empty.', 1;

    IF @JsonMode IS NULL OR @DeploymentName <> N'gpt-5-nano' OR @DeploymentName IS NULL
        THROW 51001, 'Use the workshop gpt-5-nano deployment and a valid JsonMode.', 1;

    DECLARE @Endpoint SYSNAME;

    SELECT @Endpoint = c.name
    FROM sys.external_models AS m
    JOIN sys.database_scoped_credentials AS c
        ON c.credential_id = m.credential_id
    WHERE m.name = N'embedding_openai_text3_small';

    IF @Endpoint IS NULL
        OR @Endpoint NOT LIKE N'https://foundry-%-cu.services.ai.azure.com'
        OR NOT EXISTS (
            SELECT 1
            FROM sys.database_scoped_credentials
            WHERE name = @Endpoint AND credential_identity = N'Managed Identity'
        )
        THROW 51002, 'Run Lab 07 to configure the external model and its Foundry managed-identity credential.', 1;

    DECLARE @Payload NVARCHAR(MAX), @ApiResponse NVARCHAR(MAX), @ReturnCode INT;

    DECLARE @Url NVARCHAR(4000) = @Endpoint + N'/openai/v1/chat/completions';

    SET @Payload = (
        SELECT @DeploymentName AS model,
            8192 AS max_completion_tokens,
            CASE WHEN @JsonMode = 1 THEN N'low' ELSE N'medium' END AS reasoning_effort,
            JSON_QUERY(CASE WHEN @JsonMode = 1 THEN N'{"type":"json_object"}' END) AS response_format,
            JSON_QUERY((
                SELECT role, content
                FROM (VALUES
                    (N'system', @Instructions), (N'user', @Query)
                ) AS m(role, content)
                FOR JSON PATH
            )) AS messages
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    EXEC @ReturnCode = sys.sp_invoke_external_rest_endpoint
        @url = @Url,
        @method = N'POST',
        @credential = @Endpoint,
        @payload = @Payload,
        @timeout = 60,
        @response = @ApiResponse OUTPUT;

    IF @ReturnCode <> 0
    BEGIN
        DECLARE @Message NVARCHAR(2048) = LEFT(CONCAT(N'Foundry request failed. HTTP ',
            JSON_VALUE(@ApiResponse, '$.response.status.http.code'), N': ',
            JSON_VALUE(@ApiResponse, '$.result.error.message')), 2048);

        THROW 51003, @Message, 1;
    END;

    IF COALESCE(JSON_VALUE(@ApiResponse, '$.result.choices[0].finish_reason'), N'') <> N'stop'
    BEGIN
        SET @Message = LEFT(CONCAT(N'Foundry returned an incomplete response. Finish reason: ',
            JSON_VALUE(@ApiResponse, '$.result.choices[0].finish_reason'), N'; completion tokens: ',
            JSON_VALUE(@ApiResponse, '$.result.usage.completion_tokens'),
            N'. Inspect reasoning-token budget and content filtering.'), 2048);

        THROW 51004, @Message, 1;
    END;

    SELECT @Response = Content
    FROM OPENJSON(@ApiResponse, '$.result.choices[0].message')
    WITH (Content NVARCHAR(MAX) '$.content');

    IF NULLIF(TRIM(@Response), N'') IS NULL
        THROW 51004, 'Foundry returned no response content.', 1;

    IF @JsonMode = 1 AND ISJSON(@Response, OBJECT) <> 1
        THROW 51004, 'The chat response was not a JSON object.', 1;
END;
GO

SELECT Name
FROM sys.procedures;
