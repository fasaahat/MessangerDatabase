USE Elmos_Messanger

--Update MSG
--Set Picture = 'https://cdn.tabnak.ir/files/fa/news/1399/5/22/1224927_596.jpg'
--Where Picture Is Not Null
/*========================================================== [PROCEDURES] ===================================================*/

-- Materialized View for users whenever they get into a chat (PV/Group/Channel) - Used For |Open_Chat_Proc| Procedure
Create Or Alter View Message_Details
With Schemabinding
As
Select
	c.F_Name + ' ' + c.L_Name As Full_Name,
	c.bio, c.ID As ContactID, c.profile_pic,
	c.phone,
	m.txt, m.files, m.music, m.video, m.Picture, m.locations, m.times, m.dates
From 
	dbo.MSG As m Inner Join dbo.Contact As c 
	On c.ID = m.Sender_ID


-- Materialized View For Members
Create Or Alter View Member_Contact
With Schemabinding
As
Select 
	c.F_Name + ' ' + c.L_Name As Full_Name,
	c.bio, c.ID As ContactID, c.profile_pic,
	c.phone
From 
	dbo.Members As m Inner Join dbo.Contact As c
	On c.ID = m.member_id


-- View For Admins 
Create Or Alter View Admins_V
As
	Select h.Admin_ID, h.privilege, h.recentACC, h.A_ID
	From 
		dbo.Has_AA As h Inner Join dbo.Accessibility As a 
		On a.A_ID = h.A_ID Inner Join Admin As ad
		On ad.Contact_ID = h.Admin_ID;


-- For Finding all the chats in a specific PV / Group / Channel
Create Or Alter Function Bring_Chat(@chatID Char(7))
Returns Table
As
Return 
	Select
		c.Full_Name,
		c.bio, c.ContactID, c.profile_pic,
		c.phone,
		c.txt, c.files, c.music, c.video, c.Picture, c.locations, c.times, c.dates
	From 
		(Select MD.*, ROW_NUMBER() OVER(PARTITION BY m.Sender_ID ORDER BY m.Sender_ID DESC) As rn
		From MSG As m, dbo.Message_Details As MD
		Where 
			m.Chat_ID = @chatID And
			MD.ContactID = m.Sender_ID) As c
	Where rn = 1;



-- For Finding a group of members with their details
Create Or Alter Function Members_Detail(@chatID Char(7))
Returns Table
As
Return
	Select
		c.Full_Name,
		c.bio, c.ContactID, c.profile_pic,
		c.phone
	From
		(Select mc.*, ROW_NUMBER() OVER(PARTITION BY m.member_id ORDER BY m.member_id DESC) As rn
		From Members As m, Member_Contact As mc
		Where 
			m.chat_id = @chatID And
			mc.ContactID = m.member_id) As c
	Where rn = 1;


-- Finding admins of a group or channel
--Drop Function Find_Admin
Create Or Alter Function Find_Admin(@Acc_ID Char(7))
Returns Table
As
Return
	Select
		c.F_Name + ' ' + c.L_Name As Full_Name,
		c.bio, c.ID As ContactID, c.profile_pic,
		c.phone
	From 
		Admins_V As av Inner Join Contact As c
		On c.ID = av.Admin_ID
	Where av.A_ID = @Acc_ID;


-- Find Accessibility of a chat form chat_id
Create Or Alter Procedure Find_Acc 
	@Chat_ID Char(7),
	@Acc_ID Char(7)
As
Begin
	
		Select @Acc_ID =
		Case
			When g.Chat_ID = @Chat_ID And g.A_ID Is Not Null
			Then g.A_ID
			When ch.Chat_ID = @Chat_ID And ch.A_ID Is Not Null
			Then ch.A_ID
			End
		From Groups As g, Channel As ch
End;


CREATE OR ALTER PROCEDURE Open_Chat_Proc
	@ChatID CHAR(7),
	@AccID CHAR(7)
AS
BEGIN
	-- Chat
	Select *
	From Bring_Chat(@ChatID) As b
	Order By b.dates, b.times Asc

	-- Members
	Select *
	From Members_Detail(@ChatID) As md
	Order By md.Full_Name Asc

	-- Accessibility
	Select Distinct a.photo, a.Descriptions, a.inv_link As Link
	From Accessibility As a, Groups As g
	Where 
		a.A_ID = g.A_ID And
		a.A_ID = @AccID
	Union
	Select Distinct a.photo, a.Descriptions, a.inv_link As Link
	From Accessibility As a, Channel As ch
	Where 
		a.A_ID = ch.A_ID And
		a.A_ID = @AccID

	-- Admin
	Select *
	From Find_Admin(@AccID)

END;

--Drop Procedure Group_Channel_P

