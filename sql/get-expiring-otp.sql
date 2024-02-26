SELECT *
FROM {0}
WHERE permId = {1}
AND requestDate > DATEADD(minute,-10,getdate())
AND del IS NULL;