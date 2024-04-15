SELECT *
FROM {0}
WHERE
newPw IS NOT NULL
AND resetPw = 1
AND newPw IS NOT NULL
AND requestDate > DATEADD(minute,-11,getdate())
AND del IS NULL;