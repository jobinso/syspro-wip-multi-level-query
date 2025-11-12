/*
    SYSPRO Job Closure Guard — Stored Procedures (Regenerated)
    ---------------------------------------------------------------------------
    Purpose: End-to-end SQL layer to support the SYSPRO Application Designer app
             "Job Closure Guard" with clickable drill-through on jobs, materials,
             and lot genealogy.

    Notes:
      • Designed for read-first, change-controlled updates. Direct writes to
        SYSPRO core tables are intentionally avoided. Actions are captured in
        App_JobClosureActions and App_ActionLog, for review & orchestration via
        SYSPRO Business Objects where required.
      • Objects are namespaced with the prefix usp_JobClosureGuard_*.
      • Heavily commented for maintainability (per user preference).

    Referenced Tables (from prior context):
      - WipMaster (jobs)
      - WipJobAllMat (job material requirements)
      - WipAllMatLot (lot-level allocations)
      - LotDetail (lot attributes including dates & supplier lot)
      - LotTransactions (lot movement history)
      - InvMaster (stock master)

    Helper/Support Tables (created here if not exist):
      - dbo.App_ActionLog
      - dbo.App_JobClosureActions

    ---------------------------------------------------------------------------
    Safety:
      • All procedures are idempotent (DROP/CREATE pattern).
      • READ COMMITTED SNAPSHOT assumed. Adjust as per environment.
*/
GO

------------------------------------------------------------------------------
-- 0) Support Tables
------------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.tables WHERE name = 'App_ActionLog' AND schema_id = SCHEMA_ID('dbo')
)
BEGIN
    CREATE TABLE dbo.App_ActionLog
    (
        ActionLogId        BIGINT IDENTITY(1,1) PRIMARY KEY,
        ActionTsUtc        DATETIME2(7)      NOT NULL CONSTRAINT DF_App_ActionLog_Ts DEFAULT (SYSUTCDATETIME()),
        AppArea            VARCHAR(64)       NOT NULL,  -- e.g., 'CloseJob', 'LotDrill', 'UI-Click'
        ActionName         VARCHAR(64)       NOT NULL,  -- e.g., 'REQUEST_CLOSE', 'VIEW_MATERIALS'
        Job                VARCHAR(50)       NULL,
        StockCode          VARCHAR(50)       NULL,
        Lot                VARCHAR(50)       NULL,
        RefText            VARCHAR(4000)     NULL,      -- free text / JSON-encoded payload
        PerformedBy        VARCHAR(128)      NULL       -- SYSPRO operator / app user
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.tables WHERE name = 'App_JobClosureActions' AND schema_id = SCHEMA_ID('dbo')
)
BEGIN
    CREATE TABLE dbo.App_JobClosureActions
    (
        RequestId          BIGINT IDENTITY(1,1) PRIMARY KEY,
        RequestTsUtc       DATETIME2(7)  NOT NULL CONSTRAINT DF_App_JobClosureActions_Ts DEFAULT (SYSUTCDATETIME()),
        Job                VARCHAR(50)   NOT NULL,
        RequestedStatus    VARCHAR(20)   NOT NULL,      -- e.g., 'Close', 'Hold', 'Reopen'
        ReasonCode         VARCHAR(50)   NULL,
        ReasonNote         VARCHAR(2000) NULL,
        RequestedBy        VARCHAR(128)  NULL,
        ApprovedBy         VARCHAR(128)  NULL,
        ApprovalTsUtc      DATETIME2(7)  NULL,
        ProcessedFlag      BIT           NOT NULL CONSTRAINT DF_App_JobClosureActions_Processed DEFAULT (0),
        ProcessedTsUtc     DATETIME2(7)  NULL,
        ProcessedNote      VARCHAR(2000) NULL
    );
END
GO

