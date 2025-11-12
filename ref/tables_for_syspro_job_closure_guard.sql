USE [SysproEdu1]
GO

/****** Object:  Table [dbo].[App_ActionLog]    Script Date: 4/09/2025 12:23:15 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[App_ActionLog](
	[ActionLogId] [bigint] IDENTITY(1,1) NOT NULL,
	[ActionTsUtc] [datetime2](7) NOT NULL,
	[AppArea] [varchar](64) NOT NULL,
	[ActionName] [varchar](64) NOT NULL,
	[Job] [varchar](50) NULL,
	[StockCode] [varchar](50) NULL,
	[Lot] [varchar](50) NULL,
	[RefText] [varchar](4000) NULL,
	[PerformedBy] [varchar](128) NULL,
PRIMARY KEY CLUSTERED 
(
	[ActionLogId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[App_ActionLog] ADD  CONSTRAINT [DF_App_ActionLog_Ts]  DEFAULT (sysutcdatetime()) FOR [ActionTsUtc]
GO

USE [SysproEdu1]
GO

/****** Object:  Table [dbo].[App_JobClosureActions]    Script Date: 4/09/2025 12:23:24 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[App_JobClosureActions](
	[RequestId] [bigint] IDENTITY(1,1) NOT NULL,
	[RequestTsUtc] [datetime2](7) NOT NULL,
	[Job] [varchar](50) NOT NULL,
	[RequestedStatus] [varchar](20) NOT NULL,
	[ReasonCode] [varchar](50) NULL,
	[ReasonNote] [varchar](2000) NULL,
	[RequestedBy] [varchar](128) NULL,
	[ApprovedBy] [varchar](128) NULL,
	[ApprovalTsUtc] [datetime2](7) NULL,
	[ProcessedFlag] [bit] NOT NULL,
	[ProcessedTsUtc] [datetime2](7) NULL,
	[ProcessedNote] [varchar](2000) NULL,
PRIMARY KEY CLUSTERED 
(
	[RequestId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[App_JobClosureActions] ADD  CONSTRAINT [DF_App_JobClosureActions_Ts]  DEFAULT (sysutcdatetime()) FOR [RequestTsUtc]
GO

ALTER TABLE [dbo].[App_JobClosureActions] ADD  CONSTRAINT [DF_App_JobClosureActions_Processed]  DEFAULT ((0)) FOR [ProcessedFlag]
GO


