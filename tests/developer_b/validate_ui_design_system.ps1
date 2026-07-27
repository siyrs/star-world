$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."

function Read-RequiredText {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing UI design-system contract file: $Path"
  }
  return Get-Content -Raw -Encoding UTF8 $Path
}

function Assert-Matches {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if ($Text -notmatch $Pattern) { throw $Message }
}

function Assert-NotMatches {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if ($Text -match $Pattern) { throw $Message }
}

$paths = [ordered]@{
  tokens = Join-Path $root 'src\ui\design_tokens.gd'
  kit = Join-Path $root 'src\ui\ui_kit.gd'
  theme = Join-Path $root 'src\ui\theme_factory.gd'
  main_menu = Join-Path $root 'src\ui\main_menu.gd'
  responsive_menu = Join-Path $root 'src\ui\responsive_main_menu.gd'
  protected_menu = Join-Path $root 'src\ui\protected_main_menu.gd'
  map = Join-Path $root 'src\ui\map_selection_panel.gd'
  responsive_map = Join-Path $root 'src\ui\responsive_map_selection_panel.gd'
  settings = Join-Path $root 'src\ui\settings_panel.gd'
  save = Join-Path $root 'src\ui\protected_save_browser_panel.gd'
  responsive_save = Join-Path $root 'src\ui\responsive_protected_save_browser_panel.gd'
  game_ui = Join-Path $root 'src\ui\game_ui.gd'
  hud = Join-Path $root 'src\ui\hud.gd'
  guidance = Join-Path $root 'src\ui\guidance_overlay.gd'
  inventory_slot = Join-Path $root 'src\ui\inventory_slot.gd'
  inventory = Join-Path $root 'src\ui\inventory_panel.gd'
  crafting = Join-Path $root 'src\ui\crafting_panel.gd'
  container = Join-Path $root 'src\ui\container_panel.gd'
  journal = Join-Path $root 'src\ui\exploration_journal_panel.gd'
  responsive_journal = Join-Path $root 'src\ui\responsive_exploration_journal_panel.gd'
  diagnostics = Join-Path $root 'src\ui\diagnostics_overlay.gd'
  update_prompt = Join-Path $root 'src\ui\update_prompt_panel.gd'
  unit_test = Join-Path $root 'tests\qa\ui_design_system_regression.gd'
  keyboard_test = Join-Path $root 'tests\qa\menu_keyboard_navigation_regression.gd'
  desktop_test = Join-Path $root 'tests\qa\ui_visual_refresh_desktop_acceptance.gd'
  workflow = Join-Path $root '.github\workflows\ui-visual-refresh-tests.yml'
  run_all = Join-Path $root 'tests\run_all.ps1'
  contract = Join-Path $root 'docs\UI_DESIGN_SYSTEM.md'
  audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-27_ITERATION_44.md'
  testing = Join-Path $root 'docs\TESTING.md'
  roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP.md'
}

$text = @{}
foreach ($name in $paths.Keys) {
  $text[$name] = Read-RequiredText -Path $paths[$name]
}

foreach ($token in @(
  'class_name\s+StarDesignTokens',
  'SPACE_SM\s*:=\s*8',
  'SPACE_LG\s*:=\s*16',
  'SPACE_XL\s*:=\s*24',
  'COLOR_BACKGROUND_DEEP',
  'COLOR_ACCENT_WARM',
  'COLOR_BORDER_FOCUS',
  'func\s+elevated_panel_style',
  'func\s+focus_style',
  'func\s+tone_border'
)) {
  Assert-Matches $text.tokens $token "Semantic UI tokens are missing: $token"
}
Assert-NotMatches $text.tokens 'extends\s+Node|FileAccess|Input\.' 'Design tokens must remain pure and runtime-independent'

foreach ($token in @(
  'class_name\s+StarUiKit',
  'func\s+style_button',
  'func\s+make_eyebrow',
  'func\s+make_badge',
  'func\s+make_section_header',
  'func\s+set_selected_card'
)) {
  Assert-Matches $text.kit $token "Reusable UI Kit is missing: $token"
}
Assert-NotMatches $text.kit 'extends\s+Node|FileAccess|Timer\.new' 'UI Kit must remain a pure component helper'

