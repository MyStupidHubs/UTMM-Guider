-- UTMM Guider | Matcha LuaVM + Wabi Sabi UI
-- A lógica de scan vem do UTMM Guider original; a interface antiga de Menu Binding foi removida.
-- Matcha error() apenas imprime; assert é necessário quando o script realmente precisa interromper.

local ENV = getfenv and getfenv(0) or _G
local previous = ENV.__UTMM_GUIDER_APP
if type(previous) == "table" and type(previous.Cleanup) == "function" then
    pcall(previous.Cleanup)
end

local App = {
    Version = "3.0.0",
    Config = {
        MaxResults = 50,
        ConfigFile = "utmm_guider.json",
        UILibraryUrl = "https://scripts.wabisabi.mom/wabi-sabi-ui-lib.lua",
        ProgressMinStepLevels = 3,
    },
    State = {
        Prefs = {},
        results = {}, count = 0, countKind = "found", messageKey = nil,
        status = "", progressWarning = nil,
        progressBlacklist = {}, progressBlacklistOrder = {},
        busy = false, scanned = false, stamp = 0,
        buildWeapon = nil, buildWeaponBoost = nil, buildArmor = nil,
        buildFood = nil, lastFoodScan = nil, resultCap = nil, fragDiag = nil,
    },
    Cache = {
        Config = {},
        Catalog = { battles=nil, index=nil, items=nil, sources=nil, guiRewards=nil, bosses=nil, frags=nil, player=nil, shopTargets=nil },
        Workspace = { Scan=nil, ShopWanted=nil },
        UISource = nil,
    },
    Blacklists = {
        Missing = { Map = {}, Order = {} },
        Food = { Map = {}, Order = {} },
    },
    Runtime = { Alive = true, PendingJob = nil },
    Matcha = {}, I18n = {}, Prefs = {}, Persistence = {}, Format = {}, Teleport = {},
    Reader = {}, Catalog = {}, Results = {}, Filters = {}, Features = {}, Build = {}, Food = {},
    Worker = {}, UI = {},
}
ENV.__UTMM_GUIDER_APP = App

App.Matcha.getService = function(name)
    local ok, s = pcall(function() return game:GetService(name) end)
    if ok then return s end
    return nil
end

local Players     = App.Matcha.getService("Players")
local Workspace   = App.Matcha.getService("Workspace") or workspace
local HttpService = App.Matcha.getService("HttpService")

local Lighting    = App.Matcha.getService("Lighting")

local LocalPlayer
do
    local ok, p = pcall(function() return Players.LocalPlayer end)
    if ok then LocalPlayer = p end
end


local MAX_RESULTS = App.Config.MaxResults
local CONFIG_FILE = App.Config.ConfigFile


local state = App.State


local CurrentLanguage = "PT"
local Translations = {
    PT = {
        Title = "UTMM Kit Scanner", Subtitle = "Farm Guider & Item Finder",
        YourStats = "SEUS STATS", Level = "LEVEL", Resets = "RESETS", TrueResets = "TRUE RESETS",
        Scanner = "Scanner", Farms = "Farms", SearchBoss = "Buscar", Top5 = "Top 5",
        BossesInReset = "Bosses no Reset", BossesInTrueReset = "Bosses no True Reset",
        IncludeFragments = "Incluir Fragmentos", UTMOHMaterials = "UTMOH Materials",
        Scan = "ESCANEAR", Searching = "Buscando...", Results = "RESULTADOS",
        Found = "encontrados", Best = "melhores", Search = "Pesquisar:",
        SearchPlaceholder = "Nome, Item, Soul, Comida ou Loja...", SearchHint = "Busca: Nome, Item, Soul, Comida ou Loja",
        SearchBtn = "BUSCAR", TypeSomething = "Digite algo", NoResults = "Nenhum",
        FoundResults = "achados!", Items = "itens!",
        GoldGlobal = "Gold (Global)", GoldLvl1 = "Gold (Lvl 1)",
        ExpGlobal = "EXP (Global)", ExpLvl1 = "EXP (Lvl 1)",

        FarmGold = "MELHORES PARA GOLD", FarmExp = "MELHORES PARA EXP",
        FarmDesc = "Usa LEVEL + Reset/TR dos seus stats ou os filtros Min/Max preenchidos",
        NoRewards = "Sem recompensas", NoSpecialRewards = "Sem recompensas especiais",
        Item = "Item", Soul = "Soul", TP = "TP", OK = "OK",
        FragmentChance = "Chance do Fragmento",
        Permanent = "Permanente", TruePermanent = "True Permanent",
        Loaded = "UTMM Kit Scanner carregado!",
        Top5Title = "TOP 5 BOSSES MAIS DIFICEIS", Top5Desc = "Bosses com maiores requisitos",
        Top5Scan = "SCAN TOP 5", ByCombined = "Combinado", ByTrueReset = "Por TR",
        ByReset = "Por Reset", ByLevel = "Por Level",
        FilterReset = "RESET", FilterTR = "TRUE RESET",

        SortBy = "Ordenar", Source = "Origem", TPFail = "Alvo sem posicao (TP falhou)",
        Refresh = "ATUALIZAR LISTA",

        Progress = "Progressão", GenRoute = "GERAR ROTA",
        ProgressDesc = "Rota de farm do Lv 1 até seu LEVEL alvo",
        Steps = "etapas até o Lv", SetLevel = "Defina o LEVEL alvo nos seus stats",
        NoneEligible = "Nenhum boss elegível encontrado",
        StartGap = "Sem boss elegível antes do Lv",

        Blacklist = "BLACKLIST", RemoveBlacklist = "REMOVER BLACKLIST",
        BlacklistTitle = "BLACKLIST DA PROGRESSÃO", BlacklistEmpty = "Nenhum boss na blacklist",

        Build = "Build", BuildScan = "ANALISAR BUILD",
        BuildDesc = "Lê suas armas/armaduras e aponta a melhor",
        BestWeapon = "Melhor Arma:", BestArmor = "Melhor Armadura:",

        BestWeaponConfirmed = "Melhor Arma (dano confirmado):",
        BestWeaponBoosted = "Melhor Arma (se DamageIncrease for aplicado):",
        BuildHypDamage = "Dano hipotético",
        BuildSameBoostWinner = "Também é a melhor considerando DamageIncrease",

        BestFood = "Melhor Comida:", FoodSection = "COMIDAS",
        FoodBest8 = "MELHORES 8 COMIDAS", FoodTierList = "TIERLIST DE COMIDAS",
        FoodBuildTitle = "BUILD DE 8 COMIDAS", FoodTierTitle = "TIERLIST DE COMIDAS",
        FoodHeal = "Cura", FoodCost = "Custo", FoodMax = "Máximo",
        FoodTotalHeal = "Cura total", FoodTotalCost = "Custo total",
        FoodSlots = "slots", FoodEach = "cada", FoodOnSale = "À venda",
        FoodYes = "Sim", FoodNo = "Não", FoodNotForSale = "NÃO ESTÁ À VENDA", FoodUnknownCost = "preço desconhecido",
        FoodNoValid = "Nenhuma comida válida encontrada",
        FoodBuildIncomplete = "Não foi possível preencher os 8 slots",
        FoodTierRule = "Tiers por cura relativa: S>=90%, A>=75%, B>=50%, C>=25%, D>0, F=0",
        FoodBlacklistTitle = "BLACKLIST DE COMIDAS",
        FoodBlacklistEmpty = "Nenhuma comida na blacklist",
        FoodClearBlacklist = "LIMPAR BLACKLIST DE COMIDAS",
        BuildWeapons = "SUAS ARMAS", BuildArmors = "SUAS ARMADURAS",
        BuildNoPlayer = "Pastas Weapons/Armor não encontradas no seu Player",
        BuildEmpty = "Nada encontrado", BuildNoData = "sem dados em Lighting",
        BuildAtLv = "no LV", BuildShow = "Mostrar",
        BuildSummary = "Só o resumo", BuildTop10 = "Top 10", BuildAll = "Tudo",
        BuildDmg = "Dano", BuildBase = "base", BuildPerLv = "/lv", BuildBoost = "DamageIncrease",
        BuildHP = "HP", BuildOwned = "possuídos",

        Shop = "Loja", Boss = "Boss", BossGuess = "Boss?", Frags = "Fragmentos",

        TPShop = "TP LOJA",
        TagShop = "[LOJA]", ShopItems = "Itens nessa loja",
        ShopPoints = "Pontos da loja", ShopPoint = "Part",
        ShopNoTP = "Nenhuma Part encontrada para essa loja",
        NoSource = "Sem fonte conhecida", Craft = "Craft",
        FragReady = "PRONTO", FragNeed = "faltam",
        TagWeapon = "[ARMA]", TagArmor = "[ARMADURA]", TagSoul = "[ALMA]", TagFood = "[COMIDA]",
        TagBoss = "[BOSS]", NoTP = "sem TP (só no Lighting)",

        MissingBtn = "O QUE FALTA", MissingAll = "Incluir sem fonte conhecida",
        MissingDesc = "Armas, armaduras, almas e comidas que você ainda não tem",
        MissingNone = "Você já tem tudo!", MissingCount = "faltando",
        MissingNoFolders = "Pastas Weapons/Armor/SOULs não encontradas",
        MissingTitle = "FALTA",
        MissBlacklistTitle = "BLACKLIST DOS FALTANTES", ClearBlacklist = "LIMPAR BLACKLIST",
        MissBlacklistEmpty = "Nenhum item na blacklist",
        SavedFor = "Salvo para o", NoPersist = "Sem writefile: a blacklist não sobrevive ao reexecutar",
        MissWeapons = "ARMAS", MissArmors = "ARMADURAS", MissSouls = "ALMAS", MissFoods = "COMIDAS",
    },
    EN = {
        Title = "UTMM Kit Scanner", Subtitle = "Farm Guider & Item Finder",
        YourStats = "YOUR STATS", Level = "LEVEL", Resets = "RESETS", TrueResets = "TRUE RESETS",
        Scanner = "Scanner", Farms = "Farms", SearchBoss = "Search", Top5 = "Top 5",
        BossesInReset = "Bosses in Reset", BossesInTrueReset = "Bosses in True Reset",
        IncludeFragments = "Include Fragments", UTMOHMaterials = "UTMOH Materials",
        Scan = "SCAN", Searching = "Searching...", Results = "RESULTS",
        Found = "found", Best = "best", Search = "Search:",
        SearchPlaceholder = "Name, Item, Soul, Food or Shop...", SearchHint = "Search: Name, Item, Soul, Food or Shop",
        SearchBtn = "SEARCH", TypeSomething = "Type something", NoResults = "None",
        FoundResults = "found!", Items = "items!",
        GoldGlobal = "Gold (Global)", GoldLvl1 = "Gold (Lvl 1)",
        ExpGlobal = "EXP (Global)", ExpLvl1 = "EXP (Lvl 1)",

        FarmGold = "BEST FOR GOLD", FarmExp = "BEST FOR EXP",
        FarmDesc = "Uses LEVEL + your Reset/TR, or filled Min/Max filters",
        NoRewards = "No rewards", NoSpecialRewards = "No special rewards",
        Item = "Item", Soul = "Soul", TP = "TP", OK = "OK",
        FragmentChance = "Fragment Chance",
        Permanent = "Permanent", TruePermanent = "True Permanent",
        Loaded = "UTMM Kit Scanner loaded!",
        Top5Title = "TOP 5 HARDEST BOSSES", Top5Desc = "Bosses with highest requirements",
        Top5Scan = "SCAN TOP 5", ByCombined = "Combined", ByTrueReset = "By TR",
        ByReset = "By Reset", ByLevel = "By Level",
        FilterReset = "RESET", FilterTR = "TRUE RESET",

        SortBy = "Sort by", Source = "Source", TPFail = "Target has no position (TP failed)",
        Refresh = "REFRESH LIST",

        Progress = "Progression", GenRoute = "GENERATE ROUTE",
        ProgressDesc = "Farm route from Lv 1 to your target LEVEL",
        Steps = "steps to Lv", SetLevel = "Set your target LEVEL in your stats",
        NoneEligible = "No eligible bosses found",
        StartGap = "No eligible boss before Lv",

        Blacklist = "BLACKLIST", RemoveBlacklist = "REMOVE BLACKLIST",
        BlacklistTitle = "PROGRESSION BLACKLIST", BlacklistEmpty = "No bosses blacklisted",

        Build = "Build", BuildScan = "ANALYZE BUILD",
        BuildDesc = "Reads your weapons/armors and points the best",
        BestWeapon = "Best Weapon:", BestArmor = "Best Armor:",

        BestWeaponConfirmed = "Best Weapon (confirmed damage):",
        BestWeaponBoosted = "Best Weapon (if DamageIncrease is applied):",
        BuildHypDamage = "Hypothetical damage",
        BuildSameBoostWinner = "Also the best when considering DamageIncrease",

        BestFood = "Best Food:", FoodSection = "FOODS",
        FoodBest8 = "BEST 8 FOODS", FoodTierList = "FOOD TIER LIST",
        FoodBuildTitle = "8-FOOD BUILD", FoodTierTitle = "FOOD TIER LIST",
        FoodHeal = "Heal", FoodCost = "Cost", FoodMax = "Max",
        FoodTotalHeal = "Total heal", FoodTotalCost = "Total cost",
        FoodSlots = "slots", FoodEach = "each", FoodOnSale = "On sale",
        FoodYes = "Yes", FoodNo = "No", FoodNotForSale = "NOT FOR SALE", FoodUnknownCost = "unknown price",
        FoodNoValid = "No valid food found",
        FoodBuildIncomplete = "Could not fill all 8 slots",
        FoodTierRule = "Tiers by relative heal: S>=90%, A>=75%, B>=50%, C>=25%, D>0, F=0",
        FoodBlacklistTitle = "FOOD BLACKLIST",
        FoodBlacklistEmpty = "No foods blacklisted",
        FoodClearBlacklist = "CLEAR FOOD BLACKLIST",
        BuildWeapons = "YOUR WEAPONS", BuildArmors = "YOUR ARMORS",
        BuildNoPlayer = "Weapons/Armor folders not found in your Player",
        BuildEmpty = "Nothing found", BuildNoData = "no data in Lighting",
        BuildAtLv = "at LV", BuildShow = "Show",
        BuildSummary = "Summary only", BuildTop10 = "Top 10", BuildAll = "Everything",
        BuildDmg = "Damage", BuildBase = "base", BuildPerLv = "/lv", BuildBoost = "DamageIncrease",
        BuildHP = "HP", BuildOwned = "owned",

        Shop = "Shop", Boss = "Boss", BossGuess = "Boss?", Frags = "Fragments",

        TPShop = "TP SHOP",
        TagShop = "[SHOP]", ShopItems = "Items in this shop",
        ShopPoints = "Shop points", ShopPoint = "Part",
        ShopNoTP = "No Part found for this shop",
        NoSource = "No known source", Craft = "Craft",
        FragReady = "READY", FragNeed = "need",
        TagWeapon = "[WEAPON]", TagArmor = "[ARMOR]", TagSoul = "[SOUL]", TagFood = "[FOOD]",
        TagBoss = "[BOSS]", NoTP = "no TP (Lighting only)",

        MissingBtn = "WHAT'S MISSING", MissingAll = "Include unknown sources",
        MissingDesc = "Weapons, armors, souls and foods you don't own yet",
        MissingNone = "You already have everything!", MissingCount = "missing",
        MissingNoFolders = "Weapons/Armor/SOULs folders not found",
        MissingTitle = "MISSING",
        MissBlacklistTitle = "MISSING-ITEMS BLACKLIST", ClearBlacklist = "CLEAR BLACKLIST",
        MissBlacklistEmpty = "No items blacklisted",
        SavedFor = "Saved for", NoPersist = "No writefile: blacklist won't survive a re-run",
        MissWeapons = "WEAPONS", MissArmors = "ARMORS", MissSouls = "SOULS", MissFoods = "FOODS",
    }
}
local Lang = Translations[CurrentLanguage]

local INPUT_IDS = {
    "utmm_level", "utmm_resets", "utmm_tr",
    "utmm_reset_min", "utmm_reset_max", "utmm_tr_min", "utmm_tr_max",
}

local WIDGET_DEFAULTS = {
    utmm_lang = 0,
    utmm_level = "0",
    utmm_resets = "0",
    utmm_tr = "0",
    utmm_reset_min = "0",
    utmm_reset_max = "",
    utmm_tr_min = "0",
    utmm_tr_max = "",
    utmm_search = "",
    utmm_exact_reset = false,
    utmm_exact_tr = false,
    utmm_include_frag = false,
    utmm_utmoh = false,
    utmm_top5_sort = 0,
    utmm_build_show = 1,
    utmm_missing_all = false,
}

local uiCache = App.State.Prefs

App.Prefs.inputDefault = function(id)
    local inputs = App.UI and App.UI.Inputs
    local handle = inputs and inputs[id] or nil
    if handle and type(handle.Value) == "string" then
        uiCache[id] = handle.Value
        return handle.Value
    end
    local v = uiCache[id]
    if type(v) == "string" then return v end
    local d = WIDGET_DEFAULTS[id]
    return type(d) == "string" and d or ""
end

App.Prefs.toggleDefault = function(id)
    local v = uiCache[id]
    if type(v) == "boolean" then return v end
    return WIDGET_DEFAULTS[id] == true
end

App.Prefs.comboDefault = function(id)
    local v = uiCache[id]
    if type(v) == "number" then return v end
    local d = WIDGET_DEFAULTS[id]
    return type(d) == "number" and d or 0
end

local getInput = App.Prefs.inputDefault
local getToggle = App.Prefs.toggleDefault

App.Prefs.getCombo = function(id, default)
    local v = uiCache[id]
    if type(v) == "number" then return v end
    return default or App.Prefs.comboDefault(id)
end

App.I18n.syncLanguage = function(idx)
    local want = (idx == 1) and "EN" or "PT"
    if want ~= CurrentLanguage then
        CurrentLanguage = want
        Lang = Translations[CurrentLanguage]
    end
end


local CAN_PERSIST = (type(writefile) == "function")
    and (type(readfile) == "function")
    and (type(isfile) == "function")

local PLACE_KEY
do

    
    local candidates = { "PlaceId", "GameId", "JobId" }
    for _, prop in ipairs(candidates) do
        local ok, v = pcall(function() return game[prop] end)
        if ok and (type(v) == "number" or type(v) == "string") then
            local sv = tostring(v)

            if sv ~= "" and sv ~= "0" and not string.find(string.lower(sv), "failed", 1, true) then
                PLACE_KEY = sv
                break
            end
        end
    end

    
    PLACE_KEY = PLACE_KEY or "unknown"
end


local configCache = App.Cache.Config


local missingBlacklist = App.Blacklists.Missing.Map
local missingBlacklistOrder = App.Blacklists.Missing.Order


local foodBlacklist = App.Blacklists.Food.Map
local foodBlacklistOrder = App.Blacklists.Food.Order

App.Persistence.serializeConfig = function()
    local data = {}
    for _, id in ipairs(INPUT_IDS) do
        data[id] = getInput(id)
    end

    local mb = {}
    if type(configCache.missing_blacklist) == "table" then
        for placeKey, list in pairs(configCache.missing_blacklist) do
            if type(list) == "table" then mb[placeKey] = list end
        end
    end
    mb[PLACE_KEY] = missingBlacklistOrder
    data.missing_blacklist = mb


    local fb = {}
    if type(configCache.food_blacklist) == "table" then
        for placeKey, list in pairs(configCache.food_blacklist) do
            if type(list) == "table" then fb[placeKey] = list end
        end
    end
    fb[PLACE_KEY] = foodBlacklistOrder
    data.food_blacklist = fb


    
    local pb = {}
    if type(configCache.progress_blacklist) == "table" then
        for placeKey, list in pairs(configCache.progress_blacklist) do
            if type(list) == "table" then pb[placeKey] = list end
        end
    end
    pb[PLACE_KEY] = state.progressBlacklistOrder
    data.progress_blacklist = pb

    return data
end

App.Persistence.saveConfig = function()
    if not HttpService or not CAN_PERSIST then return false end
    local data = App.Persistence.serializeConfig()
    configCache = data
    App.Cache.Config = data
    local ok, encoded = pcall(function() return HttpService:JSONEncode(data) end)
    if not ok or type(encoded) ~= "string" then return false end
    local okWrite = pcall(function() writefile(CONFIG_FILE, encoded) end)
    return okWrite
end

