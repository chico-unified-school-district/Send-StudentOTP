SELECT *
FROM {0}
WHERE requestDate < DATEADD(minute, -10, getdate())
AND del IS NULL