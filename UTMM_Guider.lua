-- UTMM Guider - Matcha LuaVM
-- UI propria em Drawing; logica de catalogo/scans preservada do arquivo anexado.

if Drawing == nil or type(Drawing.new) ~= "function" then
    assert(false, "[UTMM Guider] Drawing.new nao esta disponivel nesta build do Matcha.")
end

----------------------------------------------------------------
-- SERVICOS / CONSTANTES / ESTADO
----------------------------------------------------------------

local function getService(name)
    local ok, s = pcall(function() return game:GetService(name) end)
    if ok then return s end
    return nil
end

local Players     = getService("Players")
local Workspace   = getService("Workspace") or workspace
local HttpService = getService("HttpService")
-- O UTMM guarda o catalogo de itens em Lighting (Weapons / Armor).
local Lighting    = getService("Lighting")

local LocalPlayer
do
    local ok, p = pcall(function() return Players.LocalPlayer end)
    if ok then LocalPlayer = p end
end

local MAX_RESULTS = 50
local CONFIG_FILE = "utmm_guider.json"

local state = {
    results   = {},      -- linhas exibidas (cap = MAX_RESULTS)
    count     = 0,       -- total real de matches (pode ser > #results)
    countKind = "found", -- "found" | "best"
    messageKey = nil,    -- chave de Translations p/ mensagem de status
    -- Status e aviso exclusivos da pagina de Progressao.
    status    = "",
    progressWarning = nil,
    -- Mapa + ordem de insercao. A blacklist vale somente para
    --             a Progressao e persiste por PlaceId.
    progressBlacklist = {},
    progressBlacklistOrder = {},
    busy      = false,
    scanned   = false,
    stamp     = 0,       -- contador de scans (aparece no titulo da lista)
    -- Resumo persistente da ultima analise, desenhado no painel esquerdo
    --         (fica visivel mesmo depois de outro scan sobrescrever a lista).
    buildWeapon = nil,
    -- Segunda recomendacao: ranking hipotetico aplicando DamageIncrease.
    buildWeaponBoost = nil,
    buildArmor  = nil,
    -- Resumo da melhor comida / ultimo modo de scan de comidas.
    buildFood   = nil,
    lastFoodScan = nil,
    -- Teto de linhas do scan atual; a Build precisa de mais que os 50 padrao.
    resultCap = nil,
    -- Diagnostico da leitura de SoulFragments, desenhado na Progressao.
    fragDiag = nil,
}

-- Fila de trabalho. O callback de Button pode ser executado DEPOIS do
--            frame ja ter sido desenhado, entao o scan nao roda mais dentro do
--            clique: o clique so enfileira, e uma thread propria executa entre
--            frames, evitando travar o renderer Drawing.
local pendingJob = nil

----------------------------------------------------------------
-- TRANSLATIONS  (portado 1:1 do original)
----------------------------------------------------------------

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
        -- Farms novo: apenas dois botoes, sempre baseado nos stats.
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
        SortBy = "Ordenar", TPFail = "Alvo sem posicao (TP falhou)",
        Refresh = "ATUALIZAR LISTA",
        -- Textos da nova pagina de guia de progressao.
        Progress = "Progressão", GenRoute = "GERAR ROTA",
        ProgressDesc = "Rota de farm do Lv 1 até seu LEVEL alvo",
        Steps = "etapas até o Lv", SetLevel = "Defina o LEVEL alvo nos seus stats",
        NoneEligible = "Nenhum boss elegível encontrado",
        StartGap = "Sem boss elegível antes do Lv",
        -- Controles da blacklist exclusiva da Progressao.
        Blacklist = "BLACKLIST", RemoveBlacklist = "REMOVER BLACKLIST",
        BlacklistTitle = "BLACKLIST DA PROGRESSÃO", BlacklistEmpty = "Nenhum boss na blacklist",
        -- Textos da aba de analise de equipamento.
        Build = "Build", BuildScan = "ANALISAR BUILD",
        BuildDesc = "Lê suas armas/armaduras e aponta a melhor",
        BestWeapon = "Melhor Arma:", BestArmor = "Melhor Armadura:",
        -- Separa dano confirmado do cenario hipotetico de DamageIncrease.
        BestWeaponConfirmed = "Melhor Arma (dano confirmado):",
        BestWeaponBoosted = "Melhor Arma (se DamageIncrease for aplicado):",
        BuildHypDamage = "Dano hipotético",
        BuildSameBoostWinner = "Também é a melhor considerando DamageIncrease",
        -- Build / tierlist de comidas.
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
        -- Fontes de aquisicao (compartilhado por Buscar / Faltantes / Build).
        Shop = "Loja", Boss = "Boss", BossGuess = "Boss?", Frags = "Fragmentos",
        -- Botao para a Part cujo nome == Shop.Value.
        TPShop = "TP LOJA",
        TagShop = "[LOJA]", ShopItems = "Itens nessa loja",
        ShopPoints = "Pontos da loja", ShopPoint = "Part",
        ShopNoTP = "Nenhuma Part encontrada para essa loja",
        NoSource = "Sem fonte conhecida", Craft = "Craft",
        FragReady = "PRONTO", FragNeed = "faltam",
        TagWeapon = "[ARMA]", TagArmor = "[ARMADURA]", TagSoul = "[ALMA]", TagFood = "[COMIDA]",
        TagBoss = "[BOSS]", NoTP = "sem TP (só no Lighting)",
        -- Botao de faltantes na aba Progressao.
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
        -- New Farms: only two buttons, always based on your stats.
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
        -- chaves novas
        SortBy = "Sort by", TPFail = "Target has no position (TP failed)",
        Refresh = "REFRESH LIST",
        -- Texts for the new progression guide page.
        Progress = "Progression", GenRoute = "GENERATE ROUTE",
        ProgressDesc = "Farm route from Lv 1 to your target LEVEL",
        Steps = "steps to Lv", SetLevel = "Set your target LEVEL in your stats",
        NoneEligible = "No eligible bosses found",
        StartGap = "No eligible boss before Lv",
        -- Progression-only blacklist controls.
        Blacklist = "BLACKLIST", RemoveBlacklist = "REMOVE BLACKLIST",
        BlacklistTitle = "PROGRESSION BLACKLIST", BlacklistEmpty = "No bosses blacklisted",
        -- Texts for the gear analysis page.
        Build = "Build", BuildScan = "ANALYZE BUILD",
        BuildDesc = "Reads your weapons/armors and points the best",
        BestWeapon = "Best Weapon:", BestArmor = "Best Armor:",
        -- Separates confirmed damage from the hypothetical DamageIncrease scenario.
        BestWeaponConfirmed = "Best Weapon (confirmed damage):",
        BestWeaponBoosted = "Best Weapon (if DamageIncrease is applied):",
        BuildHypDamage = "Hypothetical damage",
        BuildSameBoostWinner = "Also the best when considering DamageIncrease",
        -- Food build / tier list.
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
        -- Acquisition sources (shared by Search / Missing / Build).
        Shop = "Shop", Boss = "Boss", BossGuess = "Boss?", Frags = "Fragments",
        -- Button for the Part whose name == Shop.Value.
        TPShop = "TP SHOP",
        TagShop = "[SHOP]", ShopItems = "Items in this shop",
        ShopPoints = "Shop points", ShopPoint = "Part",
        ShopNoTP = "No Part found for this shop",
        NoSource = "No known source", Craft = "Craft",
        FragReady = "READY", FragNeed = "need",
        TagWeapon = "[WEAPON]", TagArmor = "[ARMOR]", TagSoul = "[SOUL]", TagFood = "[FOOD]",
        TagBoss = "[BOSS]", NoTP = "no TP (Lighting only)",
        -- Missing-items button on the Progression page.
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

-- switchLanguage() virou sincronizacao com o Combo "utmm_lang" (chamada por frame,
--        custo desprezivel). O botao PT/EN do header original nao existe mais.
local function syncLanguage(idx)
    local want = (idx == 1) and "EN" or "PT"
    if want ~= CurrentLanguage then
        CurrentLanguage = want
        Lang = Translations[CurrentLanguage]
    end
end

----------------------------------------------------------------
-- LEITURA DE WIDGETS / CONFIG
----------------------------------------------------------------

local INPUT_IDS = {
    "utmm_level", "utmm_resets", "utmm_tr",
    "utmm_reset_min", "utmm_reset_max",
    "utmm_tr_min", "utmm_tr_max",
}

-- Preferencias usadas pela UI Drawing e pela logica funcional.
local WIDGET_DEFAULTS = {
    utmm_lang        = 0,
    utmm_level       = "0",
    utmm_resets      = "0",
    utmm_tr          = "0",
    utmm_reset_min   = "0",
    utmm_reset_max   = "",
    utmm_tr_min      = "0",
    utmm_tr_max      = "",
    utmm_search      = "",
    utmm_exact_reset = false,
    utmm_exact_tr    = false,
    utmm_include_frag = false,
    utmm_utmoh       = false,
    utmm_top5_sort   = 0,
    -- 0 = so o resumo, 1 = top 10 de cada, 2 = tudo.
    utmm_build_show  = 1,
    -- Marcado = lista literalmente tudo do Lighting que voce nao tem,
    --        inclusive o que nao tem boss/loja identificado.
    utmm_missing_all = false,
}

local WIDGET_IDS = {
    "utmm_lang", "utmm_level", "utmm_resets", "utmm_tr",
    "utmm_reset_min", "utmm_reset_max", "utmm_tr_min", "utmm_tr_max",
    "utmm_search", "utmm_exact_reset", "utmm_exact_tr",
    "utmm_include_frag", "utmm_utmoh", "utmm_top5_sort",
    "utmm_build_show", "utmm_missing_all",
}

local uiCache = {}
for id, value in pairs(WIDGET_DEFAULTS) do
    uiCache[id] = value
end

local function widgetValue(id)
    local v = uiCache[id]
    if v ~= nil then return v end
    return WIDGET_DEFAULTS[id]
end

local function inputDefault(id)
    local v = widgetValue(id)
    if type(v) == "string" then return v end
    return WIDGET_DEFAULTS[id] or ""
end

local function toggleDefault(id)
    local v = widgetValue(id)
    if type(v) == "boolean" then return v end
    return WIDGET_DEFAULTS[id] or false
end

local function comboDefault(id)
    local v = widgetValue(id)
    if type(v) == "number" then return v end
    return WIDGET_DEFAULTS[id] or 0
end


local getInput = inputDefault
local getToggle = toggleDefault
local function getCombo(id, default)
    local v = widgetValue(id)
    if type(v) == "number" then return v end
    return default or 0
end

----------------------------------------------------------------
-- PERSISTENCIA  (utmm_guider.json)
--
-- Formato do arquivo (compativel com o antigo -- os InputText continuam
-- soltos na raiz, entao config ja salva nao se perde):
--   {
--     "utmm_level": "100", ... ,
--     "missing_blacklist": { "<PlaceId>": ["Weapons/Dark Bone", ...] }
--   }
--
-- A blacklist dos faltantes e POR JOGO: a chave e o PlaceId, entao o que voce
-- ignorou num jogo nao vaza para outro, e o arquivo guarda todos ao mesmo tempo.
----------------------------------------------------------------

-- Escrita em disco depende de writefile/readfile/isfile, que nem toda
--       LuaVM expoe. Sem eles a blacklist funciona na sessao mas nao sobrevive
--       ao reexecutar -- a aba avisa isso em vez de fingir que salvou.
local CAN_PERSIST = (type(writefile) == "function")
    and (type(readfile) == "function")
    and (type(isfile) == "function")

local PLACE_KEY
do
    -- PlaceId primeiro; GameId/JobId so como rede de seguranca caso a
    --       propriedade nao seja legivel nesta VM.
    local candidates = { "PlaceId", "GameId", "JobId" }
    for _, prop in ipairs(candidates) do
        local ok, v = pcall(function() return game[prop] end)
        if ok and (type(v) == "number" or type(v) == "string") then
            local sv = tostring(v)
            -- Descarta vazio, zero e as strings de erro de leitura do Matcha.
            if sv ~= "" and sv ~= "0" and not string.find(string.lower(sv), "failed", 1, true) then
                PLACE_KEY = sv
                break
            end
        end
    end
    -- Sem PlaceId legivel a blacklist ainda salva, so que num balde
    --       compartilhado. Melhor do que perder tudo a cada execucao.
    PLACE_KEY = PLACE_KEY or "unknown"
end

-- Copia crua do ultimo JSON lido: preserva a blacklist dos OUTROS
--       PlaceIds na hora de regravar o arquivo.
local configCache = {}

-- chave = "<Categoria>/<NomeDaPasta>". Usa o nome da PASTA (nao o rotulo)
--       porque e ele que identifica o item de forma estavel.
local missingBlacklist = {}
local missingBlacklistOrder = {}

-- Persistente por PlaceId, separado dos faltantes.
local foodBlacklist = {}
local foodBlacklistOrder = {}

local function serializeConfig()
    local data = {}
    for _, id in ipairs(WIDGET_IDS) do
        data[id] = widgetValue(id)
    end

    local mb = {}
    if type(configCache.missing_blacklist) == "table" then
        for placeKey, list in pairs(configCache.missing_blacklist) do
            if type(list) == "table" then mb[placeKey] = list end
        end
    end
    mb[PLACE_KEY] = missingBlacklistOrder
    data.missing_blacklist = mb

    -- Preserva listas de outros PlaceIds e grava a atual.
    local fb = {}
    if type(configCache.food_blacklist) == "table" then
        for placeKey, list in pairs(configCache.food_blacklist) do
            if type(list) == "table" then fb[placeKey] = list end
        end
    end
    fb[PLACE_KEY] = foodBlacklistOrder
    data.food_blacklist = fb

    -- Preserva as listas dos outros PlaceIds e grava a
    -- blacklist acumulativa da Progressao apenas para o jogo atual.
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

local function saveConfig()
    if not HttpService or not CAN_PERSIST then return false end
    local data = serializeConfig()
    configCache = data
    local ok, encoded = pcall(function() return HttpService:JSONEncode(data) end)
    if not ok or type(encoded) ~= "string" then return false end
    local okWrite = pcall(function() writefile(CONFIG_FILE, encoded) end)
    return okWrite
end

local function loadConfig()
    if not HttpService or not CAN_PERSIST then return end
    local okExists, exists = pcall(function() return isfile(CONFIG_FILE) end)
    if not okExists or not exists then return end
    local okRead, raw = pcall(function() return readfile(CONFIG_FILE) end)
    if not okRead or type(raw) ~= "string" or raw == "" then return end
    local okDec, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not okDec or type(data) ~= "table" then return end

    configCache = data
    for _, id in ipairs(WIDGET_IDS) do
        local saved = data[id]
        local expected = type(WIDGET_DEFAULTS[id])
        if saved ~= nil and type(saved) == expected then
            uiCache[id] = saved
        end
    end

    -- So a lista DESTE PlaceId volta para a memoria.
    local mb = data.missing_blacklist
    if type(mb) == "table" and type(mb[PLACE_KEY]) == "table" then
        for _, key in ipairs(mb[PLACE_KEY]) do
            if type(key) == "string" and key ~= "" and not missingBlacklist[key] then
                missingBlacklist[key] = true
                missingBlacklistOrder[#missingBlacklistOrder + 1] = key
            end
        end
    end

    -- Restaura apenas a lista deste PlaceId.
    local fb = data.food_blacklist
    if type(fb) == "table" and type(fb[PLACE_KEY]) == "table" then
        for _, key in ipairs(fb[PLACE_KEY]) do
            if type(key) == "string" and key ~= "" and not foodBlacklist[key] then
                foodBlacklist[key] = true
                foodBlacklistOrder[#foodBlacklistOrder + 1] = key
            end
        end
    end

    -- Restaura somente os bosses bloqueados neste PlaceId.
    -- Usa o nome interno da rota, o mesmo identificador usado durante o filtro.
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

----------------------------------------------------------------
-- OPERACOES DA BLACKLIST DOS FALTANTES
----------------------------------------------------------------

local MISSING_KIND_TAG = { Weapons = "TagWeapon", Armor = "TagArmor", SOULs = "TagSoul", Food = "TagFood" }

local function missingKey(kind, folderName)
    return tostring(kind) .. "/" .. tostring(folderName)
end

-- Reconstroi um rotulo legivel a partir da chave, sem precisar persistir nome.
local function missingBlacklistLabel(key)
    local kind, name = string.match(key, "^([^/]+)/(.+)$")
    if not kind then return key end
    local tagKey = MISSING_KIND_TAG[kind]
    return ((tagKey and Lang[tagKey]) or "") .. " " .. name
end

local function addMissingBlacklist(key)
    if not key or key == "" or missingBlacklist[key] then return false end
    missingBlacklist[key] = true
    missingBlacklistOrder[#missingBlacklistOrder + 1] = key
    saveConfig()
    return true
end

local function removeMissingBlacklist(key)
    if not key or not missingBlacklist[key] then return false end
    missingBlacklist[key] = nil
    for i = #missingBlacklistOrder, 1, -1 do
        if missingBlacklistOrder[i] == key then
            table.remove(missingBlacklistOrder, i)
            break
        end
    end
    saveConfig()
    return true
end

local function clearMissingBlacklist()
    if #missingBlacklistOrder == 0 then return false end
    missingBlacklist = {}
    missingBlacklistOrder = {}
    saveConfig()
    return true
end

----------------------------------------------------------------
-- OPERACOES
----------------------------------------------------------------

local function addFoodBlacklist(folderName)
    if not folderName or folderName == "" or foodBlacklist[folderName] then return false end
    foodBlacklist[folderName] = true
    foodBlacklistOrder[#foodBlacklistOrder + 1] = folderName
    saveConfig()
    return true
end

local function removeFoodBlacklist(folderName)
    if not folderName or not foodBlacklist[folderName] then return false end
    foodBlacklist[folderName] = nil
    for i = #foodBlacklistOrder, 1, -1 do
        if foodBlacklistOrder[i] == folderName then
            table.remove(foodBlacklistOrder, i)
            break
        end
    end
    saveConfig()
    return true
end

local function clearFoodBlacklist()
    if #foodBlacklistOrder == 0 then return false end
    foodBlacklist = {}
    foodBlacklistOrder = {}
    saveConfig()
    return true
end

----------------------------------------------------------------
-- PARSERS / FORMATADORES  (portados 1:1 do original)
----------------------------------------------------------------

local function extractNumber(str)
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

local function parseNumberWithSuffix(str)
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

local function parseGoldAndExp(t)
    if not t then return 0, 0 end
    local gv, ev = 0, 0
    local gp = string.match(t, "Rewards%s+([%d%.]+%s*[KkMmBbTtQqSsOoNnDdaAiIxXpPcCoO]*)")
    if gp and gp ~= "" then gv = parseNumberWithSuffix(gp) end
    if gv == 0 then gv = tonumber(string.match(t, "Rewards%s+(%d+)")) or 0 end
    local ep = string.match(t, "([%d%.]+%s*[KkMmBbTtQqSsOoNnDdaAiIxXpPcCoO]*)%s*%(?[^%)]*%)?%s*EXP")
    if ep and ep ~= "" then ev = parseNumberWithSuffix(ep) end
    if ev == 0 then
        ep = string.match(t, "([%d%.]+[KkMmBbTtQqSsOoNnDdaAiIxXpPcCoO]?)%s*EXP")
        if ep then ev = parseNumberWithSuffix(ep) end
    end
    if ev == 0 then ev = tonumber(string.match(t, "(%d+)%s*EXP")) or 0 end
    return gv, ev
end

-- O UTMM usa "Rewards Gold 300000 (300000 Base) 300000 Exp and ...":
--            o numero vem DEPOIS da palavra Gold e o EXP e escrito "Exp". Os
--            regex originais esperam "Rewards 500 Gold" e "EXP" em maiuscula,
--            entao devolviam 0/0 nesse jogo (a aba Farms ficava toda empatada
--            em zero e o formatRewards nao mostrava Gold:/Exp:).
--            Este fallback SO roda quando o parser original devolve 0, entao
--            nao muda nada onde o formato antigo ja funcionava.
local SUF = "[KkMmBbTtQqSsOoNnDd]?[aAiIxXpPcCoO]?"

local function parseRewardValues(t)
    if not t then return 0, 0 end
    local gv, ev = parseGoldAndExp(t)

    if gv == 0 then
        local n = string.match(t, "[Gg][Oo][Ll][Dd]%s+([%d%.]+%s*" .. SUF .. ")")
            or string.match(t, "([%d%.]+%s*" .. SUF .. ")%s*[Gg][Oo][Ll][Dd]")
        if n then gv = parseNumberWithSuffix(n) end
    end

    if ev == 0 then
        local n = string.match(t, "([%d%.]+%s*" .. SUF .. ")%s*[Ee][Xx][Pp]")
            or string.match(t, "[Ee][Xx][Pp]%s+([%d%.]+%s*" .. SUF .. ")")
        if n then ev = parseNumberWithSuffix(n) end
    end

    return gv, ev
end

local function formatNumber(n)
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

local function formatReq(v)
    if v >= 1e6 then return string.format("%.1fM", v/1e6)
    elseif v >= 1e3 then return string.format("%.1fK", v/1e3)
    else return tostring(v) end
end

-- FragmentChance ja e armazenado pelo kit como o valor da
-- porcentagem. Nao converte 0.5 para 50: exibimos exatamente o Value lido,
-- apenas preservando casas decimais quando existirem.
local function formatFragmentChance(v)
    if type(v) ~= "number" then return "?" end
    if v == math.floor(v) then return tostring(math.floor(v)) .. "%" end
    local t = string.format("%.4f", v)
    t = string.gsub(t, "0+$", "")
    t = string.gsub(t, "%.$", "")
    return t .. "%"
end

local function formatRewards(rt)
    if not rt or rt == "" then return Lang.NoRewards end
    local p = {}
    local gv, ev = parseRewardValues(rt) -- [PORT/FIX] parser com fallback
    if gv > 0 then table.insert(p, "Gold:" .. formatNumber(gv)) end
    if ev > 0 then table.insert(p, "Exp:" .. formatNumber(ev)) end
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

local function extractSoulName(ft)
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

local function checkRewardsCustom(rt)
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

----------------------------------------------------------------
-- TELEPORTE
-- Nao existe GetPivot nem BasePart.CFrame no Matcha.
--        Resolve a posicao do dono do BattleInfoGui e escreve em .Position.
----------------------------------------------------------------

local function partPosition(inst)
    if not inst then return nil end

    -- Wrappers de Instance do Matcha podem ficar temporariamente
    -- invalidos entre o scan e o clique. Rele a classe/Position uma segunda vez
    -- antes de considerar que a Part nao possui posicao. Isso tambem beneficia TP
    -- de boss sem mudar o alvo legado (BattleInfoGui.Parent).
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

local function findPartIn(node)
    if not node then return nil end
    local ok, part = pcall(function()
        local c = node:FindFirstChild("HumanoidRootPart") or node:FindFirstChild("Head")
        if c then return c end
        local okPrim, prim = pcall(function() return node.PrimaryPart end)
        if okPrim and prim then return prim end
        return nil
    end)
    if ok and part then return partPosition(part) end
    return nil
end

local function resolveTargetPosition(target)
    if not target then return nil end

    -- 1) o proprio alvo e uma BasePart
    local p = partPosition(target)
    if p then return p end

    -- 2) Model: HumanoidRootPart / Head / PrimaryPart
    p = findPartIn(target)
    if p then return p end

    -- 3) sobe ate 3 niveis de Parent procurando uma BasePart
    local node = target
    for _ = 1, 3 do
        local okParent, parent = pcall(function() return node.Parent end)
        if not okParent or not parent then break end
        node = parent
        p = partPosition(node)
        if p then return p end
        p = findPartIn(node)
        if p then return p end
    end

    return nil
end

-- Movimento final por Vector3. Para loja isso evita guardar/reler
-- uma Instance do Matcha depois que a Position ja foi obtida com sucesso.
local function teleportToPosition(pos)
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

-- Parte comum do alvo. O TP de boss continua usando EXATAMENTE
-- BattleInfoGui.Parent; so resolve a posicao e entrega ao movimento acima.
local function teleportToTarget(target)
    if not target then
        notify(Lang.TPFail, "UTMM Guider", 3)
        return
    end
    local pos = resolveTargetPosition(target)
    if not pos then
        notify(Lang.TPFail, "UTMM Guider", 3)
        return
    end
    teleportToPosition(pos)
end

-- recebe o proprio BattleInfoGui e resolve o dono (gui.Parent) internamente.
local function teleportTo(gui)
    if not gui then return end
    local okParent, target = pcall(function() return gui.Parent end)
    if not okParent or not target then
        notify(Lang.TPFail, "UTMM Guider", 3)
        return
    end
    -- Boss continua 100% no caminho legado: gui.Parent.
    teleportToTarget(target)
end

-- O clique de loja continua SEM GetDescendants.
-- Em vez de depender apenas da Position capturada durante o scan, guarda tambem
-- o caminho REAL descoberto da Part a partir do Workspace. No clique, percorre
-- esse caminho com FindFirstChild (barato) para obter um wrapper fresco.
local function teleportToShopPoint(target)
    if not target then
        notify(Lang.ShopNoTP, "UTMM Guider", 3)
        return
    end

    local pos = nil

    -- 1) Melhor caminho: relocaliza a mesma Part por sua cadeia de nomes.
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

    -- 2) Wrapper original, caso ainda esteja valido.
    if not pos and target.instance then
        for _ = 1, 3 do
            local okPos, p = pcall(function() return target.instance.Position end)
            if okPos and p ~= nil then
                pos = p
                break
            end
        end
    end

    -- 3) Ultimo fallback: coordenadas capturadas no scan.
    if not pos and type(target.x) == "number" and type(target.y) == "number" and type(target.z) == "number" then
        pos = Vector3.new(target.x, target.y, target.z)
    end

    if not pos then
        notify(Lang.ShopNoTP, "UTMM Guider", 3)
        return
    end
    teleportToPosition(pos)
