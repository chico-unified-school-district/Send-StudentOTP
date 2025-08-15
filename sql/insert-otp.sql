INSERT INTO {0}
(permId,stuNum,grade,siteCode,samid,staffEmail,otp,requestDate,source,dts)
VALUES
(@id,@num,@gr,@sc,@sam,@email,@otp,@reqDate,@src,GETDATE());