------------------------------------------------------------------------------
-- 1) Get candidate jobs for closure with quick health summary
------------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_JobClosureGuard_GetJobs', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_JobClosureGuard_GetJobs;
GO
CREATE PROCEDURE dbo.usp_JobClosureGuard_GetJobs
(
    @JobLike        VARCHAR(50) = NULL,     -- optional wildcard: '1234%'
    @OnlyOpen       BIT = 1,                -- filter to open/active jobs if 1
    @TopN           INT = 200               -- cap result size for UI paging
)
AS
BEGIN
    SET NOCOUNT ON;

    /*
        Returns: One row per job with quick closure heuristics
        - Material variance (Reqd vs Issued)
        - Any un-issued reserved lots
        - Lot expiry risks on issued lots
    */

    WITH Mat AS (
        SELECT m.Job,
               SUM(TRY_CONVERT(DECIMAL(18,6), m.UnitQtyReqd)) AS QtyReqd,
               SUM(TRY_CONVERT(DECIMAL(18,6), m.QtyIssued))   AS QtyIssued
        FROM dbo.WipJobAllMat m
        GROUP BY m.Job
    ),
    LotRisk AS (
        SELECT l.Job,
               MAX(CASE WHEN ld.ExpiryDate < CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END) AS HasExpiredLots,
               MIN(ld.ExpiryDate) AS EarliestExpiry
        FROM dbo.WipAllMatLot l
        LEFT JOIN dbo.LotDetail ld
          ON ld.StockCode = l.StockCode AND ld.Lot = l.Lot AND ld.Bin = l.Bin
        GROUP BY l.Job
    ),
    UnissuedReserved AS (
        SELECT l.Job,
               SUM(CASE WHEN ISNULL(l.QtyReserved,0) > ISNULL(l.QtyIssued,0) THEN 1 ELSE 0 END) AS HasUnissuedReservations
        FROM dbo.WipAllMatLot l
        GROUP BY l.Job
    )
    SELECT TOP (@TopN)
           w.Job,
           w.JobDescription,
           w.JobClassification,
           w.Warehouse,
           w.Complete,
           w.JobStartDate,
           w.JobDeliveryDate,
           CAST(ISNULL(mat.QtyReqd,0) AS DECIMAL(18,6))  AS TotalQtyReqd,
           CAST(ISNULL(mat.QtyIssued,0) AS DECIMAL(18,6)) AS TotalQtyIssued,
           CAST(ISNULL(mat.QtyReqd,0) - ISNULL(mat.QtyIssued,0) AS DECIMAL(18,6)) AS TotalVariance,
           ISNULL(ur.HasUnissuedReservations,0) AS HasUnissuedReservations,
           ISNULL(lr.HasExpiredLots,0)          AS HasExpiredIssuedLots,
           lr.EarliestExpiry,
           CASE WHEN ISNULL(mat.QtyReqd,0) = ISNULL(mat.QtyIssued,0)
                     AND ISNULL(ur.HasUnissuedReservations,0) = 0 THEN 1 ELSE 0 END AS MaterialClear,
           CASE WHEN ISNULL(lr.HasExpiredLots,0) = 1 THEN 'Risk: Expired lots' ELSE NULL END AS RiskNote
    FROM dbo.WipMaster w
    LEFT JOIN Mat mat ON mat.Job = w.Job
    LEFT JOIN LotRisk lr ON lr.Job = w.Job
    LEFT JOIN UnissuedReserved ur ON ur.Job = w.Job
    WHERE (@JobLike IS NULL OR w.Job LIKE @JobLike)
      AND (@OnlyOpen = 0 OR (w.Complete IN ('A','R','P'))) -- example open statuses; adjust per site
    ORDER BY w.JobDeliveryDate, w.Job;
END
GO

------------------------------------------------------------------------------
-- 2) Materials for a job (header-level)
------------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_JobClosureGuard_GetJobMaterials', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_JobClosureGuard_GetJobMaterials;
GO
CREATE PROCEDURE dbo.usp_JobClosureGuard_GetJobMaterials
(
    @Job VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT m.Job,
           m.StockCode,
           im.Description AS StockDescription,
           m.Warehouse,
           m.UnitQtyReqd,
           m.QtyIssued,
           (TRY_CONVERT(DECIMAL(18,6), m.UnitQtyReqd) - TRY_CONVERT(DECIMAL(18,6), m.QtyIssued)) AS Variance,
           m.Bin,
           m.SubJob
    FROM dbo.WipJobAllMat m
    LEFT JOIN dbo.InvMaster im ON im.StockCode = m.StockCode
    WHERE m.Job = @Job
    ORDER BY m.StockCode;
END
GO

------------------------------------------------------------------------------
-- 3) Issued lots for a job — lot-level drill
------------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_JobClosureGuard_GetIssuedLots', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_JobClosureGuard_GetIssuedLots;
GO
CREATE PROCEDURE dbo.usp_JobClosureGuard_GetIssuedLots
(
    @Job VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON;

    /*
        Returns one row per lot issued/reserved to the job, including lot dates
        and supplier lot information for genealogy panels.
    */
    SELECT l.Job,
           l.StockCode,
           im.Description AS StockDescription,
           l.Warehouse,
           l.Lot,
           l.Bin,
           CAST(ISNULL(l.QtyReserved,0) AS DECIMAL(18,6)) AS QtyReserved,
           CAST(ISNULL(l.QtyIssued,0)   AS DECIMAL(18,6)) AS QtyIssued,
           CASE WHEN ISNULL(l.QtyReserved,0) > ISNULL(l.QtyIssued,0) THEN 1 ELSE 0 END AS HasUnissued,
           ld.ExpiryDate,
           ld.ManufactureDate,
           ld.UseByDate,
           ld.BestBeforeDate,
           ld.SupplierLot
    FROM dbo.WipAllMatLot l
    LEFT JOIN dbo.LotDetail ld
      ON ld.StockCode = l.StockCode AND ld.Lot = l.Lot AND ld.Bin = l.Bin
    LEFT JOIN dbo.InvMaster im ON im.StockCode = l.StockCode
    WHERE l.Job = @Job
    ORDER BY l.StockCode, l.Lot;
END
GO

------------------------------------------------------------------------------
-- 4) Lot transaction history — job-scoped
------------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_JobClosureGuard_GetLotTransactions', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_JobClosureGuard_GetLotTransactions;
GO
CREATE PROCEDURE dbo.usp_JobClosureGuard_GetLotTransactions
(
    @Job VARCHAR(50),
    @MaxRows INT = 1000
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@MaxRows)
           lt.TrnDate,
           lt.TrnType,
           lt.StockCode,
           im.Description AS StockDescription,
           lt.Lot,
           lt.Bin,
           CAST(lt.TrnQuantity AS DECIMAL(18,6)) AS TrnQuantity,
           lt.TrnValue,
           lt.Reference,
           lt.Customer,
           lt.SalesOrder,
           lt.Job,
           lt.Supplier,
           lt.DispatchNote
    FROM dbo.LotTransactions lt
    LEFT JOIN dbo.InvMaster im ON im.StockCode = lt.StockCode
    WHERE lt.Job = @Job
    ORDER BY lt.TrnDate DESC, lt.StockCode;
