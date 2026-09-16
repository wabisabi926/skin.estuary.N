param([string]$SkinDirectory = (Join-Path $PSScriptRoot '..'))

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Assert-True([bool]$Condition, [string]$Message) {
  if (!$Condition) { throw $Message }
}

$documents = @{}
$includes = @{}
$variables = @{}
foreach ($file in Get-ChildItem (Join-Path $SkinDirectory 'xml') -Filter '*.xml') {
  $document = [xml](Get-Content -Raw -LiteralPath $file.FullName)
  $documents[$file.Name] = $document
  foreach ($node in $document.SelectNodes('/includes/include[@name]')) { $includes[$node.GetAttribute('name')] = $node }
  foreach ($node in $document.SelectNodes('/includes/variable[@name]')) { $variables[$node.GetAttribute('name')] = $true }
}

foreach ($name in @('MusicVisualisation.xml', 'MusicOSD.xml', 'Includes_MusicPlayer.xml', 'Includes_MusicBackground.xml',
                    'Custom_1114_MusicPlaylistDialog.xml', 'Custom_1113_MusicAudioDialog.xml', 'script-cu-lrclyrics-main.xml')) {
  $document = $documents[$name]
  Assert-True ($null -ne $document) "Missing XML: $name"
  foreach ($node in $document.SelectNodes('//include[not(@name) and not(@file)]')) {
    $reference = if ($node.HasAttribute('content')) { $node.GetAttribute('content') } else { $node.InnerText }
    Assert-True ($includes.ContainsKey($reference)) "Unresolved include: $name $reference"
  }
  foreach ($match in [regex]::Matches($document.OuterXml, '\$VAR\[([^,\]]+)')) {
    Assert-True ($variables.ContainsKey($match.Groups[1].Value)) "Unresolved variable: $name $match"
  }
  foreach ($node in $document.SelectNodes('//*[starts-with(local-name(),"texture") or local-name()="midtexture" or local-name()="righttexture"]')) {
    if ($node.InnerText -and !$node.InnerText.StartsWith('$')) {
      Assert-True (Test-Path -LiteralPath (Join-Path $SkinDirectory ('media/' + $node.InnerText))) "Missing texture: $name $($node.InnerText)"
    }
  }
  foreach ($glass in $document.SelectNodes('//*[@material="glass"]')) {
    Assert-True ($glass.glassstyle -eq 'regular') "Unknown glass preset: $name"
    foreach ($attribute in $glass.Attributes) {
      Assert-True ($attribute.Name -in @('material', 'glassstyle', 'cornerradius')) "Music must use unchanged glass presets: $name $attribute"
    }
  }
}

function Expand-Includes($node) {
  while ($node.SelectSingleNode('./include')) {
    foreach ($inc in @($node.SelectNodes('./include'))) {
      $name = if ($inc.HasAttribute('content')) { $inc.GetAttribute('content') } else { $inc.InnerText }
      $definition = $includes[$name]
      Assert-True ($null -ne $definition) "Unknown include: $name"
      $parameters = @{}
      foreach ($param in $definition.SelectNodes('./param')) { $parameters[$param.GetAttribute('name')] = $param.InnerText }
      foreach ($param in $inc.SelectNodes('./param')) {
        $parameters[$param.GetAttribute('name')] = if ($param.HasAttribute('value')) { $param.GetAttribute('value') } else { $param.InnerText }
      }
      $body = $definition.SelectSingleNode('./definition')
      if (!$body) { $body = $definition }
      foreach ($child in @($body.ChildNodes)) {
        if ($child.NodeType -ne 'Element' -or $child.Name -eq 'param') { continue }
        $raw = $child.OuterXml
        foreach ($param in $parameters.Keys) { $raw = $raw.Replace('$PARAM[' + $param + ']', [System.Security.SecurityElement]::Escape($parameters[$param])) }
        $fragment = $node.OwnerDocument.CreateDocumentFragment()
        $fragment.InnerXml = $raw
        [void]$node.InsertBefore($fragment, $inc)
      }
      [void]$node.RemoveChild($inc)
    }
  }
  foreach ($child in @($node.SelectNodes('./*'))) { Expand-Includes $child }
}

