-- Skip entries older than {1} minutes
SELECT * FROM {0} WHERE permId = @id
AND requestDate > DATEADD(minute, -{1}, getdate())
AND del IS NULL;