/* ======================= [Open Chat Procedure] ======================= 
	1)Messages
	2)Members
	3)Accessibility (Channel/Group Profile Photo - Description - Join Link)
	4)Owners And Admins
*/
-- A Channel Test
EXEC Open_Chat_Proc @ChatID = '2000000', @AccID = '1111111';
-- A PV Test
EXEC Open_Chat_Proc @ChatID = '1000000', @AccID = '000none';


-- Saved Message Of A User
CREATE Or ALTER FUNCTION SavedMSG(@User_ID CHAR(7))
RETURNS TABLE
AS
RETURN
	SELECT M.*
	FROM 
		Has_SM AS H INNER JOIN MSG AS M
		ON M.MSG_ID = H.MSG_ID INNER JOIN Saved_Message AS SM
		ON SM.Saved_ID = H.Saved_ID
	WHERE @User_ID = SM.Use_ID

Select * From SavedMSG('3652148');


-- [INSERT] Banned Users can not send any message !
Create Table BannedMSG(
MSG_ID char(7) PRIMARY KEY,
Chat_ID char(7),
Sender_ID char(7),

FOREIGN KEY(Sender_ID) REFERENCES Sender(Contact_ID),
FOREIGN KEY(Chat_ID) REFERENCES Chat(Chat_ID)
ON DELETE NO ACTION   ON UPDATE CASCADE
);

CREATE Or Alter TRIGGER BannedRestrict
ON dbo.MSG
After Insert
AS
BEGIN
	SET NOCOUNT ON
	Declare @msgid Char(7)
	--INSERT INTO dbo.BannedMSG( 
 --       MSG_ID, Chat_ID, Sender_ID
 --   )
    SELECT
        @msgid = i.MSG_ID
    FROM
        inserted i
    WHERE
        i.Sender_ID IN 
			(Select c.ID
			From Contact As c
			Where c.ID In (	Select Distinct cu.Contact_ID
						From Contact_Of_User cu
						Where  
								(Select Count(*)
								From Contact_Of_User As cu2
								Where cu2.IsBlock = 1)
								/
								(Select Count(*)
								From Contact_Of_User As cu1)
								<
								(	Select Top 1 Count(cu1.IsBlock) As NumberOfBlocks
									From Contact_Of_User cu1
									Where cu1.Contact_ID = cu.Contact_ID
									Group By cu1.Contact_ID, cu1.IsBlock Having cu1.IsBlock = 1
									Order By NumberOfBlocks Desc)));	

	Delete From MSG
	Where @msgid = MSG_ID
END

/* ======================= [Banned Users Restriction] ======================= 
	Banned users can not send any messages (text/file/video/music/picture)
*/
-- A Text Test From KIM CHON ON :D
Insert Into MSG
Values
	('0MSG111', '1000000', '5692105', 'Lat tar az Kim Chon On nadidam!', GETDATE(), GETDATE(), NULL, NULL, NULL, NULL, NULL);
Delete From MSG Where MSG_ID = '0MSG111'
Select * From MSG Where MSG_ID = '0MSG111'


-- [Delete] Deleted Messages in groups/channels will be logged into a new table -> MSGLOG
Create Table MSGLOG(
MSG_ID char(7),
Chat_ID char(7),
Sender_ID char(7),
txt nvarchar(Max),
times time,
dates date,
locations nvarchar(50),
Picture nvarchar(200),
music nvarchar(200),
files nvarchar(200),
video nvarchar(200)

FOREIGN KEY(Sender_ID) REFERENCES Sender(Contact_ID),
FOREIGN KEY(Chat_ID) REFERENCES Chat(Chat_ID)
ON DELETE NO ACTION   ON UPDATE CASCADE
);
--Drop Table MSGLOG
Create Or Alter Trigger MSGLOG_TRG
ON dbo.MSG
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
INSERT INTO dbo.MSGLOG
	(
	MSG_ID,
	Chat_ID,
	Sender_ID,
	txt,
	times,
	dates,
	locations,
	Picture,
	music,
	files,
	video
	)

	SELECT
		i.MSG_ID,
		i.Chat_ID,
		i.Sender_ID,
		i.txt,
		i.times,
		i.dates,
		i.locations,
		i.Picture,
		i.music,
		i.files,
		i.video
    FROM
        deleted i
End;

/* ======================= [Deleted Messages Log] ======================= 
	Deleted messages will be logged into MSGLOG Table for admins and owners
	who have recent action accesssibility
*/
-- A Deletion Test
INSERT INTO MSG
VALUES
	('0MSG128', '3000000', '5692106', 'To Taj dari Vali toye SnapChat!', '11:00:42', '2021-04-04', null, null, null, null, null);
Select * From MSG Where MSG_ID = '0MSG128';
Delete From MSG Where MSG_ID = '0MSG128';
Select * From MSGLOG Where MSG_ID = '0MSG128';
Delete From MSGLOG