$page = $documents['MusicVisualisation.xml']
$controls = $documents['Includes_MusicPlayer.xml']
Assert-True ($null -ne $documents['Includes.xml'].SelectSingleNode('//include[@file="Includes_MusicBackground.xml"]')) 'Background definitions must be loaded'
Assert-True ($page.SelectSingleNode('/window/controls/include').InnerText -eq 'NaraMusicPlayerBackground') 'Player background include changed'
Assert-True ($page.window.defaultcontrol.InnerText -eq '602') 'Default focus must remain play/pause'
Assert-True ($page.SelectSingleNode('//control[@id="420"]/left').InnerText -eq '1040') 'Timed lyric column moved'
Assert-True ($page.SelectSingleNode('//control[@id="421"]/left').InnerText -eq '1040') 'Untimed lyric column must align'
Assert-True ($page.SelectSingleNode('//control[@id="420"]/width').InnerText -eq '720') 'Lyrics must retain the right margin'
Assert-True ($page.OuterXml -notmatch 'LOCALIZE\[24013\]|MusicPlayer\.(Codec|SampleRate|BitsPerSample|Channels)') 'Redundant headings or technical flags returned'
$heading = $page.SelectNodes('//control[@type="label" and contains(label,"LOCALIZE[31000]")]')
Assert-True ($heading.Count -eq 1 -and $heading[0].left -eq '40' -and $heading[0].top -eq '28') 'Only the inset top-left now-playing heading is allowed'
$trackPosition = $page.SelectSingleNode('//control[contains(label,"Playlist.Position(music)")]')
Assert-True ($null -ne $trackPosition -and $trackPosition.top -eq '64') 'Missing music track position'
$clock = $page.SelectSingleNode('//control[label="$INFO[System.Time]"]')
$homeClock = $documents['Home.xml'].SelectSingleNode('//control[label="$INFO[System.Time]"]')
Assert-True ($homeClock.visible -eq '!Window.IsVisible(notification) + !Window.IsVisible(extendedprogressdialog)') 'Home clock must yield to notifications and background progress'
Assert-True ($clock.font -eq $homeClock.font -and $clock.right -eq $homeClock.right -and $clock.width -eq $homeClock.width) 'Music clock must match Home font and horizontal position'
Assert-True ([int]$clock.top + [int]$clock.height / 2 -eq ([int]$heading[0].top + [int]$trackPosition.top + [int]$trackPosition.height) / 2) 'Clock must center against both header lines'
foreach ($label in @($heading[0], $trackPosition, $clock)) {
  $font = $documents['Font.xml'].SelectSingleNode('//font[name="' + $label.font + '"]')
  Assert-True ($null -ne $font -and !$font.aspect -and $label.font -notmatch 'narrow') 'Header text must not use condensed fonts or horizontal scaling'
}
$cover = $page.SelectSingleNode('//control[texture="$VAR[NaraMusicCoverVar]"]')
$title = $page.SelectSingleNode('//control[label="$INFO[Player.Title]"]')
Assert-True ($title.left -eq '180' -and $title.width -eq '620') 'Song title space must stay unchanged'
Assert-True ([int]$cover.left + [int]$cover.width / 2 -eq [int]$title.left + [int]$title.width / 2) 'Cover must center over the full title column'
Assert-True ($page.SelectNodes('//*[@material="glass"]').Count -eq 0) 'The clock must be plain text without a glass capsule'
Assert-True ($page.OuterXml -notmatch 'Player.ShowInfo|Player.ShowTime|ColoredBackgroundImages|osdfade') 'Music content must stay persistent and unmasked'
$gate = $page.SelectSingleNode('//include[text()="NaraMusicPlayerControls"]/../visible')
Assert-True ($gate.InnerText -eq '!Window.IsVisible(musicosd)') 'Main controls must not overlap MusicOSD controls'