App.Persistence.loadConfig = function()
    if not HttpService or not CAN_PERSIST then return end
    local okExists, exists = pcall(function() return isfile(CONFIG_FILE) end)
    if not okExists or not exists then return end
    local okRead, raw = pcall(function() return readfile(CONFIG_FILE) end)
    if not okRead or type(raw) ~= "string" or raw == "" then return end
    local okDec, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not okDec or type(data) ~= "table" then return end

    configCache = data
    App.Cache.Config = data
    for _, id in ipairs(INPUT_IDS) do
        if type(data[id]) == "string" then uiCache[id] = data[id] end
    end


    local mb = data.missing_blacklist
    if type(mb) == "table" and type(mb[PLACE_KEY]) == "table" then
        for _, key in ipairs(mb[PLACE_KEY]) do
            if type(key) == "string" and key ~= "" and not missingBlacklist[key] then
                missingBlacklist[key] = true
                missingBlacklistOrder[#missingBlacklistOrder + 1] = key
            end
        end
    end


    local fb = data.food_blacklist
    if type(fb) == "table" and type(fb[PLACE_KEY]) == "table" then
        for _, key in ipairs(fb[PLACE_KEY]) do
            if type(key) == "string" and key ~= "" and not foodBlacklist[key] then
                foodBlacklist[key] = true
                foodBlacklistOrder[#foodBlacklistOrder + 1] = key
            end
        end
    end


    
    local pb = data.progress_blacklist
    if type(pb) == "table" and type(pb[PLACE_KEY]) == "table" then
        for _, name in ipairs(pb[PLACE_KEY]) do
            if type(name) == "string" and name ~= "" and not state.progressBlacklist[name] then
                state.progressBlacklist[name] = true
                state.progressBlacklistOrder[#state.progressBlacklistOrder + 1] = name
            end
        end
    end
end


local MISSING_KIND_TAG = { Weapons = "TagWeapon", Armor = "TagArmor", SOULs = "TagSoul", Food = "TagFood" }

App.Persistence.missingKey = function(kind, folderName)
    return tostring(kind) .. "/" .. tostring(folderName)
end


App.Persistence.missingBlacklistLabel = function(key)
    local kind, name = string.match(key, "^([^/]+)/(.+)$")
    if not kind then return key end
    local tagKey = MISSING_KIND_TAG[kind]
    return ((tagKey and Lang[tagKey]) or "") .. " " .. name
end

App.Persistence.addMissingBlacklist = function(key)
    if not key or key == "" or missingBlacklist[key] then return false end
    missingBlacklist[key] = true
    missingBlacklistOrder[#missingBlacklistOrder + 1] = key
    App.Persistence.saveConfig()
    return true
end

App.Persistence.removeMissingBlacklist = function(key)
    if not key or not missingBlacklist[key] then return false end
    missingBlacklist[key] = nil
    for i = #missingBlacklistOrder, 1, -1 do
        if missingBlacklistOrder[i] == key then
            table.remove(missingBlacklistOrder, i)
            break
        end
    end
    App.Persistence.saveConfig()
    return true
end

App.Persistence.clearMissingBlacklist = function()
    if #missingBlacklistOrder == 0 then return false end
    for key in pairs(missingBlacklist) do missingBlacklist[key] = nil end
    for i = #missingBlacklistOrder, 1, -1 do missingBlacklistOrder[i] = nil end
    App.Persistence.saveConfig()
    return true
end


App.Persistence.addFoodBlacklist = function(folderName)
    if not folderName or folderName == "" or foodBlacklist[folderName] then return false end
    foodBlacklist[folderName] = true
    foodBlacklistOrder[#foodBlacklistOrder + 1] = folderName
    App.Persistence.saveConfig()
    return true
end

App.Persistence.removeFoodBlacklist = function(folderName)
    if not folderName or not foodBlacklist[folderName] then return false end
    foodBlacklist[folderName] = nil
    for i = #foodBlacklistOrder, 1, -1 do
        if foodBlacklistOrder[i] == folderName then
            table.remove(foodBlacklistOrder, i)
            break
        end
    end
    App.Persistence.saveConfig()
    return true
end

App.Persistence.clearFoodBlacklist = function()
    if #foodBlacklistOrder == 0 then return false end
    for key in pairs(foodBlacklist) do foodBlacklist[key] = nil end
    for i = #foodBlacklistOrder, 1, -1 do foodBlacklistOrder[i] = nil end
    App.Persistence.saveConfig()
    return true
end


App.Format.extractNumber = function(str)
    if not str then return 0 end
    str = tostring(str)
    local n = string.gsub(str, ",", ".")
    local num, suf = string.match(n, "([%d%.]+)([KkMmBbTt])%s*$")
    if not num then
        num, suf = string.match(n, "([%d%.]+)%s+([KkMmBbTt])%s*$")
    end
    if not num then
        num, suf = string.match(n, "([%d%.]+)([KkMmBbTt])[%s%p]")
        if suf then
            local a = string.match(n, "[%d%.]+[KkMmBbTt](.)")
            if a and string.match(a, "[%a]") then num, suf = nil, nil end
        end
    end
    if num and suf then
        local v = tonumber(num) or 0
        suf = string.upper(suf)
        if suf == "K" then v = v * 1e3
        elseif suf == "M" then v = v * 1e6
        elseif suf == "B" then v = v * 1e9
        elseif suf == "T" then v = v * 1e12 end
        return math.floor(v)
    end
    return tonumber(string.match(str, "(%d+)")) or 0
end

App.Format.parseNumberWithSuffix = function(str)
    if not str then return 0 end
    str = string.gsub(tostring(str), ",", ".")
    local sm = {
        ["K"]=1e3, ["M"]=1e6, ["B"]=1e9, ["T"]=1e12, ["Qa"]=1e15, ["Qi"]=1e18,
        ["Sx"]=1e21, ["Sp"]=1e24, ["Oc"]=1e27, ["No"]=1e30, ["Dc"]=1e33,
        ["k"]=1e3, ["m"]=1e6, ["b"]=1e9, ["t"]=1e12, ["qa"]=1e15, ["qi"]=1e18,
        ["sx"]=1e21, ["sp"]=1e24, ["oc"]=1e27, ["no"]=1e30, ["dc"]=1e33,
    }
    local num, suf = string.match(str, "([%d%.]+)%s*([QqSsOoNnDd][aAiIxXpPcCoO])")
    if not num then
        num, suf = string.match(str, "([%d%.]+)%s*([KkMmBbTt])")
    end
    if num and suf then
        return math.floor((tonumber(num) or 0) * (sm[suf] or sm[string.upper(suf)] or 1))
    end
    return tonumber(string.match(str, "([%d%.]+)")) or 0
end

App.Format.parseGoldAndExp = function(t)
    if not t then return 0, 0 end
    local gv, ev = 0, 0
    local gp = string.match(t, "Rewards%s+([%d%.]+%s*[KkMmBbTtQqSsOoNnDdaAiIxXpPcCoO]*)")
    if gp and gp ~= "" then gv = App.Format.parseNumberWithSuffix(gp) end
    if gv == 0 then gv = tonumber(string.match(t, "Rewards%s+(%d+)")) or 0 end
    local ep = string.match(t, "([%d%.]+%s*[KkMmBbTtQqSsOoNnDdaAiIxXpPcCoO]*)%s*%(?[^%)]*%)?%s*EXP")
    if ep and ep ~= "" then ev = App.Format.parseNumberWithSuffix(ep) end
    if ev == 0 then
        ep = string.match(t, "([%d%.]+[KkMmBbTtQqSsOoNnDdaAiIxXpPcCoO]?)%s*EXP")
        if ep then ev = App.Format.parseNumberWithSuffix(ep) end
    end
    if ev == 0 then ev = tonumber(string.match(t, "(%d+)%s*EXP")) or 0 end
    return gv, ev
end


local SUF = "[KkMmBbTtQqSsOoNnDd]?[aAiIxXpPcCoO]?"

App.Format.parseRewardValues = function(t)
    if not t then return 0, 0 end
    local gv, ev = App.Format.parseGoldAndExp(t)

    if gv == 0 then
        local n = string.match(t, "[Gg][Oo][Ll][Dd]%s+([%d%.]+%s*" .. SUF .. ")")
            or string.match(t, "([%d%.]+%s*" .. SUF .. ")%s*[Gg][Oo][Ll][Dd]")
        if n then gv = App.Format.parseNumberWithSuffix(n) end
    end

    if ev == 0 then
        local n = string.match(t, "([%d%.]+%s*" .. SUF .. ")%s*[Ee][Xx][Pp]")
            or string.match(t, "[Ee][Xx][Pp]%s+([%d%.]+%s*" .. SUF .. ")")
        if n then ev = App.Format.parseNumberWithSuffix(n) end
    end

    return gv, ev
end

App.Format.formatNumber = function(n)
    if n >= 1e33 then return string.format("%.1fDc", n/1e33)
    elseif n >= 1e30 then return string.format("%.1fNo", n/1e30)
    elseif n >= 1e27 then return string.format("%.1fOc", n/1e27)
    elseif n >= 1e24 then return string.format("%.1fSp", n/1e24)
    elseif n >= 1e21 then return string.format("%.1fSx", n/1e21)
    elseif n >= 1e18 then return string.format("%.1fQi", n/1e18)
    elseif n >= 1e15 then return string.format("%.1fQa", n/1e15)
    elseif n >= 1e12 then return string.format("%.1fT", n/1e12)
    elseif n >= 1e9  then return string.format("%.1fB", n/1e9)
    elseif n >= 1e6  then return string.format("%.1fM", n/1e6)
    elseif n >= 1e3  then return string.format("%.1fK", n/1e3)
    else return tostring(math.floor(n)) end
end

App.Format.formatReq = function(v)
    if v >= 1e6 then return string.format("%.1fM", v/1e6)
    elseif v >= 1e3 then return string.format("%.1fK", v/1e3)
    else return tostring(v) end
end


App.Format.formatFragmentChance = function(v)
    if type(v) ~= "number" then return "?" end
    if v == math.floor(v) then return tostring(math.floor(v)) .. "%" end
    local t = string.format("%.4f", v)
    t = string.gsub(t, "0+$", "")
    t = string.gsub(t, "%.$", "")
    return t .. "%"
end

App.Format.formatRewards = function(rt)
    if not rt or rt == "" then return Lang.NoRewards end
    local p = {}
    local gv, ev = App.Format.parseRewardValues(rt) 
    if gv > 0 then table.insert(p, "Gold:" .. App.Format.formatNumber(gv)) end
    if ev > 0 then table.insert(p, "Exp:" .. App.Format.formatNumber(ev)) end
    local it = string.match(rt, "and%s+(.+)$")
    if it then
        local prev = ""
        while prev ~= it do
            prev = it
            it = string.gsub(it, "%s*%([^%)]*%)", "")
        end
        it = string.gsub(it, "[%d%.,]+%s*[KkMmBbTt]?[QqSsOoNnDd]?[aAiIxXpPcCoO]?%s*EXP", "")
        it = string.gsub(it, "[%d%.,]+%s*[KkMmBbTt]?[QqSsOoNnDd]?[aAiIxXpPcCoO]?%s*Gold", "")
        it = string.gsub(it, "[%d%.,]+%s*[KkMmBbTt]?[QqSsOoNnDd]?[aAiIxXpPcCoO]?%s*exp", "")
        it = string.gsub(it, "[%d%.,]+%s*[KkMmBbTt]?[QqSsOoNnDd]?[aAiIxXpPcCoO]?%s*gold", "")
        it = string.gsub(it, "^%s*EXP%s*$", "")
        it = string.gsub(it, "^%s*Gold%s*$", "")
        it = string.gsub(it, "^[%d%.,]+%s*", "")
        it = string.gsub(it, "%s*[%d%.,]+$", "")
        it = string.gsub(it, "%s*base%s*", " ")
        it = string.gsub(it, "%s+", " ")
        it = string.match(it, "^%s*(.-)%s*$") or ""
        if it and #it > 2 then
            if #it > 22 then it = string.sub(it, 1, 20) .. ".." end
            table.insert(p, Lang.Item .. ":" .. it)
        end
    end
    if #p == 0 then return Lang.NoSpecialRewards end
    return table.concat(p, " | ")
end

App.Format.extractSoulName = function(ft)
    if not ft or ft == "" then return nil end
    local lt = string.lower(ft)
    if string.find(lt, "no fragment") or string.find(lt, "sem fragment")
        or string.find(lt, "none") or string.find(lt, "n/a") or string.find(lt, "hecking") then
        return nil
    end
    local s = string.match(ft, "Soul of (%w+)") or string.match(ft, "(%w+) Soul")
        or string.match(ft, "Fragment of (%w+)")
    if s then return s end
    local c = string.gsub(ft, "Fragment", "")
    c = string.gsub(c, "%s+", " ")
    c = string.match(c, "^%s*(.-)%s*$") or ""
    if c ~= "" and #c > 2 then return c end
    return nil
end

App.Format.checkRewardsCustom = function(rt)
    if not rt then return false end
    local aa = string.match(rt, "and%s+(.+)$")
    if not aa then return false end
    local c, p = aa, ""
    while p ~= c do
        p = c
        c = string.gsub(c, "%s*%([^%)]*%)", "")
    end
    c = string.gsub(c, "[%d%.,]+%s*[KkMmBbTt]?[QqSsOoNnDd]?[aAiIxXpPcCoO]?%s*EXP", "")
    c = string.gsub(c, "[%d%.,]+%s*[KkMmBbTt]?[QqSsOoNnDd]?[aAiIxXpPcCoO]?%s*Gold", "")
    c = string.gsub(c, "[%d%.,]+%s*[KkMmBbTt]?[QqSsOoNnDd]?[aAiIxXpPcCoO]?%s*exp", "")
    c = string.gsub(c, "[%d%.,]+%s*[KkMmBbTt]?[QqSsOoNnDd]?[aAiIxXpPcCoO]?%s*gold", "")
    c = string.gsub(c, "^%s*EXP%s*$", "")
    c = string.gsub(c, "^%s*Gold%s*$", "")
    c = string.gsub(c, "%s+", "")
    return #c > 2
end


App.Teleport.partPosition = function(inst)
    if not inst then return nil end


    

    
    for _ = 1, 2 do
        local ok, pos = pcall(function()
            if inst:IsA("Part") or inst:IsA("MeshPart") or inst:IsA("BasePart") then
                return inst.Position
            end
            return nil
        end)
        if ok and pos ~= nil then return pos end
    end
    return nil
end

App.Teleport.findPartIn = function(node)
    if not node then return nil end
    local ok, part = pcall(function()
        local c = node:FindFirstChild("HumanoidRootPart") or node:FindFirstChild("Head")
        if c then return c end
        local okPrim, prim = pcall(function() return node.PrimaryPart end)
        if okPrim and prim then return prim end
        return nil
    end)
    if ok and part then return App.Teleport.partPosition(part) end
    return nil
end

App.Teleport.resolveTargetPosition = function(target)
    if not target then return nil end


    local p = App.Teleport.partPosition(target)
    if p then return p end


    p = App.Teleport.findPartIn(target)
    if p then return p end


    local node = target
    for _ = 1, 3 do
        local okParent, parent = pcall(function() return node.Parent end)
        if not okParent or not parent then break end
        node = parent
        p = App.Teleport.partPosition(node)
        if p then return p end
        p = App.Teleport.findPartIn(node)
        if p then return p end
    end

    return nil
end


App.Teleport.teleportToPosition = function(pos)
    if not pos then
        notify(Lang.TPFail, "UTMM Guider", 3)
        return false
    end

    local plr = LocalPlayer
    local okLive, live = pcall(function() return Players.LocalPlayer end)
    if okLive and live then plr = live end

    local char
    local okChar = pcall(function() char = plr and plr.Character end)
    if not okChar or not char then
        notify(Lang.TPFail, "UTMM Guider", 3)
        return false
    end

    local hrp
    pcall(function() hrp = char:FindFirstChild("HumanoidRootPart") end)
    if not hrp then
        notify(Lang.TPFail, "UTMM Guider", 3)
        return false
    end

    local okMove = pcall(function()
        hrp.Position = pos + Vector3.new(0, 5, 0)
        hrp.Velocity = Vector3.new(0, 0, 0)
    end)
    if not okMove then
        notify(Lang.TPFail, "UTMM Guider", 3)
        return false
    end
    return true
end


App.Teleport.teleportToTarget = function(target)
    if not target then
        notify(Lang.TPFail, "UTMM Guider", 3)
        return
    end
    local pos = App.Teleport.resolveTargetPosition(target)
    if not pos then
        notify(Lang.TPFail, "UTMM Guider", 3)
        return
    end
    App.Teleport.teleportToPosition(pos)
end


App.Teleport.teleportTo = function(gui)
    if not gui then return end
    local okParent, target = pcall(function() return gui.Parent end)
    if not okParent or not target then
        notify(Lang.TPFail, "UTMM Guider", 3)
        return
    end

    App.Teleport.teleportToTarget(target)
end


App.Teleport.teleportToShopPoint = function(target)
    if not target then
        notify(Lang.ShopNoTP, "UTMM Guider", 3)
        return
    end

    local pos = nil


    if type(target.pathSegments) == "table" and #target.pathSegments > 0 then
        local node = Workspace
        local valid = true
        for i = 1, #target.pathSegments do
            local segment = target.pathSegments[i]
            local child = nil
            for _ = 1, 2 do
                local okChild, c = pcall(function() return node:FindFirstChild(segment) end)
                if okChild and c then child = c break end
            end
            if not child then
                valid = false
                break
            end
            node = child
        end
        if valid and node then
            for _ = 1, 3 do
                local okPos, p = pcall(function() return node.Position end)
                if okPos and p ~= nil then
                    pos = p
                    break
                end
            end
        end
    end


    if not pos and target.instance then
        for _ = 1, 3 do
            local okPos, p = pcall(function() return target.instance.Position end)
            if okPos and p ~= nil then
                pos = p
                break
            end
        end
    end


    if not pos and type(target.x) == "number" and type(target.y) == "number" and type(target.z) == "number" then
        pos = Vector3.new(target.x, target.y, target.z)
    end

    if not pos then
        notify(Lang.ShopNoTP, "UTMM Guider", 3)
        return
    end
    App.Teleport.teleportToPosition(pos)
end


local BAD_TEXT_MARKERS = {
    "failed to fetch",
    "failed to read",
    "failed to get",

    
    "unreadable_name",
    "unreadable name",
    "unreadable",
}

App.Reader.isBadText = function(txt)
    if type(txt) ~= "string" then return true end
    local lt = string.lower(txt)
    for _, marker in ipairs(BAD_TEXT_MARKERS) do
        if string.find(lt, marker, 1, true) then return true end
    end
    return false
end


local GARBLED_RATIO = 0.34
local SAFE_TEXT_PUNCT = " .,'-_!()&+:#/%,*[]"

App.Reader.looksGarbled = function(txt)
    if type(txt) ~= "string" or txt == "" then return true end
    if App.Reader.isBadText(txt) then return true end

    local alnum, weird, total = 0, 0, 0
    for i = 1, #txt do
        local byte = string.byte(txt, i)
        local ch = string.sub(txt, i, i)
        if byte and byte < 32 and byte ~= 9 then return true end
        total = total + 1
        if byte and byte >= 128 then

        elseif string.match(ch, "%w") then
            alnum = alnum + 1
        elseif string.find(SAFE_TEXT_PUNCT, ch, 1, true) then

        else
            weird = weird + 1
        end
    end

    if alnum == 0 and weird > 0 then return true end
    return total > 0 and (weird / total) > GARBLED_RATIO
end

App.Reader.cleanText = function(txt)
    if type(txt) ~= "string" or txt == "" then return nil end
    if App.Reader.isBadText(txt) or App.Reader.looksGarbled(txt) then return nil end
    return txt
end

App.Reader.rawText = function(gui, childName)
    local ok, txt = pcall(function()
        local c = gui:FindFirstChild(childName)
        if not c then return nil end
        return c.Text
    end)
    if ok then return App.Reader.cleanText(txt) end
    return nil
end


App.Reader.readText = function(gui, childName)
    local txt = App.Reader.rawText(gui, childName)

    
    if txt == nil then txt = App.Reader.rawText(gui, childName) end
    return txt
end


App.Cache.Workspace.Scan = nil


App.Cache.Workspace.ShopWanted = nil

App.Reader.collectBattleGuis = function()
    if App.Cache.Workspace.Scan then return App.Cache.Workspace.Scan.battleGuis end

    local out = {}
    local shopNodes = {}
    local ok, descendants = pcall(function() return Workspace:GetDescendants() end)
    if not ok or type(descendants) ~= "table" then
        App.Cache.Workspace.Scan = { descendants = {}, battleGuis = {}, shopNodes = {} }
        return out
    end

    for _, inst in pairs(descendants) do
        local okName, nm = pcall(function() return inst.Name end)
        if okName and type(nm) == "string" then
            if nm == "BattleInfoGui" then
                out[#out + 1] = inst
            end

            if App.Cache.Workspace.ShopWanted then
                local matchedKey = nil
                if App.Cache.Workspace.ShopWanted.exact and App.Cache.Workspace.ShopWanted.exact[nm] then
                    matchedKey = App.Cache.Workspace.ShopWanted.exact[nm]
                elseif App.Cache.Workspace.ShopWanted.lower then
                    local lowerName = string.lower(nm)
                    if App.Cache.Workspace.ShopWanted.lower[lowerName] then matchedKey = lowerName end
                end

                if matchedKey then
                    local list = shopNodes[matchedKey]
                    if not list then
                        list = {}
                        shopNodes[matchedKey] = list
                    end
                    list[#list + 1] = inst
                end
            end
        end
    end

    App.Cache.Workspace.Scan = {
        descendants = descendants,
        battleGuis = out,
        shopNodes = shopNodes,
    }
    return out
end


App.Reader.safeChild = function(parent, name)
    if not parent then return nil end
    local ok, c = pcall(function() return parent:FindFirstChild(name) end)
    if ok and c then return c end

    local ok2, c2 = pcall(function() return parent:FindFirstChild(name) end)
    if ok2 then return c2 end
    return nil
end

App.Reader.safeChildren = function(inst)
    if not inst then return {} end
    local ok, kids = pcall(function() return inst:GetChildren() end)
    if ok and type(kids) == "table" and #kids > 0 then return kids end


    

    local ok2, kids2 = pcall(function() return inst:GetChildren() end)
    if ok2 and type(kids2) == "table" then return kids2 end


    if ok and type(kids) == "table" then return kids end
    return {}
end

App.Reader.safeName = function(inst)
    if not inst then return nil end
    local ok, n = pcall(function() return inst.Name end)
    if ok then
        local clean = App.Reader.cleanText(n)
        if clean then return clean end
    end

    local ok2, n2 = pcall(function() return inst.Name end)
    if ok2 then return App.Reader.cleanText(n2) end
    return nil
end


App.Reader.safeAddress = function(inst)
    if not inst then return nil end
    local ok, a = pcall(function() return inst.Address end)
    if ok and a ~= nil then return tostring(a) end
    return nil
end


App.Reader.readNumberValue = function(inst, fallback)
    if not inst then return fallback end
    local ok, v = pcall(function() return inst.Value end)
    if not ok then return fallback end
    if type(v) == "number" then return v end
    if type(v) == "string" then
        if App.Reader.isBadText(v) then return fallback end
        local n = tonumber((string.gsub(v, ",", ".")))
        if n then return n end
    end
    return fallback
end

App.Reader.readStringValue = function(inst)
    if not inst then return nil end
    local ok, v = pcall(function() return inst.Value end)
    if ok then
        local clean = App.Reader.cleanText(v)
        if clean then return clean end
    end

    local ok2, v2 = pcall(function() return inst.Value end)
    if ok2 then return App.Reader.cleanText(v2) end
    return nil
end

App.Reader.readBoolValue = function(inst)
    if not inst then return nil end


    
    for _ = 1, 2 do
        local ok, v = pcall(function() return inst.Value end)
        if ok and type(v) == "boolean" then return v end

        if ok and type(v) == "string" then
            local lv = string.lower(v)
            if lv == "true" then return true end
            if lv == "false" then return false end
        end
    end
    return nil
end


App.Reader.readObjectValue = function(inst)
    if not inst then return nil end
    local ok, v = pcall(function() return inst.Value end)
    if not ok or v == nil then return nil end

    if type(v) == "string" then
        local clean = App.Reader.cleanText(v)
        if not clean then return nil end
        local lv = string.lower(clean)

        if lv == "nil" or lv == "none" or lv == "null" or lv == "0" then return nil end
        return clean
    end

    if type(v) == "userdata" or type(v) == "table" then return v end
    if type(v) ~= "number" and type(v) ~= "boolean" then return v end
    return nil
end


App.Reader.isOwned = function(inst)
    local ok, v = pcall(function() return inst.Value end)
    if ok and v == false then return false end
    return true
end


App.Reader.findDeep = function(root, name, depth)
    if not root then return nil end
    local direct = App.Reader.safeChild(root, name)
    if direct then return direct end
    if depth <= 0 then return nil end
    for _, kid in ipairs(App.Reader.safeChildren(root)) do
        local found = App.Reader.findDeep(kid, name, depth - 1)
        if found then return found end
    end
    return nil
end


App.Reader.firstChild = function(parent, names)
    for _, n in ipairs(names) do
        local c = App.Reader.safeChild(parent, n)
        if c then return c end
    end
    return nil
end


local catalogCache = App.Cache.Catalog

App.Catalog.invalidateCatalog = function()
    catalogCache.battles = nil
    catalogCache.index = nil
    catalogCache.items = nil
    catalogCache.sources = nil
    catalogCache.guiRewards = nil
    catalogCache.bosses = nil
    catalogCache.frags = nil
    catalogCache.player = nil
    catalogCache.shopTargets = nil

    App.Cache.Workspace.Scan = nil
    App.Cache.Workspace.ShopWanted = nil
end


local INVENTORY_FOLDERS = { "Weapons", "Armor", "SOULs", "SoulFragments" }

App.Catalog.hasInventory = function(plr)
    if not plr then return false end
    for _, f in ipairs(INVENTORY_FOLDERS) do
        if App.Reader.safeChild(plr, f) then return true end
    end
    return false
end


App.Catalog.resolvePlayer = function()
    if catalogCache.player ~= nil then
        return catalogCache.player or nil
    end

    local found = nil


    
    local ok, live = pcall(function() return Players.LocalPlayer end)
    if ok and live then
        local nm = App.Reader.safeName(live)
        if nm and nm ~= "" then
            local fresh = App.Reader.safeChild(Players, nm)
            if App.Catalog.hasInventory(fresh) then found = fresh end
            if not found and fresh then found = fresh end
        end
        if not found and App.Catalog.hasInventory(live) then found = live end
    end


    if not found and App.Catalog.hasInventory(LocalPlayer) then found = LocalPlayer end


    
    if not found then
        for _, kid in ipairs(App.Reader.safeChildren(Players)) do
            if App.Catalog.hasInventory(kid) then
                found = kid
                break
            end
        end
    end

    catalogCache.player = found or false
    return found
end

App.Catalog.myFolder = function(folderName)
    return App.Reader.safeChild(App.Catalog.resolvePlayer(), folderName)
end


App.Catalog.ownedNames = function(folderName)
    local out = {}
    local folder = App.Catalog.myFolder(folderName)
    if not folder then return out, false end
    for _, kid in ipairs(App.Reader.safeChildren(folder)) do
        local nm = App.Reader.safeName(kid)
        if nm and nm ~= "" and App.Reader.isOwned(kid) then
            out[#out + 1] = nm
        end
    end
    return out, true
end

App.Catalog.ownedSet = function(folderName)
    local set = {}
    local list, exists = App.Catalog.ownedNames(folderName)
    for _, n in ipairs(list) do set[n] = true end
    return set, exists, #list
end


local DISPLAY_VALUE = {
    Weapons = { "WeaponName" },
    Armor   = { "ArmorName" },
    SOULs   = { "SoulName" },
    Food    = { "FoodName" },
    Battles = { "BattleName" },
}

App.Catalog.displayName = function(folder, kind, fallback)
    if folder then
        local v = App.Reader.readStringValue(App.Reader.firstChild(folder, DISPLAY_VALUE[kind] or {}))
        if v then return v end
    end

    return fallback or (folder and App.Reader.safeName(folder)) or "?"
end


local PERMANENCE_KINDS = { Weapons = true, Armor = true, SOULs = true, Food = true }

App.Catalog.permanenceKind = function(ref)
    if not ref then return nil end
    if type(ref) == "string" then
        local low = string.lower(ref)
        if string.find(low, "lighting.weapons.", 1, true) then return "Weapons" end
        if string.find(low, "lighting.armor.", 1, true) then return "Armor" end
        if string.find(low, "lighting.souls.", 1, true) then return "SOULs" end
        if string.find(low, "lighting.food.", 1, true) then return "Food" end
        return nil
    end
    local ok, parent = pcall(function() return ref.Parent end)
    if ok and parent then
        local pn = App.Reader.safeName(parent)
        if pn and PERMANENCE_KINDS[pn] then return pn end
    end
    return nil
end

App.Catalog.itemPermanence = function(folder)
    if not folder or type(folder) == "string" then return nil, nil end
    local permanent = App.Reader.readBoolValue(App.Reader.safeChild(folder, "Permanent"))
    local truePermanent = App.Reader.readBoolValue(App.Reader.safeChild(folder, "TruePermanent"))
    return permanent, truePermanent
end

App.Catalog.permanenceBoolText = function(v)
    if v == true then return Lang.FoodYes end
    if v == false then return Lang.FoodNo end
    return "?"
end

App.Catalog.permanenceLine = function(permanent, truePermanent, prefix, force)
    if not force and permanent == nil and truePermanent == nil then return nil end
    local line = Lang.Permanent .. ": " .. App.Catalog.permanenceBoolText(permanent)
        .. " | " .. Lang.TruePermanent .. ": " .. App.Catalog.permanenceBoolText(truePermanent)
    if prefix and prefix ~= "" then line = prefix .. " | " .. line end
    return line
end

App.Catalog.referencePermanence = function(ref)
    local kind = App.Catalog.permanenceKind(ref)
    if not kind then return nil, nil, nil end
    if type(ref) == "string" then

        

        local clean = App.Reader.cleanText(ref) or tostring(ref)
        local fname = string.match(clean, "([^%.]+)$")
        local root = App.Reader.safeChild(Lighting, kind)
        local folder = (root and fname) and App.Reader.safeChild(root, fname) or nil
        local p, tp = App.Catalog.itemPermanence(folder)
        return p, tp, kind
    end
    local p, tp = App.Catalog.itemPermanence(ref)
    return p, tp, kind
end


App.Catalog.shopInfo = function(folder)
    if not folder then return nil end
    local onsale = App.Reader.readBoolValue(App.Reader.safeChild(folder, "Onsale"))
    local shop   = App.Reader.readStringValue(App.Reader.safeChild(folder, "Shop"))
    local cost   = App.Reader.readNumberValue(App.Reader.firstChild(folder, { "Cost", "Price" }), nil)


    
    if onsale == false then return nil end
    if onsale == nil and (shop == nil or shop == "") then return nil end

    return { shop = shop, cost = cost, sure = (onsale == true) }
end


App.Catalog.safeClassName = function(inst)
    if not inst then return nil end
    for _ = 1, 2 do
        local ok, cn = pcall(function() return inst.ClassName end)
        if ok then
            local clean = App.Reader.cleanText(cn)
            if clean then return clean end
        end
    end
    return nil
end

local SHOP_BASEPART_CLASSES = {
    BasePart = true, Part = true, MeshPart = true, UnionOperation = true,
    WedgePart = true, CornerWedgePart = true, TrussPart = true,
    Seat = true, VehicleSeat = true, SpawnLocation = true,
}

local SHOP_CONTAINER_CLASSES = {
    Folder = true, Model = true, Workspace = true, DataModel = true,
}

App.Catalog.isShopPart = function(inst)
    if not inst then return false end

    local cn = App.Catalog.safeClassName(inst)


    

    
    if cn and SHOP_CONTAINER_CLASSES[cn] then return false end

    if cn and SHOP_BASEPART_CLASSES[cn] then return true end


    
    local okIsA, yes = pcall(function() return inst:IsA("BasePart") end)
    if okIsA and yes then return true end


    

    if cn == nil then
        local okPos, pos = pcall(function() return inst.Position end)
        if okPos and pos ~= nil then
            local okType, tv = pcall(function() return typeof(pos) end)
            if okType and tv == "Vector3" then return true end
        end
    end
    return false
end


App.Catalog.workspacePathSegments = function(inst)
    if not inst then return nil end
    local rev = {}
    local cur = inst
    local wsAddr = App.Reader.safeAddress(Workspace)

    for _ = 1, 40 do
        local nm = App.Reader.safeName(cur)
        if not nm then return nil end
        table.insert(rev, 1, nm)

        local okParent, parent = pcall(function() return cur.Parent end)
        if not okParent or not parent then return nil end

        local parentAddr = App.Reader.safeAddress(parent)
        local parentName = App.Reader.safeName(parent)
        if (wsAddr and parentAddr == wsAddr) or (not wsAddr and parentName == "Workspace") then
            return rev
        end
        cur = parent
    end
    return nil
end

App.Catalog.readShopPartXYZ = function(part)
    if not part then return nil, nil, nil end
    for _ = 1, 3 do
        local ok, x, y, z = pcall(function()
            local p = part.Position
            return p.X, p.Y, p.Z
        end)
        if ok and type(x) == "number" and type(y) == "number" and type(z) == "number" then
            return x, y, z
        end
    end
    return nil, nil, nil
end


App.Catalog.shopTargetFromPart = function(part)
    if not part or not App.Catalog.isShopPart(part) then return nil end

    local nm = App.Reader.safeName(part) or "Part"
    local full = nil
    pcall(function() full = part:GetFullName() end)
    local addr = App.Reader.safeAddress(part)
    local segments = App.Catalog.workspacePathSegments(part)
    local x, y, z = App.Catalog.readShopPartXYZ(part)

    return {
        name = nm,
        path = App.Reader.cleanText(full) or nm,
        address = addr,
        pathSegments = segments,
        instance = part,
        x = x, y = y, z = z,
    }
end

App.Catalog.appendShopParts = function(out, seen, node)
    if not node then return end

    if App.Catalog.isShopPart(node) then
        local t = App.Catalog.shopTargetFromPart(node)
        if t then
            local key = t.address or t.path
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = t
            end
        end
        return
    end


    
    for _, kid in pairs(App.Reader.safeChildren(node)) do
        App.Catalog.appendShopParts(out, seen, kid)
    end
end


App.Catalog.appendShopPartsFromSnapshot = function(out, seen, container)
    if not container or not App.Cache.Workspace.Scan then return end
    local descendants = App.Cache.Workspace.Scan.descendants or {}

    local containerAddr = App.Reader.safeAddress(container)
    local containerFull = nil
    pcall(function() containerFull = App.Reader.cleanText(container:GetFullName()) end)
    local prefix = containerFull and (containerFull .. ".") or nil

    for _, candidate in pairs(descendants) do
        if App.Catalog.isShopPart(candidate) then
            local belongs = false

            local okDesc, isDesc = pcall(function() return candidate:IsDescendantOf(container) end)
            if okDesc and isDesc then belongs = true end

            if not belongs and containerAddr then
                local cur = candidate
                for _ = 1, 32 do
                    local okParent, par = pcall(function() return cur.Parent end)
                    if not okParent or not par then break end
                    if App.Reader.safeAddress(par) == containerAddr then
                        belongs = true
                        break
                    end
                    cur = par
                end
            end

            if not belongs and prefix then
                local full = nil
                pcall(function() full = App.Reader.cleanText(candidate:GetFullName()) end)
                if full and string.sub(full, 1, #prefix) == prefix then belongs = true end
            end

            if belongs then
                local t = App.Catalog.shopTargetFromPart(candidate)
                if t then
                    local key = t.address or t.path
                    if not seen[key] then
                        seen[key] = true
                        out[#out + 1] = t
                    end
                end
            end
        end
    end
end

App.Catalog.findShopTargets = function(shopName)
    local clean = App.Reader.cleanText(shopName)
    if not clean then return {} end
    local key = string.lower(clean)

    catalogCache.shopTargets = catalogCache.shopTargets or {}
    if catalogCache.shopTargets[key] then return catalogCache.shopTargets[key] end

    local out, seen = {}, {}


    
    App.Cache.Workspace.ShopWanted = App.Cache.Workspace.ShopWanted or { exact = {}, lower = {} }
    App.Cache.Workspace.ShopWanted.exact[clean] = key
    App.Cache.Workspace.ShopWanted.lower[key] = true

    if not App.Cache.Workspace.Scan then App.Reader.collectBattleGuis() end

    local nodes = {}
    local indexed = App.Cache.Workspace.Scan and App.Cache.Workspace.Scan.shopNodes
        and App.Cache.Workspace.Scan.shopNodes[key] or nil

    if indexed then
        for _, node in pairs(indexed) do nodes[#nodes + 1] = node end
    else

        local descendants = (App.Cache.Workspace.Scan and App.Cache.Workspace.Scan.descendants) or {}
        for _, node in pairs(descendants) do
            local nm = App.Reader.safeName(node)
            if nm and (nm == clean or string.lower(nm) == key) then
                nodes[#nodes + 1] = node
            end
        end
        if App.Cache.Workspace.Scan then
            App.Cache.Workspace.Scan.shopNodes = App.Cache.Workspace.Scan.shopNodes or {}
            App.Cache.Workspace.Scan.shopNodes[key] = nodes
        end
    end

    for _, node in pairs(nodes) do
        local before = #out
        App.Catalog.appendShopParts(out, seen, node)
        if #out == before and not App.Catalog.isShopPart(node) then
            App.Catalog.appendShopPartsFromSnapshot(out, seen, node)
        end
    end

    table.sort(out, function(a, b)
        local an, bn = string.lower(a.name or ""), string.lower(b.name or "")
        if an ~= bn then return an < bn end
        return tostring(a.path or "") < tostring(b.path or "")
    end)

    catalogCache.shopTargets[key] = out
    return out
end

App.Catalog.shopTargets = function(shop)
    if not shop or not shop.shop then return {} end
    return App.Catalog.findShopTargets(shop.shop)
end


App.Catalog.soulFragmentCost = function(folder)
    return App.Reader.readNumberValue(App.Reader.firstChild(folder, { "Fragments", "Fragment" }), nil)
end


App.Catalog.catalogFolder = function(kind)
    return App.Reader.safeChild(Lighting, kind)
end

App.Catalog.itemFolder = function(kind, itemName)
    local root = App.Catalog.catalogFolder(kind)
    if not root then return nil end
    return App.Reader.safeChild(root, itemName)
end

App.Catalog.weaponStats = function(itemName, folder)
    folder = folder or App.Catalog.itemFolder("Weapons", itemName)
    if not folder then return nil end


    local attack
    local tool = App.Reader.safeChild(folder, "Tool")
    if tool then attack = App.Reader.safeChild(tool, "AttackTool") end
    if not attack then attack = App.Reader.findDeep(folder, "AttackTool", 2) end

    local host = attack or folder
    local dmg = App.Reader.safeChild(host, "Damage")         or App.Reader.findDeep(folder, "Damage", 3)
    local mod = App.Reader.safeChild(host, "DamageModify")   or App.Reader.findDeep(folder, "DamageModify", 3)
    local inc = App.Reader.safeChild(host, "DamageIncrease") or App.Reader.findDeep(folder, "DamageIncrease", 3)


    

    local d = App.Reader.readNumberValue(dmg, nil)
    local m = App.Reader.readNumberValue(mod, nil)
    local i = App.Reader.readNumberValue(inc, nil)
    if d == nil and m == nil and i == nil then return nil end

    local permanent, truePermanent = App.Catalog.itemPermanence(folder)
    return {
        damage   = d or 0,
        modify   = m or 0,
        increase = i or 0,
        label    = App.Catalog.displayName(folder, "Weapons", itemName),
        shop     = App.Catalog.shopInfo(folder),
        permanent = permanent, truePermanent = truePermanent,
    }
end

App.Catalog.armorStats = function(itemName, folder)
    folder = folder or App.Catalog.itemFolder("Armor", itemName)
    if not folder then return nil end

    local hp = App.Reader.safeChild(folder, "HPBonus") or App.Reader.findDeep(folder, "HPBonus", 2)
    if not hp then return nil end


    local bonus = App.Reader.readNumberValue(hp, nil)
    if bonus == nil then return nil end

    local permanent, truePermanent = App.Catalog.itemPermanence(folder)
    return {
        hp    = bonus,
        label = App.Catalog.displayName(folder, "Armor", itemName),
        shop  = App.Catalog.shopInfo(folder),
        permanent = permanent, truePermanent = truePermanent,
    }
end


App.Catalog.foodStats = function(itemName, folder)
    folder = folder or App.Catalog.itemFolder("Food", itemName)
    if not folder then return nil end

    local foodNode = nil
    local tool = App.Reader.safeChild(folder, "Tool")
    if tool then foodNode = App.Reader.safeChild(tool, "Food") end
    if not foodNode then foodNode = App.Reader.findDeep(folder, "Food", 3) end

    local healNode = foodNode and App.Reader.safeChild(foodNode, "Heal") or nil
    if not healNode then healNode = App.Reader.findDeep(folder, "Heal", 4) end

    local heal = App.Reader.readNumberValue(healNode, nil)
    local cost = App.Reader.readNumberValue(App.Reader.firstChild(folder, { "Cost", "Price" }), nil)
    local maxv = App.Reader.readNumberValue(App.Reader.safeChild(folder, "Max"), nil)
    local onsale = App.Reader.readBoolValue(App.Reader.safeChild(folder, "Onsale"))
    local rawShop = App.Reader.readStringValue(App.Reader.safeChild(folder, "Shop"))
    local permanent, truePermanent = App.Catalog.itemPermanence(folder)


    

    local shopTarget = nil
    if rawShop and rawShop ~= "" then
        shopTarget = { shop = rawShop, cost = cost, sure = (onsale == true) }
    end

    return {
        folderName = itemName,
        label = App.Catalog.displayName(folder, "Food", itemName),
        heal = heal,
        cost = cost,
        max = maxv,
        onsale = onsale,
        shopName = rawShop,

        
        shop = App.Catalog.shopInfo(folder),
        shopTarget = shopTarget,
        permanent = permanent, truePermanent = truePermanent,
        missing = (heal == nil),
    }
end


App.Catalog.normalizeBossAlias = function(txt)
    txt = App.Reader.cleanText(txt)
    if not txt then return nil end
    local s = string.lower(txt)


    
    local prev = ""
    while prev ~= s do
        prev = s
        s = string.gsub(s, "%b()", " ")
        s = string.gsub(s, "%b[]", " ")
    end
    s = string.gsub(s, "[_%-]+", " ")
    s = string.gsub(s, "[^%w%s]", " ")
    s = string.gsub(s, "%s+", " ")
    s = string.match(s, "^%s*(.-)%s*$") or ""


    s = string.gsub(s, "%s+raid%s+boss$", "")
    s = string.gsub(s, "%s+raid$", "")
    s = string.gsub(s, "%s+boss$", "")
    s = string.match(s, "^%s*(.-)%s*$") or ""
    return (s ~= "") and s or nil
end

App.Catalog.readBattle = function(folder)
    local folderName = App.Reader.safeName(folder)
    local battleName = App.Reader.readStringValue(App.Reader.safeChild(folder, "BattleName"))
    local linked = App.Reader.readObjectValue(App.Reader.safeChild(folder, "LinkedBattle"))

    return {
        folder     = folder,
        folderName = folderName or battleName or "?",

        
        battleName = battleName,
        name       = battleName or folderName or "?",
        stableKey  = App.Reader.safeAddress(folder) or (folderName and ("folder:" .. string.lower(folderName)))
            or (battleName and ("battle:" .. string.lower(battleName))) or tostring(folder),
        linked     = linked,

        

        lvl        = App.Reader.readNumberValue(App.Reader.firstChild(folder, { "LOVE", "LVRequired", "Level" }), nil),
        r          = App.Reader.readNumberValue(App.Reader.firstChild(folder, { "Resets", "Reset" }), nil),
        tr         = App.Reader.readNumberValue(App.Reader.firstChild(folder, { "TrueResets", "TrueReset" }), nil),
        gold       = App.Reader.readNumberValue(App.Reader.safeChild(folder, "Gold"), nil),
        exp        = App.Reader.readNumberValue(App.Reader.firstChild(folder, { "XP", "EXP", "Exp" }), nil),
        reward     = App.Reader.readObjectValue(App.Reader.safeChild(folder, "RewardWeapon")),
        fragment   = App.Reader.readObjectValue(App.Reader.safeChild(folder, "SoulFragment")),
        fragChance = App.Reader.readNumberValue(App.Reader.safeChild(folder, "FragmentChance"), nil),
    }
end

App.Catalog.allBattles = function()
    if catalogCache.battles then return catalogCache.battles end
    local out = {}
    local root = App.Catalog.catalogFolder("Battles")
    for _, folder in ipairs(App.Reader.safeChildren(root)) do
        local okRead, b = pcall(App.Catalog.readBattle, folder)
        if okRead and b then out[#out + 1] = b end
    end
    catalogCache.battles = out
    return out
end


App.Catalog.putUnique = function(map, key, value)
    if not key or key == "" then return end
    if map[key] == nil then
        map[key] = value
    elseif map[key] ~= value then
        map[key] = false
    end
end

App.Catalog.battleIndex = function()
    if catalogCache.index then return catalogCache.index end
    local idx = {
        exact = {}, norm = {}, normAll = {},
        linkedAddress = {}, linkedName = {},

        
        byLevel = {}, reqExact = {},
    }

    for _, b in ipairs(App.Catalog.allBattles()) do
        local aliases = { b.folderName, b.battleName, b.name }
        for _, alias in ipairs(aliases) do
            local clean = App.Reader.cleanText(alias)
            if clean then
                App.Catalog.putUnique(idx.exact, string.lower(clean), b)
                local norm = App.Catalog.normalizeBossAlias(clean)
                if norm then
                    App.Catalog.putUnique(idx.norm, norm, b)
                    idx.normAll[norm] = idx.normAll[norm] or {}
                    local seen = false
                    for _, old in ipairs(idx.normAll[norm]) do
                        if old == b then seen = true break end
                    end
                    if not seen then idx.normAll[norm][#idx.normAll[norm] + 1] = b end
                end
            end
        end

        if b.lvl ~= nil and b.lvl > 0 then
            idx.byLevel[b.lvl] = idx.byLevel[b.lvl] or {}
            idx.byLevel[b.lvl][#idx.byLevel[b.lvl] + 1] = b
            if b.r ~= nil and b.tr ~= nil then
                local rk = tostring(b.lvl) .. ":" .. tostring(b.r) .. ":" .. tostring(b.tr)
                idx.reqExact[rk] = idx.reqExact[rk] or {}
                idx.reqExact[rk][#idx.reqExact[rk] + 1] = b
            end
        end

        if b.linked then
            App.Catalog.putUnique(idx.linkedAddress, App.Reader.safeAddress(b.linked), b)
            local ln = App.Reader.safeName(b.linked)
            if ln then App.Catalog.putUnique(idx.linkedName, string.lower(ln), b) end
        end
    end

    catalogCache.index = idx
    return idx
end

App.Catalog.chooseNormCandidate = function(list, gui, lvlTxt)
    if not list or #list == 0 then return nil end
    if #list == 1 then return list[1] end


    
    local gLvl = App.Format.extractNumber(lvlTxt or App.Reader.readText(gui, "LVRequired") or "0")
    local gR   = App.Format.extractNumber(App.Reader.readText(gui, "Resets") or "0")
    local gTR  = App.Format.extractNumber(App.Reader.readText(gui, "TrueResets") or "0")

    local best, bestScore, tie = nil, -1, false
    for _, b in ipairs(list) do
        local sc = 0
        if b.lvl ~= nil and b.lvl == gLvl then sc = sc + 4 end
        if b.r   ~= nil and b.r   == gR   then sc = sc + 2 end
        if b.tr  ~= nil and b.tr  == gTR  then sc = sc + 2 end
        if sc > bestScore then
            best, bestScore, tie = b, sc, false
        elseif sc == bestScore then
            tie = true
        end
    end
    if bestScore > 0 and not tie then return best end
    return nil
end


App.Catalog.resolveBattle = function(gui, monsterText, lvlTxt)
    local idx = App.Catalog.battleIndex()
    local okParent, owner = pcall(function() return gui.Parent end)

    if okParent and owner then

        

        
        local node = owner
        for _ = 0, 3 do
            local byAddr = idx.linkedAddress[App.Reader.safeAddress(node)]
            if byAddr and byAddr ~= false then return byAddr end

            local ownerName = App.Reader.safeName(node)
            if ownerName then
                local key = string.lower(ownerName)
                local byLinkedName = idx.linkedName[key]
                if byLinkedName and byLinkedName ~= false then return byLinkedName end
                local exactOwner = idx.exact[key]
                if exactOwner and exactOwner ~= false then return exactOwner end
            end

            local okUp, up = pcall(function() return node.Parent end)
            if not okUp or not up then break end
            node = up
        end
    end

    local cleanMonster = App.Reader.cleanText(monsterText)
    if cleanMonster then
        local exactMonster = idx.exact[string.lower(cleanMonster)]
        if exactMonster and exactMonster ~= false then return exactMonster end
    end

    local aliases = {}
    if okParent and owner then
        local node = owner
        for _ = 0, 3 do
            aliases[#aliases + 1] = App.Reader.safeName(node)
            local okUp, up = pcall(function() return node.Parent end)
            if not okUp or not up then break end
            node = up
        end
    end
    aliases[#aliases + 1] = cleanMonster
    for _, alias in ipairs(aliases) do
        local norm = App.Catalog.normalizeBossAlias(alias)
        if norm then
            local one = idx.norm[norm]
            if one and one ~= false then return one end
            local chosen = App.Catalog.chooseNormCandidate(idx.normAll[norm], gui, lvlTxt)
            if chosen then return chosen end
        end
    end


    

    
    local gLvl = App.Format.extractNumber(lvlTxt or App.Reader.readText(gui, "LVRequired") or "0")
    if gLvl > 0 then
        local gR  = App.Format.extractNumber(App.Reader.readText(gui, "Resets") or "0")
        local gTR = App.Format.extractNumber(App.Reader.readText(gui, "TrueResets") or "0")
        local gGold, gExp = App.Format.parseRewardValues(App.Reader.readText(gui, "Rewards") or "")

        local reqKey = tostring(gLvl) .. ":" .. tostring(gR) .. ":" .. tostring(gTR)
        local exactPool = idx.reqExact[reqKey] or {}
        if #exactPool == 1 then return exactPool[1] end

        local pool = (#exactPool > 1) and exactPool or (idx.byLevel[gLvl] or {})
        local candidates, bestScore = {}, -1
        for _, b in ipairs(pool) do
            local reqOK = (b.lvl == nil or b.lvl == 0 or b.lvl == gLvl)
                and (b.r == nil or b.r == 0 or b.r == gR)
                and (b.tr == nil or b.tr == 0 or b.tr == gTR)
            if reqOK then
                local sc = 0
                if b.lvl == gLvl then sc = sc + 4 end
                if b.r == gR then sc = sc + 2 end
                if b.tr == gTR then sc = sc + 2 end
                if gGold > 0 and b.gold and b.gold == gGold then sc = sc + 2 end
                if gExp > 0 and b.exp and b.exp == gExp then sc = sc + 2 end
                if sc > bestScore then
                    candidates = { b }
                    bestScore = sc
                elseif sc == bestScore then
                    candidates[#candidates + 1] = b
                end
            end
        end
        if bestScore >= 8 and #candidates == 1 then return candidates[1] end
    end

    return nil
end


App.Catalog.referenceFolderName = function(ref)
    if not ref then return nil end
    if type(ref) == "string" then
        local clean = App.Reader.cleanText(ref)
        if not clean then return nil end
        local tail = string.match(clean, "([^%.]+)$") or clean
        return App.Reader.cleanText(tail)
    end
    return App.Reader.safeName(ref)
end

App.Catalog.anyDisplayName = function(folder)
    if not folder then return nil end


    
    if type(folder) == "string" then
        return App.Catalog.referenceFolderName(folder)
    end

    for _, k in ipairs({ "Weapons", "Armor", "SOULs", "Food", "Battles" }) do
        local names = DISPLAY_VALUE[k]
        if names then
            local v = App.Reader.readStringValue(App.Reader.firstChild(folder, names))
            if v then return v end
        end
    end


    return App.Catalog.referenceFolderName(folder)
end

App.Catalog.battleRewardLine = function(b)
    local p = {}
    if b.gold and b.gold > 0 then p[#p + 1] = "Gold:" .. App.Format.formatNumber(b.gold) end
    if b.exp and b.exp > 0 then p[#p + 1] = "Exp:" .. App.Format.formatNumber(b.exp) end
    local rn = App.Catalog.anyDisplayName(b.reward)
    if rn then p[#p + 1] = Lang.Item .. ":" .. rn end
    local fn = App.Catalog.anyDisplayName(b.fragment)
    if fn then p[#p + 1] = Lang.Frags .. ":" .. fn end
    if #p == 0 then return Lang.NoRewards end
    return table.concat(p, " | ")
end


App.Catalog.fillFromGui = function(rec, gui, nameTxt, lvlTxt)
    rec.gui      = gui
    rec.rewards  = App.Reader.readText(gui, "Rewards") or ""
    rec.fragment = App.Reader.readText(gui, "Fragment") or ""
    rec.guiName  = App.Reader.cleanText(nameTxt)

    local okOwner, owner = pcall(function() return gui.Parent end)
    rec.guiOwnerName = (okOwner and owner) and App.Reader.safeName(owner) or nil
    rec.guiOwnerAddress = (okOwner and owner) and App.Reader.safeAddress(owner) or nil

    local gLvl = App.Format.extractNumber(lvlTxt or "0")
    local gR   = App.Format.extractNumber(App.Reader.readText(gui, "Resets") or "0")
    local gTR  = App.Format.extractNumber(App.Reader.readText(gui, "TrueResets") or "0")
    local gGold, gExp = App.Format.parseRewardValues(rec.rewards)


    

    if gGold > 0 then rec.guiGold = gGold end
    local gBaseText = string.match(rec.rewards, "%(([%d%.,]+%s*" .. SUF .. ")%s*[Bb][Aa][Ss][Ee]%)")
    local gBase = gBaseText and App.Format.parseNumberWithSuffix(gBaseText) or 0
    if (rec.baseGold == nil or rec.baseGold == 0) and gBase > 0 then rec.baseGold = gBase end


    

    if (rec.lvl == nil or rec.lvl == 0) and gLvl > 0 then rec.lvl = gLvl end
    if (rec.r   == nil or rec.r   == 0) and gR   > 0 then rec.r   = gR end
    if (rec.tr  == nil or rec.tr  == 0) and gTR  > 0 then rec.tr  = gTR end


    

    
    if (rec.gold == nil or rec.gold == 0) and gGold > 0 then rec.gold = gGold end
    if (rec.exp  == nil or rec.exp  == 0) and gExp  > 0 then rec.exp  = gExp end
end

App.Catalog.collectBosses = function()
    if catalogCache.bosses then return catalogCache.bosses end

    local list, byBattle, guiOnly = {}, {}, {}


    
    for _, b in ipairs(App.Catalog.allBattles()) do
        local rec = {
            name = b.battleName or b.folderName or "?", battle = b,
            lvl = b.lvl, r = b.r, tr = b.tr, gold = b.gold, baseGold = b.gold, exp = b.exp,
            guiGold = nil, fragChance = b.fragChance,
            rewards = "", fragment = "", gui = nil, source = "lighting",
            stableKey = b.stableKey,
        }
        byBattle[b] = rec
        list[#list + 1] = rec
    end


    

    
    for _, gui in ipairs(App.Reader.collectBattleGuis()) do
        local nameTxt = App.Reader.readText(gui, "MonsterName")
        local lvlTxt  = App.Reader.readText(gui, "LVRequired")
        local b = App.Catalog.resolveBattle(gui, nameTxt, lvlTxt)
        local rec = b and byBattle[b] or nil

        if rec then

            if not rec.gui then
                rec.source = "both"
                App.Catalog.fillFromGui(rec, gui, nameTxt, lvlTxt)
            end
        elseif nameTxt then

            

            local okOwner, owner = pcall(function() return gui.Parent end)
            local key = (okOwner and owner and App.Reader.safeAddress(owner))
                or App.Catalog.normalizeBossAlias(nameTxt)
                or string.lower(nameTxt)
            if not guiOnly[key] then
                local nrec = {
                    name = nameTxt, battle = nil, source = "gui",
                    stableKey = "gui:" .. tostring(key),
                }
                App.Catalog.fillFromGui(nrec, gui, nameTxt, lvlTxt)
                guiOnly[key] = nrec
                list[#list + 1] = nrec
            end
        end
    end


    for _, rec in ipairs(list) do
        local b = rec.battle


        

        if b then
            rec.name = b.battleName or rec.guiName or b.folderName
                or rec.guiOwnerName or "?"
        else
            rec.name = rec.guiName or rec.guiOwnerName or rec.name or "?"
        end

        rec.lvl  = rec.lvl or 0
        rec.r    = rec.r or 0
        rec.tr   = rec.tr or 0
        rec.gold = rec.gold or 0
        rec.baseGold = rec.baseGold or rec.gold or 0

        
        rec.farmGold = (rec.guiGold and rec.guiGold > 0) and rec.guiGold or rec.gold
        rec.exp  = rec.exp or 0
        rec.noTP = (rec.gui == nil)


        
        local lightingSoul = b and App.Catalog.anyDisplayName(b.fragment) or nil
        rec.soul = lightingSoul or App.Format.extractSoulName(rec.fragment)


        
        if b then
            rec.rewardPermanent, rec.rewardTruePermanent, rec.rewardPermKind = App.Catalog.referencePermanence(b.reward)
            rec.soulPermanent, rec.soulTruePermanent, rec.soulPermKind = App.Catalog.referencePermanence(b.fragment)
        end


        

        local lightingRewardName = b and App.Catalog.anyDisplayName(b.reward) or nil

        

        

        
        rec.hasReward = (lightingRewardName ~= nil) or App.Format.checkRewardsCustom(rec.rewards)


        

        

        if lightingRewardName then
            local parts = {}
            if rec.gold > 0 then parts[#parts + 1] = "Gold:" .. App.Format.formatNumber(rec.gold) end
            if rec.exp  > 0 then parts[#parts + 1] = "Exp:" .. App.Format.formatNumber(rec.exp) end
            parts[#parts + 1] = Lang.Item .. ":" .. lightingRewardName
            rec.rewardLine = table.concat(parts, " | ")
        elseif rec.rewards == "" and b then
            rec.rewardLine = App.Catalog.battleRewardLine(b)
        end
    end

    catalogCache.bosses = list
    return list
end


App.Catalog.normalizeName = function(str)
    local n = string.lower(tostring(str or ""))
    n = string.gsub(n, "[^%w]", "")
    n = string.gsub(n, "soul$", "")
    return n
end


local FRAGMENT_OVERRIDES = {
    -- Ex.: ["Gaster"] = "W.D Gaster Soul"
}

App.Catalog.fragmentCounters = function()
    if catalogCache.frags then return catalogCache.frags end
    local out = { exact = {}, norm = {}, list = {}, exists = false }
    local folder = App.Catalog.myFolder("SoulFragments")
    if folder then
        out.exists = true
        for _, kid in ipairs(App.Reader.safeChildren(folder)) do
            local nm = App.Reader.safeName(kid)
            if nm and nm ~= "" then
                local rec = { name = nm, value = App.Reader.readNumberValue(kid, nil), norm = App.Catalog.normalizeName(nm) }
                out.list[#out.list + 1] = rec
                out.exact[nm] = rec

                if out.norm[rec.norm] == nil then out.norm[rec.norm] = rec end
            end
        end
    end

    
    local plr = App.Catalog.resolvePlayer()
    local unread = 0
    for _, c in ipairs(out.list) do
        if c.value == nil then unread = unread + 1 end
    end
    state.fragDiag = "Player: " .. (plr and (App.Reader.safeName(plr) or "?") or "NAO ACHADO")
        .. " | SoulFragments: " .. (out.exists and (#out.list .. (unread > 0 and (" (" .. unread .. " ilegiveis)") or "")) or "NAO ACHADA")

    catalogCache.frags = out
    return out
end


App.Catalog.resolveFragments = function(entry)
    local fc = App.Catalog.fragmentCounters()
    if not fc.exists then return nil end


    local forced = FRAGMENT_OVERRIDES[entry.folderName]
    if forced and fc.exact[forced] then return fc.exact[forced], "exact" end


    local rec = fc.exact[entry.folderName] or fc.exact[entry.label]
    if rec then return rec, "exact" end


    rec = fc.norm[App.Catalog.normalizeName(entry.folderName)] or fc.norm[App.Catalog.normalizeName(entry.label)]
    if rec then return rec, "exact" end


    
    local target = App.Catalog.normalizeName(entry.folderName)
    if #target >= 4 then
        local hit, hits = nil, 0
        for _, c in ipairs(fc.list) do
            if string.find(c.norm, target, 1, true) then
                hit = c
                hits = hits + 1
            end
        end
        if hits == 1 then return hit, "guess" end
    end

    return nil
end


local ITEM_KINDS = {
    { kind = "Weapons", tagKey = "TagWeapon" },
    { kind = "Armor",   tagKey = "TagArmor"  },
    { kind = "SOULs",   tagKey = "TagSoul"   },

    { kind = "Food",    tagKey = "TagFood"   },
}


App.Catalog.allCatalogItems = function()
    if catalogCache.items then return catalogCache.items end
    local out = {}
    for _, def in ipairs(ITEM_KINDS) do
        for _, folder in ipairs(App.Reader.safeChildren(App.Catalog.catalogFolder(def.kind))) do
            local fname = App.Reader.safeName(folder)
            if fname and fname ~= "" then
                local permanent, truePermanent = App.Catalog.itemPermanence(folder)
                local entry = {
                    kind = def.kind,
                    tag = Lang[def.tagKey],
                    folder = folder,
                    folderName = fname,
                    label = App.Catalog.displayName(folder, def.kind, fname),
                    shop = App.Catalog.shopInfo(folder),
                    permanent = permanent, truePermanent = truePermanent,
                }
                if def.kind == "SOULs" then
                    entry.fragments = App.Catalog.soulFragmentCost(folder)

                    local rec, how = App.Catalog.resolveFragments(entry)
                    if rec then

                        

                        entry.have      = rec.value
                        entry.haveName  = rec.name
                        entry.haveHow   = how
                        entry.haveFound = true
                    end
                    entry.ready = (entry.have ~= nil and entry.fragments ~= nil
                        and entry.fragments > 0 and entry.have >= entry.fragments) or false
                elseif def.kind == "Food" then

                    
                    local fs = App.Catalog.foodStats(fname, folder)
                    if fs then
                        entry.heal = fs.heal
                        entry.cost = fs.cost
                        entry.max = fs.max
                        entry.onsale = fs.onsale
                        entry.shopName = fs.shopName
                    end
                end
                out[#out + 1] = entry
            end
        end
    end
    catalogCache.items = out
    return out
end


App.Catalog.bossSourceIndex = function()
    if catalogCache.sources then return catalogCache.sources end
    local idx = {}
    local function push(target, battle, drop)

        
        local nm = App.Catalog.referenceFolderName(target)
        if not nm then return end
        idx[nm] = idx[nm] or {}
        table.insert(idx[nm], { boss = battle, drop = drop })
    end
    for _, b in ipairs(App.Catalog.allBattles()) do
        push(b.reward, b, "reward")
        push(b.fragment, b, "fragment")
    end
    catalogCache.sources = idx
    return idx
end


App.Catalog.guiRewardIndex = function()
    if catalogCache.guiRewards then return catalogCache.guiRewards end
    local out = {}

    
    for _, b in ipairs(App.Catalog.collectBosses()) do
        if b.rewards ~= "" or b.fragment ~= "" then
            out[#out + 1] = {
                name = b.name, lvl = b.lvl, r = b.r, tr = b.tr,
                fragChance = b.fragChance,
                hay  = string.lower(b.rewards .. " | " .. b.fragment),
            }
        end
    end
    catalogCache.guiRewards = out
    return out
end

local MAX_SOURCES_PER_ITEM = 3


App.Catalog.findWord = function(hay, needle)
    if not hay or not needle or needle == "" then return false end
    local from = 1
    while true do
        local i, j = string.find(hay, needle, from, true)
        if not i then return false end
        local before = (i == 1) and "" or string.sub(hay, i - 1, i - 1)
        local after  = string.sub(hay, j + 1, j + 1)
        if not string.match(before, "%w") and not string.match(after, "%w") then
            return true
        end
        from = i + 1
    end
end


local TEXT_MATCH_MIN = 2


local LOOSE_MATCH_MIN = 5

App.Catalog.itemBossSources = function(entry)
    local out = {}

    for _, src in ipairs(App.Catalog.bossSourceIndex()[entry.folderName] or {}) do
        out[#out + 1] = src
        if #out >= MAX_SOURCES_PER_ITEM then return out end
    end
    if #out > 0 then return out end

    local a, b = string.lower(entry.label), string.lower(entry.folderName)


    for _, g in ipairs(App.Catalog.guiRewardIndex()) do
        if (#a >= TEXT_MATCH_MIN and App.Catalog.findWord(g.hay, a))
            or (#b >= TEXT_MATCH_MIN and App.Catalog.findWord(g.hay, b)) then
            out[#out + 1] = { boss = g, drop = "text" }
            if #out >= MAX_SOURCES_PER_ITEM then return out end
        end
    end
    if #out > 0 then return out end


    for _, g in ipairs(App.Catalog.guiRewardIndex()) do
        if (#a >= LOOSE_MATCH_MIN and string.find(g.hay, a, 1, true))
            or (#b >= LOOSE_MATCH_MIN and string.find(g.hay, b, 1, true)) then
            out[#out + 1] = { boss = g, drop = "guess" }
            if #out >= MAX_SOURCES_PER_ITEM then break end
        end
    end
    return out
end

App.Catalog.itemSources = function(entry)
    local src = { shop = entry.shop, bosses = App.Catalog.itemBossSources(entry) }

    src.shopTargets = App.Catalog.shopTargets(src.shop)
    src.shopName = src.shop and src.shop.shop or nil

    

    src.any = (src.shop ~= nil) or (#src.bosses > 0) or (entry.ready == true)
    return src
end


App.Catalog.soulCraftLine = function(entry)
    local need = entry.fragments
    if entry.have == nil then

        
        if entry.haveFound then
            return Lang.Craft .. ": ? / " .. App.Format.formatNumber(need)
                .. "  [" .. tostring(entry.haveName) .. "]"
        end
        return Lang.Craft .. ": " .. App.Format.formatNumber(need) .. " " .. Lang.Frags
    end
    local t = Lang.Craft .. ": " .. App.Format.formatNumber(entry.have) .. " / " .. App.Format.formatNumber(need)
    if entry.have >= need then
        t = t .. "  " .. Lang.FragReady
    else
        t = t .. "  (" .. Lang.FragNeed .. " " .. App.Format.formatNumber(need - entry.have) .. ")"
    end

    if entry.haveHow == "guess" then
        t = t .. "  [" .. tostring(entry.haveName) .. "?]"
    end
    return t
end

App.Catalog.itemSourceLines = function(entry, src)
    src = src or App.Catalog.itemSources(entry)
    local lines = {}


    local pl = App.Catalog.permanenceLine(entry.permanent, entry.truePermanent, nil, true)
    if pl then lines[#lines + 1] = pl end


    if entry.kind == "Food" then
        lines[#lines + 1] = Lang.FoodHeal .. ": " .. (entry.heal ~= nil and App.Format.formatNumber(entry.heal) or "?")
        lines[#lines + 1] = Lang.FoodMax .. ": " .. (entry.max ~= nil and tostring(math.floor(entry.max)) or "?")
        if entry.cost ~= nil and not src.shop then
            lines[#lines + 1] = Lang.FoodCost .. ": " .. App.Format.formatNumber(entry.cost) .. " Gold"
        end
        lines[#lines + 1] = Lang.FoodOnSale .. ": "
            .. ((entry.onsale == true and Lang.FoodYes) or (entry.onsale == false and Lang.FoodNo) or "?")
    end

    if src.shop then
        local t = Lang.Shop .. ": " .. (src.shop.shop or "?")
        if src.shop.cost then t = t .. "  |  " .. App.Format.formatNumber(src.shop.cost) .. " Gold" end
        lines[#lines + 1] = t
    end

    if entry.kind == "SOULs" and entry.fragments and entry.fragments > 0 then
        lines[#lines + 1] = App.Catalog.soulCraftLine(entry)
    end
    for _, s in ipairs(src.bosses) do
        local b = s.boss

        
        local tag
        if s.drop == "fragment" then tag = Lang.Frags
        elseif s.drop == "reward" then tag = Lang.Boss
        else tag = Lang.BossGuess end
        local bossLine = tag
            .. ": " .. b.name
            .. " (Lv:" .. App.Format.formatReq(b.lvl or 0)
            .. " | R:" .. App.Format.formatReq(b.r or 0)
            .. " | TR:" .. App.Format.formatReq(b.tr or 0) .. ")"

        
        if b.fragChance ~= nil and (s.drop == "fragment" or entry.kind == "SOULs") then
            bossLine = bossLine .. " | " .. Lang.FragmentChance .. ": "
                .. App.Format.formatFragmentChance(b.fragChance)
        end
        lines[#lines + 1] = bossLine
    end


    

    if not src.any then lines[#lines + 1] = Lang.NoSource end
    return lines
end


App.Results.beginScan = function(kind)
    state.busy = true
    state.messageKey = nil

    state.status = ""
    state.progressWarning = nil
    state.results = {}
    state.count = 0
    state.countKind = kind or "found"
    state.scanned = true

    
    state.resultCap = MAX_RESULTS

    
    state.overflow = nil

    App.Catalog.invalidateCatalog()
end

App.Results.endScan = function(count, kind)
    state.count = count
    if kind then state.countKind = kind end
    state.busy = false
    state.stamp = state.stamp + 1 
end

App.Results.addResult = function(entry)
    if #state.results >= (state.resultCap or MAX_RESULTS) then return end
    table.insert(state.results, entry)
end


App.Results.entryLines = function(e)

    
    if e.rawLines then return e.rawLines end
    if e.lines and e.cacheLang == CurrentLanguage then return e.lines end
    local l = {}
    l[#l + 1] = "Lv:" .. App.Format.formatReq(e.lvl) .. " | R:" .. App.Format.formatReq(e.r) .. " | TR:" .. App.Format.formatReq(e.tr)

    
    if e.noTP then l[#l + 1] = Lang.NoTP end
    if e.source then
        local sourceText = (e.source == "both" and "Lighting + BattleInfoGui")
            or (e.source == "lighting" and "Lighting.Battles")
            or (e.source == "gui" and "BattleInfoGui") or tostring(e.source)
        l[#l + 1] = Lang.Source .. ": " .. sourceText
    end

    local showedSoul = false
    if e.soul and e.soul ~= "" then
        l[#l + 1] = "Soul: " .. e.soul
        showedSoul = true
    elseif e.fragment and e.fragment ~= "" then
        l[#l + 1] = "Soul: " .. (App.Format.extractSoulName(e.fragment) or e.fragment)
        showedSoul = true
    end
    if showedSoul and e.fragChance ~= nil then
        l[#l + 1] = Lang.FragmentChance .. ": " .. App.Format.formatFragmentChance(e.fragChance)
    end
    if showedSoul and (e.soulPermKind or e.soulPermanent ~= nil or e.soulTruePermanent ~= nil) then
        local spl = App.Catalog.permanenceLine(e.soulPermanent, e.soulTruePermanent, Lang.Soul, true)
        if spl then l[#l + 1] = spl end
    end
    if e.material and e.material ~= "" then
        l[#l + 1] = "Material: " .. e.material
    end
    if e.highlight and e.highlight ~= "" then
        l[#l + 1] = e.highlight
    end

    
    if e.rewardLine and e.rewardLine ~= "" then
        l[#l + 1] = e.rewardLine
    else
        l[#l + 1] = App.Format.formatRewards(e.rewards)
    end
    if e.rewardPermKind or e.rewardPermanent ~= nil or e.rewardTruePermanent ~= nil then
        local rpl = App.Catalog.permanenceLine(e.rewardPermanent, e.rewardTruePermanent, Lang.Item, true)
        if rpl then l[#l + 1] = rpl end
    end
    e.lines = l
    e.cacheLang = CurrentLanguage
    return l
end


App.Filters.readStats = function()
    local myL  = App.Format.parseNumberWithSuffix(getInput("utmm_level"))
    local myR  = App.Format.parseNumberWithSuffix(getInput("utmm_resets"))
    local myTR = App.Format.parseNumberWithSuffix(getInput("utmm_tr"))

    local rMaxTxt = getInput("utmm_reset_max")
    local tMaxTxt = getInput("utmm_tr_max")

    local rMin = App.Format.parseNumberWithSuffix(getInput("utmm_reset_min"))
    local rMax = (rMaxTxt ~= "") and App.Format.parseNumberWithSuffix(rMaxTxt) or nil
    local tMin = App.Format.parseNumberWithSuffix(getInput("utmm_tr_min"))
    local tMax = (tMaxTxt ~= "") and App.Format.parseNumberWithSuffix(tMaxTxt) or nil

    local uRF = (rMin > 0 or rMax ~= nil)
    local uTF = (tMin > 0 or tMax ~= nil)

    return myL, myR, myTR, rMin, rMax, tMin, tMax, uRF, uTF
end


App.Filters.bossRequirementLess = function(a, b)
    local aNoTP = a.noTP and 1 or 0
    local bNoTP = b.noTP and 1 or 0
    if aNoTP ~= bNoTP then return aNoTP < bNoTP end

    local atr, btr = a.tr or 0, b.tr or 0
    if atr ~= btr then return atr < btr end

    local ar, br = a.r or 0, b.r or 0
    if ar ~= br then return ar < br end

    local al, bl = a.lvl or 0, b.lvl or 0
    if al ~= bl then return al < bl end

    return string.lower(tostring(a.name or "")) < string.lower(tostring(b.name or ""))
end


App.Features.runCustomScan = function()
    App.Results.beginScan("found")

    state.resultCap = math.huge

    local myL, myR, myTR, rMin, rMax, tMin, tMax, uRF, uTF = App.Filters.readStats()
    local exR  = getToggle("utmm_exact_reset")
    local exTR = getToggle("utmm_exact_tr")
    local incF = getToggle("utmm_include_frag")

    local matches = {}

    for _, b in ipairs(App.Catalog.collectBosses()) do
        local pR = true
        if uRF then
            if b.r < rMin then pR = false end
            if rMax and b.r > rMax then pR = false end
        else
            if exR then
                if b.r ~= myR then pR = false end
            else
                if b.r > myR then pR = false end
            end
        end

        local pTR = true
        if uTF then
            if b.tr < tMin then pTR = false end
            if tMax and b.tr > tMax then pTR = false end
        else
            if exTR then
                if b.tr ~= myTR then pTR = false end
            else
                if b.tr > 0 and b.tr > myTR then pTR = false end
            end
        end

        local pL = (myL >= b.lvl)
        local show = b.hasReward or (b.soul and incF)

        if show and pR and pTR and pL then
            matches[#matches + 1] = {
                name = b.name, lvl = b.lvl, r = b.r, tr = b.tr,
                rewards = b.rewards, rewardLine = b.rewardLine,
                soul = incF and b.soul or nil,
                fragChance = (incF and b.soul) and b.fragChance or nil,
                rewardPermanent = b.rewardPermanent, rewardTruePermanent = b.rewardTruePermanent,
                rewardPermKind = b.rewardPermKind,
                soulPermanent = incF and b.soulPermanent or nil,
                soulTruePermanent = incF and b.soulTruePermanent or nil,
                soulPermKind = incF and b.soulPermKind or nil,
                noTP = b.noTP, source = b.source,
                gui = b.gui,
            }
        end
    end


    table.sort(matches, App.Filters.bossRequirementLess)
    for _, entry in ipairs(matches) do App.Results.addResult(entry) end

    App.Results.endScan(#matches, "found")
end


App.Filters.farmBoundText = function(id)
    local txt = tostring(getInput(id) or "")
    txt = string.match(txt, "^%s*(.-)%s*$") or ""
    return txt
end

App.Features.findBestFarm = function(typeStr)
    App.Results.beginScan("best")

    local myL  = App.Format.parseNumberWithSuffix(getInput("utmm_level"))
    local myR  = App.Format.parseNumberWithSuffix(getInput("utmm_resets"))
    local myTR = App.Format.parseNumberWithSuffix(getInput("utmm_tr"))

    local rMinTxt = App.Filters.farmBoundText("utmm_reset_min")
    local rMaxTxt = App.Filters.farmBoundText("utmm_reset_max")
    local tMinTxt = App.Filters.farmBoundText("utmm_tr_min")
    local tMaxTxt = App.Filters.farmBoundText("utmm_tr_max")


    

    local useRRange = (rMaxTxt ~= "") or (rMinTxt ~= "" and rMinTxt ~= "0")
    local useTRRange = (tMaxTxt ~= "") or (tMinTxt ~= "" and tMinTxt ~= "0")

    local rMin = (rMinTxt ~= "") and App.Format.parseNumberWithSuffix(rMinTxt) or nil
    local rMax = (rMaxTxt ~= "") and App.Format.parseNumberWithSuffix(rMaxTxt) or nil
    local tMin = (tMinTxt ~= "") and App.Format.parseNumberWithSuffix(tMinTxt) or nil
    local tMax = (tMaxTxt ~= "") and App.Format.parseNumberWithSuffix(tMaxTxt) or nil

    local cands = {}

    
    for _, b in ipairs(App.Catalog.collectBosses()) do

        local pL = (b.lvl <= myL)

        local pR = true
        if useRRange then
            if rMin ~= nil and b.r < rMin then pR = false end
            if rMax ~= nil and b.r > rMax then pR = false end
        else

            if b.r > myR then pR = false end
        end

        local pTR = true
        if useTRRange then
            if tMin ~= nil and b.tr < tMin then pTR = false end
            if tMax ~= nil and b.tr > tMax then pTR = false end
        else

            if b.tr > 0 and b.tr > myTR then pTR = false end
        end

        local rewardValue = (typeStr == "Gold") and (b.farmGold or b.gold or 0) or (b.exp or 0)
        if pL and pR and pTR and rewardValue > 0 then
            cands[#cands + 1] = b
        end
    end


    
    table.sort(cands, function(a, b)
        local av = (typeStr == "Gold") and (a.farmGold or a.gold or 0) or (a.exp or 0)
        local bv = (typeStr == "Gold") and (b.farmGold or b.gold or 0) or (b.exp or 0)
        if av ~= bv then return av > bv end
        return App.Filters.bossRequirementLess(a, b)
    end)


    local dc = math.min(10, #cands)
    for i = 1, dc do
        local c = cands[i]
        local baseGold = c.baseGold or c.gold or 0
        local resetGold = c.farmGold or c.guiGold or c.gold or 0
        local farmParts = {}


        

        if baseGold > 0 then
            farmParts[#farmParts + 1] = "Gold Base:" .. App.Format.formatNumber(baseGold)
        end
        if resetGold > 0 then
            farmParts[#farmParts + 1] = "Gold c/ Reset:" .. App.Format.formatNumber(resetGold)
        end
        if typeStr == "Gold" and c.exp and c.exp > 0 then
            farmParts[#farmParts + 1] = "Exp:" .. App.Format.formatNumber(c.exp)
        end
        local farmItem = c.battle and App.Catalog.anyDisplayName(c.battle.reward) or nil
        if farmItem then farmParts[#farmParts + 1] = Lang.Item .. ":" .. farmItem end

        App.Results.addResult({
            name = c.name, lvl = c.lvl, r = c.r, tr = c.tr,
            rewards = c.rewards, rewardLine = table.concat(farmParts, " | "),
            rewardPermanent = c.rewardPermanent, rewardTruePermanent = c.rewardTruePermanent,
            rewardPermKind = c.rewardPermKind,

            
            highlight = (typeStr == "Gold") and nil or ("EXP:" .. App.Format.formatNumber(c.exp or 0)),
            noTP = c.noTP, source = c.source,
            gui = c.gui,
        })
    end

    App.Results.endScan(dc, "best")
end


local TOP5_MODES = { "combined", "trueset", "reset", "level" }

App.Features.findTop5Hardest = function()
    App.Results.beginScan("best")

    local top5SortMode = TOP5_MODES[App.Prefs.getCombo("utmm_top5_sort", 0) + 1] or "combined"


    local cands = {}
    for _, b in ipairs(App.Catalog.collectBosses()) do cands[#cands + 1] = b end

    table.sort(cands, function(a, b)
        if top5SortMode == "trueset" then
            if a.tr ~= b.tr then return a.tr > b.tr end
            if a.r ~= b.r then return a.r > b.r end
            return a.lvl > b.lvl
        elseif top5SortMode == "reset" then
            if a.r ~= b.r then return a.r > b.r end
            if a.tr ~= b.tr then return a.tr > b.tr end
            return a.lvl > b.lvl
        elseif top5SortMode == "level" then
            if a.lvl ~= b.lvl then return a.lvl > b.lvl end
            if a.tr ~= b.tr then return a.tr > b.tr end
            return a.r > b.r
        else
            return (a.tr * 1e6 + a.r * 1e3 + a.lvl) > (b.tr * 1e6 + b.r * 1e3 + b.lvl)
        end
    end)

    local dc = math.min(5, #cands)
    for i = 1, dc do
        local c = cands[i]
        App.Results.addResult({
            name = c.name, lvl = c.lvl, r = c.r, tr = c.tr,
            rewards = c.rewards, rewardLine = c.rewardLine,
            soul = c.soul,
            fragChance = c.fragChance,
            rewardPermanent = c.rewardPermanent, rewardTruePermanent = c.rewardTruePermanent,
            rewardPermKind = c.rewardPermKind,
            soulPermanent = c.soulPermanent, soulTruePermanent = c.soulTruePermanent,
            soulPermKind = c.soulPermKind,
            highlight = "#" .. i .. " | TR:" .. App.Format.formatReq(c.tr)
                .. " | R:" .. App.Format.formatReq(c.r) .. " | Lv:" .. App.Format.formatReq(c.lvl),
            noTP = c.noTP, source = c.source,
            gui = c.gui,
        })
    end

    App.Results.endScan(dc, "best")
end


App.Features.addProgressBlacklist = function(name)
    if not name or name == "" or state.progressBlacklist[name] then return false end
    state.progressBlacklist[name] = true
    table.insert(state.progressBlacklistOrder, name)

    
    App.Persistence.saveConfig()
    return true
end

App.Features.removeProgressBlacklist = function(name)
    if not name or not state.progressBlacklist[name] then return false end
    state.progressBlacklist[name] = nil
    for i = #state.progressBlacklistOrder, 1, -1 do
        if state.progressBlacklistOrder[i] == name then
            table.remove(state.progressBlacklistOrder, i)
            break
        end
    end
    App.Persistence.saveConfig()
    return true
end


App.Config.ProgressMinStepLevels = 3


App.Features.progressBestBossAt = function(cands, level, previousName)
    local bestExp = nil


    for _, c in ipairs(cands) do
        local lv = math.max(1, c.lvl or 1)
        if lv <= level then
            local exp = c.exp or 0
            if bestExp == nil or exp > bestExp then
                bestExp = exp
            end
        end
    end

    if bestExp == nil then return nil, nil end

    local fallback = nil
    local alternative = nil


    
    for _, c in ipairs(cands) do
        local lv = math.max(1, c.lvl or 1)
        if lv <= level and (c.exp or 0) == bestExp then
            if fallback == nil
                or lv > math.max(1, fallback.lvl or 1)
                or (lv == math.max(1, fallback.lvl or 1)
                    and tostring(c.name) < tostring(fallback.name)) then
                fallback = c
            end

            if c.name ~= previousName then
                if alternative == nil
                    or lv > math.max(1, alternative.lvl or 1)
                    or (lv == math.max(1, alternative.lvl or 1)
                        and tostring(c.name) < tostring(alternative.name)) then
                    alternative = c
                end
            end
        end
    end

    return alternative or fallback, bestExp
end

App.Features.progressNextBestChange = function(cands, currentLevel, targetLevel, currentExp, currentName)
    local nextLevel = nil


    

    
    for _, c in ipairs(cands) do
        local lv = math.max(1, c.lvl or 1)
        local exp = c.exp or 0
        if lv > currentLevel and lv <= targetLevel then
            if exp > currentExp or (exp == currentExp and c.name ~= currentName) then
                if nextLevel == nil or lv < nextLevel then
                    nextLevel = lv
                end
            end
        end
    end

    return nextLevel
end

App.Features.progressCollapseShortSteps = function(rawRoute)
    local out = {}

    for _, step in ipairs(rawRoute) do
        local span = (step.finish or step.start) - step.start + 1


        
        if #out > 0 and span < App.Config.ProgressMinStepLevels then
            out[#out].finish = step.finish
        else
            local last = out[#out]
            if last and last.boss and step.boss and last.boss.name == step.boss.name then
                last.finish = step.finish
            else
                out[#out + 1] = step
            end
        end
    end

    return out
end

App.Features.generateProgressRoute = function()

    
    local alvo = App.Format.parseNumberWithSuffix(getInput("utmm_level"))

    App.Results.beginScan("found")

    if alvo <= 0 then
        state.status = Lang.SetLevel
        App.Results.endScan(0, "found")
        return
    end


    
    local _, myR, myTR = App.Filters.readStats()
    local cands = {}

    for _, b in ipairs(App.Catalog.collectBosses()) do
        local passR  = (b.r <= myR)
        local passTR = (b.tr <= 0) or (b.tr <= myTR)

        if not state.progressBlacklist[b.name]
            and passR and passTR and b.lvl <= alvo and b.exp > 0 then
            cands[#cands + 1] = b
        end
    end

    if #cands == 0 then
        state.status = Lang.NoneEligible
        App.Results.endScan(0, "found")
        return
    end

    table.sort(cands, function(a, b)
        if a.lvl ~= b.lvl then return a.lvl < b.lvl end
        if a.exp ~= b.exp then return a.exp > b.exp end
        return tostring(a.name) < tostring(b.name)
    end)

    local firstLevel = nil
    for _, c in ipairs(cands) do
        local lv = math.max(1, c.lvl or 1)
        if lv <= alvo and (firstLevel == nil or lv < firstLevel) then
            firstLevel = lv
        end
    end

    if firstLevel == nil then
        state.status = Lang.NoneEligible
        App.Results.endScan(0, "found")
        return
    end

    if firstLevel > 1 then
        state.progressWarning = Lang.StartGap .. " " .. firstLevel
    end

    local rawRoute = {}
    local current = firstLevel
    local previousName = nil

    while current <= alvo do
        local chosen, bestExp = App.Features.progressBestBossAt(cands, current, previousName)
        if not chosen or bestExp == nil then
            break
        end

        local nextStart = App.Features.progressNextBestChange(
            cands, current, alvo, bestExp, chosen.name
        )
        local finish = nextStart and (nextStart - 1) or alvo

        rawRoute[#rawRoute + 1] = {
            boss = chosen,
            start = current,
            finish = finish,
            exp = bestExp,
        }

        previousName = chosen.name
        if not nextStart then break end
        current = nextStart
    end

    local route = App.Features.progressCollapseShortSteps(rawRoute)

    if #route == 0 then
        state.status = Lang.NoneEligible
        App.Results.endScan(0, "found")
        return
    end

    for i = 1, #route do
        local step = route[i]
        local c = step.boss
        App.Results.addResult({
            name = c.name, lvl = c.lvl, r = c.r, tr = c.tr,
            rewards = "",
            rewardLine = "EXP:" .. App.Format.formatNumber(c.exp),
            highlight = "#" .. i .. "  Lv " .. step.start .. " -> " .. step.finish,
            stepIndex = i,
            noTP = c.noTP,
            source = c.source,
            progressEntry = true,
            gui = c.gui,
        })
    end

    state.status = #route .. " " .. Lang.Steps .. " " .. alvo
    App.Results.endScan(#route, "found")
end


local MISSING_MAX_RESULTS = 80

local MISSING_GROUPS = {
    { kind = "Weapons", titleKey = "MissWeapons" },
    { kind = "Armor",   titleKey = "MissArmors"  },
    { kind = "SOULs",   titleKey = "MissSouls"   },

    { kind = "Food",    titleKey = "MissFoods"   },
}


App.Features.missingRank = function(m)

    if m.entry.ready then
        return -1, (m.src.shop and m.src.shop.cost or 0)
    end
    if m.src.shop then
        return 0, (m.src.shop.cost or math.huge)
    end
    local best = math.huge
    for _, s in ipairs(m.src.bosses) do
        local lv = s.boss.lvl or math.huge
        if lv < best then best = lv end
    end
    return 1, best
end

App.Features.findMissingItems = function()
    App.Results.beginScan("found")
    state.resultCap = MISSING_MAX_RESULTS

    local showAll = getToggle("utmm_missing_all")

    local ownedByKind, existsByKind, anyFolder = {}, {}, false
    for _, def in ipairs(MISSING_GROUPS) do
        local set, exists = App.Catalog.ownedSet(def.kind)
        ownedByKind[def.kind] = set
        existsByKind[def.kind] = exists
        if exists then anyFolder = true end
    end

    if not anyFolder then
        state.status = Lang.MissingNoFolders
        state.overflow = 0
        App.Results.endScan(0, "found")
        return
    end

    local groups, total, noSource, blocked, ready = {}, 0, 0, 0, 0
    for _, def in ipairs(MISSING_GROUPS) do groups[def.kind] = {} end

    for _, entry in ipairs(App.Catalog.allCatalogItems()) do
        local owned = ownedByKind[entry.kind]

        
        if existsByKind[entry.kind] and owned and not owned[entry.folderName] then
            local key = App.Persistence.missingKey(entry.kind, entry.folderName)

            if missingBlacklist[key] then
                blocked = blocked + 1
            else
                local src = App.Catalog.itemSources(entry)
                local include = src.any or showAll
                if not src.any then noSource = noSource + 1 end
                if include then
                    total = total + 1
                    if entry.ready then ready = ready + 1 end
                    table.insert(groups[entry.kind], { entry = entry, src = src, key = key })
                end
            end
        end
    end

    if total == 0 then
        state.status = (blocked > 0)
            and (Lang.MissingNone .. "  (" .. blocked .. " " .. Lang.Blacklist .. ")")
            or Lang.MissingNone
        state.overflow = 0
        App.Results.endScan(0, "found")
        return
    end

    local shown = 0
    for _, def in ipairs(MISSING_GROUPS) do
        local list = groups[def.kind]
        if #list > 0 then
            table.sort(list, function(a, b)
                local ta, va = App.Features.missingRank(a)
                local tb, vb = App.Features.missingRank(b)
                if ta ~= tb then return ta < tb end
                if va ~= vb then return va < vb end
                return a.entry.label < b.entry.label
            end)

            App.Results.addResult({
                label = "-- " .. Lang.MissingTitle .. ": " .. Lang[def.titleKey]
                    .. " (" .. #list .. ") --",
                rawLines = {},
            })
            for i = 1, #list do
                local m = list[i]
                App.Results.addResult({
                    label = i .. ". " .. m.entry.tag .. " " .. m.entry.label,
                    rawLines = App.Catalog.itemSourceLines(m.entry, m.src),

                    shopTargets = m.src.shopTargets,
                    shopName = m.src.shopName,

                    missingKey = m.key,
                })
                shown = shown + 1
            end
        end
    end

    state.overflow = math.max(0, total - shown)
    local extra = ""
    if ready > 0 then
        extra = extra .. "  (" .. ready .. " " .. Lang.FragReady .. ")"
    end
    if not showAll and noSource > 0 then
        extra = extra .. "  (+" .. noSource .. " " .. Lang.NoSource .. ")"
    end
    if blocked > 0 then
        extra = extra .. "  (+" .. blocked .. " " .. Lang.Blacklist .. ")"
    end
    state.status = total .. " " .. Lang.MissingCount .. extra
    App.Results.endScan(total, "found")
end


App.Features.searchBoss = function(q)
    if not q or q == "" then
        state.messageKey = "TypeSomething"
        return
    end

    App.Results.beginScan("found")

    state.resultCap = math.huge

    local sl = string.lower(q)
    local count, found = 0, {}
    local ue = getToggle("utmm_utmoh")


    

    local shopMatches, shopByKey = {}, {}

    

    local allShopNames = { exact = {}, lower = {} }
    for _, def in ipairs(ITEM_KINDS) do
        for _, folder in ipairs(App.Reader.safeChildren(App.Catalog.catalogFolder(def.kind))) do
            local fname = App.Reader.safeName(folder)
            local label = fname and App.Catalog.displayName(folder, def.kind, fname) or nil

            local info = App.Catalog.shopInfo(folder)
            local shopName = info and App.Reader.cleanText(info.shop) or nil
            if shopName then
                local allKey = string.lower(shopName)
                allShopNames.exact[shopName] = allKey
                allShopNames.lower[allKey] = true
            end
            if shopName and string.find(string.lower(shopName), sl, 1, true) then
                local skey = string.lower(shopName)
                local rec = shopByKey[skey]
                if not rec then
                    rec = { name = shopName, items = 0, exact = (skey == sl) }
                    shopByKey[skey] = rec
                    shopMatches[#shopMatches + 1] = rec
                end
                rec.items = rec.items + 1
            end
        end
    end


    
    App.Cache.Workspace.ShopWanted = allShopNames

    table.sort(shopMatches, function(a, b)
        if a.exact ~= b.exact then return a.exact end
        return string.lower(a.name) < string.lower(b.name)
    end)

    local function addShopResult(shop)
        local key = "shop:" .. string.lower(shop.name)
        if found[key] then return end
        found[key] = true
        count = count + 1

        local targets = App.Catalog.findShopTargets(shop.name)
        local lines = { Lang.ShopItems .. ": " .. tostring(shop.items) }
        if #targets > 0 then
            lines[#lines + 1] = Lang.ShopPoints .. ": " .. tostring(#targets)
        else
            lines[#lines + 1] = Lang.ShopNoTP
        end

        App.Results.addResult({
            label = count .. ". " .. Lang.TagShop .. " " .. shop.name,
            rawLines = lines,
            shopTargets = targets,
            shopName = shop.name,
        })
    end


    


    

    local bossMatches = {}
    for _, b in ipairs(App.Catalog.collectBosses()) do
        local bossFoundKey = "boss:" .. tostring(b.stableKey or b.name)
        if not found[bossFoundKey] then
            local bname = tostring(b.name or "")
            local m = string.find(string.lower(bname), sl, 1, true) and true or false
            if not m and b.battle and b.battle.folderName
                and string.find(string.lower(b.battle.folderName), sl, 1, true) then m = true end
            if not m and b.guiName and string.find(string.lower(b.guiName), sl, 1, true) then m = true end
            if not m and b.rewards ~= "" and string.find(string.lower(b.rewards), sl, 1, true) then m = true end
            if not m and b.soul and string.find(string.lower(b.soul), sl, 1, true) then m = true end
            if not m and b.battle then
                local rn = App.Catalog.anyDisplayName(b.battle.reward)
                if rn and string.find(string.lower(rn), sl, 1, true) then m = true end
            end

            local mt = nil
            if ue and b.gui then
                local ml = App.Reader.readText(b.gui, "Material")
                if ml and ml ~= "" then
                    mt = ml
                    if not m and string.find(string.lower(ml), sl, 1, true) then m = true end
                end
            end

            if m then
                found[bossFoundKey] = true
                bossMatches[#bossMatches + 1] = {
                    name = b.name, lvl = b.lvl, r = b.r, tr = b.tr,
                    rewards = b.rewards, rewardLine = b.rewardLine,
                    soul = b.soul,
                    fragChance = b.fragChance,
                    rewardPermanent = b.rewardPermanent, rewardTruePermanent = b.rewardTruePermanent,
                    rewardPermKind = b.rewardPermKind,
                    soulPermanent = b.soulPermanent, soulTruePermanent = b.soulTruePermanent,
                    soulPermKind = b.soulPermKind,
                    material = mt,
                    noTP = b.noTP, source = b.source,
                    gui = b.gui,
                }
            end
        end
    end

    table.sort(bossMatches, App.Filters.bossRequirementLess)
    for _, entry in ipairs(bossMatches) do
        count = count + 1
        App.Results.addResult(entry)
    end


    

    for _, shop in ipairs(shopMatches) do addShopResult(shop) end


    

    local catalogItems = App.Catalog.allCatalogItems()
    for _, entry in ipairs(catalogItems) do
        local hay = string.lower((entry.label or "") .. " " .. (entry.folderName or ""))
        if string.find(hay, sl, 1, true) then
            local key = tostring(entry.tag) .. tostring(entry.label)
            if not found[key] then
                found[key] = true
                count = count + 1
                local src = App.Catalog.itemSources(entry)
                App.Results.addResult({
                    label = count .. ". " .. entry.tag .. " " .. entry.label,
                    rawLines = App.Catalog.itemSourceLines(entry, src),
                    shopTargets = src.shopTargets,
                    shopName = src.shopName,
                })
            end
        end
    end

    App.Results.endScan(count, "found")
    if count == 0 then state.messageKey = "NoResults" end
end


-- DamageIncrease é exibido e usado apenas no ranking hipotético; o ranking principal mantém a fórmula original.
local LV_CAP = 100


local BUILD_MAX_RESULTS = 90
local BUILD_TOP_N = 10
local BUILD_SHOW_MODES = { "summary", "top", "all" }


App.Build.damageAtLevel = function(s, lv)
    local levels = math.max(0, math.min(lv, LV_CAP) - 1)

    return s.damage + levels * s.modify
end


App.Build.hypotheticalDamageAtLevel = function(s, lv)
    local confirmed = App.Build.damageAtLevel(s, lv)
    return confirmed * (1 + (s.increase or 0))
end


App.Build.fmtBuild = function(n)
    if n >= 1e3 then return App.Format.formatNumber(n) end
    if n == math.floor(n) then return tostring(math.floor(n)) end
    local s = string.format("%.2f", n)
    s = string.gsub(s, "0+$", "")
    s = string.gsub(s, "%.$", "")
    return s
end


App.Build.buildLevel = function()
    local lv = App.Format.parseNumberWithSuffix(getInput("utmm_level"))
    if lv <= 0 then return LV_CAP end
    if lv > LV_CAP then return LV_CAP end
    return lv
end


App.Build.shopLine = function(shop)
    if not shop then return nil end
    local t = Lang.Shop .. ": " .. (shop.shop or "?")
    if shop.cost then t = t .. "  |  " .. App.Format.formatNumber(shop.cost) .. " Gold" end
    return t
end

App.Build.weaponDetailLines = function(w)
    if w.missing then return { Lang.BuildNoData } end
    local lines = {
        Lang.BuildDmg .. ": " .. App.Build.fmtBuild(w.total),
        Lang.BuildBase .. " " .. App.Build.fmtBuild(w.damage)
            .. " | +" .. App.Build.fmtBuild(w.modify) .. Lang.BuildPerLv
            .. " | " .. Lang.BuildBoost .. " " .. App.Build.fmtBuild(w.increase * 100) .. "%",
    }
    local pl = App.Catalog.permanenceLine(w.permanent, w.truePermanent, nil, true)
    if pl then lines[#lines + 1] = pl end
    local sl = App.Build.shopLine(w.shop)
    if sl then lines[#lines + 1] = sl end
    return lines
end


App.Build.weaponHypDetailLines = function(w)
    if w.missing then return { Lang.BuildNoData } end
    local lines = {
        Lang.BuildDmg .. ": " .. App.Build.fmtBuild(w.total),
        Lang.BuildBoost .. ": " .. App.Build.fmtBuild((w.increase or 0) * 100) .. "%",
        Lang.BuildHypDamage .. ": " .. App.Build.fmtBuild(w.hypTotal or w.total),
    }
    local pl = App.Catalog.permanenceLine(w.permanent, w.truePermanent, nil, true)
    if pl then lines[#lines + 1] = pl end
    local sl = App.Build.shopLine(w.shop)
    if sl then lines[#lines + 1] = sl end
    return lines
end

App.Build.armorDetailLines = function(a)
    if a.missing then return { Lang.BuildNoData } end
    local lines = { "+" .. App.Build.fmtBuild(a.hp) .. " " .. Lang.BuildHP }
    local pl = App.Catalog.permanenceLine(a.permanent, a.truePermanent, nil, true)
    if pl then lines[#lines + 1] = pl end
    local sl = App.Build.shopLine(a.shop)
    if sl then lines[#lines + 1] = sl end
    return lines
end


App.Build.runBuildScan = function()
    App.Results.beginScan("found")
    state.resultCap = BUILD_MAX_RESULTS
    state.buildWeapon = nil
    state.buildWeaponBoost = nil
    state.buildArmor  = nil

    local lv = App.Build.buildLevel()
    local show = BUILD_SHOW_MODES[App.Prefs.getCombo("utmm_build_show", 1) + 1] or "top"

    local weaponNames, hasWeapons = App.Catalog.ownedNames("Weapons")
    local armorNames,  hasArmors  = App.Catalog.ownedNames("Armor")

    if not hasWeapons and not hasArmors then
        state.status = Lang.BuildNoPlayer
        App.Results.endScan(0, "found")
        return
    end


    local weapons = {}
    for _, nm in ipairs(weaponNames) do
        local s = App.Catalog.weaponStats(nm)
        if s then
            weapons[#weapons + 1] = {
                label = s.label, damage = s.damage, modify = s.modify,
                increase = s.increase, total = App.Build.damageAtLevel(s, lv),
                hypTotal = App.Build.hypotheticalDamageAtLevel(s, lv),
                shop = s.shop,
                permanent = s.permanent, truePermanent = s.truePermanent,
            }
        else

            weapons[#weapons + 1] = { label = nm, missing = true, total = -1, hypTotal = -1 }
        end
    end
    table.sort(weapons, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.label < b.label
    end)


    local armors = {}
    for _, nm in ipairs(armorNames) do
        local s = App.Catalog.armorStats(nm)
        if s then
            armors[#armors + 1] = {
                label = s.label, hp = s.hp, total = s.hp, shop = s.shop,
                permanent = s.permanent, truePermanent = s.truePermanent,
            }
        else
            armors[#armors + 1] = { label = nm, missing = true, total = -1 }
        end
    end
    table.sort(armors, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.label < b.label
    end)


    local bestWeapon, bestWeaponBoost, bestArmor
    for _, w in ipairs(weapons) do
        if not w.missing then
            bestWeapon = w
            break
        end
    end


    
    for _, w in ipairs(weapons) do
        if not w.missing then
            if not bestWeaponBoost
                or (w.hypTotal or -1) > (bestWeaponBoost.hypTotal or -1)
                or ((w.hypTotal or -1) == (bestWeaponBoost.hypTotal or -1) and w.label < bestWeaponBoost.label) then
                bestWeaponBoost = w
            end
        end
    end

    for _, a in ipairs(armors) do
        if not a.missing then
            bestArmor = a
            break
        end
    end


    state.buildWeapon = bestWeapon
        and (bestWeapon.label .. " (" .. App.Build.fmtBuild(bestWeapon.total) .. " " .. Lang.BuildAtLv .. " " .. lv .. ")")
        or Lang.BuildEmpty

    if bestWeaponBoost then
        if bestWeapon and bestWeaponBoost.label == bestWeapon.label then
            state.buildWeaponBoost = Lang.BuildSameBoostWinner
                .. " (" .. App.Build.fmtBuild(bestWeaponBoost.hypTotal) .. " " .. Lang.BuildHypDamage .. ")"
        else
            state.buildWeaponBoost = bestWeaponBoost.label
                .. " (" .. App.Build.fmtBuild(bestWeaponBoost.hypTotal) .. " " .. Lang.BuildHypDamage .. ")"
        end
    else
        state.buildWeaponBoost = Lang.BuildEmpty
    end

    state.buildArmor = bestArmor
        and (bestArmor.label .. " (+" .. App.Build.fmtBuild(bestArmor.hp) .. " " .. Lang.BuildHP .. ")")
        or Lang.BuildEmpty


    App.Results.addResult({
        label = "★ " .. Lang.BestWeaponConfirmed .. " " .. (bestWeapon and bestWeapon.label or Lang.BuildEmpty),
        rawLines = bestWeapon and App.Build.weaponDetailLines(bestWeapon) or { "-" },
        shopTargets = bestWeapon and App.Catalog.shopTargets(bestWeapon.shop) or {},
        shopName = bestWeapon and bestWeapon.shop and bestWeapon.shop.shop or nil,
    })


    
    if bestWeaponBoost and bestWeapon and bestWeaponBoost.label == bestWeapon.label then
        App.Results.addResult({
            label = "★ " .. Lang.BestWeaponBoosted .. " " .. bestWeaponBoost.label,
            rawLines = {
                Lang.BuildSameBoostWinner,
                Lang.BuildHypDamage .. ": " .. App.Build.fmtBuild(bestWeaponBoost.hypTotal),
            },
            shopTargets = {},
        })
    else
        App.Results.addResult({
            label = "★ " .. Lang.BestWeaponBoosted .. " "
                .. (bestWeaponBoost and bestWeaponBoost.label or Lang.BuildEmpty),
            rawLines = bestWeaponBoost and App.Build.weaponHypDetailLines(bestWeaponBoost) or { "-" },
            shopTargets = bestWeaponBoost and App.Catalog.shopTargets(bestWeaponBoost.shop) or {},
            shopName = bestWeaponBoost and bestWeaponBoost.shop and bestWeaponBoost.shop.shop or nil,
        })
    end

    App.Results.addResult({
        label = "★ " .. Lang.BestArmor .. " " .. (bestArmor and bestArmor.label or Lang.BuildEmpty),
        rawLines = bestArmor and App.Build.armorDetailLines(bestArmor) or { "-" },
        shopTargets = bestArmor and App.Catalog.shopTargets(bestArmor.shop) or {},
        shopName = bestArmor and bestArmor.shop and bestArmor.shop.shop or nil,
    })


    state.overflow = 0

    if show ~= "summary" then
        local limit = (show == "all") and math.huge or BUILD_TOP_N
        state.overflow = math.max(0, #weapons - math.min(#weapons, limit))
            + math.max(0, #armors - math.min(#armors, limit))

        App.Results.addResult({
            label = "-- " .. Lang.BuildWeapons .. " (" .. #weapons .. ") | "
                .. Lang.BuildAtLv .. " " .. lv .. " --",
            rawLines = {},
        })
        for i = 1, #weapons do
            if i > limit then break end
            local w = weapons[i]
            App.Results.addResult({
                label = i .. ". " .. w.label, rawLines = App.Build.weaponDetailLines(w),
                shopTargets = App.Catalog.shopTargets(w.shop),
                shopName = w.shop and w.shop.shop or nil,
            })
        end

        App.Results.addResult({
            label = "-- " .. Lang.BuildArmors .. " (" .. #armors .. ") --",
            rawLines = {},
        })
        for i = 1, #armors do
            if i > limit then break end
            local a = armors[i]
            App.Results.addResult({
                label = i .. ". " .. a.label, rawLines = App.Build.armorDetailLines(a),
                shopTargets = App.Catalog.shopTargets(a.shop),
                shopName = a.shop and a.shop.shop or nil,
            })
        end
    end

    state.status = (#weapons + #armors) .. " " .. Lang.BuildOwned
    App.Results.endScan(#weapons + #armors, "found")
end


local FOOD_SLOTS = 8


App.Food.foodAll = function(includeBlacklisted)
    local out = {}
    local root = App.Catalog.catalogFolder("Food")
    for _, folder in pairs(App.Reader.safeChildren(root)) do
        local fname = App.Reader.safeName(folder)
        if fname and fname ~= "" and (includeBlacklisted or not foodBlacklist[fname]) then
            local f = App.Catalog.foodStats(fname, folder)
            if f then out[#out + 1] = f end
        end
    end
    return out
end

App.Food.foodSaleText = function(f)

    
    if f.onsale == true then return Lang.FoodYes end
    return Lang.FoodNo
end

App.Food.foodMaxCopies = function(f)
    if type(f.max) == "number" then
        local m = math.floor(f.max)
        if m < 0 then return 0 end
        return m
    end

    return 1
end

App.Food.foodDetailLines = function(f, copies)
    local lines = {}
    if f.heal == nil then
        lines[#lines + 1] = Lang.FoodHeal .. ": ?"
    else
        local healLine = Lang.FoodHeal .. ": " .. App.Build.fmtBuild(f.heal)
        if copies and copies > 1 then
            healLine = healLine .. " " .. Lang.FoodEach
                .. " | " .. Lang.FoodTotalHeal .. ": " .. App.Build.fmtBuild(f.heal * copies)
        end
        lines[#lines + 1] = healLine
    end

    if f.cost ~= nil then
        local costLine = Lang.FoodCost .. ": " .. App.Format.formatNumber(f.cost) .. " Gold"
        if copies and copies > 1 then
            costLine = costLine .. " " .. Lang.FoodEach
                .. " | " .. Lang.FoodTotalCost .. ": " .. App.Format.formatNumber(f.cost * copies) .. " Gold"
        end
        lines[#lines + 1] = costLine
    else
        lines[#lines + 1] = Lang.FoodCost .. ": " .. Lang.FoodUnknownCost
    end

    lines[#lines + 1] = Lang.FoodMax .. ": " .. tostring(f.max ~= nil and math.floor(f.max) or "?")
    if f.onsale == true then
        lines[#lines + 1] = Lang.FoodOnSale .. ": " .. App.Food.foodSaleText(f)
    else

        lines[#lines + 1] = Lang.FoodNotForSale
    end
    local pl = App.Catalog.permanenceLine(f.permanent, f.truePermanent, nil, true)
    if pl then lines[#lines + 1] = pl end
    if f.shopName and f.shopName ~= "" then
        lines[#lines + 1] = Lang.Shop .. ": " .. f.shopName
    end
    return lines
end

App.Food.foodTier = function(heal, bestHeal)
    if heal == nil then return "?" end
    if heal <= 0 or bestHeal <= 0 then return "F" end
    local r = heal / bestHeal
    if r >= 0.90 then return "S" end
    if r >= 0.75 then return "A" end
    if r >= 0.50 then return "B" end
    if r >= 0.25 then return "C" end
    return "D"
end

App.Food.rerunLastFoodScan = function()
    if state.lastFoodScan == "best8" then
        App.Worker.request(function() App.Food.runBest8() end)
        return true
    elseif state.lastFoodScan == "tier" then
        App.Worker.request(function() App.Food.runTierList() end)
        return true
    end
    state.status = ""
    return false
end

App.Food.runBest8 = function()
    App.Results.beginScan("best")
    state.resultCap = math.huge
    state.lastFoodScan = "best8"

    local foods = App.Food.foodAll(false)
    table.sort(foods, function(a, b)
        local ah, bh = a.heal or -math.huge, b.heal or -math.huge
        if ah ~= bh then return ah > bh end
        local ac, bc = a.cost or math.huge, b.cost or math.huge
        if ac ~= bc then return ac < bc end
        return a.label < b.label
    end)

    local picks, remaining = {}, FOOD_SLOTS
    local totalHeal, totalCost, unknownCostSlots = 0, 0, 0

    for _, f in ipairs(foods) do
        if remaining <= 0 then break end

        
        if f.onsale == true and f.heal and f.heal > 0 then
            local cap = App.Food.foodMaxCopies(f)
            if cap > 0 then
                local take = math.min(cap, remaining)
                picks[#picks + 1] = { food = f, copies = take }
                totalHeal = totalHeal + f.heal * take
                if f.cost ~= nil then
                    totalCost = totalCost + f.cost * take
                else
                    unknownCostSlots = unknownCostSlots + take
                end
                remaining = remaining - take
            end
        end
    end

    if #picks == 0 then
        state.buildFood = Lang.FoodNoValid
        state.status = Lang.FoodNoValid
        state.overflow = 0
        App.Results.endScan(0, "best")
        return
    end

    state.buildFood = picks[1].food.label .. " (" .. App.Build.fmtBuild(picks[1].food.heal) .. " " .. Lang.FoodHeal .. ")"

    local summary = {
        Lang.FoodTotalHeal .. ": " .. App.Build.fmtBuild(totalHeal),
        Lang.FoodTotalCost .. ": " .. App.Format.formatNumber(totalCost) .. " Gold"
            .. (unknownCostSlots > 0 and (" (+" .. unknownCostSlots .. " " .. Lang.FoodUnknownCost .. ")") or ""),
        tostring(FOOD_SLOTS - remaining) .. "/" .. FOOD_SLOTS .. " " .. Lang.FoodSlots,
    }
    if remaining > 0 then summary[#summary + 1] = Lang.FoodBuildIncomplete end

    App.Results.addResult({ label = "★ " .. Lang.FoodBuildTitle, rawLines = summary })

    local slot = 1
    for _, pick in ipairs(picks) do
        local f, copies = pick.food, pick.copies
        local label
        if copies == 1 then
            label = slot .. ". " .. f.label
        else
            label = slot .. "-" .. (slot + copies - 1) .. ". " .. f.label .. " x" .. copies
        end
        App.Results.addResult({
            label = label,
            rawLines = App.Food.foodDetailLines(f, copies),

            
            shopTargets = App.Catalog.shopTargets(f.shopTarget),
            shopName = f.shopName,
            foodBlacklistKey = f.folderName,
        })
        slot = slot + copies
    end

    state.overflow = 0
    state.status = tostring(FOOD_SLOTS - remaining) .. "/" .. FOOD_SLOTS .. " " .. Lang.FoodSlots
    App.Results.endScan(#picks, "best")
end

App.Food.runTierList = function()
    App.Results.beginScan("best")
    state.resultCap = math.huge
    state.lastFoodScan = "tier"

    local foods = App.Food.foodAll(false)
    local bestHeal = 0
    for _, f in ipairs(foods) do
        if f.heal and f.heal > bestHeal then bestHeal = f.heal end
    end

    local tierOrder = { S = 1, A = 2, B = 3, C = 4, D = 5, F = 6, ["?"] = 7 }
    for _, f in ipairs(foods) do f.tier = App.Food.foodTier(f.heal, bestHeal) end
    table.sort(foods, function(a, b)
        local ta, tb = tierOrder[a.tier] or 99, tierOrder[b.tier] or 99
        if ta ~= tb then return ta < tb end
        local ah, bh = a.heal or -math.huge, b.heal or -math.huge
        if ah ~= bh then return ah > bh end
        local ac, bc = a.cost or math.huge, b.cost or math.huge
        if ac ~= bc then return ac < bc end
        return a.label < b.label
    end)

    if #foods == 0 then
        state.buildFood = Lang.FoodNoValid
        state.status = Lang.FoodNoValid
        state.overflow = 0
        App.Results.endScan(0, "best")
        return
    end

    state.buildFood = foods[1].label .. " (" .. App.Build.fmtBuild(foods[1].heal or 0) .. " " .. Lang.FoodHeal .. ")"
    App.Results.addResult({ label = "★ " .. Lang.FoodTierTitle, rawLines = { Lang.FoodTierRule } })

    for i, f in ipairs(foods) do
        App.Results.addResult({
            label = i .. ". [" .. f.tier .. "] " .. f.label,
            rawLines = App.Food.foodDetailLines(f, nil),

            
            shopTargets = App.Catalog.shopTargets(f.shopTarget),
            shopName = f.shopName,
            foodBlacklistKey = f.folderName,
        })
    end

    state.overflow = 0
    state.status = #foods .. " " .. Lang.FoodSection
    App.Results.endScan(#foods, "best")
end


-- UI independente (Wabi Sabi Drawing)
App.Worker.request = function(fn)
    if not App.Runtime.Alive or type(fn) ~= "function" then return end
    state.busy = true
    state.messageKey = nil
    state.stamp = state.stamp + 1
    App.Runtime.PendingJob = fn
    App.UI.refreshStatus()
end

App.UI.prefSet = function(id, value, persist)
    uiCache[id] = value
    if persist then App.Persistence.saveConfig() end
    App.UI.refreshSummaries()
end

App.UI.statsSummary = function()
    return "LV " .. tostring(App.Prefs.inputDefault("utmm_level"))
        .. "  |  R " .. tostring(App.Prefs.inputDefault("utmm_resets"))
        .. "  |  TR " .. tostring(App.Prefs.inputDefault("utmm_tr"))
        .. "\nR: " .. tostring(App.Prefs.inputDefault("utmm_reset_min")) .. " → " .. tostring(App.Prefs.inputDefault("utmm_reset_max"))
        .. "  |  TR: " .. tostring(App.Prefs.inputDefault("utmm_tr_min")) .. " → " .. tostring(App.Prefs.inputDefault("utmm_tr_max"))
end

App.UI.statusText = function()
    if state.busy then return Lang.Searching end
    if state.messageKey then return Lang[state.messageKey] or "" end
    if not state.scanned then return "0 " .. Lang.Found end
    return tostring(state.count) .. " " .. ((state.countKind == "best") and Lang.Best or Lang.Found)
end

App.UI.destroyHandles = function(list)
    if type(list) ~= "table" then return end
    for i = #list, 1, -1 do
        local h = list[i]
        if h and type(h.Destroy) == "function" then pcall(function() h:Destroy() end) end
        list[i] = nil
    end
end

App.UI.track = function(list, handle)
    if handle then list[#list + 1] = handle end
    return handle
end

App.UI.refreshStatus = function()
    local content = App.UI.statusText()
    if state.status and state.status ~= "" then content = content .. "\n" .. state.status end
    if state.fragDiag and state.fragDiag ~= "" then content = content .. "\n" .. state.fragDiag end
    local p = App.UI.StatusParagraph
    if p and type(p.SetContent) == "function" then
        pcall(function() p:SetContent(content) end)
    end
    local progress = App.UI.ProgressStatusParagraph
    if progress and type(progress.SetContent) == "function" then
        pcall(function() progress:SetContent((state.status ~= "" and state.status or "-")
            .. (state.fragDiag and ("\n" .. state.fragDiag) or "")) end)
    end
    local build = App.UI.BuildSummaryParagraph
    if build and type(build.SetContent) == "function" then
        pcall(function() build:SetContent(
            Lang.BestWeaponConfirmed .. " " .. tostring(state.buildWeapon or "-")
            .. "\n" .. Lang.BestWeaponBoosted .. " " .. tostring(state.buildWeaponBoost or "-")
            .. "\n" .. Lang.BestArmor .. " " .. tostring(state.buildArmor or "-")
            .. "\n" .. Lang.BestFood .. " " .. tostring(state.buildFood or "-")
        ) end)
    end
end

App.UI.refreshSummaries = function()
    local text = App.UI.statsSummary()
    for _, p in pairs(App.UI.StatsParagraphs or {}) do
        if p and type(p.SetContent) == "function" then pcall(function() p:SetContent(text) end) end
    end
    App.UI.refreshStatus()
end

App.UI.renderProgressBlacklists = function()
    local ui = App.UI
    if not ui.ProgressBlacklistSection then return end
    App.UI.destroyHandles(ui.ProgressBlacklistHandles)
    ui.ProgressBlacklistHandles = {}
    local list = state.progressBlacklistOrder
    App.UI.track(ui.ProgressBlacklistHandles, ui.ProgressBlacklistSection:AddParagraph({
        Title = Lang.BlacklistTitle,
        Content = (#list == 0) and Lang.BlacklistEmpty or (tostring(#list) .. " " .. Lang.Blacklist),
    }))
    if #list > 0 then
        local selected = list[1]
        local dd = App.UI.track(ui.ProgressBlacklistHandles, ui.ProgressBlacklistSection:AddDropdown({
            Title = Lang.Blacklist,
            Values = list,
            Default = selected,
            Searchable = #list > 8,
            Callback = function(v) selected = v end,
        }))
        App.UI.track(ui.ProgressBlacklistHandles, ui.ProgressBlacklistSection:AddButton({
            Title = Lang.RemoveBlacklist,
            Callback = function()
                local value = (dd and dd.Value) or selected
                if App.Features.removeProgressBlacklist(value) then
                    App.UI.renderProgressBlacklists()
                    App.Worker.request(function() App.Features.generateProgressRoute() end)
                end
            end,
        }))
    end
end

App.UI.renderMissingBlacklist = function()
    local ui = App.UI
    if not ui.MissingBlacklistSection then return end
    App.UI.destroyHandles(ui.MissingBlacklistHandles)
    ui.MissingBlacklistHandles = {}
    local list = missingBlacklistOrder
    App.UI.track(ui.MissingBlacklistHandles, ui.MissingBlacklistSection:AddParagraph({
        Title = Lang.MissBlacklistTitle,
        Content = (#list == 0) and Lang.MissBlacklistEmpty
            or (tostring(#list) .. "\n" .. (CAN_PERSIST and (Lang.SavedFor .. " PlaceId " .. PLACE_KEY) or Lang.NoPersist)),
    }))
    if #list > 0 then
        local labels, byLabel = {}, {}
        for _, key in ipairs(list) do
            local label = App.Persistence.missingBlacklistLabel(key)
            labels[#labels + 1] = label
            byLabel[label] = key
        end
        local selected = labels[1]
        local dd = App.UI.track(ui.MissingBlacklistHandles, ui.MissingBlacklistSection:AddDropdown({
            Title = Lang.Blacklist,
            Values = labels,
            Default = selected,
            Searchable = #labels > 8,
            Callback = function(v) selected = v end,
        }))
        App.UI.track(ui.MissingBlacklistHandles, ui.MissingBlacklistSection:AddButton({
            Title = Lang.RemoveBlacklist,
            Callback = function()
                local label = (dd and dd.Value) or selected
                local key = byLabel[label]
                if key and App.Persistence.removeMissingBlacklist(key) then
                    App.UI.renderMissingBlacklist()
                    App.Worker.request(function() App.Features.findMissingItems() end)
                end
            end,
        }))
        App.UI.track(ui.MissingBlacklistHandles, ui.MissingBlacklistSection:AddButton({
            Title = Lang.ClearBlacklist,
            Callback = function()
                if App.Persistence.clearMissingBlacklist() then
                    App.UI.renderMissingBlacklist()
                    App.Worker.request(function() App.Features.findMissingItems() end)
                end
            end,
        }))
    end
end

App.UI.renderFoodBlacklist = function()
    local ui = App.UI
    if not ui.FoodBlacklistSection then return end
    App.UI.destroyHandles(ui.FoodBlacklistHandles)
    ui.FoodBlacklistHandles = {}
    local list = foodBlacklistOrder
    App.UI.track(ui.FoodBlacklistHandles, ui.FoodBlacklistSection:AddParagraph({
        Title = Lang.FoodBlacklistTitle,
        Content = (#list == 0) and Lang.FoodBlacklistEmpty
            or (tostring(#list) .. "\n" .. (CAN_PERSIST and (Lang.SavedFor .. " PlaceId " .. PLACE_KEY) or Lang.NoPersist)),
    }))
    if #list > 0 then
        local values = {}
        for _, key in ipairs(list) do
            local folder = App.Catalog.itemFolder("Food", key)
            local fs = folder and App.Catalog.foodStats(key, folder) or nil
            values[#values + 1] = {
                key = key,
                label = fs and fs.label or key,
                heal = fs and fs.heal or nil,
                cost = fs and fs.cost or nil,
            }
        end
        local selected = values[1]
        local dd = App.UI.track(ui.FoodBlacklistHandles, ui.FoodBlacklistSection:AddDropdown({
            Title = Lang.Blacklist,
            Values = values,
            Default = selected,
            Searchable = #values > 8,
            Displayer = function(v)
                if type(v) ~= "table" then return tostring(v) end
                local heal = (v.heal ~= nil) and App.Build.fmtBuild(v.heal) or "?"
                local cost = (v.cost ~= nil) and (App.Format.formatNumber(v.cost) .. " Gold") or Lang.FoodUnknownCost
                return tostring(v.label) .. " | " .. Lang.FoodHeal .. ": " .. heal .. " | " .. Lang.FoodCost .. ": " .. cost
            end,
            Callback = function(v) selected = v end,
        }))
        App.UI.track(ui.FoodBlacklistHandles, ui.FoodBlacklistSection:AddButton({
            Title = Lang.RemoveBlacklist,
            Callback = function()
                local value = (dd and dd.Value) or selected
                local key = type(value) == "table" and value.key or value
                if key and App.Persistence.removeFoodBlacklist(key) then
                    App.UI.renderFoodBlacklist()
                    App.Food.rerunLastFoodScan()
                end
            end,
        }))
        App.UI.track(ui.FoodBlacklistHandles, ui.FoodBlacklistSection:AddButton({
            Title = Lang.FoodClearBlacklist,
            Callback = function()
                if App.Persistence.clearFoodBlacklist() then
                    App.UI.renderFoodBlacklist()
                    App.Food.rerunLastFoodScan()
                end
            end,
        }))
    end
end

App.UI.resultTitle = function(entry, index)
    return entry.label or (tostring(entry.stepIndex or index) .. ". " .. tostring(entry.name or "?"))
end

App.UI.addShopAction = function(section, handles, entry, index)
    if not entry.shopTargets or #entry.shopTargets == 0 or not entry.shopName then return end
    if #entry.shopTargets == 1 then
        local target = entry.shopTargets[1]
        App.UI.track(handles, section:AddButton({
            Title = Lang.TPShop .. " · " .. tostring(target.name),
            Callback = function() App.Teleport.teleportToShopPoint(target) end,
        }))
        return
    end
    local selected = entry.shopTargets[1]
    local dd = App.UI.track(handles, section:AddDropdown({
        Title = Lang.ShopPoint .. " · " .. tostring(entry.shopName),
        Values = entry.shopTargets,
        Default = selected,
        MaxItems = 8,
        Displayer = function(v) return tostring(v and v.name or "Part") end,
        Callback = function(v) selected = v end,
    }))
    App.UI.track(handles, section:AddButton({
        Title = Lang.TPShop,
        Callback = function() App.Teleport.teleportToShopPoint((dd and dd.Value) or selected) end,
    }))
end

App.UI.renderResults = function(selectTab)
    local ui = App.UI
    if not ui.ResultSection then return end
    App.UI.refreshStatus()
    App.UI.destroyHandles(ui.ResultHandles)
    ui.ResultHandles = {}
    local handles = ui.ResultHandles

    if state.progressWarning and state.progressWarning ~= "" then
        App.UI.track(handles, ui.ResultSection:AddParagraph({ Title = "!", Content = state.progressWarning }))
    end

    if #state.results == 0 then
        App.UI.track(handles, ui.ResultSection:AddParagraph({ Title = Lang.Results, Content = "-" }))
    else
        for i = 1, #state.results do
            local entry = state.results[i]
            local lines = App.Results.entryLines(entry)
            App.UI.track(handles, ui.ResultSection:AddParagraph({
                Title = App.UI.resultTitle(entry, i),
                Content = (#lines > 0) and table.concat(lines, "\n") or "-",
            }))

            if entry.gui then
                local gui = entry.gui
                App.UI.track(handles, ui.ResultSection:AddButton({
                    Title = Lang.TP,
                    Callback = function() App.Teleport.teleportTo(gui) end,
                }))
            end

            App.UI.addShopAction(ui.ResultSection, handles, entry, i)

            if entry.foodBlacklistKey then
                local key = entry.foodBlacklistKey
                App.UI.track(handles, ui.ResultSection:AddButton({
                    Title = Lang.Blacklist .. " · " .. tostring(entry.name or entry.label or key),
                    Callback = function()
                        if App.Persistence.addFoodBlacklist(key) then
                            App.UI.renderFoodBlacklist()
                            App.Food.rerunLastFoodScan()
                        end
                    end,
                }))
            end

            if entry.missingKey then
                local key = entry.missingKey
                App.UI.track(handles, ui.ResultSection:AddButton({
                    Title = Lang.Blacklist .. " · " .. key,
                    Callback = function()
                        if App.Persistence.addMissingBlacklist(key) then
                            App.UI.renderMissingBlacklist()
                            App.Worker.request(function() App.Features.findMissingItems() end)
                        end
                    end,
                }))
            end

            if entry.progressEntry then
                local name = entry.name
                App.UI.track(handles, ui.ResultSection:AddButton({
                    Title = Lang.Blacklist .. " · " .. tostring(name),
                    Callback = function()
                        if App.Features.addProgressBlacklist(name) then
                            App.UI.renderProgressBlacklists()
                            App.Worker.request(function() App.Features.generateProgressRoute() end)
                        end
                    end,
                }))
            end
        end

        local overflow = state.overflow
        if overflow == nil and state.count > #state.results then overflow = state.count - #state.results end
        if overflow and overflow > 0 then
            App.UI.track(handles, ui.ResultSection:AddParagraph({ Title = "…", Content = "+" .. tostring(overflow) }))
        end
    end

    if selectTab and ui.Window and ui.ResultTabIndex then
        pcall(function() ui.Window:SelectTab(ui.ResultTabIndex) end)
    end
end

App.UI.loadLibrary = function()
    if not App.Cache.UISource then
        local body = game:HttpGet(App.Config.UILibraryUrl)
        assert(type(body) == "string" and #body > 1000 and string.find(body, "WabiSabi", 1, true),
            "[UTMM Guider] Falha ao carregar a Wabi Sabi UI Library.")
        App.Cache.UISource = body
    end
    loadstring(App.Cache.UISource, "Wabi Sabi UI")()
    local library = WabiSabi
    assert(type(library) == "table" and type(library.CreateWindow) == "function" and library.Unloaded ~= true,
        "[UTMM Guider] Wabi Sabi não inicializou corretamente.")
    return library
end

App.UI.rebuild = function()
    if not App.Runtime.Alive then return end
    App.Persistence.saveConfig()
    App.UI.Rebuilding = true
    local old = App.UI.Library
    if old and type(old.Destroy) == "function" and not old.Unloaded then
        pcall(function() old:Destroy() end)
    end
    App.UI.Library = App.UI.loadLibrary()
    App.UI.build()
    App.UI.Rebuilding = false
end

App.UI.addStatsSummary = function(tab)
    local p = tab:AddParagraph({ Title = Lang.YourStats, Content = App.UI.statsSummary() })
    App.UI.StatsParagraphs[#App.UI.StatsParagraphs + 1] = p
    return p
end

App.UI.build = function()
    local library = App.UI.Library
    local window = library:CreateWindow({
        Title = "UTMM Guider",
        SubTitle = "v" .. App.Version,
        Size = Vector2.new(700, 520),
        MinSize = Vector2.new(560, 430),
        Resize = true,
        TabWidth = 150,
        Theme = "Dark",
        Translucent = true,
        MinimizeKey = "End",
    })

    App.UI.Window = window
    App.UI.StatsParagraphs = {}
    App.UI.ResultHandles = {}
    App.UI.ProgressBlacklistHandles = {}
    App.UI.MissingBlacklistHandles = {}
    App.UI.FoodBlacklistHandles = {}
    App.UI.Inputs = {}

    local scanner = window:AddTab({ Title = Lang.Scanner, Icon = "scan-search" })
    App.UI.addStatsSummary(scanner)
    local ssec = scanner:AddSection(Lang.Scanner)
    ssec:AddToggle({ Title = Lang.BossesInReset, Default = App.Prefs.toggleDefault("utmm_exact_reset"), Callback = function(v) App.UI.prefSet("utmm_exact_reset", v, false) end })
    ssec:AddToggle({ Title = Lang.BossesInTrueReset, Default = App.Prefs.toggleDefault("utmm_exact_tr"), Callback = function(v) App.UI.prefSet("utmm_exact_tr", v, false) end })
    ssec:AddToggle({ Title = Lang.IncludeFragments, Default = App.Prefs.toggleDefault("utmm_include_frag"), Callback = function(v) App.UI.prefSet("utmm_include_frag", v, false) end })
    ssec:AddButton({ Title = Lang.Scan, Callback = function() App.Worker.request(function() App.Features.runCustomScan() end) end })

    local search = window:AddTab({ Title = Lang.SearchBoss, Icon = "search" })
    App.UI.addStatsSummary(search)
    local qsec = search:AddSection(Lang.SearchBoss)
    qsec:AddToggle({ Title = Lang.UTMOHMaterials, Default = App.Prefs.toggleDefault("utmm_utmoh"), Callback = function(v) App.UI.prefSet("utmm_utmoh", v, false) end })
    local searchInput = qsec:AddInput({
        Title = Lang.Search,
        Default = App.Prefs.inputDefault("utmm_search"),
        Placeholder = Lang.SearchPlaceholder,
        Finished = true,
        Callback = function(v)
            App.UI.prefSet("utmm_search", tostring(v or ""), false)
            App.Worker.request(function() App.Features.searchBoss(tostring(v or "")) end)
        end,
    })
    qsec:AddButton({ Title = Lang.SearchBtn, Callback = function()
        local q = searchInput and searchInput.Value or App.Prefs.inputDefault("utmm_search")
        App.UI.prefSet("utmm_search", tostring(q or ""), false)
        App.Worker.request(function() App.Features.searchBoss(tostring(q or "")) end)
    end })

    local progress = window:AddTab({ Title = Lang.Progress, Icon = "route" })
    App.UI.addStatsSummary(progress)
    local psec = progress:AddSection(Lang.Progress)
    psec:AddParagraph({ Title = Lang.Progress, Content = Lang.ProgressDesc })
    App.UI.ProgressStatusParagraph = psec:AddParagraph({ Title = Lang.Results, Content = state.status ~= "" and state.status or "-" })
    psec:AddButton({ Title = Lang.GenRoute, Callback = function() App.Worker.request(function() App.Features.generateProgressRoute() end) end })
    local msec = progress:AddSection(Lang.MissingBtn)
    msec:AddToggle({ Title = Lang.MissingAll, Default = App.Prefs.toggleDefault("utmm_missing_all"), Callback = function(v) App.UI.prefSet("utmm_missing_all", v, false) end })
    msec:AddButton({ Title = Lang.MissingBtn, Callback = function() App.Worker.request(function() App.Features.findMissingItems() end) end })
    App.UI.MissingBlacklistSection = progress:AddSection(Lang.MissBlacklistTitle)
    App.UI.ProgressBlacklistSection = progress:AddSection(Lang.BlacklistTitle)

    local farms = window:AddTab({ Title = Lang.Farms, Icon = "wheat" })
    App.UI.addStatsSummary(farms)
    local fsec = farms:AddSection(Lang.Farms)
    fsec:AddParagraph({ Title = Lang.Farms, Content = Lang.FarmDesc })
    fsec:AddButton({ Title = Lang.FarmExp, Callback = function() App.Worker.request(function() App.Features.findBestFarm("Exp") end) end })
    fsec:AddButton({ Title = Lang.FarmGold, Callback = function() App.Worker.request(function() App.Features.findBestFarm("Gold") end) end })

    local build = window:AddTab({ Title = Lang.Build, Icon = "hammer" })
    App.UI.addStatsSummary(build)
    local bsec = build:AddSection(Lang.Build)
    local showOptions = { Lang.BuildSummary, Lang.BuildTop10, Lang.BuildAll }
    local currentShow = showOptions[App.Prefs.getCombo("utmm_build_show", 1) + 1] or showOptions[2]
    bsec:AddDropdown({ Title = Lang.BuildShow, Values = showOptions, Default = currentShow, Callback = function(v)
        local idx = 1
        for i, text in ipairs(showOptions) do if text == v then idx = i - 1 break end end
        App.UI.prefSet("utmm_build_show", idx, false)
    end })
    bsec:AddButton({ Title = Lang.BuildScan, Callback = function() App.Worker.request(function() App.Build.runBuildScan() end) end })
    local food = build:AddSection(Lang.FoodSection)
    food:AddButton({ Title = Lang.FoodBest8, Callback = function() App.Worker.request(function() App.Food.runBest8() end) end })
    food:AddButton({ Title = Lang.FoodTierList, Callback = function() App.Worker.request(function() App.Food.runTierList() end) end })
    App.UI.FoodBlacklistSection = build:AddSection(Lang.FoodBlacklistTitle)
    App.UI.BuildSummaryParagraph = build:AddParagraph({
        Title = Lang.Build,
        Content = Lang.BestWeaponConfirmed .. " " .. tostring(state.buildWeapon or "-")
            .. "\n" .. Lang.BestWeaponBoosted .. " " .. tostring(state.buildWeaponBoost or "-")
            .. "\n" .. Lang.BestArmor .. " " .. tostring(state.buildArmor or "-")
            .. "\n" .. Lang.BestFood .. " " .. tostring(state.buildFood or "-"),
    })

    local top = window:AddTab({ Title = Lang.Top5, Icon = "trophy" })
    local tsec = top:AddSection(Lang.Top5)
    tsec:AddParagraph({ Title = Lang.Top5Title, Content = Lang.Top5Desc })
    local topOptions = { Lang.ByCombined, Lang.ByTrueReset, Lang.ByReset, Lang.ByLevel }
    local topDefault = topOptions[App.Prefs.getCombo("utmm_top5_sort", 0) + 1] or topOptions[1]
    tsec:AddDropdown({ Title = Lang.SortBy, Values = topOptions, Default = topDefault, Callback = function(v)
        local idx = 0
        for i, text in ipairs(topOptions) do if text == v then idx = i - 1 break end end
        App.UI.prefSet("utmm_top5_sort", idx, false)
    end })
    tsec:AddButton({ Title = Lang.Top5Scan, Callback = function() App.Worker.request(function() App.Features.findTop5Hardest() end) end })

    local results = window:AddTab({ Title = Lang.Results, Icon = "list" })
    App.UI.ResultTabIndex = 7
    App.UI.StatusParagraph = results:AddParagraph({ Title = Lang.Results, Content = App.UI.statusText() })
    App.UI.ResultSection = results:AddSection(Lang.Results)

    local config = window:AddTab({ Title = "Config", Icon = "settings" })
    local csec = config:AddSection(Lang.YourStats)
    local langDefault = (CurrentLanguage == "EN") and "EN" or "PT"
    csec:AddDropdown({ Title = "PT / EN", Values = { "PT", "EN" }, Default = langDefault, Callback = function(v)
        local idx = (v == "EN") and 1 or 0
        if ((idx == 1) and CurrentLanguage ~= "EN") or ((idx == 0) and CurrentLanguage ~= "PT") then
            App.I18n.syncLanguage(idx)
            uiCache.utmm_lang = idx
            spawn(function() wait(0) App.UI.rebuild() end)
        end
    end })

    local function addInput(id, title, placeholder)
        local handle = csec:AddInput({
            Title = title,
            Default = App.Prefs.inputDefault(id),
            Placeholder = placeholder or "0",
            Finished = true,
            Callback = function(v) App.UI.prefSet(id, tostring(v or ""), true) end,
        })
        App.UI.Inputs[id] = handle
        return handle
    end
    addInput("utmm_level", Lang.Level)
    addInput("utmm_resets", Lang.Resets)
    addInput("utmm_tr", Lang.TrueResets)
    addInput("utmm_reset_min", Lang.FilterReset .. " MIN")
    addInput("utmm_reset_max", Lang.FilterReset .. " MAX", "")
    addInput("utmm_tr_min", Lang.FilterTR .. " MIN")
    addInput("utmm_tr_max", Lang.FilterTR .. " MAX", "")
    csec:AddParagraph({ Title = "Formato", Content = "K / M / B / T / Qa / Qi / Sx / Sp / Oc / No / Dc" })

    local persist = config:AddSection("Persistência")
    persist:AddParagraph({
        Title = CAN_PERSIST and (Lang.SavedFor .. " PlaceId " .. PLACE_KEY) or Lang.NoPersist,
        Content = CONFIG_FILE,
    })
    window:BuildInterfaceSection(config)
    local actions = config:AddSection("UTMM Guider")
    actions:AddButton({ Title = "Unload UTMM Guider", Callback = function() App.Cleanup() end })

    library:OnUnload(function()
        if not App.UI.Rebuilding and App.Runtime.Alive then App.Cleanup(true) end
    end)

    App.UI.renderMissingBlacklist()
    App.UI.renderProgressBlacklists()
    App.UI.renderFoodBlacklist()
    App.UI.renderResults(false)
    App.UI.refreshSummaries()
end

App.Cleanup = function(fromLibrary)
    if not App.Runtime.Alive then return end
    App.Persistence.saveConfig()
    App.Runtime.Alive = false
    App.Runtime.PendingJob = nil
    local library = App.UI.Library
    App.UI.Library = nil
    if not fromLibrary and library and type(library.Destroy) == "function" and not library.Unloaded then
        pcall(function() library:Destroy() end)
    end
    if ENV.__UTMM_GUIDER_APP == App then ENV.__UTMM_GUIDER_APP = nil end
end

App.Persistence.loadConfig()
App.I18n.syncLanguage(App.Prefs.comboDefault("utmm_lang"))
App.UI.Library = App.UI.loadLibrary()
App.UI.build()

spawn(function()
    while App.Runtime.Alive do
        local job = App.Runtime.PendingJob
        if job then
            App.Runtime.PendingJob = nil
            notify(Lang.Searching, "UTMM Guider", 1)
            local ok, err = pcall(job)
            if not ok then
                state.busy = false
                warn("[UTMM Guider] " .. tostring(err))
                local lib = App.UI.Library
                if lib and type(lib.Notify) == "function" then
                    pcall(function() lib:Notify({ Title = "UTMM Guider", Content = tostring(err), Duration = 5 }) end)
                end
            end
            App.UI.renderMissingBlacklist()
            App.UI.renderProgressBlacklists()
            App.UI.renderFoodBlacklist()
            App.UI.renderResults(true)
            App.UI.refreshSummaries()
            notify(tostring(state.count) .. " " .. ((state.countKind == "best") and Lang.Best or Lang.Found), "UTMM Guider", 2)
        end
        wait(0.05)
    end
end)

print(Lang.Loaded)
notify(Lang.Loaded, "UTMM Guider", 4)
