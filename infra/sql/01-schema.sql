IF OBJECT_ID(N'dbo.Cases', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Cases
    (
        Id INT NOT NULL PRIMARY KEY,
        Age INT NOT NULL,
        Sex NVARCHAR(6) NOT NULL
            CONSTRAINT CK_Cases_Sex CHECK (Sex IN (N'Male', N'Female')),
        Complaint NVARCHAR(500) NOT NULL,
        Symptoms NVARCHAR(MAX) NOT NULL,
        Diagnosis NVARCHAR(200) NOT NULL
    );
END;

SELECT name FROM sys.tables WHERE name = N'Cases';

GO
IF OBJECT_ID(N'dbo.ComplaintEmbeddings', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ComplaintEmbeddings
    (
        Id INT IDENTITY(1, 1) CONSTRAINT PK_ComplaintEmbeddings PRIMARY KEY,
        CaseId INT NOT NULL REFERENCES dbo.Cases(Id),
        Chunk NVARCHAR(MAX) NOT NULL,
        Embedding VECTOR(1536) NULL
    );
END;

SELECT name FROM sys.tables WHERE name = N'ComplaintEmbeddings';

GO
IF OBJECT_ID(N'dbo.SymptomEmbeddings', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SymptomEmbeddings
    (
        Id INT IDENTITY(1, 1) CONSTRAINT PK_SymptomEmbeddings PRIMARY KEY,
        CaseId INT NOT NULL REFERENCES dbo.Cases(Id),
        Chunk NVARCHAR(MAX) NOT NULL,
        Embedding VECTOR(1536) NULL
    );
END;

SELECT name FROM sys.tables WHERE name = N'SymptomEmbeddings';