$lyricsAddon = $documents['script-cu-lrclyrics-main.xml']
$addonList = $lyricsAddon.SelectSingleNode('//control[@id="110"]')
Assert-True ($addonList.type -eq 'list' -and $lyricsAddon.SelectSingleNode('//control[@id="200"]').type -eq 'label') 'CU LRC requires list 110 and source label 200'
Assert-True ($lyricsAddon.SelectNodes('//include | //texture | //texturebackground | //backgroundcolor').Count -eq 0) 'The lyrics overlay must not obscure the music page with a panel or scrim'
$adapterSlide = $addonList.SelectSingleNode('animation[@effect="slide"]')
Assert-True ($adapterSlide.end -eq '0,-10000' -and $adapterSlide.condition.Contains('NaraMusic.IntegratedLyrics')) 'Only the integrated add-on adapter must stay offscreen'
Assert-True ($addonList.top -eq '222') 'Other music modes must retain a visible add-on layout'
Assert-True ($page.OuterXml -notmatch 'script-cu-lrclyrics-main.xml') 'Native lyrics must remain visible and interactive while the add-on runs'
Assert-True ($lyricsAddon.SelectNodes('//onleft | //onright | //onclick | //onload').Count -eq 0) 'The add-on adapter must not introduce a second navigation mode'

