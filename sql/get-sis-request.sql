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
AND STU.SC IN ({0})
;