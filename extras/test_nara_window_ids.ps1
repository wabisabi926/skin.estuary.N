param([string]$SkinDirectory = (Join-Path $PSScriptRoot '..'))

$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
  if (!$Condition) { throw $Message }
}

$windows = @{}
$hubId = $null
$xmlDirectory = Join-Path $SkinDirectory 'xml'
foreach ($file in Get-ChildItem -LiteralPath $xmlDirectory -Filter 'Custom*.xml') {
  $document = [xml](Get-Content -Raw -LiteralPath $file.FullName)
  $root = $document.SelectSingleNode('/window')
  Assert-True ($null -ne $root) "Missing window root: $($file.Name)"
  $idText = $root.GetAttribute('id')
  if (!$idText) { $idText = $root.SelectSingleNode('id').InnerText }
  $id = 0
  Assert-True ([int]::TryParse($idText, [ref]$id)) "Invalid window ID: $($file.Name)"
  Assert-True (!$windows.ContainsKey($id)) "Duplicate window ID ${id}: $($windows[$id]) and $($file.Name)"
  $windows[$id] = $file.Name
  if ($file.Name -match '^Custom_(\d+)_') {
    Assert-True ([int]$Matches[1] -eq $id) "Filename/window ID mismatch: $($file.Name)"
  }
  if ($file.Name -like 'Custom_*_SettingsHub.xml') {
    Assert-True ($null -eq $hubId) 'Multiple settings hub windows'
    Assert-True ($root.GetAttribute('type') -eq 'dialog') 'Settings hub must be a dialog'
    $hubId = $id
  }
}

Assert-True ($null -ne $hubId) 'Settings hub window missing'
$repository = (Resolve-Path (Join-Path $SkinDirectory '../..')).Path
$header = Get-Content -Raw -LiteralPath (Join-Path $repository 'xbmc/guilib/WindowIDs.h')
$homeIdMatch = [regex]::Match($header, '(?m)^#define\s+WINDOW_HOME\s+(\d+)')
$hub = [regex]::Match($header, '(?m)^#define\s+WINDOW_DIALOG_NARA_SETTINGS_HUB\s+(\d+)')
Assert-True ($homeIdMatch.Success -and $hub.Success) 'Missing core window IDs'
Assert-True ([int]$hub.Groups[1].Value -eq [int]$homeIdMatch.Groups[1].Value + $hubId) 'Core and skin settings hub IDs differ'

$settings = [xml](Get-Content -Raw -LiteralPath (Join-Path $xmlDirectory 'Includes_Settings.xml'))
$entry = $settings.SelectSingleNode('/includes/include[@name="NaraSettingsHubEntry"]')
$actions = @($entry.SelectNodes('.//onclick[@condition="$PARAM[modal]"]') | ForEach-Object { $_.InnerText })
Assert-True ($actions.Count -eq 2) 'Missing modal settings entry actions'
Assert-True ($actions[0] -eq ('SetProperty(SettingsHub.Target,$PARAM[target],{0})' -f $hubId)) 'Settings target property uses the wrong window'
Assert-True ($actions[1] -eq "Dialog.Close($hubId)") 'Settings entry closes the wrong window'
$context = $settings.SelectSingleNode('/includes/expression[@name="nara_settings_context"]').InnerText
Assert-True ($context.Contains("Window.IsActive($hubId)")) 'Settings context omits the hub window'
foreach ($match in [regex]::Matches($context, 'Window\.IsActive\((\d+)\)')) {
  $id = [int]$match.Groups[1].Value
  if ($windows.ContainsKey($id)) {
    Assert-True ($id -eq $hubId) "Unrelated custom window in settings context: $($windows[$id])"
  }
}

Write-Output "PASS: $($windows.Count) unique custom window IDs; settings hub registration and actions agree ($hubId)."