$expanded = [xml]$page.OuterXml
Expand-Includes $expanded.window
Assert-True (!$expanded.OuterXml.Contains('$PARAM[')) 'Unresolved player include parameter'
$ids = @($expanded.SelectNodes('//control[@id]'))
Assert-True (@($ids | Group-Object { $_.GetAttribute('id') } | Where-Object Count -gt 1).Count -eq 0) 'Duplicate expanded control IDs'
$buttons = $expanded.SelectNodes('//control[@id="200"]/control/control[@type="radiobutton"]')
$buttonIds = @($buttons | ForEach-Object { $_.GetAttribute('id') })
$order = $buttonIds -join ','
Assert-True ($order -eq '70054,70053,70051,602,600,607,70048') 'Player button order changed'
Assert-True ($buttons[3].onclick -eq 'PlayerControl(Play)') 'Centered button must play/pause'
$checkedIcons = @{}
foreach ($button in $buttons) {
  Assert-True ($button.width -eq '61' -and $button.height -eq '61') 'Buttons must be about 15 percent smaller'
  Assert-True ([int]$button.radiowidth + 2 * [int]$button.radioposx -eq [int]$button.width) 'Icon must center in its button'
  Assert-True ($button.onup -eq '87') 'Every nested button must navigate up to the seek bar'
  Assert-True ($button.texturefocus.colordiffuse -eq 'glass_focus_medium') 'Focus must reuse the shared glass highlight'
  Assert-True ($button.SelectSingleNode('./textureradioonfocus').colordiffuse -eq 'text_primary') 'Focused icons must stay white'
  Assert-True ($button.ParentNode.SelectSingleNode('./control[@type="image"]/texture').glassstyle -eq 'regular') 'Every button needs an independent regular glass background'
  Assert-True ($button.SelectNodes('./*[starts-with(local-name(),"textureradio") and contains(text(),"$VAR[")]').Count -eq 0) 'Radio textures do not support dynamic filenames'
  foreach ($state in @('onfocus', 'onnofocus', 'ondisabled', 'offfocus', 'offnofocus', 'offdisabled')) {
    # The factory uses the first matching texture, including overrides before an include.
    $texture = $button.SelectSingleNode('./textureradio' + $state)
    $path = $texture.InnerText
    Assert-True (![string]::IsNullOrEmpty($path) -and !$path.Contains('$')) "Missing static icon: $($button.id) $state"
    if ($checkedIcons.ContainsKey($path)) { continue }
    $icon = [System.Drawing.Bitmap]::new((Join-Path $SkinDirectory ('media/' + $path)))
    try {
      $visiblePixels = 0
      for ($y = 0; $y -lt $icon.Height; $y++) {
        for ($x = 0; $x -lt $icon.Width; $x++) {
          if ($icon.GetPixel($x, $y).A -gt 0) { $visiblePixels++ }
        }
      }
      Assert-True ($visiblePixels -gt 0) "Icon is fully transparent: $path"
    }
    finally { $icon.Dispose() }
    $checkedIcons[$path] = $true
  }
}
Assert-True ($null -eq $expanded.SelectSingleNode('//control[@id="200"]/texturebackground')) 'OSD buttons must not share a long glass capsule'
$buttonRow = $expanded.SelectSingleNode('//control[@id="200"]')
Assert-True ($buttonRow.itemgap -eq '16') 'Independent buttons need spacing'
Assert-True ([int]$buttonRow.ParentNode.height - [int]$buttonRow.top - [int]$buttonRow.height -eq 20) 'Buttons need 20 pixels of bottom padding'
for ($i = 0; $i -lt $buttons.Count; $i++) {
  Assert-True ($buttons[$i].onleft -eq $buttons[($i + $buttons.Count - 1) % $buttons.Count].id) "Missing direct left navigation: $($buttons[$i].id)"
  Assert-True ($buttons[$i].onright -eq $buttons[($i + 1) % $buttons.Count].id) "Missing direct right navigation: $($buttons[$i].id)"
}
for ($disabled = 0; $disabled -lt (1 -shl $buttons.Count) - 1; $disabled++) {
  for ($i = 0; $i -lt $buttons.Count; $i++) {
    if ($disabled -band (1 -shl $i)) { continue }
    foreach ($direction in @('onleft', 'onright')) {
      $next = $i
      for ($step = 0; $step -lt $buttons.Count; $step++) {
        $target = $buttons[$next].SelectSingleNode('./' + $direction).InnerText
        $next = [array]::IndexOf($buttonIds, $target)
        Assert-True ($next -ge 0) 'Navigation must target an actual button, not an anonymous wrapper'
        if (!($disabled -band (1 -shl $next))) { break }
      }
      Assert-True (!($disabled -band (1 -shl $next))) 'Navigation cannot skip disabled buttons'
    }
  }
}
Assert-True ($buttons[3].selected -eq 'Player.Paused') 'Play/pause must use a native radio state'
Assert-True ($buttons[1].selected -eq 'Playlist.IsRepeatOne') 'Repeat-one must use a native radio state'
foreach ($state in @('focus', 'nofocus', 'disabled')) {
  Assert-True ($buttons[3].SelectSingleNode('./textureradioon' + $state).InnerText -eq 'osd/nara/play.png') "Paused state must display play: $state"
  Assert-True ($buttons[3].SelectSingleNode('./textureradiooff' + $state).InnerText -eq 'osd/nara/pause.png') "Playing state must display pause: $state"
  Assert-True ($buttons[1].SelectSingleNode('./textureradioon' + $state).InnerText -eq 'osd/nara/repeat-one.png') "Repeat-one icon changed: $state"
  Assert-True ($buttons[1].SelectSingleNode('./textureradiooff' + $state).InnerText -eq 'osd/nara/repeat.png') "Repeat icon changed: $state"
}
Assert-True ($expanded.OuterXml -notmatch 'osdfade|colors/black.png|80141418|SeekTimeLabelVar|MediaFlags') 'Unexpected overlay in expanded player'

