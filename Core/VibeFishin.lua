-- VibeFishin v4.1.0 - WoW Forever (Interface 16001)
-- Main controller for WoW Forever. Player actions are never automated.
local ADDON = ...
local aquariumController = CreateFrame('Frame')
local characterSettings
local active, casting, manual = false, false, false
local ticker, now = 0, 0
local aquariumWindow, welcome, castTimerWindow, optionsWindow, aquariumCanvas, optionsProxy = nil, nil, nil, nil, nil, nil
local swimmingFish, bubbles, foodPellets = {}, {}, {}
local fishFramePool, bubbleFramePool, foodPelletPool = {}, {}, {}
local displayedTreasureFrames, treasureFramePool = {}, {}
aquariumController.fishVitality = 100
aquariumController.lastTempTick = 0
aquariumController.zoneAmbient = 68
local floatingPlants, floatingPlantPool = {}, {}
local repopulatePlants
local splashDroplets, splashDropletPool = {}, {}
local splashRings, splashRingPool = {}, {}
local seaweedFrames = {}
local sandGrains, ambientChest = {}, nil
local splashStart, splashX, splashY = 0, 0, 0
local splashDuration = 1.2
local arrivingFishItemID, arrivingFishFrame = nil, nil
local MIN_TANK_WIDTH, MIN_TANK_HEIGHT = 420, 300
local feedingUntil, lastBagRefresh = 0, 0
local fishCooldownByID = {}
local EAT_SECONDS, FED_COOLDOWN = 5, 300
local FOOD_WINDOW_SECONDS = 120 -- Time available for slow or distant fish to reach a pellet.
local lastFishingSignal = 0
local lastChannelSeen = 0
local repopulateAquarium, updateStatus
local pendingBaitAt, baitRetryAt = nil, 0
local activeCastEnd = 0
local catchRevealWindow, catchPreviewEnds = nil, 0
local previewClock = 0
local previewParticles = {}
local baitMacroReady = false
local lastBaitReminder = 0
local minimapButton
local auctionPriceProvider, lastPriceCheck = nil, 0
local updateFishValue, detectPriceSource
local displayedFishEntries = {}
local schoolTerritories = {}
local premiumFishIDs = {}
local cookingIngredients = {}
local cookingRecipesReady = false
local flyingCatchIcon = nil
-- Store handoff state on the addon controller: WoW's Lua 5.1 main chunk
-- has a strict limit of 200 local variables.
local previewFlightClock = 0
local previewFlightDuration = 1.4
local treasureDrop = nil
local treasureDropClock = 0
local treasureDropDuration = 1.85
local sinkingBubbles, sinkingBubblePool = {}, {}
local sandCloud, sandCloudPool = {}, {}
local sandCloudAge = 0
local sandCloudDuration = 1.05
local queuedCatch = nil
local startTreasureDrop, animateTreasureDrop, makeSinkBubble
local previousFacing, waterTurnImpulse, waterSurfaceMomentum = nil, 0, 0
local overflowDroplets, overflowDropletPool = {}, {}
local spillAccumulator = 0
local spawnSpill -- forward declaration: catch splash and facing-based slosh share this emitter
local lastFacingSample = 0

-- WoW Forever and recent clients expose item info on C_Item, not necessarily GetItemInfo.
-- Keep the legacy tuple contract and safely handle uncached items.
local legacyGetItemInfo = GetItemInfo
-- Retrieves item metadata through the Forever client item API.
local function GetItemInfo(item)
  local api = (C_Item and C_Item.GetItemInfo) or legacyGetItemInfo
  if type(api) ~= 'function' then return nil end
  local ok, a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q = pcall(api,item)
  if ok then return a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q end
  return nil
end
local EMPTY = {}

-- ============================================================================
-- Saved data defaults
-- Per-character preferences, fish records and visual state.
-- ============================================================================
local defaults = {
  welcome = false,
  themeID = 'abyss',
  autoPole = true,
  autoPoleDetect = false,
  autoBait = true,
  showTimer = true,
  catchPanel = true,
  alwaysShowAquarium = false,
  inventoryFish = false,
  adaptiveFishSize = true,
  animationFPS = 20,
  lowImpactMode = false,
  catchPreview = true,
  showFishValue = false,
  highlightMostValuable = true,
  showCookingBadges = true,
  ambientChest = true,
  movingSand = true,
  heaterPower = 25,
  fishVitality = 100,
  fishHunger = 100,
  settingsX = 0,
  settingsY = 18,
  cookableReagents = {},
  priceAutoDetected = false,
  minimapAngle = 225,
  showMinimapIcon = true,
  schooling = true,
  waterMotion = true,
  opacity = 0.94,
  width = 440,
  height = 310,
  x = -30,
  treasures = {},
  plants = {},
  y = -75,
  timerX = 0,
  timerY = -125,
  timerScale = 1.0,
  -- v3 record schema: one immutable ID per caught aquarium resident.
  nextResidentID = 0,
  residents = {},
  bagResidents = {},
  catchJournal = { species = {}, achievements = {}, totalCaught = 0, rarestQuality = 1 },
  catches = {},
  deadFish = {},
  total = 0,
}

local lureNames = {
  'fishing lure', 'lure', 'bauble', 'bait', 'worm', 'spinner', 'attractor',
  'aquadynamic', 'shiny bauble', 'bright baubles', 'flesh eating worm', 'nightcrawlers',
}

-- ============================================================================
-- Shared UI and numeric helpers
-- Small constructors and safe math helpers used by each subsystem.
-- ============================================================================
-- Clears an existing table in-place so other references remain valid.
local function wipeTable(t)
  if not t then return end
  if wipe then
    wipe(t)
    return
  end
  for k in pairs(t) do t[k] = nil end
end

-- Merges missing default values into loaded per-character settings.
local function copyDefaults(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      if type(v) == 'table' then
        dst[k] = {}
        copyDefaults(dst[k], v)
      else
        dst[k] = v
      end
    elseif type(v) == 'table' and type(dst[k]) == 'table' then
      copyDefaults(dst[k], v)
    end
  end
end

-- Wraps chat labels with the addon accent color.
local function colorText(text)
  return '|cff7ce8d8' .. text .. '|r'
end
-- Prints a prefixed VibeFishin message to the default chat frame.
local function say(t)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(colorText('VibeFishin')..'  '..t) end
end
-- Clamps a numeric value to the given lower and upper limits.
local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi else return v end
end
-- Creates and anchors a lightweight frame with the requested dimensions.
local function ui(parent, w, h, point, rel, dx, dy)
  local f = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
  f:SetSize(w, h)
  f:SetPoint(point or 'CENTER', rel or parent, point or 'CENTER', dx or 0, dy or 0)
  return f
end

-- v4 visual design system. All palettes are built from WoW-safe color values.
-- The Classic palette references Blizzard's own dialog artwork (not bundled).
aquariumController.themePalettes = {
  abyss={name='Abyss',description='Deep ocean teal and luminous sea glass',
    border={.18,.66,.71,1},panel={.018,.063,.090,.97},header={.035,.16,.20,.98},
    button={.055,.20,.25,1},hover={.09,.34,.39,1},accent={.35,.92,.86,1},
    text={.89,.98,.96,1},muted={.51,.77,.78,1},water={.015,.39,.47,.35},gold={.95,.76,.42,1}},
  midnight={name='Midnight',description='Minimal charcoal and cool electric blue',
    border={.25,.32,.45,1},panel={.018,.022,.036,.98},header={.045,.052,.079,.99},
    button={.075,.09,.14,1},hover={.13,.18,.27,1},accent={.52,.72,1,1},
    text={.92,.94,1,1},muted={.58,.64,.78,1},water={.08,.15,.28,.28},gold={.65,.78,1,1}},
  classic={name='WoW Classic',description='Blizzard parchment and antique gold frame',
    border={.75,.56,.28,1},panel={.13,.095,.06,.98},header={.23,.15,.075,.98},
    button={.22,.15,.085,1},hover={.38,.27,.14,1},accent={1,.82,.42,1},
    text={1,.89,.68,1},muted={.78,.68,.50,1},water={.12,.29,.35,.27},gold={1,.78,.34,1},blizzard=true},
  coral={name='Coral Reef',description='Warm sunset coral and tropical jade',
    border={.96,.52,.48,1},panel={.11,.055,.080,.98},header={.27,.095,.13,.98},
    button={.25,.11,.16,1},hover={.38,.17,.20,1},accent={1,.70,.57,1},
    text={1,.94,.89,1},muted={.91,.70,.70,1},water={.04,.45,.40,.29},gold={1,.85,.45,1}},
  emerald={name='Emerald Grotto',description='Forest greens and luminous jade',
    border={.22,.62,.46,1},panel={.035,.080,.062,.98},header={.065,.19,.13,.98},
    button={.075,.23,.17,1},hover={.11,.37,.26,1},accent={.49,.98,.68,1},
    text={.89,1,.90,1},muted={.58,.78,.65,1},water={.045,.35,.23,.31},gold={.85,.98,.56,1}},
  arcane={name='Arcane',description='Violet magic and mana-blue highlights',
    border={.54,.41,.86,1},panel={.055,.038,.10,.98},header={.11,.070,.22,.98},
    button={.15,.085,.24,1},hover={.26,.15,.38,1},accent={.76,.59,1,1},
    text={.94,.89,1,1},muted={.69,.61,.85,1},water={.20,.16,.48,.29},gold={.93,.74,1,1}},
  frost={name='Frostbound',description='Arctic blue and silver ice',
    border={.47,.76,.90,1},panel={.033,.085,.14,.98},header={.08,.22,.31,.98},
    button={.10,.27,.35,1},hover={.15,.38,.45,1},accent={.74,.96,1,1},
    text={.94,.98,1,1},muted={.69,.84,.92,1},water={.13,.53,.69,.31},gold={.91,.96,1,1}},
  sunset={name='Sunken Sunset',description='Burnished copper and amber ocean',
    border={.76,.43,.27,1},panel={.12,.060,.054,.98},header={.24,.11,.075,.98},
    button={.25,.13,.095,1},hover={.39,.22,.13,1},accent={1,.69,.38,1},
    text={1,.93,.81,1},muted={.86,.69,.55,1},water={.22,.23,.29,.32},gold={1,.82,.44,1}}
}
aquariumController.themeOrder={'abyss','midnight','classic','coral','emerald','arcane','frost','sunset'}
aquariumController.rarityAccentRGB={{.67,.79,.80},{.32,.87,.48},{.36,.65,1},{.72,.43,.97},{1,.74,.28}}
aquariumController.themeFrames={}
aquariumController.themeButtons={}
aquariumController.themeAccentTextures={}
aquariumController.themeTextObjects={}
aquariumController.themeTintTextures={}
aquariumController.currentTheme=function()
  return aquariumController.themePalettes[(characterSettings and characterSettings.themeID) or 'abyss']
    or aquariumController.themePalettes.abyss
end
aquariumController.styleThemeFrame=function(frame,role)
  if not frame or not frame.SetBackdrop then return end
  local p=aquariumController.currentTheme()
  local edge=p.border
  local fill=(role=='button') and p.button or p.panel
  if role=='glass' then fill=p.water end
  -- Use Blizzard's sliced border artwork ONLY for large top-level windows.
  -- A whole button image as a backdrop is stretched/tiled and produces the
  -- red strips seen at reduced UI scales in the v4.0 screenshots.
  local largeClassic = p.blizzard and role=='window'
  if largeClassic then
    frame:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',
      edgeFile='Interface\\DialogFrame\\UI-DialogBox-Border',
      tile=false,edgeSize=24,insets={left=10,right=10,top=10,bottom=10}})
    frame:SetBackdropColor(unpack(p.panel))
    frame:SetBackdropBorderColor(1,.86,.58,1)
  else
    frame:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',
      edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1,
      insets={left=1,right=1,top=1,bottom=1}})
    frame:SetBackdropColor(unpack(fill))
    frame:SetBackdropBorderColor(unpack(edge))
  end
end
aquariumController.applyTheme=function()
  local p=aquariumController.currentTheme()
  for frame,role in pairs(aquariumController.themeFrames) do
    if frame then aquariumController.styleThemeFrame(frame,role) end
  end
  for button in pairs(aquariumController.themeButtons) do
    if button and button.text then button.text:SetTextColor(unpack(p.text)) end
  end
  for texture,alpha in pairs(aquariumController.themeAccentTextures) do
    if texture then texture:SetColorTexture(p.accent[1],p.accent[2],p.accent[3],type(alpha)=='number' and alpha or .19) end
  end
  for font,role in pairs(aquariumController.themeTextObjects) do
    if font then font:SetTextColor(unpack(p[role] or p.text)) end
  end
  for texture in pairs(aquariumController.themeTintTextures) do
    if texture then texture:SetVertexColor(unpack(p.accent)) end
  end
  if catchRevealWindow then
    if catchRevealWindow.header then catchRevealWindow.header:SetColorTexture(unpack(p.header)) end
    if catchRevealWindow.rule then catchRevealWindow.rule:SetColorTexture(unpack(p.accent)) end
    if catchRevealWindow.eyebrow then catchRevealWindow.eyebrow:SetTextColor(unpack(p.gold)) end
    if catchRevealWindow.title then catchRevealWindow.title:SetTextColor(unpack(p.accent)) end
  end
  if welcome and welcome.head then welcome.head:SetColorTexture(unpack(p.header)) end
  if aquariumWindow then
    if aquariumWindow.header then aquariumWindow.header:SetColorTexture(unpack(p.header)) end
    if aquariumWindow.trim then aquariumWindow.trim:SetColorTexture(unpack(p.accent)) end
    if aquariumWindow.water then aquariumWindow.water:SetColorTexture(unpack(p.water)) end
    if aquariumWindow.title then aquariumWindow.title:SetTextColor(unpack(p.text)) end
    if aquariumWindow.glow then aquariumWindow.glow:SetColorTexture(p.accent[1],p.accent[2],p.accent[3],.13) end
    if aquariumWindow.surfaceWave then aquariumWindow.surfaceWave:SetColorTexture(p.accent[1],p.accent[2],p.accent[3],.25) end
    if aquariumWindow.status then aquariumWindow.status:SetTextColor(unpack(p.accent)) end
    if aquariumWindow.count then aquariumWindow.count:SetTextColor(unpack(p.muted)) end
    if aquariumWindow.footer then aquariumWindow.footer:SetColorTexture(unpack(p.header)) end
    if aquariumWindow.footerLine then aquariumWindow.footerLine:SetColorTexture(unpack(p.accent)) end
    if aquariumWindow.roster then
      if aquariumWindow.roster.scrollAccent then aquariumWindow.roster.scrollAccent:SetColorTexture(unpack(p.accent)) end
      if aquariumWindow.roster.header then aquariumWindow.roster.header:SetTextColor(unpack(p.text)) end
      if aquariumWindow.roster.subtitle then aquariumWindow.roster.subtitle:SetTextColor(unpack(p.muted)) end
      if aquariumWindow.roster.headBand then aquariumWindow.roster.headBand:SetColorTexture(unpack(p.header)) end
    end
  end
  if optionsWindow then
    if optionsWindow.headerRule then optionsWindow.headerRule:SetColorTexture(unpack(p.accent)) end
    if optionsWindow.head then optionsWindow.head:SetColorTexture(unpack(p.header)) end
    if optionsWindow.heading then optionsWindow.heading:SetTextColor(unpack(p.text)) end
    if optionsWindow.footer then optionsWindow.footer:SetColorTexture(unpack(p.header)) end
    if optionsWindow.themeName then optionsWindow.themeName:SetText(p.name); optionsWindow.themeName:SetTextColor(unpack(p.accent)) end
    if optionsWindow.RefreshThemeCards then optionsWindow:RefreshThemeCards() end
    if optionsWindow.Refresh then optionsWindow:Refresh() end
    if optionsWindow.activatePage and optionsWindow.activePage then
      optionsWindow.activatePage(optionsWindow.activePage)
    end
  end
  if castTimerWindow then
    if castTimerWindow.caption then castTimerWindow.caption:SetTextColor(unpack(p.gold)) end
    if castTimerWindow.clock then castTimerWindow.clock:SetTextColor(unpack(p.accent)) end
  end
  if aquariumController.tempWidget then
    if aquariumController.tempWidget.readout then aquariumController.tempWidget.readout:SetTextColor(unpack(p.gold)) end
  end
  if aquariumWindow and aquariumWindow.roster and aquariumWindow.roster:IsShown() and aquariumController.renderFishRoster then
    aquariumController.renderFishRoster()
  end
end

-- Applies a frame backdrop and compatible border colors.
local function backdrop(f, border, fill)
  if not f or not f.SetBackdrop then return end
  f:SetBackdrop({
    bgFile = 'Interface\\Buttons\\WHITE8X8',
    edgeFile = 'Interface\\Buttons\\WHITE8X8',
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  f:SetBackdropColor(unpack(fill or {0.04, 0.11, 0.14, 0.94}))
  f:SetBackdropBorderColor(unpack(border or {0.50, 0.73, 0.69, 1}))
  if aquariumController.themeFrames then aquariumController.themeFrames[f]='panel' end
end

-- Applies the configured opacity to a UI frame.
local function applyAlpha(frame)
  if not frame or not characterSettings then return end
  frame:SetAlpha(characterSettings.opacity or 0.94)
end

-- Creates a left-anchored, styled font string.
local function label(p, s, size, x, y, r, g, b, a)
  local f = p:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  f:SetFont('Fonts\\FRIZQT__.TTF', size or 12, 'OUTLINE')
  f:SetPoint('TOPLEFT', p, 'TOPLEFT', x or 0, y or 0)
  f:SetText(s or '')
  f:SetTextColor(r or 0.92, g or 0.94, b or 0.88, a or 1)
  return f
end

-- Creates a text button that calls its handler only on user interaction.
local function btn(p, txt, w, h, x, y, cb)
  local b = CreateFrame('Button', nil, p, 'BackdropTemplate')
  b:SetSize(w, h)
  b:SetPoint('TOPLEFT', p, 'TOPLEFT', x, y)
  backdrop(b, {0.47, 0.71, 0.67, 1}, {0.08, 0.20, 0.22, 1})
  aquariumController.themeFrames[b]='button'
  aquariumController.themeButtons[b]=true
  local gloss = b:CreateTexture(nil, 'ARTWORK')
  gloss:SetPoint('TOPLEFT', 1, -1)
  gloss:SetPoint('TOPRIGHT', -1, -1)
  gloss:SetHeight(h * 0.45)
  gloss:SetColorTexture(1, 1, 1, 0.06)
  local l = b:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  l:SetPoint('CENTER')
  l:SetFont('Fonts\\FRIZQT__.TTF', 11, 'OUTLINE')
  l:SetText(txt)
  b.text = l
  b.gloss = gloss
  b:SetScript('OnClick', cb)
  b:SetScript('OnEnter', function(self)
    local p=aquariumController.currentTheme()
    if not p.blizzard then self:SetBackdropColor(unpack(p.hover)) end
  end)
  b:SetScript('OnLeave', function(self)
    aquariumController.styleThemeFrame(self,'button')
  end)
  aquariumController.styleThemeFrame(b,'button')
  l:SetTextColor(unpack(aquariumController.currentTheme().text))
  return b
end

-- Draw a real box and texture tick: glyph-based checkbox characters are missing in some WoW fonts.
-- Constructs a checkbox bound to a saved preference.
local function checkButton(p, txt, x, y, key, onChange)
  local b = btn(p, '', 390, 28, x, y, function(self)
    characterSettings[key] = not characterSettings[key]
    self:Refresh()
    if onChange then onChange(characterSettings[key]) end
  end)
  b.text:SetText('')
  local square = CreateFrame('Frame', nil, b, 'BackdropTemplate')
  square:SetSize(17, 17)
  square:SetPoint('LEFT', b, 'LEFT', 10, 0)
  backdrop(square, {0.46,0.75,0.71,1}, {0.02,0.08,0.10,1})
  aquariumController.themeFrames[square]='button'
  local checked = square:CreateTexture(nil, 'OVERLAY')
  checked:SetTexture('Interface\\Buttons\\UI-CheckBox-Check')
  checked:SetSize(22,22)
  checked:SetPoint('CENTER')
  local title = b:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  title:SetFont('Fonts\\FRIZQT__.TTF', 11, 'OUTLINE')
  title:SetPoint('LEFT', square, 'RIGHT', 9, 0)
  title:SetTextColor(0.89,0.96,0.90)
  title:SetText(txt)
  aquariumController.themeTextObjects[title]='text'
  aquariumController.themeTintTextures[checked]=true
  function b:Refresh()
    checked:SetShown(not not characterSettings[key])
    square:SetBackdropColor(unpack(characterSettings[key] and aquariumController.currentTheme().hover or aquariumController.currentTheme().panel))
  end
  b:Refresh()
  return b
end

-- Constructs a saved slider with range, step and display formatting.
local function simpleSlider(parent, title, x, y, width, low, high, step, key, fmt, onChange)
  local holder = CreateFrame('Frame', nil, parent)
  holder:SetSize(width, 42)
  holder:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y)

  local name = holder:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  name:SetFont('Fonts\\FRIZQT__.TTF', 11, 'OUTLINE')
  name:SetPoint('TOPLEFT', 0, 0)
  name:SetText(title)
  name:SetTextColor(0.92, 0.95, 0.88)
  aquariumController.themeTextObjects[name]='text'

  local valueText = holder:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  valueText:SetFont('Fonts\\FRIZQT__.TTF', 11, 'OUTLINE')
  valueText:SetPoint('TOPRIGHT', 0, 0)
  valueText:SetTextColor(0.52, 0.98, 0.87)
  aquariumController.themeTextObjects[valueText]='accent'

  local bar = CreateFrame('Button', nil, holder, 'BackdropTemplate')
  bar:SetSize(width, 12)
  bar:SetPoint('BOTTOMLEFT', 0, 2)
  backdrop(bar, {0.23, 0.58, 0.56, 1}, {0.02, 0.09, 0.11, 0.95})
  aquariumController.themeFrames[bar]='button'

  local fill = bar:CreateTexture(nil, 'ARTWORK')
  fill:SetPoint('LEFT', 1, 0)
  fill:SetHeight(10)
  fill:SetColorTexture(0.17, 0.80, 0.75, 0.62)
  aquariumController.themeAccentTextures[fill]=.72

  local thumb = CreateFrame('Frame', nil, bar, 'BackdropTemplate')
  thumb:SetSize(12, 20)
  backdrop(thumb, {0.72, 0.88, 0.82, 1}, {0.14, 0.33, 0.34, 1})
  aquariumController.themeFrames[thumb]='button'

  local function render(value)
    local pct = 0
    if high > low then pct = (value - low) / (high - low) end
    pct = clamp(pct, 0, 1)
    local px = pct * (width - 2)
    fill:SetWidth(math.max(8, px))
    thumb:ClearAllPoints()
    thumb:SetPoint('CENTER', bar, 'LEFT', px, 0)
    valueText:SetText(fmt and fmt:format(value) or tostring(value))
  end

  local function setFromMouse(self)
    local xPos = select(1, GetCursorPosition())
    local scale = self:GetEffectiveScale() or 1
    local left = self:GetLeft() * scale
    local pct = clamp((xPos - left) / (self:GetWidth() * scale), 0, 1)
    local value = low + pct * (high - low)
    if step and step > 0 then value = math.floor(value / step + 0.5) * step end
    if step and step < 1 then value = tonumber(string.format('%.2f', value)) end
    characterSettings[key] = value
    render(characterSettings[key])
    if onChange then onChange(characterSettings[key]) end
  end

  bar:SetScript('OnMouseDown', function(self)
    self.dragging = true
    setFromMouse(self)
  end)
  bar:SetScript('OnMouseUp', function(self)
    self.dragging = nil
  end)
  bar:SetScript('OnUpdate', function(self)
    if self.dragging then setFromMouse(self) end
  end)

  holder.Render = function() render(characterSettings[key] or low) end
  holder.Render()
  return holder
end

-- Allows a frame to be dragged and remembers its screen coordinates.
local function makeMovable(f, keyX, keyY)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag('LeftButton')
  f:SetScript('OnDragStart', function(self) self:StartMoving() end)
  f:SetScript('OnDragStop', function(self)
    self:StopMovingOrSizing()
    local cx, cy = self:GetCenter()
    local px, py = UIParent:GetCenter()
    if cx and px then
      characterSettings[keyX] = cx - px
      characterSettings[keyY] = cy - py
    end
  end)
end

-- Adds a drag handle and enforces the aquarium minimum dimensions.
local function addResizer(frame)
  local grip = CreateFrame('Button', nil, frame)
  grip:SetSize(18, 18)
  grip:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -4, 4)
  grip.tex = grip:CreateTexture(nil, 'ARTWORK')
  grip.tex:SetAllPoints()
  grip.tex:SetTexture('Interface\\CHATFRAME\\UI-ChatIM-SizeGrabber-Up')
  grip:SetScript('OnMouseDown', function()
    frame:StartSizing('BOTTOMRIGHT')
  end)
  grip:SetScript('OnMouseUp', function()
    frame:StopMovingOrSizing()
    characterSettings.width = clamp(frame:GetWidth(), MIN_TANK_WIDTH, 720)
    characterSettings.height = clamp(frame:GetHeight(), MIN_TANK_HEIGHT, 560)
    frame:SetSize(characterSettings.width, characterSettings.height)
    if frame.RefreshLayout then frame:RefreshLayout() end
  end)
  frame.resizeGrip = grip
  frame:SetResizable(true)
  if frame.SetResizeBounds then
    frame:SetResizeBounds(MIN_TANK_WIDTH, MIN_TANK_HEIGHT, 720, 560)
  elseif frame.SetMinResize then
    frame:SetMinResize(MIN_TANK_WIDTH, MIN_TANK_HEIGHT)
    if frame.SetMaxResize then frame:SetMaxResize(720, 560) end
  end
  return grip
end

-- ============================================================================
-- Fishing equipment and bait
-- Fishing checks and explicit player-activated bait macros.
-- ============================================================================
-- Checks whether a bag item is a fishing item.
local function fishingItem(id, link)
  if not id then return false end
  local equipLoc = (C_Item and C_Item.GetItemInventoryTypeByID and C_Item.GetItemInventoryTypeByID(id))
  local itemType, subType, invType
  if GetItemInfo then
    local _, _, _, _, _, typ, sub, _, loc = GetItemInfo(link or id)
    itemType, subType, invType = typ, sub, loc
    equipLoc = equipLoc or invType
  end
  if equipLoc == 'INVTYPE_FISHINGPOLE' then return true end
  if type(subType) == 'string' and subType:lower():find('fishing pole', 1, true) then return true end
  if type(itemType) == 'string' and itemType:lower():find('weapon', 1, true) and type(subType) == 'string' and subType:lower():find('pole', 1, true) then return true end
  return false
end

-- Tests whether the currently equipped item is a fishing pole.
local function currentlyEquipped()
  if GetInventoryItemID then
    local id = GetInventoryItemID('player', 16)
    if id and fishingItem(id) then return true end
  end
  if GetInventoryItemLink then
    local l = GetInventoryItemLink('player', 16)
    if l then
      local id = tonumber(l:match('item:(%d+)'))
      return fishingItem(id, l)
    end
  end
  return false
end

-- Finds a suitable fishing rod without triggering protected equips.
local function choosePole()
  local bestLink, bestScore
  for bag = 0, 4 do
    local n = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
    for slot = 1, n do
      local link = (C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)) or (GetContainerItemLink and GetContainerItemLink(bag, slot))
      if link then
        local id = tonumber(link:match('item:(%d+)'))
        if fishingItem(id, link) then
          local _, _, quality, level = GetItemInfo(link)
          local score = (tonumber(level) or 0) * 10 + (tonumber(quality) or 0)
          if not bestScore or score > bestScore then
            bestScore = score
            bestLink = link
          end
        end
      end
    end
  end
  return bestLink
end

-- Searches carried bags for a supported lure, preferring stronger options.
local function findBestBait()
  local best = nil
  for bag = 0, 4 do
    local n = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
    for slot = 1, n do
      local link = (C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)) or (GetContainerItemLink and GetContainerItemLink(bag, slot))
      if link then
        local id = tonumber(link:match('item:(%d+)'))
        local name, _, quality, _, reqLevel, className, subClassName = GetItemInfo(link)
        local lname = type(name) == 'string' and name:lower() or ''
        local matched = false
        for _, key in ipairs(lureNames) do
          if lname:find(key, 1, true) then matched = true break end
        end
        if matched or (type(className) == 'string' and className:lower():find('consumable', 1, true) and type(subClassName) == 'string' and subClassName:lower():find('other', 1, true) and lname:find('fish', 1, true)) then
          local score = (tonumber(quality) or 0) * 100 + (tonumber(reqLevel) or 0)
          if not best or score > best.score then
            best = { bag = bag, slot = slot, link = link, id = id, score = score, name = name or 'Fishing Bait' }
          end
        end
      end
    end
  end
  return best
end

-- Checks the active temporary enchant on the equipped rod.
local function mainHandHasLure()
  if not GetWeaponEnchantInfo then return false end
  local hasMainHandEnchant = GetWeaponEnchantInfo()
  return not not hasMainHandEnchant
end

-- Returns the remaining rod lure duration and whether it is active.
local function mainHandLureRemaining()
  if not GetWeaponEnchantInfo then return 0, false end
  local hasMainHandEnchant, mainHandExpiration = GetWeaponEnchantInfo()
  return (tonumber(mainHandExpiration) or 0) / 1000, not not hasMainHandEnchant
end

-- WoW restricts using items from insecure addon callbacks (including OnUpdate).
-- A hardware-activated macro is the supported way to apply a lure to slot 16.
-- Builds a secure user-triggered two-line bait macro for the current pole.
local function baitMacroBody(bait)
  -- Use the exact item ID rather than an English name when available.
  local selector = bait.id and ('item:' .. tostring(bait.id)) or bait.name
  return '/use ' .. selector .. '\n/use 16'
end

-- Creates a hardware-clickable bait macro and puts it on the cursor.
local function prepareBaitMacro()
  if InCombatLockdown and InCombatLockdown() then
    say('Create/use your bait macro outside combat.')
    return false
  end
  if not currentlyEquipped() then
    say('Equip your fishing pole first. Fishing equipment cannot be swapped by a background callback.')
    return false
  end
  if mainHandHasLure() then
    say('Your fishing pole already has a temporary lure/enchant.')
    return false
  end
  local bait = findBestBait()
  if not bait then
    say('No usable fishing lure detected. Nightcrawlers should be in normal bags (0-4).')
    return false
  end
  if not (CreateMacro and PickupMacro) then
    say('Make a macro manually: /use ' .. (bait.name or 'Nightcrawlers') .. ' then /use 16 on the next line.')
    return false
  end
  local body = baitMacroBody(bait)
  local idx = GetMacroIndexByName and GetMacroIndexByName('VibeBait')
  local ok, result
  if idx and idx > 0 and EditMacro then
    ok, result = pcall(EditMacro, idx, 'VibeBait', 'INV_Misc_Food_35', body)
  else
    ok, result = pcall(CreateMacro, 'VibeBait', 'INV_Misc_Food_35', body, true)
    if ok then idx = result end
  end
  if not ok or not idx or idx == 0 then
    say('Could not create VibeBait (macro slots may be full). Create: ' .. body:gsub('\n', ' / '))
    return false
  end
  PickupMacro(idx)
  say('VibeBait for ' .. (bait.name or 'Nightcrawlers') .. ' is on your cursor. Place it on an action bar and PRESS it to apply.')
  return true
end

