-- QuickHoverBind para WoW Forever
-- Permite bindear pasando el raton por las barras de accion y pulsando una tecla

local ADDON_NAME = "QuickHoverBind"
local isActive = false

QuickHoverBindDB = QuickHoverBindDB or { minimapAngle = 210 }

local frame = CreateFrame("Frame", "QuickHoverBindFrame", UIParent)
frame:SetAllPoints(UIParent)
frame:SetFrameStrata("DIALOG")
frame:EnableKeyboard(true)
frame:EnableMouseWheel(true)
frame:Hide()

if frame.SetPropagateKeyboardInput then
    frame:SetPropagateKeyboardInput(false)
end

-- Formatear texto para mostrar en el boton (ej: s-R, a-1, WU)
local function FormatKeyDisplay(key)
    if not key or key == "" then return "" end
    local text = key
    text = text:gsub("SHIFT%-", "s-")
    text = text:gsub("CTRL%-", "c-")
    text = text:gsub("ALT%-", "a-")
    text = text:gsub("NUMPAD", "N")
    text = text:gsub("MOUSEWHEELUP", "WU")
    text = text:gsub("MOUSEWHEELDOWN", "WD")
    text = text:gsub("BUTTON3", "M3")
    text = text:gsub("BUTTON4", "M4")
    text = text:gsub("BUTTON5", "M5")
    return text
end

-- Resolver el comando de bindeo de Blizzard para cualquier boton
local function GetButtonAction(btn)
    if not btn then return nil end
    if btn.commandName then return btn.commandName end
    if btn.bindingAction then return btn.bindingAction end

    local name = btn.GetName and btn:GetName()
    if not name then return nil end

    local a = name:match("^ActionButton(%d+)$")
    if a then return "ACTIONBUTTON" .. a end

    local m1 = name:match("^MultiBarBottomLeftButton(%d+)$")
    if m1 then return "MULTIACTIONBAR1BUTTON" .. m1 end

    local m2 = name:match("^MultiBarBottomRightButton(%d+)$")
    if m2 then return "MULTIACTIONBAR2BUTTON" .. m2 end

    local m3 = name:match("^MultiBarRightButton(%d+)$")
    if m3 then return "MULTIACTIONBAR3BUTTON" .. m3 end

    local m4 = name:match("^MultiBarLeftButton(%d+)$")
    if m4 then return "MULTIACTIONBAR4BUTTON" .. m4 end

    local m5 = name:match("^MultiBar5Button(%d+)$")
    if m5 then return "MULTIACTIONBAR5BUTTON" .. m5 end

    local m6 = name:match("^MultiBar6Button(%d+)$")
    if m6 then return "MULTIACTIONBAR6BUTTON" .. m6 end

    local m7 = name:match("^MultiBar7Button(%d+)$")
    if m7 then return "MULTIACTIONBAR7BUTTON" .. m7 end

    local pet = name:match("^PetActionButton(%d+)$")
    if pet then return "BONUSACTIONBUTTON" .. pet end

    local stance = name:match("^StanceButton(%d+)$") or name:match("^ShapeshiftButton(%d+)$")
    if stance then return "SHAPESHIFTBUTTON" .. stance end

    if GetBindingAction then
        local bAction = GetBindingAction(name)
        if bAction and bAction ~= "" then return bAction end
    end

    return nil
end

-- Determinar el boton bajo el cursor (incluso si hay capas encima como GlowingBars o Cooldown)
local function GetHoveredButton()
    local focus
    if GetMouseFoci then
        local foci = GetMouseFoci()
        focus = foci and foci[1]
    end
    if not focus and GetMouseFocus then
        focus = GetMouseFocus()
    end
    if not focus or focus == WorldFrame or focus == UIParent or focus == frame then
        return nil
    end

    -- Si el cursor apunta a un overlay, brillo o marco hijo, subimos al padre
    local current = focus
    while current and current ~= UIParent and current ~= WorldFrame do
        if GetButtonAction(current) then
            return current
        end
        current = current.GetParent and current:GetParent()
    end

    return focus
end

local function GetCurrentKeys(action)
    local k1, k2 = GetBindingKey(action)
    if k1 and k2 then
        return k1 .. ", " .. k2
    elseif k1 then
        return k1
    end
    return "Ninguna"
end

-- Lista exhaustiva de prefijos de barras de accion de WoW Forever
local ALL_BAR_PREFIXES = {
    { prefix = "ActionButton",              count = 12 },
    { prefix = "MultiBarBottomLeftButton",  count = 12 },
    { prefix = "MultiBarBottomRightButton", count = 12 },
    { prefix = "MultiBarRightButton",       count = 12 },
    { prefix = "MultiBarLeftButton",        count = 12 },
    { prefix = "MultiBar5Button",           count = 12 },
    { prefix = "MultiBar6Button",           count = 12 },
    { prefix = "MultiBar7Button",           count = 12 },
    { prefix = "PetActionButton",           count = 10 },
    { prefix = "StanceButton",              count = 10 },
    { prefix = "ShapeshiftButton",          count = 10 },
    { prefix = "PossessButton",             count = 10 },
}