$nibs = $expanded.SelectNodes('//control[@type="progress" and contains(righttexture,"progress-nib.png")]')
Assert-True ($nibs.Count -eq 2) 'Exactly one playback nib and one seek nib are allowed'
Assert-True ($nibs[0].info -eq 'Player.Progress' -and $nibs[0].visible -eq '!Player.Seeking') 'Playback nib binding changed'
Assert-True ($nibs[1].info -eq 'Player.SeekBar' -and $nibs[1].visible -eq 'Player.Seeking') 'Seek nib must be mutually exclusive'
$mouseSlider = $expanded.SelectSingleNode('//control[@type="slider"]')
foreach ($name in @('textureslidernib', 'textureslidernibfocus', 'textureslidernibdisabled', 'texturesliderbardisabled')) {
  $texture = $mouseSlider.SelectSingleNode('./' + $name)
  Assert-True ($null -ne $texture -and !$texture.InnerText) "Invisible mouse slider inherits a default texture: $name"
}
Assert-True ($documents['Defaults.xml'].SelectSingleNode('//default[@type="progress"]/overlaytexture').InnerText -eq '') 'A default progress overlay would add a second marker'
$seekGroup = $mouseSlider.ParentNode
Assert-True ([int]$buttonRow.top - ([int]$seekGroup.top + 11) -ge 24) 'Seek bar and buttons need at least 24 pixels of visual separation'
$track = $seekGroup.SelectSingleNode('./control[@type="image"]')
$videoTrack = $documents['VideoOSD.xml'].SelectSingleNode('//control[@id="6000"]/control[@type="image"]')
Assert-True ($track.top -eq $videoTrack.top -and $track.height -eq $videoTrack.height -and $track.texture.OuterXml -eq $videoTrack.texture.OuterXml) 'Music seek track must match video styling'
Assert-True ($seekGroup.SelectNodes('.//*[@material="glass"]').Count -eq 0) 'The seek bar must not use glass'
$fileManagerFanart = $documents['FileManager.xml'].SelectSingleNode('//control[contains(texture,"NaraFileManagerRandomFanartVar")]')
Assert-True ($fileManagerFanart.visible -notmatch 'Player.HasAudio' -and $fileManagerFanart.visible -match 'Player.HasVideo') 'Music startup must retain file manager fanart without changing video gating'

# These modeless windows are drawn after the fullscreen page.
$eligibility = 'Window.IsActive(fullscreenvideo) | [Window.IsActive(visualisation) + PVR.IsPlayingRadio]'
foreach ($name in @('DialogSeekBar.xml', 'Custom_1109_TopBarOverlay.xml')) {
  Assert-True ($documents[$name].SelectSingleNode('/window/visible').InnerText -eq $eligibility) "Legacy overlay is not isolated: $name"
}

$background = $documents['Includes_MusicBackground.xml']
Assert-True ($background.SelectNodes('//control[@type="image"]').Count -eq 1) 'Static background must use one image'
Assert-True ($background.SelectNodes('//animation|//control[@type="multiimage" or @type="visualisation" or @type="videowindow"]').Count -eq 0) 'Background must not animate or start another renderer'
Assert-True ($background.SelectSingleNode('//texture').InnerText -eq 'osd/nara/music-background.png') 'Wrong wallpaper'
$wallpaper = [System.Drawing.Bitmap]::new((Join-Path $SkinDirectory 'media/osd/nara/music-background.png'))
try {
  Assert-True ($wallpaper.Width -ge 1600 -and [Math]::Abs($wallpaper.Width / [double]$wallpaper.Height - 16.0/9) -lt 0.01) 'Wallpaper must be high-resolution widescreen'
  Assert-True (($wallpaper.PixelFormat -band [System.Drawing.Imaging.PixelFormat]::Indexed) -eq 0) 'Indexed PNG swaps red and blue in the existing TexturePacker; use true color'
}
finally { $wallpaper.Dispose() }

