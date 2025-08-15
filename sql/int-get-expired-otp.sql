SELECT *
FROM {0}
WHERE requestDate < DATEADD(minute, -{1}, getdate())
AND del IS NULL