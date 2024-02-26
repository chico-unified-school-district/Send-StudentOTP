function checkStr ($myString) {
 $phrases = 'drop table', 'truncate table', 'alter table', 'update', 'delete', 'create'
 foreach ($phrase in $phrases) {
  if ($myString -match $phrase) { "Unsupported Phrase Detected: [$phrase]" }
 }
}