-- Fuerza directamente el texto HotKey de un boton segun GetBindingKey.
-- NO llama a ActionButton_UpdateHotkeys porque ese sistema usa una cache interna
-- que puede devolver valores obsoletos y sobreescribir nuestra limpieza.
local function UpdateSingleButtonVisual(btn)
    if not btn then return end

    local action = GetButtonAction(btn)
    local k1 = action and GetBindingKey(action)
    local name = btn.GetName and btn:GetName()

    local hotkey = btn.HotKey or (name and _G[name .. "HotKey"])
    if hotkey then
        if k1 and k1 ~= "" then
            hotkey:SetText(FormatKeyDisplay(k1))
            hotkey:Show()
        else
            hotkey:SetText("")
            hotkey:Hide()
        end
    end
end

-- Refresca TODOS los botones de TODAS las barras de golpe
local function RefreshAllActionBars()
    for _, info in ipairs(ALL_BAR_PREFIXES) do
        for i = 1, info.count do
            local b = _G[info.prefix .. i]
            if b then UpdateSingleButtonVisual(b) end
        end
    end
end

-- Mensaje en pantalla flotante / barra de estado
local promptFrame = CreateFrame("Frame", "QuickHoverBindPrompt", UIParent, "BackdropTemplate")
promptFrame:SetSize(390, 65)
promptFrame:SetPoint("TOP", UIParent, "TOP", 0, -40)
promptFrame:SetFrameStrata("TOOLTIP")
promptFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
promptFrame:SetBackdropColor(0, 0, 0, 0.85)

local promptText = promptFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
promptText:SetPoint("TOP", promptFrame, "TOP", 0, -8)
promptText:SetText("|cff00ff00[QuickHoverBind ACTIVO]|r")

local promptSub = promptFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
promptSub:SetPoint("CENTER", promptFrame, "CENTER", 0, -8)
promptSub:SetText("Pasa el raton por un boton y pulsa una tecla\nESC o Supr: Borrar bindeo | Clic en minimapa para salir")
promptFrame:Hide()

-- Declaracion adelantada del boton del minimapa
local minimapBtn, UpdateMinimapVisual

local function ToggleHoverBind()
    if InCombatLockdown and InCombatLockdown() then
        print("|cffff0000[QuickHoverBind]|r No puedes modificar teclas en combate.")
        return
    end

    isActive = not isActive
    if isActive then
        frame:Show()
        promptFrame:Show()
        RefreshAllActionBars()
        print("|cff00ff00[QuickHoverBind]|r Modo rapido |cff00ff00ACTIVADO|r. Pasa el raton sobre la casilla y pulsa la tecla para sustituirla (ESC para borrar).")
    else
        frame:Hide()
        promptFrame:Hide()
        RefreshAllActionBars()
        print("|cffffaa00[QuickHoverBind]|r Modo rapido |cffff0000DESACTIVADO|r. Cambios guardados.")
    end

    if UpdateMinimapVisual then
        UpdateMinimapVisual()
    end
end

local function HandleKey(key)
    if not isActive then return end

    -- Ignorar teclas de sistema y modificadores sueltos
    if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" 
       or key == "LALT" or key == "RALT" or key == "LMETA" or key == "RMETA" 
       or key == "UNKNOWN" then
        return
    end

    local btn = GetHoveredButton()
    local action = btn and GetButtonAction(btn)

    -- Borrar bindeo con ESCAPE o SUPR/DELETE/BACKSPACE
    local isClearKey = (key == "ESCAPE" or key == "DELETE" or key == "BACKSPACE") 
                       and not IsShiftKeyDown() and not IsControlKeyDown() and not IsAltKeyDown()

    if isClearKey then
        if btn and action then
            -- Borrar todas las teclas existentes de ese boton
            local k1, k2 = GetBindingKey(action)
            if k1 then SetBinding(k1, nil) end
            if k2 then SetBinding(k2, nil) end
            SaveBindings(GetCurrentBindingSet())
            RefreshAllActionBars()
            print("|cffff5555[QuickHoverBind]|r Bindeo borrado de: |cffffffff" .. (btn:GetName() or action) .. "|r")
        else
            -- Si pulsa ESC sin apuntar a nada, sale del modo
            ToggleHoverBind()
        end
        return
    end

    if not action then
        return
    end

    -- Construir la combinacion con modificadores
    local fullKey = ""
    if IsAltKeyDown() then fullKey = fullKey .. "ALT-" end
    if IsControlKeyDown() then fullKey = fullKey .. "CTRL-" end
    if IsShiftKeyDown() then fullKey = fullKey .. "SHIFT-" end
    fullKey = fullKey .. key

    -- 1. Quitar las teclas viejas que tenia este boton
    local old1, old2 = GetBindingKey(action)
    if old1 then SetBinding(old1, nil) end
    if old2 then SetBinding(old2, nil) end

    -- 2. Asignar la nueva tecla como principal
    SetBinding(fullKey, action)
    SaveBindings(GetCurrentBindingSet())

    -- 3. Refrescar todas las barras: limpia la letra del boton antiguo y pone la nueva
    RefreshAllActionBars()

    print("|cff00ff00[QuickHoverBind]|r Asignada |cffffd100" .. fullKey .. "|r a |cffffffff" .. (btn:GetName() or action) .. "|r")