END
GO






------------------------------------------------------------------------------
-- 6) Action capture — request a job status change (no direct SYSPRO writes)
------------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_JobClosureGuard_RequestCompleteChange', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_JobClosureGuard_RequestCompleteChange;
GO
CREATE PROCEDURE dbo.usp_JobClosureGuard_RequestCompleteChange
(
    @Job             VARCHAR(50),
    @RequestedStatus VARCHAR(20),
    @ReasonCode      VARCHAR(50) = NULL,
    @ReasonNote      VARCHAR(2000) = NULL,
    @RequestedBy     VARCHAR(128) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.App_JobClosureActions (Job, RequestedStatus, ReasonCode, ReasonNote, RequestedBy)
    VALUES (@Job, @RequestedStatus, @ReasonCode, @ReasonNote, @RequestedBy);

    DECLARE @Id BIGINT = SCOPE_IDENTITY();

    INSERT INTO dbo.App_ActionLog (AppArea, ActionName, Job, RefText, PerformedBy)
    VALUES ('CloseJob', 'REQUEST_STATUS_CHANGE', @Job, CONCAT('RequestId=', @Id, '; Status=', @RequestedStatus, '; Reason=', COALESCE(@ReasonCode,'N/A')), @RequestedBy);

    SELECT @Id AS RequestId;
END
GO

------------------------------------------------------------------------------
-- 7) Generic click-logging helper for UI hyperlinks
------------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_JobClosureGuard_LogUiClick', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_JobClosureGuard_LogUiClick;
GO
CREATE PROCEDURE dbo.usp_JobClosureGuard_LogUiClick
(
    @AppArea     VARCHAR(64),   -- e.g., 'MaterialsPanel', 'LotPanel'
    @ActionName  VARCHAR(64),   -- e.g., 'CLICK_STOCK', 'CLICK_LOT'
    @Job         VARCHAR(50) = NULL,
    @StockCode   VARCHAR(50) = NULL,
    @Lot         VARCHAR(50) = NULL,
    @RefText     VARCHAR(4000) = NULL,
    @PerformedBy VARCHAR(128) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.App_ActionLog (AppArea, ActionName, Job, StockCode, Lot, RefText, PerformedBy)
    VALUES (@AppArea, @ActionName, @Job, @StockCode, @Lot, @RefText, @PerformedBy);
END
GO

------------------------------------------------------------------------------
-- 8) Stock search for quick-pick dialogs
------------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_JobClosureGuard_SearchStock', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_JobClosureGuard_SearchStock;
GO
CREATE PROCEDURE dbo.usp_JobClosureGuard_SearchStock
(
    @Query VARCHAR(100)  -- supports prefix search on code or description
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (100)
           im.StockCode,
           im.Description,
           im.ProductClass,
           im.StockUom
    FROM dbo.InvMaster im
    WHERE im.StockCode LIKE @Query + '%'
       OR im.Description LIKE '%' + @Query + '%'
    ORDER BY im.StockCode;
END
GO

------------------------------------------------------------------------------
-- 9) Materials-by-click — detailed issues for a clicked stock on a job
------------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_JobClosureGuard_GetMaterialIssuesForStock', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_JobClosureGuard_GetMaterialIssuesForStock;
GO
CREATE PROCEDURE dbo.usp_JobClosureGuard_GetMaterialIssuesForStock
(
    @Job       VARCHAR(50),
    @StockCode VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT l.Job,
           l.StockCode,
           im.Description AS StockDescription,
           l.Warehouse,
           l.Lot,
           l.Bin,
           CAST(ISNULL(l.QtyReserved,0) AS DECIMAL(18,6)) AS QtyReserved,
           CAST(ISNULL(l.QtyIssued,0)   AS DECIMAL(18,6)) AS QtyIssued,
           (CAST(ISNULL(l.QtyReserved,0) AS DECIMAL(18,6)) - CAST(ISNULL(l.QtyIssued,0) AS DECIMAL(18,6))) AS Variance,
           ld.ExpiryDate,
           ld.SupplierLot
    FROM dbo.WipAllMatLot l
    LEFT JOIN dbo.InvMaster im ON im.StockCode = l.StockCode
    LEFT JOIN dbo.LotDetail  ld ON ld.StockCode = l.StockCode AND ld.Lot = l.Lot AND ld.Bin = l.Bin
    WHERE l.Job = @Job
      AND l.StockCode = @StockCode
    ORDER BY l.Lot;
END
GO

------------------------------------------------------------------------------
-- 10) Admin helper — mark a job closure request as processed
------------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_JobClosureGuard_MarkRequestProcessed', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_JobClosureGuard_MarkRequestProcessed;
GO
CREATE PROCEDURE dbo.usp_JobClosureGuard_MarkRequestProcessed
(
    @RequestId     BIGINT,
    @ProcessedNote VARCHAR(2000) = NULL,
    @ProcessedBy   VARCHAR(128) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.App_JobClosureActions
       SET ProcessedFlag = 1,
           ProcessedTsUtc = SYSUTCDATETIME(),
           ProcessedNote = @ProcessedNote,
           ApprovedBy = COALESCE(ApprovedBy, @ProcessedBy),
           ApprovalTsUtc = COALESCE(ApprovalTsUtc, SYSUTCDATETIME())
     WHERE RequestId = @RequestId;

    INSERT INTO dbo.App_ActionLog (AppArea, ActionName, Job, RefText, PerformedBy)
    SELECT 'CloseJob', 'MARK_PROCESSED', a.Job, CONCAT('RequestId=', a.RequestId, '; Note=', @ProcessedNote), @ProcessedBy
    FROM dbo.App_JobClosureActions a
    WHERE a.RequestId = @RequestId;
END
GO

/*
    Deployment Checklist:
    - Review status codes in usp_JobClosureGuard_GetJobs filter for site-specific values.
    - Ensure indexes exist on WipJobAllMat(Job, StockCode), WipAllMatLot(Job, StockCode, Lot), LotTransactions(Job, TrnDate).
    - Grant EXECUTE to application SQL user/role.
*/




------------------------------------------------------------------------------
-- 5) Job hierarchy (parent → subjobs) using recursive CTE
------------------------------------------------------------------------------