foreach ($variation in @(
  'DisplayTitle','PageTitle','SectionTitle','EyebrowLabel','MutedLabel',
  'GlassPanel','ElevatedPanel','CommandPanel','CardPanel','InsetPanel','HudPanel','ModalPanel',
  'PrimaryButton','SecondaryButton','GhostButton','DangerButton','MenuPrimaryButton','MenuButton',
  'CardButton','SelectedCardButton','InventorySlot','InventorySlotSelected','InventorySlotSwap',
  'DiagnosticsBackdrop','DiagnosticsCard'
)) {
  Assert-Matches $text.theme ([regex]::Escape($variation)) "Unified theme is missing variation: $variation"
}
Assert-Matches $text.tokens 'COLOR_BORDER_FOCUS' 'Semantic tokens must expose the focus color'
Assert-Matches $text.theme 'focus_style' 'Unified theme must apply the shared high-contrast focus ring'

foreach ($token in @(
  'MainCommandSurface','HeroColumn','CommandDeck','get_visual_snapshot',
  'MenuPrimaryButton','MenuButton','DangerButton','星 的 世 界',
  '开始游戏','地图选择','存档 / 继续','设置','检查更新','退出'
)) {
  Assert-Matches $text.main_menu ([regex]::Escape($token)) "Professional main menu is missing hierarchy or command: $token"
}
Assert-Matches $text.main_menu 'PANEL_SAFE_MARGIN|_apply_responsive_layout' 'Main menu must own responsive viewport safety'
foreach ($token in @('get_viewport_rect','_configure_compact_hero','_configure_compact_command_deck')) {
  Assert-Matches $text.responsive_menu $token "Responsive command deck is missing: $token"
}
foreach ($token in @(
  'responsive_main_menu\.gd',
  'responsive_map_selection_panel\.gd',
  'responsive_protected_save_browser_panel\.gd',
  'func\s+_focus_primary_action',
  'func\s+_focus_first_interactive',
  'ui_cancel'
)) {
  Assert-Matches $text.protected_menu $token "Production menu composition or keyboard contract is missing: $token"
}
foreach ($token in @('get_viewport_rect','custom_minimum_size','MapCatalogScroll')) {
  Assert-Matches $text.responsive_map $token "Responsive map briefing is missing: $token"
}
foreach ($token in @('get_viewport_rect','SaveListScroll','custom_minimum_size')) {
  Assert-Matches $text.responsive_save $token "Responsive save archive is missing: $token"
}
Assert-Matches $text.game_ui 'responsive_exploration_journal_panel\.gd' 'Production GameUI must compose the bounded exploration journal'
foreach ($token in @('get_viewport_rect','MilestoneScroll|_milestone_scroll','RecordScroll|_record_scroll')) {
  Assert-Matches $text.responsive_journal $token "Responsive journal is missing: $token"
}

foreach ($pair in @(
  @('map','MapCatalogScroll'),
  @('map','set_selected_card'),
  @('map','地图简报'),
  @('settings','section_card_count'),
  @('settings','SettingsScroll'),
  @('settings','PrimaryButton'),
  @('save','SaveQueryBar'),
  @('save','DangerButton'),
  @('save','虚拟化 24 行'),
  @('game_ui','OverlayScrim'),
  @('game_ui','ModalPanel'),
  @('game_ui','get_visual_snapshot'),
  @('hud','VitalsCard'),
  @('hud','HotbarDock'),
  @('guidance','ContextPromptCard'),
  @('guidance','TutorialCard'),
  @('inventory','inventory_card'),
  @('crafting','CRAFTING DATABASE'),
  @('container','STORAGE TRANSFER'),
  @('journal','EXPLORATION ARCHIVE'),
  @('diagnostics','DiagnosticsDashboard'),
  @('diagnostics','DiagnosticsCard'),
  @('update_prompt','SECURE RELEASE UPDATE')
)) {
  Assert-Matches $text[$pair[0]] ([regex]::Escape($pair[1])) "UI surface $($pair[0]) is missing professional structure: $($pair[1])"
}

