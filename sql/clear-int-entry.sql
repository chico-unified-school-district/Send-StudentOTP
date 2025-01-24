UPDATE {0}
SET DEL = 1, newPw = 'cleared', otp = 000000, dts = GETDATE()
WHERE id = {1}