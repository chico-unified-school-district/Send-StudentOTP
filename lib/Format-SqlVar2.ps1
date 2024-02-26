function cleanSqlStr ($myString) {
 begin {
  $baddies = 'drop ', 'truncate ', 'alter ', 'table ', 'update ', 'delete ', 'create ',
  'join ', 'select ', 'order by ', ';', ':'
 }
 process {
  $myArr = $myString -split ' '
  $newArr = foreach ($item in $myArr) {
   if ($baddies -match $item) { Write-Verbose "Baddie found! $item" }
   else { $item }
  }
  $newArr -join ' '
 }
}