foreach ($variation in @('InventorySlot','InventorySlotSelected','InventorySlotSwap')) {
  Assert-Matches $text.inventory_slot ([regex]::Escape($variation)) "Inventory slots are missing semantic state: $variation"
}
Assert-NotMatches $text.inventory_slot 'StyleBoxFlat\.new\(' 'Inventory slots must consume the shared theme instead of owning ad-hoc boxes'

foreach ($phrase in @(
  'one reusable button variation',
  'main menu exposes six bounded commands',
  'settings groups controls into four scannable sections',
  'blocking gameplay overlay uses one shared scrim',
  'diagnostics dashboard remains fully mouse-passthrough'
)) {
  Assert-Matches $text.unit_test ([regex]::Escape($phrase)) "UI design-system regression is missing assertion: $phrase"
}
foreach ($phrase in @(
  'startup places keyboard focus on the primary expedition action',
  'Enter activates the focused primary action',
  'Escape returns from a cancellable subpage',
  'Tab advances focus through the bounded main-menu command set'
)) {
  Assert-Matches $text.keyboard_test ([regex]::Escape($phrase)) "Keyboard navigation regression is missing assertion: $phrase"
}
foreach ($phrase in @(
  'professional main menu screenshot is saved',
  'map selection screenshot is saved',
  'settings workspace screenshot is saved',
  'save archive screenshot is saved',
  'gameplay HUD screenshot is saved',
  'pause modal screenshot is saved',
  'inventory workspace screenshot is saved',
  'crafting workspace screenshot is saved',
  'exploration journal screenshot is saved',
  'diagnostics dashboard screenshot is saved'
)) {
  Assert-Matches $text.desktop_test ([regex]::Escape($phrase)) "Multi-screen visual acceptance is missing: $phrase"
}

foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_ui_design_system\.ps1',
  'ui_design_system_regression\.gd',
  'menu_keyboard_navigation_regression\.gd',
  'ui_visual_refresh_desktop_acceptance\.gd',
  'ui-visual-refresh-main-menu\.png',
  'ui-visual-refresh-diagnostics\.png',
  'ui-visual-refresh-report\.json'
)) {
  Assert-Matches $text.workflow $token "UI workflow is missing validation or evidence: $token"
}
Assert-Matches $text.run_all 'validate_ui_design_system\.ps1' 'Full regression entry point must include the static UI contract'
Assert-Matches $text.run_all 'ui_design_system_regression\.gd' 'Full regression entry point must include the UI design-system regression'
Assert-Matches $text.run_all 'menu_keyboard_navigation_regression\.gd' 'Full regression entry point must include keyboard navigation'

foreach ($phrase in @('星际远征','8pt','暖金','冷青','键盘焦点','1024×576','1280×720','真实鼠标','Windows Release')) {
  Assert-Matches $text.contract ([regex]::Escape($phrase)) "UI design contract is missing boundary: $phrase"
}
foreach ($phrase in @('视觉层级','同质矩形','重复硬编码','低分辨率','设计令牌','真实桌面')) {
  Assert-Matches $text.audit ([regex]::Escape($phrase)) "Architecture audit is missing finding or decision: $phrase"
}
Assert-Matches $text.testing 'ui_design_system_regression\.gd' 'Testing guide must document the UI domain command'
Assert-Matches $text.testing 'ui_visual_refresh_desktop_acceptance\.gd' 'Testing guide must document the multi-screen desktop journey'
Assert-Matches $text.roadmap '统一专业 UI' 'Product roadmap must record the completed professional UI system'
Assert-Matches $text.roadmap 'UI_DESIGN_SYSTEM\.md' 'Product roadmap must link the UI design contract'

Write-Host 'PASS ui_design_system palette=celestial hierarchy=semantic spacing=8pt focus=visible keyboard=enter|escape|tab menus=responsive overlays=unified screens=10 desktop=real-input release=required'
