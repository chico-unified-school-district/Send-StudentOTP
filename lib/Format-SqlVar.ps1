function Format-SqlVar ($sqlCmd) {
 $swap = ' INVALID INPUT '
 $sqlCmd -replace 'INSERT', $swap `
  -replace 'ALTER TABLE', $swap `
  -replace 'UPDATE', $swap `
  -replace 'DELETE', $swap `
  -replace 'SELECT', $swap `
  -replace 'CREATE', $swap `
  -replace 'JOIN', $swap `
  -replace 'ORDER BY', $swap `
  -replace 'DROP', $swap `
  -replace ';', $swap `
  -replace ':', $swap `
  -replace '  ', ' '
}