end

----------------------------------------------------------------
-- LEITURA DO WORKSPACE
----------------------------------------------------------------

-- Quando a leitura de uma propriedade falha, o Matcha NAO lanca erro:
--            ele devolve a string "failed to fetch text". Sem filtrar, essa
--            string passava por extractSoulName (nao bate com "no fragment" nem
--            "none", e sobra com mais de 2 chars) e virava um nome de Soul
--            valido — o que ainda fazia o boss contar no "Incluir Fragmentos".
local BAD_TEXT_MARKERS = {
    "failed to fetch",
    "failed to read",
    "failed to get",
    -- O Matcha tambem usa estes sentinelas quando consegue
    --              resolver a Instance mas nao o nome/texto apontado.
    "unreadable_name",
    "unreadable name",
    "unreadable",
}

local function isBadText(txt)
    if type(txt) ~= "string" then return true end
    local lt = string.lower(txt)
    for _, marker in ipairs(BAD_TEXT_MARKERS) do
        if string.find(lt, marker, 1, true) then return true end
    end
    return false
end

-- Alem dos sentinelas declarados, algumas leituras do Explorer
-- chegam como lixo aparentemente valido (ex.: "??6??", "0n,??"). Nao da
-- para confiar nessa string como nome. Pontuacao normal e UTF-8 sao aceitos;
-- '?' fica propositalmente fora da lista segura porque e o sintoma dominante.
local GARBLED_RATIO = 0.34
local SAFE_TEXT_PUNCT = " .,'-_!()&+:#/%,*[]"

local function looksGarbled(txt)
    if type(txt) ~= "string" or txt == "" then return true end
    if isBadText(txt) then return true end

    local alnum, weird, total = 0, 0, 0
    for i = 1, #txt do
        local byte = string.byte(txt, i)
        local ch = string.sub(txt, i, i)
        if byte and byte < 32 and byte ~= 9 then return true end
        total = total + 1
        if byte and byte >= 128 then
            -- byte de UTF-8: nao penaliza nomes acentuados.
        elseif string.match(ch, "%w") then
            alnum = alnum + 1
        elseif string.find(SAFE_TEXT_PUNCT, ch, 1, true) then
            -- pontuacao normal de nome/recompensa
        else
            weird = weird + 1
        end
    end

    if alnum == 0 and weird > 0 then return true end
    return total > 0 and (weird / total) > GARBLED_RATIO
end

local function cleanText(txt)
    if type(txt) ~= "string" or txt == "" then return nil end
    if isBadText(txt) or looksGarbled(txt) then return nil end
    return txt
end

local function rawText(gui, childName)
    local ok, txt = pcall(function()
        local c = gui:FindFirstChild(childName)
        if not c then return nil end
        return c.Text
    end)
    if ok then return cleanText(txt) end
    return nil
end

-- instancias podem sumir entre frames -> toda leitura em pcall.
local function readText(gui, childName)
    local txt = rawText(gui, childName)
    -- a falha de leitura costuma ser transitoria (emulacao por
    --            memoria), entao vale uma segunda tentativa antes de desistir.
    if txt == nil then txt = rawText(gui, childName) end
    return txt
end

-- Uma unica chamada a Workspace:GetDescendants() por scan.
-- O snapshot e a fonte comum para BattleInfoGui E para localizar lojas.
-- IMPORTANTE: nao existe caminho presumido de loja. Shop.Value e apenas o
-- nome a procurar em QUALQUER lugar do Workspace.
local workspaceScanCache = nil

-- Conjunto opcional de nomes de loja conhecidos antes da
-- varredura. Guarda forma EXATA e minuscula. Na maioria dos objetos o teste
-- exato resolve sem executar string.lower() em cada uma das ~200k Instances.
local workspaceShopWanted = nil -- { exact = {}, lower = {} }

local function collectBattleGuis()
    if workspaceScanCache then return workspaceScanCache.battleGuis end

    local out = {}
    local shopNodes = {}
    local ok, descendants = pcall(function() return Workspace:GetDescendants() end)
    if not ok or type(descendants) ~= "table" then
        workspaceScanCache = { descendants = {}, battleGuis = {}, shopNodes = {} }
        return out
    end

    for _, inst in pairs(descendants) do
        local okName, nm = pcall(function() return inst.Name end)
        if okName and type(nm) == "string" then
            if nm == "BattleInfoGui" then
                out[#out + 1] = inst
            end

            if workspaceShopWanted then
                local matchedKey = nil
                if workspaceShopWanted.exact and workspaceShopWanted.exact[nm] then
                    matchedKey = workspaceShopWanted.exact[nm]
                elseif workspaceShopWanted.lower then
                    local lowerName = string.lower(nm)
                    if workspaceShopWanted.lower[lowerName] then matchedKey = lowerName end
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

    workspaceScanCache = {
        descendants = descendants,
        battleGuis = out,
        shopNodes = shopNodes,
    }
    return out
end

----------------------------------------------------------------
-- CATALOGO DO JOGO (game.Lighting) -- camada compartilhada
--
--   Lighting.Weapons.<pasta> -> Tool.AttackTool.{Damage,DamageModify,DamageIncrease}
--                               WeaponName / Onsale / Shop / Cost
--   Lighting.Armor.<pasta>   -> HPBonus / ArmorName / Onsale / Shop / Cost
--   Lighting.SOULs.<pasta>   -> SoulName / Fragments / Onsale / Shop / Cost
--   Lighting.Battles.<pasta> -> BattleName / LOVE / Resets / Gold / XP
--                               RewardWeapon (ObjectValue) / SoulFragment (ObjectValue)
--
-- Prioridade pedida: SEMPRE o Value de exibicao (WeaponName, ArmorName,
--        SoulName, BattleName). So cai no nome da pasta / MonsterName do gui
--        quando a leitura falha -- que era o comportamento antigo do script.
----------------------------------------------------------------

-- Nenhum nome de jogador e hardcoded. Se LocalPlayer falhar,
-- o fallback final procura dinamicamente quem possui as pastas de inventario.

----------------------------------------------------------------
-- Acesso defensivo a arvore (mesmo padrao de readText: 1 retry)
----------------------------------------------------------------

local function safeChild(parent, name)
    if not parent then return nil end
    local ok, c = pcall(function() return parent:FindFirstChild(name) end)
    if ok and c then return c end
    -- A falha de leitura por memoria costuma ser transitoria.
    local ok2, c2 = pcall(function() return parent:FindFirstChild(name) end)
    if ok2 then return c2 end
    return nil
end

local function safeChildren(inst)
    if not inst then return {} end
    local ok, kids = pcall(function() return inst:GetChildren() end)
    if ok and type(kids) == "table" and #kids > 0 then return kids end

    -- GetChildren tambem pode falhar transitoriamente no Matcha.
    -- Antes, uma unica falha fazia uma loja encontrada como Folder parecer vazia
    -- e escondia ShopPart/CamPart. Tenta novamente antes de concluir que nao ha filhos.
    local ok2, kids2 = pcall(function() return inst:GetChildren() end)
    if ok2 and type(kids2) == "table" then return kids2 end

    -- Se a primeira leitura foi valida e realmente retornou {}, preserva-a.
    if ok and type(kids) == "table" then return kids end
    return {}
end

local function safeName(inst)
    if not inst then return nil end
    local ok, n = pcall(function() return inst.Name end)
    if ok then
        local clean = cleanText(n)
        if clean then return clean end
    end
    -- Nome corrompido costuma ser transitorio: tenta de novo.
    local ok2, n2 = pcall(function() return inst.Name end)
    if ok2 then return cleanText(n2) end
    return nil
end

-- Address e estavel entre wrappers e ajuda a casar LinkedBattle com
-- o dono do BattleInfoGui sem depender de nomes/sufixos.
local function safeAddress(inst)
    if not inst then return nil end
    local ok, a = pcall(function() return inst.Address end)
    if ok and a ~= nil then return tostring(a) end
    return nil
end

-- .Value de NumberValue/IntValue. O Matcha pode devolver string, ou a
--       string de erro "failed to fetch" -- por isso o filtro isBadText.
local function readNumberValue(inst, fallback)
    if not inst then return fallback end
    local ok, v = pcall(function() return inst.Value end)
    if not ok then return fallback end
    if type(v) == "number" then return v end
    if type(v) == "string" then
        if isBadText(v) then return fallback end
        local n = tonumber((string.gsub(v, ",", ".")))
        if n then return n end
    end
    return fallback
end

local function readStringValue(inst)
    if not inst then return nil end
    local ok, v = pcall(function() return inst.Value end)
    if ok then
        local clean = cleanText(v)
        if clean then return clean end
    end
    -- Segunda leitura antes de cair no fallback de outra fonte.
    local ok2, v2 = pcall(function() return inst.Value end)
    if ok2 then return cleanText(v2) end
    return nil
end

local function readBoolValue(inst)
    if not inst then return nil end

    -- BoolValue tambem pode falhar de forma transitoria no Matcha.
    -- Faz duas leituras antes de concluir que o estado e desconhecido.
    for _ = 1, 2 do
        local ok, v = pcall(function() return inst.Value end)
        if ok and type(v) == "boolean" then return v end
        -- Alguns reads devolvem "true"/"false" como texto.
        if ok and type(v) == "string" then
            local lv = string.lower(v)
            if lv == "true" then return true end
            if lv == "false" then return false end
        end
    end
    return nil
end

-- ObjectValue (RewardWeapon / SoulFragment) normalmente aponta para a
-- pasta do item. Em algumas leituras do Matcha, porem, .Value chega como o
-- caminho em texto (ex.: "game.Lighting.Gadgets.GasterBlaster"). Preserva
-- tambem esse formato para que a camada de nomes consiga extrair o alvo real.
local function readObjectValue(inst)
    if not inst then return nil end
    local ok, v = pcall(function() return inst.Value end)
    if not ok or v == nil then return nil end

    if type(v) == "string" then
        local clean = cleanText(v)
        if not clean then return nil end
        local lv = string.lower(clean)
        -- ObjectValue vazio/sem referencia em alguns forks pode virar texto.
        if lv == "nil" or lv == "none" or lv == "null" or lv == "0" then return nil end
        return clean
    end

    if type(v) == "userdata" or type(v) == "table" then return v end
    if type(v) ~= "number" and type(v) ~= "boolean" then return v end
    return nil
end

-- No kit original o Value so existe quando voce ADQUIRE o item, entao a
--       simples presenca ja basta. Alguns forks listam tudo e usam false para
--       "nao possui" -- aceita os dois: so descarta o false explicito.
local function isOwned(inst)
    local ok, v = pcall(function() return inst.Value end)
    if ok and v == false then return false end
    return true
end

-- Fallback para itens que fogem do layout esperado.
--       Profundidade limitada de proposito: varrer o Handle inteiro seria caro.
local function findDeep(root, name, depth)
    if not root then return nil end
    local direct = safeChild(root, name)
    if direct then return direct end
    if depth <= 0 then return nil end
    for _, kid in ipairs(safeChildren(root)) do
        local found = findDeep(kid, name, depth - 1)
        if found then return found end
    end
    return nil
end

-- Tenta varios nomes de Value (o kit mudou alguns entre 1.0 e 2.0).
local function firstChild(parent, names)
    for _, n in ipairs(names) do
        local c = safeChild(parent, n)
        if c then return c end
    end
    return nil
end

----------------------------------------------------------------
-- CACHE POR SCAN
-- Tudo que vem de Lighting/Players e memorizado durante um scan e descartado
-- no proximo beginScan(), entao cada clique le dados frescos sem reler a mesma
-- arvore dezenas de vezes dentro da mesma passada.
----------------------------------------------------------------

local catalogCache = {
    battles = nil, index = nil, items = nil, sources = nil,
    guiRewards = nil, bosses = nil, frags = nil, player = nil,
    -- cache: Shop.Value -> lista de Parts/posicoes da loja.
    shopTargets = nil,
}

local function invalidateCatalog()
    catalogCache.battles = nil
    catalogCache.index = nil
    catalogCache.items = nil
    catalogCache.sources = nil
    catalogCache.guiRewards = nil
    catalogCache.bosses = nil
    catalogCache.frags = nil
    catalogCache.player = nil
    catalogCache.shopTargets = nil
    -- Cada novo scan tira uma fotografia nova do Workspace.
    workspaceScanCache = nil
    workspaceShopWanted = nil
end

----------------------------------------------------------------
-- INVENTARIO DO JOGADOR
----------------------------------------------------------------

-- Pastas que identificam o SEU Player. Usadas para validar o wrapper e,
--       em ultimo caso, para achar o Player certo varrendo game.Players.
local INVENTORY_FOLDERS = { "Weapons", "Armor", "SOULs", "SoulFragments" }

local function hasInventory(plr)
    if not plr then return false end
    for _, f in ipairs(INVENTORY_FOLDERS) do
        if safeChild(plr, f) then return true end
    end
    return false
end

-- O LocalPlayer capturado no load do script NAO serve sozinho: no Matcha
--       cada leitura devolve um wrapper novo sobre um endereco, e o wrapper
--       pego cedo (antes do Player replicar) fica velho. Como ele nao e nil, o
--       fallback antigo nunca disparava e TODA leitura de inventario voltava
--       vazia em silencio. Agora o Player e reresolvido a cada scan.
local function resolvePlayer()
    if catalogCache.player ~= nil then
        return catalogCache.player or nil
    end

    local found = nil

    -- 1) Relê LocalPlayer AGORA e, com o nome dele, pega um wrapper fresco
    --    direto de game.Players -- e isso que mata o problema do wrapper velho.
    local ok, live = pcall(function() return Players.LocalPlayer end)
    if ok and live then
        local nm = safeName(live)
        if nm and nm ~= "" then
            local fresh = safeChild(Players, nm)
            if hasInventory(fresh) then found = fresh end
            if not found and fresh then found = fresh end
        end
        if not found and hasInventory(live) then found = live end
    end

    -- 2) Wrapper do load, se ainda responder.
    if not found and hasInventory(LocalPlayer) then found = LocalPlayer end

    -- 3) Ultimo recurso: procura dinamicamente um Player com as pastas de
    -- inventario. Nao depende de username hardcoded.
    if not found then
        for _, kid in ipairs(safeChildren(Players)) do
            if hasInventory(kid) then
                found = kid
                break
            end
        end
    end

    catalogCache.player = found or false
    return found
end

local function myFolder(folderName)
    return safeChild(resolvePlayer(), folderName)
end