------------------------------------------------------------------------------
-- 5) Job hierarchy (parent → subjobs) using recursive CTE — SINGLE DEFINITION
------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_JobClosureGuard_GetJobHierarchy
(
    @RootJob  VARCHAR(50),
    @MaxDepth INT = 20  -- safety to prevent runaway recursion
)
AS
BEGIN
    SET NOCOUNT ON;

    /*
        Mapping:
          - WipMaster.Job       = ChildJob
          - WipMaster.MasterJob = ParentJob (points to parent)

        Returns descendant tree starting from @RootJob (root included at Depth = 0).
        Uses explicit column list, consistent CASTs, and proper aliasing.
    */

    ;WITH R (ParentJob, ChildJob, Depth) AS (
        -- Anchor: include the root as Depth = 0
        SELECT
            CAST(NULL        AS VARCHAR(50)) AS ParentJob,
            CAST(@RootJob    AS VARCHAR(50)) AS ChildJob,
            CAST(0           AS INT)         AS Depth

        UNION ALL

        -- Recursive: children where MasterJob matches current node
        SELECT
            CAST(w.MasterJob AS VARCHAR(50)) AS ParentJob,
            CAST(w.Job       AS VARCHAR(50)) AS ChildJob,
            CAST(r.Depth + 1 AS INT)         AS Depth
        FROM R AS r
        JOIN dbo.WipMaster AS w
          ON w.MasterJob = r.ChildJob
        WHERE r.Depth < @MaxDepth
    )
    SELECT
        @RootJob AS RootJob,
        ParentJob,
        ChildJob,
        Depth
    FROM R
    ORDER BY Depth, ParentJob, ChildJob
    OPTION (MAXRECURSION 32767);
END
GO
