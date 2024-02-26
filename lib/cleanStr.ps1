function cleanStr ($myString) {
 begin {
  $baddies = 'drop', 'truncate', 'alter procedure', 'table', 'update', 'delete', 'create',
  'join', 'select', 'order by', ';', ':'
 }
 process {
  $myArr = $myString -split ' '
  $goodArr = foreach ($item in $myArr) {
   $newItem = $item -replace ':', ''
   $newItem = $newItem -replace ';', ''
   $newItem = $newItem -replace '[^\p{L}\p{Nd}]', ''
   if ($baddies -match $newItem) { Write-Verbose "Baddie found! $newItem" }
   else { $newItem }
  }
  $goodArr -join ' '
 }
}
# Special Thanks to François-Xavier Cat https://lazywinadmin.com/2015/08/powershell-remove-special-characters.html