end

frame:SetScript("OnKeyDown", function(self, key)
    HandleKey(key)
end)

frame:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then
        HandleKey("MOUSEWHEELUP")
    else
        HandleKey("MOUSEWHEELDOWN")
    end
end)

-- Actualizar texto en tiempo real segun donde apunta el cursor
local elapsed = 0
frame:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed < 0.05 then return end
    elapsed = 0

    local btn = GetHoveredButton()
    local action = btn and GetButtonAction(btn)
    if action then
        local btnName = btn:GetName() or "Boton"
        local current = GetCurrentKeys(action)
        promptSub:SetText("|cffffff00" .. btnName .. "|r (Actual: |cffffffff" .. current .. "|r)\nPulsa tecla para ASIGNAR | ESC para borrar")
    else
        promptSub:SetText("Pasa el raton por un boton de barra de accion\nESC fuera de barra o clic en minimapa para salir")
    end
end)

---------------------------------------------------------------------------
-- BOTON DEL MINIMAPA
---------------------------------------------------------------------------
minimapBtn = CreateFrame("Button", "QuickHoverBindMinimapButton", Minimap)
minimapBtn:SetSize(32, 32)
minimapBtn:SetFrameStrata("MEDIUM")
minimapBtn:SetFrameLevel(8)
minimapBtn:EnableMouse(true)
minimapBtn:RegisterForClicks("AnyUp")
minimapBtn:RegisterForDrag("LeftButton", "RightButton")

local mIcon = minimapBtn:CreateTexture(nil, "BACKGROUND")
mIcon:SetTexture("Interface\\Icons\\INV_Misc_Gear_02")
mIcon:SetSize(20, 20)
mIcon:SetPoint("CENTER", 0, 0)
mIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local mBorder = minimapBtn:CreateTexture(nil, "OVERLAY")
mBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mBorder:SetSize(53, 53)
mBorder:SetPoint("TOPLEFT", 0, 0)

minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local function UpdateMinimapPosition()
    local angle = (QuickHoverBindDB and QuickHoverBindDB.minimapAngle) or 210
    local rad = math.rad(angle)
    local radius = (Minimap:GetWidth() / 2) + 10
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

UpdateMinimapVisual = function()
    if isActive then
        mBorder:SetVertexColor(0, 1, 0) -- Verde brillante cuando este activo
        mIcon:SetVertexColor(0.2, 1, 0.2)
    else
        mBorder:SetVertexColor(1, 1, 1) -- Normal
        mIcon:SetVertexColor(1, 1, 1)
    end
end

minimapBtn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local angle = math.deg(math.atan2(cy - my, cx - mx))
        QuickHoverBindDB = QuickHoverBindDB or {}
        QuickHoverBindDB.minimapAngle = angle
        UpdateMinimapPosition()
    end)
end)

minimapBtn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)

minimapBtn:SetScript("OnClick", function(self, button)
    ToggleHoverBind()
end)

minimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff00ff00QuickHoverBind|r")
    GameTooltip:AddLine("Clic: |cffffffffActivar/Desactivar bindeo rápido|r", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Arrastrar: |cffffffffMover alrededor del minimapa|r", 0.8, 0.8, 0.8)
    if isActive then
        GameTooltip:AddLine("Estado: |cff00ff00ACTIVO|r (pulsa para salir)", 1, 1, 1)
    else
        GameTooltip:AddLine("Estado: |cffff5555INACTIVO|r (pulsa para bindear)", 1, 1, 1)
    end
    GameTooltip:Show()
end)

minimapBtn:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

-- Inicializar posición al cargar
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        QuickHoverBindDB = QuickHoverBindDB or { minimapAngle = 210 }
        UpdateMinimapPosition()
    elseif event == "PLAYER_LOGIN" then
        UpdateMinimapPosition()
        UpdateMinimapVisual()
        RefreshAllActionBars()
    end
end)

-- Comandos de chat
SLASH_QUICKHOVERBIND1 = "/hb"
SLASH_QUICKHOVERBIND2 = "/hoverbind"
SlashCmdList["QUICKHOVERBIND"] = function()
    ToggleHoverBind()
end
