UPDATE {0}
SET del = 1, newPw = 'cleared', otp = 000000, dts = GETDATE()
WHERE id = @id