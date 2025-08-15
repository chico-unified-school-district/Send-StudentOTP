UPDATE {0} SET del = 1
WHERE
requestDate < DATEADD(minute, -{1}, getdate())
AND del IS NULL