-- Reminds the player when a lure is missing, with spam protection.
local function adviseBait(force)
  if not characterSettings or not characterSettings.autoBait or not active then return end
  local _, hasLure = mainHandLureRemaining()
  if hasLure then
    baitMacroReady = false
    return
  end
  local bait = findBestBait()
  if currentlyEquipped() and bait then
    local t = GetTime and GetTime() or now or 0
    if force or not baitMacroReady or (t - (lastBaitReminder or 0)) >= 45 then
      baitMacroReady = true
      lastBaitReminder = t
      say('Your fishing bait buff is missing or expired. Use your VibeBait action button to apply ' .. (bait.name or 'bait') .. '. /vfish baitmacro recreates the macro.')
    end
  else
    baitMacroReady = false
  end
end


-- Updates opacity consistently across aquarium, options and timer.
local function applyThemeOpacity()
  if aquariumWindow then applyAlpha(aquariumWindow) end
  if optionsWindow then applyAlpha(optionsWindow) end
  if castTimerWindow then castTimerWindow:SetAlpha(clamp((characterSettings.opacity or 0.94) + 0.04, 0.25, 1)) end
end

-- Synchronizes visibility and status labels with fishing mode and preferences.
updateStatus = function()
  if aquariumWindow then
    aquariumWindow:SetShown(characterSettings.catchPanel and (active or characterSettings.alwaysShowAquarium))
    if aquariumWindow.status then
      aquariumWindow.status:SetText(active and '● FISHING MODE ACTIVE' or '○ AQUARIUM DISPLAY')
    end
  end
  if castTimerWindow then
    local clock = GetTime and GetTime() or now
    -- WoW ends the channel before the loot event. Keep the complete rod/timer
    -- visible during that gap and throughout a confirmed catch handoff.
    local keepTimer = (active and casting)
      or (aquariumController.timerGraceUntil and clock < aquariumController.timerGraceUntil)
      or aquariumController.catchTimerHandoff
    castTimerWindow:SetShown(characterSettings.showTimer and not not keepTimer)
  end
end