$playlist = $documents['Custom_1114_MusicPlaylistDialog.xml']
Assert-True ($playlist.window.id -eq '1114') 'Music playlist must have an independent dialog ID'
Assert-True ($controls.SelectSingleNode('//control[@id="70051"]/onclick').InnerText -eq 'ActivateWindow(1114)') 'Music controls must open the music-only playlist'
Assert-True ($playlist.SelectSingleNode('//content').focusplaying -eq 'true') 'Playlist must focus the playing item'
Assert-True ($playlist.SelectSingleNode('//content').InnerText -eq 'playlistmusic://?reload=$INFO[Playlist.Position(music)]') 'Music playlist provider changed'
$panelImages = $includes['NaraMusicPlaylistBackground'].SelectNodes('.//control[@type="image"]')
Assert-True ($panelImages.Count -eq 10) 'Short-playlist panel variants changed'
$referencePanel = $documents['FileManager.xml'].SelectSingleNode('//texture[@material="glass"]')
$referenceFocus = $documents['FileManager.xml'].SelectSingleNode('//focusedlayout/control[texture="lists/focus.png"]')
Assert-True ($referenceFocus.texture.colordiffuse -eq 'glass_focus_medium') 'File Manager and music popup rows must use the shared medium highlight'
for ($i = 0; $i -lt 10; $i++) {
  Assert-True ($panelImages[$i].texture.glassstyle -eq 'regular') 'Every music panel must use regular glass'
  Assert-True ($panelImages[$i].texture.cornerradius -eq $referencePanel.cornerradius) 'Music panel corners must match File Manager'
  Assert-True ([int]$panelImages[$i].top -eq 252 - 28 * $i) 'Short-playlist centering changed'
  if ($i -lt 9) { Assert-True ([int]$panelImages[$i].height -eq 166 + 56 * $i) 'Short-playlist panel height changed' }
  else { Assert-True ($panelImages[$i].bottom -eq '0') 'Full playlist panel must fill its group' }
}
$focus = $playlist.SelectSingleNode('//focusedlayout/control[texture/@colordiffuse="glass_focus_medium"]')
Assert-True ($focus.top -eq $referenceFocus.top -and $focus.bottom -eq $referenceFocus.top) 'Playlist focus must retain 3-pixel vertical padding'
Assert-True ($focus.texture.colordiffuse -eq $referenceFocus.texture.colordiffuse) 'Playlist focus must reuse File Manager color'
Assert-True ($focus.texture.InnerText -eq 'colors/white.png' -and $focus.texture.cornerradius -eq '4' -and !$focus.texture.HasAttribute('border')) 'Short popup rows need a single rounded quad, not overlapping nine-slice borders'
$audio = $documents['Custom_1113_MusicAudioDialog.xml']
Assert-True ($audio.SelectSingleNode('//texture[@material="glass" and @cornerradius="42"]').glassstyle -eq 'regular') 'Audio panel must use regular glass'
$audioFocus = $audio.SelectSingleNode('//control[texture/@colordiffuse="glass_focus_medium"]')
$mute = $audio.SelectSingleNode('//control[@id="11"]')
Assert-True ($audioFocus.texture.OuterXml -eq $focus.texture.OuterXml) 'Audio and playlist popups must use identical seam-free focus'
Assert-True ([int]$audioFocus.top - [int]$mute.top -eq 3 -and [int]$mute.height - [int]$audioFocus.height -eq 6) 'Audio focus must retain 3-pixel vertical padding'
Assert-True ($audioFocus.visible -eq 'Control.HasFocus(11)' -and !$mute.texturefocus.InnerText) 'Mute focus must render once'
$videoPlaylist = $documents['Custom_1112_OSDPlaylistDialog.xml']
Assert-True ($videoPlaylist.OuterXml -notmatch 'NaraMusic|Player.HasAudio|material="glass"') 'Video playlist must not contain music-specific styles'
Assert-True ($videoPlaylist.SelectSingleNode('//content').InnerText -eq 'playlistvideo://?reload=$INFO[Playlist.Position(video)]') 'Video playlist provider must stay unchanged'
Assert-True ($null -eq $documents['Includes_DialogSelect.xml'].SelectSingleNode('//include[@name="NaraStreamDialogPanel"]')) 'Shared video dialog must not contain a music glass branch'

foreach ($name in @('Custom_1114_MusicPlaylistDialog.xml', 'Custom_1113_MusicAudioDialog.xml')) {
  $popup = [xml]$documents[$name].OuterXml
  Expand-Includes $popup.window
  Assert-True (!$popup.OuterXml.Contains('$PARAM[')) "Unresolved popup parameter: $name"
  $ids = @($popup.SelectNodes('//control[@id]'))
  Assert-True (@($ids | Group-Object { $_.GetAttribute('id') } | Where-Object Count -gt 1).Count -eq 0) "Duplicate popup IDs: $name"
}
Assert-True ($documents['Custom_1113_MusicAudioDialog.xml'].OuterXml -notmatch 'colors/black.png|osdfade') 'Music audio popup must be glass without a black scrim'

Write-Output "PASS: $($documents.Count) XML files; expanded music controls/popups, legacy overlay isolation, single nib, static wallpaper, regular glass, File Manager focus styling and independent video dialog checked."
