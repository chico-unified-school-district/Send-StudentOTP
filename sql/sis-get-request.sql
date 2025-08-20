-- Temp siteCodes Table
 -- CREATE TABLE #TempStuOTPSiteCodes (sc INT);
 -- INSERT INTO #TempStuOTPSiteCodes (sc) VALUES MY_VALUES;
-- Get SIS OTP PW Requests
SELECT
 STU.ID as id
 ,SUP.SC as sc
 ,SUP.SN as sn
 ,STU.BD as bd
 ,STU.GR as gr
FROM
 SUP LEFT JOIN STU ON STU.SC = SUP.SC AND STU.SN = SUP.SN
WHERE
SUP.ADPW = 'Y'
-- AND STU.SC IN (SELECT sc FROM #TempStuOTPSiteCodes)
;