-- ============================================================================
-- Aquarium populations and bag synchronization
-- Object pooling, item classification, resident lists and preserved inventory state.
-- ============================================================================
-- Returns active fish frames to the reusable frame pool.
local function clearFish()
  for _, fish in ipairs(swimmingFish) do
    fish:Hide()
    fishFramePool[#fishFramePool + 1] = fish
  end
  wipeTable(swimmingFish)
end

-- Returns ambient aquarium bubbles to their reusable frame pool.
local function clearBubbles()
  for _, bubble in ipairs(bubbles) do
    bubble:Hide()
    bubbleFramePool[#bubbleFramePool + 1] = bubble
  end
  wipeTable(bubbles)
end

-- Counts persistent dead-fish records for inventory matching.
local function deadFishCountBySpecies()
  local counts = {}
  if not characterSettings or not characterSettings.deadFish then return counts end
  for _, entry in ipairs(characterSettings.deadFish) do
    if entry and entry.id then counts[entry.id] = (counts[entry.id] or 0) + 1 end
  end
  return counts
end

-- Creates an ambient bubble and tracks it in the frame pool.
local function makeBubble(parent, x, y, size, speed, drift)
  local f = table.remove(bubbleFramePool) or CreateFrame('Frame', nil, parent)
  f:SetSize(size, size)
  if not f.tex then
    f.tex = f:CreateTexture(nil,'ARTWORK')
    f.tex:SetAllPoints()
    f.tex:SetTexture('Interface\\COMMON\\Indicator-Yellow')
  end
  f.tex:SetVertexColor(0.85, 1, 1, 0.12)
  f.baseX, f.baseY, f.speed, f.drift = x, y, speed, drift
  f:Show()
  table.insert(bubbles, f)
  return f
end

local fishNameParts = {
  'fish', 'salmon', 'trout', 'snapper', 'catfish', 'eel', 'squid', 'lobster',
  'clam', 'mackerel', 'sardine', 'carp', 'herring', 'tuna', 'sturgeon',
  'grouper', 'piranha', 'octopus', 'shrimp', 'mudskipper', 'redgill',
  'cod', 'mightfish', 'yellowtail', 'sagefish', 'oily blackmouth',
  'firefin', 'stonescale', 'deviate', 'rockscale', 'silverfin', 'goby',
}
local knownFish = {
  [6291]=true,[6289]=true,[6303]=true,[6308]=true,[6309]=true,[6310]=true,
  [6311]=true,[6358]=true,[6359]=true,[6361]=true,[6362]=true,[6364]=true,
  [6522]=true,[8365]=true,[13754]=true,[13755]=true,[13756]=true,
  [13757]=true,[13758]=true,[13759]=true,[13888]=true,[13889]=true,
  [13890]=true,[13893]=true,[13907]=true,[13908]=true,[13909]=true,
  [13910]=true,[13911]=true,[13912]=true,[13913]=true,[13914]=true,
  [13915]=true,[13916]=true,[13917]=true,[13918]=true,
}
-- Explicitly exclude non-fish consumables that may have been collected by older versions.
-- WoW Forever Sharpening Wheel is item 279944 (blacksmithing camping buff).
local excludedFishIDs = { [279944] = true }
local excludedFishNameParts = {
  'sharpening wheel', 'sharpening stone', 'weightstone', 'grinding stone',
  'blacksmith', 'campfire', 'recipe', 'schematic', 'cooked', 'bait', 'lure',
  'fishing pole', 'fishing rod', 'fish feast', 'fish oil',
}
-- Classifies an item as fish rather than bait, gear, or other catches.
local function isFishItem(id, link)
  if not id or excludedFishIDs[id] then return false end
  if knownFish[id] then return true end
  local name, _, _, _, _, itemType, subType = GetItemInfo(link or id)
  if type(name) ~= 'string' and type(link)=='string' then
    name = link:match('|h%[([^%]]+)%]|h')
  end
  if type(name) ~= 'string' then return false end
  local n = name:lower()
  -- Restrict matches to the actual item name, never the full tooltip or link.
  -- Category exclusions win over name fragments to avoid non-fish aquarium props.
  for _, part in ipairs(excludedFishNameParts) do
    if n:find(part, 1, true) then return false end
  end
  for _, part in ipairs(fishNameParts) do
    if n:find(part, 1, true) then return true end
  end
  return false
end
-- Fishing-only inventory filtering: never treat arbitrary world/quest crates as catches.
-- Confirmed fishing containers (WoW Forever Fishing guide / Classic fishing tables).
local fishingContainerIDs = { [20708]=true, [6351]=true }
local fishingContainers = {
  ['tightly sealed trunk']=true, ['watertight trunk']=true,
  ['iron bound trunk']=true, ['mithril bound trunk']=true,
  ['dented crate']=true, ['waterlogged crate']=true,
  ['sealed crate']=true, ['heavy crate']=true,
}
local floatingPlantNames = { ['stranglekelp']=true, ['weeds']=true }
local excludedFishingNames = { ['waylaid crate']=true, ['waylaid shipment']=true }
local excludedFishingIDs = { [248549]=true }
-- Resolves the display name from a link or cached item metadata.
local function itemName(id, link)
  local name=select(1,GetItemInfo(link or id))
  if type(name) ~= 'string' and type(link)=='string' then
    name=link:match('|h%[([^%]]+)%]|h')
  end
  return type(name)=='string' and name:lower() or nil
end
-- Rejects quest crates and other non-fishing inventory items.
local function isExcludedFishingLoot(id,link)
  if excludedFishingIDs[id] then return true end
  local n=itemName(id,link)
  if not n then return false end
  if excludedFishingNames[n] or n:find('waylaid',1,true) then return true end
  return false
end
-- Recognizes floating plants such as Stranglekelp.
local function isPlantCatch(id,link)
  local n=itemName(id,link)
  return n and floatingPlantNames[n] or false
end
-- Recognizes actual fishing treasure containers.
local function isTreasureCatch(id, link)
  if not id or isExcludedFishingLoot(id,link) or isFishItem(id,link) or isPlantCatch(id,link) then return false end
  local n=itemName(id,link)
  if fishingContainerIDs[id] or (n and fishingContainers[n]) then return true end
  -- Only items observed during fishing may extend the known fishing inventory set.
  return characterSettings and characterSettings.fishingLootIDs and characterSettings.fishingLootIDs[id]=='treasure' or false
end

-- Records a fishing container and schedules its sink animation.
local function addTreasureCatch(id, count, itemLink)
  if not id then return end
  count = clamp(tonumber(count) or 1, 1, 20)
  characterSettings.treasures = characterSettings.treasures or {}
  characterSettings.treasures[#characterSettings.treasures + 1] = { id = id, count = count, link = itemLink }
  if #characterSettings.treasures > 24 then table.remove(characterSettings.treasures, 1) end
  repopulateAquarium('preserve')
  -- The floor prop appears only once its animated version has settled.
  if aquariumWindow and aquariumWindow:IsShown() and aquariumCanvas then startTreasureDrop(id) end
end

-- Inventory treasure is independent of the "show bag fish" preference.
-- The client can expose item IDs even while item-link text is uncached.
-- Collects only recognized fishing containers from carried bags.
local function inventoryTreasureList()
  local result = {}
  for bag = 0, 4 do
    local slots = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
    for slot = 1, slots do
      local link = (C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag,slot)) or (GetContainerItemLink and GetContainerItemLink(bag,slot))
      local id = (type(link) == 'string' and tonumber(link:match('item:(%d+)'))) or
        (C_Container and C_Container.GetContainerItemID and C_Container.GetContainerItemID(bag,slot))
      if id and isTreasureCatch(id, link) then
        local count = 1
        if C_Container and C_Container.GetContainerItemInfo then
          local info = C_Container.GetContainerItemInfo(bag,slot)
          if type(info) == 'table' then count = info.stackCount or info.quantity or 1 end
        elseif GetContainerItemInfo then
          local _, n = GetContainerItemInfo(bag,slot)
          count = n or 1
        end
        result[#result+1] = {id = id, count = math.max(1,tonumber(count) or 1), link = link}
      end
    end
  end
  return result
end

-- Collects valid floating fishing plants from carried bags.
local function inventoryPlantList()
  local result={}
  for bag=0,4 do
    local slots=(C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
    for slot=1,slots do
      local link=(C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag,slot)) or (GetContainerItemLink and GetContainerItemLink(bag,slot))
      local id=(type(link)=='string' and tonumber(link:match('item:(%d+)'))) or (C_Container and C_Container.GetContainerItemID and C_Container.GetContainerItemID(bag,slot))
      if id and (isPlantCatch(id,link) or (characterSettings.fishingLootIDs and characterSettings.fishingLootIDs[id]=='plant')) then
        local count=1
        if C_Container and C_Container.GetContainerItemInfo then
          local info=C_Container.GetContainerItemInfo(bag,slot)
          if type(info)=='table' then count=info.stackCount or info.quantity or 1 end
        elseif GetContainerItemInfo then
          local _,qty=GetContainerItemInfo(bag,slot); count=qty or 1
        end
        result[#result+1]={id=id,count=count,link=link}
      end
    end
  end
  return result
end
-- Records aquatic plants without adding them to swimming-fish totals.
local function addPlantCatch(id,count,link)
  if not id then return end
  characterSettings.plants=characterSettings.plants or {}
  characterSettings.plants[#characterSettings.plants+1]={id=id,count=math.max(1,tonumber(count) or 1),link=link}
  if #characterSettings.plants>24 then table.remove(characterSettings.plants,1) end
  if repopulatePlants then repopulatePlants() end
end

-- Counts fish in carried bags without accessing bank contents.
local function inventoryFishList()
  local aggregate, links = {}, {}
  for bag=0,4 do
    local n = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
    for slot=1,n do
      local link = (C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag,slot)) or (GetContainerItemLink and GetContainerItemLink(bag,slot))
      if link then
        local id = tonumber(link:match('item:(%d+)'))
        if id and isFishItem(id,link) then
          local count = 1
          if C_Container and C_Container.GetContainerItemInfo then
            local info = C_Container.GetContainerItemInfo(bag,slot)
            if type(info)=='table' then count = info.stackCount or 1 end
          elseif GetContainerItemInfo then
            local _, nstack = GetContainerItemInfo(bag,slot)
            count = nstack or 1
          end
          aggregate[id] = (aggregate[id] or 0) + math.max(1, count)
          if not links[id] then links[id] = link end
        end
      end
    end
  end
  local deadCounts = deadFishCountBySpecies()
  local result = {}
  for id, count in pairs(aggregate) do
    local liveCount = count - (deadCounts[id] or 0)
    if liveCount > 0 then
      result[#result+1] = { id = id, count = liveCount, link = links[id] }
    end
  end
  table.sort(result, function(a,b) return (a.id or 0) < (b.id or 0) end)
  return result
end


-- Price adapters: optional, read-only, and never scan the auction house.
-- All prices are copper PER ITEM. Missing prices stay unknown, not zero-valued.
-- Detects available read-only Auctionator or AHDB pricing APIs.
-- ============================================================================
-- Auction pricing and Cooking metadata
-- Read-only integrations and learned cooking ingredient lookup.
-- ============================================================================
detectPriceSource = function()
  local previous = auctionPriceProvider
  auctionPriceProvider = nil
  if type(Auctionator)=='table' and type(Auctionator.API)=='table' and
     type(Auctionator.API.v1)=='table' and
     type(Auctionator.API.v1.GetAuctionPriceByItemID)=='function' then
    auctionPriceProvider = 'Auctionator'
  elseif type(AuctionDB)=='table' and type(AuctionDB.AHGetAuctionInfoByLink)=='function' then
    auctionPriceProvider = 'AHDB'
  elseif type(Atr_GetAuctionBuyout)=='function' then
    auctionPriceProvider = 'Auctionator (Classic)'
  end
  if characterSettings and auctionPriceProvider and not characterSettings.priceAutoDetected then
    characterSettings.showFishValue = true -- enable once; respect later manual preference
    characterSettings.priceAutoDetected = true
  end
  return auctionPriceProvider
end

-- Queries a selected price provider for the unit value of a fish.
local function priceOfFish(entry)
  if not auctionPriceProvider then return nil end
  local price
  if auctionPriceProvider=='Auctionator' then
    local api=Auctionator and Auctionator.API and Auctionator.API.v1
    if api and type(api.GetAuctionPriceByItemID)=='function' then
      local ok,val=pcall(api.GetAuctionPriceByItemID, 'VibeFishin', entry.id)
      if ok then price=val end
    end
  elseif auctionPriceProvider=='AHDB' then
    local api=AuctionDB
    if api and type(api.AHGetAuctionInfoByLink)=='function' then
      local link=entry.link or select(2,GetItemInfo(entry.id))
      if link then
        local ok,info=pcall(api.AHGetAuctionInfoByLink,api,link)
        if ok and type(info)=='table' then price=info.minBuyout end
      end
    end
  elseif auctionPriceProvider=='Auctionator (Classic)' then
    local ok,val=pcall(Atr_GetAuctionBuyout, entry.link or entry.id)
    if ok then price=val end
  end
  if type(price)=='number' and price>0 then return math.floor(price) end
  return nil
end

-- Formats a price stored in copper as gold, silver and copper.
local function moneyString(copper)
  copper=math.max(0,math.floor(copper or 0))
  local g=math.floor(copper/10000)
  local silver=math.floor(copper%10000/100)
  local c=copper%100
  return string.format('%dg %ds %dc',g,silver,c)
end

-- Updates displayed AH totals and highlights the highest-value fish.
updateFishValue = function()
  if not aquariumWindow or not aquariumWindow.value then return end
  if not auctionPriceProvider then detectPriceSource() end
  wipeTable(premiumFishIDs)
  local wantValue = characterSettings.showFishValue and auctionPriceProvider
  local wantGold = characterSettings.highlightMostValuable ~= false and auctionPriceProvider
  -- Valuation and highlighting are independent preferences. Neither should
  -- invent values for items missing from an auction addon's scan data.
  local total, missing, highest = 0, 0, 0
  if wantValue or wantGold then
    for _, entry in ipairs(displayedFishEntries) do
      local unit = priceOfFish(entry)
      if unit then
        if wantValue then total = total + unit * (entry.count or 1) end
        if wantGold and unit > highest then
          highest = unit
          wipeTable(premiumFishIDs)
          premiumFishIDs[entry.id] = true
        elseif wantGold and unit == highest and unit > 0 then
          premiumFishIDs[entry.id] = true
        end
      elseif wantValue then
        missing = missing + (entry.count or 1)
      end
    end
  end
  -- Recycled fish frames must update when switching the checkbox or display mode.
  for _, fish in ipairs(swimmingFish) do
    if fish.rareBorder then
      fish.rareBorder:SetShown(not not premiumFishIDs[fish.species])
    end
  end
  if wantValue then
    aquariumWindow.value:SetText('AH EST.  '..moneyString(total)..(missing > 0 and ('  |cff9fc8c3('..missing..' unpriced)|r') or ''))
    aquariumWindow.value:Show()
  else
    aquariumWindow.value:Hide()
  end
end

-- Cooking icons use the actual learned recipe ingredients. The modern
-- TradeSkillUI API exposes the current profession after the Cooking window
-- has been opened, not a reliable offline list of all learned recipes.
-- Shows cooking badges for fish used in learned recipes.
local function refreshCookingBadges()
  if not characterSettings then return end
  for _, fish in ipairs(swimmingFish) do
    if fish.cookingBadge then
      fish.cookingBadge:SetShown(characterSettings.showCookingBadges ~= false and cookingIngredients[fish.species] == true)
    end
  end
end

-- Reads known Cooking recipes after the profession UI is opened.
local function scanCookingRecipes(quiet)
  if not characterSettings then return false end
  local api = C_TradeSkillUI
  if type(api) ~= 'table' or type(api.GetAllRecipeIDs) ~= 'function' then
    if not quiet then say('Cooking recipe API unavailable on this client.') end
    return false
  end
  local isCooking = false
  if type(api.GetBaseProfessionInfo) == 'function' then
    local ok, info = pcall(api.GetBaseProfessionInfo)
    if ok and type(info) == 'table' then
      isCooking = (info.profession == 5 or info.professionID == 185 or
        info.parentProfessionID == 185 or
        (type(info.professionName) == 'string' and info.professionName:lower() == 'cooking'))
    end
  end
  if not isCooking and type(api.GetTradeSkillLine) == 'function' then
    local ok, id, displayName, _, _, _, parentID, parentName = pcall(api.GetTradeSkillLine)
    if ok then
      isCooking = id == 185 or parentID == 185 or
        (type(displayName) == 'string' and displayName:lower() == 'cooking') or
        (type(parentName) == 'string' and parentName:lower() == 'cooking')
    end
  end
  if not isCooking then
    if not quiet then say('Open your Cooking profession window, then use /vfish recipes.') end
    return false
  end
  local ok, recipes = pcall(api.GetAllRecipeIDs)
  if not ok or type(recipes) ~= 'table' or #recipes == 0 then
    if not quiet then say('No Cooking recipe list loaded yet. Open Cooking and try again.') end
    return false
  end
  local found = {}
  local learned = 0
  for _, recipeID in ipairs(recipes) do
    if type(recipeID) == 'number' then
      local known = false
      if type(api.GetRecipeInfo) == 'function' then
        local good, info = pcall(api.GetRecipeInfo, recipeID)
        known = good and type(info) == 'table' and info.learned == true
      end
      if known and type(api.GetRecipeSchematic) == 'function' then
        learned = learned + 1
        local good, schematic = pcall(api.GetRecipeSchematic, recipeID, false)
        if good and type(schematic) == 'table' and type(schematic.reagentSlotSchematics) == 'table' then
          for _, slot in ipairs(schematic.reagentSlotSchematics) do
            if type(slot) == 'table' and slot.required ~= false and type(slot.reagents) == 'table' then
              for _, reagent in ipairs(slot.reagents) do
                if type(reagent) == 'table' and type(reagent.itemID) == 'number' then
                  found[reagent.itemID] = true
                end
              end
            end
          end
        end
      end
    end
  end
  -- If no recipes report as learned, never erase a valid previous scan.
  if learned == 0 then
    if not quiet then say('No learned Cooking recipes found in the open profession window.') end
    return false
  end
  characterSettings.cookableReagents = found
  cookingIngredients = found
  cookingRecipesReady = true
  refreshCookingBadges()
  if not quiet then
    local ingredients = 0
    for _ in pairs(found) do ingredients = ingredients + 1 end
    say(('Cooking scan complete: %d learned recipes, %d ingredient types. Cooking badges updated.'):format(learned, ingredients))
  end
  return true
end

-- ============================================================================
-- Resident fish simulation
-- Fish visuals, feeding, refresh, schooling and stable generated names.
-- ============================================================================
-- Creates or reuses one animated fish icon for the aquarium.
local function spawnFish(id, idx, population)
  if not aquariumCanvas then return end
  local w,h = math.max(50,aquariumCanvas:GetWidth()), math.max(50,aquariumCanvas:GetHeight())
  local size = 31
  if characterSettings.adaptiveFishSize then
    -- Density based on available tank area, not just number of fish.
    size = clamp(math.sqrt(w*h / math.max(1,population)) * 0.55, 12, 36)
  end
  local f = table.remove(fishFramePool) or CreateFrame('Frame',nil,aquariumCanvas)
  f:SetSize(size,size)
  if not f.icon then
    f.icon = f:CreateTexture(nil,'ARTWORK')
    f.icon:SetAllPoints()
  end
  if not f.goldFrame then
    f.goldFrame = CreateFrame('Frame', nil, f)
    f.goldFrame:SetAllPoints(f)
    local edges = {}
    local function edge(pointA, pointB, horizontal)
      local tex = f.goldFrame:CreateTexture(nil, 'OVERLAY')
      tex:SetTexture('Interface\\Buttons\\WHITE8X8')
      tex:SetVertexColor(1, .76, .19, .95)
      if horizontal then
        tex:SetHeight(2)
        tex:SetPoint(pointA, f.goldFrame, pointA, 0, 0)
        tex:SetPoint(pointB, f.goldFrame, pointB, 0, 0)
      else
        tex:SetWidth(2)
        tex:SetPoint(pointA, f.goldFrame, pointA, 0, 0)
        tex:SetPoint(pointB, f.goldFrame, pointB, 0, 0)
      end
      edges[#edges+1] = tex
    end
    edge('TOPLEFT', 'TOPRIGHT', true)
    edge('BOTTOMLEFT', 'BOTTOMRIGHT', true)
    edge('TOPLEFT', 'BOTTOMLEFT', false)
    edge('TOPRIGHT', 'BOTTOMRIGHT', false)
    f.goldFrame.edges = edges
    f.rareBorder = f.goldFrame -- retain the existing value-highlighting path
  end
  f.baseIcon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id)) or 'Interface\\Icons\\INV_Misc_Fish_02'
  f.icon:SetTexture(f.baseIcon)
  f.icon:SetTexCoord(.08,.92,.08,.92)
  if not f.cookingBadge then
    f.cookingBadge = f:CreateTexture(nil, 'OVERLAY', nil, 7)
    f.cookingBadge:SetTexture('Interface\\AddOns\\VibeFishin\\Media\\CookingBadge')
    f.cookingBadge:SetPoint('TOPRIGHT', f, 'TOPRIGHT', 2, 2)
  end
  local cookingSize = clamp(size * 0.46, 9, 17)
  f.cookingBadge:SetSize(cookingSize, cookingSize)
  f.cookingBadge:SetShown(characterSettings.showCookingBadges ~= false and cookingIngredients[id] == true)
  f.rareBorder:SetShown(not not premiumFishIDs[id])
  f.size=size
  f.species=id
  f.phase=idx*2.39996
  f.x = 4 + ((idx*83) % math.max(5,w-size-8))
  f.y = 4 + ((idx*53) % math.max(5,h-size-8))
  f.targetX = 4 + ((idx*117+41) % math.max(5,w-size-8))
  f.targetY = 4 + ((idx*61+27) % math.max(5,h-size-8))
  f.speed = 20 + (idx % 7)*3
  f.vx = math.cos(f.phase)*f.speed*0.5
  f.vy = math.sin(f.phase)*f.speed*0.5
  f.schoolIndex = idx
  local home=schoolTerritories[id]
  if home then
    local spread = 0.10 + (idx % 4) * 0.017
    f.x=clamp((home.x + math.cos(f.phase)*spread)*w, 4, math.max(4,w-size-4))
    f.y=clamp((home.y + math.sin(f.phase)*spread)*h, 4, math.max(4,h-size-4))
    f.targetX=clamp((home.x + math.cos(f.phase+0.8)*spread)*w, 4, math.max(4,w-size-4))
    f.targetY=clamp((home.y + math.sin(f.phase+0.8)*spread)*h, 4, math.max(4,h-size-4))
  end
  -- Rebuilds have a short waterfall entrance before ordinary schooling begins.
  if characterSettings._aquariumRefreshEntrance then
    f.entryTargetX, f.entryTargetY = f.x, f.y
    f.entryStartX = clamp(w * (0.09 + math.random() * 0.82), 4, math.max(4, w-size-4))
    f.entryStartY = math.max(4, h-size-4)
    f.x, f.y = f.entryStartX, f.entryStartY
    f.entryElapsed = -(idx % 12) * 0.065
    f.entryDuration = 1.05 + (idx % 5) * 0.13
  else
    f.entryElapsed = nil
  end
  f.nextWaypoint=(GetTime and GetTime() or 0)+5+(idx%8)*1.4
  f.wobble = idx*0.61
  f.foodTarget=nil
  f.eatingBit=nil
  f.fedUntil=fishCooldownByID[idx] or 0
  f.lastFed=f.lastFed or (GetTime and GetTime() or 0)
  f.deadState=nil
  f.deadAt=nil
  f.skeletonAt=nil
  f.deathX=nil
  f:SetPoint('BOTTOMLEFT', aquariumCanvas, 'BOTTOMLEFT',f.x,f.y)
  f:Show()
  swimmingFish[#swimmingFish+1]=f
  return f
end

-- Clears uneaten pellets and releases fish food targets.
local function resetFood()
  -- Clear claims and eating animations. A fish retains its five-minute
  -- eating cooldown even when the player drops another batch of food.
  for _, fish in ipairs(swimmingFish) do
    fish.foodTarget=nil
    fish.eatingBit=nil
  end
  for _, bit in ipairs(foodPellets) do
    bit:Hide()
    foodPelletPool[#foodPelletPool+1]=bit
  end
  wipeTable(foodPellets)
  feedingUntil=0
end

-- Drops feed pellets and starts the fish-feeding simulation.
local function feedAquarium()
  local living=0
  for _,fish in ipairs(swimmingFish) do if not fish.deadState then living=living+1 end end
  if not aquariumCanvas or living==0 then
    say('Your aquarium needs living fish before you can feed them.')
    return
  end
  resetFood()
  local w,h = aquariumCanvas:GetWidth(),aquariumCanvas:GetHeight()
  local t = GetTime and GetTime() or 0
  feedingUntil=t+FOOD_WINDOW_SECONDS
  for i=1,math.min(16,5+math.floor(living/4)) do
    local bit=table.remove(foodPelletPool) or CreateFrame('Frame',nil,aquariumCanvas)
    bit:SetSize(5+(i%3),5+(i%3))
    if not bit.tex then
      bit.tex=bit:CreateTexture(nil,'ARTWORK')
      bit.tex:SetAllPoints()
      bit.tex:SetTexture('Interface\\Buttons\\WHITE8X8')
    end
    bit.tex:SetVertexColor(.56+(i%3)*.04,.31,.12,.94)
    bit.x=8+((i*59+17)%math.max(12,w-20))
    bit.y=h-10-(i%3)*5
    bit.vel=3+(i%4)*2
    bit.eaten=false
    bit.claimedBy=nil
    bit.eatStarted=nil
    bit.eater=nil
    bit.baseSize=5+(i%3)
    bit:SetPoint('BOTTOMLEFT',aquariumCanvas,'BOTTOMLEFT',bit.x,bit.y)
    bit:Show()
    foodPellets[#foodPellets+1]=bit
  end
end

-- Lays out treasure items across randomly assigned bottom positions.
local function repopulateTreasures()
  for _, fr in ipairs(displayedTreasureFrames) do
    fr:Hide()
    treasureFramePool[#treasureFramePool+1] = fr
  end
  wipeTable(displayedTreasureFrames)
  if not aquariumCanvas or not characterSettings then return end
  characterSettings.treasures = characterSettings.treasures or {}
  local bag = inventoryTreasureList()
  local byID, sources = {}, {}
  for _, item in ipairs(characterSettings.treasures) do
    if item and item.id and isTreasureCatch(item.id, item.link) then
      local entry = byID[item.id]
      if not entry then
        entry = {id=item.id, count=0, link=item.link}
        byID[item.id] = entry
        sources[#sources+1] = entry
      end
      entry.count = entry.count + (tonumber(item.count) or 1)
    end
  end
  local inBags = {}
  for _, item in ipairs(bag) do
    inBags[item.id] = (inBags[item.id] or 0) + item.count
    if not byID[item.id] then
      byID[item.id] = {id=item.id, count=0, link=item.link}
      sources[#sources+1] = byID[item.id]
    end
  end
  -- Items looted while fishing may already be in bags. Use the larger
  -- count instead of treating the same chest as two different objects.
  for id, count in pairs(inBags) do
    byID[id].count = math.max(byID[id].count, count)
  end
  local shown = 0
  local floorY = 2
  local maxTreasure = 8
  local w = aquariumCanvas:GetWidth()
  -- Randomized non-overlapping slots. Each chest falls vertically at its own X.
  local slots = {}
  for n = 1, maxTreasure do slots[n] = n end
  for n = maxTreasure, 2, -1 do
    local k = math.random(n)
    slots[n], slots[k] = slots[k], slots[n]
  end
  for i = #sources, 1, -1 do
    local item = sources[i]
    local copies = math.min(item.count or 1, maxTreasure - shown)
    for j = 1, copies do
      shown = shown + 1
      local fr = table.remove(treasureFramePool) or CreateFrame('Frame', nil, aquariumCanvas)
      fr:SetSize(26, 26)
      if not fr.icon then
        fr.icon = fr:CreateTexture(nil, 'BORDER')
        fr.icon:SetAllPoints()
        fr.shadow = fr:CreateTexture(nil, 'BACKGROUND')
        fr.shadow:SetTexture('Interface\\Buttons\\WHITE8X8')
        fr.shadow:SetColorTexture(0,0,0,0.18)
        fr.shadow:SetPoint('BOTTOMLEFT', fr, 'BOTTOMLEFT', 3, -2)
        fr.shadow:SetPoint('BOTTOMRIGHT', fr, 'BOTTOMRIGHT', -3, -5)
      end
      local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item.id)) or (GetItemIcon and GetItemIcon(item.id)) or 'Interface\\Icons\\INV_Misc_TreasureChest03'
      fr.icon:SetTexture(icon)
      fr.icon:SetTexCoord(.08,.92,.08,.92)
      -- The slot order is randomized rather than a right-to-left cascade.
      -- Use the full tank width and leave a gap between adjacent items.
      fr.baseX = clamp(4 + (slots[shown] - .5) * ((w-8) / maxTreasure) - fr:GetWidth()*.5,
        4, math.max(4,w-fr:GetWidth()-4))
      fr.baseY = floorY
      fr.phase = shown * 0.9
      fr.itemID = item.id
      if characterSettings._aquariumRefreshEntrance then
        fr.entryX = fr.baseX
        fr.entryY = math.max(6, aquariumCanvas:GetHeight()-fr:GetHeight()-3)
        fr.entryElapsed = -(math.random() * 0.72)
        fr.entryDuration = 1.28 + math.random() * 0.42
        fr.entryBubbleClock = math.random() * 0.08
        fr.entryImpactDone = false
      else
        fr.entryElapsed = nil
      end
      fr:ClearAllPoints()
      fr:SetPoint('BOTTOMLEFT', aquariumCanvas, 'BOTTOMLEFT', fr.entryX or fr.baseX, fr.entryY or fr.baseY)
      fr:Show()
      displayedTreasureFrames[#displayedTreasureFrames + 1] = fr
      if shown >= maxTreasure then break end
    end
    if shown >= maxTreasure then break end
  end
end

-- Rebuilds only the floating plant decorations from recorded catches.
repopulatePlants = function()
  for _, plant in ipairs(floatingPlants) do
    plant:Hide()
    floatingPlantPool[#floatingPlantPool + 1] = plant
  end
  wipeTable(floatingPlants)
  if not aquariumCanvas or not characterSettings then return end
  local byID={}
  for _,item in ipairs(characterSettings.plants or {}) do
    if item and item.id and (isPlantCatch(item.id,item.link) or (characterSettings.fishingLootIDs and characterSettings.fishingLootIDs[item.id]=='plant')) then
      byID[item.id]=math.max(byID[item.id] or 0,tonumber(item.count) or 1)
    end
  end
  local bagCounts={}
  for _,item in ipairs(inventoryPlantList()) do bagCounts[item.id]=(bagCounts[item.id] or 0)+(tonumber(item.count) or 1) end
  for id,qty in pairs(bagCounts) do byID[id]=math.max(byID[id] or 0,qty) end
  local w,h=aquariumCanvas:GetWidth(),aquariumCanvas:GetHeight()
  local displayed=0
  for id,qty in pairs(byID) do
    for j=1,math.min(qty,6-displayed) do
      displayed=displayed+1
      local f=table.remove(floatingPlantPool) or CreateFrame('Frame',nil,aquariumCanvas)
      f:SetSize(22,22)
      if not f.icon then
        f.icon=f:CreateTexture(nil,'ARTWORK'); f.icon:SetAllPoints(); f.icon:SetTexCoord(.07,.93,.07,.93)
      end
      local icon=(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
      f.icon:SetTexture(icon or 'Interface\\Icons\\INV_Misc_Herb_11')
      f.anchorX=(0.1+0.8*((displayed*0.6180339887)%1))*w
      f.phase=displayed*1.71
      f:ClearAllPoints(); f:SetPoint('CENTER',aquariumCanvas,'BOTTOMLEFT',f.anchorX,h-12)
      f:Show(); floatingPlants[#floatingPlants+1]=f
      if displayed>=6 then break end
    end
    if displayed>=6 then break end
  end
end

-- Name pool for individually persisted fish records.
aquariumController.fishPetNames = {
  'Frank', 'Joe', 'Jeff', 'Fish McFisherson', 'Fishy', 'Bubbles',
  'Captain Gills', 'Finn Diesel', 'Sir Swimsalot', 'Nibbles',
  'Wanda', 'Gillbert', 'Bloop', 'Sushi', 'Marty', 'Pearl',
  'Franklin', 'Kevin', 'Biscuit', 'Splash', 'Professor Fins',
  'Linda', 'Fred', 'Finnegan', 'Tiny', 'Mr. Wiggles',
  'Bartholomew', 'Doris', 'Squiggles', 'Steve', 'Bobber',
}
-- V3 fish records are data-first; UI Frames are disposable views of these records.
-- A simulated variant is separate from the WoW item's actual quality and
-- never creates a virtual or real inventory item.
aquariumController.fishRarityNames = {'Common','Uncommon','Rare','Epic','Legendary'}
aquariumController.fishRarityColors = {'|cffb6c5ca','|cff51d975','|cff549fff','|cffba68ff','|cffffb947'}
aquariumController.fishPersonalityNames = {'Curious','Social','Forager','Shy','Lazy','Playful'}
aquariumController.fishVariantNames = {'Normal','Golden','Albino','Glowing','Giant'}
aquariumController.fishMilestones = {
  {key='first', name='First Catch', goal=1, type='total'},
  {key='ten', name='Getting Hooked', goal=10, type='total'},
  {key='fifty', name='Dedicated Angler', goal=50, type='total'},
  {key='hundred', name='Master Angler', goal=100, type='total'},
  {key='species5', name='Five Fin Friends', goal=5, type='species'},
  {key='species20', name='Aquatic Naturalist', goal=20, type='species'},
  {key='rare', name='Rare Encounter', goal=1, type='rare'},
  {key='gold', name='Golden Catch', goal=1, type='gold'},
}

-- Creates a stable ID and randomized rarity, variant and personality once.
aquariumController.newResident = function(species, link)
  characterSettings.nextResidentID = (characterSettings.nextResidentID or 0) + 1
  local roll = math.random(1,10000)
  local rarity = roll > 9995 and 5 or roll > 9960 and 4 or roll > 9800 and 3 or roll > 8400 and 2 or 1
  local variantRoll = math.random(1,10000)
  local variant = variantRoll > 9990 and 4 or variantRoll > 9950 and 3 or variantRoll > 9900 and 2 or variantRoll > 9700 and 5 or 1
  local petName = aquariumController.fishPetNames[math.random(1,#aquariumController.fishPetNames)]
  return {
    uid = 'VF-'..tostring(characterSettings.nextResidentID), species = species,
    link = link, name = petName, rarity = rarity, variant = variant,
    personality = math.random(1,#aquariumController.fishPersonalityNames),
    happiness = 100, hunger = 100, temperatureExposure = 0,
    lifeStage = 'adult', bornAt = (time and time() or 0),
    lastFedAt = (time and time() or 0), fedUntilAt = 0, deathState = nil,
  }
end

-- Counts unique caught species; unlike resident count, it never changes on rebuild.
aquariumController.journalSpeciesCount = function()
  local species = characterSettings.catchJournal and characterSettings.catchJournal.species or {}
  local n = 0
  for _ in pairs(species) do n = n + 1 end
  return n
end

-- Awards discoveries and named milestones only for actual catches.
aquariumController.recordFishDiscovery = function(resident)
  local journal = characterSettings.catchJournal
  journal.totalCaught = (journal.totalCaught or 0) + 1
  local speciesKey = tostring(resident.species)
  local entry = journal.species[speciesKey] or {caught=0,bestRarity=1,variants={}}
  entry.caught = entry.caught + 1
  entry.bestRarity = math.max(entry.bestRarity or 1, resident.rarity)
  entry.variants[resident.variant] = true
  entry.lastCaughtAt = (time and time() or 0)
  journal.species[speciesKey] = entry
  journal.rarestQuality = math.max(journal.rarestQuality or 1,resident.rarity)
  local count = aquariumController.journalSpeciesCount()
  local milestones = journal.achievements
  for _,goal in ipairs(aquariumController.fishMilestones) do
    local achieved = (goal.type=='total' and journal.totalCaught >= goal.goal)
      or (goal.type=='species' and count >= goal.goal)
      or (goal.type=='rare' and resident.rarity >= 3)
      or (goal.type=='gold' and resident.variant == 2)
    if achieved and not milestones[goal.key] then
      milestones[goal.key] = (time and time() or 0)
      if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage('|cff48d9dcVibe Achievement:|r '..goal.name)
      end
    end
  end
end

-- Saves runtime welfare into the resident record. Use wall-clock stamps for
-- reload safety; GetTime() is only a session-relative animation clock.
aquariumController.saveResidentFromFrame = function(f,t)
  if not f or not f.resident then return end
  local record = f.resident
  record.happiness = f.deadState and 0 or (f.happiness or record.happiness)
  record.hunger = f.hunger or record.hunger
  record.temperatureExposure = f.temperatureExposure or 0
  record.deathState = f.deadState
  record.deathCause = f.deathCause
  record.x, record.y = f.x, f.y
  local epoch = (time and time() or 0)
  record.lastFedAt = epoch - math.max(0,(t or 0)-(f.lastFed or t or 0))
  record.fedUntilAt = epoch + math.max(0,(f.fedUntil or 0)-(t or 0))
  if f.deadState then
    record.deadAt = epoch - math.max(0,(t or 0)-(f.deadAt or t or 0))
  end
end

-- Binds an individual saved identity and welfare state to a visual fish.
aquariumController.bindResident = function(f,record)
  f.resident = record
  f.uid = record.uid
  f.petName = record.name
  f.rarity, f.variant, f.personality = record.rarity, record.variant, record.personality
  f.lifeStage = record.lifeStage
  -- Personality changes behavior without extra O(N²) neighbor scans.
  if f.personality == 5 then f.speed = f.speed*0.65 end -- Lazy
  if f.personality == 6 then f.speed = f.speed*1.18 end -- Playful
  if f.personality == 4 then f.nextWaypoint = (GetTime and GetTime() or 0)+10 end -- Shy
  f.temperatureExposure = record.temperatureExposure or 0
  f.happiness, f.hunger = record.happiness or 100, record.hunger or 100
  local gameNow, epoch = (GetTime and GetTime() or 0), (time and time() or 0)
  f.lastFed = gameNow - math.max(0,epoch-(record.lastFedAt or epoch))
  f.fedUntil = gameNow + math.max(0,(record.fedUntilAt or 0)-epoch)
  f.deadState = record.deathState
  f.deathCause = record.deathCause
  if f.deadState then
    f.entryElapsed=nil
    f.deadAt = gameNow - math.max(0,epoch-(record.deadAt or epoch))
    f.skeletonAt = f.deadAt + 300
    f.deathX = record.x or f.x
  end
  if record.x and record.y then
    f.x, f.y = record.x, record.y
    f:ClearAllPoints()
    f:SetPoint('BOTTOMLEFT',aquariumCanvas,'BOTTOMLEFT',f.x,f.y)
  end
  if f.variant == 2 then f.icon:SetVertexColor(1,.83,.24,1)
  elseif f.variant == 3 then f.icon:SetVertexColor(.94,.98,1,1)
  elseif f.variant == 4 then f.icon:SetVertexColor(.41,.92,1,1)
  else f.icon:SetVertexColor(1,1,1,1) end
  if f.variant == 5 then f:SetScale(1.17) else f:SetScale(1) end
  f.rareBorder:SetShown((f.rarity or 1)>=3 or premiumFishIDs[f.species]~=nil)
  if f.deadState == 'skeleton' then
    f.icon:SetTexture('Interface\\Icons\\INV_Misc_Bone_ElfSkull_01')
  end
end

-- Assigns the identity of a persistent resident to an animated fish frame.
aquariumController.assignFishName = function(f, speciesIndex, record)
  if not f or not characterSettings then return end
  record = record or aquariumController.newResident(f.species,nil)
  aquariumController.bindResident(f, record)
end

-- Builds displayed fish from inventory/catches while restoring current state.
repopulateAquarium = function(skipEntrance)
  local preserve = skipEntrance == 'preserve'
  local oldFish = {}
  local gameNow=GetTime and GetTime() or 0
  for _,f in ipairs(swimmingFish) do
    aquariumController.saveResidentFromFrame(f,gameNow)
    if f.uid then
      oldFish[f.uid] = {
        x=f.x,y=f.y,targetX=f.targetX,targetY=f.targetY,
        vx=f.vx,vy=f.vy,heading=f.heading,
      }
    end
  end
  if treasureDrop and treasureDrop:IsShown() then
    treasureDrop:Hide()
    treasureDrop.floorProp = nil
  end
  -- Existing catch previews have their own landing animation. Every other
  -- aquarium rebuild animates the contents in from the waterline.
  characterSettings._aquariumRefreshEntrance = skipEntrance ~= "skip" and not preserve
  for i, fish in ipairs(swimmingFish) do fishCooldownByID[i] = fish.fedUntil or 0 end
  -- A routine catch/bag refresh must not discard active food. Frames are
  -- pooled below, so clear the old fish claims before any frames are reused.
  for _, pellet in ipairs(foodPellets) do
    pellet.claimedBy=nil
    pellet.eater=nil
    pellet.eatStarted=nil
  end
  -- A refresh recycles fish frames; never leave a highlight on a reused icon.
  if aquariumController.clearJournalFlash then aquariumController.clearJournalFlash() end
  clearFish()
  clearBubbles()
  if not characterSettings or not aquariumCanvas then return end
  repopulatePlants()
  local w,h=aquariumCanvas:GetWidth(), aquariumCanvas:GetHeight()
  for i=1,math.max(10,math.floor(w*h/3200)) do
    makeBubble(aquariumCanvas,12+(i*43)%math.max(40,w-20),6+(i*23)%math.max(30,h-10),5+(i%4),.18+(i%5)*.03,6+(i%3)*3)
  end
  -- The aquarium is a view of stable records. Inventory mode reconciles
  -- live bag counts to separate records without altering any WoW inventory.
  local entries, shown = {}, 0
  wipeTable(displayedFishEntries)
  if characterSettings.inventoryFish then
    local wanted = {}
    for _, source in ipairs(inventoryFishList()) do
      if isFishItem(source.id,source.link) then
        wanted[source.id] = { count=source.count or 1, link=source.link }
      end
    end
    local kept, current = {}, {}
    for _,record in ipairs(characterSettings.bagResidents) do
      local source = wanted[record.species]
      local n = current[record.species] or 0
      if source and n < source.count then
        current[record.species]=n+1
        kept[#kept+1]=record
      end
    end
    for id,source in pairs(wanted) do
      while (current[id] or 0) < source.count do
        local record = aquariumController.newResident(id,source.link)
        kept[#kept+1]=record
        current[id]=(current[id] or 0)+1
      end
    end
    characterSettings.bagResidents=kept
    entries=kept
  else
    entries=characterSettings.residents
  end
  shown=#entries
  for _,record in ipairs(entries) do
    displayedFishEntries[#displayedFishEntries+1]={id=record.species,count=1,link=record.link}
  end
  wipeTable(schoolTerritories)
  local seen = {}
  for _,resident in ipairs(entries) do local id=resident.species; if not seen[id] then seen[id]=true end end
  local speciesIDs={}
  for id in pairs(seen) do speciesIDs[#speciesIDs+1]=id end
  table.sort(speciesIDs)
  local nSpecies = #speciesIDs
  for k,id in ipairs(speciesIDs) do
    -- Vogel spiral distributes species across the entire glass, avoiding a
    -- single center-of-mass attractor even when several species are present.
    local radius = math.sqrt((k-0.5)/math.max(1,nSpecies)) * 0.46
    local theta = k * 2.3999632297
    local cx = 0.5 + radius * math.cos(theta)
    local cy = 0.5 + radius * math.sin(theta)
    schoolTerritories[id]={x=clamp(cx,0.12,0.88),y=clamp(cy,0.14,0.86)}
  end
  for i,record in ipairs(entries) do
    local id=record.species
    local f=spawnFish(id,i,#entries)
    if f then
      aquariumController.assignFishName(f,i,record)
      -- Only preserve current movement state for an identical resident ID.
      local saved=oldFish[record.uid]
      if saved and preserve then
        local mx=math.max(3,w-f.size-3)
        local my=math.max(3,h-f.size-3)
        f.x=clamp(saved.x or f.x,2,mx)
        f.y=clamp(saved.y or f.y,2,my)
        f.targetX=clamp(saved.targetX or f.targetX,2,mx)
        f.targetY=clamp(saved.targetY or f.targetY,2,my)
        f.vx=saved.vx; f.vy=saved.vy; f.heading=saved.heading
        f.entryElapsed=nil
        f:ClearAllPoints()
        f:SetPoint('BOTTOMLEFT',aquariumCanvas,'BOTTOMLEFT',f.x,f.y)
      end
    end
  end
  arrivingFishFrame=nil
  if arrivingFishItemID and characterSettings.catchPreview and aquariumWindow and aquariumWindow:IsShown() then
    for _,fish in ipairs(swimmingFish) do
      if fish.species==arrivingFishItemID then
        arrivingFishFrame=fish
        fish:Hide()
        break
      end
    end
  end
  repopulateTreasures()
  characterSettings._aquariumRefreshEntrance = nil
  if updateFishValue then updateFishValue() end
  if aquariumWindow and aquariumWindow.count then
    local suffix=characterSettings.inventoryFish and ('BAG FISH   %d DISPLAYED'):format(shown) or ('SESSION CATCHES   %d'):format(characterSettings.total or 0)
    aquariumWindow.count:SetText(suffix)
  end
  if aquariumWindow and aquariumWindow.roster and aquariumWindow.roster:IsShown() and aquariumController.renderFishRoster then aquariumController.renderFishRoster() end
end

-- A cinematic catch card inspired by the polished trophy reveals in western games.
-- UI only: no 3D model positioning, camera locking, or replacement of game loot.
local qualityPalette = {
  [0] = {0.62,0.62,0.62}, [1] = {0.94,0.94,0.88},
  [2] = {0.27,0.92,0.45}, [3] = {0.27,0.61,1},
  [4] = {0.69,0.36,1}, [5] = {1,0.52,0.16},
}
local qualityWords = {
  [0]='WORN', [1]='COMMON', [2]='UNCOMMON',
  [3]='RARE', [4]='EPIC', [5]='LEGENDARY'
}
-- ============================================================================
-- Catch presentation and aquarium effects
-- The catch card, decorative plants/chest, splash and water-overflow simulations.
-- ============================================================================
-- Creates the animated fish-catch reveal window and trophy display.
local function buildCatchPreview()
  local f = ui(UIParent, 500, 160, 'TOP', UIParent, 0, -130)
  f:SetFrameStrata('FULLSCREEN_DIALOG')
  f:EnableMouse(false)
  backdrop(f, {0.62,0.47,0.24,1}, {0.025,0.075,0.086,0.96})

  local header=f:CreateTexture(nil,'BACKGROUND')
  header:SetColorTexture(.23,.16,.065,.96)
  header:SetPoint('TOPLEFT',2,-2)
  header:SetPoint('TOPRIGHT',-2,-2)
  header:SetHeight(25)
  f.header=header
  local topLine=f:CreateTexture(nil,'ARTWORK')
  topLine:SetColorTexture(.93,.72,.38,.8)
  topLine:SetPoint('TOPLEFT',2,-27)
  topLine:SetPoint('TOPRIGHT',-2,-27)
  topLine:SetHeight(1)
  f.rule=topLine
  f.eyebrow=label(f,'✦   THE DAILY CATCH   ✦',12,148,-7,.98,.84,.52)

  local medallion=ui(f,112,112,'LEFT',f,14,-7)
  backdrop(medallion,{.88,.71,.39,1},{.09,.17,.18,1})
  local icon=medallion:CreateTexture(nil,'ARTWORK')
  icon:SetPoint('TOPLEFT',9,-9)
  icon:SetPoint('BOTTOMRIGHT',-9,9)
  icon:SetTexture('Interface\\Icons\\INV_Misc_Fish_02')
  icon:SetTexCoord(.07,.93,.07,.93)
  f.icon=icon

  local sparkle=f:CreateTexture(nil,'OVERLAY')
  sparkle:SetColorTexture(1,.89,.57,.16)
  sparkle:SetSize(92,5)
  sparkle:SetPoint('TOP',medallion,'TOP',0,-12)
  f.sparkle=sparkle

  -- Stylized gold glimmer, animated ripple rings, and a gently floating trophy icon.
  f.ripples={}
  for i=1,3 do
    local r=f:CreateTexture(nil,'ARTWORK')
    r:SetTexture('Interface\\COMMON\\Indicator-Yellow')
    r:SetPoint('CENTER',medallion,'CENTER',0,0)
    r:SetSize(100,100)
    r:SetVertexColor(0.92,0.72,0.35,0.08)
    f.ripples[i]=r
  end
  f.trophyFrame=medallion
  f.shineBar=f:CreateTexture(nil,'OVERLAY')
  f.shineBar:SetTexture('Interface\\Buttons\\WHITE8X8')
  f.shineBar:SetSize(22,120)
  f.shineBar:SetColorTexture(1,0.87,0.52,0.11)
  f.shineBar:SetPoint('LEFT',f,'LEFT',0,0)

  f.title=label(f,'YOU CAUGHT A FISH',11,151,-44,.55,.91,.86)
  f.name=label(f,'Fresh Fish',21,151,-67,.99,.93,.77)
  f.name:SetWidth(330)
  f.name:SetJustifyH('LEFT')
  if f.name.SetMaxLines then f.name:SetMaxLines(2) end
  f.grade=label(f,'COMMON',11,152,-113,.94,.79,.52)
  f.quantity=label(f,'x1',14,438,-112,.97,.93,.72)
  local bottom=f:CreateTexture(nil,'BORDER')
  bottom:SetColorTexture(.66,.49,.24,.55)
  bottom:SetPoint('BOTTOMLEFT',12,12)
  bottom:SetPoint('BOTTOMRIGHT',-12,12)
  bottom:SetHeight(2)
  f:Hide()
  catchRevealWindow=f
end

-- Shows the catch-preview card for newly fished loot.
local function revealCatch(id, count, itemLink)
  if not characterSettings or not characterSettings.catchPreview or not catchRevealWindow then return end
  if not isFishItem(id, itemLink) then return end
  local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(itemLink or id)
  if not name then name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(id) end
  if not name and type(itemLink)=='string' then
    name=itemLink:match('|h%[([^%]]+)%]|h')
  end
  name=name or 'Fresh Catch'
  quality=tonumber(quality) or 1
  local shade=qualityPalette[quality] or qualityPalette[1]
  catchRevealWindow.name:SetText(name)
  catchRevealWindow.name:SetTextColor(shade[1],shade[2],shade[3])
  local caught = aquariumController.lastCaughtResident
  if caught and caught.species == id then
    local rarity = caught.rarity or 1
    catchRevealWindow.grade:SetText(aquariumController.fishRarityNames[rarity]..' '..aquariumController.fishVariantNames[caught.variant or 1]..' • '..aquariumController.fishPersonalityNames[caught.personality or 1])
    local rarityColors = {{.72,.78,.80},{.32,.88,.46},{.35,.66,1},{.74,.43,1},{1,.73,.29}}
    local color = rarityColors[rarity]
    catchRevealWindow.grade:SetTextColor(color[1],color[2],color[3])
  else
    catchRevealWindow.grade:SetText(qualityWords[quality] or 'FRESH CATCH')
    catchRevealWindow.grade:SetTextColor(shade[1],shade[2],shade[3])
  end
  catchRevealWindow.quantity:SetText('x'..tostring(count or 1))
  local imageIcon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id)) or icon
  catchRevealWindow.icon:SetTexture(imageIcon or 'Interface\\Icons\\INV_Misc_Fish_02')
  queuedCatch={id=id,icon=imageIcon or icon,count=count or 1}
  if flyingCatchIcon then flyingCatchIcon:Hide() end
  if aquariumController.finishBobberHandoff then aquariumController.finishBobberHandoff() end
  previewClock=0
  catchPreviewEnds=(GetTime and GetTime() or 0)+5.5
  catchRevealWindow:ClearAllPoints()
  catchRevealWindow:SetPoint('TOP', UIParent, 'TOP', 0, -130)
  catchRevealWindow:SetAlpha(0)
  catchRevealWindow:Show()
  -- Keep the complete fishing rod, clock, and bobber displayed until landing.
  -- The UI-only handoff should never outlive the catch or require an active cast.
  aquariumController.catchTimerHandoff = characterSettings.showTimer == true
  aquariumController.timerGraceUntil = nil
  if castTimerWindow and characterSettings.showTimer then
    if castTimerWindow.clock then castTimerWindow.clock:SetText('CAUGHT!') end
    if castTimerWindow.sub then castTimerWindow.sub:SetText('sending to aquarium...') end
  end
  if updateStatus then updateStatus() end
  -- The timer may already have hidden after loot, but its bobber keeps
  -- its last screen position for the transition to the catch-preview fish.
  if aquariumController.beginBobberHandoff then aquariumController.beginBobberHandoff() end
end

-- Creates the seaweed strands and segment textures once.
local function ensureSeaweed()
  if not aquariumCanvas or #seaweedFrames > 0 then return end
  local homes = { 0.08, 0.18, 0.31, 0.69, 0.84 }
  for i = 1, 5 do
    local sw = CreateFrame('Frame', nil, aquariumCanvas)
    sw:SetFrameLevel(aquariumCanvas:GetFrameLevel())
    sw.phase = i * 1.27
    sw.home = homes[i] or (i / 6)
    sw.segments = {}
    sw.fronds = {}
    for s = 1, 6 do
      local seg = sw:CreateTexture(nil, 'BACKGROUND')
      seg:SetTexture('Interface\\Buttons\\WHITE8X8')
      seg:SetColorTexture(0.12 + s * 0.01, 0.39 + (i % 2) * 0.04 + s * 0.02, 0.20 + s * 0.01, 0.55)
      sw.segments[s] = seg
    end
    for f = 1, 4 do
      local fr = sw:CreateTexture(nil, 'BACKGROUND')
      fr:SetTexture('Interface\\Buttons\\WHITE8X8')
      fr:SetColorTexture(0.18, 0.56 + (f % 2) * 0.04, 0.28, 0.42)
      sw.fronds[f] = fr
    end
    seaweedFrames[#seaweedFrames + 1] = sw
  end
end

-- Sizes and anchors decorative seaweed when the aquarium resizes.
local function layoutSeaweed()
  if not aquariumCanvas then return end
  ensureSeaweed()
  local w, h = math.max(50, aquariumCanvas:GetWidth()), math.max(50, aquariumCanvas:GetHeight())
  for i, sw in ipairs(seaweedFrames) do
    local segW = math.max(3, math.floor(w * 0.0105))
    local strandH = math.max(42, math.floor(h * (0.26 + ((i + 1) % 3) * 0.07)))
    local totalW = segW * 8
    sw.segW = segW
    sw.strandH = strandH
    sw.baseX = clamp(math.floor(w * sw.home), 4, math.max(4, w - totalW - 4))
    sw:SetSize(totalW, strandH + 8)
    sw:ClearAllPoints()
    sw:SetPoint('BOTTOMLEFT', aquariumCanvas, 'BOTTOMLEFT', sw.baseX, 2)
    sw:Show()
  end
end

-- Ambient sand and an explicitly decorative chest: never counted as loot.
-- Creates the sand bed, decorative chest, crab and particles.
local function makeAquariumDecor()
  if not aquariumCanvas then return end
  if not ambientChest then
    ambientChest=CreateFrame('Frame',nil,aquariumCanvas)
    ambientChest:SetSize(108,98)
    ambientChest:SetFrameLevel(aquariumCanvas:GetFrameLevel()+12)
    -- The soft contact shadow anchors the chest to the sediment.
    local shadow=ambientChest:CreateTexture(nil,'BACKGROUND')
    shadow:SetTexture('Interface\\Buttons\\WHITE8X8')
    shadow:SetColorTexture(.01,.025,.025,.40)
    shadow:SetPoint('BOTTOM',ambientChest,'BOTTOM',0,1)
    shadow:SetSize(90,7)
    local body=ambientChest:CreateTexture(nil,'OVERLAY')
    body:SetTexture('Interface\\AddOns\\VibeFishin\\Media\\TreasureBody.tga')
    body:SetPoint('BOTTOM',ambientChest,'BOTTOM',0,4)
    body:SetSize(101,64)
    ambientChest.body=body
    -- Black interior is concealed by the lid while closed.
    local inside=ambientChest:CreateTexture(nil,'OVERLAY')
    inside:SetTexture('Interface\\Buttons\\WHITE8X8')
    inside:SetColorTexture(.006,.035,.035,.92)
    inside:SetPoint('BOTTOM',ambientChest,'BOTTOM',0,56)
    inside:SetSize(83,8)
    ambientChest.inside=inside
    local glow=ambientChest:CreateTexture(nil,'OVERLAY')
    glow:SetTexture('Interface\\Buttons\\WHITE8X8')
    glow:SetColorTexture(.24,.80,.91,.30)
    glow:SetPoint('BOTTOM',ambientChest,'BOTTOM',0,58)
    glow:SetSize(64,5)
    ambientChest.glow=glow
    -- Separate high-resolution lid image: its shape compresses with opening,
    -- This creates a lid hinge illusion using only standard 2-D textures.
    local lid=ambientChest:CreateTexture(nil,'OVERLAY')
    lid:SetTexture('Interface\\AddOns\\VibeFishin\\Media\\TreasureLid.tga')
    lid:SetPoint('BOTTOM',ambientChest,'BOTTOM',0,49)
    lid:SetSize(94,38)
    ambientChest.lid=lid
    ambientChest.openAmt=0
    ambientChest.bubblesClock=0
  end
  local w=aquariumCanvas:GetWidth()
  ambientChest.anchorX=clamp(w*.12, 4, math.max(4,w-115))
  ambientChest:ClearAllPoints()
  ambientChest:SetPoint('BOTTOMLEFT',aquariumCanvas,'BOTTOMLEFT',ambientChest.anchorX,1)
  ambientChest:SetShown(characterSettings and characterSettings.ambientChest ~= false)
  if #sandGrains == 0 then
    local bed=aquariumCanvas:CreateTexture(nil,'BACKGROUND')
    bed:SetTexture('Interface\\Buttons\\WHITE8X8')
    bed:SetColorTexture(.53,.40,.22,.30)
    bed:SetHeight(18)
    bed:SetPoint('BOTTOMLEFT',aquariumCanvas,'BOTTOMLEFT',1,1)
    bed:SetPoint('BOTTOMRIGHT',aquariumCanvas,'BOTTOMRIGHT',-1,1)
    local rim=aquariumCanvas:CreateTexture(nil,'BACKGROUND')
    rim:SetTexture('Interface\\Buttons\\WHITE8X8')
    rim:SetColorTexture(.72,.59,.36,.19)
    rim:SetHeight(3)
    rim:SetPoint('BOTTOMLEFT',aquariumCanvas,'BOTTOMLEFT',1,18)
    rim:SetPoint('BOTTOMRIGHT',aquariumCanvas,'BOTTOMRIGHT',-1,18)
    for i=1,110 do
      local grain=aquariumCanvas:CreateTexture(nil,'BACKGROUND')
      grain:SetTexture('Interface\\Buttons\\WHITE8X8')
      grain:SetColorTexture(.70+(i%4)*.04,.57+(i%3)*.05,.34+(i%5)*.025,.17+(i%4)*.055)
      grain:SetSize(2+(i%3),1.2+(i%2))
      sandGrains[i]={tex=grain,phase=i*2.399963,noise=i*1.73,seed=(i*.6180339887)%1,impulse=0}
    end
  end
  for i,g in ipairs(sandGrains) do
    g.baseX=6+g.seed*math.max(12,w-12)
    g.tex:ClearAllPoints()
    g.tex:SetPoint('BOTTOMLEFT',aquariumCanvas,'BOTTOMLEFT',g.baseX,3+(i%12)*1.05)
  end
  if not aquariumController.crab then
    aquariumController.crab=CreateFrame('Frame',nil,aquariumCanvas)
    aquariumController.crab:SetSize(26,18)
    aquariumController.crab:SetFrameLevel(aquariumCanvas:GetFrameLevel()+6)
    aquariumController.crab.body=aquariumController.crab:CreateTexture(nil,'ARTWORK')
    aquariumController.crab.body:SetTexture('Interface\\Buttons\\WHITE8X8')
    aquariumController.crab.body:SetColorTexture(.71,.36,.18,.95)
    aquariumController.crab.body:SetPoint('CENTER')
    aquariumController.crab.body:SetSize(14,9)
    aquariumController.crab.clawL=aquariumController.crab:CreateTexture(nil,'ARTWORK')
    aquariumController.crab.clawL:SetTexture('Interface\\Buttons\\WHITE8X8')
    aquariumController.crab.clawL:SetColorTexture(.80,.43,.20,.95)
    aquariumController.crab.clawL:SetSize(6,3)
    aquariumController.crab.clawL:SetPoint('RIGHT',aquariumController.crab.body,'TOPLEFT',1,-1)
    aquariumController.crab.clawR=aquariumController.crab:CreateTexture(nil,'ARTWORK')
    aquariumController.crab.clawR:SetTexture('Interface\\Buttons\\WHITE8X8')
    aquariumController.crab.clawR:SetColorTexture(.80,.43,.20,.95)
    aquariumController.crab.clawR:SetSize(6,3)
    aquariumController.crab.clawR:SetPoint('LEFT',aquariumController.crab.body,'TOPRIGHT',-1,-1)
    aquariumController.crab.legs={}
    for i=1,6 do
      local leg=aquariumController.crab:CreateTexture(nil,'ARTWORK')
      leg:SetTexture('Interface\\Buttons\\WHITE8X8')
      leg:SetColorTexture(.54,.25,.12,.9)
      leg:SetSize(5,1.2)
      aquariumController.crab.legs[i]=leg
    end
    aquariumController.crab.dir=1
    aquariumController.crab.x=w*0.64
    aquariumController.crab.speed=10
    aquariumController.crab.pauseUntil=0
  end
  aquariumController.crab:SetShown(characterSettings and characterSettings.movingSand ~= false)
end

-- Injects impulse into nearby sediment after a splash or chest impact.
local function disturbSand(x, strength)
  if not aquariumCanvas then return end
  for _,g in ipairs(sandGrains) do
    local dx=g.baseX-x
    local reach=math.max(25,35*strength)
    if math.abs(dx)<reach then
      g.impulse=clamp((g.impulse or 0)+(1-math.abs(dx)/reach)*strength*math.random()*15,0,34)
    end
  end
end

-- Animates sand movement, decorative chest, bubbles and crab patrol.
local function updateAquariumDecor(t, dt)
  if not aquariumCanvas or not characterSettings or not aquariumWindow or not aquariumWindow:IsShown() then return end
  local w,h=aquariumCanvas:GetWidth(),aquariumCanvas:GetHeight()
  if characterSettings.movingSand ~= false then
    for i,g in ipairs(sandGrains) do
      local push=clamp(waterSurfaceMomentum*.22+waterTurnImpulse*.11,-10,10)
      g.impulse=(g.impulse or 0)*math.max(0,1-dt*2.4)
      local drift=math.sin(t*.66+g.phase)*2.0 + push
      local xx=clamp(g.baseX + drift + math.sin(t*2.6+g.noise)*g.impulse,3,w-5)
      local yy=3+(i%12)*1.05+math.abs(math.sin(t*3+g.phase))*math.min(7,g.impulse*.28)
      g.tex:ClearAllPoints()
      g.tex:SetPoint('BOTTOMLEFT',aquariumCanvas,'BOTTOMLEFT',xx,yy)
      g.tex:SetAlpha(clamp(.35+g.impulse*.022,.2,.85))
      g.tex:Show()
    end
  else
    for _,g in ipairs(sandGrains) do g.tex:Hide() end
  end
  if ambientChest then
    ambientChest:SetShown(characterSettings.ambientChest ~= false)
    if characterSettings.ambientChest ~= false then
      -- Slowly opens, emits bubbles, and closes; slightly reacts to slosh.
      local cycle=(t*0.47+0.17)%3.5
      local target=0
      if cycle<1.2 then target=math.sin(cycle/1.2*math.pi)*0.95 end
      local slosh=characterSettings.waterMotion and clamp(math.abs(waterSurfaceMomentum)*.011,0,.25) or 0
      local goal=clamp(target+slosh,0,1)
      ambientChest.openAmt=ambientChest.openAmt+(goal-ambientChest.openAmt)*math.min(1,dt*6)
      local o=ambientChest.openAmt
      ambientChest.lid:ClearAllPoints()
      ambientChest.lid:SetPoint('BOTTOM',ambientChest,'BOTTOM',-o*1.2,49+o*11)
      ambientChest.lid:SetSize(94-o*3,38-o*9)
      ambientChest.lid:SetAlpha(1)
      ambientChest.glow:SetAlpha(.12+o*.58)
      ambientChest.inside:SetAlpha(clamp(o*.88,0,.86))
      -- Bubbles are emitted on a repeating rhythm even if the frame's
      -- open amount has not yet reached the full pose.
      if o>.16 or cycle<1.5 then
        ambientChest.bubblesClock=ambientChest.bubblesClock+dt
        if ambientChest.bubblesClock>.10 then
          ambientChest.bubblesClock=0
          for _=1,3 do
            makeSinkBubble(clamp((ambientChest.anchorX+50+math.random(-21,21))/math.max(1,w),.04,.96),clamp((64+o*12)/math.max(1,h),.03,.9))
          end
          disturbSand(ambientChest.anchorX+50, .7)
        end
      end
    end
  end
  if aquariumController.crab then
    local minX,maxX=10,math.max(10,w-32)
    if t>=(aquariumController.crab.pauseUntil or 0) then
      aquariumController.crab.x=clamp((aquariumController.crab.x or w*0.6)+(aquariumController.crab.dir or 1)*(aquariumController.crab.speed or 10)*dt, minX, maxX)
      if aquariumController.crab.x<=minX+1 then aquariumController.crab.dir=1; aquariumController.crab.pauseUntil=t+.8 end
      if aquariumController.crab.x>=maxX-1 then aquariumController.crab.dir=-1; aquariumController.crab.pauseUntil=t+.8 end
    end
    local bob=math.sin(t*8)*0.8
    local sway=(characterSettings.waterMotion and waterSurfaceMomentum or 0)*0.08
    aquariumController.crab:ClearAllPoints()
    aquariumController.crab:SetPoint('BOTTOMLEFT',aquariumCanvas,'BOTTOMLEFT',aquariumController.crab.x,5+bob)
    for i,leg in ipairs(aquariumController.crab.legs) do
      local side=i<=3 and -1 or 1
      local idx=i<=3 and i or (i-3)
      leg:ClearAllPoints()
      leg:SetPoint('CENTER',aquariumController.crab.body,'CENTER',side*(5+idx*1.8),-1-idx*1.5+math.sin(t*10+i)*0.3)
      if leg.SetRotation then leg:SetRotation(side*(0.25+math.sin(t*9+i)*0.08)) end
    end
    if aquariumController.crab.clawL.SetRotation then aquariumController.crab.clawL:SetRotation(-0.35+math.sin(t*6)*0.14+sway*0.01) end
    if aquariumController.crab.clawR.SetRotation then aquariumController.crab.clawR:SetRotation(0.35+math.sin(t*6+1.2)*0.14+sway*0.01) end
    aquariumController.crab:SetShown(characterSettings.movingSand ~= false)
  end
end

-- Spawns a white-blue impact splash and agitates the water surface.
local function splashAt(x, y)
  if not aquariumCanvas or not aquariumWindow or not aquariumWindow:IsShown() then return end
  local left,bottom=aquariumCanvas:GetLeft(),aquariumCanvas:GetBottom()
  if not left or not bottom then return end
  local fx=x+(UIParent:GetLeft() or 0)-left
  local fy=y+(UIParent:GetBottom() or 0)-bottom
  splashX=clamp(fx,12,aquariumCanvas:GetWidth()-12)
  splashY=clamp(fy,12,aquariumCanvas:GetHeight()-12)
  splashStart=GetTime and GetTime() or now
  if arrivingFishFrame then
    arrivingFishFrame.x=splashX
    arrivingFishFrame.y=splashY
    arrivingFishFrame.vx=18 + math.sin((now or 0) * 2.1) * 18
    arrivingFishFrame.vy=-38
    arrivingFishFrame:Show()
  end
  arrivingFishItemID,arrivingFishFrame=nil,nil
  local impactSide = (splashX / math.max(1, aquariumCanvas:GetWidth())) < 0.5 and -1 or 1
  waterTurnImpulse=clamp(waterTurnImpulse+24*impactSide,-48,48)
  waterSurfaceMomentum=clamp(waterSurfaceMomentum+12*impactSide,-28,28)
  for _=1,4 do spawnSpill(impactSide,1.1+math.random()*0.4) end
  if aquariumWindow and aquariumWindow.surfaceWave then aquariumWindow.surfaceWave:SetAlpha(1) end
  for _, droplet in ipairs(splashDroplets) do
    droplet:Hide()
    splashDropletPool[#splashDropletPool + 1] = droplet
  end
  for _, ring in ipairs(splashRings) do
    ring:Hide()
    splashRingPool[#splashRingPool + 1] = ring
  end
  wipeTable(splashDroplets)
  wipeTable(splashRings)
  for i=1,24 do
    local part=table.remove(splashDropletPool) or CreateFrame('Frame',nil,aquariumCanvas)
    part:SetSize(2.5+(i%4)*1.6,5+(i%4)*1.2)
    if not part.tex then
      part.tex=part:CreateTexture(nil,'OVERLAY')
      part.tex:SetAllPoints()
      part.tex:SetTexture('Interface\\Buttons\\WHITE8X8')
    end
    part.tex:SetColorTexture(.90,.98,1,.92)
    local ang=(i/24)*2*math.pi + math.random()*0.22
    local speed=42+(i%7)*12
    part.vx=math.cos(ang)*speed
    part.vy=math.sin(ang)*speed+44
    part.phase=i*.62
    part:ClearAllPoints()
    part:SetPoint('CENTER',aquariumCanvas,'BOTTOMLEFT',splashX,splashY)
    part:Show()
    splashDroplets[#splashDroplets+1]=part
  end
  for i=1,4 do
    local ring=table.remove(splashRingPool) or aquariumCanvas:CreateTexture(nil,'OVERLAY')
    ring:SetTexture('Interface\\COMMON\\Indicator-Yellow')
    ring:SetVertexColor(.84,.98,1,.52)
    ring:SetSize(10,10)
    ring:ClearAllPoints()
    ring:SetPoint('CENTER',aquariumCanvas,'BOTTOMLEFT',splashX,splashY)
    ring:Show()
    splashRings[#splashRings+1]=ring
  end
end


-- Updates splash droplets and expanding water rings per frame.
local function animateSplash(t)
  if splashStart<=0 then return end
  local elapsed=t-splashStart
  if elapsed>=splashDuration then
    for _,part in ipairs(splashDroplets) do part:Hide() end
    for _,ring in ipairs(splashRings) do ring:Hide() end
    splashStart=0
    return
  end
  local progress=clamp(elapsed/splashDuration,0,1)
  waterTurnImpulse = clamp(waterTurnImpulse + (0.5 - progress) * 0.35, -48, 48)
  for _,part in ipairs(splashDroplets) do
    local px=splashX+part.vx*elapsed
    local py=splashY+part.vy*elapsed-185*elapsed*elapsed
    part:ClearAllPoints()
    part:SetPoint('CENTER',aquariumCanvas,'BOTTOMLEFT',px,py)
    part:SetAlpha((1-progress)^1.45)
  end
  for i,ring in ipairs(splashRings) do
    local phase=clamp((elapsed-(i-1)*.10)/.95,0,1)
    ring:SetSize(12+phase*112,8+phase*36)
    ring:SetAlpha((1-phase)*.52)
  end
end


-- GetCenter/GetLeft/GetBottom share the same UI coordinate space.
-- Anchor positions are relative to the UIParent's bottom-left origin.
-- Converts a frame center to UIParent-local screen coordinates.
local function screenPointInUIParent(frame)
  if not frame then return nil end
  local x,y=frame:GetCenter()
  if not x or not y then return nil end
  return x-(UIParent:GetLeft() or 0), y-(UIParent:GetBottom() or 0)
end

-- Converts normalized aquarium coordinates to UIParent coordinates.
local function aquariumPointInUIParent(normX, normY)
  if not aquariumCanvas then return nil end
  local left, bottom = aquariumCanvas:GetLeft(), aquariumCanvas:GetBottom()
  if not left or not bottom then return nil end
  normX = clamp(tonumber(normX) or 0.5, 0, 1)
  normY = clamp(tonumber(normY) or 0.5, 0, 1)
  local x = left - (UIParent:GetLeft() or 0) + aquariumCanvas:GetWidth() * normX
  local y = bottom - (UIParent:GetBottom() or 0) + aquariumCanvas:GetHeight() * normY
  return x, y
end

-- Lightweight spill sprites are deliberately *outside* the tank bounds.
-- This is a screen-space illusion, not an attempt to alter WoW water physics.
-- Creates a water droplet that spills over the aquarium rim.
spawnSpill = function(side, strength)
  if not aquariumWindow or not aquariumWindow.tank or not aquariumWindow:IsShown() then return end
  local tank=aquariumWindow.tank
  local w=tank:GetWidth()
  local part=table.remove(overflowDropletPool) or CreateFrame('Frame',nil,aquariumWindow)
  if not part.tex then
    part.tex=part:CreateTexture(nil,'OVERLAY')
    part.tex:SetAllPoints()
    part.tex:SetTexture('Interface\\Buttons\\WHITE8X8')
  end
  part:SetFrameLevel(aquariumWindow:GetFrameLevel()+8)
  local ordinal=#overflowDroplets+1
  part.side=side
  part.x=(side<0 and -4 or w+4) + math.sin((now or 0)*3+ordinal*2.3)*5
  part.y=-12
  part.vx=(side<0 and -1 or 1)*(11+ordinal%4*5)*strength
  part.vy=-(19+ordinal%5*7)
  part.age=0
  part.life=.58+ordinal%4*.12
  local size=2.5+(ordinal%3)
  part:SetSize(size,size+2)
  part.tex:SetColorTexture(.58,.91,1,.83)
  part:ClearAllPoints()
  part:SetPoint('CENTER',tank,'TOPLEFT',part.x,part.y)
  part:Show()
  overflowDroplets[#overflowDroplets+1]=part
end

-- Animates water overflow droplets outside the tank boundaries.
local function updateSpills(t,dt)
  if not aquariumWindow or not aquariumWindow.tank then return end
  local drift=characterSettings.waterMotion and waterSurfaceMomentum or 0
  local amt=math.abs(drift)
  if aquariumWindow.surfaceWave then
    -- Keep the surface line within the aquarium; never slide it sideways.
    aquariumWindow.surfaceWave:SetAlpha(clamp(.38+amt*.023, .3, .9))
  end
  if aquariumWindow.waterLipLeft and aquariumWindow.waterLipRight then
    local height=clamp((amt-1.5)*0.9,0,22)
    local left=drift<0 and height or 0
    local right=drift>0 and height or 0
    aquariumWindow.waterLipLeft:SetHeight(math.max(1,2+left))
    aquariumWindow.waterLipRight:SetHeight(math.max(1,2+right))
    aquariumWindow.waterLipLeft:SetAlpha(clamp(left/10,.08,.83))
    aquariumWindow.waterLipRight:SetAlpha(clamp(right/10,.08,.83))
  end
  if amt>3.5 and aquariumWindow:IsShown() and characterSettings.waterMotion then
    spillAccumulator=spillAccumulator+dt*(2+(amt-3.5)*.7)
    while spillAccumulator>=1 do
      spawnSpill(drift<0 and -1 or 1,clamp(amt/12,.6,1.7))
      spillAccumulator=spillAccumulator-1
    end
  else
    spillAccumulator=0
  end
  for i=#overflowDroplets,1,-1 do
    local p=overflowDroplets[i]
    p.age=p.age+dt
    if p.age>=p.life or not aquariumWindow:IsShown() then
      p:Hide()
      overflowDropletPool[#overflowDropletPool+1]=p
      table.remove(overflowDroplets,i)
    else
      p.x=p.x+p.vx*dt
      p.y=p.y+p.vy*dt-120*dt*dt
      p.vy=p.vy-160*dt
      p:ClearAllPoints()
      p:SetPoint('CENTER',aquariumWindow.tank,'TOPLEFT',p.x,p.y)
      p:SetAlpha((1-p.age/p.life)*.85)
    end
  end
end

-- Reuses a single cosmetic copy of the cast bobber for catch handoffs.
-- The fishing timer remains in its saved location; no inventory action occurs.
aquariumController.beginBobberHandoff = function()
  if not characterSettings or not characterSettings.showTimer or not castTimerWindow or not castTimerWindow.bobberAnchor then return end
  local startX, startY = screenPointInUIParent(castTimerWindow.bobberAnchor)
  if not startX then return end
  if not aquariumController.handoffBobber then
    local bobber = CreateFrame('Frame', nil, UIParent)
    bobber:SetFrameStrata('TOOLTIP')
    bobber:SetSize(40, 40)
    local function addPiece(width, height, x, y, r, g, b, alpha)
      local texture = bobber:CreateTexture(nil, 'ARTWORK')
      texture:SetColorTexture(r, g, b, alpha or 1)
      texture:SetSize(width, height)
      texture:SetPoint('CENTER', bobber, 'CENTER', x, y)
      return texture
    end
    addPiece(12, 16, 0, -1, .98, .98, 1)
    addPiece(12, 8, 0, 9, .94, .27, .22)
    addPiece(4, 4, 0, 15, 1, .86, .35)
    bobber.surface = addPiece(38, 2, 0, -5, .36, .91, 1, .95)
    bobber:Hide()
    aquariumController.handoffBobber = bobber
  end
  aquariumController.handoffBobber.startX, aquariumController.handoffBobber.startY = startX, startY
  aquariumController.handoffBobber.elapsed = 0
  aquariumController.handoffBobber.phase = 'approach'
  aquariumController.handoffBobber:ClearAllPoints()
  aquariumController.handoffBobber:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', startX, startY)
  aquariumController.handoffBobber:SetAlpha(1)
  aquariumController.handoffBobber:Show()
end

-- Animates the bobber from the rod to the preview, then beside the flying fish.
-- Uses the existing throttled heartbeat without a second OnUpdate callback.
aquariumController.animateBobberHandoff = function(dt)
  local bobber = aquariumController.handoffBobber
  if not bobber or not bobber:IsShown() then return end
  local inFlight = flyingCatchIcon and flyingCatchIcon:IsShown()
  if not inFlight and (not catchRevealWindow or not catchRevealWindow:IsShown()) then
    bobber:Hide()
    return
  end
  local target = inFlight and flyingCatchIcon or catchRevealWindow.trophyFrame
  local targetX, targetY = screenPointInUIParent(target)
  if not targetX then bobber:Hide(); return end
  -- Keep the fish icon unobscured by offsetting the attached bobber.
  targetX, targetY = targetX + 27, targetY - 8
  local x, y = targetX, targetY
  if not inFlight and bobber.phase == 'approach' then
    bobber.elapsed = (bobber.elapsed or 0) + dt
    local progress = clamp(bobber.elapsed / 0.7, 0, 1)
    local eased = progress * progress * (3 - 2 * progress)
    x = bobber.startX + (targetX - bobber.startX) * eased
    y = bobber.startY + (targetY - bobber.startY) * eased + math.sin(progress * math.pi) * 30
    if progress >= 1 then bobber.phase = 'attached' end
  elseif inFlight then
    bobber.phase = 'flight'
  end
  bobber:ClearAllPoints()
  bobber:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', x, y)
  bobber.surface:SetWidth(38 + math.sin((now or 0) * 4) * 3)
end

-- Removes the cosmetic transfer bobber when the catch enters the water.
aquariumController.finishBobberHandoff = function()
  if aquariumController.handoffBobber then aquariumController.handoffBobber:Hide() end
  aquariumController.catchTimerHandoff = nil
  if updateStatus then updateStatus() end
end

-- Moves a caught fish from the reveal window toward the aquarium.
local function startCatchFlight()
  if not catchRevealWindow or not aquariumWindow or not aquariumCanvas or not queuedCatch then return false end
  if not aquariumWindow:IsShown() then return false end
  local x,y=screenPointInUIParent(catchRevealWindow.trophyFrame)
  if not x then return false end
  if not flyingCatchIcon then
    flyingCatchIcon=CreateFrame('Frame',nil,UIParent)
    flyingCatchIcon:SetFrameStrata('TOOLTIP')
    flyingCatchIcon:SetSize(74,74)
    flyingCatchIcon.icon=flyingCatchIcon:CreateTexture(nil,'ARTWORK')
    flyingCatchIcon.icon:SetAllPoints()
    flyingCatchIcon.icon:SetTexCoord(.07,.93,.07,.93)
    flyingCatchIcon:Hide()
  end
  -- Land at the top of the aquarium rather than its center.
  -- Recompute it during flight to follow a dragged/resized aquarium.
  flyingCatchIcon.entryNormX = 0.22 + math.random() * 0.56
  flyingCatchIcon.entryNormY = 0.93
  local destX,destY=aquariumPointInUIParent(flyingCatchIcon.entryNormX, flyingCatchIcon.entryNormY)
  if not destX then return false end
  flyingCatchIcon.icon:SetTexture(queuedCatch.icon or 'Interface\\Icons\\INV_Misc_Fish_02')
  flyingCatchIcon.startX=x
  flyingCatchIcon.startY=y
  flyingCatchIcon.endX=destX
  flyingCatchIcon.endY=destY
  previewFlightClock=0
  flyingCatchIcon:ClearAllPoints()
  flyingCatchIcon:SetPoint('CENTER',UIParent,'BOTTOMLEFT',x,y)
  flyingCatchIcon:SetSize(74,74)
  flyingCatchIcon:SetAlpha(1)
  flyingCatchIcon:SetScale(1)
  if not flyingCatchIcon.trails then
    flyingCatchIcon.trails={}
    for i=1,4 do
      local t=CreateFrame('Frame',nil,UIParent)
      t:SetFrameStrata('TOOLTIP')
      t:SetSize(14,14)
      t.icon=t:CreateTexture(nil,'OVERLAY')
      t.icon:SetAllPoints()
      t.icon:SetTexture('Interface\\COMMON\\Indicator-Yellow')
      t.icon:SetVertexColor(.83,.98,1,.32)
      flyingCatchIcon.trails[i]=t
    end
  end
  for _,trail in ipairs(flyingCatchIcon.trails) do trail:Show() end
  flyingCatchIcon:Show()
  queuedCatch=nil
  return true
end

-- Advances the fish flight arc and triggers a splash at landing.
local function animateCatchFlight(dt)
  if not flyingCatchIcon or not flyingCatchIcon:IsShown() then return end
  previewFlightClock=previewFlightClock+dt
  local t=clamp(previewFlightClock/previewFlightDuration,0,1)
  local eased=t*t*(3-2*t)
  local targetX,targetY=aquariumPointInUIParent(flyingCatchIcon.entryNormX or 0.5, flyingCatchIcon.entryNormY or 0.93)
  if targetX then
    flyingCatchIcon.endX=targetX
    flyingCatchIcon.endY=targetY
  end
  local x=flyingCatchIcon.startX+(flyingCatchIcon.endX-flyingCatchIcon.startX)*eased
  local y=flyingCatchIcon.startY+(flyingCatchIcon.endY-flyingCatchIcon.startY)*eased+math.sin(t*math.pi)*95
  flyingCatchIcon:ClearAllPoints()
  flyingCatchIcon:SetPoint('CENTER',UIParent,'BOTTOMLEFT',x,y)
  -- Do not scale the frame: scaled offsets caused the icon to drift off-screen.
  flyingCatchIcon:SetSize(74-46*eased,74-46*eased)
  flyingCatchIcon:SetAlpha(1-t*.15)
  if flyingCatchIcon.trails then
    for i, trail in ipairs(flyingCatchIcon.trails) do
      local u=clamp(t-i*.045,0,1)
      local e=u*u*(3-2*u)
      local trailX=flyingCatchIcon.startX+(flyingCatchIcon.endX-flyingCatchIcon.startX)*e
      local trailY=flyingCatchIcon.startY+(flyingCatchIcon.endY-flyingCatchIcon.startY)*e+math.sin(u*math.pi)*95
      trail:ClearAllPoints()
      trail:SetPoint('CENTER',UIParent,'BOTTOMLEFT',trailX,trailY)
      trail:SetSize(12-i,12-i)
      trail:SetAlpha((1-t)*(0.37-i*.07))
    end
  end
  if t>=1 then
    if aquariumController.finishBobberHandoff then aquariumController.finishBobberHandoff() end
    flyingCatchIcon:Hide()
    if flyingCatchIcon.trails then for _,trail in ipairs(flyingCatchIcon.trails) do trail:Hide() end end
    splashAt(flyingCatchIcon.endX, flyingCatchIcon.endY)
    if aquariumWindow and aquariumWindow.surfaceWave then aquariumWindow.surfaceWave:SetAlpha(.95) end
  end
end

-- Short-lived cosmetic particles; none of these are inventory items.
-- ============================================================================
-- Treasure physics and particle effects
-- Sinking loot, suspended sediment, impact debris and bubbles.
-- ============================================================================
-- Recycles trail bubbles from prior chest animations.
local function clearSinkingBubbles()
  for _, bubble in ipairs(sinkingBubbles) do
    bubble:Hide()
    sinkingBubblePool[#sinkingBubblePool + 1] = bubble
  end
  wipeTable(sinkingBubbles)
end

-- Recycles particles from the last treasure impact.
local function clearSandCloud()
  for _, particle in ipairs(sandCloud) do
    particle:Hide()
    sandCloudPool[#sandCloudPool + 1] = particle
  end
  wipeTable(sandCloud)
  sandCloudAge = 0
end

-- Creates a rising bubble with a normalized tank position.
makeSinkBubble = function(normX, normY)
  if not aquariumCanvas then return end
  local b = table.remove(sinkingBubblePool) or CreateFrame('Frame', nil, aquariumCanvas)
  if not b.dot then
    b.dot = b:CreateTexture(nil, 'OVERLAY')
    b.dot:SetAllPoints()
    b.dot:SetTexture('Interface\\AddOns\\VibeFishin\\Media\\BubbleRing.tga')
  end
  local w, h = aquariumCanvas:GetWidth(), aquariumCanvas:GetHeight()
  b.x = clamp(normX * w + (math.random() - 0.5) * 14, 4, w - 4)
  b.y = clamp(normY * h + 5, 4, h - 4)
  b.speed = 26 + math.random() * 26
  b.age = 0
  b.life = 1.8 + math.random() * 1.1
  local size = 8 + math.random() * 6
  b:SetSize(size, size)
  b.dot:SetVertexColor(0.85, 1, 1, 1)
  b:ClearAllPoints()
  b:SetPoint('CENTER', aquariumCanvas, 'BOTTOMLEFT', b.x, b.y)
  b:Show()
  sinkingBubbles[#sinkingBubbles + 1] = b
end

-- Creates bottom-sediment particles after a treasure impact.
local function spawnSandCloud(normX)
  clearSandCloud()
  if not aquariumCanvas then return end
  local w = aquariumCanvas:GetWidth()
  local x = clamp(normX * w, 12, w - 12)
  disturbSand(x, 2.7)
  for i = 1, 14 do
    local part = table.remove(sandCloudPool) or CreateFrame('Frame', nil, aquariumCanvas)
    if not part.dot then
      part.dot = part:CreateTexture(nil, 'OVERLAY')
      part.dot:SetAllPoints()
      part.dot:SetTexture('Interface\\COMMON\\Indicator-Yellow')
    end
    local angle = math.pi * (0.08 + (i / 15) * 0.84)
    part.baseX = x
    part.vx = math.cos(angle) * (22 + (i % 5) * 7)
    part.vy = math.sin(angle) * (10 + (i % 4) * 7)
    local size = 6 + (i % 4) * 2
    part:SetSize(size, size)
    part.dot:SetVertexColor(0.68, 0.55, 0.33, 0.50)
    part:ClearAllPoints()
    part:SetPoint('CENTER', aquariumCanvas, 'BOTTOMLEFT', x, 9)
    part:Show()
    sandCloud[#sandCloud + 1] = part
  end
  sandCloudAge = 0.0001
end

-- Advances bubble trails and impact sand particles.
local function updateTreasureParticles(dt)
  if not aquariumCanvas then return end
  for i = #sinkingBubbles, 1, -1 do
    local b = sinkingBubbles[i]
    b.age = b.age + dt
    b.y = b.y + b.speed * dt
    b.x = b.x + math.sin(b.age * 7 + i) * dt * 6
    if b.age > b.life or b.y > aquariumCanvas:GetHeight() - 3 then
      b:Hide()
      sinkingBubblePool[#sinkingBubblePool + 1] = b
      table.remove(sinkingBubbles, i)
    else
      b:ClearAllPoints()
      b:SetPoint('CENTER', aquariumCanvas, 'BOTTOMLEFT', b.x, b.y)
      b:SetAlpha((1 - b.age / b.life) * 0.98)
    end
  end
  if sandCloudAge > 0 then
    sandCloudAge = sandCloudAge + dt
    if sandCloudAge >= sandCloudDuration then
      clearSandCloud()
    else
      local progress = sandCloudAge / sandCloudDuration
      for _, part in ipairs(sandCloud) do
        local dx = part.vx * sandCloudAge
        local dy = part.vy * sandCloudAge - 16 * sandCloudAge * sandCloudAge
        part:ClearAllPoints()
        part:SetPoint('CENTER', aquariumCanvas, 'BOTTOMLEFT', part.baseX + dx, 9 + dy)
        part:SetAlpha(0.38 * (1 - progress) * (1 - progress))
      end
    end
  end
end

-- Creates a vertically sinking chest from a top-of-tank entry point.
startTreasureDrop = function(id)
  if not aquariumWindow or not aquariumCanvas or not aquariumWindow:IsShown() then return false end
  -- If another chest is still sinking, finish it before beginning this one.
  if treasureDrop and treasureDrop:IsShown() then
    treasureDrop:Hide()
    if treasureDrop.floorProp then treasureDrop.floorProp:Show() end
  end
  clearSinkingBubbles()
  local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id)) or 'Interface\\Icons\\INV_Misc_TreasureChest03'
  if not treasureDrop then
    treasureDrop = CreateFrame('Frame', nil, UIParent)
    treasureDrop:SetFrameStrata('TOOLTIP')
    treasureDrop:SetSize(42, 42)
    treasureDrop.icon = treasureDrop:CreateTexture(nil, 'OVERLAY')
    treasureDrop.icon:SetAllPoints()
    treasureDrop.icon:SetTexCoord(.08, .92, .08, .92)
    treasureDrop.shadow = treasureDrop:CreateTexture(nil, 'BACKGROUND')
    treasureDrop.shadow:SetTexture('Interface\\Buttons\\WHITE8X8')
    treasureDrop.shadow:SetColorTexture(0, 0, 0, 0.2)
    treasureDrop.shadow:SetPoint('BOTTOMLEFT', treasureDrop, 'BOTTOMLEFT', 5, -5)
    treasureDrop.shadow:SetPoint('BOTTOMRIGHT', treasureDrop, 'BOTTOMRIGHT', -5, -9)
    treasureDrop.shadow:SetHeight(8)
    treasureDrop:Hide()
  end
  treasureDrop.icon:SetTexture(icon)
  -- Pick the newly added floor icon and hide it until the animation completes.
  treasureDrop.floorProp = nil
  for _, prop in ipairs(displayedTreasureFrames) do
    if prop.itemID == id then
      treasureDrop.floorProp = prop
      prop:Hide()
      break
    end
  end
  treasureDrop.entryNormY = 0.94
  treasureDrop.floorNormY = 0.10
  if treasureDrop.floorProp then
    treasureDrop.floorNormX = clamp((treasureDrop.floorProp.baseX + 13) / math.max(1, aquariumCanvas:GetWidth()), 0.06, 0.94)
    treasureDrop.entryNormX = treasureDrop.floorNormX
  else
    treasureDrop.entryNormX = 0.10 + math.random() * 0.80
    treasureDrop.floorNormX = treasureDrop.entryNormX
  end
  local sx, sy = aquariumPointInUIParent(treasureDrop.entryNormX, treasureDrop.entryNormY)
  local ex, ey = aquariumPointInUIParent(treasureDrop.floorNormX, treasureDrop.floorNormY)
  if not sx or not ex then
    if treasureDrop.floorProp then treasureDrop.floorProp:Show() end
    return false
  end
  treasureDrop.startX, treasureDrop.startY = sx, sy + 10
  treasureDrop.endX, treasureDrop.endY = ex, ey
  treasureDropClock = 0
  treasureDrop.bubbleClock = 0
  treasureDrop.impactDone = false
  treasureDrop:ClearAllPoints()
  treasureDrop:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', sx, sy + 10)
  treasureDrop:SetSize(42, 42)
  treasureDrop:SetAlpha(1)
  treasureDrop:Show()
  splashAt(sx, sy)
  return true
end

-- Animates chest acceleration, trailing bubbles and landing bounce.
animateTreasureDrop = function(dt)
  updateTreasureParticles(dt)
  if not treasureDrop or not treasureDrop:IsShown() then return end
  treasureDropClock = treasureDropClock + dt
  -- 0-76%: accelerating sink; 76-100%: short, damped bottom bounce.
  local t = clamp(treasureDropClock / treasureDropDuration, 0, 1)
  local sinkProgress = clamp(t / 0.76, 0, 1)
  local gravityEase = sinkProgress * sinkProgress
  local bounceT = clamp((t - 0.76) / 0.24, 0, 1)
  local sx, sy = aquariumPointInUIParent(treasureDrop.entryNormX, treasureDrop.entryNormY)
  local ex, ey = aquariumPointInUIParent(treasureDrop.floorNormX, treasureDrop.floorNormY)
  if sx and ex then
    treasureDrop.startX, treasureDrop.startY = sx, sy + 10
    treasureDrop.endX, treasureDrop.endY = ex, ey
  end
  local x = treasureDrop.startX + (treasureDrop.endX - treasureDrop.startX) * gravityEase
  local y = treasureDrop.startY + (treasureDrop.endY - treasureDrop.startY) * gravityEase
  if t > 0.76 then
    -- One small bounce, then settle onto the prop's final location.
    y = treasureDrop.endY + math.sin(bounceT * math.pi) * (1 - bounceT) * 13
    x = treasureDrop.endX
    if not treasureDrop.impactDone then
      treasureDrop.impactDone = true
      spawnSandCloud(treasureDrop.floorNormX)
    end
  else
    treasureDrop.bubbleClock = treasureDrop.bubbleClock + dt
    if treasureDrop.bubbleClock >= 0.11 then
      treasureDrop.bubbleClock = 0
      local w, h = aquariumCanvas:GetWidth(), aquariumCanvas:GetHeight()
      local left, bottom = aquariumCanvas:GetLeft(), aquariumCanvas:GetBottom()
      if left and bottom and w > 0 and h > 0 then
        local localX = (x + (UIParent:GetLeft() or 0) - left) / w
        local localY = (y + (UIParent:GetBottom() or 0) - bottom) / h
        makeSinkBubble(clamp(localX, 0.05, 0.95), clamp(localY, 0.05, 0.95))
      end
    end
  end
  treasureDrop:ClearAllPoints()
  treasureDrop:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', x, y)
  treasureDrop:SetSize(42 - 12 * sinkProgress, 42 - 12 * sinkProgress)
  treasureDrop:SetAlpha(1)
  if t >= 1 then
    treasureDrop:Hide()
    if treasureDrop.floorProp then treasureDrop.floorProp:Show() end
    treasureDrop.floorProp = nil
  end
end

-- ============================================================================
-- Catch recording and tank temperature
-- Recording catches and managing the simulated fish welfare system.
-- ============================================================================
-- Records a fish catch and preserves the locations of existing residents.
local function addCatch(id, count, itemLink)
  if not id then return end
  count = math.max(1, math.floor(tonumber(count) or 1))
  if arrivingFishFrame then arrivingFishFrame:Show() end
  arrivingFishFrame=nil
  arrivingFishItemID=(characterSettings.catchPreview and aquariumWindow and aquariumWindow:IsShown()) and id or nil
  characterSettings.total = (characterSettings.total or 0) + count
  characterSettings.catches[#characterSettings.catches + 1] = { id = id, count = count }
  local newResidents={}
  for j=1,count do
    local resident=aquariumController.newResident(id,itemLink)
    characterSettings.residents[#characterSettings.residents+1]=resident
    newResidents[#newResidents+1]=resident
    aquariumController.recordFishDiscovery(resident)
  end
  aquariumController.lastCaughtResident=newResidents[1]
  if characterSettings.inventoryFish then
    repopulateAquarium('preserve')
  elseif aquariumCanvas then
    -- Add just the new fish frames. Do not clear the live schools, feeding
    -- targets, bubbles, or the positions of fish already in the aquarium.
    local firstNew=nil
    for j=1,count do
      if not schoolTerritories[id] then
        schoolTerritories[id]={x=.2+math.random()*.6,y=.25+math.random()*.5}
      end
      local f=spawnFish(id,#swimmingFish+1,math.max(1,#swimmingFish+1))
      if f then
        local speciesCount=0
        for _,existing in ipairs(swimmingFish) do if existing.species==id then speciesCount=speciesCount+1 end end
        aquariumController.assignFishName(f,speciesCount,newResidents[j])
        displayedFishEntries[#displayedFishEntries+1]={id=id,count=1,link=itemLink}
        if not firstNew then firstNew=f end
      end
    end
    if characterSettings.catchPreview and aquariumWindow and aquariumWindow:IsShown() then
      arrivingFishFrame=firstNew
      if firstNew then firstNew:Hide() end
    end
    if aquariumWindow and aquariumWindow.count then
      aquariumWindow.count:SetText(('SESSION CATCHES   %d'):format(characterSettings.total or 0))
    end
    if updateFishValue then updateFishValue() end
    if aquariumWindow and aquariumWindow.roster and aquariumWindow.roster:IsShown() and aquariumController.renderFishRoster then aquariumController.renderFishRoster() end
  else
    repopulateAquarium('preserve')
  end
  revealCatch(id, count, itemLink)
end

-- UI-only temperature simulation. No inventory items or saved catches are destroyed.
-- Estimates ambient aquarium temperature from the current WoW zone.
aquariumController.getZoneAmbient = function()
  local zone = (GetZoneText and GetZoneText()) or ''
  local subzone = (GetSubZoneText and GetSubZoneText()) or ''
  local name = (zone .. ' ' .. subzone):lower()
  local cold = {'winterspring','dun morogh','alterac','icecrown','storm peaks','dragonblight',
    'howling fjord','borean tundra','wintergrasp','frostfire','snow','frozen','glacier'}
  local hot = {'tanaris','thousand needles','uldum','silithus','searing gorge','burning steppes',
    'hellfire','ungoro','un\'goro','badlands','desolace','volcan','lava','desert'}
  for _,part in ipairs(cold) do if name:find(part,1,true) then return 51, zone end end
  for _,part in ipairs(hot) do if name:find(part,1,true) then return 78, zone end end
  local warm = {'stranglethorn','durotar','barrens','dustwallow','feralas','swamp','nagrand','sholazar'}
  for _,part in ipairs(warm) do if name:find(part,1,true) then return 72, zone end end
  return 65, zone
end

-- Updates temperature, heater power and fish welfare text.
aquariumController.updateHeaterDisplay = function(t)
  if not characterSettings or not aquariumWindow then return end
  if not aquariumController.waterTemp then aquariumController.waterTemp = (aquariumController.getZoneAmbient()) + (characterSettings.heaterPower or 25)*.28 end
  if aquariumController.tempWidget then
    local temp = math.floor(aquariumController.waterTemp + .5)
    local vital = math.floor((aquariumController.fishVitality or 100) + .5)
    local hunger = math.floor((aquariumController.hungerVitality or 100) + .5)
    aquariumController.tempWidget.readout:SetText(('%d|cffff9a3a°F|r  %d%%'):format(temp, characterSettings.heaterPower or 0))
    local comfort = aquariumController.waterTemp >= 70 and aquariumController.waterTemp <= 80
    local state = comfort and 'HAPPY' or (aquariumController.waterTemp < 70 and 'COLD' or 'HOT')
    if (aquariumController.deadFishCount or 0) > 0 then
      state = 'LOSS'
    elseif hunger <= 25 then
      state = 'STARVING'
    elseif hunger <= 60 then
      state = 'HUNGRY'
    end
    local sr,sg,sb = .45,.92,.42
    if state == 'COLD' or state == 'HOT' then sr,sg,sb = 1,.55,.42 end
    if state == 'HUNGRY' then sr,sg,sb = .97,.84,.36 end
    if state == 'STARVING' or state == 'LOSS' then sr,sg,sb = .99,.44,.44 end
    aquariumController.tempWidget.state:SetText(state)
    aquariumController.tempWidget.state:SetTextColor(sr,sg,sb)
    aquariumController.tempWidget.vitality:SetText(('H%d%% F%d%%'):format(hunger,vital))
  end
  if aquariumController.heater then
    local power = clamp((characterSettings.heaterPower or 0) / 100, 0, 1)
    local pulse = .77 + .23 * math.sin((t or 0) * (1.8 + power * 3.1))
    -- The photographic-style body stays visible; only its coil is animated.
    aquariumController.heater.glow:SetAlpha(clamp((.04 + .96 * power) * pulse, .015, 1))
    aquariumController.heater.indicator:SetAlpha(.16 + .8 * power)
    if aquariumController.heater.aura then
      aquariumController.heater.aura:SetAlpha(clamp((.04 + .67 * power) * (.62 + .38 * math.sin((t or 0)* (1.4 + power*2.5))), .01, .8))
    end
    if aquariumController.heater.auraOuter then
      aquariumController.heater.auraOuter:SetAlpha(clamp((.025 + .35 * power) * (.65 + .35 * math.sin((t or 0)* (1.08+power*1.6)+1.1)), .01, .45))
    end
  end
end

-- Simulates slow heat changes and temperature-related health changes.
aquariumController.tickHeater = function(t)
  if not characterSettings or not aquariumWindow then return end
  local dt = aquariumController.lastTempTick > 0 and math.min(1.2, math.max(0,t-aquariumController.lastTempTick)) or 0
  aquariumController.lastTempTick=t
  if dt > 0 then
    aquariumController.zoneAmbient = aquariumController.getZoneAmbient()
    local equilibrium=aquariumController.zoneAmbient + (characterSettings.heaterPower or 0)*.33
    if not aquariumController.waterTemp then aquariumController.waterTemp=equilibrium end
    -- Smooth inertia: power/zone changes take time to affect the tank.
    -- About 95% of a new temperature target after 60 seconds.
    local approach = 1-math.exp(-dt * 0.05)
    aquariumController.waterTemp=aquariumController.waterTemp + (equilibrium-aquariumController.waterTemp)*approach
    aquariumController.tempVitality = aquariumController.tempVitality or aquariumController.fishVitality or 100
    local stress = aquariumController.waterTemp < 68 and (68-aquariumController.waterTemp) or (aquariumController.waterTemp > 83 and aquariumController.waterTemp-83 or 0)
    if stress > 0 then
      aquariumController.tempVitality=math.max(0,aquariumController.tempVitality-dt*stress*.095)
    else
      aquariumController.tempVitality=math.min(100,aquariumController.tempVitality+dt*.8)
    end
    aquariumController.hungerVitality = aquariumController.hungerVitality or (characterSettings.fishHunger or 100)
    aquariumController.fishVitality = math.min(aquariumController.tempVitality, aquariumController.hungerVitality)
    characterSettings.fishVitality=aquariumController.fishVitality
    characterSettings.fishHunger=aquariumController.hungerVitality
  end
  aquariumController.updateHeaterDisplay(t)
end

-- ============================================================================
-- Frame construction
-- Aquarium, heater, cast timer, welcome flow and options pages.
-- ============================================================================
-- Builds the aquarium window, controls, glass, water and heater.
local function buildChamber()
  aquariumWindow = ui(UIParent, characterSettings.width or 440, characterSettings.height or 310, 'CENTER', UIParent, characterSettings.x or 0, characterSettings.y or 0)
  aquariumWindow:SetFrameStrata('MEDIUM')
  backdrop(aquariumWindow, {0.48, 0.70, 0.67, 1}, {0.03, 0.10, 0.13, 0.94})
  aquariumController.themeFrames[aquariumWindow]='window'
  aquariumController.styleThemeFrame(aquariumWindow,'window')
  applyAlpha(aquariumWindow)

  aquariumWindow.header = aquariumWindow:CreateTexture(nil, 'BACKGROUND')
  aquariumWindow.header:SetColorTexture(0.22, 0.16, 0.08, 0.94)
  aquariumWindow.header:SetPoint('TOPLEFT', 2, -2)
  aquariumWindow.header:SetPoint('TOPRIGHT', -2, -2)
  aquariumWindow.header:SetHeight(52)

  aquariumWindow.trim = aquariumWindow:CreateTexture(nil, 'BORDER')
  aquariumWindow.trim:SetColorTexture(0.73, 0.58, 0.26, 0.35)
  aquariumWindow.trim:SetPoint('TOPLEFT', 8, -52)
  aquariumWindow.trim:SetPoint('TOPRIGHT', -8, -52)
  aquariumWindow.trim:SetHeight(2)
  aquariumWindow.footer=aquariumWindow:CreateTexture(nil,'BACKGROUND')
  aquariumWindow.footer:SetPoint('BOTTOMLEFT',aquariumWindow,'BOTTOMLEFT',3,3)
  aquariumWindow.footer:SetPoint('BOTTOMRIGHT',aquariumWindow,'BOTTOMRIGHT',-3,3)
  aquariumWindow.footer:SetHeight(87)
  aquariumWindow.footerLine=aquariumWindow:CreateTexture(nil,'BORDER')
  aquariumWindow.footerLine:SetPoint('BOTTOMLEFT',aquariumWindow,'BOTTOMLEFT',9,90)
  aquariumWindow.footerLine:SetPoint('BOTTOMRIGHT',aquariumWindow,'BOTTOMRIGHT',-9,90)
  aquariumWindow.footerLine:SetHeight(1)

  aquariumWindow.brandIcon=aquariumWindow:CreateTexture(nil,'ARTWORK')
  aquariumWindow.brandIcon:SetTexture('Interface\\Icons\\INV_Misc_Fish_02')
  aquariumWindow.brandIcon:SetTexCoord(.08,.92,.08,.92)
  aquariumWindow.brandIcon:SetSize(31,31)
  aquariumWindow.brandIcon:SetPoint('TOPLEFT',aquariumWindow,'TOPLEFT',13,-10)
  aquariumWindow.title = label(aquariumWindow, 'VIBE  /  AQUARIUM', 16, 52, -9, 0.98, 0.82, 0.49)
  aquariumWindow.status = label(aquariumWindow, '● FISHING MODE ACTIVE', 9, 53, -31, .46, .89, .79)
  aquariumWindow.hideButton=btn(aquariumWindow,'X',25,24,(characterSettings.width or 370)-35,-13,function()
    -- Closing the tank is independent of fishing mode; uncheck tank visibility.
    characterSettings.catchPanel=false
    if optionsWindow and optionsWindow.Refresh then optionsWindow:Refresh() end
    updateStatus()
  end)

  aquariumWindow.tank = ui(aquariumWindow, (characterSettings.width or 370) - 22, (characterSettings.height or 258) - 154, 'TOPLEFT', aquariumWindow, 11, -61)
  backdrop(aquariumWindow.tank, {.36, .65, .59, 1}, {.02, .11, .14, .95})
  aquariumController.themeFrames[aquariumWindow.tank]='glass'
  aquariumController.styleThemeFrame(aquariumWindow.tank,'glass')
  aquariumWindow.tankTop = aquariumWindow.tank:CreateTexture(nil, 'BACKGROUND')
  aquariumWindow.tankTop:SetPoint('TOPLEFT', 2, -2)
  aquariumWindow.tankTop:SetPoint('TOPRIGHT', -2, -2)
  aquariumWindow.tankTop:SetHeight(12)
  aquariumWindow.tankTop:SetColorTexture(1, 1, 1, 0.08)

  aquariumWindow.water = aquariumWindow.tank:CreateTexture(nil, 'BACKGROUND')
  aquariumWindow.water:SetPoint('TOPLEFT', 2, -14)
  aquariumWindow.water:SetPoint('BOTTOMRIGHT', -2, 2)
  aquariumWindow.water:SetColorTexture(0.02, 0.38, 0.43, 0.26)
  aquariumWindow.glassGlint=aquariumWindow.tank:CreateTexture(nil,'BORDER')
  aquariumWindow.glassGlint:SetPoint('TOPLEFT',aquariumWindow.tank,'TOPLEFT',10,-16)
  aquariumWindow.glassGlint:SetPoint('BOTTOMLEFT',aquariumWindow.tank,'BOTTOMLEFT',10,10)
  aquariumWindow.glassGlint:SetWidth(2)
  aquariumWindow.glassGlint:SetColorTexture(.83,1,1,.13)

  aquariumWindow.glow = aquariumWindow.tank:CreateTexture(nil, 'BORDER')
  aquariumWindow.glow:SetPoint('TOPLEFT', 8, -20)
  aquariumWindow.glow:SetPoint('TOPRIGHT', -8, -20)
  aquariumWindow.glow:SetHeight(18)
  aquariumWindow.glow:SetColorTexture(1, 1, 1, 0.04)

  aquariumWindow.lightShafts={}
  for i=1,4 do
    local ray=aquariumWindow.tank:CreateTexture(nil,'ARTWORK')
    ray:SetTexture('Interface\\Buttons\\WHITE8X8')
    ray:SetColorTexture(0.59,0.91,0.93,0.035)
    ray:SetWidth(7+i*4)
    ray:SetPoint('TOP',aquariumWindow.tank,'TOP',-120+i*48,-15)
    ray:SetPoint('BOTTOM',aquariumWindow.tank,'BOTTOM',-120+i*48,12)
    aquariumWindow.lightShafts[i]=ray
  end
  aquariumWindow.surfaceWave=aquariumWindow.tank:CreateTexture(nil,'OVERLAY')
  aquariumWindow.surfaceWave:SetTexture('Interface\\Buttons\\WHITE8X8')
  aquariumWindow.surfaceWave:SetColorTexture(0.66,0.98,0.99,0.16)
  aquariumWindow.surfaceWave:SetHeight(2)
  aquariumWindow.surfaceWave:SetPoint('TOPLEFT',aquariumWindow.tank,'TOPLEFT',3,-14)
  aquariumWindow.surfaceWave:SetPoint('TOPRIGHT',aquariumWindow.tank,'TOPRIGHT',-3,-14)
  aquariumWindow.waterLipLeft=aquariumWindow.tank:CreateTexture(nil,'OVERLAY')
  aquariumWindow.waterLipLeft:SetTexture('Interface\\Buttons\\WHITE8X8')
  aquariumWindow.waterLipLeft:SetColorTexture(.52,.94,1,.65)
  aquariumWindow.waterLipLeft:SetPoint('BOTTOMLEFT',aquariumWindow.tank,'TOPLEFT',0,-15)
  aquariumWindow.waterLipLeft:SetSize(25,2)
  aquariumWindow.waterLipRight=aquariumWindow.tank:CreateTexture(nil,'OVERLAY')
  aquariumWindow.waterLipRight:SetTexture('Interface\\Buttons\\WHITE8X8')
  aquariumWindow.waterLipRight:SetColorTexture(.52,.94,1,.65)
  aquariumWindow.waterLipRight:SetPoint('BOTTOMRIGHT',aquariumWindow.tank,'TOPRIGHT',0,-15)
  aquariumWindow.waterLipRight:SetSize(25,2)

  aquariumCanvas = ui(aquariumWindow.tank, aquariumWindow.tank:GetWidth() - 8, aquariumWindow.tank:GetHeight() - 18, 'BOTTOM', aquariumWindow.tank, 0, 3)
  aquariumCanvas:SetFrameLevel(aquariumWindow.tank:GetFrameLevel()+3)
  layoutSeaweed()
  makeAquariumDecor()

  aquariumWindow.value=label(aquariumWindow,'',11,(characterSettings.width or 370)-165,-(characterSettings.height or 258)+42,.98,.84,.52)
  aquariumWindow.value:Hide()

  aquariumWindow.count = label(aquariumWindow, 'SESSION CATCHES   0', 12, 15, -(characterSettings.height or 258) + 42, 0.95, 0.83, 0.55)
  aquariumWindow.resetButton = btn(aquariumWindow, 'RESET', 53, 21, (characterSettings.width or 370) - 96, -(characterSettings.height or 258) + 31, function()
    characterSettings.total = 0
    wipeTable(characterSettings.catches)
    wipeTable(characterSettings.residents)
    wipeTable(characterSettings.bagResidents)
    wipeTable(characterSettings.treasures)
    wipeTable(characterSettings.plants or {})
    wipeTable(characterSettings.deadFish or {})
    repopulateAquarium()
  end)
  aquariumWindow.settingsButton = btn(aquariumWindow, '', 25, 21, (characterSettings.width or 370) - 132, -(characterSettings.height or 258) + 31, function()
    optionsWindow:SetShown(not optionsWindow:IsShown())
  end)

  -- Compact, scrollable aquarium resident directory, docked outside the glass.
  aquariumWindow.rosterButton=btn(aquariumWindow,'>',25,21,(characterSettings.width or 370)-36,-(characterSettings.height or 258)+31,function()
    if not aquariumWindow.roster then return end
    aquariumWindow.roster:SetShown(not aquariumWindow.roster:IsShown())
    if not aquariumWindow.roster:IsShown() and aquariumController.clearJournalFlash then aquariumController.clearJournalFlash() end
    aquariumWindow.rosterButton.text:SetText(aquariumWindow.roster:IsShown() and '<' or '>')
    if aquariumWindow.roster:IsShown() and aquariumController.renderFishRoster then aquariumController.renderFishRoster() end
  end)
  aquariumWindow.roster=CreateFrame('Frame',nil,aquariumWindow,'BackdropTemplate')
  aquariumWindow.roster:SetSize(302,424)
  aquariumWindow.roster:SetFrameStrata('HIGH')
  aquariumWindow.roster:SetFrameLevel(aquariumWindow:GetFrameLevel()+18)
  backdrop(aquariumWindow.roster,{.58,.78,.69,1},{.025,.09,.11,.97})
  aquariumController.themeFrames[aquariumWindow.roster]='window'
  aquariumController.styleThemeFrame(aquariumWindow.roster,'window')
  aquariumWindow.roster:SetPoint('TOPLEFT',aquariumWindow,'TOPRIGHT',10,-13)
  aquariumWindow.roster.headBand=aquariumWindow.roster:CreateTexture(nil,'BACKGROUND')
  aquariumWindow.roster.headBand:SetPoint('TOPLEFT',3,-3)
  aquariumWindow.roster.headBand:SetPoint('TOPRIGHT',-3,-3)
  aquariumWindow.roster.headBand:SetHeight(76)
  aquariumWindow.roster.scrollAccent=aquariumWindow.roster:CreateTexture(nil,'BORDER')
  aquariumWindow.roster.scrollAccent:SetPoint('TOPLEFT',aquariumWindow.roster,'TOPLEFT',14,-79)
  aquariumWindow.roster.scrollAccent:SetPoint('TOPRIGHT',aquariumWindow.roster,'TOPRIGHT',-14,-79)
  aquariumWindow.roster.scrollAccent:SetHeight(2)
  aquariumWindow.roster.header=label(aquariumWindow.roster,'YOUR FISH COLLECTION',14,15,-14,.95,.81,.48)
  aquariumWindow.roster.header:SetWidth(178)
  aquariumWindow.roster.subtitle=label(aquariumWindow.roster,'Hover to find a fish in the tank',10,15,-57,.68,.89,.86)
  aquariumWindow.roster.subtitle:SetWidth(255)
  aquariumWindow.roster.list=CreateFrame('ScrollFrame',nil,aquariumWindow.roster,'UIPanelScrollFrameTemplate')
  aquariumWindow.roster.list:SetPoint('TOPLEFT',aquariumWindow.roster,'TOPLEFT',12,-93)
  aquariumWindow.roster.list:SetPoint('BOTTOMRIGHT',aquariumWindow.roster,'BOTTOMRIGHT',-29,12)
  aquariumWindow.roster.content=CreateFrame('Frame',nil,aquariumWindow.roster.list)
  aquariumWindow.roster.content:SetSize(258,1)
  aquariumWindow.roster.list:SetScrollChild(aquariumWindow.roster.content)
  aquariumWindow.roster.rows={}
  aquariumWindow.roster:Hide()
  aquariumWindow.roster.showJournal=false
  local journalToggle=btn(aquariumWindow.roster,'JOURNAL',92,26,195,-12,function()
    local panel=aquariumWindow.roster
    panel.showJournal=not panel.showJournal
    if aquariumController.clearJournalFlash then aquariumController.clearJournalFlash() end
    aquariumController.renderFishRoster()
  end)
  aquariumWindow.roster.journalToggle=journalToggle

  -- Select one visible resident, using UID for fish rows or species for journal rows.
  aquariumController.flashJournalFish = function(species, uid)
    local previous = aquariumController.highlightFishFrame
    if previous and previous.icon then previous.icon:SetAlpha(1) end
    aquariumController.highlightFishFrame = nil
    if not aquariumWindow or not aquariumWindow:IsShown() then return end
    local candidate
    for _, fish in ipairs(swimmingFish) do
      if uid and fish.uid == uid then
        candidate = fish
        break
      elseif not uid and species and fish.species == species then
        if not candidate or (candidate.deadState and not fish.deadState) then candidate = fish end
        if candidate and not candidate.deadState then break end
      end
    end
    if candidate and candidate:IsShown() and candidate.icon then
      aquariumController.highlightFishFrame = candidate
    end
  end

  -- Restore icon opacity when the highlight ends.
  aquariumController.clearJournalFlash = function()
    local fish = aquariumController.highlightFishFrame
    if fish and fish.icon then fish.icon:SetAlpha(1) end
    aquariumController.highlightFishFrame = nil
  end

  -- Highlight a displayed fish matching the encyclopedia species row.
  local function showJournalSpeciesHighlight(self)
    local p=aquariumController.currentTheme()
    self.bg:SetColorTexture(unpack(p.hover))
    if self.journalSpeciesID then aquariumController.flashJournalFish(self.journalSpeciesID) end
  end

  local function hideJournalSpeciesHighlight(self)
    local p=aquariumController.currentTheme()
    self.bg:SetColorTexture(p.button[1],p.button[2],p.button[3],(self.index or 1)%2==0 and .82 or .58)
    aquariumController.clearJournalFlash()
  end

  local function showResidentTooltip(self)
          local fish=self.fish
          if not fish then return end
          local p=aquariumController.currentTheme()
    self.bg:SetColorTexture(unpack(p.hover))
          aquariumController.flashJournalFish(fish.species, fish.uid)
          local itemName=select(1,GetItemInfo(fish.species)) or 'Unknown Fish'
          local timestamp=GetTime and GetTime() or now
          local hunger=clamp(100-(timestamp-(fish.lastFed or timestamp))/36,0,100)
          local happiness=fish.deadState and 0 or math.min(aquariumController.tempVitality or 100,hunger)
          local cookable = cookingIngredients[fish.species] or (characterSettings.cookableReagents and characterSettings.cookableReagents[fish.species])
          GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
          GameTooltip:AddLine(fish.petName or 'Unnamed Fish',1,.82,.4)
          GameTooltip:AddLine(itemName,.69,.94,.93)
          GameTooltip:AddLine('Resident ID: '..tostring(fish.uid or 'unknown'),.54,.78,.80)
          local rarity=fish.rarity or 1
          GameTooltip:AddLine('Rarity: '..aquariumController.fishRarityNames[rarity]..'  |  Variant: '..aquariumController.fishVariantNames[fish.variant or 1],.95,.79,.55)
          GameTooltip:AddLine('Personality: '..aquariumController.fishPersonalityNames[fish.personality or 1]..'  |  Stage: '..tostring(fish.lifeStage or 'adult'),.75,.92,.89)
          GameTooltip:AddLine(('Happiness: %d%%'):format(math.floor(happiness+.5)),.94,.94,.84)
          GameTooltip:AddLine(('Hunger (fullness): %d%%'):format(math.floor(hunger+.5)),.94,.94,.84)
          if fish.deadState then
            GameTooltip:AddLine(fish.deadState=='skeleton' and 'Status: Skeleton' or 'Status: Deceased',1,.45,.45)
            if fish.deathCause then GameTooltip:AddLine('Cause of death: '..fish.deathCause,1,.74,.55) end
          elseif hunger<25 then
            GameTooltip:AddLine('Status: Very hungry; looking for food',1,.65,.35)
          else
            GameTooltip:AddLine('Status: Swimming around the aquarium',.64,.96,.7)
          end
          local descriptions={
            'Curious and adventurous, often exploring beyond its usual school.',
            'A social swimmer that prefers familiar neighbors and steady water.',
            'A determined little forager with an impressive appetite.',
            'Generally peaceful, though sometimes startled by a big splash.',
            'Loves drifting past the seaweed and investigating the tank floor.',
            'An energetic swimmer that likes the warm glow of the heater.',
          }
          local description=descriptions[math.floor((fish.schoolIndex or 1)%#descriptions)+1]
          GameTooltip:AddLine('Description: '..itemName..'. '..description,.73,.83,.85,true)
          if cookable then
            GameTooltip:AddLine('Cooking: Known recipe uses this fish',.48,.96,.57)
          else
            GameTooltip:AddLine('Cooking: No known recipe detected',.87,.75,.49)
          end
          if not cookingRecipesReady then GameTooltip:AddLine('Open Cooking and scan recipes for updated results.',.65,.75,.85,true) end
          GameTooltip:Show()
  end
  local function hideResidentTooltip(self)
          local p=aquariumController.currentTheme()
    self.bg:SetColorTexture(p.button[1],p.button[2],p.button[3],self.index%2==0 and .82 or .58)
          aquariumController.clearJournalFlash()
          GameTooltip:Hide()
  end

  aquariumController.renderFishRoster=function()
    if not aquariumWindow or not aquariumWindow.roster then return end
    local panel=aquariumWindow.roster
    local content=panel.content
    if panel.showJournal then
      local journal=characterSettings.catchJournal
      local rows={}
      local speciesByRow={}
      local speciesRarityByRow={}
      local speciesCount=aquariumController.journalSpeciesCount()
      rows[#rows+1]='|cff6ee3e8DISCOVERIES|r    '..speciesCount..' species / '..(journal.totalCaught or 0)..' catches'
      rows[#rows+1]='Best rarity: '..aquariumController.fishRarityNames[journal.rarestQuality or 1]
      rows[#rows+1]='|cff6ee3e8ACHIEVEMENTS|r'
      for _,milestone in ipairs(aquariumController.fishMilestones) do
        local unlocked=journal.achievements[milestone.key]
        rows[#rows+1]=(unlocked and '|cff58e49a[+]|r ' or '|cff7b8585[-]|r ')..milestone.name
      end
      rows[#rows+1]='|cff6ee3e8SPECIES INDEX|r'
      local species={}
      for id,entry in pairs(journal.species) do
        species[#species+1]={id=tonumber(id),entry=entry}
      end
      table.sort(species,function(a,b) return (a.id or 0)<(b.id or 0) end)
      for _,discovery in ipairs(species) do
        local entry=discovery.entry
        local name=select(1,GetItemInfo(discovery.id)) or ('Fish #'..tostring(discovery.id))
        rows[#rows+1]=name..'  x'..(entry.caught or 0)..'  ['..aquariumController.fishRarityNames[entry.bestRarity or 1]..']'
        speciesByRow[#rows]=discovery.id
        speciesRarityByRow[#rows]=entry.bestRarity or 1
      end
      content:SetHeight(math.max(1,#rows*29+3))
      panel.header:SetText('AQUARIUM JOURNAL')
      panel.subtitle:SetText('Discovery history survives aquarium RESET')
      journalToggle.text:SetText('FISH')
      for i,labelText in ipairs(rows) do
        local row=panel.rows[i]
        if not row then
          row=CreateFrame('Button',nil,content)
          row:SetSize(254,28)
          row.bg=row:CreateTexture(nil,'BACKGROUND')
          row.bg:SetAllPoints()
          row.name=row:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
          row.name:SetPoint('LEFT',6,0)
          row.name:SetWidth(237)
          row.name:SetJustifyH('LEFT')
          panel.rows[i]=row
        end
        if not row.rarityStripe then
          row.rarityStripe=row:CreateTexture(nil,'ARTWORK')
          row.rarityStripe:SetPoint('TOPLEFT',row,'TOPLEFT',1,-2)
          row.rarityStripe:SetPoint('BOTTOMLEFT',row,'BOTTOMLEFT',1,2)
          row.rarityStripe:SetWidth(3)
        end
        local stripeColor=aquariumController.rarityAccentRGB[speciesRarityByRow[i] or 1]
        row.rarityStripe:SetColorTexture(stripeColor[1],stripeColor[2],stripeColor[3],.93)
        row.rarityStripe:SetShown(not not speciesByRow[i])
        row.fish=nil
        row.journalSpeciesID=speciesByRow[i]
        row.index=i
        row:SetScript('OnEnter',showJournalSpeciesHighlight)
        row:SetScript('OnLeave',hideJournalSpeciesHighlight)
        if row.icon then row.icon:Hide() end
        row.name:ClearAllPoints()
        row.name:SetPoint('LEFT',row,'LEFT',9,0)
        row.name:SetWidth(238)
        row.name:SetText(labelText)
        local p=aquariumController.currentTheme()
        row.bg:SetColorTexture(p.button[1],p.button[2],p.button[3],i%2==0 and .82 or .58)
        row:ClearAllPoints()
        row:SetPoint('TOPLEFT',content,'TOPLEFT',0,-(i-1)*29)
        row:SetShown(true)
      end
      for i=#rows+1,#panel.rows do panel.rows[i]:Hide();panel.rows[i].fish=nil;panel.rows[i].journalSpeciesID=nil end
      return
    end
    journalToggle.text:SetText('JOURNAL')
    local count=#swimmingFish
    content:SetHeight(math.max(1,count*29+3))
    panel.header:SetText(('FISH COLLECTION  (%d)'):format(count))
    if count==0 then panel.subtitle:SetText('No fish in the aquarium')
    else panel.subtitle:SetText('Hover for happiness, hunger and cooking') end
    for i,f in ipairs(swimmingFish) do
      local row=panel.rows[i]
      if not row then
        row=CreateFrame('Button',nil,content)
        row:SetSize(254,28)
        row.bg=row:CreateTexture(nil,'BACKGROUND')
        row.bg:SetAllPoints()
        row.bg:SetTexture('Interface\\Buttons\\WHITE8X8')
        row.icon=row:CreateTexture(nil,'ARTWORK')
        row.icon:SetSize(22,22)
        row.icon:SetPoint('LEFT',4,0)
        row.icon:SetTexCoord(.08,.92,.08,.92)
        row.name=row:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
        row.name:SetPoint('LEFT',row.icon,'RIGHT',7,0)
        row.name:SetWidth(208)
        row.name:SetJustifyH('LEFT')
        panel.rows[i]=row
      end
      if not row.icon then
        row.icon=row:CreateTexture(nil,'ARTWORK')
        row.icon:SetSize(22,22)
        row.icon:SetPoint('LEFT',4,0)
        row.icon:SetTexCoord(.08,.92,.08,.92)
      end
      row.icon:Show()
      row.name:ClearAllPoints()
      row.name:SetPoint('LEFT',row.icon,'RIGHT',7,0)
      row.name:SetWidth(208)
      row:SetScript('OnEnter',showResidentTooltip)
      row:SetScript('OnLeave',hideResidentTooltip)
      row.journalSpeciesID=nil
      row.index=i
      row.fish=f
      row:ClearAllPoints()
      row:SetPoint('TOPLEFT',content,'TOPLEFT',0,-(i-1)*29)
      local p=aquariumController.currentTheme()
      row.bg:SetColorTexture(p.button[1],p.button[2],p.button[3],i%2==0 and .82 or .58)
      row.icon:SetTexture(f.deadState=='skeleton' and 'Interface\\Icons\\INV_Misc_Bone_ElfSkull_01' or f.baseIcon)
      if not row.rarityStripe then
        row.rarityStripe=row:CreateTexture(nil,'ARTWORK')
        row.rarityStripe:SetPoint('TOPLEFT',row,'TOPLEFT',1,-2)
        row.rarityStripe:SetPoint('BOTTOMLEFT',row,'BOTTOMLEFT',1,2)
        row.rarityStripe:SetWidth(3)
      end
      local stripeColor=aquariumController.rarityAccentRGB[f.rarity or 1] or aquariumController.rarityAccentRGB[1]
      row.rarityStripe:SetColorTexture(stripeColor[1],stripeColor[2],stripeColor[3],.93)
      row.rarityStripe:Show()
      local itemName=select(1,GetItemInfo(f.species)) or 'Fish'
      local color=aquariumController.fishRarityColors[f.rarity or 1] or aquariumController.fishRarityColors[1]
      row.name:SetText(color..(f.petName or 'Unnamed Fish')..'|r  |cff819c9a('..itemName..')|r')
      row:SetShown(true)
    end
    for i = count + 1, #panel.rows do
    panel.rows[i]:Hide()
    panel.rows[i].fish = nil
  end
  end

  -- Use an icon texture instead of a font-dependent gear character.
  local gear = aquariumWindow.settingsButton:CreateTexture(nil,'OVERLAY')
  gear:SetSize(16,16)
  gear:SetPoint('CENTER')
  gear:SetTexture('Interface\\Icons\\INV_Gizmo_02')
  aquariumWindow.feedButton=btn(aquariumWindow,'FEED',48,21,(characterSettings.width or 370)-188,-(characterSettings.height or 258)+75,feedAquarium)
  -- Detailed aquarium immersion heater with an independently pulsing heating coil.
  -- Both texture layers are centered on the same scalable frame.
  aquariumController.heater = CreateFrame('Frame', nil, aquariumWindow.tank)
  aquariumController.heater:SetSize(56,132)
  -- The heater must remain behind aquarium fish, regardless of draw layer.
  aquariumController.heater:SetFrameLevel(aquariumWindow.tank:GetFrameLevel()+1)
  -- Wide additive light spill is separate from the photographic shell.
  aquariumController.heater.auraOuter=aquariumController.heater:CreateTexture(nil,'BACKGROUND')
  aquariumController.heater.auraOuter:SetTexture('Interface\\AddOns\\VibeFishin\\Media\\HeaterAura.tga')
  aquariumController.heater.auraOuter:SetBlendMode('ADD')
  aquariumController.heater.auraOuter:SetPoint('CENTER',aquariumController.heater,'CENTER',0,-6)
  aquariumController.heater.auraOuter:SetSize(150,210)
  aquariumController.heater.aura=aquariumController.heater:CreateTexture(nil,'BORDER')
  aquariumController.heater.aura:SetTexture('Interface\\AddOns\\VibeFishin\\Media\\HeaterAura.tga')
  aquariumController.heater.aura:SetBlendMode('ADD')
  aquariumController.heater.aura:SetPoint('CENTER',aquariumController.heater,'CENTER',0,-5)
  aquariumController.heater.aura:SetSize(102,163)
  aquariumController.heater.shell=aquariumController.heater:CreateTexture(nil,'ARTWORK')
  aquariumController.heater.shell:SetTexture('Interface\\AddOns\\VibeFishin\\Media\\AquariumHeater.tga')
  aquariumController.heater.shell:SetAllPoints(aquariumController.heater)
  aquariumController.heater.glow=aquariumController.heater:CreateTexture(nil,'OVERLAY')
  aquariumController.heater.glow:SetTexture('Interface\\AddOns\\VibeFishin\\Media\\AquariumHeaterGlow.tga')
  aquariumController.heater.glow:SetAllPoints(aquariumController.heater)
  aquariumController.heater.glow:SetBlendMode('ADD')
  aquariumController.heater.indicator=aquariumController.heater:CreateTexture(nil,'OVERLAY')
  aquariumController.heater.indicator:SetTexture('Interface\\Buttons\\WHITE8X8')
  aquariumController.heater.indicator:SetColorTexture(1,.6,.16,.85)
  aquariumController.heater.indicator:SetPoint('TOP',aquariumController.heater,'TOP',0,-22)
  aquariumController.heater.indicator:SetSize(2.5,4)
  aquariumController.tempWidget=CreateFrame('Frame',nil,aquariumWindow,'BackdropTemplate')
  aquariumController.tempWidget:SetSize(166,36)
  backdrop(aquariumController.tempWidget,{.33,.59,.53,.8},{.028,.10,.13,.83})
  aquariumController.themeFrames[aquariumController.tempWidget]='button'
  aquariumController.tempWidget.readout=label(aquariumController.tempWidget,'',11,48,-4,1,.78,.43)
  aquariumController.tempWidget.state=label(aquariumController.tempWidget,'',8,48,-18,.42,.9,.48)
  aquariumController.tempWidget.state:SetWidth(51)
  aquariumController.tempWidget.vitality=label(aquariumController.tempWidget,'',8,99,-18,.75,.86,.85)
  aquariumController.tempWidget.vitality:SetWidth(63)
  aquariumController.tempWidget.vitality:SetJustifyH('RIGHT')
  aquariumController.tempWidget.minus=btn(aquariumController.tempWidget,'-',21,21,0,-2,function()
    characterSettings.heaterPower=clamp((characterSettings.heaterPower or 0)-10,0,100)
    aquariumController.updateHeaterDisplay(GetTime and GetTime() or now)
  end)
  aquariumController.tempWidget.plus=btn(aquariumController.tempWidget,'+',21,21,24,-2,function()
    characterSettings.heaterPower=clamp((characterSettings.heaterPower or 0)+10,0,100)
    aquariumController.updateHeaterDisplay(GetTime and GetTime() or now)
  end)
  aquariumController.updateHeaterDisplay(GetTime and GetTime() or now)
  aquariumWindow.closeButton = nil

  function aquariumWindow:RefreshLayout()
    self:SetSize(characterSettings.width or 370, characterSettings.height or 258)
    if self.header then self.header:SetHeight(52) end
    if self.hideButton then
      self.hideButton:ClearAllPoints()
      self.hideButton:SetPoint('TOPLEFT',self,'TOPLEFT',(characterSettings.width or 370)-35,-13)
    end
    if self.tank then
      self.tank:ClearAllPoints()
      self.tank:SetPoint('TOPLEFT', self, 'TOPLEFT', 11, -61)
      self.tank:SetSize((characterSettings.width or 370) - 22, (characterSettings.height or 258) - 154)
    end
    if aquariumCanvas then
      aquariumCanvas:SetSize(self.tank:GetWidth() - 8, self.tank:GetHeight() - 18)
      layoutSeaweed()
      makeAquariumDecor()
    end
    if self.value then
      self.value:ClearAllPoints()
      self.value:SetPoint('RIGHT',self,'BOTTOMRIGHT',-15,29)
      self.value:SetJustifyH('RIGHT')
    end
    if self.count then
      self.count:ClearAllPoints()
      self.count:SetPoint('BOTTOMLEFT',self,'BOTTOMLEFT',15,29)
    end
    if self.resetButton then
      self.resetButton:ClearAllPoints()
      self.resetButton:SetPoint('TOPRIGHT',self,'BOTTOMRIGHT',-51,75)
    end
    if self.rosterButton then
      self.rosterButton:ClearAllPoints()
      self.rosterButton:SetPoint('TOPRIGHT',self,'BOTTOMRIGHT',-12,75)
    end
    if self.roster then
      self.roster:ClearAllPoints()
      self.roster:SetPoint('TOPLEFT',self,'TOPRIGHT',10,-13)
      local screenRight=UIParent:GetRight() or 0
      local tankRight=self:GetRight() or 0
      if tankRight+316>screenRight then
        self.roster:ClearAllPoints()
        self.roster:SetPoint('TOPRIGHT',self,'TOPLEFT',-10,-13)
      end
    end
    if self.settingsButton then
      self.settingsButton:ClearAllPoints()
      self.settingsButton:SetPoint('TOPRIGHT',self,'BOTTOMRIGHT',-118,75)
    end
    if self.feedButton then
      self.feedButton:ClearAllPoints()
      self.feedButton:SetPoint('TOPRIGHT',self,'BOTTOMRIGHT',-156,75)
    end
    if aquariumController.heater and self.tank then
      local h = self.tank:GetHeight()
      local heaterH = clamp(h * .78, 98, 188)
      aquariumController.heater:SetSize(heaterH * .47, heaterH)
      if aquariumController.heater.aura then aquariumController.heater.aura:SetSize(heaterH * .78, heaterH * 1.1) end
      if aquariumController.heater.auraOuter then aquariumController.heater.auraOuter:SetSize(heaterH * 1.23, heaterH * 1.42) end
      aquariumController.heater:ClearAllPoints()
      aquariumController.heater:SetPoint('TOP',self.tank,'TOPLEFT',self.tank:GetWidth() * .78,-5)
    end
    if aquariumController.tempWidget then
      aquariumController.tempWidget:ClearAllPoints()
      aquariumController.tempWidget:SetPoint('TOPLEFT',self,'BOTTOMLEFT',12,76)
    end
    repopulateAquarium()
  end

  makeMovable(aquariumWindow, 'x', 'y')
  addResizer(aquariumWindow)
  aquariumWindow:RefreshLayout()
end

-- Builds the pole-and-bobber fishing cast countdown widget.
local function buildIndicator()
  castTimerWindow = ui(UIParent, 228, 116, 'CENTER', UIParent, characterSettings.timerX or 0, characterSettings.timerY or 0)
  castTimerWindow:SetFrameStrata('HIGH')
  castTimerWindow:SetScale(characterSettings.timerScale or 1)

  -- Transparent cast timer: render only the bobber, rod and countdown.

  castTimerWindow.caption = label(castTimerWindow, 'CAST WATCH', 10, 12, -14, .95, .82, .55)
  castTimerWindow.clock = label(castTimerWindow, '0.0s', 15, 176, -13, .93, .99, .95)
  castTimerWindow.sub = label(castTimerWindow, 'watch the bobber', 10, 12, -95, .67, .88, .85)

  castTimerWindow.pole = castTimerWindow:CreateTexture(nil, 'ARTWORK')
  castTimerWindow.pole:SetTexture('Interface\\Icons\\INV_Fishingpole_02')
  castTimerWindow.pole:SetTexCoord(.08,.92,.08,.92)
  castTimerWindow.pole:SetSize(34,34)
  castTimerWindow.pole:SetPoint('LEFT', castTimerWindow, 'LEFT', 18, 0)

  castTimerWindow.line = castTimerWindow:CreateTexture(nil, 'ARTWORK')
  castTimerWindow.line:SetTexture('Interface\\Buttons\\WHITE8X8')
  castTimerWindow.line:SetColorTexture(.88,.96,1,.85)
  castTimerWindow.line:SetSize(90, 2)
  castTimerWindow.line:SetPoint('LEFT', castTimerWindow.pole, 'RIGHT', 2, 0)

  castTimerWindow.lineGuide = castTimerWindow:CreateTexture(nil, 'BACKGROUND')
  castTimerWindow.lineGuide:SetTexture('Interface\\Buttons\\WHITE8X8')
  castTimerWindow.lineGuide:SetColorTexture(.36,.58,.64,.28)
  castTimerWindow.lineGuide:SetSize(95, 1)
  castTimerWindow.lineGuide:SetPoint('LEFT', castTimerWindow.pole, 'RIGHT', 2, 0)

  castTimerWindow.bobberAnchor = CreateFrame('Frame', nil, castTimerWindow)
  castTimerWindow.bobberAnchor:SetSize(40,40)
  castTimerWindow.bobberAnchor:SetPoint('LEFT', castTimerWindow, 'LEFT', 138, -2)

  castTimerWindow.ripples = {}
  for i=1,3 do
    local r = castTimerWindow:CreateTexture(nil, 'BACKGROUND')
    r:SetTexture('Interface\\Buttons\\WHITE8X8')
    r:SetColorTexture(.46,.86,1, .25 - i*0.04)
    castTimerWindow.ripples[i] = r
  end

  -- Surface line follows the bobber anchor so it moves with each cast.
  castTimerWindow.waterlineShadow = castTimerWindow:CreateTexture(nil, 'ARTWORK')
  castTimerWindow.waterlineShadow:SetColorTexture(.02, .20, .28, .6)
  castTimerWindow.waterlineShadow:SetSize(40, 3)
  castTimerWindow.waterlineShadow:SetPoint('CENTER', castTimerWindow.bobberAnchor, 'CENTER', 0, -6)
  castTimerWindow.waterline = castTimerWindow:CreateTexture(nil, 'OVERLAY')
  castTimerWindow.waterline:SetColorTexture(.36, .91, 1, .95)
  castTimerWindow.waterline:SetSize(38, 2)
  castTimerWindow.waterline:SetPoint('CENTER', castTimerWindow.bobberAnchor, 'CENTER', 0, -5)
  castTimerWindow.bobberShadow = castTimerWindow:CreateTexture(nil, 'ARTWORK')
  castTimerWindow.bobberShadow:SetTexture('Interface\\Buttons\\WHITE8X8')
  castTimerWindow.bobberShadow:SetColorTexture(0,0,0,.22)
  castTimerWindow.bobberShadow:SetSize(20,5)
  castTimerWindow.bobberShadow:SetPoint('CENTER', castTimerWindow.bobberAnchor, 'CENTER', 0, -13)

  castTimerWindow.bobberBottom = castTimerWindow:CreateTexture(nil, 'ARTWORK')
  castTimerWindow.bobberBottom:SetTexture('Interface\\Buttons\\WHITE8X8')
  castTimerWindow.bobberBottom:SetColorTexture(.98,.98,1, .98)
  castTimerWindow.bobberBottom:SetSize(12,16)
  castTimerWindow.bobberBottom:SetPoint('CENTER', castTimerWindow.bobberAnchor, 'CENTER', 0, -1)

  castTimerWindow.bobberTop = castTimerWindow:CreateTexture(nil, 'OVERLAY')
  castTimerWindow.bobberTop:SetTexture('Interface\\Buttons\\WHITE8X8')
  castTimerWindow.bobberTop:SetColorTexture(.94,.27,.22, .98)
  castTimerWindow.bobberTop:SetSize(12,8)
  castTimerWindow.bobberTop:SetPoint('BOTTOM', castTimerWindow.bobberBottom, 'TOP', 0, -3)

  castTimerWindow.bobberTip = castTimerWindow:CreateTexture(nil, 'OVERLAY')
  castTimerWindow.bobberTip:SetTexture('Interface\\Buttons\\WHITE8X8')
  castTimerWindow.bobberTip:SetColorTexture(1,.86,.35,.9)
  castTimerWindow.bobberTip:SetSize(4,4)
  castTimerWindow.bobberTip:SetPoint('BOTTOM', castTimerWindow.bobberTop, 'TOP', 0, -1)

  castTimerWindow.ringTicks = {}
  for i=1,28 do
    local t = castTimerWindow:CreateTexture(nil, 'OVERLAY')
    t:SetTexture('Interface\\Buttons\\WHITE8X8')
    t:SetSize(3,7)
    t:SetColorTexture(.40,.95,.92,.88)
    castTimerWindow.ringTicks[i] = t
  end

  makeMovable(castTimerWindow, 'timerX', 'timerY')
  castTimerWindow:Hide()
  applyThemeOpacity()
end

-- Creates the player-clickable fishing-mode action bar macro.
local function createMacro()
  if InCombatLockdown and InCombatLockdown() then say('Create the macro after combat.') return end
  if not CreateMacro or not PickupMacro then say('Macro API unavailable. Create a macro manually with /vfish toggle.') return end
  local index = GetMacroIndexByName and GetMacroIndexByName('VibeFishin')
  if not index or index == 0 then
    local ok, val = pcall(CreateMacro, 'VibeFishin', 'INV_Misc_Fish_02', '/vfish toggle', true)
    if ok then index = val end
  end
  if index and index > 0 then
    PickupMacro(index)
    say('Macro on cursor. Drop it on your hotbar!')
  else
    say('Could not create macro (macro slots may be full). Create /vfish toggle manually.')
  end
end

-- Creates the first-run introduction and onboarding controls.
local function buildWelcome()
  welcome = ui(UIParent, 468, 336, 'CENTER', UIParent, 0, 45)
  welcome:SetFrameStrata('DIALOG')
  backdrop(welcome, {.73, .59, .31, 1}, {.03, .12, .14, .98})

  local head = welcome:CreateTexture(nil, 'BACKGROUND')
  head:SetColorTexture(.15, .31, .31, .94)
  head:SetPoint('TOPLEFT', 2, -2)
  head:SetPoint('TOPRIGHT', -2, -2)
  head:SetHeight(94)
  welcome.head=head

  local wave = welcome:CreateTexture(nil, 'ARTWORK')
  wave:SetPoint('TOPLEFT', 18, -74)
  wave:SetPoint('TOPRIGHT', -18, -74)
  wave:SetHeight(18)
  wave:SetColorTexture(0.18, 0.56, 0.60, 0.25)

  label(welcome, '✦  W E L C O M E   A B O A R D', 12, 28, -22, .97, .76, .42)
  label(welcome, 'VibeFishin', 30, 28, -48, .79, 1, .87)
  label(welcome, 'A little tranquility, one cast at a time.', 13, 28, -115, .8, .9, .86)
  label(welcome, 'Create your fishing-mode button:', 13, 28, -151, .98, .83, .58)

  local b = btn(welcome, '', 70, 70, 28, -179, createMacro)
  local ic = b:CreateTexture(nil, 'ARTWORK')
  ic:SetPoint('CENTER')
  ic:SetSize(56, 56)
  ic:SetTexture('Interface\\Icons\\INV_Misc_Fish_02')

  label(welcome, 'CLICK TO PICK UP MACRO', 12, 114, -188, .92, .96, .82)
  label(welcome, 'Drop it onto any action bar slot.', 11, 114, -211, .66, .82, .81)
  label(welcome, 'Use that button to toggle fishing mode on and off.', 11, 114, -232, .66, .82, .81)
  label(welcome, 'Keep the normal Fishing spell on another button for casting.', 11, 114, -253, .66, .82, .81)

  btn(welcome, 'LET’S GO FISHING', 176, 31, 247, -286, function()
    characterSettings.welcome = true
    welcome:Hide()
    startFishing(false)
  end)
  btn(welcome, 'LATER', 82, 31, 153, -286, function()
    characterSettings.welcome = true
    welcome:Hide()
  end)
end

-- Builds and wires the options window and its settings tabs.
local function buildSettings()
  optionsWindow = ui(UIParent, 454, 620, 'CENTER', UIParent, characterSettings.settingsX or 0, characterSettings.settingsY or 18)
  optionsWindow:SetFrameStrata('DIALOG')
  backdrop(optionsWindow,{.55,.73,.69,1},{.025,.10,.13,.97})
  aquariumController.themeFrames[optionsWindow]='window'
  applyAlpha(optionsWindow)
  local head=optionsWindow:CreateTexture(nil,'BACKGROUND')
  head:SetPoint('TOPLEFT',2,-2)
  head:SetPoint('TOPRIGHT',-2,-2)
  head:SetHeight(43)
  head:SetColorTexture(.15,.26,.28,.98)
  optionsWindow.head=head
  optionsWindow.headerRule=optionsWindow:CreateTexture(nil,'BORDER')
  optionsWindow.headerRule:SetPoint('TOPLEFT',optionsWindow,'TOPLEFT',10,-45)
  optionsWindow.headerRule:SetPoint('TOPRIGHT',optionsWindow,'TOPRIGHT',-10,-45)
  optionsWindow.headerRule:SetHeight(2)
  local dragHandle = CreateFrame('Frame', nil, optionsWindow)
  dragHandle:SetPoint('TOPLEFT', optionsWindow, 'TOPLEFT', 4, -4)
  dragHandle:SetSize(398, 37)
  dragHandle:EnableMouse(true)
  dragHandle:RegisterForDrag('LeftButton')
  dragHandle:SetScript('OnDragStart', function() optionsWindow:SetMovable(true); optionsWindow:StartMoving() end)
  dragHandle:SetScript('OnDragStop', function()
    optionsWindow:StopMovingOrSizing()
    local cx, cy = optionsWindow:GetCenter()
    local px, py = UIParent:GetCenter()
    if cx and px then characterSettings.settingsX, characterSettings.settingsY = cx-px, cy-py end
  end)
  local heading=label(optionsWindow,'VIBE  /  SETTINGS',18,19,-14,.98,.85,.57)
  optionsWindow.heading=heading
  label(optionsWindow,'DRAG HEADER TO MOVE',9,268,-20,.49,.78,.73)
  btn(optionsWindow,'×',26,24,416,-11,function()optionsWindow:Hide() end)

  optionsWindow.checks = {}
  optionsWindow.sliders = {}
  optionsWindow.pages = {}
  optionsWindow.tabs = {}
  local names = {'Fishing', 'Aquarium', 'Cinematics', 'Display', 'Performance', 'Theme'}
  local descriptions = {
    'Pole reminders, bait and player actions',
    'Your aquarium, fish behavior and layout',
    'Catch reveals, splash effects and cast timer',
    'Value sources and HUD presentation',
    'Animation update rates and lower-power aquarium mode',
    'Select an aquarium-wide interface and window style',
  }
  local function makePage(index)
    local frame=CreateFrame('Frame',nil,optionsWindow)
    frame:SetPoint('TOPLEFT',optionsWindow,'TOPLEFT',13,-150)
    frame:SetPoint('BOTTOMRIGHT',optionsWindow,'BOTTOMRIGHT',-13,52)
    local cap=label(frame,descriptions[index],11,12,-7,.60,.84,.84)
    frame:Hide()
    optionsWindow.pages[index]=frame
    return frame
  end
  local function activatePage(index)
    optionsWindow.activePage = index
    for i, page in ipairs(optionsWindow.pages) do page:SetShown(i==index) end
    local palette=aquariumController.currentTheme()
    for i, tab in ipairs(optionsWindow.tabs) do
      aquariumController.styleThemeFrame(tab,'button')
      if not palette.blizzard then tab:SetBackdropColor(unpack(i==index and palette.hover or palette.button)) end
      tab:SetBackdropBorderColor(unpack(i==index and palette.accent or palette.border))
      if tab.text then tab.text:SetTextColor(unpack(i==index and palette.accent or palette.text)) end
    end
  end
  optionsWindow.activatePage=activatePage
  for i,name in ipairs(names) do
    local col=(i-1)%3
    local row=math.floor((i-1)/3)
    local tab=btn(optionsWindow,name,137,28,13+col*141,-54-row*34,function()activatePage(i) end)
    tab:SetScript('OnLeave',function() activatePage(optionsWindow.activePage or 1) end)
    optionsWindow.tabs[i]=tab
    makePage(i)
  end

  local function section(page,name,y)
    local strip=page:CreateTexture(nil,'BACKGROUND')
    strip:SetColorTexture(.18,.34,.36,.35)
    aquariumController.themeAccentTextures[strip]=true
    strip:SetPoint('TOPLEFT',page,'TOPLEFT',7,y+2)
    strip:SetPoint('TOPRIGHT',page,'TOPRIGHT',-7,y+2)
    strip:SetHeight(24)
    local sectionTitle=label(page,string.upper(name),11,15,y-3,.97,.79,.44)
    aquariumController.themeTextObjects[sectionTitle]='gold'
  end
  local function addCheck(page,name,key,y,callback)
    local b=checkButton(page,name,12,y,key,callback)
    b:SetWidth(397)
    optionsWindow.checks[#optionsWindow.checks+1]=b
    return b
  end
  local function slider(page,name,key,y,min,max,step,fmt,callback)
    local s=simpleSlider(page,name,18,y,384,min,max,step,key,fmt,callback)
    optionsWindow.sliders[#optionsWindow.sliders+1]=s
    return s
  end

  local fishing=optionsWindow.pages[1]
  section(fishing,'Fishing mode',-38)
  addCheck(fishing,'Suggest a fishing pole found in my bags','autoPole',-71)
  addCheck(fishing,'Enter mode when a fishing pole is equipped','autoPoleDetect',-104)
  addCheck(fishing,'Remind me to apply bait with the VibeBait macro','autoBait',-137)
  section(fishing,'Action bar buttons',-187)
  local function macroIcon(page,x,y,texture,title,desc,callback)
    local b=btn(page,'',52,50,x,y,callback)
    local icon=b:CreateTexture(nil,'OVERLAY')
    icon:SetSize(39,39)
    icon:SetPoint('CENTER')
    icon:SetTexture(texture)
    icon:SetTexCoord(.08,.92,.08,.92)
    b:SetScript('OnEnter',function(self)
      GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
      GameTooltip:AddLine(title,.98,.83,.48)
      GameTooltip:AddLine(desc,.82,.96,.91,true)
      GameTooltip:Show()
    end)
    b:SetScript('OnLeave',function() GameTooltip:Hide() end)
    return b
  end
  macroIcon(fishing,23,-229,'Interface\\Icons\\INV_Misc_Fish_02','Fishing Mode','Create the VibeFishin mode macro and pick it up for your hotbar.',createMacro)
  macroIcon(fishing,92,-229,'Interface\\Icons\\INV_Misc_Food_35','Fishing Bait','Create a player-activated bait macro and pick it up for your hotbar.',prepareBaitMacro)
  label(fishing,'Drag the resulting icon from your cursor to your hotbar.',11,22,-294,.70,.84,.81)

  local aquarium=optionsWindow.pages[2]
  section(aquarium,'Display and collection',-38)
  addCheck(aquarium,'Show aquarium while fishing','catchPanel',-71,updateStatus)
  addCheck(aquarium,'Keep aquarium visible outside fishing mode','alwaysShowAquarium',-104,updateStatus)
  addCheck(aquarium,'Show fish currently in my inventory','inventoryFish',-137,repopulateAquarium)
  addCheck(aquarium,'Automatically shrink fish when crowded','adaptiveFishSize',-170,repopulateAquarium)
  local cookingCheck = addCheck(aquarium,'Cooking badges for known recipes','showCookingBadges',-203,refreshCookingBadges)
  cookingCheck:SetWidth(260)
  local recipeScanButton = btn(aquarium,'SCAN RECIPES',128,26,278,-202,function()
    scanCookingRecipes(false)
  end)
  recipeScanButton:SetScript('OnEnter',function(self)
    GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
    GameTooltip:AddLine('Scan known Cooking recipes',.98,.83,.48)
    GameTooltip:AddLine('Open your Cooking profession window first, then click this button. The learned fish ingredients will be saved for Cooking badges.',.82,.96,.91,true)
    GameTooltip:Show()
  end)
  recipeScanButton:SetScript('OnLeave',function()GameTooltip:Hide() end)
  section(aquarium,'Movement and size',-243)
  addCheck(aquarium,'Swim in same-species schools','schooling',-275)
  local noCapNote = label(aquarium,'All collected fish are displayed. No aquarium fish limit.',11,20,-313,.72,.88,.81)
  noCapNote:SetWidth(382)
  btn(aquarium,'RESET AQUARIUM POSITION',196,30,18,-359,function()
    characterSettings.x,characterSettings.y=0,0
    characterSettings.width,characterSettings.height=440,310
    if aquariumWindow then
      aquariumWindow:ClearAllPoints()
      aquariumWindow:SetPoint('CENTER',UIParent,'CENTER',0,0)
      aquariumWindow:SetSize(characterSettings.width,characterSettings.height)
      if aquariumWindow.RefreshLayout then aquariumWindow:RefreshLayout() end
    end
    say('Aquarium location and size reset.')
  end)
  btn(aquarium,'CLEAR CATCHES',116,30,231,-359,function()
    characterSettings.total = 0
    wipeTable(characterSettings.catches)
    wipeTable(characterSettings.residents)
    wipeTable(characterSettings.bagResidents)
    wipeTable(characterSettings.treasures)
    wipeTable(characterSettings.deadFish or {})
    repopulateAquarium()
  end)
  local cinema=optionsWindow.pages[3]
  section(cinema,'Cinematic catch experience',-38)
  addCheck(cinema,'Animated catch preview and aquarium transfer','catchPreview',-71)
  addCheck(cinema,'Subtle water movement while character turns','waterMotion',-104)
  section(cinema,'Cast timer',-156)
  addCheck(cinema,'Show circular cast timer','showTimer',-189,updateStatus)
  slider(cinema,'Timer scale','timerScale',-232,.7,1.6,.05,'%.2f',function(v)
    if castTimerWindow then castTimerWindow:SetScale(v) end
  end)
  section(cinema,'Aquarium atmosphere',-282)
  addCheck(cinema,'Animated sand along the aquarium floor','movingSand',-317)
  addCheck(cinema,'Decorative bubbling treasure chest','ambientChest',-351)

  local display=optionsWindow.pages[4]
  section(display,'Appearance',-38)
  slider(display,'Window opacity','opacity',-74,.35,1,.05,'%.2f',applyThemeOpacity)
  section(display,'Auction data',-143)
  addCheck(display,'Show estimated value of displayed aquarium fish','showFishValue',-180,updateFishValue)
  addCheck(display,'Gold border around the most valuable fish','highlightMostValuable',-213,updateFishValue)
  local note=label(display,'Uses existing Auctionator / AHDB price scans.\nUnpriced fish are not assigned a value.',11,20,-261,.70,.84,.81)
  note:SetJustifyH('LEFT')
  btn(display,'REFRESH AQUARIUM',157,30,18,-337,repopulateAquarium)

  local performance = optionsWindow.pages[5]
  section(performance,'Aquarium animation',-38)
  slider(performance,'Animation frames per second','animationFPS',-85,10,30,5,'%d')
  addCheck(performance,'Low-impact mode (12 FPS max, simpler decoration updates)','lowImpactMode',-153)
  local perfInfo=label(performance,
    'Normal: Fish and water animate at up to 20 FPS, sand and props at 10 FPS, and schooling at 5 FPS.\n\nLow-impact mode lowers visual rates further, while feeding, hunger and temperature still use real elapsed time.\n\nAnimations pause when the aquarium is hidden.',
    11,20,-212,.70,.88,.83)
  perfInfo:SetWidth(379)
  perfInfo:SetJustifyH('LEFT')

  local themes=optionsWindow.pages[6]
  section(themes,'Interface theme gallery',-38)
  optionsWindow.themeCards={}
  -- Single-column gallery avoids narrow, overlapping text in scaled WoW UI.
  -- Fixed-height rows separate the color swatch, title and short descriptor.
  for index, themeKey in ipairs(aquariumController.themeOrder) do
    local palette=aquariumController.themePalettes[themeKey]
    local card=btn(themes,'',392,39,12,-72-(index-1)*43,function()
      characterSettings.themeID=themeKey
      aquariumController.applyTheme()
    end)
    card.text:SetText('')
    card:SetScript('OnLeave',function()
      aquariumController.styleThemeFrame(card,'button')
      if optionsWindow.RefreshThemeCards then optionsWindow:RefreshThemeCards() end
    end)
    local swatch=card:CreateTexture(nil,'ARTWORK')
    swatch:SetSize(21,24)
    swatch:SetPoint('LEFT',card,'LEFT',10,0)
    swatch:SetColorTexture(unpack(palette.accent))
    local name=card:CreateFontString(nil,'OVERLAY','GameFontNormal')
    name:SetFont('Fonts\\FRIZQT__.TTF',12,'OUTLINE')
    name:SetPoint('LEFT',card,'LEFT',43,0)
    name:SetWidth(124)
    name:SetJustifyH('LEFT')
    name:SetText(palette.name)
    local desc=card:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
    desc:SetFont('Fonts\\FRIZQT__.TTF',10,'OUTLINE')
    desc:SetPoint('LEFT',card,'LEFT',171,0)
    desc:SetWidth(175)
    desc:SetJustifyH('LEFT')
    local shortDescriptions={
      abyss='Ocean teal',midnight='Dark and blue',classic='Blizzard interface',
      coral='Warm tropical',emerald='Forest jade',arcane='Violet magic',
      frost='Arctic silver',sunset='Copper and amber'
    }
    desc:SetText(shortDescriptions[themeKey] or '')
    local indicator=card:CreateTexture(nil,'OVERLAY')
    indicator:SetTexture('Interface\\Buttons\\WHITE8X8')
    indicator:SetSize(4,24)
    indicator:SetPoint('RIGHT',card,'RIGHT',-8,0)
    indicator:SetColorTexture(unpack(palette.accent))
    optionsWindow.themeCards[index]={button=card,key=themeKey,name=name,description=desc,indicator=indicator}
  end
  function optionsWindow:RefreshThemeCards()
    for _,entry in ipairs(self.themeCards) do
      local pal=aquariumController.themePalettes[entry.key]
      local selected=entry.key==characterSettings.themeID
      if entry.button.gloss then entry.button.gloss:SetAlpha(selected and .18 or .04) end
      if entry.indicator then entry.indicator:SetAlpha(selected and 1 or .13) end
      entry.button:SetBackdropBorderColor(unpack(selected and pal.accent or aquariumController.currentTheme().border))
      entry.name:SetTextColor(unpack(selected and pal.accent or aquariumController.currentTheme().text))
      entry.description:SetTextColor(unpack(aquariumController.currentTheme().muted))
    end
  end
  local hint=label(themes,'Applied instantly. Saved for this character.',10,14,-423,.66,.85,.82)
  hint:SetWidth(385)

  local footer=optionsWindow:CreateTexture(nil,'BACKGROUND')
  footer:SetColorTexture(.15,.25,.25,.95)
  optionsWindow.footer=footer
  footer:SetPoint('BOTTOMLEFT',2,2)
  footer:SetPoint('BOTTOMRIGHT',-2,2)
  footer:SetHeight(44)
  label(optionsWindow,'VIBE  /  AQUARIUM 4.0',11,19,-589,.69,.87,.83)
  optionsWindow.themeName=label(optionsWindow,'',11,306,-589,.70,.93,.89)
  function optionsWindow:Refresh()
    for _,b in ipairs(self.checks) do b:Refresh() end
    for _,s in ipairs(self.sliders) do s.Render() end
  end
  activatePage(2)
  aquariumController.applyTheme()
  optionsWindow:RefreshThemeCards()
  optionsWindow:Hide()
end

-- Registers settings with the client options pane when available.
local function registerOptionsCategory()
  if not InterfaceOptions_AddCategory then return end
  optionsProxy = CreateFrame('Frame', 'VibeFishinOptionsProxy', InterfaceOptionsFramePanelContainer)
  optionsProxy.name = 'VibeFishin'
  optionsProxy.title = optionsProxy:CreateFontString(nil, 'ARTWORK', 'GameFontNormalLarge')
  optionsProxy.title:SetPoint('TOPLEFT', 16, -16)
  optionsProxy.title:SetText('VibeFishin')
  optionsProxy.subtitle = optionsProxy:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
  optionsProxy.subtitle:SetPoint('TOPLEFT', optionsProxy.title, 'BOTTOMLEFT', 0, -8)
  optionsProxy.subtitle:SetWidth(560)
  optionsProxy.subtitle:SetJustifyH('LEFT')
  optionsProxy.subtitle:SetText('Open the full VibeFishin options window for aquarium visuals, bait automation, opacity, and cast-timer controls.')
  local open = CreateFrame('Button', nil, optionsProxy, 'UIPanelButtonTemplate')
  open:SetSize(180, 24)
  open:SetPoint('TOPLEFT', optionsProxy.subtitle, 'BOTTOMLEFT', 0, -16)
  open:SetText('Open VibeFishin Options')
  open:SetScript('OnClick', function()
    if optionsWindow and optionsWindow.Refresh then optionsWindow:Refresh() end
    if optionsWindow then optionsWindow:Show() end
  end)
  InterfaceOptions_AddCategory(optionsProxy)
end

-- Enables fishing mode, cast detection and bait reminder state.
function startFishing(automatic)
  if active then return end
  if InCombatLockdown and InCombatLockdown() then say('Cannot switch fishing equipment in combat.') return end
  if characterSettings.autoPole and not currentlyEquipped() then
    local link = choosePole()
    if link then
      say('Fishing pole found in bags. Equip it manually before using bait (WoW blocks background equipment changes).')
    else
      say('No fishing pole detected in bags. You can still use the visual mode.')
    end
  end
  active = true
  manual = not automatic
  if characterSettings.autoBait then adviseBait() end
  updateStatus()
  say('Fishing mode enabled. Cast Fishing using your spell or action bar.')
end

-- Disables fishing mode and removes active temporary cast state.
local function stopFishing()
  if not active then return end
  active = false
  casting = false
  manual = false
  pendingBaitAt = nil
  updateStatus()
  say('Fishing mode disabled.')
end

-- Toggles the fishing mode using the player-facing command.
local function toggleFishing()
  if active then
    stopFishing()
  else
    startFishing(false)
  end
end

-- Starts or stops the countdown using actual cast time when available.
local function setCast(isOn, startTime, duration)
  if not castTimerWindow then return end
  if isOn then
    local t = GetTime and GetTime() or now
    startTime = startTime or t
    duration = clamp(duration or 22, 1, 60)
    -- Don't reset the visible timer when the client sends redundant events.
    if casting and activeCastEnd > t and math.abs(activeCastEnd-(startTime+duration)) < 2 then
      updateStatus()
      return
    end
    aquariumController.timerGraceUntil = nil
    aquariumController.catchTimerHandoff = nil
    casting = true
    activeCastEnd = startTime + duration
    castTimerWindow.start = startTime
    castTimerWindow.duration = duration
    if characterSettings and characterSettings.autoBait and not mainHandHasLure() then adviseBait(true) end
  else
    -- Leave the full widget visible briefly so a real fish-loot event can
    -- take over without the rod disappearing between channel stop and loot.
    if casting and characterSettings and characterSettings.showTimer then
      aquariumController.timerGraceUntil = (GetTime and GetTime() or now) + 2
    end
    casting = false
  end
  updateStatus()
end

-- Gets the locale-specific Fishing spell name from the client.
local function fishingName()
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, 7620)
    if ok and type(info)=='table' and info.name then return info.name end
  end
  if GetSpellInfo then
    local ok, name = pcall(GetSpellInfo, 7620)
    if ok and type(name)=='string' then return name end
  end
  return 'Fishing'
end
-- Recognizes fishing cast events using IDs or localized names.
local function isFishingSpell(name, spellID)
  if spellID==7620 or spellID==131474 then return true end
  if type(name)=='string' then return name==fishingName() or name=='Fishing' end
  return false
end

-- Reads current channeled cast timing from available client APIs.
local function channelInfo()
  if not UnitChannelInfo then return nil end
  local ok, name, _, _, startMS, endMS, _, _, spellID = pcall(UnitChannelInfo, 'player')
  if not ok or not name or not isFishingSpell(name, spellID) then return nil end
  local t=GetTime and GetTime() or now
  if type(startMS)=='number' and type(endMS)=='number' and endMS>startMS then
    return startMS / 1000, (endMS-startMS) / 1000
  end
  return t, 22
end

-- Handles cast-related client events for the player only.
local function eventCast(event, unit, castGUID, spellID)
  if unit~='player' or not active then return end
  local name=nil
  if C_Spell and C_Spell.GetSpellInfo and type(spellID)=='number' then
    local ok, info=pcall(C_Spell.GetSpellInfo, spellID)
    if ok and type(info)=='table' then name=info.name end
  end
  if not name and GetSpellInfo and type(spellID)=='number' then
    local ok, resolved=pcall(GetSpellInfo, spellID)
    if ok then name=resolved end
  end
  local fishing=isFishingSpell(name, spellID)
  if event=='UNIT_SPELLCAST_CHANNEL_START' then
    local begin, duration=channelInfo()
    if begin or fishing then
      lastFishingSignal=GetTime and GetTime() or now
      setCast(true, begin, duration)
    end
  elseif event=='UNIT_SPELLCAST_START' or event=='UNIT_SPELLCAST_SENT' then
    -- Some Forever builds send cast events before the fishing channel starts.
    if fishing then
      lastFishingSignal=GetTime and GetTime() or now
      local begin, duration=channelInfo()
      setCast(true, begin, duration)
    end
  elseif event=='UNIT_SPELLCAST_CHANNEL_STOP' or event=='UNIT_SPELLCAST_INTERRUPTED' or event=='UNIT_SPELLCAST_STOP' then
    -- Ignore unrelated spells; only cancel if a recent fishing signal existed.
    if casting and (fishing or ((GetTime and GetTime() or now)-lastFishingSignal < 30 and event=='UNIT_SPELLCAST_CHANNEL_STOP')) then
      setCast(false)
    end
  end
end

-- Classifies a fresh loot event as fish, plant or sinking treasure.
local function onLoot(msg)
  -- Loot can arrive after the cast channel ends or as the mode is closing.
  -- Accept likely fishing loot when a pole is equipped or recently cast too.
  local recentlyFished = ((GetTime and GetTime() or now) - lastFishingSignal) < 65
  if not active and not recentlyFished and not currentlyEquipped() then return end
  if type(msg) ~= 'string' then return end
  local selfLoot = (LOOT_ITEM_SELF or 'You receive loot: %s.')
  local selfMultiple = (LOOT_ITEM_SELF_MULTIPLE or 'You receive loot: %sx%d.')
  local isSelf = (msg:find('You receive loot', 1, true) or msg:find('You receive item', 1, true))
  if not isSelf then
    for _, fmt in ipairs({ selfLoot, selfMultiple }) do
      local prefix = fmt:match('^(.-)%%')
      if prefix and #prefix > 0 and msg:sub(1, #prefix) == prefix then isSelf = true break end
    end
  end
  if not isSelf then return end
  local id = tonumber(msg:match('|Hitem:(%d+)'))
  if not id then return end
  local count = tonumber(msg:match('x(%d+)%s*%.?$')) or 1
  local link = msg:match('(|Hitem:.-|h%[.-%]|h)') or msg:match('(|c%x+|Hitem:.-|h%[.-%]|h|r)')
  -- Retail-style color tags (|cnIQ...) and abbreviated item links are okay:
  -- item ID is enough for known fish; pass the message for name fallback.
  link = link or msg
  if isExcludedFishingLoot(id,link) then return end
  if isFishItem(id, link) then
    addCatch(id, count, link)
    return
  end
  characterSettings.fishingLootIDs=characterSettings.fishingLootIDs or {}
  if isPlantCatch(id,link) or characterSettings.fishingLootIDs[id]=='plant' then
    characterSettings.fishingLootIDs[id]='plant'
    addPlantCatch(id,count,link)
    return
  end
  -- A known fishing container can always be recorded. Unknown items are
  -- accepted only very close to a real fishing event, not during a long
  -- passive 65-second window (which also sees unrelated quest loot).
  if isTreasureCatch(id,link) or (recentlyFished and ((GetTime and GetTime() or now)-lastFishingSignal)<12) then
    characterSettings.fishingLootIDs[id]='treasure'
    addTreasureCatch(id,count,link)
  end
end

-- ============================================================================
-- Timed aquarium simulation
-- Survival: 1 Hz; fish and timer: configurable 10-30 Hz; schooling: ~5 Hz;
-- sand/props: 5-10 Hz. Hidden tanks run survival but not visual animations.
-- ============================================================================
-- Simulates fish hunger, dangerous temperature exposure, and death once per
-- second. Time is based on GetTime rather than rendered frames so a hidden tank
-- still ages normally, but rendering is never performed from this function.
local function updateFishSurvival(t)
  if not aquariumCanvas then return end
  local previousTick = aquariumController.lastSurvivalTick or t
  local survivalElapsed = clamp(t - previousTick, 0, 10)
  aquariumController.lastSurvivalTick = t
  local hungerSum, hungerCount, deadCount = 0, 0, 0
  for _, f in ipairs(swimmingFish) do
      f.lastFed = f.lastFed or t
      -- Each fish accumulates thermal exposure while the water is outside its
      -- safe range. Cooling/heating the water lets exposure fade before death.
      if not f.deadState then
        local waterTemp = aquariumController.waterTemp or 75
        local coldStress = math.max(0, 68 - waterTemp)
        local heatStress = math.max(0, waterTemp - 83)
        local stress = math.max(coldStress, heatStress)
        f.temperatureExposure = clamp((f.temperatureExposure or 0) + (stress > 0 and survivalElapsed * stress / 6 or -survivalElapsed * 1.6), 0, 300)
      end
      local starved = (t - f.lastFed) >= 3600
      local thermalFailure = (f.temperatureExposure or 0) >= 300
      if not f.deadState and (starved or thermalFailure) then
        f.deathCause = thermalFailure and ((aquariumController.waterTemp or 75) < 68 and 'cold' or 'heat') or 'hunger'
        f.deadState='dead'
        f.deadAt=t
        f.skeletonAt=t+300
        f.deathX=f.x
        f.foodTarget=nil
        f.eatingBit=nil
        aquariumController.saveResidentFromFrame(f,t)
      end
      if f.deadState then
        deadCount = deadCount + 1
        -- Death and skeleton stages are stored on the unique resident record.
        if f.deadState=='skeleton' then
          f.icon:SetTexture('Interface\\Icons\\INV_Misc_Bone_ElfSkull_01')
          f.icon:SetTexCoord(.08,.92,.08,.92)
        elseif f.deadState=='dead' and t >= (f.skeletonAt or (f.deadAt or t)+300) then
          f.deadState='skeleton'
          f.icon:SetTexture('Interface\\Icons\\INV_Misc_Bone_ElfSkull_01')
          f.icon:SetTexCoord(.08,.92,.08,.92)
        end
      else
        local satiety = clamp(1 - ((t - f.lastFed) / 3600), 0, 1)
        hungerSum = hungerSum + satiety*100
        hungerCount = hungerCount + 1
        f.hunger = satiety*100
        local thermal = clamp(100-(f.temperatureExposure or 0)/3,0,100)
        f.happiness = math.min(thermal,f.hunger)
      end
      aquariumController.saveResidentFromFrame(f,t)
  end
  aquariumController.hungerVitality = hungerCount > 0 and (hungerSum / hungerCount) or 100
  aquariumController.deadFishCount = deadCount
  aquariumController.fishVitality = math.min(aquariumController.tempVitality or 100, aquariumController.hungerVitality or 100)
  characterSettings.fishHunger = aquariumController.hungerVitality
  characterSettings.fishVitality = aquariumController.fishVitality
end

local function updateFishVisuals(t)
  local tankVisible = aquariumWindow and aquariumWindow:IsShown()
  if tankVisible and characterSettings and characterSettings.waterMotion and GetPlayerFacing and (t-lastFacingSample)>.065 then
    lastFacingSample=t
    local ok,facing=pcall(GetPlayerFacing)
    if ok and type(facing)=='number' then
      if previousFacing then
        local diff=(facing-previousFacing+math.pi)%(2*math.pi)-math.pi
        waterTurnImpulse=clamp(waterTurnImpulse+diff*18,-32,32)
      end
      previousFacing=facing
    end
  end
  if tankVisible then
    local dtFluid=clamp(aquariumController.lastFluid and t-aquariumController.lastFluid or .016,.006,.08)
    aquariumController.lastFluid=t
    waterSurfaceMomentum=waterSurfaceMomentum+waterTurnImpulse*dtFluid*3
    waterTurnImpulse=waterTurnImpulse*(1-dtFluid*3.2)-waterSurfaceMomentum*dtFluid*1.8
    waterSurfaceMomentum=clamp(waterSurfaceMomentum,-21,21)
    updateSpills(t,dtFluid)
  else
    aquariumController.lastFluid=t
  end
  if tankVisible then
    if aquariumWindow.lightShafts then
      for i,ray in ipairs(aquariumWindow.lightShafts) do
        ray:SetAlpha(0.45+math.sin(t*.43+i*1.7)*0.22)
      end
    end
    if aquariumWindow.surfaceWave then
      local waveAmp = clamp(3 + math.abs(waterSurfaceMomentum)*0.66 + math.abs(waterTurnImpulse)*0.08, 3, 18)
      aquariumWindow.surfaceWave:SetAlpha(clamp(0.52+math.sin(t*2.1)*0.22+math.abs(waterSurfaceMomentum)*.018,.18,1))
      aquariumWindow.surfaceWave:SetHeight(waveAmp)
      local crest = math.sin(t*2.2) * math.min(3.2, waveAmp*0.28)
      aquariumWindow.surfaceWave:ClearAllPoints()
      aquariumWindow.surfaceWave:SetPoint('TOPLEFT',aquariumWindow.tank,'TOPLEFT',3,-14+crest)
      aquariumWindow.surfaceWave:SetPoint('TOPRIGHT',aquariumWindow.tank,'TOPRIGHT',-3,-14-crest)
      -- Surface remains anchored to the rim; overflow is handled below.
    end
  end
  if castTimerWindow and casting then
    local remain = clamp(activeCastEnd - t, 0, 100)
    local duration = math.max(castTimerWindow.duration or 1, 0.01)
    local progress = clamp(remain / duration, 0, 1)
    if castTimerWindow.clock then castTimerWindow.clock:SetText(('%0.1fs'):format(remain)) end
    if castTimerWindow.sub then
      if remain < 3 then castTimerWindow.sub:SetText('get ready...') elseif remain < 7 then castTimerWindow.sub:SetText('watch the bobber...') else castTimerWindow.sub:SetText('steady... steady...') end
    end
    if castTimerWindow.bobberAnchor then
      local bobX = 138 + math.sin(t * 2.2) * 4
      local bobY = -2 + math.sin(t * 5.4) * 5
      castTimerWindow.bobberAnchor:ClearAllPoints()
      castTimerWindow.bobberAnchor:SetPoint('LEFT', castTimerWindow, 'LEFT', bobX, bobY)
      local waterSway = math.sin(t * 3.2) * 1.6
      local waterWidth = 38 + math.sin(t * 2.4) * 4
      castTimerWindow.waterline:ClearAllPoints()
      castTimerWindow.waterline:SetPoint('CENTER', castTimerWindow.bobberAnchor, 'CENTER', 0, -5 + waterSway)
      castTimerWindow.waterline:SetWidth(waterWidth)
      castTimerWindow.waterlineShadow:ClearAllPoints()
      castTimerWindow.waterlineShadow:SetPoint('CENTER', castTimerWindow.bobberAnchor, 'CENTER', 0, -6 + waterSway)
      castTimerWindow.waterlineShadow:SetWidth(waterWidth + 2)
      if castTimerWindow.bobberShadow then castTimerWindow.bobberShadow:SetWidth(16 + math.abs(math.sin(t*5.4))*6) end
      if castTimerWindow.line then
        local startX, startY = 46, 2
        local endX, endY = bobX - 2, bobY
        local dx, dy = endX - startX, endY - startY
        local len = math.sqrt(dx*dx + dy*dy)
        castTimerWindow.line:ClearAllPoints()
        castTimerWindow.line:SetPoint('LEFT', castTimerWindow, 'LEFT', startX, startY)
        castTimerWindow.line:SetSize(len, 2)
        if castTimerWindow.line.SetRotation then local ang=math.atan2 and math.atan2(dy,dx) or math.atan(dy/(math.abs(dx)<0.001 and 0.001 or dx)); if not math.atan2 and dx<0 then ang=ang+math.pi end; castTimerWindow.line:SetRotation(ang) end
        castTimerWindow.lineGuide:ClearAllPoints()
        castTimerWindow.lineGuide:SetPoint('LEFT', castTimerWindow, 'LEFT', startX, startY)
        castTimerWindow.lineGuide:SetSize(len, 1)
        if castTimerWindow.lineGuide.SetRotation then local ang=math.atan2 and math.atan2(dy,dx) or math.atan(dy/(math.abs(dx)<0.001 and 0.001 or dx)); if not math.atan2 and dx<0 then ang=ang+math.pi end; castTimerWindow.lineGuide:SetRotation(ang) end
      end
      if castTimerWindow.ringTicks then
        local lit = math.floor(progress * #castTimerWindow.ringTicks + 0.5)
        for i, tex in ipairs(castTimerWindow.ringTicks) do
          local ang = ((i-1)/#castTimerWindow.ringTicks) * math.pi * 2 - math.pi/2
          local radius = 18
          tex:ClearAllPoints()
          tex:SetPoint('CENTER', castTimerWindow.bobberAnchor, 'CENTER', math.cos(ang)*radius, math.sin(ang)*radius)
          if tex.SetRotation then tex:SetRotation(ang) end
          tex:SetAlpha(i <= lit and 0.95 or 0.14)
        end
      end
      if castTimerWindow.ripples then
        for i, r in ipairs(castTimerWindow.ripples) do
          local phase = ((t*1.9)+(i*.18)) % 1
          r:SetSize(16 + phase*28, 2)
          r:SetAlpha((1-phase) * (0.18 - i*0.03))
          r:ClearAllPoints()
          r:SetPoint('CENTER', castTimerWindow.bobberAnchor, 'CENTER', 0, -12)
        end
      end
    end
  end

  if tankVisible and aquariumCanvas then
    local w,h=aquariumCanvas:GetWidth(),aquariumCanvas:GetHeight()
    local dt=clamp(aquariumController.lastVisual and (t-aquariumController.lastVisual) or .016,.005,.06)
    -- Rebuild one compact spatial index at the AI rate. Schooling decisions
    -- inspect neighboring buckets, rather than every resident in the tank.
    if characterSettings.schooling and (not aquariumController.nextSchoolGridTick or t >= aquariumController.nextSchoolGridTick) then
      aquariumController.nextSchoolGridTick = t + (characterSettings.lowImpactMode and 0.333 or 0.2)
      local cells, populations = {}, {}
      local size = 72
      for _, resident in ipairs(swimmingFish) do
        if not resident.deadState then
          local sx=math.floor((resident.x or 0)/size)
          local sy=math.floor((resident.y or 0)/size)
          cells[sx] = cells[sx] or {}
          cells[sx][sy] = cells[sx][sy] or {}
          local bucket=cells[sx][sy]
          bucket[#bucket+1]=resident
          local species=resident.species
          local group=populations[species]
          if not group then
            group={ count=0, x=0, y=0, vx=0, vy=0 }
            populations[species]=group
          end
          group.count=group.count+1
          group.x=group.x+(resident.x or 0)
          group.y=group.y+(resident.y or 0)
          group.vx=group.vx+(resident.vx or 0)
          group.vy=group.vy+(resident.vy or 0)
        end
      end
      aquariumController.schoolCells=cells
      aquariumController.schoolStats=populations
      aquariumController.schoolCellSize=size
    end
    for i,f in ipairs(swimmingFish) do
      local maxX=math.max(3,w-f.size-3)
      local maxY=math.max(3,h-f.size-3)
      if f.entryElapsed then
        f.entryElapsed = f.entryElapsed + dt
        local progress = clamp(f.entryElapsed / f.entryDuration, 0, 1)
        -- Gentle plunge then swim to a school position; independent per fish.
        local ease = 1 - (1-progress)*(1-progress)
        f.x = clamp(f.entryStartX + (f.entryTargetX-f.entryStartX)*ease + math.sin(progress*math.pi*2+f.phase)*3*(1-progress), 2, maxX)
        f.y = clamp(f.entryStartY + (f.entryTargetY-f.entryStartY)*ease, 2, maxY)
        f:ClearAllPoints()
        f:SetPoint('BOTTOMLEFT', aquariumCanvas, 'BOTTOMLEFT', f.x, f.y)
        if progress >= 1 then f.entryElapsed = nil end
      else
      if f.deadState then
        local driftX = clamp((f.deathX or f.x or maxX*0.5) + math.sin(t*0.35+f.phase)*4 + waterSurfaceMomentum*0.04, 2, maxX)
        if f.deadState=='dead' then
          f.x = driftX
          f.y = clamp((f.y or maxY*0.5) + dt*16, 2, maxY)
          if (f.heading or 1) < 0 then
            f.icon:SetTexCoord(.92,.08,.92,.08)
          else
            f.icon:SetTexCoord(.08,.92,.92,.08)
          end
        else
          f.x = driftX
          f.y = clamp((f.y or maxY) - dt*7, 4, maxY)
          f.icon:SetTexCoord(.08,.92,.08,.92)
        end
        f.heading=0
        f:ClearAllPoints()
        f:SetPoint('BOTTOMLEFT',aquariumCanvas,'BOTTOMLEFT',f.x,f.y)
      else
      local target=f.foodTarget
      if t >= (f.nextWaypoint or 0) and not target then
        local home=schoolTerritories[f.species]
        local roaming=math.sin(t*0.19+i*3.11)
        local theta=t*0.18+i*2.3999632
        local distance=0.16+0.22*(0.5+0.5*math.sin(t*.10+i*1.4))
        local centerX=(home and home.x or 0.5)*w
        local centerY=(home and home.y or 0.5)*h
        -- Every fourth move takes a fish on a longer expedition, otherwise
        -- its home territory keeps different species from merging centrally.
        if roaming > 0.70 or f.personality==1 then distance=distance+0.20 end
        if f.personality==4 then distance=distance*0.55 end -- Shy fish stay near home
        f.targetX=clamp(centerX+math.cos(theta)*distance*w,2,maxX)
        f.targetY=clamp(centerY+math.sin(theta*1.21)*distance*h,2,maxY)
        f.nextWaypoint=t+4+(i%7)*1.1
      end
      local canEat=(f.fedUntil or 0)<=t and t<feedingUntil

      if target and (target.eaten or not canEat) then
        if target.claimedBy==f then target.claimedBy=nil end
        f.foodTarget=nil
        f.eatingBit=nil
        target=nil
      end

      if canEat and not target then
        local free,freeDist,contested,contestedDist
        for _,bit in ipairs(foodPellets) do
          if not bit.eaten then
            local dx=bit.x-f.x
            local dy=bit.y-f.y
            local dist=dx*dx+dy*dy
            if not bit.claimedBy then
              if not freeDist or dist<freeDist then free,freeDist=bit,dist end
            elseif not contestedDist or dist<contestedDist then
              contested,contestedDist=bit,dist
            end
          end
        end
        target=free or contested
        if target then
          f.foodTarget=target
          if not target.claimedBy then target.claimedBy=f end
        end
      end

      local tx,ty=f.targetX,f.targetY
      if target then
        tx=target.x-(f.size-target.baseSize)*0.5
        ty=target.y-(f.size-target.baseSize)*0.5
      end
      -- Recalculate school steering at ~5 Hz. Population statistics are O(N),
      -- and individual avoidance only visits spatially close fish.
      if not target and characterSettings.schooling then
        if t >= (f.nextSchoolUpdate or 0) then
          f.nextSchoolUpdate = t + (characterSettings.lowImpactMode and 0.333 or 0.2) + (i % 7) * 0.005
          local home=schoolTerritories[f.species]
          local group=aquariumController.schoolStats and aquariumController.schoolStats[f.species]
          if group and group.count>1 then
            local others=group.count-1
            local centerX=(group.x-f.x)/others
            local centerY=(group.y-f.y)/others
            local flowX=(group.vx-(f.vx or 0))/others
            local flowY=(group.vy-(f.vy or 0))/others
            local follow = f.personality==2 and .38 or .22 -- Social fish school more closely
            tx=tx*(.85-follow)+centerX*follow+(home and home.x*w or w*.5)*.15+flowX*.12
            ty=ty*(.85-follow)+centerY*follow+(home and home.y*h or h*.5)*.15+flowY*.12
          elseif home then
            tx=tx*.81+home.x*w*.19
            ty=ty*.81+home.y*h*.19
          end
          local cells=aquariumController.schoolCells
          local friendCandidate, friendDistance
          if cells then
            local size=aquariumController.schoolCellSize or 72
            local cellX=math.floor(f.x/size)
            local cellY=math.floor(f.y/size)
            local pushX,pushY=0,0
            -- Three buckets in each direction cover up to 216px avoidance.
            for gx=cellX-3,cellX+3 do
              local column=cells[gx]
              if column then
                for gy=cellY-3,cellY+3 do
                  local bucket=column[gy]
                  if bucket then
                    for _,other in ipairs(bucket) do
                      if other~=f then
                        local rx=f.x-other.x
                        local ry=f.y-other.y
                        local distanceSquared=rx*rx+ry*ry
                        if distanceSquared>1 then
                          if other.species==f.species then
                            -- Bond with a nearby same-species companion while
                            -- performing the existing low-frequency spatial scan.
                            if distanceSquared < 1800 and (not friendDistance or distanceSquared < friendDistance) then
                              friendCandidate,friendDistance=other,distanceSquared
                            end
                            local spacing=(f.size+other.size)*.55
                            if distanceSquared<spacing*spacing then
                              pushX=pushX+rx/distanceSquared*900
                              pushY=pushY+ry/distanceSquared*900
                            end
                          else
                            local safe=math.max(30,(f.size+other.size)*2.1)
                            if f.personality==4 then safe=safe*1.35 end
                            if distanceSquared<safe*safe then
                              local distance=math.sqrt(distanceSquared)
                              local weight=(safe-distance)/safe*27/distance
                              pushX=pushX+rx*weight
                              pushY=pushY+ry*weight
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
            tx=tx+pushX
            ty=ty+pushY
            if friendCandidate and f.resident then
              local record=f.resident
              if record.friendUid==friendCandidate.uid then
                record.bondScore=math.min(100,(record.bondScore or 0)+1)
              elseif not record.friendUid or (record.bondScore or 0)<15 then
                record.friendUid=friendCandidate.uid
                record.bondScore=1
              end
            end
          end
          f.schoolTargetX, f.schoolTargetY = tx, ty
        end
        tx,ty=f.schoolTargetX or tx,f.schoolTargetY or ty
      end
      tx=clamp(tx,2,maxX)
      ty=clamp(ty,2,maxY)
      local dx,dy=tx-f.x,ty-f.y
      local d=math.sqrt(dx*dx+dy*dy)
      local reached=target and d<math.max(7,f.size*0.38)

      if reached then
        -- The first fish starts a 5-second nibbling window. Other hungry
        -- fish can join and visibly compete, but only the winner eats.
        if not target.eatStarted then
          target.eatStarted=t
          target.eater=f
          target.claimedBy=f
        end
        -- Another hungry fish may join a claimed pellet and jostle for it;
        -- the first fish to start nibbling receives the meal after 5 seconds.
        f.eatingBit=target
        local jiggle=math.sin(t*22+f.phase)*2.5
        f.x=clamp(tx+jiggle,2,maxX)
        f.y=clamp(ty+math.cos(t*25+f.phase)*2,2,maxY)
      elseif d<10 and not target then
        f.targetX=2+((i*71+math.floor(t*5)*47)%math.max(5,maxX-2))
        f.targetY=2+((i*113+math.floor(t*4)*59)%math.max(5,maxY-2))
        f.eatingBit=nil
      else
        f.eatingBit=nil
        if d>0.001 then
          local foodSpeed = f.personality==3 and 4.1 or 3.4 -- Foragers pursue food faster.
          local speed=f.speed*(target and foodSpeed or 1)*(0.34 + 0.66 * (aquariumController.fishVitality / 100))
          local distance=math.min(d,speed*dt)
          local nextVX=dx/d*speed
          local nextVY=dy/d*speed
          f.vx=(f.vx or nextVX)*0.82+nextVX*0.18
          f.vy=(f.vy or nextVY)*0.82+nextVY*0.18
          f.x=clamp(f.x+(f.vx+waterSurfaceMomentum*.8)*dt,2,maxX)
          f.y=clamp(f.y+f.vy*dt,2,maxY)
          f.heading=f.vx
        end
      end
      f:ClearAllPoints()
      f:SetPoint('BOTTOMLEFT',aquariumCanvas,'BOTTOMLEFT',f.x,f.y+math.sin(t*2+f.wobble)*(f.eatingBit and 1 or 1.5))
      if f.heading and f.heading<0 then f.icon:SetTexCoord(.92,.08,.08,.92) else f.icon:SetTexCoord(.08,.92,.08,.92) end
      end
      end -- regular swimming (after refresh entry)
    end

    for _,bit in ipairs(foodPellets) do
      if not bit.eaten then
        if t>=feedingUntil and not bit.eatStarted then
          bit.eaten=true
          bit:Hide()
        elseif bit.eatStarted then
          local progress=t-bit.eatStarted
          -- Fish and food shake together for five full seconds.
          bit.x=bit.x+math.sin(t*29)*0.15
          bit.y=bit.y+math.cos(t*26)*0.12
          if progress>=EAT_SECONDS then
            bit.eaten=true
            bit:Hide()
            local winner=bit.eater
            if winner and not winner.deadState then
              winner.fedUntil=t+FED_COOLDOWN
              winner.lastFed=t
              aquariumController.saveResidentFromFrame(winner,t)
              for fishIndex, fish in ipairs(swimmingFish) do
                if fish == winner then fishCooldownByID[fishIndex] = winner.fedUntil break end
              end
              winner.foodTarget=nil
              winner.eatingBit=nil
            end
            for _,fish in ipairs(swimmingFish) do
              if fish.foodTarget==bit then
                fish.foodTarget=nil
                fish.eatingBit=nil
              end
            end
            bit.claimedBy=nil
          end
        else
          bit.y=math.max(h*.30,bit.y-bit.vel*dt)
        end
        if not bit.eaten then
          bit:ClearAllPoints()
          bit:SetPoint('BOTTOMLEFT',aquariumCanvas,'BOTTOMLEFT',bit.x+math.sin(t*24)* (bit.eatStarted and 1.8 or 0),bit.y+math.cos(t*21)*(bit.eatStarted and 1.8 or 0))
        end
      end
    end
    aquariumController.lastVisual=t
    for i,plant in ipairs(floatingPlants) do
      plant:ClearAllPoints()
      plant:SetPoint('CENTER',aquariumCanvas,'BOTTOMLEFT',clamp(plant.anchorX+math.sin(t*.67+plant.phase)*8+waterSurfaceMomentum*.25,14,w-14),h-12+math.sin(t*1.9+plant.phase)*2.4)
    end
    for i, b in ipairs(bubbles) do
      local yy = (b.baseY + (t * (24 + i * 2) * b.speed)) % math.max(40, aquariumCanvas:GetHeight() - 8)
      local xx = b.baseX + math.sin(t * 0.8 + i) * b.drift
      b:ClearAllPoints()
      b:SetPoint('BOTTOMLEFT', aquariumCanvas, 'BOTTOMLEFT', xx, yy)
      local alpha = 0.08 + (math.sin(t * 2 + i) + 1) * 0.05
      b.tex:SetVertexColor(0.87, 1, 1, alpha)
    end
    for i, tr in ipairs(displayedTreasureFrames) do
      local tx, ty = tr.baseX + math.sin(t*.7 + tr.phase)*1.1, tr.baseY + math.sin(t*1.1 + tr.phase)*.5
      if tr.entryElapsed then
        tr.entryElapsed = tr.entryElapsed + dt
        local progress = clamp(tr.entryElapsed / tr.entryDuration, 0, 1)
        local sink = clamp(progress / 0.81, 0, 1)
        local fall = sink * sink
        tx = tr.entryX + (tr.baseX-tr.entryX) * fall
        ty = tr.entryY + (tr.baseY-tr.entryY) * fall
        if progress >= 0.81 then
          local bounce = clamp((progress-0.81) / 0.19, 0, 1)
          ty = tr.baseY + math.sin(bounce * math.pi) * (1-bounce)*9
          if not tr.entryImpactDone then
            tr.entryImpactDone = true
            spawnSandCloud(clamp((tr.baseX+13)/math.max(1,w), .03, .97))
          end
        elseif tr.entryElapsed > 0 then
          tr.entryBubbleClock = (tr.entryBubbleClock or 0) + dt
          if tr.entryBubbleClock > 0.19 then
            tr.entryBubbleClock = 0
            makeSinkBubble(clamp((tx+13)/math.max(1,w), .03, .97), clamp((ty+14)/math.max(1,h), .03, .97))
          end
        end
        if progress >= 1 then tr.entryElapsed = nil end
      end
      tr:ClearAllPoints()
      tr:SetPoint('BOTTOMLEFT', aquariumCanvas, 'BOTTOMLEFT', tx, ty)
    end
    for i, sw in ipairs(seaweedFrames) do
      local segCount = #sw.segments
      local segH = sw.strandH / math.max(1, segCount)
      local swell = math.sin(t * 1.13 + sw.phase) * 3.4 + math.sin(t * 0.57 + sw.phase * 1.7) * 1.9
      local surge = waterSurfaceMomentum * 0.16 + waterTurnImpulse * 0.08
      local totalSway = swell + surge
      sw:ClearAllPoints()
      sw:SetPoint('BOTTOMLEFT', aquariumCanvas, 'BOTTOMLEFT', sw.baseX + totalSway * 0.22, 2)
      for s, seg in ipairs(sw.segments) do
        local pct = s / segCount
        local bend = totalSway * pct * pct
        local wiggle = math.sin(t * 2.0 + sw.phase + s * 0.55) * (0.6 + pct * 1.2)
        seg:ClearAllPoints()
        seg:SetSize(sw.segW + pct * 1.2, segH + 2)
        seg:SetPoint('BOTTOMLEFT', sw, 'BOTTOMLEFT', bend + wiggle, (s - 1) * segH)
        seg:SetVertexColor(0.11 + pct * 0.05, 0.38 + pct * 0.18, 0.20 + pct * 0.06, 0.50 + pct * 0.08)
      end
      for fIndex, fr in ipairs(sw.fronds) do
        local pct = (fIndex + 1) / (#sw.fronds + 2)
        local y = pct * sw.strandH
        local branchBend = totalSway * pct * pct
        local dir = (fIndex % 2 == 0) and 1 or -1
        local len = sw.segW * (2.2 + pct * 1.1)
        fr:ClearAllPoints()
        fr:SetSize(len, math.max(2, sw.segW * 0.72))
        fr:SetPoint('BOTTOMLEFT', sw, 'BOTTOMLEFT', branchBend + dir * 1.5, y)
        if fr.SetRotation then fr:SetRotation(dir * (0.26 + totalSway * 0.012)) end
        fr:SetAlpha(0.28 + pct * 0.20)
      end
    end
  end
end

-- Runs the throttled addon heartbeat and all active animations.
local function update(_, elapsed)
  if not characterSettings then return end
  -- A single lightweight OnUpdate gate prevents every animation subsystem
  -- from waking up for every rendered frame (often 60-144 FPS).
  local frameRate = clamp(tonumber(characterSettings.animationFPS) or 20, 10, 30)
  if characterSettings.lowImpactMode then frameRate = math.min(frameRate, 12) end
  local frameInterval = 1 / frameRate
  ticker = ticker + elapsed
  if ticker < frameInterval then return end
  local heartbeatElapsed = math.min(ticker, 0.25)
  ticker = ticker % frameInterval
  now = GetTime and GetTime() or (now + heartbeatElapsed)
  local tankVisible = aquariumWindow and aquariumWindow:IsShown()
  if not aquariumController.lastHeaterTick or now - aquariumController.lastHeaterTick >= 1 then
    aquariumController.lastHeaterTick=now
    aquariumController.tickHeater(now)
  end

  -- Never use or equip items from OnUpdate: these APIs are protected in WoW Forever.
  if active and characterSettings.autoBait and now > baitRetryAt then
    baitRetryAt = now + 12
    adviseBait()
  end

  if now-lastPriceCheck>45 then
    lastPriceCheck=now
    local was=auctionPriceProvider
    detectPriceSource()
    if auctionPriceProvider or was then updateFishValue() end
  end
  -- Recover from missing/nonstandard spellcast events on WoW Forever.
  -- UnitChannelInfo is authoritative whenever it exposes the Fishing channel.
  if active then
    local begin, duration=channelInfo()
    if begin then
      lastChannelSeen=now
      if not casting then
        lastFishingSignal=now
        setCast(true, begin, duration)
      end
    elseif casting and activeCastEnd <= now then
      setCast(false)
    end
  end

  -- Survival must continue while the tank is hidden, but only at 1 Hz.
  if not aquariumController.nextSurvivalTick or now >= aquariumController.nextSurvivalTick then
    aquariumController.nextSurvivalTick = now + 1
    updateFishSurvival(now)
  end

  -- Hide an unmatched cast timer after its short grace period expires.
  if aquariumController.timerGraceUntil and now >= aquariumController.timerGraceUntil then
    aquariumController.timerGraceUntil = nil
    if updateStatus then updateStatus() end
  end
  -- The bobber timer has its own visibility and can animate with a hidden tank.
  if tankVisible or (castTimerWindow and castTimerWindow:IsShown()) then
    updateFishVisuals(now)
  end
  if tankVisible then
    local decorInterval = characterSettings.lowImpactMode and 0.2 or 0.1
    if not aquariumController.nextDecorTick or now >= aquariumController.nextDecorTick then
      local decorElapsed = clamp(now - (aquariumController.lastDecorTick or now - 0.1), 0.01, 0.25)
      aquariumController.lastDecorTick = now
      aquariumController.nextDecorTick = now + decorInterval
      updateAquariumDecor(now, decorElapsed)
      -- Preserve smooth heater glow without calculating the thermal simulation.
      if aquariumController.updateHeaterDisplay then aquariumController.updateHeaterDisplay(now) end
    end
    animateTreasureDrop(heartbeatElapsed)
    animateSplash(now)
  end
  -- The catch card can be visible even when the aquarium is hidden.
  if flyingCatchIcon and flyingCatchIcon:IsShown() then animateCatchFlight(heartbeatElapsed) end
  if catchRevealWindow and catchRevealWindow:IsShown() then
    if queuedCatch and previewClock>=3.05 and (not flyingCatchIcon or not flyingCatchIcon:IsShown()) then
      -- If the aquarium is hidden, finish this reveal without retrying the flight.
      if not startCatchFlight() then
        queuedCatch=nil
        if aquariumController.finishBobberHandoff then aquariumController.finishBobberHandoff() end
        if arrivingFishFrame then arrivingFishFrame:Show() end
        arrivingFishFrame,arrivingFishItemID=nil,nil
      end
    end
    previewClock=previewClock+heartbeatElapsed
    local left=catchPreviewEnds-now
    if left <= 0 then
      catchRevealWindow:Hide()
      if aquariumController.finishBobberHandoff and not (flyingCatchIcon and flyingCatchIcon:IsShown()) then
        aquariumController.finishBobberHandoff()
      end
    else
      local fadeIn=clamp(previewClock/0.35,0,1)
      local fadeOut=clamp(left/0.8,0,1)
      local handoff=1-clamp((previewClock-3.08)/1.0,0,1)
      catchRevealWindow:SetAlpha(math.min(fadeIn,fadeOut,handoff))
      -- Subtle slide in with an ease-out; fixed camera remains fully playable.
      local slide=(1-fadeIn)*(1-fadeIn)*28 + math.sin(previewClock*13)*math.exp(-previewClock*4)*5
      catchRevealWindow:ClearAllPoints()
      catchRevealWindow:SetPoint('TOP',UIParent,'TOP',0,-130+slide)
      if catchRevealWindow.sparkle then catchRevealWindow.sparkle:SetAlpha(0.4+math.sin(previewClock*4)*0.28) end
      if catchRevealWindow.trophyFrame then
        catchRevealWindow.trophyFrame:ClearAllPoints()
        catchRevealWindow.trophyFrame:SetPoint('LEFT',catchRevealWindow,'LEFT',14,-7+math.sin(previewClock*4.6)*3)
      end
      if catchRevealWindow.ripples then
        for i,r in ipairs(catchRevealWindow.ripples) do
          local phase=(previewClock*0.55+(i-1)/3)%1
          local sz=78+phase*53
          r:SetSize(sz,sz)
          r:SetAlpha((1-phase)*0.24)
        end
      end
      if catchRevealWindow.shineBar then
        catchRevealWindow.shineBar:ClearAllPoints()
        catchRevealWindow.shineBar:SetPoint('LEFT',catchRevealWindow,'LEFT',-15+(previewClock%2.2)*240,0)
        catchRevealWindow.shineBar:SetAlpha((previewClock<2.5) and (0.11+math.sin(previewClock*9)*.07) or 0)
      end
    end
  end

  -- Follow the final position of the preview card or the flying fish.
  if aquariumController.animateBobberHandoff then aquariumController.animateBobberHandoff(heartbeatElapsed) end

  -- Pulse only the selected icon within the existing capped heartbeat.
  local highlighted = aquariumController.highlightFishFrame
  if highlighted and highlighted.icon then
    if aquariumWindow and aquariumWindow:IsShown() and highlighted:IsShown() then
      highlighted.icon:SetAlpha(.32 + .68 * (.5 + .5 * math.sin(now * 12)))
    else
      aquariumController.clearJournalFlash()
    end
  end

  if aquariumWindow and aquariumWindow.roster and aquariumWindow.roster:IsShown() then
    if not aquariumController.nextRosterUpdate or now>=aquariumController.nextRosterUpdate then
      aquariumController.nextRosterUpdate=now+2
      if aquariumController.renderFishRoster then aquariumController.renderFishRoster() end
    end
  end
end

-- ============================================================================
-- Minimap control
-- Persistent minimap docking, drag behavior and click commands.
-- ============================================================================
-- Positions the minimap icon using its saved polar angle.
local function setMinimapPosition()
  if not minimapButton or not Minimap then return end
  local a=math.rad(characterSettings.minimapAngle or 225)
  minimapButton:ClearAllPoints()
  minimapButton:SetPoint('CENTER',Minimap,'CENTER',math.cos(a)*78,math.sin(a)*78)
  minimapButton:SetShown(characterSettings.showMinimapIcon ~= false)
end

-- Adds the movable minimap button and its tooltip actions.
local function createMinimapButton()
  if not Minimap then return end
  local b=CreateFrame('Button','VibeFishinMinimapButton',Minimap)
  b:SetSize(31,31)
  b:SetFrameStrata('MEDIUM')
  b:RegisterForClicks('LeftButtonUp','RightButtonUp')
  local icon=b:CreateTexture(nil,'ARTWORK')
  icon:SetPoint('CENTER')
  icon:SetSize(20,20)
  icon:SetTexture('Interface\\Icons\\INV_Misc_Fish_02')
  icon:SetTexCoord(.08,.92,.08,.92)
  -- Custom centered border: Blizzard's TrackingBorder art has an
  -- asymmetric transparent canvas, which made the icon look displaced.
  local ring=b:CreateTexture(nil,'OVERLAY')
  ring:SetSize(31,31)
  ring:SetPoint('CENTER',b,'CENTER',0,0)
  ring:SetTexture('Interface\\AddOns\\VibeFishin\\Media\\MinimapRing')
  b:SetScript('OnClick',function(_,button)
    if button=='RightButton' then
      if optionsWindow and optionsWindow.Refresh then optionsWindow:Refresh() end
      optionsWindow:SetShown(not optionsWindow:IsShown())
    else
      characterSettings.catchPanel=not characterSettings.catchPanel
      -- Left click always opens the tank, including outside fishing mode.
      if characterSettings.catchPanel then characterSettings.alwaysShowAquarium=true end
      updateStatus()
      if optionsWindow and optionsWindow.Refresh then optionsWindow:Refresh() end
    end
  end)
  b:SetScript('OnEnter',function(self)
    GameTooltip:SetOwner(self,'ANCHOR_LEFT')
    GameTooltip:AddLine('VibeFishin',0.45,0.94,0.85)
    GameTooltip:AddLine('Left-click: Show / hide aquarium',1,1,1)
    GameTooltip:AddLine('Right-click: Open options',1,1,1)
    GameTooltip:AddLine('Drag: Move minimap button',0.65,0.83,0.78)
    GameTooltip:Show()
  end)
  b:SetScript('OnLeave',function() GameTooltip:Hide() end)
  b:RegisterForDrag('LeftButton')
  b:SetScript('OnDragStart',function(self) self.dragging=true end)
  b:SetScript('OnDragStop',function(self) self.dragging=false end)
  b:SetScript('OnUpdate',function(self)
    if not self.dragging then return end
    local mx,my=Minimap:GetCenter()
    local cx,cy=GetCursorPosition()
    local scale=UIParent:GetEffectiveScale() or 1
    cx,cy=cx/scale,cy/scale
    local dx,dy=cx-mx,cy-my
    local angle=math.atan2 and math.atan2(dy,dx) or math.atan(dy/(math.abs(dx)<0.001 and 0.001 or dx))
    if not math.atan2 and dx<0 then angle=angle+math.pi end
    characterSettings.minimapAngle=angle*180/math.pi
    setMinimapPosition()
  end)
  minimapButton=b
  setMinimapPosition()
end

aquariumController:SetScript('OnUpdate', update)
aquariumController:RegisterEvent('ADDON_LOADED')
aquariumController:RegisterEvent('PLAYER_ENTERING_WORLD')
aquariumController:RegisterEvent('PLAYER_EQUIPMENT_CHANGED')
aquariumController:RegisterEvent('UNIT_SPELLCAST_SENT')
aquariumController:RegisterEvent('UNIT_SPELLCAST_START')
aquariumController:RegisterEvent('UNIT_SPELLCAST_STOP')
aquariumController:RegisterEvent('UNIT_SPELLCAST_CHANNEL_START')
aquariumController:RegisterEvent('UNIT_SPELLCAST_CHANNEL_STOP')
aquariumController:RegisterEvent('UNIT_SPELLCAST_INTERRUPTED')
aquariumController:RegisterEvent('CHAT_MSG_LOOT')
aquariumController:RegisterEvent('BAG_UPDATE_DELAYED')
for _, eventName in ipairs({'TRADE_SKILL_SHOW','TRADE_SKILL_LIST_UPDATE','TRADE_SKILL_DATA_SOURCE_CHANGED','NEW_RECIPE_LEARNED'}) do
  pcall(aquariumController.RegisterEvent, aquariumController, eventName)
end

aquariumController:SetScript('OnEvent', function(_, event, ...)
  if event == 'ADDON_LOADED' then
    local name = ...
    if name ~= 'VibeFishin' then return end
    VibeFishinDB = VibeFishinDB or {}
    characterSettings = VibeFishinDB
    -- V3 intentionally starts fresh fish records; preserve UI preferences.
    -- No lossy conversion of old per-species-slot identities is attempted.
    if characterSettings.schemaVersion ~= 3 then
      characterSettings.nextResidentID=0
      characterSettings.residents={}
      characterSettings.bagResidents={}
      characterSettings.catchJournal={species={},achievements={},totalCaught=0,rarestQuality=1}
      characterSettings.catches={}
      characterSettings.deadFish={}
      characterSettings.fishNames=nil
      characterSettings.total=0
      characterSettings.schemaVersion=3
    end
    copyDefaults(characterSettings, defaults)
    if not aquariumController.themePalettes[characterSettings.themeID] then characterSettings.themeID='abyss' end
    characterSettings.realism = nil -- discard retired preference from older saves
    characterSettings.catches = characterSettings.catches or {}
    characterSettings.residents = characterSettings.residents or {}
    characterSettings.bagResidents = characterSettings.bagResidents or {}
    characterSettings.catchJournal = characterSettings.catchJournal or {species={}, achievements={}, totalCaught=0, rarestQuality=1}
    characterSettings.catchJournal.species = characterSettings.catchJournal.species or {}
    characterSettings.catchJournal.achievements = characterSettings.catchJournal.achievements or {}
    -- Clean up Sharpening Wheels mistakenly captured by an older build.
    for i = #characterSettings.catches, 1, -1 do
      local c = characterSettings.catches[i]
      if c and excludedFishIDs[c.id] then
        characterSettings.total = math.max(0, (characterSettings.total or 0) - (c.count or 1))
        table.remove(characterSettings.catches, i)
      end
    end
    characterSettings.treasures = characterSettings.treasures or {}
    characterSettings.plants = characterSettings.plants or {}
    characterSettings.fishingLootIDs = characterSettings.fishingLootIDs or {}
    characterSettings.cookableReagents = characterSettings.cookableReagents or {}
    cookingIngredients = characterSettings.cookableReagents
    cookingRecipesReady = next(cookingIngredients) ~= nil
    characterSettings.heaterPower=clamp(tonumber(characterSettings.heaterPower) or 25,0,100)
    aquariumController.fishVitality=clamp(tonumber(characterSettings.fishVitality) or 100,0,100)
    aquariumController.zoneAmbient=aquariumController.getZoneAmbient()
    aquariumController.waterTemp=aquariumController.zoneAmbient+characterSettings.heaterPower*.33
    characterSettings.width = clamp(tonumber(characterSettings.width) or 440,MIN_TANK_WIDTH,720)
    characterSettings.height = clamp(tonumber(characterSettings.height) or 310,MIN_TANK_HEIGHT,560)
    if type(characterSettings.opacity) ~= 'number' then characterSettings.opacity = defaults.opacity end
    buildChamber()
    buildIndicator()
    buildCatchPreview()
    buildWelcome()
    buildSettings()
    detectPriceSource()
    createMinimapButton()
    registerOptionsCategory()
    repopulateAquarium()
    updateStatus()
    if not characterSettings.welcome then welcome:Show() else welcome:Hide() end
    say('Ready. /vfish opens options, /vfish toggle enables fishing mode.')
  elseif not characterSettings then
    return
  elseif event == 'TRADE_SKILL_SHOW' or event == 'TRADE_SKILL_LIST_UPDATE' or event == 'TRADE_SKILL_DATA_SOURCE_CHANGED' or event == 'NEW_RECIPE_LEARNED' then
    scanCookingRecipes(true)
  elseif event == 'PLAYER_EQUIPMENT_CHANGED' then
    if characterSettings.autoPoleDetect then
      if currentlyEquipped() then startFishing(true) elseif active and not manual then stopFishing() end
    end
  elseif event == 'UNIT_SPELLCAST_CHANNEL_START' or event == 'UNIT_SPELLCAST_CHANNEL_STOP' or event == 'UNIT_SPELLCAST_INTERRUPTED' or event == 'UNIT_SPELLCAST_START' or event == 'UNIT_SPELLCAST_SENT' or event == 'UNIT_SPELLCAST_STOP' then
    eventCast(event, ...)
    if event == 'UNIT_SPELLCAST_CHANNEL_STOP' then aquariumController.lastCast = GetTime and GetTime() or 0 end
  elseif event == 'BAG_UPDATE_DELAYED' or event == 'BAG_UPDATE' then
    local t=GetTime and GetTime() or 0
    if t-lastBagRefresh>1 then
      lastBagRefresh=t
      if characterSettings.inventoryFish then repopulateAquarium('preserve')
      else
        repopulateTreasures()
        repopulatePlants()
        if characterSettings.showFishValue and updateFishValue then updateFishValue() end
      end
    end
  elseif event == 'CHAT_MSG_LOOT' then
    onLoot(...)
  elseif event == 'PLAYER_ENTERING_WORLD' then
    if active then stopFishing() end
    if characterSettings.inventoryFish then repopulateAquarium() end
    if updateFishValue then updateFishValue() end
  end
end)

SLASH_VIBEFISHIN1 = '/vfish'
SLASH_VIBEFISHIN2 = '/vibefishin'
SlashCmdList.VIBEFISHIN = function(msg)
  if not characterSettings then return end
  msg = (msg or ''):lower():match('^%s*(.-)%s*$')
  if msg == 'toggle' then
    toggleFishing()
  elseif msg == 'on' then
    startFishing(false)
  elseif msg == 'off' then
    stopFishing()
  elseif msg == 'welcome' then
    welcome:Show()
  elseif msg == 'macro' then
    createMacro()
  elseif msg == 'reset' then
    characterSettings.total = 0
    wipeTable(characterSettings.catches)
    wipeTable(characterSettings.residents)
    wipeTable(characterSettings.bagResidents)
    wipeTable(characterSettings.treasures)
    wipeTable(characterSettings.deadFish or {})
    repopulateAquarium()
  elseif msg == 'chesttest' then
    if aquariumWindow and not aquariumWindow:IsShown() then aquariumWindow:Show() end
    startTreasureDrop(6351) -- cosmetic test; creates no saved treasure
    say('Decorative chest sink test started (no loot added).')
  elseif msg == 'preview' then
    characterSettings.catchPreview=true
    if optionsWindow and optionsWindow.Refresh then optionsWindow:Refresh() end
    aquariumController.lastCaughtResident=nil
    revealCatch(6291,1,'|Hitem:6291::::::::|h[Raw Brilliant Smallfish]|h')
    say('Preview test launched. Enable aquarium display to see the icon transfer.')
  elseif msg == 'theme' then
    if optionsWindow then
      optionsWindow:Show()
      if optionsWindow.activatePage then optionsWindow.activatePage(6) end
    end
  elseif msg:match('^theme%s+') then
    local selected=msg:match('^theme%s+([%w_]+)')
    if selected and aquariumController.themePalettes[selected] then
      characterSettings.themeID=selected
      aquariumController.applyTheme()
      say('Theme: '..aquariumController.currentTheme().name)
    else
      say('Available: '..table.concat(aquariumController.themeOrder,', '))
    end
  elseif msg == 'timer' then
    if not active then startFishing(false) end
    if characterSettings.showTimer ~= true then characterSettings.showTimer = true end
    lastFishingSignal=GetTime and GetTime() or now
    setCast(true, nil, 22)
    say('Showing 22-second cast timer test.')
  elseif msg == 'feed' then
    feedAquarium()
  elseif msg == 'journal' then
    if aquariumWindow then aquariumWindow:Show() end
    if aquariumWindow and aquariumWindow.roster then
      aquariumWindow.roster:Show()
      aquariumWindow.roster.showJournal=true
      if aquariumController.renderFishRoster then aquariumController.renderFishRoster() end
    end
  elseif msg == 'recipes' or msg == 'cooking' then
    scanCookingRecipes(false)
  elseif msg == 'refresh' then
    detectPriceSource()
    repopulateAquarium()
    updateFishValue()
  elseif msg == 'value' then
    detectPriceSource()
    updateFishValue()
    say(auctionPriceProvider and ('Fish price source: '..auctionPriceProvider) or 'No supported auction price addon API detected.')
  elseif msg == 'bait' or msg == 'baitmacro' then
    prepareBaitMacro()
  else
    if optionsWindow and optionsWindow.Refresh then optionsWindow:Refresh() end
    optionsWindow:SetShown(not optionsWindow:IsShown())
  end
end