-- Devolve lista de nomes possuidos + se a pasta existe (distingue "voce nao tem
-- nada" de "nao achei a pasta").
local function ownedNames(folderName)
    local out = {}
    local folder = myFolder(folderName)
    if not folder then return out, false end
    for _, kid in ipairs(safeChildren(folder)) do
        local nm = safeName(kid)
        if nm and nm ~= "" and isOwned(kid) then
            out[#out + 1] = nm
        end
    end
    return out, true
end

local function ownedSet(folderName)
    local set = {}
    local list, exists = ownedNames(folderName)
    for _, n in ipairs(list) do set[n] = true end
    return set, exists, #list
end

----------------------------------------------------------------
-- NOMES DE EXIBICAO
----------------------------------------------------------------

-- Value de exibicao por categoria. Ordem = prioridade de leitura.
local DISPLAY_VALUE = {
    Weapons = { "WeaponName" },
    Armor   = { "ArmorName" },
    SOULs   = { "SoulName" },
    Food    = { "FoodName" },
    Battles = { "BattleName" },
}

local function displayName(folder, kind, fallback)
    if folder then
        local v = readStringValue(firstChild(folder, DISPLAY_VALUE[kind] or {}))
        if v then return v end
    end
    -- Forma antiga: nome da pasta (ou o texto que o chamador ja tinha).
    return fallback or (folder and safeName(folder)) or "?"
end

----------------------------------------------------------------
-- Permanent / TruePermanent
-- Armas, Armaduras, SOULs e Food usam os mesmos BoolValues no catalogo.
-- nil significa "nao consegui ler / Value ausente"; nunca e convertido em false.
----------------------------------------------------------------

local PERMANENCE_KINDS = { Weapons = true, Armor = true, SOULs = true, Food = true }

local function permanenceKind(ref)
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
        local pn = safeName(parent)
        if pn and PERMANENCE_KINDS[pn] then return pn end
    end
    return nil
end

local function itemPermanence(folder)
    if not folder or type(folder) == "string" then return nil, nil end
    local permanent = readBoolValue(safeChild(folder, "Permanent"))
    local truePermanent = readBoolValue(safeChild(folder, "TruePermanent"))
    return permanent, truePermanent
end

local function permanenceBoolText(v)
    if v == true then return Lang.FoodYes end
    if v == false then return Lang.FoodNo end
    return "?"
end

local function permanenceLine(permanent, truePermanent, prefix, force)
    if not force and permanent == nil and truePermanent == nil then return nil end
    local line = Lang.Permanent .. ": " .. permanenceBoolText(permanent)
        .. " | " .. Lang.TruePermanent .. ": " .. permanenceBoolText(truePermanent)
    if prefix and prefix ~= "" then line = prefix .. " | " .. line end
    return line
end

local function referencePermanence(ref)
    local kind = permanenceKind(ref)
    if not kind then return nil, nil, nil end
    if type(ref) == "string" then
        -- Matcha pode devolver ObjectValue como caminho-texto.
        -- A categoria e o nome da pasta ainda permitem reler a pasta real do
        -- Lighting e obter Permanent/TruePermanent sem depender do wrapper.
        local clean = cleanText(ref) or tostring(ref)
        local fname = string.match(clean, "([^%.]+)$")
        local root = safeChild(Lighting, kind)
        local folder = (root and fname) and safeChild(root, fname) or nil
        local p, tp = itemPermanence(folder)
        return p, tp, kind
    end
    local p, tp = itemPermanence(ref)
    return p, tp, kind
end

----------------------------------------------------------------
-- LOJAS  (Onsale / Shop / Cost -- vale p/ Arma, Armadura, Alma e Food)
----------------------------------------------------------------

-- Metadados da loja do item. Esta funcao tinha sido apagada
-- acidentalmente na versao ShopPoints_Perf, causando o erro
-- "attempt to call a nil value" em allCatalogItems().
local function shopInfo(folder)
    if not folder then return nil end
    local onsale = readBoolValue(safeChild(folder, "Onsale"))
    local shop   = readStringValue(safeChild(folder, "Shop"))
    local cost   = readNumberValue(firstChild(folder, { "Cost", "Price" }), nil)

    -- Onsale=false e definitivo. Se Onsale nao leu, Shop preenchido ainda
    -- e evidência suficiente para considerar o item ligado a uma loja.
    if onsale == false then return nil end
    if onsale == nil and (shop == nil or shop == "") then return nil end

    return { shop = shop, cost = cost, sure = (onsale == true) }
end

-- Shop.Value pode apontar para uma Part OU para uma Folder/Model.
-- Se for container, lista TODAS as BaseParts dentro dele para o usuario escolher.
-- As coordenadas sao capturadas durante o scan; nenhum wrapper e reutilizado no clique.
-- Classificacao defensiva de BasePart. No Matcha, IsA pode falhar
-- transitoriamente mesmo quando ClassName/Position estao legiveis.
local function safeClassName(inst)
    if not inst then return nil end
    for _ = 1, 2 do
        local ok, cn = pcall(function() return inst.ClassName end)
        if ok then
            local clean = cleanText(cn)
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

local function isShopPart(inst)
    if not inst then return false end

    local cn = safeClassName(inst)

    -- Se o Matcha conseguiu ler o ClassName e ele identifica um
    -- container, a instancia NUNCA pode virar ponto de TP. A versao anterior
    -- ainda tentava Position/IsA depois disso e algumas Folders acabavam sendo
    -- classificadas falsamente como BasePart (ex.: a propria pasta da loja).
    if cn and SHOP_CONTAINER_CLASSES[cn] then return false end

    if cn and SHOP_BASEPART_CLASSES[cn] then return true end

    -- Para classes conhecidas que nao sao containers canonicos,
    -- IsA(BasePart) ainda cobre subclasses diferentes entre forks do kit.
    local okIsA, yes = pcall(function() return inst:IsA("BasePart") end)
    if okIsA and yes then return true end

    -- Position so e usado quando ClassName ficou ilegivel. Se o
    -- ClassName foi lido como uma classe nao-BasePart, nao arriscamos transformar
    -- esse objeto em Part por um read fantasma da emulacao.
    if cn == nil then
        local okPos, pos = pcall(function() return inst.Position end)
        if okPos and pos ~= nil then
            local okType, tv = pcall(function() return typeof(pos) end)
            if okType and tv == "Vector3" then return true end
        end
    end
    return false
end

-- Monta a rota REAL Workspace -> ... -> Part sem assumir nenhuma
-- estrutura do kit. Nomes com pontos/espacos funcionam porque nao splitamos
-- GetFullName; cada segmento vem do .Name de um Parent real.
local function workspacePathSegments(inst)
    if not inst then return nil end
    local rev = {}
    local cur = inst
    local wsAddr = safeAddress(Workspace)

    for _ = 1, 40 do
        local nm = safeName(cur)
        if not nm then return nil end
        table.insert(rev, 1, nm)

        local okParent, parent = pcall(function() return cur.Parent end)
        if not okParent or not parent then return nil end

        local parentAddr = safeAddress(parent)
        local parentName = safeName(parent)
        if (wsAddr and parentAddr == wsAddr) or (not wsAddr and parentName == "Workspace") then
            return rev
        end
        cur = parent
    end
    return nil
end

local function readShopPartXYZ(part)
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

-- A opcao de TP existe assim que uma Part e identificada. Position
-- ilegivel durante o scan NAO esconde mais o botao; ela pode ser relida no clique
-- por pathSegments, sem uma nova varredura global.
local function shopTargetFromPart(part)
    if not part or not isShopPart(part) then return nil end

    local nm = safeName(part) or "Part"
    local full = nil
    pcall(function() full = part:GetFullName() end)
    local addr = safeAddress(part)
    local segments = workspacePathSegments(part)
    local x, y, z = readShopPartXYZ(part)

    return {
        name = nm,
        path = cleanText(full) or nm,
        address = addr,
        pathSegments = segments,
        instance = part,
        x = x, y = y, z = z,
    }
end

local function appendShopParts(out, seen, node)
    if not node then return end

    if isShopPart(node) then
        local t = shopTargetFromPart(node)
        if t then
            local key = t.address or t.path
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = t
            end
        end
        return
    end

    -- pairs em vez de ipairs: tolera arrays nao-contiguos retornados
    -- pela emulacao sem afetar arrays normais.
    for _, kid in pairs(safeChildren(node)) do
        appendShopParts(out, seen, kid)
    end
end

-- Fallback baseado no snapshot global. Primeiro filtra apenas
-- BaseParts e so depois testa ancestralidade, reduzindo muito o custo quando o
-- Workspace possui centenas de milhares de Instances.
local function appendShopPartsFromSnapshot(out, seen, container)
    if not container or not workspaceScanCache then return end
    local descendants = workspaceScanCache.descendants or {}

    local containerAddr = safeAddress(container)
    local containerFull = nil
    pcall(function() containerFull = cleanText(container:GetFullName()) end)
    local prefix = containerFull and (containerFull .. ".") or nil

    for _, candidate in pairs(descendants) do
        if isShopPart(candidate) then
            local belongs = false

            local okDesc, isDesc = pcall(function() return candidate:IsDescendantOf(container) end)
            if okDesc and isDesc then belongs = true end

            if not belongs and containerAddr then
                local cur = candidate
                for _ = 1, 32 do
                    local okParent, par = pcall(function() return cur.Parent end)
                    if not okParent or not par then break end
                    if safeAddress(par) == containerAddr then
                        belongs = true
                        break
                    end
                    cur = par
                end
            end

            if not belongs and prefix then
                local full = nil
                pcall(function() full = cleanText(candidate:GetFullName()) end)
                if full and string.sub(full, 1, #prefix) == prefix then belongs = true end
            end

            if belongs then
                local t = shopTargetFromPart(candidate)
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

local function findShopTargets(shopName)
    local clean = cleanText(shopName)
    if not clean then return {} end
    local key = string.lower(clean)

    catalogCache.shopTargets = catalogCache.shopTargets or {}
    if catalogCache.shopTargets[key] then return catalogCache.shopTargets[key] end

    local out, seen = {}, {}

    -- Nenhuma estrutura de mapa e presumida. O nome e procurado na fotografia
    -- global do Workspace, em qualquer profundidade.
    workspaceShopWanted = workspaceShopWanted or { exact = {}, lower = {} }
    workspaceShopWanted.exact[clean] = key
    workspaceShopWanted.lower[key] = true

    if not workspaceScanCache then collectBattleGuis() end

    local nodes = {}
    local indexed = workspaceScanCache and workspaceScanCache.shopNodes
        and workspaceScanCache.shopNodes[key] or nil

    if indexed then
        for _, node in pairs(indexed) do nodes[#nodes + 1] = node end
    else
        -- Snapshot ja existente: percorre somente a tabela em memoria.
        local descendants = (workspaceScanCache and workspaceScanCache.descendants) or {}
        for _, node in pairs(descendants) do
            local nm = safeName(node)
            if nm and (nm == clean or string.lower(nm) == key) then
                nodes[#nodes + 1] = node
            end
        end
        if workspaceScanCache then
            workspaceScanCache.shopNodes = workspaceScanCache.shopNodes or {}
            workspaceScanCache.shopNodes[key] = nodes
        end
    end

    for _, node in pairs(nodes) do
        local before = #out
        appendShopParts(out, seen, node)
        if #out == before and not isShopPart(node) then
            appendShopPartsFromSnapshot(out, seen, node)
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

local function shopTargets(shop)
    if not shop or not shop.shop then return {} end
    return findShopTargets(shop.shop)
end

-- Almas sao CRAFTADAS: o Fragments diz quantos fragmentos a receita pede.
local function soulFragmentCost(folder)
    return readNumberValue(firstChild(folder, { "Fragments", "Fragment" }), nil)
end

----------------------------------------------------------------
-- STATS DOS ITENS
----------------------------------------------------------------

local function catalogFolder(kind)
    return safeChild(Lighting, kind)
end

local function itemFolder(kind, itemName)
    local root = catalogFolder(kind)
    if not root then return nil end
    return safeChild(root, itemName)
end

local function weaponStats(itemName, folder)
    folder = folder or itemFolder("Weapons", itemName)
    if not folder then return nil end

    -- Caminho canonico do kit; o findDeep so entra se o jogo fugir dele.
    local attack
    local tool = safeChild(folder, "Tool")
    if tool then attack = safeChild(tool, "AttackTool") end
    if not attack then attack = findDeep(folder, "AttackTool", 2) end

    local host = attack or folder
    local dmg = safeChild(host, "Damage")         or findDeep(folder, "Damage", 3)
    local mod = safeChild(host, "DamageModify")   or findDeep(folder, "DamageModify", 3)
    local inc = safeChild(host, "DamageIncrease") or findDeep(folder, "DamageIncrease", 3)

    -- fallback nil de proposito: se os TRES falharem na leitura, isso e
    --         falha de leitura, nao uma arma de dano 0 -- melhor marcar "sem
    --         dados" do que ranquear o item com um zero falso.
    local d = readNumberValue(dmg, nil)
    local m = readNumberValue(mod, nil)
    local i = readNumberValue(inc, nil)
    if d == nil and m == nil and i == nil then return nil end

    local permanent, truePermanent = itemPermanence(folder)
    return {
        damage   = d or 0,
        modify   = m or 0,
        increase = i or 0,
        label    = displayName(folder, "Weapons", itemName),
        shop     = shopInfo(folder),
        permanent = permanent, truePermanent = truePermanent,
    }
end

local function armorStats(itemName, folder)
    folder = folder or itemFolder("Armor", itemName)
    if not folder then return nil end

    local hp = safeChild(folder, "HPBonus") or findDeep(folder, "HPBonus", 2)
    if not hp then return nil end

    -- Mesma regra das armas: leitura falha vira "sem dados", nao +0 HP.
    local bonus = readNumberValue(hp, nil)
    if bonus == nil then return nil end

    local permanent, truePermanent = itemPermanence(folder)
    return {
        hp    = bonus,
        label = displayName(folder, "Armor", itemName),
        shop  = shopInfo(folder),
        permanent = permanent, truePermanent = truePermanent,
    }
end

----------------------------------------------------------------
-- STATS DAS COMIDAS
-- Lighting.Food.<pasta>.Tool.Food.Heal + FoodName/Cost/Shop/Onsale/Max
----------------------------------------------------------------

local function foodStats(itemName, folder)
    folder = folder or itemFolder("Food", itemName)
    if not folder then return nil end

    local foodNode = nil
    local tool = safeChild(folder, "Tool")
    if tool then foodNode = safeChild(tool, "Food") end
    if not foodNode then foodNode = findDeep(folder, "Food", 3) end

    local healNode = foodNode and safeChild(foodNode, "Heal") or nil
    if not healNode then healNode = findDeep(folder, "Heal", 4) end

    local heal = readNumberValue(healNode, nil)
    local cost = readNumberValue(firstChild(folder, { "Cost", "Price" }), nil)
    local maxv = readNumberValue(safeChild(folder, "Max"), nil)
    local onsale = readBoolValue(safeChild(folder, "Onsale"))
    local rawShop = readStringValue(safeChild(folder, "Shop"))
    local permanent, truePermanent = itemPermanence(folder)

    -- A localizacao da loja e independente do Onsale. Uma comida
    -- pode estar fora de venda agora e ainda ter Shop.Value configurado; isso e
    -- util na tierlist para permitir visitar a loja mesmo assim.
    local shopTarget = nil
    if rawShop and rawShop ~= "" then
        shopTarget = { shop = rawShop, cost = cost, sure = (onsale == true) }
    end

    return {
        folderName = itemName,
        label = displayName(folder, "Food", itemName),
        heal = heal,
        cost = cost,
        max = maxv,
        onsale = onsale,
        shopName = rawShop,
        -- shop = fonte de aquisicao real (respeita Onsale); shopTarget = apenas
        -- localizacao para TP, mesmo quando a comida nao esta a venda.
        shop = shopInfo(folder),
        shopTarget = shopTarget,
        permanent = permanent, truePermanent = truePermanent,
        missing = (heal == nil),
    }
end

----------------------------------------------------------------
-- BATTLES (game.Lighting.Battles)
--
-- Fonte de verdade dos bosses. O BattleInfoGui do workspace so existe para
-- boss ja "instanciado" no mapa -- por isso boss como o Chicken sumia da busca.
-- Aqui a lista sai direto do Lighting, com ou sem gui/TP.
----------------------------------------------------------------

local function normalizeBossAlias(txt)
    txt = cleanText(txt)
    if not txt then return nil end
    local s = string.lower(txt)

    -- O BattleInfoGui costuma acrescentar metadados ao mesmo boss:
    -- "Boss Name (30K) (RAID)" -> "boss name".
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

    -- Sufixos de interface sem parenteses, usados por alguns forks.
    s = string.gsub(s, "%s+raid%s+boss$", "")
    s = string.gsub(s, "%s+raid$", "")
    s = string.gsub(s, "%s+boss$", "")
    s = string.match(s, "^%s*(.-)%s*$") or ""
    return (s ~= "") and s or nil
end

local function readBattle(folder)
    local folderName = safeName(folder)
    local battleName = readStringValue(safeChild(folder, "BattleName"))
    local linked = readObjectValue(safeChild(folder, "LinkedBattle"))

    return {
        folder     = folder,
        folderName = folderName or battleName or "?",
        -- Mantem o BattleName cru separado. O nome final so e
        -- decidido depois de tentar o MonsterName do BattleInfoGui.
        battleName = battleName,
        name       = battleName or folderName or "?",
        stableKey  = safeAddress(folder) or (folderName and ("folder:" .. string.lower(folderName)))
            or (battleName and ("battle:" .. string.lower(battleName))) or tostring(folder),
        linked     = linked,
        -- nil de proposito: distingue "value ausente/ilegivel" de um
        --            zero real. Quem monta o boss usa isso para decidir se cai
        --            no BattleInfoGui ou se o Lighting ja respondeu.
        lvl        = readNumberValue(firstChild(folder, { "LOVE", "LVRequired", "Level" }), nil),
        r          = readNumberValue(firstChild(folder, { "Resets", "Reset" }), nil),
        tr         = readNumberValue(firstChild(folder, { "TrueResets", "TrueReset" }), nil),
        gold       = readNumberValue(safeChild(folder, "Gold"), nil),
        exp        = readNumberValue(firstChild(folder, { "XP", "EXP", "Exp" }), nil),
        reward     = readObjectValue(safeChild(folder, "RewardWeapon")),
        fragment   = readObjectValue(safeChild(folder, "SoulFragment")),
        fragChance = readNumberValue(safeChild(folder, "FragmentChance"), nil),
    }
end

local function allBattles()
    if catalogCache.battles then return catalogCache.battles end
    local out = {}
    local root = catalogFolder("Battles")
    for _, folder in ipairs(safeChildren(root)) do
        local okRead, b = pcall(readBattle, folder)
        if okRead and b then out[#out + 1] = b end
    end
    catalogCache.battles = out
    return out
end

-- Indice em camadas. Chaves ambiguas viram false em vez de casar
-- silenciosamente com o boss errado.
local function putUnique(map, key, value)
    if not key or key == "" then return end
    if map[key] == nil then
        map[key] = value
    elseif map[key] ~= value then
        map[key] = false
    end
end

local function battleIndex()
    if catalogCache.index then return catalogCache.index end
    local idx = {
        exact = {}, norm = {}, normAll = {},
        linkedAddress = {}, linkedName = {},
        -- Buckets para o fallback de assinatura. Evita percorrer TODOS
        -- os Lighting.Battles para cada BattleInfoGui com nome corrompido.
        byLevel = {}, reqExact = {},
    }

    for _, b in ipairs(allBattles()) do
        local aliases = { b.folderName, b.battleName, b.name }
        for _, alias in ipairs(aliases) do
            local clean = cleanText(alias)
            if clean then
                putUnique(idx.exact, string.lower(clean), b)
                local norm = normalizeBossAlias(clean)
                if norm then
                    putUnique(idx.norm, norm, b)
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
            putUnique(idx.linkedAddress, safeAddress(b.linked), b)
            local ln = safeName(b.linked)
            if ln then putUnique(idx.linkedName, string.lower(ln), b) end
        end
    end

    catalogCache.index = idx
    return idx
end

local function chooseNormCandidate(list, gui, lvlTxt)
    if not list or #list == 0 then return nil end
    if #list == 1 then return list[1] end

    -- Le os requisitos do GUI UMA vez; a versao anterior relia Reset/TR
    -- para cada candidato com o mesmo alias normalizado.
    local gLvl = extractNumber(lvlTxt or readText(gui, "LVRequired") or "0")
    local gR   = extractNumber(readText(gui, "Resets") or "0")
    local gTR  = extractNumber(readText(gui, "TrueResets") or "0")

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

-- Resolve Lighting.Battles <-> BattleInfoGui sem exigir nome literal.
-- Ordem: LinkedBattle/address -> nome exato -> nome normalizado -> requisitos.
local function resolveBattle(gui, monsterText, lvlTxt)
    local idx = battleIndex()
    local okParent, owner = pcall(function() return gui.Parent end)

    if okParent and owner then
        -- LinkedBattle e a pista mais forte e NAO muda o TP; so identifica
        -- qual registro do Lighting corresponde ao gui antigo. O ObjectValue
        -- pode apontar para o Model enquanto o gui esta num Head/Part interno,
        -- entao testa o owner e ate 3 ancestrais.
        local node = owner
        for _ = 0, 3 do
            local byAddr = idx.linkedAddress[safeAddress(node)]
            if byAddr and byAddr ~= false then return byAddr end

            local ownerName = safeName(node)
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

    local cleanMonster = cleanText(monsterText)
    if cleanMonster then
        local exactMonster = idx.exact[string.lower(cleanMonster)]
        if exactMonster and exactMonster ~= false then return exactMonster end
    end

    local aliases = {}
    if okParent and owner then
        local node = owner
        for _ = 0, 3 do
            aliases[#aliases + 1] = safeName(node)
            local okUp, up = pcall(function() return node.Parent end)
            if not okUp or not up then break end
            node = up
        end
    end
    aliases[#aliases + 1] = cleanMonster
    for _, alias in ipairs(aliases) do
        local norm = normalizeBossAlias(alias)
        if norm then
            local one = idx.norm[norm]
            if one and one ~= false then return one end
            local chosen = chooseNormCandidate(idx.normAll[norm], gui, lvlTxt)
            if chosen then return chosen end
        end
    end

    -- Ultimo fallback para MonsterName realmente ilegivel: usa a
    -- assinatura Lv/R/TR e, quando disponiveis, Gold/EXP.
    -- Primeiro consulta bucket exato; se precisar pontuar, restringe ao
    -- mesmo Level. Nunca mais percorre allBattles() inteiro por GUI.
    local gLvl = extractNumber(lvlTxt or readText(gui, "LVRequired") or "0")
    if gLvl > 0 then
        local gR  = extractNumber(readText(gui, "Resets") or "0")
        local gTR = extractNumber(readText(gui, "TrueResets") or "0")
        local gGold, gExp = parseRewardValues(readText(gui, "Rewards") or "")

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

local function bossDisplayName(gui, monsterText)
    local b = resolveBattle(gui, monsterText)
    if b then
        -- Prioridade pedida: Lighting BattleName -> BattleGui -> pasta.
        return b.battleName or cleanText(monsterText) or b.folderName or "?", b
    end
    return cleanText(monsterText) or "?", nil
end

-- RewardWeapon/SoulFragment podem apontar para QUALQUER pasta do
-- Lighting (Weapons, Armor, SOULs, Gadgets, etc.). Se Matcha devolver o
-- ObjectValue como caminho-texto, pega tudo depois do ultimo ponto:
-- "game.Lighting.Gadgets.GasterBlaster" -> "GasterBlaster".
local function referenceFolderName(ref)
    if not ref then return nil end
    if type(ref) == "string" then
        local clean = cleanText(ref)
        if not clean then return nil end
        local tail = string.match(clean, "([^%.]+)$") or clean
        return cleanText(tail)
    end
    return safeName(ref)
end

local function anyDisplayName(folder)
    if not folder then return nil end

    -- Caminho textual de ObjectValue: nao ha Instance para procurar WeaponName,
    -- entao o nome final do path e a informacao mais confiavel disponivel.
    if type(folder) == "string" then
        return referenceFolderName(folder)
    end

    for _, k in ipairs({ "Weapons", "Armor", "SOULs", "Food", "Battles" }) do
        local names = DISPLAY_VALUE[k]
        if names then
            local v = readStringValue(firstChild(folder, names))
            if v then return v end
        end
    end

    -- Gadgets e qualquer categoria futura caem aqui sem precisar hardcode.
    return referenceFolderName(folder)
end

local function battleRewardLine(b)
    local p = {}
    if b.gold and b.gold > 0 then p[#p + 1] = "Gold:" .. formatNumber(b.gold) end
    if b.exp and b.exp > 0 then p[#p + 1] = "Exp:" .. formatNumber(b.exp) end
    local rn = anyDisplayName(b.reward)
    if rn then p[#p + 1] = Lang.Item .. ":" .. rn end
    local fn = anyDisplayName(b.fragment)
    if fn then p[#p + 1] = Lang.Frags .. ":" .. fn end
    if #p == 0 then return Lang.NoRewards end
    return table.concat(p, " | ")
end

----------------------------------------------------------------
-- FONTE UNIFICADA DE BOSSES
--
-- Regra: Lighting.Battles MANDA. O BattleInfoGui entra so como fallback --
-- preenche campo que o Lighting nao tem/nao leu, fornece os textos (Rewards,
-- Fragment, Material) que so existem no gui, e da o alvo de TP.
--
-- Um boss pode terminar em tres estados:
--   "lighting" -> so no Lighting.Battles (ex: Chicken). Sem TP.
--   "both"     -> no Lighting E com gui no mapa. Caso normal, TP disponivel.
--   "gui"      -> so no workspace, sem entrada no Lighting. Fallback puro.
----------------------------------------------------------------

local function fillFromGui(rec, gui, nameTxt, lvlTxt)
    rec.gui      = gui
    rec.rewards  = readText(gui, "Rewards") or ""
    rec.fragment = readText(gui, "Fragment") or ""
    rec.guiName  = cleanText(nameTxt)

    local okOwner, owner = pcall(function() return gui.Parent end)
    rec.guiOwnerName = (okOwner and owner) and safeName(owner) or nil
    rec.guiOwnerAddress = (okOwner and owner) and safeAddress(owner) or nil

    local gLvl = extractNumber(lvlTxt or "0")
    local gR   = extractNumber(readText(gui, "Resets") or "0")
    local gTR  = extractNumber(readText(gui, "TrueResets") or "0")
    local gGold, gExp = parseRewardValues(rec.rewards)

    -- BattleInfoGui mostra o Gold ja multiplicado pelos Resets
    -- antes dos parenteses. O valor entre parenteses ("Base") corresponde ao
    -- Gold cru do Lighting.Battles. Guardamos as duas fontes separadamente.
    if gGold > 0 then rec.guiGold = gGold end
    local gBaseText = string.match(rec.rewards, "%(([%d%.,]+%s*" .. SUF .. ")%s*[Bb][Aa][Ss][Ee]%)")
    local gBase = gBaseText and parseNumberWithSuffix(gBaseText) or 0
    if (rec.baseGold == nil or rec.baseGold == 0) and gBase > 0 then rec.baseGold = gBase end

    -- So preenche o que veio nil do Lighting.
    -- Zero no Lighting tambem pede tentativa no gui, conforme
    -- a regra do guider: so fica zero se as duas fontes nao tiverem algo util.
    if (rec.lvl == nil or rec.lvl == 0) and gLvl > 0 then rec.lvl = gLvl end
    if (rec.r   == nil or rec.r   == 0) and gR   > 0 then rec.r   = gR end
    if (rec.tr  == nil or rec.tr  == 0) and gTR  > 0 then rec.tr  = gTR end

    -- Gold/EXP tambem aceitam substituir um ZERO do Lighting: muito
    --            fork deixa esses IntValue em 0 e paga a recompensa por script,
    --            e um 0 global quebraria a aba Farms inteira. O gui so entra
    --            quando tem numero > 0 para oferecer.
    if (rec.gold == nil or rec.gold == 0) and gGold > 0 then rec.gold = gGold end
    if (rec.exp  == nil or rec.exp  == 0) and gExp  > 0 then rec.exp  = gExp end
end

local function collectBosses()
    if catalogCache.bosses then return catalogCache.bosses end

    local list, byBattle, guiOnly = {}, {}, {}

    -- 1) Fonte primaria: Lighting.Battles. Cada PASTA e um registro unico;
    -- nomes nunca sao usados como chave primaria, evitando colisao entre bosses.
    for _, b in ipairs(allBattles()) do
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

    -- 2) Fallback/TP: BattleInfoGui do workspace.
    -- IMPORTANTE: nao exige mais MonsterName/LV legiveis para casar.
    -- Se o texto estiver bugado, LinkedBattle/owner ainda consegue anexar o GUI
    -- ao registro do Lighting e restaurar o TP mesmo quando uma das fontes vier corrompida.
    for _, gui in ipairs(collectBattleGuis()) do
        local nameTxt = readText(gui, "MonsterName")
        local lvlTxt  = readText(gui, "LVRequired")
        local b = resolveBattle(gui, nameTxt, lvlTxt)
        local rec = b and byBattle[b] or nil

        if rec then
            -- Boss ja veio do Lighting: o gui so completa. Primeiro gui vence.
            if not rec.gui then
                rec.source = "both"
                fillFromGui(rec, gui, nameTxt, lvlTxt)
            end
        elseif nameTxt then
            -- Boss realmente sem entrada correspondente no Lighting.
            -- Usa endereco do owner como chave; so cai no nome normalizado se
            -- nao houver Address. Assim clones do mesmo GUI nao duplicam a lista.
            local okOwner, owner = pcall(function() return gui.Parent end)
            local key = (okOwner and owner and safeAddress(owner))
                or normalizeBossAlias(nameTxt)
                or string.lower(nameTxt)
            if not guiOnly[key] then
                local nrec = {
                    name = nameTxt, battle = nil, source = "gui",
                    stableKey = "gui:" .. tostring(key),
                }
                fillFromGui(nrec, gui, nameTxt, lvlTxt)
                guiOnly[key] = nrec
                list[#list + 1] = nrec
            end
        end
    end

    -- 3) Normaliza e deriva o que depende das duas fontes.
    for _, rec in ipairs(list) do
        local b = rec.battle

        -- Cadeia final e explicita:
        -- BattleName valido -> MonsterName valido -> nome da pasta -> owner.
        -- "Unreadable_name" e strings corrompidas ja chegam como nil.
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
        -- Gold efetivamente exibido pelo BattleInfoGui (com multiplicador de
        -- Reset). Se o GUI nao existir/nao puder ser lido, cai no Gold base.
        rec.farmGold = (rec.guiGold and rec.guiGold > 0) and rec.guiGold or rec.gold
        rec.exp  = rec.exp or 0
        rec.noTP = (rec.gui == nil)

        -- SoulFragment do Lighting e o nome real da alma; se a leitura
        -- do ObjectValue/nome vier "Unreadable_name", cai no Fragment do gui.
        local lightingSoul = b and anyDisplayName(b.fragment) or nil
        rec.soul = lightingSoul or extractSoulName(rec.fragment)

        -- Metadados do item/alma apontados pelos ObjectValues.
        -- Para RewardWeapon textual/GUI sem alvo resolvido, nao inventamos flags.
        if b then
            rec.rewardPermanent, rec.rewardTruePermanent, rec.rewardPermKind = referencePermanence(b.reward)
            rec.soulPermanent, rec.soulTruePermanent, rec.soulPermKind = referencePermanence(b.fragment)
        end

        -- RewardWeapon do Lighting indica que existe drop, mas o
        -- nome mostrado so vem dele se estiver legivel; caso contrario o texto
        -- do gui continua sendo usado para apresentar o item.
        local lightingRewardName = b and anyDisplayName(b.reward) or nil
        -- O simples fato de RewardWeapon ser um ObjectValue nao
        -- prova que o boss dropa item: muitos Battles mantem o ObjectValue
        -- presente com Value vazio/ilegivel. Scanner so considera reward real
        -- quando conseguimos resolver um NOME valido do item pelo Lighting ou
        -- quando o texto antigo de Rewards contem recompensa especial alem de
        -- Gold/EXP. Isso impede bosses de Gold/EXP puro de aparecerem no Scanner.
        rec.hasReward = (lightingRewardName ~= nil) or checkRewardsCustom(rec.rewards)

        -- Se Lighting conhece o RewardWeapon, ele tem
        -- prioridade tambem na EXIBICAO. Antes, um BattleInfoGui com texto
        -- "Gold/EXP" nao vazio fazia entryLines usar formatRewards(gui) e
        -- escondia o item do Lighting (caso GasterBlaster). Monta a linha com
        -- Gold/EXP ja unificados + o reward real, independentemente do gui.
        if lightingRewardName then
            local parts = {}
            if rec.gold > 0 then parts[#parts + 1] = "Gold:" .. formatNumber(rec.gold) end
            if rec.exp  > 0 then parts[#parts + 1] = "Exp:" .. formatNumber(rec.exp) end
            parts[#parts + 1] = Lang.Item .. ":" .. lightingRewardName
            rec.rewardLine = table.concat(parts, " | ")
        elseif rec.rewards == "" and b then
            rec.rewardLine = battleRewardLine(b)
        end
    end

    catalogCache.bosses = list
    return list
end

----------------------------------------------------------------
-- FRAGMENTOS QUE VOCE TEM
--
--   Players.<voce>.SoulFragments.<Nome>  -> NumberValue com a quantidade
--   Lighting.SOULs.<pasta>.Fragments     -> quantos a receita pede
--
-- ATENCAO: o nome do contador NEM SEMPRE e o nome da pasta da alma. No jogo
-- existem contadores como "W.D Gaster Soul" e "X Gaster Soul" enquanto a pasta
-- da alma e so "Gaster". Por isso a resolucao tem tres niveis e o palpite fica
-- marcado com "?" -- inventar um 0/N seria pior do que admitir que nao achou.
----------------------------------------------------------------

-- Reduz o nome a letras e numeros minusculos e derruba o sufixo "soul":
--   "W.D Gaster Soul" -> "wdgaster" ; "Annoying Dog Soul" -> "annoyingdog"
local function normalizeName(str)
    local n = string.lower(tostring(str or ""))
    n = string.gsub(n, "[^%w]", "")
    n = string.gsub(n, "soul$", "")
    return n
end

-- Escape hatch: pasta da alma em Lighting.SOULs -> nome EXATO do
--        contador em SoulFragments. Use quando a heuristica nao tiver como
--        adivinhar (ex: alma "Gaster" com dois contadores candidatos).
--        Descomente e ajuste conforme o seu jogo:
local FRAGMENT_OVERRIDES = {
    -- = "W.D Gaster Soul",
}

local function fragmentCounters()
    if catalogCache.frags then return catalogCache.frags end
    local out = { exact = {}, norm = {}, list = {}, exists = false }
    local folder = myFolder("SoulFragments")
    if folder then
        out.exists = true
        for _, kid in ipairs(safeChildren(folder)) do
            local nm = safeName(kid)
            if nm and nm ~= "" then
                local rec = { name = nm, value = readNumberValue(kid, nil), norm = normalizeName(nm) }
                out.list[#out.list + 1] = rec
                out.exact[nm] = rec
                -- Colisao de normalizado: o primeiro vence, e o nivel 3 nem roda.
                if out.norm[rec.norm] == nil then out.norm[rec.norm] = rec end
            end
        end
    end
    -- Linha curta que diz se o Player e a pasta foram achados e quantos
    --        contadores foram lidos. Sem isso, "nao funciona" nao tem sinal.
    local plr = resolvePlayer()
    local unread = 0
    for _, c in ipairs(out.list) do
        if c.value == nil then unread = unread + 1 end
    end
    state.fragDiag = "Player: " .. (plr and (safeName(plr) or "?") or "NAO ACHADO")
        .. " | SoulFragments: " .. (out.exists and (#out.list .. (unread > 0 and (" (" .. unread .. " ilegiveis)") or "")) or "NAO ACHADA")

    catalogCache.frags = out
    return out
end

-- Devolve o contador da alma + como foi achado ("exact" | "guess"), ou nil.
local function resolveFragments(entry)
    local fc = fragmentCounters()
    if not fc.exists then return nil end

    -- Nivel 0: mapa manual, se voce preencheu FRAGMENT_OVERRIDES.
    local forced = FRAGMENT_OVERRIDES[entry.folderName]
    if forced and fc.exact[forced] then return fc.exact[forced], "exact" end

    -- Nivel 1: nome da pasta ou o SoulName, literais.
    local rec = fc.exact[entry.folderName] or fc.exact[entry.label]
    if rec then return rec, "exact" end

    -- Nivel 2: normalizado, que absorve espaco, ponto e o sufixo "Soul".
    rec = fc.norm[normalizeName(entry.folderName)] or fc.norm[normalizeName(entry.label)]
    if rec then return rec, "exact" end

    -- Nivel 3: contador que CONTEM o nome da alma. So aceita candidato UNICO --
    -- "Gaster" bate em dois contadores, entao fica sem em vez de chutar errado.
    local target = normalizeName(entry.folderName)
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

----------------------------------------------------------------
-- ITENS DO CATALOGO E DE ONDE ELES VEM
----------------------------------------------------------------

local ITEM_KINDS = {
    { kind = "Weapons", tagKey = "TagWeapon" },
    { kind = "Armor",   tagKey = "TagArmor"  },
    { kind = "SOULs",   tagKey = "TagSoul"   },
    -- Food participa de Buscar, shops e fontes de boss.
    { kind = "Food",    tagKey = "TagFood"   },
}

-- Lista unica de arma + armadura + alma + food, ja com nome de exibicao e loja.
local function allCatalogItems()
    if catalogCache.items then return catalogCache.items end
    local out = {}
    for _, def in ipairs(ITEM_KINDS) do
        for _, folder in ipairs(safeChildren(catalogFolder(def.kind))) do
            local fname = safeName(folder)
            if fname and fname ~= "" then
                local permanent, truePermanent = itemPermanence(folder)
                local entry = {
                    kind = def.kind,
                    tag = Lang[def.tagKey],
                    folder = folder,
                    folderName = fname,
                    label = displayName(folder, def.kind, fname),
                    shop = shopInfo(folder),
                    permanent = permanent, truePermanent = truePermanent,
                }
                if def.kind == "SOULs" then
                    entry.fragments = soulFragmentCost(folder)
                    -- Quantos voce ja tem, se der para localizar o contador.
                    local rec, how = resolveFragments(entry)
                    if rec then
                        -- rec.value pode ser nil se a leitura falhar; o
                        --        haveFound separa "nao achei o contador" de
                        --        "achei mas nao consegui ler o numero".
                        entry.have      = rec.value
                        entry.haveName  = rec.name
                        entry.haveHow   = how
                        entry.haveFound = true
                    end
                    entry.ready = (entry.have ~= nil and entry.fragments ~= nil
                        and entry.fragments > 0 and entry.have >= entry.fragments) or false
                elseif def.kind == "Food" then
                    -- Buscar/O que falta tambem mostram Heal/Max e
                    -- metadados do catalogo, nao so o nome da comida.
                    local fs = foodStats(fname, folder)
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

-- Forma 1 do Battles: os ObjectValue RewardWeapon / SoulFragment
--        apontam direto para a pasta do item. E o vinculo confiavel.
local function bossSourceIndex()
    if catalogCache.sources then return catalogCache.sources end
    local idx = {}
    local function push(target, battle, drop)
        -- ObjectValue pode ser Instance ou caminho-texto. Para cruzar com o
        -- catalogo usa o nome da pasta, nao o display name.
        local nm = referenceFolderName(target)
        if not nm then return end
        idx[nm] = idx[nm] or {}
        table.insert(idx[nm], { boss = battle, drop = drop })
    end
    for _, b in ipairs(allBattles()) do
        push(b.reward, b, "reward")
        push(b.fragment, b, "fragment")
    end
    catalogCache.sources = idx
    return idx
end

-- Forma 2 do Battles: o texto de Rewards/Fragment do BattleInfoGui.
--        Serve para boss que entrega item sem preencher o RewardWeapon.
local function guiRewardIndex()
    if catalogCache.guiRewards then return catalogCache.guiRewards end
    local out = {}
    -- Sai de collectBosses em vez de varrer o Workspace de novo: uma
    --        unica passada por scan, e ja com o nome/LV resolvidos pelo Lighting.
    for _, b in ipairs(collectBosses()) do
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

-- Substring crua fazia nome curto colidir: "RED" batia dentro de
--         "hundred". Aqui o nome so casa como PALAVRA INTEIRA -- olha o char
--         antes e depois e exige que nao seja alfanumerico. Feito na mao com
--         string.find plain porque o padrao de fronteira (%f) nao e garantido
--         em toda LuaVM.
local function findWord(hay, needle)
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

-- Com palavra inteira, 2 chars ja e seguro.
local TEXT_MATCH_MIN = 2
-- Ultimo recurso: substring solta. So para nome longo, onde um acerto
--         parcial praticamente nao acontece por acaso. Cobre plural e sufixo
--         ("...and Lost Blades"), que a palavra inteira perderia.
local LOOSE_MATCH_MIN = 5

local function itemBossSources(entry)
    local out = {}
    -- Nivel 1: ObjectValue do Lighting.Battles -- vinculo exato, sem adivinhacao.
    for _, src in ipairs(bossSourceIndex()[entry.folderName] or {}) do
        out[#out + 1] = src
        if #out >= MAX_SOURCES_PER_ITEM then return out end
    end
    if #out > 0 then return out end

    local a, b = string.lower(entry.label), string.lower(entry.folderName)

    -- Nivel 2: nome como palavra inteira no texto do BattleInfoGui.
    for _, g in ipairs(guiRewardIndex()) do
        if (#a >= TEXT_MATCH_MIN and findWord(g.hay, a))
            or (#b >= TEXT_MATCH_MIN and findWord(g.hay, b)) then
            out[#out + 1] = { boss = g, drop = "text" }
            if #out >= MAX_SOURCES_PER_ITEM then return out end
        end
    end
    if #out > 0 then return out end

    -- Nivel 3: substring solta, so para nome longo. Marcado como "guess".
    for _, g in ipairs(guiRewardIndex()) do
        if (#a >= LOOSE_MATCH_MIN and string.find(g.hay, a, 1, true))
            or (#b >= LOOSE_MATCH_MIN and string.find(g.hay, b, 1, true)) then
            out[#out + 1] = { boss = g, drop = "guess" }
            if #out >= MAX_SOURCES_PER_ITEM then break end
        end
    end
    return out
end

local function itemSources(entry)
    local src = { shop = entry.shop, bosses = itemBossSources(entry) }
    -- Resolve os pontos apenas para item que realmente virou resultado.
    src.shopTargets = shopTargets(src.shop)
    src.shopName = src.shop and src.shop.shop or nil
    -- Alma com fragmentos suficientes ja e obtivel por definicao -- o
    --        craft em si e a fonte. Sem isso ela sumia da lista quando o Onsale
    --        estava desmarcado, justamente estando pronta para pegar.
    src.any = (src.shop ~= nil) or (#src.bosses > 0) or (entry.ready == true)
    return src
end

-- "Craft: 23 / 50  (faltam 27)" ou "Craft: 60 / 50  PRONTO".
--        Sem contador correspondente, cai no formato antigo (so o requisito).
local function soulCraftLine(entry)
    local need = entry.fragments
    if entry.have == nil then
        -- Contador localizado mas com valor ilegivel: mostra "?" em vez de
        -- fingir que a alma nao tem contador nenhum.
        if entry.haveFound then
            return Lang.Craft .. ": ? / " .. formatNumber(need)
                .. "  [" .. tostring(entry.haveName) .. "]"
        end
        return Lang.Craft .. ": " .. formatNumber(need) .. " " .. Lang.Frags
    end
    local t = Lang.Craft .. ": " .. formatNumber(entry.have) .. " / " .. formatNumber(need)
    if entry.have >= need then
        t = t .. "  " .. Lang.FragReady
    else
        t = t .. "  (" .. Lang.FragNeed .. " " .. formatNumber(need - entry.have) .. ")"
    end
    -- Deixa visivel qual contador foi usado quando a associacao foi deduzida.
    if entry.haveHow == "guess" then
        t = t .. "  [" .. tostring(entry.haveName) .. "?]"
    end
    return t
end

local function itemSourceLines(entry, src)
    src = src or itemSources(entry)
    local lines = {}

    -- Buscar / O QUE FALTA sempre deixam claro os dois flags.
    local pl = permanenceLine(entry.permanent, entry.truePermanent, nil, true)
    if pl then lines[#lines + 1] = pl end

    -- Informacoes uteis aparecem tambem na Buscar/Faltantes.
    if entry.kind == "Food" then
        lines[#lines + 1] = Lang.FoodHeal .. ": " .. (entry.heal ~= nil and formatNumber(entry.heal) or "?")
        lines[#lines + 1] = Lang.FoodMax .. ": " .. (entry.max ~= nil and tostring(math.floor(entry.max)) or "?")
        if entry.cost ~= nil and not src.shop then
            lines[#lines + 1] = Lang.FoodCost .. ": " .. formatNumber(entry.cost) .. " Gold"
        end
        lines[#lines + 1] = Lang.FoodOnSale .. ": "
            .. ((entry.onsale == true and Lang.FoodYes) or (entry.onsale == false and Lang.FoodNo) or "?")
    end

    if src.shop then
        local t = Lang.Shop .. ": " .. (src.shop.shop or "?")
        if src.shop.cost then t = t .. "  |  " .. formatNumber(src.shop.cost) .. " Gold" end
        lines[#lines + 1] = t
    end
    -- Alma e craftada: receita + quantos fragmentos voce ja juntou.
    if entry.kind == "SOULs" and entry.fragments and entry.fragments > 0 then
        lines[#lines + 1] = soulCraftLine(entry)
    end
    for _, s in ipairs(src.bosses) do
        local b = s.boss
        -- "Boss?" = deduzido do texto do gui, nao do ObjectValue. Fica
        --         explicito para voce nao confiar cegamente num palpite.
        local tag
        if s.drop == "fragment" then tag = Lang.Frags
        elseif s.drop == "reward" then tag = Lang.Boss
        else tag = Lang.BossGuess end
        local bossLine = tag
            .. ": " .. b.name
            .. " (Lv:" .. formatReq(b.lvl or 0)
            .. " | R:" .. formatReq(b.r or 0)
            .. " | TR:" .. formatReq(b.tr or 0) .. ")"
        -- Em resultados de alma/fonte de fragmento, mostra
        -- diretamente Lighting.Battles.<Boss>.FragmentChance.Value.
        if b.fragChance ~= nil and (s.drop == "fragment" or entry.kind == "SOULs") then
            bossLine = bossLine .. " | " .. Lang.FragmentChance .. ": "
                .. formatFragmentChance(b.fragChance)
        end
        lines[#lines + 1] = bossLine
    end

    -- Sempre deixa explicito quando nao ha loja NEM boss: uma alma pode
    --        ter receita conhecida (Craft: N) e mesmo assim nao ter de onde
    --        tirar os fragmentos -- sem esta linha isso parecia obtivel.
    if not src.any then lines[#lines + 1] = Lang.NoSource end
    return lines
end

----------------------------------------------------------------
-- RESULTADOS (substitui addToList / addBossToList)
----------------------------------------------------------------

local function beginScan(kind)
    state.busy = true
    state.messageKey = nil
    -- Qualquer novo scan limpa o status/aviso da rota anterior.
    state.status = ""
    state.progressWarning = nil
    state.results = {}
    state.count = 0
    state.countKind = kind or "found"
    state.scanned = true
    -- Cada scan volta ao teto padrao; quem precisar de mais sobrescreve
    --         state.resultCap logo depois de chamar beginScan.
    state.resultCap = MAX_RESULTS
    -- nil = usa a regra antiga (count > linhas exibidas). A Build define
    --         o proprio numero, porque la o count e "itens possuidos", nao linhas.
    state.overflow = nil
    -- Dados de Lighting sao cacheados por scan: cada clique le do zero.
    invalidateCatalog()
end

local function endScan(count, kind)
    state.count = count
    if kind then state.countKind = kind end
    state.busy = false
    state.stamp = state.stamp + 1
end

local function addResult(entry)
    if #state.results >= (state.resultCap or MAX_RESULTS) then return end
    table.insert(state.results, entry)
end

-- cache das linhas ja formatadas: formatRewards() e caro e o menu
--        redesenha por frame. Recalcula so quando o idioma muda.
local function entryLines(e)
    -- Linhas ja prontas (aba Build). Nao passam por formatRewards nem
    --         pelo cabecalho Lv/R/TR, que nao fazem sentido para equipamento.
    if e.rawLines then return e.rawLines end
    if e.lines and e.cacheLang == CurrentLanguage then return e.lines end
    local l = {}
    l[#l + 1] = "Lv:" .. formatReq(e.lvl) .. " | R:" .. formatReq(e.r) .. " | TR:" .. formatReq(e.tr)
    -- Boss que so existe no Lighting nao tem alvo no mapa: avisa aqui,
    --        ja que o botao de TP nem chega a ser desenhado.
    if e.noTP then l[#l + 1] = Lang.NoTP end
    -- Nome ja resolvido pelo SoulFragment do Lighting tem prioridade.
    local showedSoul = false
    if e.soul and e.soul ~= "" then
        l[#l + 1] = "Soul: " .. e.soul
        showedSoul = true
    elseif e.fragment and e.fragment ~= "" then
        l[#l + 1] = "Soul: " .. (extractSoulName(e.fragment) or e.fragment)
        showedSoul = true
    end
    if showedSoul and e.fragChance ~= nil then
        l[#l + 1] = Lang.FragmentChance .. ": " .. formatFragmentChance(e.fragChance)
    end
    if showedSoul and (e.soulPermKind or e.soulPermanent ~= nil or e.soulTruePermanent ~= nil) then
        local spl = permanenceLine(e.soulPermanent, e.soulTruePermanent, Lang.Soul, true)
        if spl then l[#l + 1] = spl end
    end
    if e.material and e.material ~= "" then
        l[#l + 1] = "Material: " .. e.material
    end
    if e.highlight and e.highlight ~= "" then
        l[#l + 1] = e.highlight
    end
    -- A rota fornece uma linha de EXP pronta; demais features continuam
    --        usando formatRewards exatamente como antes.
    if e.rewardLine and e.rewardLine ~= "" then
        l[#l + 1] = e.rewardLine
    else
        l[#l + 1] = formatRewards(e.rewards)
    end
    if e.rewardPermKind or e.rewardPermanent ~= nil or e.rewardTruePermanent ~= nil then
        local rpl = permanenceLine(e.rewardPermanent, e.rewardTruePermanent, Lang.Item, true)
        if rpl then l[#l + 1] = rpl end
    end
    e.lines = l
    e.cacheLang = CurrentLanguage
    return l
end

----------------------------------------------------------------
-- LEITURA DOS STATS / FILTROS
----------------------------------------------------------------

-- o original usava tonumber() nos 3 stats (sufixo "50K" virava 0) e
--        parseNumberWithSuffix() so nos filtros. O prompt especifica sufixo em
--        TODOS -> unificado em parseNumberWithSuffix (identico p/ numero puro).
local function readStats()
    local myL  = parseNumberWithSuffix(getInput("utmm_level"))
    local myR  = parseNumberWithSuffix(getInput("utmm_resets"))
    local myTR = parseNumberWithSuffix(getInput("utmm_tr"))

    local rMaxTxt = getInput("utmm_reset_max")
    local tMaxTxt = getInput("utmm_tr_max")

    local rMin = parseNumberWithSuffix(getInput("utmm_reset_min"))
    local rMax = (rMaxTxt ~= "") and parseNumberWithSuffix(rMaxTxt) or nil
    local tMin = parseNumberWithSuffix(getInput("utmm_tr_min"))
    local tMax = (tMaxTxt ~= "") and parseNumberWithSuffix(tMaxTxt) or nil

    local uRF = (rMin > 0 or rMax ~= nil)
    local uTF = (tMin > 0 or tMax ~= nil)

    return myL, myR, myTR, rMin, rMax, tMin, tMax, uRF, uTF
end

----------------------------------------------------------------
-- ORDEM DOS BOSSES NOS RESULTADOS
-- Menor requisito primeiro: TR -> Reset -> Level. Independente dos requisitos,
-- boss sem TP sempre vai para o fim. Nome desempata para a lista nao "pular".
----------------------------------------------------------------

local function bossRequirementLess(a, b)
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

----------------------------------------------------------------
-- SCAN (aba Scanner)
----------------------------------------------------------------

local function runCustomScan()
    beginScan("found")
    -- Scanner mostra todos os resultados encontrados.
    state.resultCap = math.huge

    local myL, myR, myTR, rMin, rMax, tMin, tMax, uRF, uTF = readStats()
    local exR  = getToggle("utmm_exact_reset")
    local exTR = getToggle("utmm_exact_tr")
    local incF = getToggle("utmm_include_frag")

    local matches = {}
    -- Lighting.Battles primeiro; gui so como fallback (ver collectBosses).
    for _, b in ipairs(collectBosses()) do
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
                noTP = b.noTP,
                gui = b.gui,
            }
        end
    end

    -- Requisitos crescentes; sem TP sempre no fim.
    table.sort(matches, bossRequirementLess)
    for _, entry in ipairs(matches) do addResult(entry) end

    endScan(#matches, "found")
end

----------------------------------------------------------------
-- FARMS (aba Farms)
----------------------------------------------------------------

-- Farms trabalha somente com os stats atuais do usuario.
-- LEVEL e SEMPRE um teto de acesso. Reset/TR usam os campos fixos quando os
-- respectivos filtros Min/Max estao vazios; se qualquer limite da categoria
-- estiver preenchido, a faixa substitui o stat fixo daquela categoria.
local function farmBoundText(id)
    local txt = tostring(getInput(id) or "")
    txt = string.match(txt, "^%s*(.-)%s*$") or ""
    return txt
end

local function findBestFarm(typeStr)
    beginScan("best")

    local myL  = parseNumberWithSuffix(getInput("utmm_level"))
    local myR  = parseNumberWithSuffix(getInput("utmm_resets"))
    local myTR = parseNumberWithSuffix(getInput("utmm_tr"))

    local rMinTxt = farmBoundText("utmm_reset_min")
    local rMaxTxt = farmBoundText("utmm_reset_max")
    local tMinTxt = farmBoundText("utmm_tr_min")
    local tMaxTxt = farmBoundText("utmm_tr_max")

    -- Compatibilidade com configs antigas: Reset/TR MIN tinham
    -- default "0". Um MIN isolado em 0 equivale a campo vazio; com MAX
    -- preenchido, 0 continua funcionando naturalmente como limite inferior.
    local useRRange = (rMaxTxt ~= "") or (rMinTxt ~= "" and rMinTxt ~= "0")
    local useTRRange = (tMaxTxt ~= "") or (tMinTxt ~= "" and tMinTxt ~= "0")

    local rMin = (rMinTxt ~= "") and parseNumberWithSuffix(rMinTxt) or nil
    local rMax = (rMaxTxt ~= "") and parseNumberWithSuffix(rMaxTxt) or nil
    local tMin = (tMinTxt ~= "") and parseNumberWithSuffix(tMinTxt) or nil
    local tMax = (tMaxTxt ~= "") and parseNumberWithSuffix(tMaxTxt) or nil

    local cands = {}
    -- Gold/EXP saem dos Values do Lighting.Battles; BattleInfoGui fica
    --        apenas como fallback dentro de collectBosses().
    for _, b in ipairs(collectBosses()) do
        -- Nivel nunca e ignorado: so boss ja acessivel no LEVEL.
        local pL = (b.lvl <= myL)

        local pR = true
        if useRRange then
            if rMin ~= nil and b.r < rMin then pR = false end
            if rMax ~= nil and b.r > rMax then pR = false end
        else
            -- Sem faixa: requisito de Reset precisa caber nos seus Resets.
            if b.r > myR then pR = false end
        end

        local pTR = true
        if useTRRange then
            if tMin ~= nil and b.tr < tMin then pTR = false end
            if tMax ~= nil and b.tr > tMax then pTR = false end
        else
            -- TR 0 = sem requisito; qualquer TR positivo precisa caber no seu.
            if b.tr > 0 and b.tr > myTR then pTR = false end
        end

        local rewardValue = (typeStr == "Gold") and (b.farmGold or b.gold or 0) or (b.exp or 0)
        if pL and pR and pTR and rewardValue > 0 then
            cands[#cands + 1] = b
        end
    end

    -- Maior recompensa primeiro. Empates preferem o boss de
    -- menor requisito e, por fim, quem possui TP.
    table.sort(cands, function(a, b)
        local av = (typeStr == "Gold") and (a.farmGold or a.gold or 0) or (a.exp or 0)
        local bv = (typeStr == "Gold") and (b.farmGold or b.gold or 0) or (b.exp or 0)
        if av ~= bv then return av > bv end
        return bossRequirementLess(a, b)
    end)

    -- Mostra os 10 melhores bosses acessiveis pelos seus stats.
    local dc = math.min(10, #cands)
    for i = 1, dc do
        local c = cands[i]
        local baseGold = c.baseGold or c.gold or 0
        local resetGold = c.farmGold or c.guiGold or c.gold or 0
        local farmParts = {}

        -- Nao mostra mais dois "Gold:" indistinguiveis.
        -- Base = Lighting / valor entre parenteses do BattleInfoGui.
        -- Com Reset = valor antes dos parenteses no BattleInfoGui.
        if baseGold > 0 then
            farmParts[#farmParts + 1] = "Gold Base:" .. formatNumber(baseGold)
        end
        if resetGold > 0 then
            farmParts[#farmParts + 1] = "Gold c/ Reset:" .. formatNumber(resetGold)
        end
        if typeStr == "Gold" and c.exp and c.exp > 0 then
            farmParts[#farmParts + 1] = "Exp:" .. formatNumber(c.exp)
        end
        local farmItem = c.battle and anyDisplayName(c.battle.reward) or nil
        if farmItem then farmParts[#farmParts + 1] = Lang.Item .. ":" .. farmItem end

        addResult({
            name = c.name, lvl = c.lvl, r = c.r, tr = c.tr,
            rewards = c.rewards, rewardLine = table.concat(farmParts, " | "),
            rewardPermanent = c.rewardPermanent, rewardTruePermanent = c.rewardTruePermanent,
            rewardPermKind = c.rewardPermKind,
            -- Gold ja aparece, com os DOIS valores rotulados, na rewardLine.
            -- Para EXP mantemos o destaque sem repetir o mesmo EXP abaixo.
            highlight = (typeStr == "Gold") and nil or ("EXP:" .. formatNumber(c.exp or 0)),
            noTP = c.noTP,
            gui = c.gui,
        })
    end

    endScan(dc, "best")
end

----------------------------------------------------------------
-- TOP 5 (aba Top 5)
----------------------------------------------------------------

local TOP5_MODES = { "combined", "trueset", "reset", "level" }

local function findTop5Hardest()
    beginScan("best")

    local top5SortMode = TOP5_MODES[getCombo("utmm_top5_sort", 0) + 1] or "combined"

    -- collectBosses ja vem deduplicado e com os requisitos do Lighting.
    local cands = {}
    for _, b in ipairs(collectBosses()) do cands[#cands + 1] = b end

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
        addResult({
            name = c.name, lvl = c.lvl, r = c.r, tr = c.tr,
            rewards = c.rewards, rewardLine = c.rewardLine,
            soul = c.soul,
            fragChance = c.fragChance,
            rewardPermanent = c.rewardPermanent, rewardTruePermanent = c.rewardTruePermanent,
            rewardPermKind = c.rewardPermKind,
            soulPermanent = c.soulPermanent, soulTruePermanent = c.soulTruePermanent,
            soulPermKind = c.soulPermKind,
            highlight = "#" .. i .. " | TR:" .. formatReq(c.tr)
                .. " | R:" .. formatReq(c.r) .. " | Lv:" .. formatReq(c.lvl),
            noTP = c.noTP,
            gui = c.gui,
        })
    end

    endScan(dc, "best")
end

----------------------------------------------------------------
-- BLACKLIST DA PROGRESSAO
-- Exclusiva da rota de level; Scanner/Farms/Buscar/Top 5 nao consultam esta tabela.
----------------------------------------------------------------

local function addProgressBlacklist(name)
    if not name or name == "" or state.progressBlacklist[name] then return false end
    state.progressBlacklist[name] = true
    table.insert(state.progressBlacklistOrder, name)
    -- Salva imediatamente; se a VM nao tiver filesystem,
    -- continua funcionando normalmente apenas durante a sessao.
    saveConfig()
    return true
end

local function removeProgressBlacklist(name)
    if not name or not state.progressBlacklist[name] then return false end
    state.progressBlacklist[name] = nil
    for i = #state.progressBlacklistOrder, 1, -1 do
        if state.progressBlacklistOrder[i] == name then
            table.remove(state.progressBlacklistOrder, i)
            break
        end
    end
    saveConfig()
    return true
end

----------------------------------------------------------------
-- PROGRESSAO (aba Progressao)
--
-- Regra principal: a rota NUNCA troca voluntariamente para um boss que de
-- menos EXP que o boss recomendado na etapa anterior.
--
-- A variedade vem de duas fontes seguras:
--   * qualquer boss novo que passe a dar MAIS EXP pode entrar, mesmo que a
--     melhoria seja pequena (nao existe mais threshold/ratio de EXP);
--   * bosses novos empatados com o MELHOR EXP atual podem substituir o atual,
--     trazendo variedade sem sacrificar eficiencia.
--
-- Etapas de apenas 1-2 levels sao colapsadas na etapa anterior. Assim, se um
-- boss vira o melhor por so um instante antes de outro ainda melhor liberar,
-- o jogador nao recebe a recomendacao inutil de trocar de farm por 1 level.
--
-- Blacklist continua removendo o boss do pool inteiro; ao recalcular, a rota
-- escolhe automaticamente o melhor substituto disponivel para aqueles stats.
----------------------------------------------------------------

state.PROGRESS_MIN_STEP_LEVELS = 3

-- Helpers da progressao ficam como campos de state para nao consumir
-- registradores locais permanentes do chunk principal (limite da VM: 200).
state.progressBestBossAt = function(cands, level, previousName)
    local bestExp = nil

    -- Primeiro descobre qual e o MAIOR EXP realmente disponivel nesse level.
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

    -- Entre empates exatos do melhor EXP, prefere um boss diferente do anterior.
    -- Em empate adicional, o boss liberado mais recentemente ganha prioridade.
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

state.progressNextBestChange = function(cands, currentLevel, targetLevel, currentExp, currentName)
    local nextLevel = nil

    -- So reavalia quando acontece algo que pode manter ou melhorar a eficiencia:
    -- 1) libera um boss com EXP MAIOR; ou
    -- 2) libera um boss diferente com o MESMO melhor EXP (variedade sem perda).
    -- Boss com EXP menor nunca abre uma nova etapa.
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

state.progressCollapseShortSteps = function(rawRoute)
    local out = {}

    for _, step in ipairs(rawRoute) do
        local span = (step.finish or step.start) - step.start + 1

        -- Uma etapa curtissima no meio/fim nao vale uma troca de farm. Mantem o
        -- boss anterior por esses levels e deixa a proxima melhoria assumir depois.
        if #out > 0 and span < state.PROGRESS_MIN_STEP_LEVELS then
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

local function generateProgressRoute()
    -- O LEVEL dos stats e o destino; a rota sempre parte do menor
    -- level em que existe algum boss elegivel.
    local alvo = parseNumberWithSuffix(getInput("utmm_level"))

    beginScan("found")

    if alvo <= 0 then
        state.status = Lang.SetLevel
        endScan(0, "found")
        return
    end

    -- Progressao usa somente LEVEL alvo + seus RESETS + TRUE RESETS. Os campos
    -- Min/Max das outras paginas continuam sem interferir aqui.
    local _, myR, myTR = readStats()
    local cands = {}

    for _, b in ipairs(collectBosses()) do
        local passR  = (b.r <= myR)
        local passTR = (b.tr <= 0) or (b.tr <= myTR)

        if not state.progressBlacklist[b.name]
            and passR and passTR and b.lvl <= alvo and b.exp > 0 then
            cands[#cands + 1] = b
        end
    end

    if #cands == 0 then
        state.status = Lang.NoneEligible
        endScan(0, "found")
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
        endScan(0, "found")
        return
    end

    if firstLevel > 1 then
        state.progressWarning = Lang.StartGap .. " " .. firstLevel
    end

    local rawRoute = {}
    local current = firstLevel
    local previousName = nil

    while current <= alvo do
        local chosen, bestExp = state.progressBestBossAt(cands, current, previousName)
        if not chosen or bestExp == nil then
            break
        end

        local nextStart = state.progressNextBestChange(
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

    local route = state.progressCollapseShortSteps(rawRoute)

    if #route == 0 then
        state.status = Lang.NoneEligible
        endScan(0, "found")
        return
    end

    for i = 1, #route do
        local step = route[i]
        local c = step.boss
        addResult({
            name = c.name, lvl = c.lvl, r = c.r, tr = c.tr,
            rewards = "",
            rewardLine = "EXP:" .. formatNumber(c.exp),
            highlight = "#" .. i .. "  Lv " .. step.start .. " -> " .. step.finish,
            stepIndex = i,
            noTP = c.noTP,
            progressEntry = true,
            gui = c.gui,
        })
    end

    state.status = #route .. " " .. Lang.Steps .. " " .. alvo
    endScan(#route, "found")
end

----------------------------------------------------------------
-- O QUE FALTA  (segundo botao da aba Progressao)
--
-- Compara o que voce tem com o catalogo inteiro:
--     Players.<voce>.Weapons / .Armor / .SOULs
--   x Lighting.Weapons / .Armor / .SOULs
--
-- Marcado   -> lista TUDO que falta, inclusive o que nao tem fonte conhecida.
-- Desmarcado-> so o que da para pegar: item de loja (Onsale/Shop/Cost) ou drop
--              de boss, cruzando as DUAS formas do Battles (o ObjectValue do
--              Lighting.Battles e o texto do BattleInfoGui).
----------------------------------------------------------------

local MISSING_MAX_RESULTS = 80

local MISSING_GROUPS = {
    { kind = "Weapons", titleKey = "MissWeapons" },
    { kind = "Armor",   titleKey = "MissArmors"  },
    { kind = "SOULs",   titleKey = "MissSouls"   },
    -- So entra em faltantes se o Player realmente tiver uma pasta Food.
    { kind = "Food",    titleKey = "MissFoods"   },
}

-- Ordem: primeiro o que da para COMPRAR (mais barato antes), depois o
--        que vem de boss (menor LV antes). Ou seja, do mais facil de pegar.
local function missingRank(m)
    -- Alma com fragmentos completos e o que da para pegar AGORA: topo.
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

local function findMissingItems()
    beginScan("found")
    state.resultCap = MISSING_MAX_RESULTS

    local showAll = getToggle("utmm_missing_all")

    local ownedByKind, existsByKind, anyFolder = {}, {}, false
    for _, def in ipairs(MISSING_GROUPS) do
        local set, exists = ownedSet(def.kind)
        ownedByKind[def.kind] = set
        existsByKind[def.kind] = exists
        if exists then anyFolder = true end
    end

    if not anyFolder then
        state.status = Lang.MissingNoFolders
        state.overflow = 0
        endScan(0, "found")
        return
    end

    local groups, total, noSource, blocked, ready = {}, 0, 0, 0, 0
    for _, def in ipairs(MISSING_GROUPS) do groups[def.kind] = {} end

    for _, entry in ipairs(allCatalogItems()) do
        local owned = ownedByKind[entry.kind]
        -- Casa pelo nome da PASTA: e assim que o kit grava o Value no seu
        --        inventario, mesmo quando o rotulo de exibicao e outro.
        if existsByKind[entry.kind] and owned and not owned[entry.folderName] then
            local key = missingKey(entry.kind, entry.folderName)
            -- Item na blacklist salva nunca reaparece nesta lista.
            if missingBlacklist[key] then
                blocked = blocked + 1
            else
                local src = itemSources(entry)
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
        endScan(0, "found")
        return
    end

    local shown = 0
    for _, def in ipairs(MISSING_GROUPS) do
        local list = groups[def.kind]
        if #list > 0 then
            table.sort(list, function(a, b)
                local ta, va = missingRank(a)
                local tb, vb = missingRank(b)
                if ta ~= tb then return ta < tb end
                if va ~= vb then return va < vb end
                return a.entry.label < b.entry.label
            end)

            addResult({
                label = "-- " .. Lang.MissingTitle .. ": " .. Lang[def.titleKey]
                    .. " (" .. #list .. ") --",
                rawLines = {},
            })
            for i = 1, #list do
                local m = list[i]
                addResult({
                    label = i .. ". " .. m.entry.tag .. " " .. m.entry.label,
                    rawLines = itemSourceLines(m.entry, m.src),
                    -- Parts da loja encontradas pelo Shop.Value.
                    shopTargets = m.src.shopTargets,
                    shopName = m.src.shopName,
                    -- Marca que habilita o botao de blacklist no renderizador.
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
    endScan(total, "found")
end

----------------------------------------------------------------
-- BUSCA (aba Buscar)
----------------------------------------------------------------

local function searchBoss(q)
    if not q or q == "" then
        state.messageKey = "TypeSomething"
        return
    end

    beginScan("found")
    -- Buscar nao corta resultados.
    state.resultCap = math.huge

    local sl = string.lower(q)
    local count, found = 0, {}
    local ue = getToggle("utmm_utmoh")

    -- Indice LEVE de Shop.Value. Nao chama allCatalogItems(),
    -- resolveFragments() nem procura fontes de boss; le apenas os tres catalogos
    -- e os Values Onsale/Shop/Cost. Os nomes alimentam a UNICA varredura global.
    local shopMatches, shopByKey = {}, {}
    -- Todos os Shop.Value conhecidos sao preparados antes da
    -- varredura global. Assim collectBosses() consegue indexar lojas e
    -- BattleInfoGui na MESMA passada pelo Workspace.
    local allShopNames = { exact = {}, lower = {} }
    for _, def in ipairs(ITEM_KINDS) do
        for _, folder in ipairs(safeChildren(catalogFolder(def.kind))) do
            local fname = safeName(folder)
            local label = fname and displayName(folder, def.kind, fname) or nil

            local info = shopInfo(folder)
            local shopName = info and cleanText(info.shop) or nil
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

    -- Nao assume onde a loja mora; apenas informa ao snapshot
    -- global quais nomes vale a pena guardar enquanto ele percorre o mapa.
    workspaceShopWanted = allShopNames

    table.sort(shopMatches, function(a, b)
        if a.exact ~= b.exact then return a.exact end
        return string.lower(a.name) < string.lower(b.name)
    end)

    local function addShopResult(shop)
        local key = "shop:" .. string.lower(shop.name)
        if found[key] then return end
        found[key] = true
        count = count + 1

        local targets = findShopTargets(shop.name)
        local lines = { Lang.ShopItems .. ": " .. tostring(shop.items) }
        if #targets > 0 then
            lines[#lines + 1] = Lang.ShopPoints .. ": " .. tostring(#targets)
        else
            lines[#lines + 1] = Lang.ShopNoTP
        end

        addResult({
            label = count .. ". " .. Lang.TagShop .. " " .. shop.name,
            rawLines = lines,
            shopTargets = targets,
            shopName = shop.name,
        })
    end

    -- Sem retorno antecipado para loja: a Buscar sempre executa o
    -- fluxo completo (bosses -> lojas -> itens), evitando esconder resultados
    -- homonimos e mantendo o comportamento consistente entre kits.

    -- ---------------- 1) bosses ----------------
    -- Comportamento restaurado: mesma busca completa anterior, com Lighting
    -- primario + BattleInfoGui como fallback e ordenacao por requisitos.
    local bossMatches = {}
    for _, b in ipairs(collectBosses()) do
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
                local rn = anyDisplayName(b.battle.reward)
                if rn and string.find(string.lower(rn), sl, 1, true) then m = true end
            end

            local mt = nil
            if ue and b.gui then
                local ml = readText(b.gui, "Material")
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
                    noTP = b.noTP,
                    gui = b.gui,
                }
            end
        end
    end

    table.sort(bossMatches, bossRequirementLess)
    for _, entry in ipairs(bossMatches) do
        count = count + 1
        addResult(entry)
    end

    -- ---------------- 2) lojas ----------------
    -- Mesmo comportamento anterior: lojas que casam com a query aparecem como
    -- resultado proprio; a pasta da loja pode oferecer varios pontos de TP.
    for _, shop in ipairs(shopMatches) do addShopResult(shop) end

    -- ---------------- 3) itens ----------------
    -- allCatalogItems e montado apos bosses/lojas, mantendo a ordem de exibicao
    -- e reaproveitando os caches do mesmo scan.
    local catalogItems = allCatalogItems()
    for _, entry in ipairs(catalogItems) do
        local hay = string.lower((entry.label or "") .. " " .. (entry.folderName or ""))
        if string.find(hay, sl, 1, true) then
            local key = tostring(entry.tag) .. tostring(entry.label)
            if not found[key] then
                found[key] = true
                count = count + 1
                local src = itemSources(entry)
                addResult({
                    label = count .. ". " .. entry.tag .. " " .. entry.label,
                    rawLines = itemSourceLines(entry, src),
                    shopTargets = src.shopTargets,
                    shopName = src.shopName,
                })
            end
        end
    end

    endScan(count, "found")
    if count == 0 then state.messageKey = "NoResults" end
end

----------------------------------------------------------------
-- ANALISE DE EQUIPAMENTO (aba Build)
--
-- O que voce POSSUI (um Value por item, o nome do Value == nome da pasta):
--     game.Players.<voce>.Weapons
--     game.Players.<voce>.Armor
-- Onde estao os stats (catalogo do jogo):
--     game.Lighting.Weapons.<Nome>.Tool.AttackTool.{Damage,DamageModify,DamageIncrease}
--     game.Lighting.Armor.<Nome>.HPBonus
--
-- FORMULA USADA PELO GUIDER
--   Damage       -> dano base.
--   DamageModify -> ganho por level: (LV - 1) * DamageModify.
--
--   dano_estimado(LV) = Damage + (LV - 1) * DamageModify
--
-- DamageIncrease CONTINUA sendo lido e exibido, mas NAO entra no
-- dano confirmado nem no ranking PRINCIPAL. Neste fork do UTMM, aplicar
-- diretamente (1 + DamageIncrease) produzia valores que nao batem com a UI
-- (ex.: Power of Love: 975 calculado vs 195 informado pelo jogo).
-- Em vez de descartar a informacao, existe um SEGUNDO ranking
-- explicitamente hipotetico que aplica (1 + DamageIncrease). Assim o Guider
-- mostra as duas recomendacoes sem afirmar que o multiplicador e dano real.
--
-- O ranking ainda muda conforme o LV por causa de DamageModify. O LV vem do
-- campo LEVEL dos seus stats e respeita LV_CAP.
----------------------------------------------------------------

-- Teto de LV do escalonamento. O kit trava em 100 (ganho maximo
--         99 * Modify). Se o seu servidor subiu esse teto, mude AQUI.
local LV_CAP = 100

-- Equipamento sao dezenas de linhas, nao centenas: cabe folga sobre os
--         50 do scanner de boss.
local BUILD_MAX_RESULTS = 90
local BUILD_TOP_N = 10
local BUILD_SHOW_MODES = { "summary", "top", "all" }

----------------------------------------------------------------
-- CALCULO E FORMATACAO
----------------------------------------------------------------

local function damageAtLevel(s, lv)
    local levels = math.max(0, math.min(lv, LV_CAP) - 1)
    -- DamageIncrease e apenas informativo: nao altera dano/ranking principal.
    return s.damage + levels * s.modify
end

-- Cenario HIPOTETICO. Nao e tratado como dano confirmado do fork:
-- apenas permite uma segunda recomendacao caso DamageIncrease realmente seja
-- aplicado como multiplicador pelo script de ataque deste UTMM.
local function hypotheticalDamageAtLevel(s, lv)
    local confirmed = damageAtLevel(s, lv)
    return confirmed * (1 + (s.increase or 0))
end

-- formatNumber() trunca a parte decimal; equipamento inicial tem
--         numeros pequenos, entao abaixo de 1K mostra o valor real.
local function fmtBuild(n)
    if n >= 1e3 then return formatNumber(n) end
    if n == math.floor(n) then return tostring(math.floor(n)) end
    local s = string.format("%.2f", n)
    s = string.gsub(s, "0+$", "")
    s = string.gsub(s, "%.$", "")
    return s
end

-- LV do calculo = campo LEVEL dos stats, limitado por LV_CAP.
--         Vazio ou 0 assume o teto (comparar no maximo e o caso mais util).
local function buildLevel()
    local lv = parseNumberWithSuffix(getInput("utmm_level"))
    if lv <= 0 then return LV_CAP end
    if lv > LV_CAP then return LV_CAP end
    return lv
end

-- Linha opcional de loja: util para saber o que da para recomprar depois
--        de um reset (o Value Permanent nao protege tudo).
local function shopLine(shop)
    if not shop then return nil end
    local t = Lang.Shop .. ": " .. (shop.shop or "?")
    if shop.cost then t = t .. "  |  " .. formatNumber(shop.cost) .. " Gold" end
    return t
end

local function weaponDetailLines(w)
    if w.missing then return { Lang.BuildNoData } end
    local lines = {
        Lang.BuildDmg .. ": " .. fmtBuild(w.total),
        Lang.BuildBase .. " " .. fmtBuild(w.damage)
            .. " | +" .. fmtBuild(w.modify) .. Lang.BuildPerLv
            .. " | " .. Lang.BuildBoost .. " " .. fmtBuild(w.increase * 100) .. "%",
    }
    local pl = permanenceLine(w.permanent, w.truePermanent, nil, true)
    if pl then lines[#lines + 1] = pl end
    local sl = shopLine(w.shop)
    if sl then lines[#lines + 1] = sl end
    return lines
end

-- Detalhes exclusivos da segunda recomendacao. O valor aparece
-- explicitamente como hipotetico para nao ser confundido com o dano real.
local function weaponHypDetailLines(w)
    if w.missing then return { Lang.BuildNoData } end
    local lines = {
        Lang.BuildDmg .. ": " .. fmtBuild(w.total),
        Lang.BuildBoost .. ": " .. fmtBuild((w.increase or 0) * 100) .. "%",
        Lang.BuildHypDamage .. ": " .. fmtBuild(w.hypTotal or w.total),
    }
    local pl = permanenceLine(w.permanent, w.truePermanent, nil, true)
    if pl then lines[#lines + 1] = pl end
    local sl = shopLine(w.shop)
    if sl then lines[#lines + 1] = sl end
    return lines
end

local function armorDetailLines(a)
    if a.missing then return { Lang.BuildNoData } end
    local lines = { "+" .. fmtBuild(a.hp) .. " " .. Lang.BuildHP }
    local pl = permanenceLine(a.permanent, a.truePermanent, nil, true)
    if pl then lines[#lines + 1] = pl end
    local sl = shopLine(a.shop)
    if sl then lines[#lines + 1] = sl end
    return lines
end

----------------------------------------------------------------
-- SCAN
----------------------------------------------------------------

local function runBuildScan()
    beginScan("found")
    state.resultCap = BUILD_MAX_RESULTS
    state.buildWeapon = nil
    state.buildWeaponBoost = nil
    state.buildArmor  = nil

    local lv = buildLevel()
    local show = BUILD_SHOW_MODES[getCombo("utmm_build_show", 1) + 1] or "top"

    local weaponNames, hasWeapons = ownedNames("Weapons")
    local armorNames,  hasArmors  = ownedNames("Armor")

    if not hasWeapons and not hasArmors then
        state.status = Lang.BuildNoPlayer
        endScan(0, "found")
        return
    end

    -- ---------------- armas ----------------
    local weapons = {}
    for _, nm in ipairs(weaponNames) do
        local s = weaponStats(nm)
        if s then
            weapons[#weapons + 1] = {
                label = s.label, damage = s.damage, modify = s.modify,
                increase = s.increase, total = damageAtLevel(s, lv),
                hypTotal = hypotheticalDamageAtLevel(s, lv),
                shop = s.shop,
                permanent = s.permanent, truePermanent = s.truePermanent,
            }
        else
            -- Item possuido que nao existe mais no catalogo (removido/renomeado).
            weapons[#weapons + 1] = { label = nm, missing = true, total = -1, hypTotal = -1 }
        end
    end
    table.sort(weapons, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.label < b.label
    end)

    -- ---------------- armaduras ----------------
    local armors = {}
    for _, nm in ipairs(armorNames) do
        local s = armorStats(nm)
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

    -- ---------------- melhores ----------------
    local bestWeapon, bestWeaponBoost, bestArmor
    for _, w in ipairs(weapons) do
        if not w.missing then
            bestWeapon = w
            break
        end
    end

    -- Segundo ranking independente: maior dano HIPOTETICO depois
    -- de aplicar (1 + DamageIncrease). Nao altera a ordem/lista principal.
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

    -- Resumo curto para o painel esquerdo (sobrevive a outros scans).
    state.buildWeapon = bestWeapon
        and (bestWeapon.label .. " (" .. fmtBuild(bestWeapon.total) .. " " .. Lang.BuildAtLv .. " " .. lv .. ")")
        or Lang.BuildEmpty

    if bestWeaponBoost then
        if bestWeapon and bestWeaponBoost.label == bestWeapon.label then
            state.buildWeaponBoost = Lang.BuildSameBoostWinner
                .. " (" .. fmtBuild(bestWeaponBoost.hypTotal) .. " " .. Lang.BuildHypDamage .. ")"
        else
            state.buildWeaponBoost = bestWeaponBoost.label
                .. " (" .. fmtBuild(bestWeaponBoost.hypTotal) .. " " .. Lang.BuildHypDamage .. ")"
        end
    else
        state.buildWeaponBoost = Lang.BuildEmpty
    end

    state.buildArmor = bestArmor
        and (bestArmor.label .. " (+" .. fmtBuild(bestArmor.hp) .. " " .. Lang.BuildHP .. ")")
        or Lang.BuildEmpty

    -- ---------------- linhas da lista ----------------
    addResult({
        label = "★ " .. Lang.BestWeaponConfirmed .. " " .. (bestWeapon and bestWeapon.label or Lang.BuildEmpty),
        rawLines = bestWeapon and weaponDetailLines(bestWeapon) or { "-" },
        shopTargets = bestWeapon and shopTargets(bestWeapon.shop) or {},
        shopName = bestWeapon and bestWeapon.shop and bestWeapon.shop.shop or nil,
    })

    -- Se a mesma arma vence os dois rankings, evita repetir um
    -- bloco inteiro e apenas registra que ela tambem vence no cenario hipotetico.
    if bestWeaponBoost and bestWeapon and bestWeaponBoost.label == bestWeapon.label then
        addResult({
            label = "★ " .. Lang.BestWeaponBoosted .. " " .. bestWeaponBoost.label,
            rawLines = {
                Lang.BuildSameBoostWinner,
                Lang.BuildHypDamage .. ": " .. fmtBuild(bestWeaponBoost.hypTotal),
            },
            shopTargets = {},
        })
    else
        addResult({
            label = "★ " .. Lang.BestWeaponBoosted .. " "
                .. (bestWeaponBoost and bestWeaponBoost.label or Lang.BuildEmpty),
            rawLines = bestWeaponBoost and weaponHypDetailLines(bestWeaponBoost) or { "-" },
            shopTargets = bestWeaponBoost and shopTargets(bestWeaponBoost.shop) or {},
            shopName = bestWeaponBoost and bestWeaponBoost.shop and bestWeaponBoost.shop.shop or nil,
        })
    end

    addResult({
        label = "★ " .. Lang.BestArmor .. " " .. (bestArmor and bestArmor.label or Lang.BuildEmpty),
        rawLines = bestArmor and armorDetailLines(bestArmor) or { "-" },
        shopTargets = bestArmor and shopTargets(bestArmor.shop) or {},
        shopName = bestArmor and bestArmor.shop and bestArmor.shop.shop or nil,
    })

    -- No modo resumo nada foi "cortado": o usuario pediu so os dois melhores.
    state.overflow = 0

    if show ~= "summary" then
        local limit = (show == "all") and math.huge or BUILD_TOP_N
        state.overflow = math.max(0, #weapons - math.min(#weapons, limit))
            + math.max(0, #armors - math.min(#armors, limit))

        addResult({
            label = "-- " .. Lang.BuildWeapons .. " (" .. #weapons .. ") | "
                .. Lang.BuildAtLv .. " " .. lv .. " --",
            rawLines = {},
        })
        for i = 1, #weapons do
            if i > limit then break end
            local w = weapons[i]
            addResult({
                label = i .. ". " .. w.label, rawLines = weaponDetailLines(w),
                shopTargets = shopTargets(w.shop),
                shopName = w.shop and w.shop.shop or nil,
            })
        end

        addResult({
            label = "-- " .. Lang.BuildArmors .. " (" .. #armors .. ") --",
            rawLines = {},
        })
        for i = 1, #armors do
            if i > limit then break end
            local a = armors[i]
            addResult({
                label = i .. ". " .. a.label, rawLines = armorDetailLines(a),
                shopTargets = shopTargets(a.shop),
                shopName = a.shop and a.shop.shop or nil,
            })
        end
    end

    state.status = (#weapons + #armors) .. " " .. Lang.BuildOwned
    endScan(#weapons + #armors, "found")
end

----------------------------------------------------------------
-- BUILD DE 8 COMIDAS + TIERLIST
----------------------------------------------------------------

local FOOD_SLOTS = 8

-- Forward declarations: os callbacks sao definidos depois deste modulo.
local requestJob
local runFoodBest8, runFoodTierList

local function foodAll(includeBlacklisted)
    local out = {}
    local root = catalogFolder("Food")
    for _, folder in pairs(safeChildren(root)) do
        local fname = safeName(folder)
        if fname and fname ~= "" and (includeBlacklisted or not foodBlacklist[fname]) then
            local f = foodStats(fname, folder)
            if f then out[#out + 1] = f end
        end
    end
    return out
end

local function foodSaleText(f)
    -- Para o usuario, so Onsale=true conta como "a venda".
    -- false ou leitura ausente/ilegivel sao tratados como indisponivel.
    if f.onsale == true then return Lang.FoodYes end
    return Lang.FoodNo
end

local function foodMaxCopies(f)
    if type(f.max) == "number" then
        local m = math.floor(f.max)
        if m < 0 then return 0 end
        return m
    end
    -- Sem Max legivel, assume 1 em vez de inventar estoque ilimitado.
    return 1
end

local function foodDetailLines(f, copies)
    local lines = {}
    if f.heal == nil then
        lines[#lines + 1] = Lang.FoodHeal .. ": ?"
    else
        local healLine = Lang.FoodHeal .. ": " .. fmtBuild(f.heal)
        if copies and copies > 1 then
            healLine = healLine .. " " .. Lang.FoodEach
                .. " | " .. Lang.FoodTotalHeal .. ": " .. fmtBuild(f.heal * copies)
        end
        lines[#lines + 1] = healLine
    end

    if f.cost ~= nil then
        local costLine = Lang.FoodCost .. ": " .. formatNumber(f.cost) .. " Gold"
        if copies and copies > 1 then
            costLine = costLine .. " " .. Lang.FoodEach
                .. " | " .. Lang.FoodTotalCost .. ": " .. formatNumber(f.cost * copies) .. " Gold"
        end
        lines[#lines + 1] = costLine
    else
        lines[#lines + 1] = Lang.FoodCost .. ": " .. Lang.FoodUnknownCost
    end

    lines[#lines + 1] = Lang.FoodMax .. ": " .. tostring(f.max ~= nil and math.floor(f.max) or "?")
    if f.onsale == true then
        lines[#lines + 1] = Lang.FoodOnSale .. ": " .. foodSaleText(f)
    else
        -- Aviso explicito na tierlist para comida indisponivel.
        lines[#lines + 1] = Lang.FoodNotForSale
    end
    local pl = permanenceLine(f.permanent, f.truePermanent, nil, true)
    if pl then lines[#lines + 1] = pl end
    if f.shopName and f.shopName ~= "" then
        lines[#lines + 1] = Lang.Shop .. ": " .. f.shopName
    end
    return lines
end

local function foodTier(heal, bestHeal)
    if heal == nil then return "?" end
    if heal <= 0 or bestHeal <= 0 then return "F" end
    local r = heal / bestHeal
    if r >= 0.90 then return "S" end
    if r >= 0.75 then return "A" end
    if r >= 0.50 then return "B" end
    if r >= 0.25 then return "C" end
    return "D"
end

local function rerunLastFoodScan()
    if state.lastFoodScan == "best8" then
        requestJob(function() runFoodBest8() end)
        return true
    elseif state.lastFoodScan == "tier" then
        requestJob(function() runFoodTierList() end)
        return true
    end
    state.status = ""
    return false
end

runFoodBest8 = function()
    beginScan("best")
    state.resultCap = math.huge
    state.lastFoodScan = "best8"

    local foods = foodAll(false)
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
        -- A build de 8 representa uma compra possivel AGORA.
        -- Portanto so considera comida com Onsale explicitamente true.
        if f.onsale == true and f.heal and f.heal > 0 then
            local cap = foodMaxCopies(f)
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
        endScan(0, "best")
        return
    end

    state.buildFood = picks[1].food.label .. " (" .. fmtBuild(picks[1].food.heal) .. " " .. Lang.FoodHeal .. ")"

    local summary = {
        Lang.FoodTotalHeal .. ": " .. fmtBuild(totalHeal),
        Lang.FoodTotalCost .. ": " .. formatNumber(totalCost) .. " Gold"
            .. (unknownCostSlots > 0 and (" (+" .. unknownCostSlots .. " " .. Lang.FoodUnknownCost .. ")") or ""),
        tostring(FOOD_SLOTS - remaining) .. "/" .. FOOD_SLOTS .. " " .. Lang.FoodSlots,
    }
    if remaining > 0 then summary[#summary + 1] = Lang.FoodBuildIncomplete end

    addResult({ label = "★ " .. Lang.FoodBuildTitle, rawLines = summary })

    local slot = 1
    for _, pick in ipairs(picks) do
        local f, copies = pick.food, pick.copies
        local label
        if copies == 1 then
            label = slot .. ". " .. f.label
        else
            label = slot .. "-" .. (slot + copies - 1) .. ". " .. f.label .. " x" .. copies
        end
        addResult({
            label = label,
            rawLines = foodDetailLines(f, copies),
            -- TP usa Shop.Value diretamente; Onsale ja foi
            -- validado para a build, mas a resolucao de mapa e independente.
            shopTargets = shopTargets(f.shopTarget),
            shopName = f.shopName,
            foodBlacklistKey = f.folderName,
        })
        slot = slot + copies
    end

    state.overflow = 0
    state.status = tostring(FOOD_SLOTS - remaining) .. "/" .. FOOD_SLOTS .. " " .. Lang.FoodSlots
    endScan(#picks, "best")
end

runFoodTierList = function()
    beginScan("best")
    state.resultCap = math.huge
    state.lastFoodScan = "tier"

    local foods = foodAll(false)
    local bestHeal = 0
    for _, f in ipairs(foods) do
        if f.heal and f.heal > bestHeal then bestHeal = f.heal end
    end

    local tierOrder = { S = 1, A = 2, B = 3, C = 4, D = 5, F = 6, ["?"] = 7 }
    for _, f in ipairs(foods) do f.tier = foodTier(f.heal, bestHeal) end
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
        endScan(0, "best")
        return
    end

    state.buildFood = foods[1].label .. " (" .. fmtBuild(foods[1].heal or 0) .. " " .. Lang.FoodHeal .. ")"
    addResult({ label = "★ " .. Lang.FoodTierTitle, rawLines = { Lang.FoodTierRule } })

    for i, f in ipairs(foods) do
        addResult({
            label = i .. ". [" .. f.tier .. "] " .. f.label,
            rawLines = foodDetailLines(f, nil),
            -- Tierlist oferece TP sempre que houver Shop.Value,
            -- mesmo se Onsale=false, para o usuario poder visitar a loja.
            shopTargets = shopTargets(f.shopTarget),
            shopName = f.shopName,
            foodBlacklistKey = f.folderName,
        })
    end

    state.overflow = 0
    state.status = #foods .. " " .. Lang.FoodSection
    endScan(#foods, "best")
end

----------------------------------------------------------------
-- UI DRAWING INDEPENDENTE
----------------------------------------------------------------

(function()
loadConfig()

local RunService = getService("RunService")
local UserInputService = getService("UserInputService")
local Mouse = LocalPlayer and LocalPlayer:GetMouse() or nil

if not RunService or not Mouse then
    assert(false, "[UTMM Guider] RunService/Mouse indisponivel no Matcha.")
end

local Gui = {
    running = true,
    visible = true,
    selectedPage = 1,
    dirty = true,
    lastStamp = -1,
    lastMouseX = -1,
    lastMouseY = -1,
    lastMouseDown = false,
    hovered = nil,
    hitboxes = {},
    pageData = {},
    pageBusy = {},
    resultScroll = {},
    resultScrollMax = {},
    activeInput = nil,
    caret = 0,
    keyPrev = {},
    draggingWindow = false,
    draggingResize = false,
    draggingResultScroll = false,
    draggingOverlayScroll = false,
    dragDX = 0,
    dragDY = 0,
    scrollGrab = 0,
    overlay = nil,
    overlayScroll = 0,
    overlayScrollMax = 0,
    logoData = nil,
    logoLoading = false,
    logoFailed = false,
    window = {
        x = 180, y = 90,
        width = 820, height = 600,
        minWidth = 650, minHeight = 470,
        maxWidth = 1040, maxHeight = 760,
        sidebar = 178, header = 44,
    },
    pool = {},
    poolCursor = {},
}

local Theme = {
    bg = Color3.fromRGB(11, 12, 15),
    shell = Color3.fromRGB(17, 18, 22),
    sidebar = Color3.fromRGB(14, 15, 18),
    panel = Color3.fromRGB(22, 23, 28),
    panel2 = Color3.fromRGB(27, 28, 34),
    hover = Color3.fromRGB(33, 34, 41),
    border = Color3.fromRGB(49, 51, 61),
    borderSoft = Color3.fromRGB(37, 39, 47),
    accent = Color3.fromRGB(255, 52, 73),
    accentSoft = Color3.fromRGB(151, 31, 46),
    text = Color3.fromRGB(244, 245, 247),
    textDim = Color3.fromRGB(164, 167, 176),
    textMuted = Color3.fromRGB(111, 115, 126),
    success = Color3.fromRGB(102, 214, 146),
    warning = Color3.fromRGB(244, 196, 88),
    danger = Color3.fromRGB(255, 94, 110),
}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function inRect(mx, my, x, y, w, h)
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

local function safeSet(obj, key, value)
    pcall(function() obj[key] = value end)
end

function Gui:Acquire(kind)
    local list = self.pool[kind]
    if not list then
        list = {}
        self.pool[kind] = list
    end
    local index = (self.poolCursor[kind] or 0) + 1
    self.poolCursor[kind] = index
    local obj = list[index]
    if not obj then
        local ok, created = pcall(function() return Drawing.new(kind) end)
        if not ok or not created then return nil end
        obj = created
        list[index] = obj
    end
    safeSet(obj, "Visible", true)
    safeSet(obj, "Transparency", 1)
    return obj
end

function Gui:BeginFrame()
    self.poolCursor = {}
    self.hitboxes = {}
    self.hovered = nil
end

function Gui:EndFrame()
    for kind, list in pairs(self.pool) do
        local used = self.poolCursor[kind] or 0
        for i = used + 1, #list do
            safeSet(list[i], "Visible", false)
        end
    end
end

function Gui:Box(x, y, w, h, color, filled, z, corner)
    if w <= 0 or h <= 0 then return nil end
    local o = self:Acquire("Square")
    if not o then return nil end
    safeSet(o, "Position", Vector2.new(math.floor(x), math.floor(y)))
    safeSet(o, "Size", Vector2.new(math.floor(w), math.floor(h)))
    safeSet(o, "Color", color)
    safeSet(o, "Filled", filled ~= false)
    safeSet(o, "Thickness", 1)
    safeSet(o, "ZIndex", z or 1)
    if corner then safeSet(o, "Corner", corner) end
    return o
end

function Gui:Line(x1, y1, x2, y2, color, thickness, z)
    local o = self:Acquire("Line")
    if not o then return nil end
    safeSet(o, "From", Vector2.new(math.floor(x1), math.floor(y1)))
    safeSet(o, "To", Vector2.new(math.floor(x2), math.floor(y2)))
    safeSet(o, "Color", color)
    safeSet(o, "Thickness", thickness or 1)
    safeSet(o, "ZIndex", z or 2)
    return o
end

function Gui:Circle(x, y, radius, color, filled, thickness, z)
    local o = self:Acquire("Circle")
    if not o then return nil end
    safeSet(o, "Position", Vector2.new(math.floor(x), math.floor(y)))
    safeSet(o, "Radius", radius)
    safeSet(o, "Color", color)
    safeSet(o, "Filled", filled == true)
    safeSet(o, "Thickness", thickness or 1)
    safeSet(o, "NumSides", 40)
    safeSet(o, "ZIndex", z or 3)
    return o
end

function Gui:Triangle(ax, ay, bx, by, cx, cy, color, filled, z)
    local o = self:Acquire("Triangle")
    if not o then return nil end
    safeSet(o, "PointA", Vector2.new(ax, ay))
    safeSet(o, "PointB", Vector2.new(bx, by))
    safeSet(o, "PointC", Vector2.new(cx, cy))
    safeSet(o, "Color", color)
    safeSet(o, "Filled", filled ~= false)
    safeSet(o, "ZIndex", z or 3)
    return o
end

function Gui:Text(text, x, y, color, size, center, bold, z)
    local o = self:Acquire("Text")
    if not o then return nil end
    safeSet(o, "Text", tostring(text or ""))
    safeSet(o, "Position", Vector2.new(math.floor(x), math.floor(y)))
    safeSet(o, "Color", color or Theme.text)
    safeSet(o, "Center", center == true)
    safeSet(o, "Outline", false)
    local font = Drawing.Fonts and (bold and Drawing.Fonts.SystemBold or Drawing.Fonts.System)
    if font then safeSet(o, "Font", font) end
    local okSize = pcall(function() o.FontSize = size or 13 end)
    if not okSize then safeSet(o, "Size", size or 13) end
    safeSet(o, "ZIndex", z or 4)
    return o
end

function Gui:Image(data, x, y, w, h, z)
    if type(data) ~= "string" or data == "" then return nil end
    local o = self:Acquire("Image")
    if not o then return nil end
    safeSet(o, "Position", Vector2.new(math.floor(x), math.floor(y)))
    safeSet(o, "Size", Vector2.new(math.floor(w), math.floor(h)))
    safeSet(o, "Data", data)
    safeSet(o, "Rounding", 8)
    safeSet(o, "ZIndex", z or 5)
    return o
end

function Gui:Register(id, x, y, w, h, callback, priority)
    if w <= 0 or h <= 0 then return end
    self.hitboxes[#self.hitboxes + 1] = {
        id = id, x = x, y = y, w = w, h = h,
        callback = callback, priority = priority or 0,
    }
end

function Gui:Hit(mx, my)
    local best, bestP, bestIndex = nil, -math.huge, -1
    for i = 1, #self.hitboxes do
        local h = self.hitboxes[i]
        if inRect(mx, my, h.x, h.y, h.w, h.h) then
            if h.priority > bestP or (h.priority == bestP and i > bestIndex) then
                best, bestP, bestIndex = h, h.priority, i
            end
        end
    end
    return best
end

function Gui:Button(id, label, x, y, w, h, callback, accent, z)
    local hovered = self.hovered == id
    local fill = accent and (hovered and Theme.accent or Theme.accentSoft)
        or (hovered and Theme.hover or Theme.panel2)
    self:Box(x, y, w, h, fill, true, z or 3, 6)
    self:Box(x, y, w, h, accent and Theme.accent or Theme.border, false, (z or 3) + 1, 6)
    self:Text(label, x + w * 0.5, y + math.floor((h - 13) * 0.5), Theme.text, 12, true, true, (z or 3) + 2)
    self:Register(id, x, y, w, h, callback, (z or 3) + 2)
end

function Gui:Toggle(id, label, x, y, w)
    local value = getToggle(id)
    local boxX = x + w - 34
    self:Text(label, x, y + 3, Theme.textDim, 12, false, false, 5)
    self:Box(boxX, y, 34, 20, value and Theme.accentSoft or Theme.panel2, true, 5, 10)
    self:Box(boxX, y, 34, 20, value and Theme.accent or Theme.border, false, 6, 10)
    self:Circle(boxX + (value and 24 or 10), y + 10, 6, value and Theme.text or Theme.textDim, true, 1, 7)
    self:Register("toggle:" .. id, x, y - 2, w, 24, function()
        uiCache[id] = not getToggle(id)
        saveConfig()
        self.dirty = true
    end, 7)
end

function Gui:Cycle(id, label, options, x, y, w)
    local index = getCombo(id, 0)
    if index < 0 or index >= #options then index = 0 end
    self:Text(label, x, y, Theme.textMuted, 11, false, false, 5)
    local by = y + 16
    self:Box(x, by, w, 27, Theme.panel2, true, 5, 6)
    self:Box(x, by, w, 27, Theme.border, false, 6, 6)
    self:Text(options[index + 1] or "-", x + 9, by + 6, Theme.text, 12, false, false, 7)
    self:Text("›", x + w - 13, by + 5, Theme.textDim, 16, true, true, 7)
    self:Register("cycle:" .. id, x, by, w, 27, function()
        uiCache[id] = (index + 1) % #options
        saveConfig()
        self.dirty = true
    end, 8)
    return by + 27
end

local VK = {
    BACK = 0x08, RETURN = 0x0D, SHIFT = 0x10, ESC = 0x1B, DELETE = 0x2E,
    LEFT = 0x25, UP = 0x26, RIGHT = 0x27, DOWN = 0x28, HOME = 0x24, ENDKEY = 0x23,
    PGUP = 0x21, PGDN = 0x22, SPACE = 0x20,
}
for i = 0, 9 do VK[tostring(i)] = 0x30 + i end
for i = 0, 25 do VK[string.char(65 + i)] = 0x41 + i end

local VKCHARS = {
    [0x20] = {" ", " "},
    [0x30] = {"0", ")"}, [0x31] = {"1", "!"}, [0x32] = {"2", "@"}, [0x33] = {"3", "#"},
    [0x34] = {"4", "$"}, [0x35] = {"5", "%"}, [0x36] = {"6", "^"}, [0x37] = {"7", "&"},
    [0x38] = {"8", "*"}, [0x39] = {"9", "("},
    [0xBD] = {"-", "_"}, [0xBB] = {"=", "+"}, [0xBC] = {",", "<"}, [0xBE] = {".", ">"},
    [0xBA] = {";", ":"}, [0xBF] = {"/", "?"}, [0xDB] = {"[", "{"}, [0xDD] = {"]", "}"},
    [0xDE] = {"'", '"'},
}
for i = 0, 25 do
    local lower = string.char(97 + i)
    local upper = string.char(65 + i)
    VKCHARS[0x41 + i] = {lower, upper}
end

local KEY_POLL = {VK.ESC, VK.RETURN, VK.BACK, VK.DELETE, VK.LEFT, VK.RIGHT, VK.HOME, VK.ENDKEY}
for code = 0x30, 0x39 do KEY_POLL[#KEY_POLL + 1] = code end
for code = 0x41, 0x5A do KEY_POLL[#KEY_POLL + 1] = code end
for _, code in ipairs({0x20, 0xBD, 0xBB, 0xBC, 0xBE, 0xBA, 0xBF, 0xDB, 0xDD, 0xDE}) do
    KEY_POLL[#KEY_POLL + 1] = code
end

function Gui:FocusInput(id)
    self.activeInput = id
    local value = tostring(widgetValue(id) or "")
    self.caret = #value
    self.keyPrev = {}
    self.dirty = true
end

function Gui:BlurInput(save)
    if self.activeInput and save ~= false and self.activeInput ~= "utmm_search" then
        saveConfig()
    end
    self.activeInput = nil
    self.keyPrev = {}
    self.dirty = true
end

function Gui:SubmitSearch()
    local q = tostring(getInput("utmm_search") or "")
    q = string.match(q, "^%s*(.-)%s*$") or ""
    if q == "" then
        state.messageKey = "TypeSomething"
        self.dirty = true
        return
    end
    self:QueueJob(2, function() searchBoss(q) end, true)
end

function Gui:PollTextInput()
    local id = self.activeInput
    if not id then return end
    local value = tostring(widgetValue(id) or "")
    local shift = type(iskeypressed) == "function" and iskeypressed(VK.SHIFT) or false

    for _, code in ipairs(KEY_POLL) do
        local down = type(iskeypressed) == "function" and iskeypressed(code) or false
        local prev = self.keyPrev[code] == true
        if down and not prev then
            if code == VK.ESC then
                self:BlurInput(true)
                return
            elseif code == VK.RETURN then
                if id == "utmm_search" then self:SubmitSearch() end
                self:BlurInput(true)
                return
            elseif code == VK.LEFT then
                self.caret = math.max(0, self.caret - 1)
            elseif code == VK.RIGHT then
                self.caret = math.min(#value, self.caret + 1)
            elseif code == VK.HOME then
                self.caret = 0
            elseif code == VK.ENDKEY then
                self.caret = #value
            elseif code == VK.BACK then
                if self.caret > 0 then
                    value = string.sub(value, 1, self.caret - 1) .. string.sub(value, self.caret + 1)
                    self.caret = self.caret - 1
                    uiCache[id] = value
                end
            elseif code == VK.DELETE then
                if self.caret < #value then
                    value = string.sub(value, 1, self.caret) .. string.sub(value, self.caret + 2)
                    uiCache[id] = value
                end
            else
                local pair = VKCHARS[code]
                if pair then
                    local char = pair[shift and 2 or 1]
                    value = string.sub(value, 1, self.caret) .. char .. string.sub(value, self.caret + 1)
                    self.caret = self.caret + #char
                    uiCache[id] = value
                end
            end
            self.dirty = true
        end
        self.keyPrev[code] = down
    end
end

function Gui:Input(id, label, placeholder, x, y, w)
    local value = tostring(widgetValue(id) or "")
    local focused = self.activeInput == id
    self:Text(label, x, y, Theme.textMuted, 11, false, false, 5)
    local by = y + 16
    self:Box(x, by, w, 29, Theme.panel2, true, 5, 6)
    self:Box(x, by, w, 29, focused and Theme.accent or Theme.border, false, 6, 6)

    local shown = value
    if shown == "" and not focused then shown = placeholder or "" end
    local maxChars = math.max(6, math.floor((w - 18) / 7))
    local startIndex = 1
    if #shown > maxChars then startIndex = #shown - maxChars + 1 end
    local visible = string.sub(shown, startIndex)
    self:Text(visible, x + 8, by + 7, (value == "" and not focused) and Theme.textMuted or Theme.text, 12, false, false, 7)

    if focused and math.floor(tick() * 2) % 2 == 0 then
        local caretVisible = self.caret - (startIndex - 1)
        caretVisible = clamp(caretVisible, 0, #visible)
        local cx = x + 8 + caretVisible * 7
        self:Line(cx, by + 6, cx, by + 22, Theme.accent, 1, 8)
    end

    self:Register("input:" .. id, x, by, w, 29, function() self:FocusInput(id) end, 9)
    return by + 29
end

function Gui:DrawIcon(kind, x, y, color, z)
    local c = color or Theme.textDim
    z = z or 6
    if kind == "scanner" then
        self:Circle(x + 9, y + 9, 7, c, false, 1, z)
        self:Line(x + 9, y, x + 9, y + 5, c, 1, z)
        self:Line(x + 9, y + 13, x + 9, y + 18, c, 1, z)
        self:Line(x, y + 9, x + 5, y + 9, c, 1, z)
        self:Line(x + 13, y + 9, x + 18, y + 9, c, 1, z)
    elseif kind == "search" then
        self:Circle(x + 7, y + 7, 6, c, false, 2, z)
        self:Line(x + 11, y + 11, x + 17, y + 17, c, 2, z)
    elseif kind == "progress" then
        self:Line(x + 2, y + 15, x + 7, y + 10, c, 2, z)
        self:Line(x + 7, y + 10, x + 11, y + 12, c, 2, z)
        self:Line(x + 11, y + 12, x + 17, y + 4, c, 2, z)
        self:Triangle(x + 14, y + 4, x + 18, y + 3, x + 17, y + 7, c, true, z)
    elseif kind == "farms" then
        self:Line(x + 11, y, x + 5, y + 10, c, 2, z)
        self:Line(x + 5, y + 10, x + 10, y + 10, c, 2, z)
        self:Line(x + 10, y + 10, x + 6, y + 18, c, 2, z)
        self:Line(x + 6, y + 18, x + 16, y + 7, c, 2, z)
        self:Line(x + 16, y + 7, x + 11, y + 7, c, 2, z)
    elseif kind == "build" then
        self:Line(x + 4, y + 2, x + 14, y + 12, c, 2, z)
        self:Line(x + 14, y + 2, x + 4, y + 12, c, 2, z)
        self:Box(x + 7, y + 11, 4, 7, c, true, z, 1)
    elseif kind == "top" then
        self:Line(x + 2, y + 7, x + 5, y + 15, c, 2, z)
        self:Line(x + 5, y + 15, x + 15, y + 15, c, 2, z)
        self:Line(x + 15, y + 15, x + 18, y + 7, c, 2, z)
        self:Line(x + 2, y + 7, x + 7, y + 11, c, 2, z)
        self:Line(x + 7, y + 11, x + 10, y + 5, c, 2, z)
        self:Line(x + 10, y + 5, x + 13, y + 11, c, 2, z)
        self:Line(x + 13, y + 11, x + 18, y + 7, c, 2, z)
    elseif kind == "close" then
        self:Line(x + 3, y + 3, x + 15, y + 15, c, 2, z)
        self:Line(x + 15, y + 3, x + 3, y + 15, c, 2, z)
    elseif kind == "searchbutton" then
        self:Circle(x + 7, y + 7, 5, c, false, 2, z)
        self:Line(x + 11, y + 11, x + 16, y + 16, c, 2, z)
    elseif kind == "teleport" then
        self:Line(x + 2, y + 14, x + 15, y + 2, c, 2, z)
        self:Line(x + 9, y + 2, x + 15, y + 2, c, 2, z)
        self:Line(x + 15, y + 2, x + 15, y + 8, c, 2, z)
    elseif kind == "blacklist" then
        self:Line(x + 3, y + 3, x + 15, y + 15, c, 2, z)
        self:Line(x + 15, y + 3, x + 3, y + 15, c, 2, z)
    elseif kind == "shop" then
        self:Box(x + 3, y + 8, 12, 9, c, false, z, 1)
        self:Line(x + 2, y + 8, x + 5, y + 3, c, 2, z)
        self:Line(x + 5, y + 3, x + 13, y + 3, c, 2, z)
        self:Line(x + 13, y + 3, x + 16, y + 8, c, 2, z)
    end
end

function Gui:DrawFallbackLogo(x, y, size)
    local cx, cy = x + size * 0.5, y + size * 0.5
    self:Circle(cx, cy, size * 0.38, Theme.textDim, false, 2, 5)
    self:Circle(cx, cy, size * 0.29, Theme.accent, false, 2, 5)
    self:Line(cx, y + 3, cx, y + size - 3, Theme.text, 1, 6)
    self:Line(x + 3, cy, x + size - 3, cy, Theme.text, 1, 6)
    self:Box(cx - 4, cy - 3, 8, 7, Theme.accent, true, 7, 1)
end

function Gui:LoadLogo()
    if self.logoLoading or self.logoData or self.logoFailed then return end
    self.logoLoading = true
    task.spawn(function()
        local url = "https://raw.githubusercontent.com/MyStupidHubs/UTMM-Guider/main/assets/logo.png"
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if ok and type(body) == "string" and #body > 100 then
            self.logoData = body
        else
            self.logoFailed = true
        end
        self.logoLoading = false
        self.dirty = true
    end)
end

function Gui:CapturePage(page)
    self.pageData[page] = {
        results = state.results,
        count = state.count,
        countKind = state.countKind,
        scanned = state.scanned,
        warning = state.progressWarning,
        status = state.status,
        overflow = state.overflow,
        stamp = state.stamp,
    }
    self.pageBusy[page] = false
    self.dirty = true
end

local pendingJobPage = nil

requestJob = function(fn)
    if type(fn) ~= "function" then return end
    state.busy = true
    state.messageKey = nil
    pendingJob = fn
    pendingJobPage = Gui.selectedPage
    Gui.pageBusy[pendingJobPage] = true
    Gui.dirty = true
end

function Gui:QueueJob(page, fn, resetScroll)
    self.selectedPage = page or self.selectedPage
    if resetScroll then self.resultScroll[self.selectedPage] = 0 end
    requestJob(fn)
end

function Gui:PageSnapshot(page)
    return self.pageData[page] or {
        results = {}, count = 0, countKind = "found", scanned = false,
        warning = nil, status = "", overflow = nil, stamp = 0,
    }
end

function Gui:StatusFor(page, snap)
    if self.pageBusy[page] then return Lang.Searching end
    if not snap.scanned then return "0 " .. Lang.Found end
    return tostring(snap.count or 0) .. " " .. (((snap.countKind or "found") == "best") and Lang.Best or Lang.Found)
end

function Gui:PageName(page)
    local names = {Lang.Scanner, Lang.SearchBoss, Lang.Progress, Lang.Farms, Lang.Build, Lang.Top5}
    return names[page] or "UTMM"
end

function Gui:PageIcon(page)
    return ({"scanner", "search", "progress", "farms", "build", "top"})[page] or "scanner"
end

function Gui:DrawSidebar(wx, wy, ww, wh)
    local sw = self.window.sidebar
    self:Box(wx, wy, sw, wh, Theme.sidebar, true, 2, 12)
    self:Line(wx + sw, wy + 1, wx + sw, wy + wh - 1, Theme.borderSoft, 1, 3)

    self:Box(wx + 14, wy + 13, 42, 42, Theme.panel, true, 3, 9)
    if self.logoData then
        self:Image(self.logoData, wx + 16, wy + 15, 38, 38, 5)
    else
        self:DrawFallbackLogo(wx + 18, wy + 17, 34)
    end
    self:Text("UTMM", wx + 66, wy + 16, Theme.text, 15, false, true, 5)
    self:Text("GUIDER", wx + 66, wy + 34, Theme.textDim, 12, false, true, 5)

    self:Text(CurrentLanguage == "PT" and "NAVEGAÇÃO" or "NAVIGATION", wx + 16, wy + 78, Theme.textMuted, 10, false, true, 5)
    local y = wy + 99
    for page = 1, 6 do
        local active = self.selectedPage == page
        local id = "page:" .. page
        local hovered = self.hovered == id
        if active then self:Box(wx + 8, y, sw - 16, 34, Theme.panel2, true, 3, 6) end
        if hovered and not active then self:Box(wx + 8, y, sw - 16, 34, Theme.hover, true, 3, 6) end
        if active then self:Box(wx + 8, y + 5, 3, 24, Theme.accent, true, 5, 2) end
        self:DrawIcon(self:PageIcon(page), wx + 20, y + 8, active and Theme.accent or Theme.textDim, 6)
        self:Text(self:PageName(page), wx + 48, y + 9, active and Theme.text or Theme.textDim, 12, false, active, 6)
        self:Register(id, wx + 8, y, sw - 16, 34, function()
            self:BlurInput(true)
            self.overlay = nil
            self.selectedPage = page
            self.dirty = true
        end, 8)
        y = y + 39
    end

    local langY = wy + wh - 70
    self:Line(wx + 14, langY - 10, wx + sw - 14, langY - 10, Theme.borderSoft, 1, 4)
    self:Text("Idioma / Language", wx + 16, langY, Theme.textMuted, 10, false, false, 5)
    self:Button("lang:pt", "PT", wx + 16, langY + 19, 54, 25, function()
        uiCache.utmm_lang = 0
        syncLanguage(0)
        saveConfig()
        self.dirty = true
    end, CurrentLanguage == "PT", 5)
    self:Button("lang:en", "EN", wx + 76, langY + 19, 54, 25, function()
        uiCache.utmm_lang = 1
        syncLanguage(1)
        saveConfig()
        self.dirty = true
    end, CurrentLanguage == "EN", 5)
end

function Gui:DrawHeader(wx, wy, ww)
    local sw = self.window.sidebar
    local hx = wx + sw
    self:Box(hx, wy, ww - sw, self.window.header, Theme.shell, true, 2, 12)
    self:Line(hx, wy + self.window.header, wx + ww, wy + self.window.header, Theme.borderSoft, 1, 3)
    self:Text(self:PageName(self.selectedPage), hx + 18, wy + 14, Theme.text, 14, false, true, 5)
    local status = self.pageBusy[self.selectedPage] and Lang.Searching or "Matcha LuaVM"
    self:Text(status, wx + ww - 64, wy + 15, self.pageBusy[self.selectedPage] and Theme.warning or Theme.textMuted, 10, true, false, 5)

    local cx = wx + ww - 32
    self:DrawIcon("close", cx + 7, wy + 12, self.hovered == "close" and Theme.danger or Theme.textDim, 7)
    self:Register("close", cx, wy + 7, 25, 27, function() self:Shutdown() end, 20)
    self:Register("window_drag", hx, wy, ww - sw - 42, self.window.header, function()
        self.draggingWindow = true
        self.dragDX = Mouse.X - self.window.x
        self.dragDY = Mouse.Y - self.window.y
    end, 2)
end

function Gui:DrawStatInputs(cx, cy, cw)
    local gap = 9
    local cell = math.floor((cw - gap * 2) / 3)
    self:Input("utmm_level", Lang.Level, "0", cx, cy, cell)
    self:Input("utmm_resets", Lang.Resets, "0", cx + cell + gap, cy, cell)
    self:Input("utmm_tr", Lang.TrueResets, "0", cx + (cell + gap) * 2, cy, cell)
    return cy + 49
end

function Gui:DrawFilters(cx, cy, cw)
    local gap = 8
    local cell = math.floor((cw - gap * 3) / 4)
    self:Input("utmm_reset_min", "RESET MIN", "0", cx, cy, cell)
    self:Input("utmm_reset_max", "RESET MAX", "", cx + cell + gap, cy, cell)
    self:Input("utmm_tr_min", "TR MIN", "0", cx + (cell + gap) * 2, cy, cell)
    self:Input("utmm_tr_max", "TR MAX", "", cx + (cell + gap) * 3, cy, cell)
    return cy + 49
end

function Gui:OpenManager(kind)
    self:BlurInput(true)
    self.overlay = kind
    self.overlayScroll = 0
    self.dirty = true
end

function Gui:DrawPageControls(cx, cy, cw)
    local page = self.selectedPage
    local y = cy

    if page == 1 then
        y = self:DrawFilters(cx, y, cw)
        self:Toggle("utmm_exact_reset", Lang.BossesInReset, cx, y + 3, math.floor(cw * 0.48))
        self:Toggle("utmm_exact_tr", Lang.BossesInTrueReset, cx + math.floor(cw * 0.51), y + 3, math.floor(cw * 0.49))
        y = y + 29
        self:Toggle("utmm_include_frag", Lang.IncludeFragments, cx, y + 2, math.floor(cw * 0.48))
        self:Button("scan", Lang.Scan, cx + cw - 138, y - 2, 138, 28, function()
            self:QueueJob(1, function() runCustomScan() end, true)
        end, true, 6)
        y = y + 35

    elseif page == 2 then
        local inputW = cw - 104
        self:Input("utmm_search", Lang.Search, Lang.SearchPlaceholder, cx, y, inputW)
        self:Button("search", "", cx + inputW + 8, y + 16, 40, 29, function() self:SubmitSearch() end, true, 6)
        self:DrawIcon("searchbutton", cx + inputW + 19, y + 22, Theme.text, 9)
        self:Button("search_text", Lang.SearchBtn, cx + inputW + 54, y + 16, 50, 29, function() self:SubmitSearch() end, false, 6)
        y = y + 53
        self:Toggle("utmm_utmoh", Lang.UTMOHMaterials, cx, y, math.floor(cw * 0.50))
        y = y + 29

    elseif page == 3 then
        self:Text(Lang.ProgressDesc, cx, y, Theme.textDim, 11, false, false, 5)
        y = y + 22
        self:Button("progress:route", Lang.GenRoute, cx, y, 145, 29, function()
            self:QueueJob(3, function() generateProgressRoute() end, true)
        end, true, 6)
        self:Button("progress:missing", Lang.MissingBtn, cx + 153, y, 145, 29, function()
            self:QueueJob(3, function() findMissingItems() end, true)
        end, false, 6)
        self:Toggle("utmm_missing_all", Lang.MissingAll, cx + 310, y + 3, cw - 310)
        y = y + 37
        self:Button("manage:progress", Lang.BlacklistTitle .. " (" .. #state.progressBlacklistOrder .. ")", cx, y, math.floor((cw - 8) * 0.5), 27, function()
            self:OpenManager("progress")
        end, false, 6)
        self:Button("manage:missing", Lang.MissBlacklistTitle .. " (" .. #missingBlacklistOrder .. ")", cx + math.floor((cw - 8) * 0.5) + 8, y, math.floor((cw - 8) * 0.5), 27, function()
            self:OpenManager("missing")
        end, false, 6)
        y = y + 35
        if state.fragDiag and state.fragDiag ~= "" then
            self:Text(state.fragDiag, cx, y, Theme.textMuted, 10, false, false, 5)
            y = y + 17
        end

    elseif page == 4 then
        self:Text(Lang.FarmDesc, cx, y, Theme.textDim, 11, false, false, 5)
        y = y + 23
        y = self:DrawFilters(cx, y, cw)
        self:Button("farm:exp", Lang.FarmExp, cx, y, math.floor((cw - 8) * 0.5), 30, function()
            self:QueueJob(4, function() findBestFarm("Exp") end, true)
        end, true, 6)
        self:Button("farm:gold", Lang.FarmGold, cx + math.floor((cw - 8) * 0.5) + 8, y, math.floor((cw - 8) * 0.5), 30, function()
            self:QueueJob(4, function() findBestFarm("Gold") end, true)
        end, false, 6)
        y = y + 38

    elseif page == 5 then
        self:Text(Lang.BuildDesc, cx, y, Theme.textDim, 11, false, false, 5)
        y = y + 20
        local comboW = math.min(190, math.floor(cw * 0.42))
        self:Cycle("utmm_build_show", Lang.BuildShow, {Lang.BuildSummary, Lang.BuildTop10, Lang.BuildAll}, cx, y, comboW)
        self:Button("build:scan", Lang.BuildScan, cx + comboW + 10, y + 16, cw - comboW - 10, 29, function()
            self:QueueJob(5, function() runBuildScan() end, true)
        end, true, 6)
        y = y + 54
        local half = math.floor((cw - 8) * 0.5)
        self:Button("food:8", Lang.FoodBest8, cx, y, half, 28, function()
            self:QueueJob(5, function() runFoodBest8() end, true)
        end, false, 6)
        self:Button("food:tier", Lang.FoodTierList, cx + half + 8, y, half, 28, function()
            self:QueueJob(5, function() runFoodTierList() end, true)
        end, false, 6)
        y = y + 36
        self:Button("manage:food", Lang.FoodBlacklistTitle .. " (" .. #foodBlacklistOrder .. ")", cx, y, math.min(240, cw), 27, function()
            self:OpenManager("food")
        end, false, 6)
        y = y + 33
        local bestW = state.buildWeapon or "-"
        local bestA = state.buildArmor or "-"
        local bestF = state.buildFood or "-"
        self:Text(Lang.BestWeaponConfirmed .. " " .. string.sub(bestW, 1, 45), cx, y, Theme.textDim, 9, false, false, 5)
        self:Text(Lang.BestArmor .. " " .. string.sub(bestA, 1, 30) .. " | " .. Lang.BestFood .. " " .. string.sub(bestF, 1, 24), cx, y + 14, Theme.textMuted, 9, false, false, 5)
        y = y + 31

    elseif page == 6 then
        self:Text(Lang.Top5Title, cx, y, Theme.text, 12, false, true, 5)
        self:Text(Lang.Top5Desc, cx, y + 18, Theme.textDim, 10, false, false, 5)
        y = y + 41
        self:Cycle("utmm_top5_sort", Lang.SortBy, {Lang.ByCombined, Lang.ByTrueReset, Lang.ByReset, Lang.ByLevel}, cx, y, 210)
        self:Button("top5", Lang.Top5Scan, cx + 220, y + 16, 145, 29, function()
            self:QueueJob(6, function() findTop5Hardest() end, true)
        end, true, 6)
        y = y + 53
    end

    return y
end

local function visibleIntersection(y, h, top, bottom)
    local iy = math.max(y, top)
    local ib = math.min(y + h, bottom)
    if ib <= iy then return nil end
    return iy, ib - iy
end

function Gui:ResultEntryHeight(e)
    local lines = entryLines(e)
    local h = 34 + #lines * 15 + 12
    local actionCount = 0
    if e.gui then actionCount = actionCount + 1 end
    if e.foodBlacklistKey or e.missingKey or e.progressEntry then actionCount = actionCount + 1 end
    if actionCount > 0 then h = h + 31 end
    if e.shopTargets and #e.shopTargets > 0 and e.shopName then
        h = h + #e.shopTargets * 42
    end
    return h
end

function Gui:RerunFood(resetScroll)
    if state.lastFoodScan == "best8" then
        self:QueueJob(5, function() runFoodBest8() end, resetScroll == true)
        return true
    elseif state.lastFoodScan == "tier" then
        self:QueueJob(5, function() runFoodTierList() end, resetScroll == true)
        return true
    end
    state.status = ""
    self.dirty = true
    return false
end

function Gui:DrawResultCard(e, displayIndex, x, y, w, top, bottom)
    local h = self:ResultEntryHeight(e)
    local iy, ih = visibleIntersection(y, h, top, bottom)
    if not iy then return h end

    self:Box(x, iy, w, ih, Theme.panel, true, 4, 7)
    self:Box(x, iy, w, ih, Theme.borderSoft, false, 5, 7)

    local title = e.label or (tostring(displayIndex) .. ". " .. tostring(e.name or "?"))
    if y + 9 >= top and y + 9 <= bottom - 14 then
        self:Text(string.sub(title, 1, 82), x + 12, y + 9, Theme.text, 12, false, true, 7)
    end

    local ly = y + 31
    local lines = entryLines(e)
    for i = 1, #lines do
        if ly >= top and ly <= bottom - 14 then
            self:Text(string.sub(tostring(lines[i]), 1, 96), x + 12, ly, Theme.textDim, 10, false, false, 7)
        end
        ly = ly + 15
    end
    ly = ly + 4

    local actionX = x + 12
    if e.gui then
        local by = ly
        if by + 25 >= top and by <= bottom then
            self:Button("tp:" .. tostring(displayIndex), Lang.TP, actionX, by, 88, 25, function() teleportTo(e.gui) end, true, 8)
            self:DrawIcon("teleport", actionX + 8, by + 4, Theme.text, 10)
        end
        actionX = actionX + 96
    end

    local blacklistAction = nil
    if e.foodBlacklistKey then
        blacklistAction = function()
            if addFoodBlacklist(e.foodBlacklistKey) then
                self:RerunFood(false)
            end
        end
    elseif e.missingKey then
        blacklistAction = function()
            if addMissingBlacklist(e.missingKey) then
                self:QueueJob(3, function() findMissingItems() end, false)
            end
        end
    elseif e.progressEntry then
        blacklistAction = function()
            if addProgressBlacklist(e.name) then
                self:QueueJob(3, function() generateProgressRoute() end, false)
            end
        end
    end
    if blacklistAction then
        local by = ly
        if by + 25 >= top and by <= bottom then
            self:Button("black:" .. tostring(displayIndex), Lang.Blacklist, actionX, by, 108, 25, blacklistAction, false, 8)
            self:DrawIcon("blacklist", actionX + 7, by + 4, Theme.danger, 10)
        end
    end
    if e.gui or blacklistAction then ly = ly + 31 end

    if e.shopTargets and #e.shopTargets > 0 and e.shopName then
        for shopI = 1, #e.shopTargets do
            local target = e.shopTargets[shopI]
            if ly >= top and ly <= bottom - 14 then
                self:Text(Lang.ShopPoint .. ": " .. tostring(target.name), x + 12, ly, Theme.textMuted, 9, false, false, 7)
            end
            local by = ly + 14
            if by + 24 >= top and by <= bottom then
                local clickTarget = {
                    name = target.name, pathSegments = target.pathSegments,
                    instance = target.instance, x = target.x, y = target.y, z = target.z,
                }
                self:Button("shop:" .. tostring(displayIndex) .. ":" .. shopI, Lang.TPShop, x + 12, by, 112, 24, function()
                    teleportToShopPoint(clickTarget)
                end, false, 8)
                self:DrawIcon("shop", x + 18, by + 3, Theme.textDim, 10)
            end
            ly = ly + 42
        end
    end

    return h
end

function Gui:ScrollResults(delta)
    local page = self.selectedPage
    local maxScroll = self.resultScrollMax[page] or 0
    local current = self.resultScroll[page] or 0
    local nextValue = clamp(current + delta, 0, maxScroll)
    if nextValue ~= current then
        self.resultScroll[page] = nextValue
        self.dirty = true
        return true
    end
    return false
end

function Gui:DrawResults(cx, cy, cw, bottomY)
    local page = self.selectedPage
    local snap = self:PageSnapshot(page)
    local status = self:StatusFor(page, snap)
    local headerH = 29
    self:Text(status, cx + 2, cy + 4, self.pageBusy[page] and Theme.warning or Theme.textDim, 11, false, true, 5)

    local viewTop = cy + headerH
    local viewBottom = bottomY
    local viewH = math.max(80, viewBottom - viewTop)
    self:Box(cx, viewTop, cw, viewH, Theme.bg, true, 3, 7)
    self:Box(cx, viewTop, cw, viewH, Theme.borderSoft, false, 4, 7)

    local entries = snap.results or {}
    local contentH = 10
    if snap.warning and snap.warning ~= "" then contentH = contentH + 32 end
    for i = 1, #entries do contentH = contentH + self:ResultEntryHeight(entries[i]) + 8 end
    if snap.overflow and snap.overflow > 0 then contentH = contentH + 24 end
    local maxScroll = math.max(0, contentH - viewH)
    self.resultScrollMax[page] = maxScroll
    self.resultScroll[page] = clamp(self.resultScroll[page] or 0, 0, maxScroll)

    local scroll = self.resultScroll[page] or 0
    local y = viewTop + 10 - scroll
    local cardW = cw - (maxScroll > 0 and 17 or 8)

    if snap.warning and snap.warning ~= "" then
        if y + 20 >= viewTop and y <= viewBottom then
            self:Text(string.sub(snap.warning, 1, 92), cx + 10, y + 3, Theme.warning, 10, false, false, 7)
        end
        y = y + 32
    end

    if #entries == 0 and not self.pageBusy[page] then
        self:Text("-", cx + 12, viewTop + 13, Theme.textMuted, 12, false, false, 6)
    end

    for i = 1, #entries do
        local e = entries[i]
        local displayIndex = e.stepIndex or i
        local h = self:DrawResultCard(e, displayIndex, cx + 7, y, cardW - 7, viewTop + 2, viewBottom - 2)
        y = y + h + 8
    end

    if snap.overflow and snap.overflow > 0 and y >= viewTop and y <= viewBottom - 15 then
        self:Text("... +" .. tostring(snap.overflow), cx + 12, y, Theme.textMuted, 10, false, false, 6)
    end

    if maxScroll > 0 then
        local trackX = cx + cw - 9
        local trackY = viewTop + 5
        local trackH = viewH - 10
        self:Box(trackX, trackY, 4, trackH, Theme.panel2, true, 6, 2)
        local thumbH = math.max(28, math.floor((viewH / contentH) * trackH))
        local travel = math.max(1, trackH - thumbH)
        local thumbY = trackY + math.floor((scroll / maxScroll) * travel)
        self:Box(trackX, thumbY, 4, thumbH, self.hovered == "result_scroll" and Theme.accent or Theme.border, true, 8, 2)
        self:Register("result_scroll", trackX - 5, thumbY, 14, thumbH, function()
            self.draggingResultScroll = true
            self.scrollGrab = Mouse.Y - thumbY
        end, 14)
        self.resultMetrics = {
            x = cx, y = viewTop, w = cw, h = viewH,
            trackY = trackY, trackH = trackH, thumbH = thumbH,
        }
    else
        self.resultMetrics = {x = cx, y = viewTop, w = cw, h = viewH}
    end
end

function Gui:ManagerList(kind)
    local list = {}
    if kind == "progress" then
        for i, name in ipairs(state.progressBlacklistOrder) do
            list[#list + 1] = {key = name, label = name, index = i}
        end
    elseif kind == "missing" then
        for i, key in ipairs(missingBlacklistOrder) do
            list[#list + 1] = {key = key, label = missingBlacklistLabel(key), index = i}
        end
    elseif kind == "food" then
        for i, key in ipairs(foodBlacklistOrder) do
            local ff = itemFolder("Food", key)
            local fs = ff and foodStats(key, ff) or nil
            local label = fs and fs.label or key
            local detail = ""
            if fs then
                local heal = fs.heal ~= nil and fmtBuild(fs.heal) or "?"
                local cost = fs.cost ~= nil and (formatNumber(fs.cost) .. " Gold") or Lang.FoodUnknownCost
                detail = Lang.FoodHeal .. ": " .. heal .. " | " .. Lang.FoodCost .. ": " .. cost
            end
            list[#list + 1] = {key = key, label = label, detail = detail, index = i}
        end
    end
    return list
end

function Gui:DrawOverlay(wx, wy, ww, wh)
    if not self.overlay then return end
    self:Box(wx, wy, ww, wh, Color3.fromRGB(6, 7, 9), true, 30, 12)
    safeSet(self.pool.Square and self.pool.Square[self.poolCursor.Square or 0], "Transparency", 0.88)

    local pw = math.min(540, ww - 70)
    local ph = math.min(390, wh - 70)
    local px = wx + math.floor((ww - pw) * 0.5)
    local py = wy + math.floor((wh - ph) * 0.5)
    self:Box(px, py, pw, ph, Theme.shell, true, 31, 10)
    self:Box(px, py, pw, ph, Theme.border, false, 32, 10)

    local title = self.overlay == "progress" and Lang.BlacklistTitle
        or (self.overlay == "missing" and Lang.MissBlacklistTitle or Lang.FoodBlacklistTitle)
    self:Text(title, px + 16, py + 14, Theme.text, 13, false, true, 34)
    self:DrawIcon("close", px + pw - 28, py + 10, self.hovered == "overlay_close" and Theme.danger or Theme.textDim, 35)
    self:Register("overlay_close", px + pw - 35, py + 6, 30, 30, function()
        self.overlay = nil
        self.dirty = true
    end, 40)

    local list = self:ManagerList(self.overlay)
    local canClear = self.overlay == "missing" or self.overlay == "food"
    local listTop = py + 48
    if canClear and #list > 0 then
        self:Button("overlay_clear", self.overlay == "food" and Lang.FoodClearBlacklist or Lang.ClearBlacklist,
            px + 16, py + 43, 190, 25, function()
                if self.overlay == "food" then
                    if clearFoodBlacklist() then self:RerunFood(false) end
                else
                    if clearMissingBlacklist() then self:QueueJob(3, function() findMissingItems() end, false) end
                end
                self.overlayScroll = 0
            end, false, 36)
        listTop = py + 76
    end

    local viewX = px + 12
    local viewY = listTop
    local viewW = pw - 24
    local viewH = py + ph - 14 - viewY
    self:Box(viewX, viewY, viewW, viewH, Theme.bg, true, 33, 6)
    self:Box(viewX, viewY, viewW, viewH, Theme.borderSoft, false, 34, 6)

    local rowH = self.overlay == "food" and 50 or 38
    local contentH = #list * rowH + 10
    self.overlayScrollMax = math.max(0, contentH - viewH)
    self.overlayScroll = clamp(self.overlayScroll or 0, 0, self.overlayScrollMax)
    local ry = viewY + 6 - self.overlayScroll

    if #list == 0 then
        local empty = self.overlay == "progress" and Lang.BlacklistEmpty
            or (self.overlay == "missing" and Lang.MissBlacklistEmpty or Lang.FoodBlacklistEmpty)
        self:Text(empty, viewX + 12, viewY + 14, Theme.textMuted, 11, false, false, 36)
    end

    for _, row in ipairs(list) do
        local iy, ih = visibleIntersection(ry, rowH - 5, viewY + 2, viewY + viewH - 2)
        if iy then
            self:Box(viewX + 6, iy, viewW - 20, ih, Theme.panel, true, 35, 5)
            if ry + 8 >= viewY and ry + 8 <= viewY + viewH - 14 then
                self:Text(tostring(row.index) .. ". " .. string.sub(row.label, 1, 55), viewX + 15, ry + 8, Theme.text, 10, false, false, 37)
            end
            if row.detail and row.detail ~= "" and ry + 24 >= viewY and ry + 24 <= viewY + viewH - 13 then
                self:Text(string.sub(row.detail, 1, 68), viewX + 15, ry + 24, Theme.textMuted, 9, false, false, 37)
            end
            local removeY = ry + math.floor((rowH - 29) * 0.5)
            if removeY + 24 >= viewY and removeY <= viewY + viewH then
                local rkey = row.key
                self:Button("overlay_remove:" .. tostring(row.index), Lang.RemoveBlacklist, viewX + viewW - 128, removeY, 108, 24, function()
                    if self.overlay == "progress" then
                        if removeProgressBlacklist(rkey) then self:QueueJob(3, function() generateProgressRoute() end, false) end
                    elseif self.overlay == "missing" then
                        if removeMissingBlacklist(rkey) then self:QueueJob(3, function() findMissingItems() end, false) end
                    else
                        if removeFoodBlacklist(rkey) then self:RerunFood(false) end
                    end
                end, false, 38)
            end
        end
        ry = ry + rowH
    end

    if self.overlayScrollMax > 0 then
        local trackX = viewX + viewW - 8
        local trackY = viewY + 5
        local trackH = viewH - 10
        local thumbH = math.max(25, math.floor((viewH / contentH) * trackH))
        local travel = math.max(1, trackH - thumbH)
        local thumbY = trackY + math.floor((self.overlayScroll / self.overlayScrollMax) * travel)
        self:Box(trackX, trackY, 4, trackH, Theme.panel2, true, 37, 2)
        self:Box(trackX, thumbY, 4, thumbH, self.hovered == "overlay_scroll" and Theme.accent or Theme.border, true, 39, 2)
        self:Register("overlay_scroll", trackX - 5, thumbY, 14, thumbH, function()
            self.draggingOverlayScroll = true
            self.scrollGrab = Mouse.Y - thumbY
        end, 45)
        self.overlayMetrics = {x = viewX, y = viewY, w = viewW, h = viewH, trackY = trackY, trackH = trackH, thumbH = thumbH}
    else
        self.overlayMetrics = {x = viewX, y = viewY, w = viewW, h = viewH}
    end
end

function Gui:Render()
    if not self.visible then
        for _, list in pairs(self.pool) do
            for _, obj in ipairs(list) do safeSet(obj, "Visible", false) end
        end
        return
    end

    self:BeginFrame()
    local wx, wy = self.window.x, self.window.y
    local ww, wh = self.window.width, self.window.height
    self:Box(wx, wy, ww, wh, Theme.bg, true, 1, 12)
    self:Box(wx, wy, ww, wh, Theme.border, false, 2, 12)
    self:DrawSidebar(wx, wy, ww, wh)
    self:DrawHeader(wx, wy, ww)

    local cx = wx + self.window.sidebar + 16
    local cw = ww - self.window.sidebar - 32
    local cy = wy + self.window.header + 13
    cy = self:DrawStatInputs(cx, cy, cw) + 8
    cy = self:DrawPageControls(cx, cy, cw)
    cy = cy + 3
    local bottomY = wy + wh - 18
    self:DrawResults(cx, cy, cw, bottomY)

    self:Register("resize", wx + ww - 15, wy + wh - 15, 15, 15, function()
        self.draggingResize = true
        self.dragDX = Mouse.X - self.window.width
        self.dragDY = Mouse.Y - self.window.height
    end, 18)
    self:Line(wx + ww - 12, wy + wh - 4, wx + ww - 4, wy + wh - 12, Theme.border, 1, 8)
    self:Line(wx + ww - 8, wy + wh - 4, wx + ww - 4, wy + wh - 8, Theme.border, 1, 8)

    self:DrawOverlay(wx, wy, ww, wh)
    self:EndFrame()
    self.dirty = false
end

function Gui:HandleWheel(delta)
    if not delta or delta == 0 then return end
    local mx, my = Mouse.X, Mouse.Y
    if self.overlay and self.overlayMetrics and inRect(mx, my, self.overlayMetrics.x, self.overlayMetrics.y, self.overlayMetrics.w, self.overlayMetrics.h) then
        self.overlayScroll = clamp(self.overlayScroll - delta * 34, 0, self.overlayScrollMax or 0)
        self.dirty = true
        return
    end
    local m = self.resultMetrics
    if m and inRect(mx, my, m.x, m.y, m.w, m.h) then
        self:ScrollResults(-delta * 42)
    end
end

-- Algumas builds do Matcha entregam MouseWheel por InputBegan; outras nao.
-- O scrollbar arrastavel permanece funcional mesmo quando o evento nao existe.
if UserInputService and UserInputService.InputBegan then
    pcall(function()
        UserInputService.InputBegan:Connect(function(input)
            local kind = ""
            pcall(function() kind = tostring(input.UserInputType) end)
            if string.find(kind, "MouseWheel", 1, true) then
                local delta = 0
                pcall(function() delta = input.Position.Z end)
                if delta == 0 then pcall(function() delta = input.Delta.Z end) end
                Gui:HandleWheel(delta)
            end
        end)
    end)
end

function Gui:PollFallbackScrollKeys()
    if self.activeInput then return end
    local mappings = {
        {VK.UP, -32}, {VK.DOWN, 32}, {VK.PGUP, -180}, {VK.PGDN, 180},
    }
    for _, item in ipairs(mappings) do
        local code, amount = item[1], item[2]
        local down = type(iskeypressed) == "function" and iskeypressed(code) or false
        local key = "scroll:" .. code
        local prev = self.keyPrev[key] == true
        if down and not prev then
            if self.overlay then
                self.overlayScroll = clamp((self.overlayScroll or 0) + amount, 0, self.overlayScrollMax or 0)
                self.dirty = true
            else
                self:ScrollResults(amount)
            end
        end
        self.keyPrev[key] = down
    end
end

function Gui:HandleMouse(dt)
    local mx, my = Mouse.X or 0, Mouse.Y or 0
    local down = type(ismouse1pressed) == "function" and ismouse1pressed() or false
    local pressed = down and not self.lastMouseDown

    if self.draggingWindow and down then
        self.window.x = math.floor(mx - self.dragDX)
        self.window.y = math.floor(my - self.dragDY)
        self.dirty = true
    elseif self.draggingResize and down then
        self.window.width = clamp(math.floor(mx - self.window.x - self.dragDX), self.window.minWidth, self.window.maxWidth)
        self.window.height = clamp(math.floor(my - self.window.y - self.dragDY), self.window.minHeight, self.window.maxHeight)
        self.dirty = true
    elseif self.draggingResultScroll and down and self.resultMetrics then
        local m = self.resultMetrics
        local travel = math.max(1, m.trackH - m.thumbH)
        local thumbY = my - self.scrollGrab
        local ratio = clamp((thumbY - m.trackY) / travel, 0, 1)
        self.resultScroll[self.selectedPage] = ratio * (self.resultScrollMax[self.selectedPage] or 0)
        self.dirty = true
    elseif self.draggingOverlayScroll and down and self.overlayMetrics then
        local m = self.overlayMetrics
        local travel = math.max(1, m.trackH - m.thumbH)
        local thumbY = my - self.scrollGrab
        local ratio = clamp((thumbY - m.trackY) / travel, 0, 1)
        self.overlayScroll = ratio * (self.overlayScrollMax or 0)
        self.dirty = true
    end

    if not down and self.lastMouseDown then
        self.draggingWindow = false
        self.draggingResize = false
        self.draggingResultScroll = false
        self.draggingOverlayScroll = false
    end

    local hit = self:Hit(mx, my)
    local hover = hit and hit.id or nil
    if hover ~= self.hovered then
        self.hovered = hover
        self.dirty = true
    end

    if pressed then
        if hit and hit.callback then
            local ok, err = pcall(hit.callback)
            if not ok then warn("[UTMM UI] " .. tostring(err)) end
        elseif self.activeInput then
            self:BlurInput(true)
        elseif self.overlay then
            self.overlay = nil
            self.dirty = true
        end
    end

    if mx ~= self.lastMouseX or my ~= self.lastMouseY then self.dirty = true end
    self.lastMouseX, self.lastMouseY, self.lastMouseDown = mx, my, down
end

function Gui:Shutdown()
    if not self.running then return end
    self.running = false
    self.visible = false
    for _, list in pairs(self.pool) do
        for _, obj in ipairs(list) do
            pcall(function() obj:Remove() end)
        end
    end
    self.pool = {}
    self.hitboxes = {}
end

Gui:LoadLogo()
syncLanguage(comboDefault("utmm_lang"))

spawn(function()
    while Gui.running do
        local job = pendingJob
        if job then
            local page = pendingJobPage or Gui.selectedPage
            pendingJob = nil
            pendingJobPage = nil
            notify(Lang.Searching, "UTMM Guider", 1)
            local ok, err = pcall(job)
            if not ok then
                state.busy = false
                Gui.pageBusy[page] = false
                warn("[UTMM Guider] " .. tostring(err))
            end
            Gui:CapturePage(page)
            notify(tostring(state.count) .. " " .. ((state.countKind == "best") and Lang.Best or Lang.Found), "UTMM Guider", 2)
        end
        wait(0.04)
    end
end)

local renderConnection
renderConnection = RunService.RenderStepped:Connect(function(dt)
    if not Gui.running then
        if renderConnection then pcall(function() renderConnection:Disconnect() end) end
        return
    end

    Gui:PollTextInput()
    Gui:PollFallbackScrollKeys()
    Gui:HandleMouse(dt)

    if state.stamp ~= Gui.lastStamp then
        Gui.lastStamp = state.stamp
        Gui.dirty = true
    end

    if Gui.activeInput and math.floor(tick() * 2) ~= math.floor((tick() - (dt or 0.016)) * 2) then
        Gui.dirty = true
    end

    if Gui.dirty then Gui:Render() end
end)

Gui:Render()
print(Lang.Loaded)
notify(Lang.Loaded, "UTMM Guider", 4)

end)()
