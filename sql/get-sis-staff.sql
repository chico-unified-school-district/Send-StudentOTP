SELECT TOP 1 USR
FROM LOG
WHERE
-- ID = 72591
ID = {0}
AND CD = 'SUPchg'
AND ND LIKE '%ADPW%Y%'
ORDER BY DTS DESC