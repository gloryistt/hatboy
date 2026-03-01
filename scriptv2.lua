local UI = {}
--------------------------------------------------
-- LUMIWARE V4.6 — Enhanced Update
-- + Trainer Battle Auto-Mode
-- + Config Save/Load/Reset Tab
-- + Auto-Heal Scanner & Auto-Heal
-- + Encounter Rate Graph
-- + Battle Type Filter for Automation
-- + Flee Fail Retry Improvements
--------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local VERSION = "v4.6"

--------------------------------------------------
-- CONFIGURATION SYSTEM
--------------------------------------------------
local configName = "LumiWare_v46_Config.json"
local defaultConfig = {
    webhookUrl = "",
    useAutoPing = false,
    pingIds = "",
    autoMode = "off",
    autoMoveSlot = 1,
    autoWalk = false,
    discoveryMode = false,
    customRares = {},
    -- NEW v4.6
    trainerAutoMode = "off",     -- "off", "move", "run"
    trainerAutoMoveSlot = 1,
    autoHealEnabled = false,
    autoHealThreshold = 30,      -- Heal when HP < X%
    healRemoteName = "",
    healRemotePath = "",
    automateTrainer = true,
    automateWild = true,
    infiniteRepel = false,       -- NEW v4.6
    autoFishEnabled = false,
    autoDiscEnabled = false,
    masteryDisable = false,
    autoSkipDialogue = false,
    autoDenyMove = false,
    autoDenySwitch = false,
    autoDenyNick = false,
    
    -- Rally & Catch
    autoRally = false,
    rallyKeepGleam = false,
    rallyKeepHA = false,
    autoCatchNotOwned = false,
    autoCatchGleam = false,
    autoCatchGamma = false,
    autoCatchSpare = false,
    defeatCorruptMove = 0, -- 0 is disabled, 1-4 is move slot
    autoEncounter = false,
    
    -- Exploits
    fastBattle = false,
    infUMV = false,
    skipFish = false,
    noUnstuck = false,
}

local config = defaultConfig
if isfile and readfile and writefile then
    pcall(function()
        if isfile(configName) then
            local decoded = HttpService:JSONDecode(readfile(configName))
            for k, v in pairs(decoded) do
                config[k] = v
            end
        else
            writefile(configName, HttpService:JSONEncode(defaultConfig))
        end
    end)
end

local function saveConfig()
    if writefile then
        pcall(function()
            writefile(configName, HttpService:JSONEncode(config))
        end)
    end
end

local function resetConfigToDefault()
    config = {}
    for k, v in pairs(defaultConfig) do
        config[k] = v
    end
    saveConfig()
end

local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local PLAYER_NAME = player.Name

--------------------------------------------------
-- LOGGING
--------------------------------------------------
local VERBOSE_MODE = false

local function log(category, ...)
    print("[LumiWare][" .. category .. "]", ...)
end

local function logDebug(...)
    if VERBOSE_MODE then log("DEBUG", ...) end
end

log("INFO", "Initializing LumiWare " .. VERSION .. " for:", PLAYER_NAME)

--------------------------------------------------
-- GAME API EXFILTRATION (v6.0 — Multi-Strategy with Diagnostics)
--
-- Strategies (tried in order, first success wins):
--   1. Classic: getgc(true) → find table with "Utilities" key
--   2. Scoring: getgc/registry → score tables by known key names
--   3. Connections: getconnections() on RemoteEvents → upvalues
--   4. Require: require() ALL ModuleScripts (with thread identity)
--   5. Deep upvalue: getupvalues on ALL functions in getgc
--   6. Synthetic: build from individual module signatures
--   7. Environment: scan function environments (getfenv)
--   8. getnilinstances / getscripts fallback
--------------------------------------------------
local gameAPI = nil
local gameAPIReady = false
local setThreadContext = setthreadcontext or setthreadidentity or setidentity or function(_) end

-- ============================================================
-- STEP 0: Detect which executor APIs are available
-- ============================================================
local HAS = {}
local function probe(name)
    local ok, val = pcall(function()
        return getfenv()[name] or _G[name] or getgenv and getgenv()[name]
    end)
    if ok and val then HAS[name] = val; return val end
    -- try rawget on shared environments
    pcall(function()
        local v = rawget(getfenv(0), name)
        if v then HAS[name] = v end
    end)
    pcall(function()
        if not HAS[name] and getgenv then
            local v = rawget(getgenv(), name)
            if v then HAS[name] = v end
        end
    end)
    return HAS[name]
end

-- Probe all relevant APIs
for _, apiName in ipairs({
    "getgc", "getupvalues", "getupvalue", "debug",
    "getreg", "getconnections", "getscripts", "getrunningscripts",
    "getnilinstances", "getinstances", "getfenv", "hookfunction",
    "hookmetamethod", "newcclosure", "iscclosure", "getinfo",
    "getconstants", "getprotos", "getstack", "checkcaller",
    "setthreadcontext", "setthreadidentity", "setidentity",
    "getnamecallmethod", "getrawmetatable",
}) do
    probe(apiName)
end

-- Log available APIs
do
    local available = {}
    local missing = {}
    for _, name in ipairs({"getgc", "getupvalues", "getreg", "getconnections", "getscripts", 
                           "getrunningscripts", "getnilinstances", "getinstances", "getfenv",
                           "getconstants", "getprotos", "setthreadcontext", "setthreadidentity"}) do
        if HAS[name] then
            table.insert(available, name)
        else
            table.insert(missing, name)
        end
    end
    log("API", "Available APIs: " .. (next(available) and table.concat(available, ", ") or "NONE"))
    log("API", "Missing APIs: " .. (next(missing) and table.concat(missing, ", ") or "none"))
end

-- Convenience: getupvalues that works across executor APIs
local function safeGetUpvalues(func)
    if type(func) ~= "function" then return {} end
    -- Try getupvalues first (returns {[name]=value} or {[idx]=value})
    if HAS.getupvalues then
        local ok, ups = pcall(HAS.getupvalues, func)
        if ok and type(ups) == "table" then return ups end
    end
    -- Try debug.getupvalue iteration
    if debug and debug.getupvalue then
        local ups = {}
        local ok = pcall(function()
            for i = 1, 200 do
                local name, val = debug.getupvalue(func, i)
                if name == nil then break end
                ups[i] = val
            end
        end)
        if ok and next(ups) then return ups end
    end
    return {}
end

-- ============================================================
-- MODULE SIGNATURES for synthetic build
-- ============================================================
local MODULE_SIGNATURES = {
    {"Battle",     {"setupScene"},                                  {"doTrainerBattle", "doWildBattle", "currentBattle"}},
    {"Network",    {"get"},                                         {"post", "fire", "set"}},
    {"Menu",       {"disable", "enable"},                           {"pc", "shop", "rally", "mastery", "options", "fastClose", "enabled"}},
    {"DataManager",{"loadChunk"},                                   {"loadModule", "currentChunk", "setLoading", "getModule"}},
    {"BattleGui",  {"message"},                                     {"switchMonster", "animHit", "animMove", "animWeather", "animStatus", "animAbility", "animBoost", "setCameraIfLookingAway"}},
    {"NPCChat",    {},                                              {"Say", "say", "manualAdvance"}},
    {"MasterControl", {"WalkEnabled"},                              {}},
    {"Utilities",  {"FadeOut", "FadeIn"},                           {"TeleportToSpawnBox", "Teleport"}},
    {"PlayerData", {"completedEvents"},                             {}},
    {"Repel",      {"steps"},                                       {}},
    {"Fishing",    {"OnWaterClicked"},                               {"rod", "FishMiniGame", "DisableRodModel"}},
    {"WalkEvents", {"beginLoop"},                                   {}},
    {"BattleClientSprite", {"animFaint", "animSummon"},             {"animUnsummon", "monsterIn", "monsterOut", "animEmulate"}},
    {"BattleClientSide",   {"switchOut", "faint"},                  {"swapTo", "dragIn"}},
    {"RoundedFrame",       {"setFillbarRatio"},                     {}},
    {"ArcadeController",   {"playing"},                             {}},
}

local function matchSignature(tbl, sig)
    local name, required, optional = sig[1], sig[2], sig[3]
    if type(tbl) ~= "table" then return 0 end
    local ok, score = pcall(function()
        local s = 0
        for _, key in ipairs(required) do
            if rawget(tbl, key) == nil then return 0 end
            s = s + 10
        end
        if name == "NPCChat" then
            local optCount = 0
            for _, key in ipairs(optional) do
                if rawget(tbl, key) ~= nil then optCount = optCount + 1 end
            end
            if optCount < 2 then return 0 end
            s = s + optCount * 5
        else
            for _, key in ipairs(optional) do
                if rawget(tbl, key) ~= nil then s = s + 5 end
            end
        end
        return s
    end)
    return (ok and score) or 0
end

-- Known shared-table keys and scoring
local KNOWN_KEYS = {
    Battle = 10, Network = 10, Utilities = 10, DataManager = 10,
    BattleGui = 10, NPCChat = 10, MasterControl = 10, Menu = 10,
    PlayerData = 5, Repel = 5, WalkEvents = 5, BattleClientSprite = 5,
    BattleClientSide = 5, Constants = 5, Assets = 5, Fishing = 5,
    ObjectiveManager = 5, RoundedFrame = 5, BitBuffer = 5,
    Mining = 3, ArcadeController = 3,
    battle = 10, network = 10, utilities = 10, dataManager = 10,
    battleGui = 10, npcChat = 10, masterControl = 10, menu = 10,
    playerData = 5, repel = 5, walkEvents = 5, fishing = 5,
}

local function scoreSharedTable(t)
    if type(t) ~= "table" then return 0, {} end
    local score, matched = 0, {}
    pcall(function()
        for k in pairs(t) do
            if type(k) == "string" and KNOWN_KEYS[k] then
                score = score + KNOWN_KEYS[k]
                matched[#matched+1] = k
            end
        end
    end)
    return score, matched
end

-- ============================================================
-- TABLE COLLECTORS — gather tables from every available source
-- ============================================================
local function gatherTablesFromGC()
    local tbls = {}
    if not HAS.getgc then return tbls end
    local ok, gc = pcall(HAS.getgc, true)
    if not ok or type(gc) ~= "table" then
        log("API", "getgc(true) returned: " .. tostring(gc) .. " (ok=" .. tostring(ok) .. ")")
        return tbls
    end
    local count, tableCount = 0, 0
    for _, obj in ipairs(gc) do
        count = count + 1
        if type(obj) == "table" then
            tableCount = tableCount + 1
            tbls[#tbls+1] = obj
        end
    end
    log("API", "getgc returned " .. count .. " objects, " .. tableCount .. " tables")
    return tbls
end

local function gatherTablesFromRegistry()
    local tbls = {}
    pcall(function()
        if not debug or not debug.getregistry then return end
        local reg = debug.getregistry()
        if type(reg) ~= "table" then return end
        for _, v in pairs(reg) do
            if type(v) == "table" then
                tbls[#tbls+1] = v
            elseif type(v) == "function" then
                local ups = safeGetUpvalues(v)
                for _, upv in pairs(ups) do
                    if type(upv) == "table" then tbls[#tbls+1] = upv end
                end
            end
        end
        log("API", "Registry scan found " .. #tbls .. " tables")
    end)
    return tbls
end

local function gatherTablesFromGetreg()
    local tbls = {}
    if not HAS.getreg then return tbls end
    pcall(function()
        local reg = HAS.getreg()
        if type(reg) == "table" then
            for _, v in pairs(reg) do
                if type(v) == "table" then tbls[#tbls+1] = v end
            end
        end
        log("API", "getreg found " .. #tbls .. " tables")
    end)
    return tbls
end

-- Strategy 3: getconnections on RemoteEvents
local function gatherTablesFromConnections()
    local tbls = {}
    if not HAS.getconnections then
        log("API", "getconnections not available, skipping connection scan")
        return tbls
    end
    pcall(function()
        local RS = game:GetService("ReplicatedStorage")
        local events = {}
        for _, obj in ipairs(RS:GetDescendants()) do
            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") or obj:IsA("BindableEvent") then
                events[#events+1] = obj
            end
        end
        -- Also check player GUI
        pcall(function()
            for _, obj in ipairs(player:WaitForChild("PlayerGui", 2):GetDescendants()) do
                if obj:IsA("RemoteEvent") or obj:IsA("BindableEvent") then
                    events[#events+1] = obj
                end
            end
        end)
        
        local connCount = 0
        for _, evt in ipairs(events) do
            pcall(function()
                local conns = HAS.getconnections(evt.OnClientEvent or evt.Event)
                if type(conns) == "table" then
                    for _, conn in ipairs(conns) do
                        pcall(function()
                            local func = conn.Function or conn["function"]
                            if func then
                                connCount = connCount + 1
                                local ups = safeGetUpvalues(func)
                                for _, upv in pairs(ups) do
                                    if type(upv) == "table" then
                                        tbls[#tbls+1] = upv
                                    end
                                end
                                -- Also check upvalue tables one level deep
                                for _, upv in pairs(ups) do
                                    if type(upv) == "table" then
                                        pcall(function()
                                            for k2, v2 in pairs(upv) do
                                                if type(v2) == "table" and type(k2) == "string" then
                                                    tbls[#tbls+1] = v2
                                                end
                                            end
                                        end)
                                    end
                                end
                            end
                        end)
                    end
                end
            end)
        end
        log("API", "Connection scan: " .. connCount .. " connections → " .. #tbls .. " tables")
    end)
    return tbls
end

-- Strategy 4: require() all ModuleScripts
local function gatherTablesFromRequire()
    local tbls = {}
    pcall(function()
        -- Set thread identity for requiring game modules
        pcall(setThreadContext, 2)
        
        local RS = game:GetService("ReplicatedStorage")
        local moduleCount, successCount = 0, 0
        for _, child in ipairs(RS:GetDescendants()) do
            if child:IsA("ModuleScript") then
                moduleCount = moduleCount + 1
                pcall(function()
                    local mod = require(child)
                    if type(mod) == "table" then
                        successCount = successCount + 1
                        tbls[#tbls+1] = mod
                        -- Also add sub-tables
                        pcall(function()
                            for k, v in pairs(mod) do
                                if type(v) == "table" and type(k) == "string" then
                                    tbls[#tbls+1] = v
                                end
                            end
                        end)
                    end
                end)
            end
        end
        
        -- Also try StarterPlayer scripts
        pcall(function()
            local SP = game:GetService("StarterPlayer")
            if SP then
                for _, child in ipairs(SP:GetDescendants()) do
                    if child:IsA("ModuleScript") then
                        moduleCount = moduleCount + 1
                        pcall(function()
                            local mod = require(child)
                            if type(mod) == "table" then
                                successCount = successCount + 1
                                tbls[#tbls+1] = mod
                                pcall(function()
                                    for k, v in pairs(mod) do
                                        if type(v) == "table" and type(k) == "string" then
                                            tbls[#tbls+1] = v
                                        end
                                    end
                                end)
                            end
                        end)
                    end
                end
            end
        end)
        
        log("API", "Require scan: " .. moduleCount .. " modules tried, " .. successCount .. " returned tables → " .. #tbls .. " total")
    end)
    return tbls
end

-- Strategy 5: Deep upvalue scan on ALL functions from getgc
local function gatherTablesFromUpvalues()
    local tbls = {}
    if not HAS.getgc then return tbls end
    pcall(function()
        local funcCount = 0
        local ok, gc = pcall(HAS.getgc)  -- getgc() without true = only functions
        if not ok or type(gc) ~= "table" then
            -- Try getgc(false) or just getgc()
            return
        end
        for _, func in ipairs(gc) do
            if type(func) == "function" then
                funcCount = funcCount + 1
                pcall(function()
                    local ups = safeGetUpvalues(func)
                    for _, upv in pairs(ups) do
                        if type(upv) == "table" then
                            tbls[#tbls+1] = upv
                        end
                    end
                end)
            end
        end
        log("API", "Upvalue scan: " .. funcCount .. " functions → " .. #tbls .. " tables")
    end)
    return tbls
end

-- Strategy 7: getfenv on functions
local function gatherTablesFromEnv()
    local tbls = {}
    if not HAS.getgc or not getfenv then return tbls end
    pcall(function()
        local ok, gc = pcall(HAS.getgc)
        if not ok or type(gc) ~= "table" then return end
        local envs = 0
        for _, func in ipairs(gc) do
            if type(func) == "function" then
                pcall(function()
                    local env = getfenv(func)
                    if type(env) == "table" and env ~= _G and env ~= getfenv(0) then
                        envs = envs + 1
                        tbls[#tbls+1] = env
                        -- Check for a "shared" or "modules" key in the env
                        pcall(function()
                            for k, v in pairs(env) do
                                if type(v) == "table" and type(k) == "string" then
                                    tbls[#tbls+1] = v
                                end
                            end
                        end)
                    end
                end)
            end
        end
        log("API", "Env scan: " .. envs .. " unique envs → " .. #tbls .. " tables")
    end)
    return tbls
end

-- Strategy 8: getscripts / getrunningscripts
local function gatherTablesFromScripts()
    local tbls = {}
    local scriptFunc = HAS.getscripts or HAS.getrunningscripts
    if not scriptFunc then return tbls end
    pcall(function()
        local scripts = scriptFunc()
        if type(scripts) ~= "table" then return end
        local count = 0
        for _, scr in ipairs(scripts) do
            if typeof(scr) == "Instance" and scr:IsA("ModuleScript") then
                count = count + 1
                pcall(function()
                    local mod = require(scr)
                    if type(mod) == "table" then
                        tbls[#tbls+1] = mod
                        pcall(function()
                            for k, v in pairs(mod) do
                                if type(v) == "table" and type(k) == "string" then
                                    tbls[#tbls+1] = v
                                end
                            end
                        end)
                    end
                end)
            end
        end
        log("API", "Scripts scan: " .. count .. " ModuleScripts → " .. #tbls .. " tables")
    end)
    return tbls
end

-- ============================================================
-- DEDUPLICATE and EXPAND a set of tables
-- ============================================================
local function deduplicateAndExpand(tableLists)
    local seen = {}
    local all = {}
    local function add(t)
        if type(t) == "table" and not seen[t] then
            seen[t] = true
            all[#all+1] = t
        end
    end
    
    -- Add all from every list
    for _, list in ipairs(tableLists) do
        for _, t in ipairs(list) do add(t) end
    end
    
    -- Expand one level deep
    local firstPassCount = #all
    for i = 1, firstPassCount do
        pcall(function()
            for k, v in pairs(all[i]) do
                if type(v) == "table" and type(k) == "string" then add(v) end
            end
        end)
    end
    
    return all
end

-- ============================================================
-- BUILD SYNTHETIC API from individual module signatures
-- ============================================================
local function buildSyntheticAPI(allTables)
    local synthetic = {}
    local found = {}
    for _, sig in ipairs(MODULE_SIGNATURES) do
        local moduleName = sig[1]
        local bestScore, bestTable = 0, nil
        for _, tbl in ipairs(allTables) do
            local alreadyUsed = false
            for _, assigned in pairs(found) do
                if assigned == tbl then alreadyUsed = true; break end
            end
            if not alreadyUsed then
                local score = matchSignature(tbl, sig)
                if score > bestScore then
                    bestScore = score; bestTable = tbl
                end
            end
        end
        if bestTable and bestScore > 0 then
            synthetic[moduleName] = bestTable
            found[moduleName] = bestTable
            log("API", "  Sig match: '" .. moduleName .. "' score=" .. bestScore)
        end
    end
    return synthetic, found
end

-- ============================================================
-- DIAGNOSTIC DUMP — shows everything found
-- ============================================================
local function dumpDiagnostic(allTables)
    log("DIAG", "=== DIAGNOSTIC DUMP (" .. #allTables .. " tables total) ===")
    local candidates = {}
    for _, obj in ipairs(allTables) do
        pcall(function()
            local keys = {}
            local fc, tc = 0, 0
            for k, v in pairs(obj) do
                if type(k) == "string" then
                    keys[#keys+1] = k
                    if type(v) == "function" then fc = fc + 1 end
                    if type(v) == "table" then tc = tc + 1 end
                end
                if #keys > 40 then break end
            end
            if #keys >= 1 then
                candidates[#candidates+1] = {keys = keys, f = fc, t = tc}
            end
        end)
    end
    table.sort(candidates, function(a, b) return (#a.keys) > (#b.keys) end)
    log("DIAG", #candidates .. " tables with string keys")
    for i, c in ipairs(candidates) do
        if i > 40 then log("DIAG", "... +" .. (#candidates - 40) .. " more"); break end
        table.sort(c.keys)
        local ks = table.concat(c.keys, ", ")
        if #ks > 400 then ks = ks:sub(1, 400) .. "..." end
        log("DIAG", string.format("  #%d [%df %dt %dk]: %s", i, c.f, c.t, #c.keys, ks))
    end
    log("DIAG", "=== END DUMP === Please share output above.")
end

-- ============================================================
-- MAIN DISCOVERY LOOP
-- ============================================================
task.spawn(function()
    local attempts = 0
    local diagnosticDone = false
    
    while not gameAPI do
        attempts = attempts + 1
        
        -- On each attempt, gather tables from progressively more sources
        local sources = {}
        
        -- Always try these
        sources[#sources+1] = gatherTablesFromGC()
        sources[#sources+1] = gatherTablesFromRegistry()
        sources[#sources+1] = gatherTablesFromGetreg()
        
        -- From attempt 2+: try connections and upvalues
        if attempts >= 2 then
            sources[#sources+1] = gatherTablesFromConnections()
            sources[#sources+1] = gatherTablesFromUpvalues()
        end
        
        -- From attempt 3+: try require and env
        if attempts >= 3 then
            sources[#sources+1] = gatherTablesFromRequire()
            sources[#sources+1] = gatherTablesFromEnv()
            sources[#sources+1] = gatherTablesFromScripts()
        end
        
        -- Deduplicate and expand
        local allTables = deduplicateAndExpand(sources)
        if attempts <= 3 or attempts % 10 == 0 then
            log("API", "Attempt " .. attempts .. ": " .. #allTables .. " unique tables to scan")
        end
        
        -- STRATEGY 1: Classic shared table (rawget Utilities)
        for _, t in ipairs(allTables) do
            pcall(function()
                if rawget(t, "Utilities") and type(rawget(t, "Utilities")) == "table" then
                    for _, ck in ipairs({"Battle", "Network", "Menu", "DataManager", "BattleGui"}) do
                        if rawget(t, ck) then
                            gameAPI = t
                            log("API", "Found shared table via Utilities key!")
                            return
                        end
                    end
                end
            end)
            if gameAPI then break end
        end
        
        -- STRATEGY 2: Scoring-based
        if not gameAPI then
            local bestScore, bestTable, bestKeys = 0, nil, {}
            for _, t in ipairs(allTables) do
                local score, matched = scoreSharedTable(t)
                if score > bestScore then
                    bestScore = score; bestTable = t; bestKeys = matched
                end
            end
            local threshold = (attempts < 5 and 15) or (attempts < 10 and 8) or 3
            if bestScore >= threshold then
                gameAPI = bestTable
                log("API", string.format("Shared table via scoring! Score=%d Keys=[%s]",
                    bestScore, table.concat(bestKeys, ", ")))
            end
        end
        
        -- STRATEGY 3: Build synthetic API
        if not gameAPI and attempts >= 3 then
            local synthetic, found = buildSyntheticAPI(allTables)
            local coreCount = 0
            for _, cn in ipairs({"Battle", "Network", "Menu", "DataManager", "BattleGui"}) do
                if synthetic[cn] then coreCount = coreCount + 1 end
            end
            local total = 0
            for _ in pairs(found) do total = total + 1 end
            
            if coreCount >= 2 or total >= 4 then
                gameAPI = synthetic
                log("API", string.format("Synthetic gameAPI! %d modules (%d core)", total, coreCount))
            elseif total > 0 and attempts >= 8 then
                gameAPI = synthetic
                log("API", string.format("Partial synthetic accepted: %d modules after %d attempts", total, attempts))
            elseif attempts <= 5 or attempts % 10 == 0 then
                log("API", string.format("Synthetic: %d modules (%d core) — not enough", total, coreCount))
            end
        end
        
        -- Diagnostic dump on attempt 5
        if not gameAPI and attempts == 5 and not diagnosticDone then
            diagnosticDone = true
            dumpDiagnostic(allTables)
        end
        
        if not gameAPI then
            if attempts % 10 == 0 then
                log("API", "Still searching... attempt " .. attempts)
            end
            task.wait(1)
        end
    end
    
    -- Log what we found
    local foundKeys = {}
    pcall(function()
        for k, v in pairs(gameAPI) do
            if type(k) == "string" then foundKeys[#foundKeys+1] = k .. "(" .. type(v) .. ")" end
        end
    end)
    table.sort(foundKeys)
    log("API", "gameAPI modules: " .. table.concat(foundKeys, ", "))
    
    -- ============================================================
    -- INSTALL HOOKS
    -- ============================================================
    local Battle = gameAPI.Battle
    local DataMgr = gameAPI.DataManager
    local Net = gameAPI.Network
    local BGui = gameAPI.BattleGui
    local MenuMod = gameAPI.Menu
    local MC = gameAPI.MasterControl
    
    pcall(function()
        if Battle and Battle.setupScene then
            local old = Battle.setupScene
            Battle.setupScene = function(...) setThreadContext(2); return old(...) end
            log("HOOK", "Battle.setupScene hooked")
        end
    end)
    pcall(function()
        if DataMgr and DataMgr.loadModule then
            local old = DataMgr.loadModule
            DataMgr.loadModule = function(...) setThreadContext(2); return old(...) end
            log("HOOK", "DataManager.loadModule hooked")
        end
    end)
    pcall(function()
        if DataMgr and DataMgr.loadChunk then
            local old = DataMgr.loadChunk
            DataMgr.loadChunk = function(...) setThreadContext(2); return old(...) end
            log("HOOK", "DataManager.loadChunk hooked")
        end
    end)
    pcall(function()
        if Battle and Battle.doTrainerBattle then
            local old = Battle.doTrainerBattle
            Battle.doTrainerBattle = function(...)
                if config.autoHealEnabled and Net then
                    local maxWait = 60; local start = tick()
                    while (tick() - start) < maxWait do
                        local ok2, fullHP = pcall(function() return Net:get("PDS", "areFullHealth") end)
                        if ok2 and fullHP then break end
                        task.wait(0.5)
                    end
                end
                setThreadContext(2); return old(...)
            end
            log("HOOK", "Battle.doTrainerBattle hooked")
        end
    end)
    pcall(function()
        if BGui and BGui.switchMonster then
            local old = BGui.switchMonster
            BGui.switchMonster = function(...) setThreadContext(2); return old(...) end
            log("HOOK", "BattleGui.switchMonster hooked")
        end
    end)
    pcall(function()
        if MenuMod and MenuMod.mastery and MenuMod.mastery.showProgressUpdate then
            local old = MenuMod.mastery.showProgressUpdate
            MenuMod.mastery.showProgressUpdate = function(...)
                if config.masteryDisable then return end
                return old(...)
            end
            log("HOOK", "Menu.mastery.showProgressUpdate hooked")
        end
    end)
    pcall(function()
        if MenuMod and MenuMod.options then
            MenuMod.options.resetLastUnstuckTick = function() end
            log("HOOK", "Unstuck cooldown removed")
        end
    end)
    
    -- FOV fix
    task.spawn(function()
        while task.wait(0.5) do
            pcall(function()
                if MC and MC.WalkEnabled then
                    local inBattle = false
                    pcall(function() inBattle = Battle and Battle.currentBattle ~= nil end)
                    if not inBattle then workspace.Camera.FieldOfView = 70 end
                end
            end)
        end
    end)
    
    gameAPIReady = true
    log("INFO", "All gameAPI hooks installed. LumiWare is ready.")
end)

--------------------------------------------------
-- RARE LOOMIANS
--------------------------------------------------
local RARE_LOOMIANS = {
    "Duskit", "Ikazune", "Mutagon", "Metronette", "Wabalisc",
    "Cephalops", "Elephage", "Gargolem", "Celesting", "Nyxre", "Pyramind",
    "Terracolt", "Garbantis", "Avitross", "Snocub", "Eaglit", "Grimyuline",
    "Vambat", "Weevolt", "Nevermare", "Ikazune", "Protogon", "Mimask", "Odoyaga",
    "Akhalos", "Odasho", "Cosmiore", "Dakuda", "Shawchi", "Arceros", "Galacadia"
}
UI.customRares = config.customRares or {}

local RARE_MODIFIERS = {
    "gleam", "gleaming", "gamma", "corrupt", "corrupted",
    "alpha", "iridescent", "metallic", "rainbow",
    "sa ", "pn ", "hw ", "ny ",
    "secret", "shiny", "radiant",
}

local function isRareModifier(name)
    if type(name) ~= "string" then return false end
    local l = string.lower(name)
    for _, mod in ipairs(RARE_MODIFIERS) do
        if string.find(l, mod) then return true end
    end
    return false
end

local RARE_KEYWORDS_DEEP = {
    "gleam", "gamma", "corrupt", "alpha",
    "iridescent", "metallic", "rainbow", "shiny", "radiant", "secret",
}

local function deepScanForRare(value, depth)
    if depth > 5 then return false end
    depth = depth or 0
    if type(value) == "string" then
        local l = string.lower(value)
        for _, kw in ipairs(RARE_KEYWORDS_DEEP) do
            if string.find(l, kw) then
                log("RARE", "Deep scan HIT: keyword=" .. kw .. " in string=" .. string.sub(value, 1, 60))
                return true
            end
        end
    elseif type(value) == "table" then
        for k, v in pairs(value) do
            if type(k) == "string" then
                local kl = string.lower(k)
                if kl == "variant" or kl == "gleam" or kl == "gamma" or kl == "corrupt"
                    or kl == "issecret" or kl == "isgleam" or kl == "isgamma" then
                    if v == true or v == 1 or (type(v) == "string" and v ~= "" and v ~= "false" and v ~= "0") then
                        log("RARE", "Deep scan HIT: key=" .. k .. " val=" .. tostring(v))
                        return true
                    end
                end
            end
            if deepScanForRare(v, depth + 1) then return true end
        end
    end
    return false
end

local function scanEntryForRare(entry)
    if type(entry) ~= "table" then return false end
    for i = 1, #entry do
        local v = entry[i]
        if type(v) == "string" then
            if isRareModifier(v) then return true end
        elseif type(v) == "table" then
            if deepScanForRare(v, 0) then return true end
        end
    end
    return false
end

local function isRareLoomian(name)
    local l = string.lower(name)
    for _, r in ipairs(RARE_LOOMIANS) do
        if string.find(l, string.lower(r)) then return true end
    end
    for _, r in ipairs(UI.customRares) do
        if string.find(l, string.lower(r)) then return true end
    end
    return false
end

--------------------------------------------------
-- MASTERY DATA (135 families)
--------------------------------------------------
local MASTERY_DATA = {
    {f="Embit/Rabburn/Searknight",t={{"D",0,200},{"E",30000,300},{"R",50,400},{"K",30,100}}},
    {f="Dripple/Reptide/Luminami",t={{"D",0,200},{"E",30000,300},{"R",50,400},{"K",30,100}}},
    {f="Fevine/Felver/Tahtab",t={{"D",0,200},{"E",30000,300},{"R",50,400},{"K",30,100}}},
    {f="Eaglit/Torprey/Falkyrie",t={{"D",0,200},{"E",30000,300},{"R",50,400},{"K",30,100}}},
    {f="Vambat/Dimpire/Vesperatu",t={{"D",0,200},{"E",30000,300},{"R",50,400},{"K",30,100}}},
    {f="Snocub/Snowki/Himbrr",t={{"D",0,200},{"E",30000,300},{"R",50,400},{"K",30,100}}},
    {f="Weevolt/Stozap/Zuelong",t={{"D",0,200},{"E",30000,300},{"R",50,400},{"K",30,100}}},
    {f="Twilat/Umbrat/Luxoar/Tiklipse",t={{"D",0,200},{"C",10,200},{"K",20,400},{"R",10,200}}},
    {f="Cathorn/Propae/Cynamoth/Sumobito",t={{"E",20000,300},{"PA",10,200},{"SL",10,200},{"K",25,300}}},
    {f="Twittle/Paratweet/Avitross",t={{"DD",1000,300},{"C",5,200},{"E",20000,300},{"K",15,200}}},
    {f="Pyder/Swolder",t={{"R",20,300},{"LU",30,200},{"DD",1000,200},{"C",5,300}}},
    {f="Antsee/Florant",t={{"E",20000,300},{"C",5,200},{"R",20,400},{"K",10,100}}},
    {f="Grubby/Coonucopia/Terrafly/Terraclaw",t={{"K",20,300},{"C",5,200},{"LU",30,400},{"D",0,100}}},
    {f="Kleptyke/Ragoon",t={{"DD",800,200},{"K",10,400},{"R",20,100},{"C",5,300}}},
    {f="Babore/Boarrok",t={{"E",20000,300},{"C",5,200},{"K",15,200},{"KSE",15,300}}},
    {f="Geklow/Eleguana",t={{"FB",0,500},{"R",5,100},{"KSE",5,200},{"DC",10,200}}},
    {f="Slugling/Escargrow/Gastroak",t={{"K",15,300},{"R",10,200},{"C",5,200},{"E",20000,300}}},
    {f="Kabunga/Wiki-Wiki/Chartiki/Waka-Laka/Thawmin",t={{"D",3,400},{"R",10,200},{"K",15,200},{"E",15000,200}}},
    {f="Shawchi",t={{"K",5,300},{"C",5,400},{"R",5,100},{"DD",1000,200}}},
    {f="Rakrawla/Sedimars",t={{"LU",30,300},{"C",5,200},{"K",10,300},{"DD",500,200}}},
    {f="Gumpod/Ventacean",t={{"BU",5,400},{"FB",0,400},{"KSE",5,100},{"R",5,100}}},
    {f="Phancub/Ursoul/Ursnac",t={{"K",10,200},{"R",10,200},{"E",15000,200},{"FB",0,400}}},
    {f="Whispup/Revenine",t={{"LU",30,300},{"C",5,200},{"K",30,300},{"KSE",15,200}}},
    {f="Skilava/Geksplode/Eruptidon",t={{"DD",1000,300},{"K",20,200},{"K",15,200},{"DC",15,300}}},
    {f="Craytal/Krakaloa/Volkaloa/Festifir/Leshent",t={{"D",3,400},{"R",15,200},{"DD",1000,200},{"KSE",10,200}}},
    {f="Igneol/Chrysite/Obsidrugon",t={{"C",2,300},{"LU",30,300},{"R",10,200},{"D",0,200}}},
    {f="Cafnote/Trumbull/Mootune",t={{"D",0,300},{"E",15000,200},{"C",5,200},{"FB",0,300}}},
    {f="Gobbidemic",t={{"C",5,300},{"R",10,200},{"K",5,200},{"KSE",15,300}}},
    {f="Icigool",t={{"E",20000,300},{"K",30,400},{"KSE",15,300}}},
    {f="Pyramind/Pharoglyph",t={{"D",0,500},{"C",3,300},{"K",20,200}}},
    {f="Burroach/Garbantis",t={{"C",3,200},{"K",15,200},{"E",20000,300},{"R",10,300}}},
    {f="Whimpor/Stratusoar",t={{"DD",1000,200},{"FB",0,300},{"R",10,200},{"KSE",15,300}}},
    {f="Territi/Dyeborg",t={{"LU",30,200},{"C",5,200},{"K",40,400},{"DD",1000,200}}},
    {f="Operaptor/Concredon/Tyrecks",t={{"K",3,300},{"E",20000,300},{"DD",2000,300},{"R",10,100}}},
    {f="Chompactor/Munchweel",t={{"C",5,200},{"K",10,200},{"E",20000,400},{"KSE",5,200}}},
    {f="Scorb/Veylens/Gardrone",t={{"D",0,400},{"PA",1,200},{"BU",1,200},{"FR",1,200}}},
    {f="Poochrol/Hunder",t={{"K",35,200},{"LU",30,200},{"DD",1500,200},{"FB",0,300}}},
    {f="Goppie/Arapaigo",t={{"C",10,300},{"K",20,200},{"E",20000,200},{"R",20,300}}},
    {f="Pyke/Skelic",t={{"D",0,500},{"E",25000,500}}},
    {f="Zaleo/Joltooth",t={{"D",0,500},{"E",25000,500}}},
    {f="Dobo/Infernix",t={{"D",0,500},{"E",25000,500}}},
    {f="Kyogo/Dorogo",t={{"D",0,500},{"E",25000,500}}},
    {f="Wiledile/Mawamurk",t={{"K",15,200},{"DC",10,400},{"R",20,200},{"LU",45,200}}},
    {f="Ampole/Amphiton/Meditoad",t={{"C",5,200},{"E",20000,300},{"PA",10,200},{"KSE",15,300}}},
    {f="Pwuff/Bloatox/Barblast",t={{"C",5,200},{"LU",40,100},{"DC",10,400},{"PO",10,300}}},
    {f="Swimp/Snapr/Garlash",t={{"K",15,200},{"R",20,200},{"E",20000,300},{"KSE",15,300}}},
    {f="Hydrini/Bezeldew/Deludrix",t={{"D",0,300},{"K",45,200},{"E",20000,200},{"KSE",15,300}}},
    {f="Ceratot/Trepodon/Colossotrops",t={{"D",0,500},{"E",30000,500}}},
    {f="Cupoink/Hoganosh",t={{"KSE",15,200},{"BU",5,300},{"E",20000,200},{"DD",2000,300}}},
    {f="Mochibi/Totemochi/Mocho",t={{"KSE",15,200},{"FR",3,300},{"E",20000,200},{"DD",2000,300}}},
    {f="Gwurm/Odasho/Spreezy",t={{"KSE",15,200},{"R",20,300},{"E",20000,200},{"DD",2000,300}}},
    {f="Pipsee/Dandylil/Whippledriff",t={{"D",0,300},{"K",45,200},{"E",20000,200},{"KSE",15,300}}},
    {f="Vari/Cervolen/Wendolen/+evos",t={{"C",1,400},{"E",20000,200},{"R",20,200},{"KSE",15,200}}},
    {f="Copling/Copperage/Oxidrake",t={{"KSE",10,200},{"E",20000,300},{"D",0,200},{"C",3,300}}},
    {f="Spirivii/Eidohusk/Harvesect",t={{"D",0,200},{"E",20000,300},{"K",30,300},{"R",10,200}}},
    {f="Snowl/Stricicle/Wintrix",t={{"E",20000,300},{"R",10,200},{"KSE",10,200},{"FR",2,300}}},
    {f="Snagull/Snagulp/Snagoop",t={{"PO",5,300},{"C",5,200},{"DD",2000,300},{"R",10,200}}},
    {f="Makame/Makoro/Tsukame",t={{"C",3,300},{"E",20000,200},{"KSE",5,200},{"DD",3000,300}}},
    {f="Cavenish/Banfino",t={{"K",25,300},{"DD",2000,300},{"R",10,200},{"E",20000,200}}},
    {f="Kanki/Kanibo",t={{"K",30,300},{"C",5,200},{"E",20000,300},{"DD",2000,200}}},
    {f="Sharpod/Samarine",t={{"KSE",15,400},{"E",20000,100},{"C",3,300},{"DD",2000,200}}},
    {f="Lumica/Lumello",t={{"PO",5,400},{"E",20000,300},{"C",4,200},{"R",10,100}}},
    {f="Polypi/Laphyra/Jellusa",t={{"K",20,300},{"C",5,200},{"R",10,300},{"E",20000,200}}},
    {f="Taoshi/Taoshinu",t={{"C",5,300},{"K",30,200},{"R",20,200},{"DD",3000,300}}},
    {f="Kittone/Lyricat",t={{"R",25,300},{"C",5,200},{"DD",2000,200},{"E",25000,300}}},
    {f="Boonary",t={{"K",30,300},{"E",20000,300},{"DD",3000,400}}},
    {f="Somata/Clionae",t={{"E",20000,200},{"K",15,300},{"R",5,200},{"DD",2000,300}}},
    {f="Cinnaboo/Cinnogre",t={{"E",20000,300},{"R",25,200},{"DD",2000,200},{"KSE",5,300}}},
    {f="Swirelle",t={{"E",20000,300},{"DD",2000,200},{"KSE",5,300},{"R",20,200}}},
    {f="Swishy/Fiscarna",t={{"E",20000,300},{"DD",2000,200},{"KSE",5,300},{"R",20,200}}},
    {f="Bunpuff/Bunnecki",t={{"E",20000,300},{"DD",2000,200},{"KSE",5,300},{"R",20,200}}},
    {f="Dractus/Frutress/Seedrake",t={{"E",20000,300},{"DD",2000,200},{"KSE",5,300},{"R",20,200}}},
    {f="Volpup/Halvantic",t={{"E",20000,300},{"DD",2000,200},{"KSE",5,300},{"R",20,200}}},
    {f="Impkin/Grimmick/Imperior",t={{"E",20000,300},{"DD",2000,200},{"KSE",5,300},{"R",20,200}}},
    {f="Mistlebud/Hollibunch",t={{"E",20000,300},{"DD",2000,200},{"KSE",5,300},{"R",20,200}}},
    {f="Cryocub/Barbadger",t={{"E",20000,300},{"DD",2000,200},{"KSE",5,300},{"R",20,200}}},
    {f="Kyeggo/Doreggo/Dreggodyne",t={{"DD",2500,300},{"R",10,200},{"KSE",8,200},{"E",25000,300}}},
    {f="Wispur/Lampurge/Charonyx",t={{"D",0,300},{"K",45,200},{"E",20000,200},{"KSE",15,300}}},
    {f="Smoal/Charkiln/Billoforge",t={{"D",0,300},{"K",45,200},{"E",20000,200},{"KSE",15,300}}},
    {f="Sherbot",t={{"E",20000,200},{"KSE",6,300},{"R",10,300},{"DD",2000,200}}},
    {f="Llamba/Choochew/Loomala",t={{"D",0,400},{"C",1,200},{"R",10,100},{"DD",2000,200}}},
    {f="Fentern/Weaselin",t={{"R",10,200},{"DD",1500,200},{"C",3,400},{"E",20000,200}}},
    {f="Singeel/Moreel",t={{"DD",2000,200},{"C",5,300},{"E",20000,400},{"R",5,100}}},
    {f="Crabushi/Crabtana",t={{"C",5,200},{"K",10,300},{"R",10,300},{"DD",2000,200}}},
    {f="Teripod/Teridescent",t={{"KSE",10,200},{"DD",1500,300},{"R",5,300},{"E",15000,200}}},
    {f="Skampi/Prawnsu/Shrimposte",t={{"D",0,400},{"C",5,200},{"R",10,200},{"DD",1000,200}}},
    {f="Dokan/Dokumori",t={{"KSE",10,200},{"DD",1500,300},{"R",5,300},{"E",15000,200}}},
    {f="Mirrami/Mirraith",t={{"R",10,300},{"DD",2000,300},{"E",10000,200},{"KSE",5,200}}},
    {f="Kayute/Kayappa/Kramboss",t={{"E",10000,300},{"DD",1000,200},{"KSE",10,200},{"R",10,300}}},
    {f="Leopaw/Chienta",t={{"E",10000,200},{"DD",1000,300},{"KSE",10,300},{"R",10,200}}},
    {f="Eyebrella/Parasoul",t={{"K",5,400},{"E",10000,300},{"DD",2000,200},{"R",5,100}}},
    {f="Lissen/Biwarned",t={{"K",5,400},{"E",10000,300},{"DD",2000,200},{"R",5,100}}},
    {f="Lantot/Lantorch",t={{"K",5,400},{"E",10000,300},{"DD",2000,200},{"R",5,100}}},
    {f="Milgoo/Rancidor",t={{"K",5,400},{"E",10000,300},{"DD",2000,200},{"R",5,100}}},
    {f="Nautling/Nautillect/Naukout",t={{"D",0,500},{"E",20000,500}}},
    {f="Yutiny/Yuteen/Yutyphoon",t={{"D",0,500},{"E",20000,500}}},
    {f="Venile/Verinox/Verinosaur",t={{"D",0,500},{"E",20000,500}}},
    {f="Nymvolt/Ohmbolt/Plasmoth",t={{"D",0,300},{"K",35,200},{"E",20000,200},{"KSE",10,300}}},
    {f="Cicalute/Violana",t={{"DD",1000,200},{"R",15,300},{"KSE",10,300},{"LU",15,200}}},
    {f="Goswing/Ganderveil",t={{"DC",5,300},{"K",20,200},{"E",15000,200},{"R",10,300}}},
    {f="Banooh/Banokey",t={{"DD",1500,300},{"K",20,300},{"R",20,200},{"LU",15,200}}},
    {f="Spirwix/Malevowax",t={{"BU",5,300},{"KSE",10,200},{"R",20,200},{"LU",15,300}}},
    {f="Grievestone/Obelost",t={{"FB",0,300},{"K",20,200},{"R",20,200},{"E",15000,300}}},
    {f="Jimby/Piccolio",t={{"DD",1300,300},{"K",20,300},{"R",15,200},{"E",12000,200}}},
    {f="Wassel/Borealisk",t={{"K",20,300},{"DD",1000,200},{"R",10,200},{"LU",25,300}}},
    {f="Snicle/Slivyce",t={{"LU",15,200},{"R",10,300},{"KSE",10,300},{"DD",1000,200}}},
    {f="Nukichi/Dainuki",t={{"R",5,200},{"DD",1000,200},{"LU",15,300},{"FB",0,300}}},
    {f="Terracolt/Broncotta",t={{"R",5,200},{"KSE",10,300},{"DD",1000,300},{"E",10000,200}}},
    {f="Duskit",t={{"C",1,500},{"E",30000,500}}},
    {f="Ikazune",t={{"C",1,500},{"E",30000,500}}},
    {f="Protogon",t={{"C",1,500},{"E",30000,500}}},
    {f="Dakuda",t={{"C",1,500},{"E",20000,500}}},
    {f="Cosmeleon",t={{"C",1,500},{"E",20000,500}}},
    {f="Mutagon",t={{"C",1,500},{"E",30000,500}}},
    {f="Cephalops",t={{"C",1,500},{"K",35,500}}},
    {f="Elephage/Phagenaut",t={{"C",1,500},{"E",30000,500}}},
    {f="Glacadia",t={{"C",1,500},{"E",20000,500}}},
    {f="Arceros",t={{"C",1,500},{"E",20000,500}}},
    {f="Novadeaus",t={{"E",20000,1000}}},
    {f="Morphezu",t={{"E",20000,1000}}},
    {f="Behemoroth",t={{"E",20000,1000}}},
    {f="Leviatross",t={{"E",20000,1000}}},
    {f="Cosmiore",t={{"C",1,500},{"E",30000,500}}},
    {f="Solnecta",t={{"C",1,500},{"K",35,500}}},
    {f="Nymaurae",t={{"C",1,500},{"K",35,500}}},
    {f="Nymesis",t={{"C",1,500},{"K",35,500}}},
    {f="Metronette",t={{"C",1,1000}}},
    {f="Nevermare",t={{"C",1,500},{"K",35,500}}},
    {f="Gargolem",t={{"C",1,500},{"E",30000,500}}},
    {f="Odoyaga",t={{"C",1,500},{"E",20000,500}}},
    {f="Wabalisc",t={{"C",1,500},{"E",30000,500}}},
    {f="Akhalos",t={{"C",1,500},{"E",30000,500}}},
    {f="Celesting",t={{"C",1,500},{"E",30000,500}}},
    {f="Mimask",t={{"C",1,500},{"E",20000,500}}},
    {f="Grimyuline",t={{"C",1,500},{"E",20000,500}}},
}

local TASK_NAMES = {
    D="Discover all stages", E="Earn Experience", R="Rally", K="KO Loomians",
    C="Capture", DD="Deal Damage", KSE="KO w/ Super Effective", DC="Deal Crits",
    LU="Level Up", FB="Form Perfect Bond", BU="Burn Loomians", PA="Paralyze",
    SL="Put to Sleep", PO="Poison Loomians", FR="Inflict Frostbite"
}

local function searchMastery(query)
    if not query or query == "" then return {} end
    local q = string.lower(query)
    local results = {}
    for _, entry in ipairs(MASTERY_DATA) do
        if string.find(string.lower(entry.f), q) then
            table.insert(results, entry)
        end
    end
    return results
end

local sessionKOs = 0
local sessionDamage = 0

local function sendNotification(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = duration or 5 })
    end)
end

local function playRareSound()
    pcall(function()
        local s = Instance.new("Sound")
        s.SoundId = "rbxassetid://6518811702"
        s.Volume = 1
        s.Parent = SoundService
        s:Play()
        task.delay(3, function() s:Destroy() end)
    end)
end

--------------------------------------------------
-- WEBHOOK
--------------------------------------------------
local webhookUrl = config.webhookUrl or ""

local function sendWebhook(embedData, contentText)
    if webhookUrl == "" then return end
    pcall(function()
        local payloadObj = { username = "LumiWare", embeds = { embedData } }
        if contentText then payloadObj.content = contentText end
        local payload = HttpService:JSONEncode(payloadObj)
        local httpFunc = (syn and syn.request) or (http and http.request) or request or http_request
        if httpFunc then
            httpFunc({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = payload })
        end
    end)
end

local function getRarityTier(name)
    local l = string.lower(name)
    local superRares = {"duskit", "ikazune", "mutagon", "protogon", "metronette", "wabalisc", "cephalops", "elephage", "gargolem", "celesting", "nyxre", "odasho", "cosmiore", "armenti", "nevermare", "akhalos"}
    for _, r in ipairs(superRares) do
        if string.find(l, r) then return "SUPER RARE" end
    end
    if string.find(l, "gamma") then return "GAMMA RARE" end
    if string.find(l, "gleam") then return "GLEAMING RARE" end
    if string.find(l, "corrupt") then return "CORRUPT" end
    if string.find(l, "sa ") or string.find(l, "secret") then return "SECRET ABILITY" end
    return "RARE"
end

local function sendRareWebhook(name, level, gender, enc, huntTime)
    local rarityTier = getRarityTier(name)
    sendWebhook({
        title = "⭐ " .. rarityTier .. " FOUND!", description = "**" .. name .. "** detected!",
        color = 16766720,
        fields = {
            { name = "Rarity Tier", value = rarityTier, inline = true },
            { name = "Loomian", value = name, inline = true },
            { name = "Level", value = tostring(level or "?"), inline = true },
            { name = "Gender", value = gender or "?", inline = true },
            { name = "Encounters", value = tostring(enc), inline = true },
            { name = "Hunt Time", value = huntTime or "?", inline = true },
            { name = "Player", value = PLAYER_NAME, inline = true },
        },
        footer = { text = "LumiWare " .. VERSION .. " • " .. os.date("%X") },
    }, "@everyone")
end

local function sendSessionWebhook(enc, huntTime, rares)
    sendWebhook({
        title = "📊 Session Summary", description = "LumiWare session update",
        color = 7930367,
        fields = {
            { name = "Encounters", value = tostring(enc), inline = true },
            { name = "Hunt Time", value = huntTime, inline = true },
            { name = "Rares", value = tostring(rares), inline = true },
            { name = "Player", value = PLAYER_NAME, inline = true },
        },
        footer = { text = "LumiWare " .. VERSION .. " • " .. os.date("%X") },
    })
end

--------------------------------------------------
-- STATE
--------------------------------------------------
UI.encounterCount = 0
UI.huntStartTime = tick()
local currentEnemy = nil
local isMinimized = false
local battleState = "idle"
local lastBattleTick = 0
local raresFoundCount = 0
UI.encounterHistory = {}
local discoveryMode = false

-- Automation state
local autoMode = config.autoMode or "off"
local autoMoveSlot = config.autoMoveSlot or 1
local autoWalkEnabled = false
local autoWalkThread = nil
local rareFoundPause = false
local pendingAutoAction = false

-- NEW v4.6: Trainer automation
local trainerAutoMode = config.trainerAutoMode or "off"
local trainerAutoMoveSlot = config.trainerAutoMoveSlot or 1

-- Keep track of whether fish/disc/mastery starts turned on
if config.autoDiscEnabled then
    task.spawn(function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/thedragonslayer2/MrJack-Game-List/main/Functions/Loomian%20Legacy%20-%20306964494/Disc%20Drop.lua"))()
        if getgenv().LoomianLegacyAutoDisDrop then
            local autoDropOn, getGui = getgenv().LoomianLegacyAutoDisDrop(config, gameAPI)
            task.spawn(function()
                while config.autoDiscEnabled and task.wait() do
                    pcall(function()
                        if gameAPI.ArcadeController.playing and getGui() and getGui().gui.GridFrame:IsDescendantOf(client.PlayerGui) then
                            if getGui().gameEnded then
                                getGui():CleanUp()
                                getGui():new()
                            else
                                autoDropOn()
                            end
                        end
                    end)
                end
            end)
        end
    end)
end

-- NEW v4.6: Auto-heal (state)
local autoHealEnabled = config.autoHealEnabled or false
local autoHealThreshold = config.autoHealThreshold or 30
local autoHealMethod = config.autoHealMethod or "remote"
local scannedHealRemotes = {}
local lastHealTime = 0
local healCooldown = 15  -- seconds between heals

-- Battle filter flags
UI.automateTrainer = (config.automateTrainer ~= false)
UI.automateWild = (config.automateWild ~= false)

local currentBattle = {
    active = false,
    enemy = nil,
    player = nil,
    enemyStats = nil,
    playerStats = nil,
    battleType = "N/A",
    enemyProcessed = false,
}

local function resetBattle()
    currentBattle = {
        active = false, enemy = nil, player = nil,
        enemyStats = nil, playerStats = nil,
        battleType = "N/A", enemyProcessed = false,
    }
end

--------------------------------------------------
-- GAME API ACTIONS
--------------------------------------------------
local isAutoHealing = false

local function performGameAPIHeal()
    if not gameAPI or not gameAPIReady then return end
    if isAutoHealing then return end -- Prevent re-entrancy
    
    local fullHealth = false
    pcall(function()
        fullHealth = gameAPI.Network:get("PDS", "areFullHealth")
    end)
    
    if fullHealth then return end
    
    -- Extra safety: don't heal during battle
    pcall(function()
        if gameAPI.Battle and gameAPI.Battle.currentBattle then
            return
        end
    end)
    
    -- Extra safety: don't heal if walk is disabled (already in a cutscene/menu)
    pcall(function()
        if not gameAPI.MasterControl.WalkEnabled or not gameAPI.Menu.enabled then
            return
        end
    end)
    
    log("HEAL", "Attempting gameAPI-based heal sequence...")
    isAutoHealing = true
    
    xpcall(function()
        local chunk = gameAPI.DataManager.currentChunk
        if not chunk then
            log("HEAL", "No current chunk, aborting heal")
            isAutoHealing = false
            return
        end
        
        -- Don't heal if indoors (matching original's check)
        if chunk.indoors then
            log("HEAL", "Indoors, skipping heal")
            isAutoHealing = false
            return
        end
        
        -- Method 1: If chunk has outdoor healers, use them directly
        if chunk.data and chunk.data.HasOutsideHealers then
            setThreadContext(2)
            gameAPI.Network:get("heal", nil, "HealMachine1")
            log("HEAL", "Used outdoor healer.")
            isAutoHealing = false
            return
        end
        
        -- Method 2: Teleport to health center (ported from original)
        local blackOutTarget = (chunk.regionData and chunk.regionData.BlackOutTo) or (chunk.data and chunk.data.blackOutTo)
        local originalChunkId = chunk.id
        local originalCFrame = nil
        pcall(function()
            originalCFrame = game.Players.LocalPlayer.Character.PrimaryPart.CFrame
        end)
        
        if blackOutTarget then
            local mc = gameAPI.MasterControl
            mc.WalkEnabled = false
            gameAPI.Menu:disable()
            pcall(function() gameAPI.Menu:fastClose(3) end)
            pcall(function() gameAPI.Utilities.FadeOut(1) end)
            task.spawn(function()
                pcall(function() gameAPI.NPCChat:Say("[ma][LumiWare]Auto healing...") end)
            end)
            pcall(function() gameAPI.Utilities.TeleportToSpawnBox() end)
            pcall(function() chunk:unbindIndoorCam() end)
            pcall(function() chunk:destroy() end)
            setThreadContext(2)
            chunk = gameAPI.DataManager:loadChunk(blackOutTarget)
        end
        
        -- Get the health center room and healer
        pcall(function()
            local room = chunk:getRoom("HealthCenter", chunk:getDoor("HealthCenter"), 1)
            task.wait()
            local healer = gameAPI.Network:get("getHealer", "HealthCenter")
            if healer then
                setThreadContext(2)
                gameAPI.Network:get("heal", "HealthCenter", healer)
            end
            if room then room:Destroy() end
        end)
        
        -- Return to original location if we teleported
        if blackOutTarget and originalChunkId then
            pcall(function() chunk:destroy() end)
            setThreadContext(2)
            pcall(function() gameAPI.DataManager:loadChunk(originalChunkId) end)
            if originalCFrame then
                pcall(function() gameAPI.Utilities.Teleport(originalCFrame) end)
            end
            pcall(function() gameAPI.Menu:enable() end)
            pcall(function() gameAPI.NPCChat:manualAdvance() end)
            pcall(function() gameAPI.Utilities.FadeIn(1) end)
            pcall(function() gameAPI.MasterControl.WalkEnabled = true end)
        end
    end, function(err)
        warn("[LumiWare][HEAL] Error:", err)
    end)
    
    isAutoHealing = false
    lastHealTime = tick()
end


-- Infinite Repel Loop — matches original logic:
-- When ON: always ensure steps >= 100
-- When OFF: set steps to 0 (cancel repel effect)
-- Runs every frame via game loop for reliability (original used LooP)
task.spawn(function()
    while task.wait(0.5) do
        pcall(function()
            if not gameAPI or not gameAPI.Repel then return end
            if config.infiniteRepel then
                if gameAPI.Repel.steps < 10 then
                    gameAPI.Repel.steps = 100
                    logDebug("Repel steps reset to 100.")
                end
            end
        end)
    end
end)

--------------------------------------------------
-- HELPERS
--------------------------------------------------
local function extractLoomianName(str)
    if not str then return "Unknown" end
    local formatted = str:gsub("-", " ")
    formatted = formatted:gsub("(%a)([%w_]*)", function(a, b) return string.upper(a) .. b end)
    return formatted
end

local function parseLoomianStats(infoStr)
    if type(infoStr) ~= "string" then return nil end
    local name, level, rest = infoStr:match("^(.+), L(%d+), (.+)$")
    if not level then return nil end
    local gender = rest and rest:match("^(%a)") or "?"
    local hp, maxHP = rest and rest:match("(%d+)/(%d+)") or nil, nil
    return { name = name, level = tonumber(level), gender = gender, hp = tonumber(hp), maxHP = tonumber(maxHP) }
end

local function formatTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then return string.format("%dh %02dm %02ds", h, m, s)
    else return string.format("%dm %02ds", m, s) end
end

local function tablePreview(tbl, depth)
    depth = depth or 0
    if depth > 2 then return "{...}" end
    local parts, count = {}, 0
    for k, v in pairs(tbl) do
        count = count + 1
        if count > 6 then table.insert(parts, "...") break end
        if type(v) == "table" then table.insert(parts, tostring(k) .. "=" .. tablePreview(v, depth + 1))
        else table.insert(parts, tostring(k) .. "=" .. tostring(v)) end
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

--------------------------------------------------
-- FULL CLEANUP
--------------------------------------------------
if _G.LumiWare_Cleanup then
    pcall(_G.LumiWare_Cleanup)
end

local allConnections = {}
local function track(connection)
    table.insert(allConnections, connection)
    return connection
end

_G.LumiWare_Cleanup = function()
    for _, conn in ipairs(allConnections) do
        pcall(function() conn:Disconnect() end)
    end
    allConnections = {}
    pcall(function()
        if _G.LumiWare_Threads then
            for _, th in ipairs(_G.LumiWare_Threads) do task.cancel(th) end
            _G.LumiWare_Threads = {}
        end
    end)
    pcall(function()
        if _G.LumiWare_WalkThread then
            task.cancel(_G.LumiWare_WalkThread)
            _G.LumiWare_WalkThread = nil
        end
    end)
    pcall(function()
        if _G.LumiWare_StopFlag then _G.LumiWare_StopFlag = true end
    end)
    pcall(function()
        for _, v in pairs(player:WaitForChild("PlayerGui"):GetChildren()) do
            if string.find(v.Name, "LumiWare_Hub") or v.Name == "BattleLoomianViewer" then v:Destroy() end
        end
    end)
    pcall(function()
        for _, v in pairs(CoreGui:GetChildren()) do
            if string.find(v.Name, "LumiWare_Hub") or v.Name == "BattleLoomianViewer" then v:Destroy() end
        end
    end)
    pcall(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
    end)
end

local guiName = "LumiWare_Hub_" .. tostring(math.random(1000, 9999))
for _, v in pairs(player:WaitForChild("PlayerGui"):GetChildren()) do
    if string.find(v.Name, "LumiWare_Hub") or v.Name == "BattleLoomianViewer" then v:Destroy() end
end
pcall(function()
    for _, v in pairs(CoreGui:GetChildren()) do
        if string.find(v.Name, "LumiWare_Hub") or v.Name == "BattleLoomianViewer" then v:Destroy() end
    end
end)

_G.LumiWare_StopFlag = false
_G.LumiWare_Threads = {}

local gui = Instance.new("ScreenGui")
gui.Name = guiName
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
local ok = pcall(function() gui.Parent = CoreGui end)
if not ok then gui.Parent = player:WaitForChild("PlayerGui") end

--------------------------------------------------
-- THEME
--------------------------------------------------
local C = {
    BG = Color3.fromRGB(13, 13, 18), TopBar = Color3.fromRGB(20, 20, 28),
    Accent = Color3.fromRGB(110, 80, 255), AccentDim = Color3.fromRGB(75, 55, 180),
    Text = Color3.fromRGB(245, 245, 250), TextDim = Color3.fromRGB(150, 150, 165),
    Panel = Color3.fromRGB(20, 20, 26), PanelAlt = Color3.fromRGB(26, 26, 34),
    Gold = Color3.fromRGB(255, 210, 50), Green = Color3.fromRGB(60, 215, 120),
    Red = Color3.fromRGB(255, 75, 90), Wild = Color3.fromRGB(70, 190, 255),
    Trainer = Color3.fromRGB(255, 150, 60), Orange = Color3.fromRGB(255, 150, 60),
    Cyan = Color3.fromRGB(70, 190, 255), Pink = Color3.fromRGB(255, 100, 200),
    Teal = Color3.fromRGB(50, 220, 190),
}

local function createShadow(parent, radius, offset)
    local shadow = Instance.new("ImageLabel", parent)
    shadow.Name = "Shadow"
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://1316045217"
    shadow.ImageColor3 = Color3.new(0, 0, 0)
    shadow.ImageTransparency = 0.5
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(10, 10, 118, 118)
    shadow.Position = UDim2.new(0, -radius + offset.X, 0, -radius + offset.Y)
    shadow.Size = UDim2.new(1, radius * 2, 1, radius * 2)
    shadow.ZIndex = parent.ZIndex - 1
    return shadow
end

local function addHoverEffect(button, defaultColor, hoverColor)
    local tInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    track(button.MouseEnter:Connect(function()
        TweenService:Create(button, tInfo, {BackgroundColor3 = hoverColor}):Play()
    end))
    track(button.MouseLeave:Connect(function()
        TweenService:Create(button, tInfo, {BackgroundColor3 = defaultColor}):Play()
    end))
end

--------------------------------------------------
-- MAIN FRAME (wider to fit 4 tabs)
--------------------------------------------------
local mainFrame = Instance.new("CanvasGroup")
mainFrame.Size = UDim2.fromOffset(480, 740)
mainFrame.Position = UDim2.fromScale(0.5, 0.5)
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.BackgroundColor3 = C.BG
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = false
mainFrame.Parent = gui
mainFrame.GroupTransparency = 1
UI.mainScale = Instance.new("UIScale", mainFrame)
UI.mainScale.Scale = 0.9

Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)
createShadow(mainFrame, 15, Vector2.new(0, 4))
UI.stroke = Instance.new("UIStroke", mainFrame)
UI.stroke.Color = C.Accent
UI.stroke.Thickness = 1.5
UI.stroke.Transparency = 0.5

-- SPLASH
UI.splashFrame = Instance.new("Frame", mainFrame)
UI.splashFrame.Size = UDim2.fromScale(1, 1)
UI.splashFrame.BackgroundTransparency = 0
UI.splashFrame.BackgroundColor3 = C.BG
UI.splashFrame.ZIndex = 100
Instance.new("UICorner", UI.splashFrame).CornerRadius = UDim.new(0, 12)
UI.splashGrad = Instance.new("UIGradient", UI.splashFrame)
UI.splashGrad.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, C.AccentDim),
    ColorSequenceKeypoint.new(1, C.BG)
}
UI.splashGrad.Rotation = 90

UI.splashLogo = Instance.new("TextLabel", UI.splashFrame)
UI.splashLogo.Size = UDim2.fromScale(1, 1)
UI.splashLogo.BackgroundTransparency = 1
UI.splashLogo.Text = "⚡ LumiWare " .. VERSION
UI.splashLogo.Font = Enum.Font.GothamBlack
UI.splashLogo.TextSize = 34
UI.splashLogo.TextColor3 = C.Text
UI.splashLogo.ZIndex = 101

UI.splashUIScale = Instance.new("UIScale", UI.splashLogo)
UI.splashUIScale.Scale = 0.8

task.spawn(function()
    TweenService:Create(mainFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {GroupTransparency = 0}):Play()
    TweenService:Create(UI.splashUIScale, TweenInfo.new(1.2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Scale = 1.05}):Play()
    task.wait(1.5)
    TweenService:Create(UI.splashFrame, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundTransparency = 1}):Play()
    TweenService:Create(UI.splashLogo, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 1}):Play()
    TweenService:Create(UI.mainScale, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
    task.wait(0.6)
    UI.splashFrame:Destroy()
end)

-- TOPBAR
UI.topbar = Instance.new("Frame", mainFrame)
UI.topbar.Size = UDim2.new(1, 0, 0, 36)
UI.topbar.BackgroundColor3 = C.TopBar
UI.topbar.BorderSizePixel = 0
Instance.new("UICorner", UI.topbar).CornerRadius = UDim.new(0, 10)
UI.topFill = Instance.new("Frame", UI.topbar)
UI.topFill.Size = UDim2.new(1, 0, 0, 10)
UI.topFill.Position = UDim2.new(0, 0, 1, -10)
UI.topFill.BackgroundColor3 = C.TopBar
UI.topFill.BorderSizePixel = 0

UI.titleLbl = Instance.new("TextLabel", UI.topbar)
UI.titleLbl.Size = UDim2.new(1, -80, 1, 0)
UI.titleLbl.Position = UDim2.new(0, 12, 0, 0)
UI.titleLbl.BackgroundTransparency = 1
UI.titleLbl.Text = "⚡ LumiWare " .. VERSION
UI.titleLbl.Font = Enum.Font.GothamBold
UI.titleLbl.TextSize = 15
UI.titleLbl.TextColor3 = C.Accent
UI.titleLbl.TextXAlignment = Enum.TextXAlignment.Left

UI.minBtn = Instance.new("TextButton", UI.topbar)
UI.minBtn.Size = UDim2.fromOffset(28, 28)
UI.minBtn.Position = UDim2.new(1, -66, 0, 4)
UI.minBtn.BackgroundColor3 = C.PanelAlt
UI.minBtn.Text = "–"
UI.minBtn.Font = Enum.Font.GothamBold
UI.minBtn.TextSize = 18
UI.minBtn.TextColor3 = C.Text
UI.minBtn.BorderSizePixel = 0
Instance.new("UICorner", UI.minBtn).CornerRadius = UDim.new(0, 6)
addHoverEffect(UI.minBtn, C.PanelAlt, C.AccentDim)

UI.closeBtn = Instance.new("TextButton", UI.topbar)
UI.closeBtn.Size = UDim2.fromOffset(28, 28)
UI.closeBtn.Position = UDim2.new(1, -34, 0, 4)
UI.closeBtn.BackgroundColor3 = C.PanelAlt
UI.closeBtn.Text = "×"
UI.closeBtn.Font = Enum.Font.GothamBold
UI.closeBtn.TextSize = 18
UI.closeBtn.TextColor3 = C.Text
UI.closeBtn.BorderSizePixel = 0
Instance.new("UICorner", UI.closeBtn).CornerRadius = UDim.new(0, 6)
addHoverEffect(UI.closeBtn, C.PanelAlt, C.Red)

UI.closeBtn.MouseButton1Click:Connect(function()
    local elapsed = tick() - UI.huntStartTime
    sendSessionWebhook(UI.encounterCount, formatTime(elapsed), raresFoundCount)
    gui:Destroy()
end)

-- Drag
local dragging, dragInput, dragStart, startPos
track(UI.topbar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = mainFrame.Position
        track(input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end))
    end
end))
track(UI.topbar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
end))
track(UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local d = input.Position - dragStart
        mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end))

--------------------------------------------------
-- TAB BAR (4 tabs now)
--------------------------------------------------
UI.tabBar = Instance.new("Frame", mainFrame)
UI.tabBar.Size = UDim2.new(1, -16, 0, 30)
UI.tabBar.Position = UDim2.new(0, 8, 0, 44)
UI.tabBar.BackgroundTransparency = 1
UI.tabLayout = Instance.new("UIListLayout", UI.tabBar)
UI.tabLayout.FillDirection = Enum.FillDirection.Horizontal
UI.tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
UI.tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
UI.tabLayout.Padding = UDim.new(0, 4)

local function mkTabBtn(parent, text)
    local b = Instance.new("TextButton", parent)
    b.Size = UDim2.new(0.25, -3, 1, 0)
    b.BackgroundColor3 = C.PanelAlt
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.TextColor3 = C.TextDim
    b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

UI.huntTabBtn = mkTabBtn(UI.tabBar, "🗡️ HUNT")
UI.masteryTabBtn = mkTabBtn(UI.tabBar, "📖 MASTERY")
UI.healTabBtn = mkTabBtn(UI.tabBar, "💊 HEAL")
UI.cfgTabBtn = mkTabBtn(UI.tabBar, "⚙️ CONFIG")

-- CONTENT WRAPPER
UI.contentContainer = Instance.new("Frame", mainFrame)
UI.contentContainer.Name = "ContentContainer"
UI.contentContainer.Size = UDim2.new(1, -16, 1, -82)
UI.contentContainer.Position = UDim2.new(0, 8, 0, 78)
UI.contentContainer.BackgroundTransparency = 1

-- forward decl for addBattleLog
local addBattleLog

-- Make contentFrame scrollable since hunt tab exceeds visible area
local contentScrollFrame = Instance.new("ScrollingFrame", UI.contentContainer)
contentScrollFrame.Name = "HuntScrollWrapper"
contentScrollFrame.Size = UDim2.new(1, 0, 1, 0)
contentScrollFrame.BackgroundTransparency = 1
contentScrollFrame.BorderSizePixel = 0
contentScrollFrame.ScrollBarThickness = 5
contentScrollFrame.ScrollBarImageColor3 = C.AccentDim
contentScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 1170)
contentScrollFrame.Visible = true

--==================================================
-- MASTERY FRAME
--==================================================
UI.masteryFrame = Instance.new("Frame", UI.contentContainer)
UI.masteryFrame.Size = UDim2.new(1, 0, 1, 0)
UI.masteryFrame.BackgroundTransparency = 1
UI.masteryFrame.Visible = false

UI.masterySearch = Instance.new("TextBox", UI.masteryFrame)
UI.masterySearch.Size = UDim2.new(1, 0, 0, 36)
UI.masterySearch.BackgroundColor3 = C.Panel
UI.masterySearch.Text = ""
UI.masterySearch.PlaceholderText = "🔍 Search Loomian..."
UI.masterySearch.Font = Enum.Font.GothamBold
UI.masterySearch.TextSize = 13
UI.masterySearch.TextColor3 = C.Text
UI.masterySearch.BorderSizePixel = 0
UI.masterySearch.ClearTextOnFocus = false
Instance.new("UICorner", UI.masterySearch).CornerRadius = UDim.new(0, 6)
UI.searchPadding = Instance.new("UIPadding", UI.masterySearch)
UI.searchPadding.PaddingLeft = UDim.new(0, 12)

UI.masterySessionPanel = Instance.new("Frame", UI.masteryFrame)
UI.masterySessionPanel.Size = UDim2.new(1, 0, 0, 24)
UI.masterySessionPanel.Position = UDim2.new(0, 0, 0, 44)
UI.masterySessionPanel.BackgroundTransparency = 1
UI.sessionLbl = Instance.new("TextLabel", UI.masterySessionPanel)
UI.sessionLbl.Size = UDim2.new(1, 0, 1, 0)
UI.sessionLbl.BackgroundTransparency = 1
UI.sessionLbl.Text = "Session: 0 KOs | 0.0k Damage"
UI.sessionLbl.Font = Enum.Font.GothamBold
UI.sessionLbl.TextSize = 11
UI.sessionLbl.TextColor3 = C.TextDim
UI.sessionLbl.TextXAlignment = Enum.TextXAlignment.Left

UI.masteryScroll = Instance.new("ScrollingFrame", UI.masteryFrame)
UI.masteryScroll.Size = UDim2.new(1, 0, 1, -76)
UI.masteryScroll.Position = UDim2.new(0, 0, 0, 76)
UI.masteryScroll.BackgroundTransparency = 1
UI.masteryScroll.BorderSizePixel = 0
UI.masteryScroll.ScrollBarThickness = 4
UI.masteryScroll.ScrollBarImageColor3 = C.AccentDim

UI.masteryListLayout = Instance.new("UIListLayout", UI.masteryScroll)
UI.masteryListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UI.masteryListLayout.Padding = UDim.new(0, 8)

local function renderMasteryFamily(data)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, -8, 0, 110)
    card.BackgroundColor3 = C.Panel
    card.BorderSizePixel = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)
    local familyName = Instance.new("TextLabel", card)
    familyName.Size = UDim2.new(1, -16, 0, 24)
    familyName.Position = UDim2.new(0, 8, 0, 4)
    familyName.BackgroundTransparency = 1
    familyName.Text = string.gsub(data.f, "/", " → ")
    familyName.Font = Enum.Font.GothamBold
    familyName.TextSize = 13
    familyName.TextColor3 = C.Accent
    familyName.TextXAlignment = Enum.TextXAlignment.Left
    for i, t in ipairs(data.t) do
        local typ, amt, rwd = t[1], t[2], t[3]
        local taskRow = Instance.new("Frame", card)
        taskRow.Size = UDim2.new(1, -16, 0, 18)
        taskRow.Position = UDim2.new(0, 8, 0, 26 + (i-1)*20)
        taskRow.BackgroundTransparency = 1
        local checkLbl = Instance.new("TextLabel", taskRow)
        checkLbl.Size = UDim2.new(0, 20, 1, 0)
        checkLbl.BackgroundTransparency = 1
        checkLbl.Text = "☐"
        checkLbl.Font = Enum.Font.GothamBold
        checkLbl.TextSize = 14
        checkLbl.TextColor3 = C.TextDim
        local descLbl = Instance.new("TextLabel", taskRow)
        descLbl.Size = UDim2.new(1, -60, 1, 0)
        descLbl.Position = UDim2.new(0, 24, 0, 0)
        descLbl.BackgroundTransparency = 1
        local taskName = TASK_NAMES[typ] or typ
        if amt > 0 then taskName = string.gsub(taskName, "Loomians", amt .. " Loomians") end
        if typ == "E" then taskName = "Earn " .. tostring(amt) .. " EXP" end
        if typ == "D" and amt > 0 then taskName = "Discover " .. amt .. " stages" end
        if typ == "R" then taskName = "Rally " .. amt .. " times" end
        if typ == "DD" then taskName = "Deal " .. amt .. " Damage" end
        if typ == "C" then taskName = "Capture " .. amt .. (amt==1 and " time" or " times") end
        if typ == "DC" then taskName = "Deal " .. amt .. " Critical Hits" end
        if typ == "LU" then taskName = "Level up " .. amt .. " times" end
        descLbl.Text = taskName
        descLbl.Font = Enum.Font.Gotham
        descLbl.TextSize = 11
        descLbl.TextColor3 = C.Text
        descLbl.TextXAlignment = Enum.TextXAlignment.Left
        local rewardLbl = Instance.new("TextLabel", taskRow)
        rewardLbl.Size = UDim2.new(0, 40, 1, 0)
        rewardLbl.Position = UDim2.new(1, -40, 0, 0)
        rewardLbl.BackgroundTransparency = 1
        rewardLbl.Text = tostring(rwd) .. " MP"
        rewardLbl.Font = Enum.Font.GothamBold
        rewardLbl.TextSize = 10
        rewardLbl.TextColor3 = C.Gold
        rewardLbl.TextXAlignment = Enum.TextXAlignment.Right
    end
    return card
end

local function populateMasteryList(query)
    for _, v in ipairs(UI.masteryScroll:GetChildren()) do
        if v:IsA("Frame") then v:Destroy() end
    end
    local results = searchMastery(query)
    if not query or query == "" then results = MASTERY_DATA end
    local count = 0
    for i = 1, math.min(#results, 50) do
        local card = renderMasteryFamily(results[i])
        card.Parent = UI.masteryScroll
        count = count + 1
    end
    UI.masteryScroll.CanvasSize = UDim2.new(0, 0, 0, count * 118)
end

UI.masterySearch:GetPropertyChangedSignal("Text"):Connect(function()
    populateMasteryList(UI.masterySearch.Text)
end)
populateMasteryList("")

--==================================================
-- CONFIG TAB FRAME (NEW)
--==================================================
UI.cfgFrame = Instance.new("ScrollingFrame", UI.contentContainer)
UI.cfgFrame.Size = UDim2.new(1, 0, 1, 0)
UI.cfgFrame.BackgroundTransparency = 1
UI.cfgFrame.BorderSizePixel = 0
UI.cfgFrame.ScrollBarThickness = 4
UI.cfgFrame.ScrollBarImageColor3 = C.AccentDim
UI.cfgFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
UI.cfgFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
UI.cfgFrame.Visible = false
UI.cfgLayout = Instance.new("UIListLayout", UI.cfgFrame)
UI.cfgLayout.SortOrder = Enum.SortOrder.LayoutOrder
UI.cfgLayout.Padding = UDim.new(0, 8)

local function mkCfgSection(parent, title, color)
    local sec = Instance.new("Frame", parent)
    sec.Size = UDim2.new(1, -8, 0, 0)
    sec.BackgroundColor3 = C.Panel
    sec.BorderSizePixel = 0
    Instance.new("UICorner", sec).CornerRadius = UDim.new(0, 8)
    local hdr = Instance.new("TextLabel", sec)
    hdr.Size = UDim2.new(1, -16, 0, 28)
    hdr.Position = UDim2.new(0, 8, 0, 0)
    hdr.BackgroundTransparency = 1
    hdr.Text = title
    hdr.Font = Enum.Font.GothamBold
    hdr.TextSize = 12
    hdr.TextColor3 = color or C.Accent
    hdr.TextXAlignment = Enum.TextXAlignment.Left
    return sec, hdr
end

local function mkCfgRow(parent, yOff, label, value, color)
    local row = Instance.new("Frame", parent)
    row.Size = UDim2.new(1, -16, 0, 22)
    row.Position = UDim2.new(0, 8, 0, yOff)
    row.BackgroundTransparency = 1
    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(0.6, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 11
    lbl.TextColor3 = C.TextDim
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    local val = Instance.new("TextLabel", row)
    val.Name = "Value"
    val.Size = UDim2.new(0.4, 0, 1, 0)
    val.Position = UDim2.new(0.6, 0, 0, 0)
    val.BackgroundTransparency = 1
    val.Text = tostring(value)
    val.Font = Enum.Font.GothamBold
    val.TextSize = 11
    val.TextColor3 = color or C.Text
    val.TextXAlignment = Enum.TextXAlignment.Right
    return row, val
end

local function mkSmallBtn(parent, text, xOff, yOff, w, h, col)
    local b = Instance.new("TextButton", parent)
    b.Size = UDim2.fromOffset(w or 80, h or 22)
    b.Position = UDim2.new(0, xOff, 0, yOff)
    b.BackgroundColor3 = col or C.AccentDim
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.TextColor3 = C.Text
    b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    return b
end

-- Section 1: Current Config Summary
UI.cfgSummSec, _ = mkCfgSection(UI.cfgFrame, "📋 CURRENT CONFIG", C.Accent)
UI.cfgSummSec.Size = UDim2.new(1, -8, 0, 200)

UI.cfgAutoModeRow, UI.cfgAutoModeVal = mkCfgRow(UI.cfgSummSec, 30, "Wild Auto Mode:", config.autoMode, C.Green)
UI.cfgTrainerModeRow, UI.cfgTrainerModeVal = mkCfgRow(UI.cfgSummSec, 56, "Trainer Auto Mode:", config.trainerAutoMode, C.Orange)
UI.cfgWildSlotRow, UI.cfgWildSlotVal = mkCfgRow(UI.cfgSummSec, 82, "Wild Move Slot:", config.autoMoveSlot, C.Text)
UI.cfgTrainerSlotRow, UI.cfgTrainerSlotVal = mkCfgRow(UI.cfgSummSec, 108, "Trainer Move Slot:", config.trainerAutoMoveSlot, C.Text)
UI.cfgHealRow, UI.cfgHealVal = mkCfgRow(UI.cfgSummSec, 134, "Auto-Heal:", config.autoHealEnabled and "ON" or "OFF", C.Teal)
UI.cfgThreshRow, UI.cfgThreshVal = mkCfgRow(UI.cfgSummSec, 160, "Heal Threshold:", config.autoHealThreshold .. "%", C.Teal)

-- Section 2: Webhook Config
UI.cfgWhSec, _ = mkCfgSection(UI.cfgFrame, "📡 WEBHOOK CONFIG", C.Cyan)
UI.cfgWhSec.Size = UDim2.new(1, -8, 0, 96)

UI.cfgWhInput = Instance.new("TextBox", UI.cfgWhSec)
UI.cfgWhInput.Size = UDim2.new(1, -80, 0, 26)
UI.cfgWhInput.Position = UDim2.new(0, 8, 0, 30)
UI.cfgWhInput.BackgroundColor3 = C.PanelAlt
UI.cfgWhInput.BorderSizePixel = 0
UI.cfgWhInput.PlaceholderText = "Discord webhook URL..."
UI.cfgWhInput.Text = config.webhookUrl or ""
UI.cfgWhInput.Font = Enum.Font.Gotham
UI.cfgWhInput.TextSize = 10
UI.cfgWhInput.TextColor3 = C.Text
UI.cfgWhInput.ClearTextOnFocus = false
UI.cfgWhInput.TextXAlignment = Enum.TextXAlignment.Left
Instance.new("UICorner", UI.cfgWhInput).CornerRadius = UDim.new(0, 5)
Instance.new("UIPadding", UI.cfgWhInput).PaddingLeft = UDim.new(0, 6)

UI.cfgWhSave = mkSmallBtn(UI.cfgWhSec, "SAVE", 0, 30, 60, 26, C.Cyan)
UI.cfgWhSave.Position = UDim2.new(1, -68, 0, 30)
UI.cfgWhSave.TextColor3 = C.BG

UI.cfgPingInput = Instance.new("TextBox", UI.cfgWhSec)
UI.cfgPingInput.Size = UDim2.new(1, -16, 0, 22)
UI.cfgPingInput.Position = UDim2.new(0, 8, 0, 64)
UI.cfgPingInput.BackgroundColor3 = C.PanelAlt
UI.cfgPingInput.BorderSizePixel = 0
UI.cfgPingInput.PlaceholderText = "Ping user IDs (e.g. <@12345>) or @everyone"
UI.cfgPingInput.Text = config.pingIds or ""
UI.cfgPingInput.Font = Enum.Font.Gotham
UI.cfgPingInput.TextSize = 10
UI.cfgPingInput.TextColor3 = C.Text
UI.cfgPingInput.ClearTextOnFocus = false
UI.cfgPingInput.TextXAlignment = Enum.TextXAlignment.Left
Instance.new("UICorner", UI.cfgPingInput).CornerRadius = UDim.new(0, 5)
Instance.new("UIPadding", UI.cfgPingInput).PaddingLeft = UDim.new(0, 6)

-- Section 3: Custom Rares
UI.cfgRareSec, _ = mkCfgSection(UI.cfgFrame, "⭐ CUSTOM RARES", C.Gold)
UI.cfgRareSec.Size = UDim2.new(1, -8, 0, 80)

UI.cfgRareInput = Instance.new("TextBox", UI.cfgRareSec)
UI.cfgRareInput.Size = UDim2.new(1, -100, 0, 26)
UI.cfgRareInput.Position = UDim2.new(0, 8, 0, 30)
UI.cfgRareInput.BackgroundColor3 = C.PanelAlt
UI.cfgRareInput.BorderSizePixel = 0
UI.cfgRareInput.PlaceholderText = "e.g. Twilat, Cathorn..."
UI.cfgRareInput.Text = ""
UI.cfgRareInput.Font = Enum.Font.Gotham
UI.cfgRareInput.TextSize = 11
UI.cfgRareInput.TextColor3 = C.Text
UI.cfgRareInput.ClearTextOnFocus = false
UI.cfgRareInput.TextXAlignment = Enum.TextXAlignment.Left
Instance.new("UICorner", UI.cfgRareInput).CornerRadius = UDim.new(0, 5)
Instance.new("UIPadding", UI.cfgRareInput).PaddingLeft = UDim.new(0, 6)

UI.cfgRareAdd = mkSmallBtn(UI.cfgRareSec, "+ ADD", 0, 30, 42, 26, C.Green)
UI.cfgRareAdd.Position = UDim2.new(1, -90, 0, 30)
UI.cfgRareAdd.TextColor3 = C.BG
UI.cfgRareClear = mkSmallBtn(UI.cfgRareSec, "CLEAR", 0, 30, 42, 26, C.Red)
UI.cfgRareClear.Position = UDim2.new(1, -44, 0, 30)

UI.cfgRareCountLbl = Instance.new("TextLabel", UI.cfgRareSec)
UI.cfgRareCountLbl.Size = UDim2.new(1, -16, 0, 18)
UI.cfgRareCountLbl.Position = UDim2.new(0, 8, 0, 58)
UI.cfgRareCountLbl.BackgroundTransparency = 1
UI.cfgRareCountLbl.Font = Enum.Font.Gotham
UI.cfgRareCountLbl.TextSize = 10
UI.cfgRareCountLbl.TextColor3 = C.TextDim
UI.cfgRareCountLbl.TextXAlignment = Enum.TextXAlignment.Left

local function updateRareCount()
    UI.cfgRareCountLbl.Text = #UI.customRares .. " custom rares: " .. (
        #UI.customRares > 0 and table.concat(UI.customRares, ", ") or "(none)"
    )
end
updateRareCount()

-- Section 4: Save/Reset
UI.cfgSaveSec, _ = mkCfgSection(UI.cfgFrame, "💾 SAVE / RESET CONFIG", C.Green)
UI.cfgSaveSec.Size = UDim2.new(1, -8, 0, 80)

UI.cfgSaveBtn = mkSmallBtn(UI.cfgSaveSec, "💾 SAVE ALL", 8, 30, 130, 28, C.Green)
UI.cfgSaveBtn.TextColor3 = C.BG
UI.cfgSaveBtn.TextSize = 12
UI.cfgResetBtn = mkSmallBtn(UI.cfgSaveSec, "🔄 RESET DEFAULTS", 0, 30, 150, 28, C.Red)
UI.cfgResetBtn.Position = UDim2.new(1, -158, 0, 30)
UI.cfgResetBtn.TextSize = 11

UI.cfgStatusLbl = Instance.new("TextLabel", UI.cfgSaveSec)
UI.cfgStatusLbl.Size = UDim2.new(1, -16, 0, 18)
UI.cfgStatusLbl.Position = UDim2.new(0, 8, 0, 60)
UI.cfgStatusLbl.BackgroundTransparency = 1
UI.cfgStatusLbl.Text = "Config saved at: never"
UI.cfgStatusLbl.Font = Enum.Font.Gotham
UI.cfgStatusLbl.TextSize = 10
UI.cfgStatusLbl.TextColor3 = C.TextDim
UI.cfgStatusLbl.TextXAlignment = Enum.TextXAlignment.Left

-- Section 5: Bot Filters
UI.cfgFilterSec, _ = mkCfgSection(UI.cfgFrame, "🎯 BATTLE TYPE FILTER", C.Pink)
UI.cfgFilterSec.Size = UDim2.new(1, -8, 0, 80)

UI.wildFilterBtn = mkSmallBtn(UI.cfgFilterSec, "Wild: ON", 8, 30, 100, 26, UI.automateWild and C.Wild or C.PanelAlt)
UI.trainerFilterBtn = mkSmallBtn(UI.cfgFilterSec, "Trainer: ON", 116, 30, 100, 26, UI.automateTrainer and C.Trainer or C.PanelAlt)

UI.cfgFilterLbl = Instance.new("TextLabel", UI.cfgFilterSec)
UI.cfgFilterLbl.Size = UDim2.new(1, -16, 0, 18)
UI.cfgFilterLbl.Position = UDim2.new(0, 8, 0, 58)
UI.cfgFilterLbl.BackgroundTransparency = 1
UI.cfgFilterLbl.Text = "Controls which battle types trigger automation"
UI.cfgFilterLbl.Font = Enum.Font.Gotham
UI.cfgFilterLbl.TextSize = 10
UI.cfgFilterLbl.TextColor3 = C.TextDim
UI.cfgFilterLbl.TextXAlignment = Enum.TextXAlignment.Left

--==================================================
-- HEAL TAB FRAME (NEW v4.6)
--==================================================
UI.healFrame = Instance.new("ScrollingFrame", UI.contentContainer)
UI.healFrame.Size = UDim2.new(1, 0, 1, 0)
UI.healFrame.BackgroundTransparency = 1
UI.healFrame.BorderSizePixel = 0
UI.healFrame.ScrollBarThickness = 4
UI.healFrame.ScrollBarImageColor3 = C.AccentDim
UI.healFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
UI.healFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
UI.healFrame.Visible = false
UI.healTabLayout = Instance.new("UIListLayout", UI.healFrame)
UI.healTabLayout.SortOrder = Enum.SortOrder.LayoutOrder
UI.healTabLayout.Padding = UDim.new(0, 8)

-- Section: Auto-Heal Toggle
UI.healToggleSec = Instance.new("Frame", UI.healFrame)
UI.healToggleSec.Size = UDim2.new(1, -8, 0, 90)
UI.healToggleSec.BackgroundColor3 = C.Panel
UI.healToggleSec.BorderSizePixel = 0
Instance.new("UICorner", UI.healToggleSec).CornerRadius = UDim.new(0, 8)

UI.healToggleLbl = Instance.new("TextLabel", UI.healToggleSec)
UI.healToggleLbl.Size = UDim2.new(1, -16, 0, 24)
UI.healToggleLbl.Position = UDim2.new(0, 8, 0, 4)
UI.healToggleLbl.BackgroundTransparency = 1
UI.healToggleLbl.Text = "💊 AUTO-HEAL"
UI.healToggleLbl.Font = Enum.Font.GothamBold
UI.healToggleLbl.TextSize = 12
UI.healToggleLbl.TextColor3 = C.Teal
UI.healToggleLbl.TextXAlignment = Enum.TextXAlignment.Left

UI.healOnBtn = mkSmallBtn(UI.healToggleSec, "ENABLE", 8, 30, 80, 26, autoHealEnabled and C.Teal or C.AccentDim)
UI.healOffBtn = mkSmallBtn(UI.healToggleSec, "DISABLE", 96, 30, 80, 26, not autoHealEnabled and C.Red or C.AccentDim)

UI.healThreshLbl = Instance.new("TextLabel", UI.healToggleSec)
UI.healThreshLbl.Size = UDim2.new(0, 100, 0, 22)
UI.healThreshLbl.Position = UDim2.new(0, 8, 0, 60)
UI.healThreshLbl.BackgroundTransparency = 1
UI.healThreshLbl.Text = "Heal when HP <"
UI.healThreshLbl.Font = Enum.Font.Gotham
UI.healThreshLbl.TextSize = 11
UI.healThreshLbl.TextColor3 = C.TextDim
UI.healThreshLbl.TextXAlignment = Enum.TextXAlignment.Left

UI.healThreshInput = Instance.new("TextBox", UI.healToggleSec)
UI.healThreshInput.Size = UDim2.fromOffset(50, 22)
UI.healThreshInput.Position = UDim2.new(0, 112, 0, 60)
UI.healThreshInput.BackgroundColor3 = C.PanelAlt
UI.healThreshInput.BorderSizePixel = 0
UI.healThreshInput.Text = tostring(autoHealThreshold)
UI.healThreshInput.Font = Enum.Font.GothamBold
UI.healThreshInput.TextSize = 12
UI.healThreshInput.TextColor3 = C.Teal
UI.healThreshInput.ClearTextOnFocus = false
UI.healThreshInput.TextXAlignment = Enum.TextXAlignment.Center
Instance.new("UICorner", UI.healThreshInput).CornerRadius = UDim.new(0, 5)

UI.healThreshPctLbl = Instance.new("TextLabel", UI.healToggleSec)
UI.healThreshPctLbl.Size = UDim2.fromOffset(20, 22)
UI.healThreshPctLbl.Position = UDim2.new(0, 166, 0, 60)
UI.healThreshPctLbl.BackgroundTransparency = 1
UI.healThreshPctLbl.Text = "%"
UI.healThreshPctLbl.Font = Enum.Font.GothamBold
UI.healThreshPctLbl.TextSize = 12
UI.healThreshPctLbl.TextColor3 = C.Teal

-- Section: Heal Remote Scanner
UI.healScanSec = Instance.new("Frame", UI.healFrame)
UI.healScanSec.Size = UDim2.new(1, -8, 0, 120)
UI.healScanSec.BackgroundColor3 = C.Panel
UI.healScanSec.BorderSizePixel = 0
Instance.new("UICorner", UI.healScanSec).CornerRadius = UDim.new(0, 8)

UI.healScanTitle = Instance.new("TextLabel", UI.healScanSec)
UI.healScanTitle.Size = UDim2.new(1, -16, 0, 24)
UI.healScanTitle.Position = UDim2.new(0, 8, 0, 4)
UI.healScanTitle.BackgroundTransparency = 1
UI.healScanTitle.Text = "🔍 HEAL REMOTE SCANNER"
UI.healScanTitle.Font = Enum.Font.GothamBold
UI.healScanTitle.TextSize = 12
UI.healScanTitle.TextColor3 = C.Teal
UI.healScanTitle.TextXAlignment = Enum.TextXAlignment.Left

UI.healScanBtn = mkSmallBtn(UI.healScanSec, "🔍 SCAN REMOTES", 8, 30, 140, 26, C.Teal)
UI.healScanBtn.TextColor3 = C.BG
UI.healScanBtnBtn = mkSmallBtn(UI.healScanSec, "🔍 SCAN BUTTONS", 156, 30, 140, 26, C.Cyan)
UI.healScanBtnBtn.TextColor3 = C.BG

UI.healScanStatusLbl = Instance.new("TextLabel", UI.healScanSec)
UI.healScanStatusLbl.Size = UDim2.new(1, -16, 0, 18)
UI.healScanStatusLbl.Position = UDim2.new(0, 8, 0, 62)
UI.healScanStatusLbl.BackgroundTransparency = 1
UI.healScanStatusLbl.Text = "▸ Press Scan to find heal remotes"
UI.healScanStatusLbl.Font = Enum.Font.Gotham
UI.healScanStatusLbl.TextSize = 10
UI.healScanStatusLbl.TextColor3 = C.TextDim
UI.healScanStatusLbl.TextXAlignment = Enum.TextXAlignment.Left

-- Heal remote list (scrollable)
UI.healRemoteScroll = Instance.new("ScrollingFrame", UI.healScanSec)
UI.healRemoteScroll.Size = UDim2.new(1, -16, 0, 40)
UI.healRemoteScroll.Position = UDim2.new(0, 8, 0, 78)
UI.healRemoteScroll.BackgroundColor3 = C.PanelAlt
UI.healRemoteScroll.BorderSizePixel = 0
UI.healRemoteScroll.ScrollBarThickness = 3
UI.healRemoteScroll.ScrollBarImageColor3 = C.Teal
UI.healRemoteScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
UI.healRemoteScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Instance.new("UICorner", UI.healRemoteScroll).CornerRadius = UDim.new(0, 5)
UI.healRemoteLayout = Instance.new("UIListLayout", UI.healRemoteScroll)
UI.healRemoteLayout.SortOrder = Enum.SortOrder.LayoutOrder
UI.healRemoteLayout.Padding = UDim.new(0, 2)

UI.healRemoteName = config.healRemoteName or ""
UI.healRemotePath = config.healRemotePath or ""

-- Section: Selected Heal Remote Display
UI.healSelectedSec = Instance.new("Frame", UI.healFrame)
UI.healSelectedSec.Size = UDim2.new(1, -8, 0, 100)
UI.healSelectedSec.BackgroundColor3 = C.Panel
UI.healSelectedSec.BorderSizePixel = 0
Instance.new("UICorner", UI.healSelectedSec).CornerRadius = UDim.new(0, 8)

UI.healSelectedTitle = Instance.new("TextLabel", UI.healSelectedSec)
UI.healSelectedTitle.Size = UDim2.new(1, -16, 0, 24)
UI.healSelectedTitle.Position = UDim2.new(0, 8, 0, 4)
UI.healSelectedTitle.BackgroundTransparency = 1
UI.healSelectedTitle.Text = "✅ SELECTED HEAL SOURCE"
UI.healSelectedTitle.Font = Enum.Font.GothamBold
UI.healSelectedTitle.TextSize = 12
UI.healSelectedTitle.TextColor3 = C.Teal
UI.healSelectedTitle.TextXAlignment = Enum.TextXAlignment.Left

UI.healSelectedName = Instance.new("TextLabel", UI.healSelectedSec)
UI.healSelectedName.Size = UDim2.new(1, -16, 0, 18)
UI.healSelectedName.Position = UDim2.new(0, 8, 0, 30)
UI.healSelectedName.BackgroundTransparency = 1
UI.healSelectedName.Text = UI.healRemoteName ~= "" and ("Remote: " .. UI.healRemoteName) or "None selected"
UI.healSelectedName.Font = Enum.Font.GothamBold
UI.healSelectedName.TextSize = 12
UI.healSelectedName.TextColor3 = UI.healRemoteName ~= "" and C.Teal or C.TextDim
UI.healSelectedName.TextXAlignment = Enum.TextXAlignment.Left

UI.healSelectedPath = Instance.new("TextLabel", UI.healSelectedSec)
UI.healSelectedPath.Size = UDim2.new(1, -16, 0, 16)
UI.healSelectedPath.Position = UDim2.new(0, 8, 0, 50)
UI.healSelectedPath.BackgroundTransparency = 1
UI.healSelectedPath.Text = UI.healRemotePath ~= "" and UI.healRemotePath or "Path: —"
UI.healSelectedPath.Font = Enum.Font.Code
UI.healSelectedPath.TextSize = 9
UI.healSelectedPath.TextColor3 = C.TextDim
UI.healSelectedPath.TextXAlignment = Enum.TextXAlignment.Left
UI.healSelectedPath.TextTruncate = Enum.TextTruncate.AtEnd

UI.healTestBtn = mkSmallBtn(UI.healSelectedSec, "🧪 TEST HEAL NOW", 8, 70, 140, 22, C.Teal)
UI.healTestBtn.TextColor3 = C.BG
UI.healClearBtn = mkSmallBtn(UI.healSelectedSec, "❌ CLEAR", 0, 70, 70, 22, C.Red)
UI.healClearBtn.Position = UDim2.new(1, -78, 0, 70)

-- Section: Auto-Heal Log
UI.healLogSec = Instance.new("Frame", UI.healFrame)
UI.healLogSec.Size = UDim2.new(1, -8, 0, 100)
UI.healLogSec.BackgroundColor3 = C.Panel
UI.healLogSec.BorderSizePixel = 0
Instance.new("UICorner", UI.healLogSec).CornerRadius = UDim.new(0, 8)

UI.healLogTitle = Instance.new("TextLabel", UI.healLogSec)
UI.healLogTitle.Size = UDim2.new(1, -16, 0, 24)
UI.healLogTitle.Position = UDim2.new(0, 8, 0, 4)
UI.healLogTitle.BackgroundTransparency = 1
UI.healLogTitle.Text = "📋 HEAL LOG"
UI.healLogTitle.Font = Enum.Font.GothamBold
UI.healLogTitle.TextSize = 12
UI.healLogTitle.TextColor3 = C.Teal
UI.healLogTitle.TextXAlignment = Enum.TextXAlignment.Left

UI.healLogScroll = Instance.new("ScrollingFrame", UI.healLogSec)
UI.healLogScroll.Size = UDim2.new(1, -16, 1, -32)
UI.healLogScroll.Position = UDim2.new(0, 8, 0, 28)
UI.healLogScroll.BackgroundTransparency = 1
UI.healLogScroll.ScrollBarThickness = 3
UI.healLogScroll.ScrollBarImageColor3 = C.Teal
UI.healLogScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
UI.healLogScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
UI.healLogLayout = Instance.new("UIListLayout", UI.healLogScroll)
UI.healLogLayout.SortOrder = Enum.SortOrder.LayoutOrder
UI.healLogLayout.Padding = UDim.new(0, 2)

UI.healLogOrder = 0
local function addHealLog(text, color)
    UI.healLogOrder = UI.healLogOrder + 1
    local item = Instance.new("TextLabel")
    item.Size = UDim2.new(1, 0, 0, 16)
    item.BackgroundTransparency = 1
    item.Text = "[" .. os.date("%X") .. "] " .. text
    item.Font = Enum.Font.Code
    item.TextSize = 10
    item.TextColor3 = color or C.Teal
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.TextTruncate = Enum.TextTruncate.AtEnd
    item.LayoutOrder = UI.healLogOrder
    item.Parent = UI.healLogScroll
end

--==================================================
-- HUNT FRAME
--==================================================
local contentFrame = Instance.new("Frame", contentScrollFrame)
contentFrame.Name = "HuntFrame"
contentFrame.Size = UDim2.new(1, -6, 0, 1170)
contentFrame.BackgroundTransparency = 1
contentFrame.Visible = true

-- TAB SWITCH LOGIC
local function switchTab(active)
    local tabs = {hunt=contentScrollFrame, mastery=UI.masteryFrame, heal=UI.healFrame, cfg=UI.cfgFrame}
    local btns = {hunt=UI.huntTabBtn, mastery=UI.masteryTabBtn, heal=UI.healTabBtn, cfg=UI.cfgTabBtn}
    for name, frame in pairs(tabs) do
        frame.Visible = (name == active)
        TweenService:Create(btns[name], TweenInfo.new(0.2), {
            BackgroundColor3 = (name == active) and C.Accent or C.PanelAlt,
            TextColor3 = (name == active) and C.Text or C.TextDim,
        }):Play()
    end
end

UI.huntTabBtn.MouseButton1Click:Connect(function() switchTab("hunt") end)
UI.masteryTabBtn.MouseButton1Click:Connect(function() switchTab("mastery") end)
UI.healTabBtn.MouseButton1Click:Connect(function() switchTab("heal") end)
UI.cfgTabBtn.MouseButton1Click:Connect(function() switchTab("cfg") end)
switchTab("hunt")

-- STATS BAR
UI.statsBar = Instance.new("Frame", contentFrame)
UI.statsBar.Size = UDim2.new(1, 0, 0, 50)
UI.statsBar.BackgroundColor3 = C.Panel
UI.statsBar.BorderSizePixel = 0
Instance.new("UICorner", UI.statsBar).CornerRadius = UDim.new(0, 8)
UI.statsLayout = Instance.new("UIListLayout", UI.statsBar)
UI.statsLayout.FillDirection = Enum.FillDirection.Horizontal
UI.statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
UI.statsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
UI.statsLayout.Padding = UDim.new(0, 4)

local function makeStatCell(parent, label, value, color)
    local cell = Instance.new("Frame", parent)
    cell.Size = UDim2.new(0.2, -4, 1, -8)
    cell.BackgroundColor3 = C.PanelAlt
    cell.BorderSizePixel = 0
    Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 6)
    local lbl = Instance.new("TextLabel", cell)
    lbl.Size = UDim2.new(1, 0, 0.45, 0)
    lbl.Position = UDim2.new(0, 0, 0, 2)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 9
    lbl.TextColor3 = C.TextDim
    local val = Instance.new("TextLabel", cell)
    val.Name = "Value"
    val.Size = UDim2.new(1, 0, 0.55, 0)
    val.Position = UDim2.new(0, 0, 0.4, 0)
    val.BackgroundTransparency = 1
    val.Text = value
    val.Font = Enum.Font.GothamBold
    val.TextSize = 13
    val.TextColor3 = color or C.Text
    return val
end

UI.encounterVal = makeStatCell(UI.statsBar, "ENCOUNTERS", "0", C.Green)
local epmVal = makeStatCell(UI.statsBar, "ENC/MIN", "0.0", C.Text)
local timerVal = makeStatCell(UI.statsBar, "HUNT TIME", "0m 00s", C.Text)
local typeVal = makeStatCell(UI.statsBar, "BATTLE", "N/A", C.TextDim)
local stateVal = makeStatCell(UI.statsBar, "STATUS", "Idle", C.TextDim)

-- ENCOUNTER PANEL
UI.encounterPanel = Instance.new("Frame", contentFrame)
UI.encounterPanel.Size = UDim2.new(1, 0, 0, 90)
UI.encounterPanel.Position = UDim2.new(0, 0, 0, 56)
UI.encounterPanel.BackgroundColor3 = C.Panel
UI.encounterPanel.BorderSizePixel = 0
Instance.new("UICorner", UI.encounterPanel).CornerRadius = UDim.new(0, 8)
local encTitle = Instance.new("TextLabel", UI.encounterPanel)
encTitle.Size = UDim2.new(1, -16, 0, 24)
encTitle.Position = UDim2.new(0, 8, 0, 4)
encTitle.BackgroundTransparency = 1
encTitle.Text = "CURRENT ENCOUNTER"
encTitle.Font = Enum.Font.GothamBold
encTitle.TextSize = 11
encTitle.TextColor3 = C.Accent
encTitle.TextXAlignment = Enum.TextXAlignment.Left

local enemyLbl = Instance.new("TextLabel", UI.encounterPanel)
enemyLbl.Size = UDim2.new(1, -16, 0, 22)
enemyLbl.Position = UDim2.new(0, 8, 0, 28)
enemyLbl.BackgroundTransparency = 1
enemyLbl.Text = "Enemy: Waiting for battle..."
enemyLbl.Font = Enum.Font.GothamMedium
enemyLbl.TextSize = 15
enemyLbl.TextColor3 = C.Text
enemyLbl.TextXAlignment = Enum.TextXAlignment.Left
enemyLbl.RichText = true

local enemyStatsLbl = Instance.new("TextLabel", UI.encounterPanel)
enemyStatsLbl.Size = UDim2.new(1, -16, 0, 18)
enemyStatsLbl.Position = UDim2.new(0, 8, 0, 48)
enemyStatsLbl.BackgroundTransparency = 1
enemyStatsLbl.Text = ""
enemyStatsLbl.Font = Enum.Font.Gotham
enemyStatsLbl.TextSize = 12
enemyStatsLbl.TextColor3 = C.TextDim
enemyStatsLbl.TextXAlignment = Enum.TextXAlignment.Left

local playerLbl = Instance.new("TextLabel", UI.encounterPanel)
playerLbl.Size = UDim2.new(1, -16, 0, 18)
playerLbl.Position = UDim2.new(0, 8, 0, 68)
playerLbl.BackgroundTransparency = 1
playerLbl.Text = "Your Loomian: —"
playerLbl.Font = Enum.Font.Gotham
playerLbl.TextSize = 12
playerLbl.TextColor3 = C.TextDim
playerLbl.TextXAlignment = Enum.TextXAlignment.Left

-- RARE LOG
UI.logPanel = Instance.new("Frame", contentFrame)
UI.logPanel.Size = UDim2.new(1, 0, 0, 80)
UI.logPanel.Position = UDim2.new(0, 0, 0, 152)
UI.logPanel.BackgroundColor3 = C.Panel
UI.logPanel.BorderSizePixel = 0
Instance.new("UICorner", UI.logPanel).CornerRadius = UDim.new(0, 8)
UI.logTitle = Instance.new("TextLabel", UI.logPanel)
UI.logTitle.Size = UDim2.new(1, -16, 0, 24)
UI.logTitle.Position = UDim2.new(0, 8, 0, 4)
UI.logTitle.BackgroundTransparency = 1
UI.logTitle.Text = "⭐ RARE FINDER LOG"
UI.logTitle.Font = Enum.Font.GothamBold
UI.logTitle.TextSize = 11
UI.logTitle.TextColor3 = C.Gold
UI.logTitle.TextXAlignment = Enum.TextXAlignment.Left
local rareScroll = Instance.new("ScrollingFrame", UI.logPanel)
rareScroll.Size = UDim2.new(1, -16, 1, -32)
rareScroll.Position = UDim2.new(0, 8, 0, 28)
rareScroll.BackgroundTransparency = 1
rareScroll.ScrollBarThickness = 3
rareScroll.ScrollBarImageColor3 = C.Accent
rareScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
rareScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
UI.logLayout = Instance.new("UIListLayout", rareScroll)
UI.logLayout.SortOrder = Enum.SortOrder.LayoutOrder
UI.logLayout.Padding = UDim.new(0, 3)

UI.logOrder = 0
local function addRareLog(name, extraInfo)
    UI.logOrder = UI.logOrder + 1
    local item = Instance.new("TextLabel")
    item.Size = UDim2.new(1, 0, 0, 20)
    item.BackgroundTransparency = 1
    item.Text = "⭐ [" .. os.date("%X") .. "] " .. name .. (extraInfo and (" — " .. extraInfo) or "")
    item.Font = Enum.Font.GothamMedium
    item.TextSize = 12
    item.TextColor3 = C.Gold
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.LayoutOrder = UI.logOrder
    item.Parent = rareScroll
end

-- WEBHOOK PANEL (compact, in hunt tab)
UI.whPanel = Instance.new("Frame", contentFrame)
UI.whPanel.Size = UDim2.new(1, 0, 0, 56)
UI.whPanel.Position = UDim2.new(0, 0, 0, 238)
UI.whPanel.BackgroundColor3 = C.Panel
UI.whPanel.BorderSizePixel = 0
Instance.new("UICorner", UI.whPanel).CornerRadius = UDim.new(0, 8)
local wt = Instance.new("TextLabel", UI.whPanel)
wt.Size = UDim2.new(1, -16, 0, 20)
wt.Position = UDim2.new(0, 8, 0, 4)
wt.BackgroundTransparency = 1
wt.Text = "📡 WEBHOOK"
wt.Font = Enum.Font.GothamBold
wt.TextSize = 11
wt.TextColor3 = C.Cyan
wt.TextXAlignment = Enum.TextXAlignment.Left
UI.whInput = Instance.new("TextBox", UI.whPanel)
UI.whInput.Size = UDim2.new(1, -60, 0, 26)
UI.whInput.Position = UDim2.new(0, 8, 0, 26)
UI.whInput.BackgroundColor3 = C.PanelAlt
UI.whInput.BorderSizePixel = 0
UI.whInput.PlaceholderText = "Paste webhook URL..."
UI.whInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 110)
UI.whInput.Text = config.webhookUrl or ""
UI.whInput.Font = Enum.Font.Gotham
UI.whInput.TextSize = 11
UI.whInput.TextColor3 = C.Text
UI.whInput.ClearTextOnFocus = false
UI.whInput.TextXAlignment = Enum.TextXAlignment.Left
Instance.new("UICorner", UI.whInput).CornerRadius = UDim.new(0, 5)
Instance.new("UIPadding", UI.whInput).PaddingLeft = UDim.new(0, 6)
UI.whSave = Instance.new("TextButton", UI.whPanel)
UI.whSave.Size = UDim2.fromOffset(42, 26)
UI.whSave.Position = UDim2.new(1, -50, 0, 26)
UI.whSave.BackgroundColor3 = C.Cyan
UI.whSave.Text = "SET"
UI.whSave.Font = Enum.Font.GothamBold
UI.whSave.TextSize = 11
UI.whSave.TextColor3 = C.BG
UI.whSave.BorderSizePixel = 0
Instance.new("UICorner", UI.whSave).CornerRadius = UDim.new(0, 5)
UI.whSave.MouseButton1Click:Connect(function()
    webhookUrl = UI.whInput.Text
    config.webhookUrl = webhookUrl
    if webhookUrl ~= "" then
        sendNotification("LumiWare", "Webhook saved!", 3)
        sendWebhook({title="✅ Webhook Connected!", color=5763719, fields={{name="Player",value=PLAYER_NAME,inline=true}}, footer={text="LumiWare " .. VERSION}})
    else
        sendNotification("LumiWare", "Webhook cleared.", 3)
    end
end)

--==================================================
-- AUTOMATION PANEL (Wild + NEW Trainer)
--==================================================
UI.autoPanel = Instance.new("Frame", contentFrame)
UI.autoPanel.Size = UDim2.new(1, 0, 0, 710)
UI.autoPanel.Position = UDim2.new(0, 0, 0, 300)
UI.autoPanel.BackgroundColor3 = C.Panel
UI.autoPanel.BorderSizePixel = 0
Instance.new("UICorner", UI.autoPanel).CornerRadius = UDim.new(0, 8)

UI.autoTitle = Instance.new("TextLabel", UI.autoPanel)
UI.autoTitle.Size = UDim2.new(1, -16, 0, 20)
UI.autoTitle.Position = UDim2.new(0, 8, 0, 4)
UI.autoTitle.BackgroundTransparency = 1
UI.autoTitle.Text = "🤖 AUTOMATION"
UI.autoTitle.Font = Enum.Font.GothamBold
UI.autoTitle.TextSize = 11
UI.autoTitle.TextColor3 = Color3.fromRGB(255, 120, 255)
UI.autoTitle.TextXAlignment = Enum.TextXAlignment.Left

-- Wild Battle Auto
local wildSectionLbl = Instance.new("TextLabel", UI.autoPanel)
wildSectionLbl.Size = UDim2.new(0.4, 0, 0, 16)
wildSectionLbl.Position = UDim2.new(0, 8, 0, 26)
wildSectionLbl.BackgroundTransparency = 1
wildSectionLbl.Text = "🌿 WILD:"
wildSectionLbl.Font = Enum.Font.GothamBold
wildSectionLbl.TextSize = 10
wildSectionLbl.TextColor3 = C.Wild
wildSectionLbl.TextXAlignment = Enum.TextXAlignment.Left

local function mkAutoBtn(parent, text, xOff, yOff, width)
    local b = Instance.new("TextButton", parent)
    b.Size = UDim2.fromOffset(width or 60, 22)
    b.Position = UDim2.new(0, xOff, 0, yOff)
    b.BackgroundColor3 = C.AccentDim
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.TextColor3 = C.Text
    b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    return b
end

local wildOffBtn  = mkAutoBtn(UI.autoPanel, "OFF",  8,  44, 44)
local wildMoveBtn = mkAutoBtn(UI.autoPanel, "MOVE", 58, 44, 52)
local wildRunBtn  = mkAutoBtn(UI.autoPanel, "RUN",  116, 44, 44)

addHoverEffect(wildOffBtn, C.AccentDim, C.Red)
addHoverEffect(wildMoveBtn, C.AccentDim, C.Green)
addHoverEffect(wildRunBtn, C.AccentDim, C.Cyan)

local wildSlotLbl = Instance.new("TextLabel", UI.autoPanel)
wildSlotLbl.Size = UDim2.new(0, 32, 0, 22)
wildSlotLbl.Position = UDim2.new(0, 166, 0, 44)
wildSlotLbl.BackgroundTransparency = 1
wildSlotLbl.Text = "Slot:"
wildSlotLbl.Font = Enum.Font.GothamBold
wildSlotLbl.TextSize = 10
wildSlotLbl.TextColor3 = C.TextDim

local wildSlotBtns = {}
for s = 1, 4 do
    local sb = mkAutoBtn(UI.autoPanel, tostring(s), 200 + (s-1)*26, 44, 22)
    wildSlotBtns[s] = sb
end

-- Trainer Battle Auto (NEW)
UI.trainerSectionLbl = Instance.new("TextLabel", UI.autoPanel)
UI.trainerSectionLbl.Size = UDim2.new(0.4, 0, 0, 16)
UI.trainerSectionLbl.Position = UDim2.new(0, 8, 0, 74)
UI.trainerSectionLbl.BackgroundTransparency = 1
UI.trainerSectionLbl.Text = "🎖️ TRAINER:"
UI.trainerSectionLbl.Font = Enum.Font.GothamBold
UI.trainerSectionLbl.TextSize = 10
UI.trainerSectionLbl.TextColor3 = C.Trainer
UI.trainerSectionLbl.TextXAlignment = Enum.TextXAlignment.Left

UI.trOffBtn  = mkAutoBtn(UI.autoPanel, "OFF",  8,  92, 44)
UI.trMoveBtn = mkAutoBtn(UI.autoPanel, "MOVE", 58, 92, 52)
UI.trRunBtn  = mkAutoBtn(UI.autoPanel, "RUN",  116, 92, 44)

addHoverEffect(UI.trOffBtn, C.AccentDim, C.Red)
addHoverEffect(UI.trMoveBtn, C.AccentDim, C.Orange)
addHoverEffect(UI.trRunBtn, C.AccentDim, C.Cyan)

UI.trSlotLbl = Instance.new("TextLabel", UI.autoPanel)
UI.trSlotLbl.Size = UDim2.new(0, 32, 0, 22)
UI.trSlotLbl.Position = UDim2.new(0, 166, 0, 92)
UI.trSlotLbl.BackgroundTransparency = 1
UI.trSlotLbl.Text = "Slot:"
UI.trSlotLbl.Font = Enum.Font.GothamBold
UI.trSlotLbl.TextSize = 10
UI.trSlotLbl.TextColor3 = C.TextDim

UI.trSlotBtns = {}
for s = 1, 4 do
    local sb = mkAutoBtn(UI.autoPanel, tostring(s), 200 + (s-1)*26, 92, 22)
    UI.trSlotBtns[s] = sb
end

-- Auto-walk + Scan row
local walkBtn = mkAutoBtn(UI.autoPanel, "🚶 AUTO-WALK: OFF", 8, 122, 140)
local scanBtn = mkAutoBtn(UI.autoPanel, "🔍 SCAN UI", 155, 122, 80)
scanBtn.BackgroundColor3 = C.PanelAlt
addHoverEffect(scanBtn, C.PanelAlt, C.Accent)

-- Auto Fish & Disc Drop
UI.autoFishBtn = mkAutoBtn(UI.autoPanel, "🎣 AUTO FISH: OFF", 8, 152, 140)
UI.autoDiscBtn = mkAutoBtn(UI.autoPanel, "💿 DISC DROP: OFF", 155, 152, 110)

-- Server Actions
UI.serverHopBtn = mkAutoBtn(UI.autoPanel, "🌍 SERVER HOP", 8, 182, 110)
UI.emptyServerBtn = mkAutoBtn(UI.autoPanel, "📉 EMPTY SERVER", 125, 182, 120)

-- Mastery Hook
UI.masteryDisableBtn = mkAutoBtn(UI.autoPanel, "📖 DISABLE MASTERY UI: OFF", 8, 212, 180)

-- Dialogue Skips
UI.autoSkipDialogueBtn = mkAutoBtn(UI.autoPanel, "💬 SKIP DIALOGUE: OFF", 8, 242, 140)
UI.autoDenyMoveBtn = mkAutoBtn(UI.autoPanel, "🚫 DENY MOVES: OFF", 155, 242, 130)

UI.autoDenySwitchBtn = mkAutoBtn(UI.autoPanel, "🚫 DENY SWITCH: OFF", 8, 272, 140)
UI.autoDenyNickBtn = mkAutoBtn(UI.autoPanel, "🚫 DENY NICK: OFF", 155, 272, 130)

-- Auto Catch Filters
UI.catchSectionLbl = Instance.new("TextLabel", UI.autoPanel)
UI.catchSectionLbl.Size = UDim2.new(0.4, 0, 0, 16)
UI.catchSectionLbl.Position = UDim2.new(0, 8, 0, 302)
UI.catchSectionLbl.BackgroundTransparency = 1
UI.catchSectionLbl.Text = "🎯 AUTO CATCH:"
UI.catchSectionLbl.Font = Enum.Font.GothamBold
UI.catchSectionLbl.TextSize = 10
UI.catchSectionLbl.TextColor3 = C.Gold
UI.catchSectionLbl.TextXAlignment = Enum.TextXAlignment.Left

UI.catchGleamBtn = mkAutoBtn(UI.autoPanel, "CATCH GLEAM: OFF", 8, 320, 120)
UI.catchGammaBtn = mkAutoBtn(UI.autoPanel, "CATCH GAMMA: OFF", 132, 320, 120)
UI.catchNotOwnedBtn = mkAutoBtn(UI.autoPanel, "CATCH NOT OWNED: OFF", 8, 346, 140)
UI.catchSpareBtn = mkAutoBtn(UI.autoPanel, "USE SPARE (<20%): OFF", 152, 346, 140)

-- Auto Defeat Corrupt
UI.defeatCorruptBtn = mkAutoBtn(UI.autoPanel, "DEFEAT CORRUPT: OFF", 8, 376, 140)
UI.defeatCorruptSlotBtns = {}
for s = 1, 4 do
    local sb = mkAutoBtn(UI.autoPanel, tostring(s), 152 + (s-1)*26, 376, 22)
    UI.defeatCorruptSlotBtns[s] = sb
end

-- Auto Rally
UI.rallySectionLbl = Instance.new("TextLabel", UI.autoPanel)
UI.rallySectionLbl.Size = UDim2.new(0.4, 0, 0, 16)
UI.rallySectionLbl.Position = UDim2.new(0, 8, 0, 406)
UI.rallySectionLbl.BackgroundTransparency = 1
UI.rallySectionLbl.Text = "🏇 AUTO RALLY:"
UI.rallySectionLbl.Font = Enum.Font.GothamBold
UI.rallySectionLbl.TextSize = 10
UI.rallySectionLbl.TextColor3 = C.Pink
UI.rallySectionLbl.TextXAlignment = Enum.TextXAlignment.Left

UI.autoRallyBtn = mkAutoBtn(UI.autoPanel, "ENABLE RALLY: OFF", 8, 424, 120)
UI.rallyKeepGleamBtn = mkAutoBtn(UI.autoPanel, "KEEP GLEAM: OFF", 132, 424, 110)
UI.rallyKeepHABtn = mkAutoBtn(UI.autoPanel, "KEEP S.A.: OFF", 246, 424, 90)

-- Auto Encounter
UI.encounterSectionLbl = Instance.new("TextLabel", UI.autoPanel)
UI.encounterSectionLbl.Size = UDim2.new(0.4, 0, 0, 16)
UI.encounterSectionLbl.Position = UDim2.new(0, 8, 0, 456)
UI.encounterSectionLbl.BackgroundTransparency = 1
UI.encounterSectionLbl.Text = "🏃 AUTO ENCOUNTER:"
UI.encounterSectionLbl.Font = Enum.Font.GothamBold
UI.encounterSectionLbl.TextSize = 10
UI.encounterSectionLbl.TextColor3 = C.Green
UI.encounterSectionLbl.TextXAlignment = Enum.TextXAlignment.Left

UI.autoEncounterBtn = mkAutoBtn(UI.autoPanel, "ENABLE ENCOUNTER: OFF", 8, 474, 150)

-- Exploits
UI.exploitSectionLbl = Instance.new("TextLabel", UI.autoPanel)
UI.exploitSectionLbl.Size = UDim2.new(0.4, 0, 0, 16)
UI.exploitSectionLbl.Position = UDim2.new(0, 8, 0, 506)
UI.exploitSectionLbl.BackgroundTransparency = 1
UI.exploitSectionLbl.Text = "🛠️ EXPLOITS:"
UI.exploitSectionLbl.Font = Enum.Font.GothamBold
UI.exploitSectionLbl.TextSize = 10
UI.exploitSectionLbl.TextColor3 = C.Red
UI.exploitSectionLbl.TextXAlignment = Enum.TextXAlignment.Left

UI.fastBattleBtn = mkAutoBtn(UI.autoPanel, "FAST BATTLE: OFF", 8, 524, 120)
UI.infUMVBtn = mkAutoBtn(UI.autoPanel, "INF UMV: OFF", 132, 524, 100)
UI.skipFishBtn = mkAutoBtn(UI.autoPanel, "SKIP FISH: OFF", 236, 524, 100)
UI.noUnstuckBtn = mkAutoBtn(UI.autoPanel, "NO UNSTUCK CD: OFF", 8, 550, 140)
UI.infRepelBtn = mkAutoBtn(UI.autoPanel, "INFINITE REPEL: OFF", 152, 550, 140)

-- GUI Openers
UI.guiSectionLbl = Instance.new("TextLabel", UI.autoPanel)
UI.guiSectionLbl.Size = UDim2.new(0.4, 0, 0, 16)
UI.guiSectionLbl.Position = UDim2.new(0, 8, 0, 582)
UI.guiSectionLbl.BackgroundTransparency = 1
UI.guiSectionLbl.Text = "🖥️ GUIs:"
UI.guiSectionLbl.Font = Enum.Font.GothamBold
UI.guiSectionLbl.TextSize = 10
UI.guiSectionLbl.TextColor3 = C.Cyan
UI.guiSectionLbl.TextXAlignment = Enum.TextXAlignment.Left

UI.openPCBtn = mkAutoBtn(UI.autoPanel, "OPEN PC", 8, 600, 80)
UI.openShopBtn = mkAutoBtn(UI.autoPanel, "OPEN SHOP", 92, 600, 80)
UI.openRallyTeamBtn = mkAutoBtn(UI.autoPanel, "OPEN RALLY TEAM", 8, 626, 120)
UI.openRalliedBtn = mkAutoBtn(UI.autoPanel, "OPEN RALLIED", 132, 626, 100)




-- Status
local autoStatusLbl = Instance.new("TextLabel", UI.autoPanel)
autoStatusLbl.Size = UDim2.new(1, -16, 0, 22)
autoStatusLbl.Position = UDim2.new(0, 8, 0, 680)
autoStatusLbl.BackgroundTransparency = 1
autoStatusLbl.Text = ""
autoStatusLbl.Font = Enum.Font.Gotham
autoStatusLbl.TextSize = 10
autoStatusLbl.TextColor3 = C.TextDim
autoStatusLbl.TextXAlignment = Enum.TextXAlignment.Left

local function updateAutoUI()
    wildOffBtn.BackgroundColor3  = autoMode == "off"  and C.Red   or C.AccentDim
    wildMoveBtn.BackgroundColor3 = autoMode == "move" and C.Green or C.AccentDim
    wildRunBtn.BackgroundColor3  = autoMode == "run"  and C.Cyan  or C.AccentDim
    for s = 1, 4 do
        wildSlotBtns[s].BackgroundColor3 = (autoMoveSlot == s and autoMode == "move") and C.Accent or C.AccentDim
    end
    UI.trOffBtn.BackgroundColor3  = trainerAutoMode == "off"  and C.Red    or C.AccentDim
    UI.trMoveBtn.BackgroundColor3 = trainerAutoMode == "move" and C.Orange or C.AccentDim
    UI.trRunBtn.BackgroundColor3  = trainerAutoMode == "run"  and C.Cyan   or C.AccentDim
    for s = 1, 4 do
        UI.trSlotBtns[s].BackgroundColor3 = (trainerAutoMoveSlot == s and trainerAutoMode == "move") and C.Accent or C.AccentDim
    end
    walkBtn.BackgroundColor3 = autoWalkEnabled and C.Green or C.PanelAlt
    walkBtn.Text = autoWalkEnabled and "🚶 WALKING" or "🚶 AUTO-WALK"

    UI.autoFishBtn.BackgroundColor3 = config.autoFishEnabled and C.Teal or C.AccentDim
    UI.autoFishBtn.Text = config.autoFishEnabled and "🎣 AUTO FISH: ON" or "🎣 AUTO FISH: OFF"
    
    UI.autoDiscBtn.BackgroundColor3 = config.autoDiscEnabled and C.Teal or C.AccentDim
    UI.autoDiscBtn.Text = config.autoDiscEnabled and "💿 DISC DROP: ON" or "💿 DISC DROP: OFF"

    UI.masteryDisableBtn.BackgroundColor3 = config.masteryDisable and C.Teal or C.AccentDim
    UI.masteryDisableBtn.Text = config.masteryDisable and "📖 DISABLE MASTERY UI: ON" or "📖 DISABLE MASTERY UI: OFF"

    UI.autoSkipDialogueBtn.BackgroundColor3 = config.autoSkipDialogue and C.Teal or C.AccentDim
    UI.autoSkipDialogueBtn.Text = config.autoSkipDialogue and "💬 SKIP DIALOGUE: ON" or "💬 SKIP DIALOGUE: OFF"
    
    UI.autoDenyMoveBtn.BackgroundColor3 = config.autoDenyMove and C.Teal or C.AccentDim
    UI.autoDenyMoveBtn.Text = config.autoDenyMove and "🚫 DENY MOVES: ON" or "🚫 DENY MOVES: OFF"
    
    UI.autoDenySwitchBtn.BackgroundColor3 = config.autoDenySwitch and C.Teal or C.AccentDim
    UI.autoDenySwitchBtn.Text = config.autoDenySwitch and "🚫 DENY SWITCH: ON" or "🚫 DENY SWITCH: OFF"
    
    UI.autoDenyNickBtn.BackgroundColor3 = config.autoDenyNick and C.Teal or C.AccentDim
    UI.autoDenyNickBtn.Text = config.autoDenyNick and "🚫 DENY NICK: ON" or "🚫 DENY NICK: OFF"

    UI.catchGleamBtn.BackgroundColor3 = config.autoCatchGleam and C.Teal or C.AccentDim
    UI.catchGleamBtn.Text = config.autoCatchGleam and "CATCH GLEAM: ON" or "CATCH GLEAM: OFF"
    
    UI.catchGammaBtn.BackgroundColor3 = config.autoCatchGamma and C.Teal or C.AccentDim
    UI.catchGammaBtn.Text = config.autoCatchGamma and "CATCH GAMMA: ON" or "CATCH GAMMA: OFF"
    
    UI.catchNotOwnedBtn.BackgroundColor3 = config.autoCatchNotOwned and C.Teal or C.AccentDim
    UI.catchNotOwnedBtn.Text = config.autoCatchNotOwned and "CATCH NOT OWNED: ON" or "CATCH NOT OWNED: OFF"
    
    UI.catchSpareBtn.BackgroundColor3 = config.autoCatchSpare and C.Teal or C.AccentDim
    UI.catchSpareBtn.Text = config.autoCatchSpare and "USE SPARE (<20%): ON" or "USE SPARE (<20%): OFF"

    UI.defeatCorruptBtn.BackgroundColor3 = (config.defeatCorruptMove > 0) and C.Teal or C.AccentDim
    UI.defeatCorruptBtn.Text = (config.defeatCorruptMove > 0) and "DEFEAT CORRUPT: ON" or "DEFEAT CORRUPT: OFF"
    for s=1,4 do UI.defeatCorruptSlotBtns[s].BackgroundColor3 = (config.defeatCorruptMove == s) and C.Accent or C.AccentDim end
    
    UI.autoRallyBtn.BackgroundColor3 = config.autoRally and C.Teal or C.AccentDim
    UI.autoRallyBtn.Text = config.autoRally and "ENABLE RALLY: ON" or "ENABLE RALLY: OFF"
    
    UI.rallyKeepGleamBtn.BackgroundColor3 = config.rallyKeepGleam and C.Teal or C.AccentDim
    UI.rallyKeepGleamBtn.Text = config.rallyKeepGleam and "KEEP GLEAM: ON" or "KEEP GLEAM: OFF"
    
    UI.rallyKeepHABtn.BackgroundColor3 = config.rallyKeepHA and C.Teal or C.AccentDim
    UI.rallyKeepHABtn.Text = config.rallyKeepHA and "KEEP S.A.: ON" or "KEEP S.A.: OFF"

    UI.autoEncounterBtn.BackgroundColor3 = config.autoEncounter and C.Teal or C.AccentDim
    UI.autoEncounterBtn.Text = config.autoEncounter and "ENABLE ENCOUNTER: ON" or "ENABLE ENCOUNTER: OFF"

    UI.fastBattleBtn.BackgroundColor3 = config.fastBattle and C.Teal or C.AccentDim
    UI.fastBattleBtn.Text = config.fastBattle and "FAST BATTLE: ON" or "FAST BATTLE: OFF"
    
    UI.infUMVBtn.BackgroundColor3 = config.infUMV and C.Teal or C.AccentDim
    UI.infUMVBtn.Text = config.infUMV and "INF UMV: ON" or "INF UMV: OFF"
    
    UI.skipFishBtn.BackgroundColor3 = config.skipFish and C.Teal or C.AccentDim
    UI.skipFishBtn.Text = config.skipFish and "SKIP FISH: ON" or "SKIP FISH: OFF"
    
    UI.noUnstuckBtn.BackgroundColor3 = config.noUnstuck and C.Teal or C.AccentDim
    UI.noUnstuckBtn.Text = config.noUnstuck and "NO UNSTUCK CD: ON" or "NO UNSTUCK CD: OFF"

    UI.infRepelBtn.BackgroundColor3 = config.infiniteRepel and C.Teal or C.AccentDim
    UI.infRepelBtn.Text = config.infiniteRepel and "INFINITE REPEL: ON" or "INFINITE REPEL: OFF"

    local wild_s = autoMode == "off" and "Wild: OFF" or ("Wild: " .. string.upper(autoMode) .. " /" .. autoMoveSlot)
    local trainer_s = trainerAutoMode == "off" and "Trainer: OFF" or ("Trainer: " .. string.upper(trainerAutoMode) .. " /" .. trainerAutoMoveSlot)
    autoStatusLbl.Text = wild_s .. "  |  " .. trainer_s .. (rareFoundPause and "  [⏸ RARE PAUSE]" or "")

    -- Update config UI
    UI.cfgAutoModeVal.Text = autoMode
    UI.cfgAutoModeVal.TextColor3 = autoMode == "off" and C.Red or C.Green
    UI.cfgTrainerModeVal.Text = trainerAutoMode
    UI.cfgTrainerModeVal.TextColor3 = trainerAutoMode == "off" and C.Red or C.Orange
    UI.cfgWildSlotVal.Text = tostring(autoMoveSlot)
    UI.cfgTrainerSlotVal.Text = tostring(trainerAutoMoveSlot)
end

-- Wild buttons
track(wildOffBtn.MouseButton1Click:Connect(function()
    autoMode = "off"; config.autoMode = autoMode; saveConfig(); rareFoundPause = false; updateAutoUI()
end))
track(wildMoveBtn.MouseButton1Click:Connect(function()
    autoMode = "move"; config.autoMode = autoMode; saveConfig(); rareFoundPause = false; updateAutoUI()
    sendNotification("LumiWare", "Wild Auto-MOVE slot " .. autoMoveSlot, 3)
end))
track(wildRunBtn.MouseButton1Click:Connect(function()
    autoMode = "run"; config.autoMode = autoMode; saveConfig(); rareFoundPause = false; updateAutoUI()
    sendNotification("LumiWare", "Wild Auto-RUN enabled", 3)
end))
for s = 1, 4 do
    track(wildSlotBtns[s].MouseButton1Click:Connect(function()
        autoMoveSlot = s; config.autoMoveSlot = s; saveConfig(); updateAutoUI()
    end))
    addHoverEffect(wildSlotBtns[s], C.PanelAlt, C.AccentDim)
end

-- Trainer buttons
track(UI.trOffBtn.MouseButton1Click:Connect(function()
    trainerAutoMode = "off"; config.trainerAutoMode = trainerAutoMode; saveConfig(); updateAutoUI()
end))
track(UI.trMoveBtn.MouseButton1Click:Connect(function()
    trainerAutoMode = "move"; config.trainerAutoMode = trainerAutoMode; saveConfig(); updateAutoUI()
    sendNotification("LumiWare", "Trainer Auto-MOVE slot " .. trainerAutoMoveSlot, 3)
end))
track(UI.trRunBtn.MouseButton1Click:Connect(function()
    trainerAutoMode = "run"; config.trainerAutoMode = trainerAutoMode; saveConfig(); updateAutoUI()
    sendNotification("LumiWare", "Trainer Auto-RUN enabled", 3)
end))
for s = 1, 4 do
    track(UI.trSlotBtns[s].MouseButton1Click:Connect(function()
        trainerAutoMoveSlot = s; config.trainerAutoMoveSlot = s; saveConfig(); updateAutoUI()
    end))
    addHoverEffect(UI.trSlotBtns[s], C.PanelAlt, C.AccentDim)
end

updateAutoUI()

--==================================================
-- ALL AUTOMATION BUTTON CLICK HANDLERS
--==================================================

-- Toggle helper for config boolean buttons
local function toggleConfigBool(key)
    config[key] = not config[key]
    saveConfig()
    updateAutoUI()
end

-- Auto Fish
track(UI.autoFishBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("autoFishEnabled")
    sendNotification("LumiWare", "Auto Fish: " .. (config.autoFishEnabled and "ON" or "OFF"), 3)
    addBattleLog("🎣 Auto Fish: " .. (config.autoFishEnabled and "ON" or "OFF"), config.autoFishEnabled and C.Teal or C.TextDim)
end))
addHoverEffect(UI.autoFishBtn, C.AccentDim, C.Teal)

-- Auto Disc Drop
track(UI.autoDiscBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("autoDiscEnabled")
    sendNotification("LumiWare", "Disc Drop: " .. (config.autoDiscEnabled and "ON" or "OFF"), 3)
    addBattleLog("💿 Disc Drop: " .. (config.autoDiscEnabled and "ON" or "OFF"), config.autoDiscEnabled and C.Teal or C.TextDim)
end))
addHoverEffect(UI.autoDiscBtn, C.AccentDim, C.Teal)

-- Server Hop
track(UI.serverHopBtn.MouseButton1Click:Connect(function()
    sendNotification("LumiWare", "Server hopping...", 3)
    pcall(function()
        game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId)
    end)
end))
addHoverEffect(UI.serverHopBtn, C.AccentDim, C.Accent)

-- Empty Server
track(UI.emptyServerBtn.MouseButton1Click:Connect(function()
    sendNotification("LumiWare", "Finding emptiest server...", 3)
    pcall(function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/thedragonslayer2/hey/main/Misc./Find%20the%20most%20empty%20server%20script"))()
    end)
end))
addHoverEffect(UI.emptyServerBtn, C.AccentDim, C.Accent)

-- Mastery Disable
track(UI.masteryDisableBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("masteryDisable")
    sendNotification("LumiWare", "Mastery UI: " .. (config.masteryDisable and "DISABLED" or "ENABLED"), 3)
end))
addHoverEffect(UI.masteryDisableBtn, C.AccentDim, C.Teal)

-- Skip Dialogue
track(UI.autoSkipDialogueBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("autoSkipDialogue")
    sendNotification("LumiWare", "Skip Dialogue: " .. (config.autoSkipDialogue and "ON" or "OFF"), 3)
end))
addHoverEffect(UI.autoSkipDialogueBtn, C.AccentDim, C.Teal)

-- Deny Move Reassign
track(UI.autoDenyMoveBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("autoDenyMove")
    sendNotification("LumiWare", "Deny Moves: " .. (config.autoDenyMove and "ON" or "OFF"), 3)
end))
addHoverEffect(UI.autoDenyMoveBtn, C.AccentDim, C.Teal)

-- Deny Switch
track(UI.autoDenySwitchBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("autoDenySwitch")
    sendNotification("LumiWare", "Deny Switch: " .. (config.autoDenySwitch and "ON" or "OFF"), 3)
end))
addHoverEffect(UI.autoDenySwitchBtn, C.AccentDim, C.Teal)

-- Deny Nickname
track(UI.autoDenyNickBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("autoDenyNick")
    sendNotification("LumiWare", "Deny Nick: " .. (config.autoDenyNick and "ON" or "OFF"), 3)
end))
addHoverEffect(UI.autoDenyNickBtn, C.AccentDim, C.Teal)

-- Catch Gleam
track(UI.catchGleamBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("autoCatchGleam")
    sendNotification("LumiWare", "Catch Gleam: " .. (config.autoCatchGleam and "ON" or "OFF"), 3)
end))
addHoverEffect(UI.catchGleamBtn, C.AccentDim, C.Teal)

-- Catch Gamma
track(UI.catchGammaBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("autoCatchGamma")
    sendNotification("LumiWare", "Catch Gamma: " .. (config.autoCatchGamma and "ON" or "OFF"), 3)
end))
addHoverEffect(UI.catchGammaBtn, C.AccentDim, C.Teal)

-- Catch Not Owned
track(UI.catchNotOwnedBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("autoCatchNotOwned")
    sendNotification("LumiWare", "Catch Not Owned: " .. (config.autoCatchNotOwned and "ON" or "OFF"), 3)
end))
addHoverEffect(UI.catchNotOwnedBtn, C.AccentDim, C.Teal)

-- Use Spare
track(UI.catchSpareBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("autoCatchSpare")
    sendNotification("LumiWare", "Use Spare: " .. (config.autoCatchSpare and "ON" or "OFF"), 3)
end))
addHoverEffect(UI.catchSpareBtn, C.AccentDim, C.Teal)

-- Defeat Corrupt toggle + slot
track(UI.defeatCorruptBtn.MouseButton1Click:Connect(function()
    if config.defeatCorruptMove > 0 then
        config.defeatCorruptMove = 0
    else
        config.defeatCorruptMove = 1
    end
    saveConfig(); updateAutoUI()
    sendNotification("LumiWare", "Defeat Corrupt: " .. (config.defeatCorruptMove > 0 and "ON (slot " .. config.defeatCorruptMove .. ")" or "OFF"), 3)
end))
addHoverEffect(UI.defeatCorruptBtn, C.AccentDim, C.Teal)
for s = 1, 4 do
    track(UI.defeatCorruptSlotBtns[s].MouseButton1Click:Connect(function()
        config.defeatCorruptMove = s; saveConfig(); updateAutoUI()
    end))
    addHoverEffect(UI.defeatCorruptSlotBtns[s], C.PanelAlt, C.AccentDim)
end

-- Auto Rally
track(UI.autoRallyBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("autoRally")
    sendNotification("LumiWare", "Auto Rally: " .. (config.autoRally and "ON" or "OFF"), 3)
end))
addHoverEffect(UI.autoRallyBtn, C.AccentDim, C.Teal)

-- Rally Keep Gleam
track(UI.rallyKeepGleamBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("rallyKeepGleam")
    sendNotification("LumiWare", "Rally Keep Gleam: " .. (config.rallyKeepGleam and "ON" or "OFF"), 3)
end))
addHoverEffect(UI.rallyKeepGleamBtn, C.AccentDim, C.Teal)

-- Rally Keep SA
track(UI.rallyKeepHABtn.MouseButton1Click:Connect(function()
    toggleConfigBool("rallyKeepHA")
    sendNotification("LumiWare", "Rally Keep S.A.: " .. (config.rallyKeepHA and "ON" or "OFF"), 3)
end))
addHoverEffect(UI.rallyKeepHABtn, C.AccentDim, C.Teal)

-- Auto Encounter
track(UI.autoEncounterBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("autoEncounter")
    sendNotification("LumiWare", "Auto Encounter: " .. (config.autoEncounter and "ON" or "OFF"), 3)
    addBattleLog("🏃 Auto Encounter: " .. (config.autoEncounter and "ON" or "OFF"), config.autoEncounter and C.Green or C.TextDim)
end))
addHoverEffect(UI.autoEncounterBtn, C.AccentDim, C.Green)

-- Fast Battle
track(UI.fastBattleBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("fastBattle")
    sendNotification("LumiWare", "Fast Battle: " .. (config.fastBattle and "ON" or "OFF"), 3)
end))
addHoverEffect(UI.fastBattleBtn, C.AccentDim, C.Teal)

-- Infinite UMV
track(UI.infUMVBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("infUMV")
    sendNotification("LumiWare", "Infinite UMV: " .. (config.infUMV and "ON" or "OFF"), 3)
end))
addHoverEffect(UI.infUMVBtn, C.AccentDim, C.Teal)

-- Skip Fish Minigame
track(UI.skipFishBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("skipFish")
    sendNotification("LumiWare", "Skip Fish: " .. (config.skipFish and "ON" or "OFF"), 3)
end))
addHoverEffect(UI.skipFishBtn, C.AccentDim, C.Teal)

-- No Unstuck Cooldown
track(UI.noUnstuckBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("noUnstuck")
    sendNotification("LumiWare", "No Unstuck CD: " .. (config.noUnstuck and "ON" or "OFF"), 3)
end))
addHoverEffect(UI.noUnstuckBtn, C.AccentDim, C.Teal)

-- Infinite Repel
track(UI.infRepelBtn.MouseButton1Click:Connect(function()
    toggleConfigBool("infiniteRepel")
    sendNotification("LumiWare", "Infinite Repel: " .. (config.infiniteRepel and "ON" or "OFF"), 3)
end))
addHoverEffect(UI.infRepelBtn, C.AccentDim, C.Teal)

-- GUI Opener: Open PC
track(UI.openPCBtn.MouseButton1Click:Connect(function()
    if not gameAPIReady then
        sendNotification("LumiWare", "Game API still loading... please wait", 3)
        return
    end
    pcall(function()
        if gameAPI.Menu and gameAPI.Menu.pc then
            setThreadContext(2)
            gameAPI.Menu.pc:bootUp()
            sendNotification("LumiWare", "PC opened", 3)
        else
            sendNotification("LumiWare", "PC module not found in this area", 3)
        end
    end)
end))
addHoverEffect(UI.openPCBtn, C.AccentDim, C.Cyan)

-- GUI Opener: Open Shop
track(UI.openShopBtn.MouseButton1Click:Connect(function()
    if not gameAPIReady then
        sendNotification("LumiWare", "Game API still loading... please wait", 3)
        return
    end
    pcall(function()
        if gameAPI.Menu and gameAPI.Menu.shop then
            setThreadContext(2)
            gameAPI.Menu:disable()
            gameAPI.Menu.shop:open()
            gameAPI.Menu:enable()
            sendNotification("LumiWare", "Shop opened", 3)
        else
            sendNotification("LumiWare", "Shop module not found in this area", 3)
        end
    end)
end))
addHoverEffect(UI.openShopBtn, C.AccentDim, C.Cyan)

-- GUI Opener: Open Rally Team
track(UI.openRallyTeamBtn.MouseButton1Click:Connect(function()
    if not gameAPIReady then
        sendNotification("LumiWare", "Game API still loading... please wait", 3)
        return
    end
    pcall(function()
        if gameAPI.Menu and gameAPI.Menu.rally then
            setThreadContext(2)
            gameAPI.Menu:disable()
            gameAPI.Menu.rally:openRallyTeamMenu()
            gameAPI.Menu:enable()
            sendNotification("LumiWare", "Rally Team opened", 3)
        else
            sendNotification("LumiWare", "Rally module not found", 3)
        end
    end)
end))
addHoverEffect(UI.openRallyTeamBtn, C.AccentDim, C.Cyan)

-- GUI Opener: Open Rallied
track(UI.openRalliedBtn.MouseButton1Click:Connect(function()
    if not gameAPIReady then
        sendNotification("LumiWare", "Game API still loading... please wait", 3)
        return
    end
    pcall(function()
        if gameAPI.Menu and gameAPI.Menu.rally then
            setThreadContext(2)
            local ok, rStatus = pcall(function()
                return gameAPI.Network:get("PDS", "ranchStatus")
            end)
            if ok and rStatus and rStatus.rallied and rStatus.rallied > 0 then
                gameAPI.Menu:disable()
                gameAPI.Menu.rally:openRalliedMonstersMenu()
                gameAPI.Menu:enable()
                sendNotification("LumiWare", "Rallied menu opened", 3)
            else
                sendNotification("LumiWare", "No rallied Loomians", 3)
            end
        else
            sendNotification("LumiWare", "Rally module not found", 3)
        end
    end)
end))
addHoverEffect(UI.openRalliedBtn, C.AccentDim, C.Cyan)

-- BATTLE LOG
local blPanel = Instance.new("Frame", contentFrame)
blPanel.Size = UDim2.new(1, 0, 0, 100)
blPanel.Position = UDim2.new(0, 0, 0, 1016)
blPanel.BackgroundColor3 = C.Panel
blPanel.BorderSizePixel = 0
Instance.new("UICorner", blPanel).CornerRadius = UDim.new(0, 8)
local blt = Instance.new("TextLabel", blPanel)
blt.Size = UDim2.new(1, -16, 0, 20)
blt.Position = UDim2.new(0, 8, 0, 4)
blt.BackgroundTransparency = 1
blt.Text = "⚔️ BATTLE LOG"
blt.Font = Enum.Font.GothamBold
blt.TextSize = 11
blt.TextColor3 = C.Green
blt.TextXAlignment = Enum.TextXAlignment.Left
local battleScroll = Instance.new("ScrollingFrame", blPanel)
battleScroll.Size = UDim2.new(1, -16, 1, -28)
battleScroll.Position = UDim2.new(0, 8, 0, 24)
battleScroll.BackgroundTransparency = 1
battleScroll.ScrollBarThickness = 3
battleScroll.ScrollBarImageColor3 = C.Green
battleScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
battleScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
local bll = Instance.new("UIListLayout", battleScroll)
bll.SortOrder = Enum.SortOrder.LayoutOrder
bll.Padding = UDim.new(0, 2)

local blOrder, blCount = 0, 0
addBattleLog = function(text, color)
    blOrder = blOrder + 1
    blCount = blCount + 1
    local item = Instance.new("TextLabel")
    item.Size = UDim2.new(1, 0, 0, 16)
    item.BackgroundTransparency = 1
    item.Text = "[" .. os.date("%X") .. "] " .. text
    item.Font = Enum.Font.Code
    item.TextSize = 10
    item.TextColor3 = color or C.TextDim
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.TextTruncate = Enum.TextTruncate.AtEnd
    item.LayoutOrder = blOrder
    item.Parent = battleScroll
    if blCount > 40 then
        for _, ch in ipairs(battleScroll:GetChildren()) do
            if ch:IsA("TextLabel") then ch:Destroy(); blCount = blCount - 1; break end
        end
    end
end

-- CONTROLS
UI.ctrlPanel = Instance.new("Frame", contentFrame)
UI.ctrlPanel.Size = UDim2.new(1, 0, 0, 36)
UI.ctrlPanel.Position = UDim2.new(0, 0, 0, 1122)
UI.ctrlPanel.BackgroundColor3 = C.Panel
UI.ctrlPanel.BorderSizePixel = 0
Instance.new("UICorner", UI.ctrlPanel).CornerRadius = UDim.new(0, 8)
local cl = Instance.new("UIListLayout", UI.ctrlPanel)
cl.FillDirection = Enum.FillDirection.Horizontal
cl.HorizontalAlignment = Enum.HorizontalAlignment.Center
cl.VerticalAlignment = Enum.VerticalAlignment.Center
cl.Padding = UDim.new(0, 6)

local function mkCtrlBtn(parent, text)
    local b = Instance.new("TextButton", parent)
    b.Size = UDim2.new(0.33, -6, 0, 26)
    b.BackgroundColor3 = C.AccentDim
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.TextColor3 = C.Text
    b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    return b
end
local resetBtn    = mkCtrlBtn(UI.ctrlPanel, "🔄 RESET")
local discoveryBtn = mkCtrlBtn(UI.ctrlPanel, "🔍 DISCOVERY")
local verboseBtn  = mkCtrlBtn(UI.ctrlPanel, "📝 VERBOSE")

track(resetBtn.MouseButton1Click:Connect(function()
    UI.encounterCount = 0; UI.huntStartTime = tick(); raresFoundCount = 0
    UI.encounterHistory = {}; currentEnemy = nil; resetBattle()
    UI.encounterVal.Text = "0"; epmVal.Text = "0.0"; timerVal.Text = "0m 00s"
    typeVal.Text = "N/A"; typeVal.TextColor3 = C.TextDim
    stateVal.Text = "Idle"; stateVal.TextColor3 = C.TextDim
    enemyLbl.Text = "Enemy: Waiting for battle..."
    enemyStatsLbl.Text = ""; playerLbl.Text = "Your Loomian: —"
    addBattleLog("Session reset", C.Accent)
end))
track(discoveryBtn.MouseButton1Click:Connect(function()
    discoveryMode = not discoveryMode
    discoveryBtn.BackgroundColor3 = discoveryMode and C.Orange or C.AccentDim
    discoveryBtn.Text = discoveryMode and "🔍 DISC: ON" or "🔍 DISCOVERY"
    addBattleLog("Discovery: " .. tostring(discoveryMode), C.Orange)
end))
track(verboseBtn.MouseButton1Click:Connect(function()
    VERBOSE_MODE = not VERBOSE_MODE
    verboseBtn.BackgroundColor3 = VERBOSE_MODE and C.Orange or C.AccentDim
    verboseBtn.Text = VERBOSE_MODE and "📝 VERB: ON" or "📝 VERBOSE"
end))

-- MINIMIZE
local fullSize = UDim2.fromOffset(480, 740)
track(UI.minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {Size = UDim2.fromOffset(480, 36)}):Play()
        UI.contentContainer.Visible = false; UI.tabBar.Visible = false; UI.minBtn.Text = "+"
    else
        UI.contentContainer.Visible = true; UI.tabBar.Visible = true
        TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {Size = fullSize}):Play()
        UI.minBtn.Text = "–"
    end
end))

--==================================================
-- CONFIG TAB LOGIC
--==================================================
local function refreshConfigUI()
    UI.cfgAutoModeVal.Text = autoMode
    UI.cfgAutoModeVal.TextColor3 = autoMode == "off" and C.Red or C.Green
    UI.cfgTrainerModeVal.Text = trainerAutoMode
    UI.cfgTrainerModeVal.TextColor3 = trainerAutoMode == "off" and C.Red or C.Orange
    UI.cfgWildSlotVal.Text = tostring(autoMoveSlot)
    UI.cfgTrainerSlotVal.Text = tostring(trainerAutoMoveSlot)
    UI.cfgHealVal.Text = autoHealEnabled and "ON" or "OFF"
    UI.cfgHealVal.TextColor3 = autoHealEnabled and C.Teal or C.TextDim
    UI.cfgThreshVal.Text = tostring(autoHealThreshold) .. "%"
    UI.wildFilterBtn.BackgroundColor3 = UI.automateWild and C.Wild or C.PanelAlt
    UI.wildFilterBtn.Text = UI.automateWild and "Wild: ON" or "Wild: OFF"
    UI.trainerFilterBtn.BackgroundColor3 = UI.automateTrainer and C.Trainer or C.PanelAlt
    UI.trainerFilterBtn.Text = UI.automateTrainer and "Trainer: ON" or "Trainer: OFF"
    updateRareCount()
end

UI.cfgWhSave.MouseButton1Click:Connect(function()
    webhookUrl = UI.cfgWhInput.Text
    config.webhookUrl = webhookUrl
    config.pingIds = UI.cfgPingInput.Text
    saveConfig()
    sendNotification("LumiWare", "Webhook saved!", 3)
end)

UI.cfgRareAdd.MouseButton1Click:Connect(function()
    local input = UI.cfgRareInput.Text
    if input == "" then return end
    for word in input:gmatch("[^,]+") do
        local trimmed = word:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then table.insert(UI.customRares, trimmed) end
    end
    config.customRares = UI.customRares
    UI.cfgRareInput.Text = ""
    updateRareCount()
    sendNotification("LumiWare", "Added to rare list!", 3)
end)

UI.cfgRareClear.MouseButton1Click:Connect(function()
    UI.customRares = {}
    config.customRares = UI.customRares
    updateRareCount()
    sendNotification("LumiWare", "Custom rares cleared.", 3)
end)

UI.cfgSaveBtn.MouseButton1Click:Connect(function()
    config.autoMode = autoMode
    config.autoMoveSlot = autoMoveSlot
    config.trainerAutoMode = trainerAutoMode
    config.trainerAutoMoveSlot = trainerAutoMoveSlot
    config.autoHealEnabled = autoHealEnabled
    config.autoHealThreshold = autoHealThreshold
    config.customRares = UI.customRares
    config.webhookUrl = webhookUrl
    config.pingIds = UI.cfgPingInput.Text
    config.automateTrainer = UI.automateTrainer
    config.automateWild = UI.automateWild
    config.healRemoteName = UI.healRemoteName
    config.healRemotePath = UI.healRemotePath
    saveConfig()
    UI.cfgStatusLbl.Text = "✅ Config saved at: " .. os.date("%X")
    UI.cfgStatusLbl.TextColor3 = C.Green
    sendNotification("LumiWare", "Config saved!", 3)
    task.delay(3, function()
        UI.cfgStatusLbl.TextColor3 = C.TextDim
    end)
end)

UI.cfgResetBtn.MouseButton1Click:Connect(function()
    resetConfigToDefault()
    autoMode = "off"; trainerAutoMode = "off"
    autoMoveSlot = 1; trainerAutoMoveSlot = 1
    autoHealEnabled = false; autoHealThreshold = 30
    UI.customRares = {}; webhookUrl = ""
    UI.automateTrainer = true; UI.automateWild = true
    updateAutoUI()
    refreshConfigUI()
    UI.cfgStatusLbl.Text = "🔄 Reset to defaults at: " .. os.date("%X")
    UI.cfgStatusLbl.TextColor3 = C.Orange
    sendNotification("LumiWare", "Config reset to defaults.", 4)
end)

UI.wildFilterBtn.MouseButton1Click:Connect(function()
    UI.automateWild = not UI.automateWild
    config.automateWild = UI.automateWild
    UI.wildFilterBtn.BackgroundColor3 = UI.automateWild and C.Wild or C.PanelAlt
    UI.wildFilterBtn.Text = UI.automateWild and "Wild: ON" or "Wild: OFF"
end)
UI.trainerFilterBtn.MouseButton1Click:Connect(function()
    UI.automateTrainer = not UI.automateTrainer
    config.automateTrainer = UI.automateTrainer
    UI.trainerFilterBtn.BackgroundColor3 = UI.automateTrainer and C.Trainer or C.PanelAlt
    UI.trainerFilterBtn.Text = UI.automateTrainer and "Trainer: ON" or "Trainer: OFF"
end)

refreshConfigUI()

--==================================================
-- AUTO-HEAL SYSTEM (NEW v4.6)
--==================================================

-- Keywords that suggest a remote is heal-related
local HEAL_KEYWORDS = {
    "heal", "nurse", "restore", "recovery", "clinic", "center",
    "pokecenter", "loomacenter", "inn", "rest", "fullrestore"
}
local HEAL_BUTTON_KEYWORDS = {
    "heal", "nurse", "restore", "yes", "confirm", "rest"
}

local function looksLikeHealRemote(name, path)
    local nl = string.lower(name)
    local pl = string.lower(path)
    for _, kw in ipairs(HEAL_KEYWORDS) do
        if string.find(nl, kw) or string.find(pl, kw) then return true end
    end
    return false
end

local function getFullPath(obj)
    local path = obj.Name
    local current = obj.Parent
    while current and current ~= game do
        path = current.Name .. "/" .. path
        current = current.Parent
    end
    return path
end

local function addHealRemoteEntry(name, path, remote, isButton)
    local entry = {
        name = name,
        path = path,
        remote = remote,
        isButton = isButton,
    }
    table.insert(scannedHealRemotes, entry)

    -- Add to scroll list
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -4, 0, 20)
    row.BackgroundTransparency = 1

    local nameLbl = Instance.new("TextLabel", row)
    nameLbl.Size = UDim2.new(1, -52, 1, 0)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = (isButton and "🔘 " or "📡 ") .. name
    nameLbl.Font = Enum.Font.Code
    nameLbl.TextSize = 9
    nameLbl.TextColor3 = isButton and C.Cyan or C.Teal
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.TextTruncate = Enum.TextTruncate.AtEnd

    local selectBtn = Instance.new("TextButton", row)
    selectBtn.Size = UDim2.fromOffset(48, 16)
    selectBtn.Position = UDim2.new(1, -50, 0, 2)
    selectBtn.BackgroundColor3 = C.AccentDim
    selectBtn.Text = "USE"
    selectBtn.Font = Enum.Font.GothamBold
    selectBtn.TextSize = 9
    selectBtn.TextColor3 = C.Text
    selectBtn.BorderSizePixel = 0
    Instance.new("UICorner", selectBtn).CornerRadius = UDim.new(0, 4)

    track(selectBtn.MouseButton1Click:Connect(function()
        UI.healRemoteName = name
        UI.healRemotePath = path
        UI.healRemote = remote
        autoHealMethod = isButton and "button" or "remote"
        config.healRemoteName = UI.healRemoteName
        config.healRemotePath = UI.healRemotePath
        config.autoHealMethod = autoHealMethod
        saveConfig()
        UI.healSelectedName.Text = (isButton and "Button: " or "Remote: ") .. name
        UI.healSelectedName.TextColor3 = C.Teal
        UI.healSelectedPath.Text = path
        selectBtn.BackgroundColor3 = C.Teal
        selectBtn.Text = "✓ SET"
        addHealLog("✅ Selected: " .. name, C.Teal)
        sendNotification("LumiWare", "Heal source set: " .. name, 4)
    end))

    row.Parent = UI.healRemoteScroll
end

-- Scan for heal remotes
UI.healScanBtn.MouseButton1Click:Connect(function()
    -- Clear existing list
    for _, v in ipairs(UI.healRemoteScroll:GetChildren()) do
        if not v:IsA("UIListLayout") then v:Destroy() end
    end
    scannedHealRemotes = {}

    UI.healScanStatusLbl.Text = "⏳ Scanning for heal remotes..."
    UI.healScanStatusLbl.TextColor3 = C.Orange

    task.spawn(function()
        local found = 0
        local function scanService(svc)
            pcall(function()
                for _, obj in ipairs(svc:GetDescendants()) do
                    if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                        local path = getFullPath(obj)
                        if looksLikeHealRemote(obj.Name, path) then
                            addHealRemoteEntry(obj.Name, path, obj, false)
                            found = found + 1
                            addHealLog("Found remote: " .. obj.Name .. " @ " .. path, C.Teal)
                        end
                    end
                end
            end)
        end

        scanService(ReplicatedStorage)
        scanService(game:GetService("Workspace"))
        pcall(function() scanService(player:WaitForChild("PlayerGui")) end)

        if found == 0 then
            UI.healScanStatusLbl.Text = "⚠ No heal remotes found. Try entering a heal center first."
            UI.healScanStatusLbl.TextColor3 = C.Orange
        else
            UI.healScanStatusLbl.Text = "✅ Found " .. found .. " heal remote(s). Click USE to select."
            UI.healScanStatusLbl.TextColor3 = C.Teal
        end

        UI.healScanSec.Size = UDim2.new(1, -8, 0, math.max(120, 80 + found * 22))
        UI.healRemoteScroll.Size = UDim2.new(1, -16, 0, math.min(60, math.max(22, found * 22)))
    end)
end)

-- Scan for heal buttons in PlayerGui
UI.healScanBtnBtn.MouseButton1Click:Connect(function()
    for _, v in ipairs(UI.healRemoteScroll:GetChildren()) do
        if not v:IsA("UIListLayout") then v:Destroy() end
    end
    scannedHealRemotes = {}

    UI.healScanStatusLbl.Text = "⏳ Scanning for heal buttons..."
    UI.healScanStatusLbl.TextColor3 = C.Cyan

    task.spawn(function()
        local found = 0
        local pgui = player:FindFirstChild("PlayerGui")
        if not pgui then
            UI.healScanStatusLbl.Text = "⚠ PlayerGui not found"
            return
        end

        local function scanNode(inst, depth)
            if depth > 15 then return end
            for _, child in ipairs(inst:GetChildren()) do
                if child:IsA("TextButton") or child:IsA("ImageButton") then
                    local name = child.Name
                    local text = child:IsA("TextButton") and child.Text or ""
                    local nl = string.lower(name)
                    local tl = string.lower(text)
                    for _, kw in ipairs(HEAL_BUTTON_KEYWORDS) do
                        if string.find(nl, kw) or string.find(tl, kw) then
                            local path = getFullPath(child)
                            addHealRemoteEntry(name .. " [" .. text .. "]", path, child, true)
                            found = found + 1
                            addHealLog("Found button: " .. name .. " (" .. text .. ")", C.Cyan)
                            break
                        end
                    end
                end
                scanNode(child, depth + 1)
            end
        end
        scanNode(pgui, 0)

        if found == 0 then
            UI.healScanStatusLbl.Text = "⚠ No heal buttons found. Go near a heal center and scan again."
            UI.healScanStatusLbl.TextColor3 = C.Orange
        else
            UI.healScanStatusLbl.Text = "✅ Found " .. found .. " heal button(s). Click USE to select."
            UI.healScanStatusLbl.TextColor3 = C.Cyan
        end

        UI.healScanSec.Size = UDim2.new(1, -8, 0, math.max(120, 80 + found * 22))
        UI.healRemoteScroll.Size = UDim2.new(1, -16, 0, math.min(60, math.max(22, found * 22)))
    end)
end)

-- Perform heal action
local function performHeal()
    if not UI.healRemote then
        addHealLog("⚠ No heal source selected!", C.Red)
        return false
    end
    if autoHealMethod == "button" then
        pcall(function()
            local p, s = UI.healRemote.AbsolutePosition, UI.healRemote.AbsoluteSize
            local cx, cy = p.X + s.X/2, p.Y + s.Y/2
            VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
            task.wait(0.05)
            VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
        end)
        addHealLog("💊 Heal button clicked", C.Teal)
    else
        pcall(function()
            if UI.healRemote:IsA("RemoteEvent") then
                UI.healRemote:FireServer()
            elseif UI.healRemote:IsA("RemoteFunction") then
                UI.healRemote:InvokeServer()
            end
        end)
        addHealLog("💊 Heal remote fired: " .. UI.healRemoteName, C.Teal)
    end
    lastHealTime = tick()
    return true
end

-- Test heal
UI.healTestBtn.MouseButton1Click:Connect(function()
    addHealLog("🧪 Manual heal test triggered", C.Orange)
    performHeal()
end)

UI.healClearBtn.MouseButton1Click:Connect(function()
    UI.healRemote = nil
    UI.healRemoteName = ""
    UI.healRemotePath = ""
    config.healRemoteName = ""
    config.healRemotePath = ""
    saveConfig()
    UI.healSelectedName.Text = "None selected"
    UI.healSelectedName.TextColor3 = C.TextDim
    UI.healSelectedPath.Text = "Path: —"
    addHealLog("Heal source cleared", C.TextDim)
end)

-- Auto-heal toggle buttons
UI.healOnBtn.MouseButton1Click:Connect(function()
    autoHealEnabled = true
    config.autoHealEnabled = true
    saveConfig()
    UI.healOnBtn.BackgroundColor3 = C.Teal
    UI.healOffBtn.BackgroundColor3 = C.AccentDim
    refreshConfigUI()
    sendNotification("LumiWare", "Auto-Heal ENABLED (< " .. autoHealThreshold .. "%)", 4)
    addHealLog("✅ Auto-Heal ON (< " .. autoHealThreshold .. "%)", C.Teal)
end)

UI.healOffBtn.MouseButton1Click:Connect(function()
    autoHealEnabled = false
    config.autoHealEnabled = false
    saveConfig()
    UI.healOnBtn.BackgroundColor3 = C.AccentDim
    UI.healOffBtn.BackgroundColor3 = C.Red
    refreshConfigUI()
    addHealLog("❌ Auto-Heal OFF", C.TextDim)
end)

UI.healThreshInput.FocusLost:Connect(function()
    local val = tonumber(UI.healThreshInput.Text)
    if val and val >= 1 and val <= 99 then
        autoHealThreshold = math.floor(val)
        config.autoHealThreshold = autoHealThreshold
        saveConfig()
        refreshConfigUI()
    else
        UI.healThreshInput.Text = tostring(autoHealThreshold)
    end
end)

-- Auto-heal monitor thread
UI.healMonitorThread = task.spawn(function()
    while not _G.LumiWare_StopFlag do
        if not gui.Parent then break end
        if autoHealEnabled and UI.healRemote and battleState ~= "active" then
            -- Check player's active Loomian HP from battle data (if available)
            if currentBattle.playerStats and currentBattle.playerStats.hp and currentBattle.playerStats.maxHP then
                local pct = (currentBattle.playerStats.hp / currentBattle.playerStats.maxHP) * 100
                if pct < autoHealThreshold and (tick() - lastHealTime) > healCooldown then
                    addHealLog(string.format("⚠ HP low (%.0f%%) — auto-healing!", pct), C.Orange)
                    performHeal()
                end
            end
        end
        task.wait(3)
    end
end)
if _G.LumiWare_Threads then table.insert(_G.LumiWare_Threads, UI.healMonitorThread) end

--==================================================
-- SCAN UI (moved to button handler)
--==================================================
scanBtn.MouseButton1Click:Connect(function()
    log("SCAN", "========== SCANNING PlayerGui ==========")
    addBattleLog("🔍 Scanning PlayerGui for buttons...", C.Orange)
    local pgui = player:FindFirstChild("PlayerGui")
    if not pgui then addBattleLog("⚠ PlayerGui not found", C.Red); return end
    local btnCount = 0
    local function scanNode(inst, path, depth)
        if depth > 15 then return end
        for _, child in ipairs(inst:GetChildren()) do
            local childPath = path .. "/" .. child.Name
            local isBtn = child:IsA("TextButton") or child:IsA("ImageButton")
            if isBtn then
                btnCount = btnCount + 1
                local text = child:IsA("TextButton") and child.Text or "[ImageBtn]"
                local vis = child.Visible and "V" or "H"
                local info = string.format("[%s] %s | text=%q class=%s size=%dx%d",
                    vis, childPath, text, child.ClassName,
                    math.floor(child.AbsoluteSize.X), math.floor(child.AbsoluteSize.Y))
                log("SCAN", info)
                addBattleLog("🔘 " .. child.Name .. " | " .. text .. " [" .. vis .. "]", C.Orange)
            end
            scanNode(child, childPath, depth + 1)
        end
    end
    scanNode(pgui, "PlayerGui", 0)
    log("SCAN", "Total buttons found: " .. btnCount)
    addBattleLog("🔍 Scan: " .. btnCount .. " buttons (check F9 console)", C.Orange)
    sendNotification("LumiWare", "Scan: " .. btnCount .. " buttons.\nCheck F9 console.", 5)
end)

-- Outgoing remote spy
pcall(function()
    if hookmetamethod then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if method == "FireServer" and self:IsA("RemoteEvent") then
                if discoveryMode and self.Name == "EVT" then
                    local args = {...}
                    local parts = {}
                    for i = 1, math.min(#args, 6) do
                        if type(args[i]) == "string" then
                            table.insert(parts, "arg" .. i .. '="' .. string.sub(args[i], 1, 30) .. '"')
                        elseif type(args[i]) == "table" then
                            table.insert(parts, "arg" .. i .. "=table")
                        elseif type(args[i]) == "number" then
                            table.insert(parts, "arg" .. i .. "=" .. tostring(args[i]))
                        else
                            table.insert(parts, "arg" .. i .. "=" .. type(args[i]))
                        end
                    end
                    log("OUTGOING", ">>> " .. self.Name .. ":FireServer(" .. table.concat(parts, ", ") .. ")")
                    addBattleLog("📤 OUT " .. self.Name .. " | " .. table.concat(parts, ", "), Color3.fromRGB(255, 180, 80))
                end
                -- NEW: intercept heal remotes for auto-detection
                pcall(function()
                    if looksLikeHealRemote(self.Name, getFullPath(self)) then
                        if UI.healRemoteName == "" then
                            local path = getFullPath(self)
                            addHealLog("🔍 Auto-detected heal remote: " .. self.Name, C.Teal)
                            addHealRemoteEntry(self.Name, path, self, false)
                            UI.healScanStatusLbl.Text = "✅ Auto-detected: " .. self.Name
                            UI.healScanStatusLbl.TextColor3 = C.Teal
                        end
                    end
                end)
            end
            return oldNamecall(self, ...)
        end)
        log("HOOK", "Outgoing remote spy + heal detector installed")
    end
end)

--==================================================
-- AUTO-WALK (Fixed: waits for character to be fully loaded to avoid
-- 'Part RightLowerLeg/LeftLowerLeg is not parented' warnings)
--==================================================
local function waitForCharacterReady()
    local char = player.Character
    if not char then
        char = player.CharacterAdded:Wait()
    end
    -- Wait for the character model to be fully parented and loaded
    if not char:IsDescendantOf(workspace) then
        char.AncestryChanged:Wait()
    end
    local humanoid = char:WaitForChild("Humanoid", 10)
    local rootPart = char:WaitForChild("HumanoidRootPart", 10)
    -- Wait for the body to be assembled (avoids GetJoints warnings)
    if humanoid then
        pcall(function()
            if not humanoid.RootPart then
                humanoid:GetPropertyChangedSignal("RootPart"):Wait()
            end
        end)
    end
    task.wait(0.1) -- Small buffer for joints
    return char, humanoid, rootPart
end

local function startAutoWalk()
    if autoWalkThread then return end
    autoWalkThread = task.spawn(function()
        _G.LumiWare_WalkThread = autoWalkThread
        log("INFO", "Auto-walk started")
        local char, humanoid, rootPart = waitForCharacterReady()
        if not char or not humanoid or not rootPart then
            log("WARN", "Auto-walk: character not ready, aborting")
            autoWalkThread = nil
            return
        end
        local center = rootPart.Position
        local radius = 6
        local numPoints = 12
        local pointIndex = 0
        local heartbeat = RunService.Heartbeat

        -- Re-acquire character on respawn
        local respawnConn
        respawnConn = player.CharacterAdded:Connect(function(newChar)
            task.wait(0.5) -- Wait for body assembly
            char = newChar
            humanoid = char:WaitForChild("Humanoid", 10)
            rootPart = char:WaitForChild("HumanoidRootPart", 10)
            if rootPart then center = rootPart.Position end
        end)

        while autoWalkEnabled and gui.Parent do
            if battleState == "active" then
                pcall(function()
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
                end)
                task.wait(0.5)
            else
                if not char or not char.Parent or not humanoid or not rootPart or not rootPart.Parent then
                    task.wait(1)
                elseif humanoid.Health <= 0 then
                    task.wait(1)
                else
                    pcall(function()
                        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
                    end)
                    local angle = (pointIndex / numPoints) * math.pi * 2
                    local targetPos = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
                    pointIndex = (pointIndex + 1) % numPoints
                    humanoid:MoveTo(targetPos)
                    local moveStart = tick()
                    while autoWalkEnabled and (tick() - moveStart) < 2 do
                        heartbeat:Wait()
                        if not rootPart or not rootPart.Parent then break end
                        if (rootPart.Position - targetPos).Magnitude < 2 then break end
                    end
                end
            end
        end
        if respawnConn then respawnConn:Disconnect() end
        pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game) end)
        log("INFO", "Auto-walk stopped")
    end)
end

local function stopAutoWalk()
    autoWalkEnabled = false
    if autoWalkThread then pcall(function() task.cancel(autoWalkThread) end); autoWalkThread = nil end
    pcall(function()
        local char = player.Character
        if char then
            local h = char:FindFirstChild("Humanoid")
            local rp = char:FindFirstChild("HumanoidRootPart")
            if h and rp then h:MoveTo(rp.Position) end
        end
    end)
    pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game) end)
end

walkBtn.MouseButton1Click:Connect(function()
    autoWalkEnabled = not autoWalkEnabled
    config.autoWalk = autoWalkEnabled
    saveConfig()
    updateAutoUI()
    if autoWalkEnabled then
        startAutoWalk()
        sendNotification("LumiWare", "Auto-walk ON", 3)
        addBattleLog("🚶 Auto-walk ON", C.Green)
    else
        stopAutoWalk()
        sendNotification("LumiWare", "Auto-walk OFF", 3)
        addBattleLog("🚶 Auto-walk OFF", C.TextDim)
    end
end)
addHoverEffect(walkBtn, C.AccentDim, C.Accent)

--==================================================
-- BATTLE UI DETECTION
--==================================================
local cachedMoveNames = {}
local cachedBattleGui = nil
local battleGuiDumped = false

local function getBattleGui()
    if cachedBattleGui then
        local ok, hasParent = pcall(function() return cachedBattleGui.Parent ~= nil end)
        if ok and hasParent then return cachedBattleGui end
        cachedBattleGui = nil
    end
    local pgui = player:FindFirstChild("PlayerGui")
    if not pgui then return nil end
    local bg = nil
    pcall(function()
        local m = pgui:FindFirstChild("MainGui")
        if m then
            local f = m:FindFirstChild("Frame")
            if f then bg = f:FindFirstChild("BattleGui") end
        end
    end)
    if not bg then pcall(function() bg = pgui:FindFirstChild("BattleGui", true) end) end
    if bg then
        cachedBattleGui = bg
        if not battleGuiDumped then
            battleGuiDumped = true
            pcall(function()
                log("AUTO", "=== BattleGui children ===")
                for _, ch in ipairs(bg:GetChildren()) do
                    log("AUTO", "  " .. ch.Name .. " (" .. ch.ClassName .. ") Visible=" .. tostring(ch.Visible))
                end
                log("AUTO", "=== end ===")
            end)
        end
    end
    return bg
end

local cachedBtns = {run = nil, fight = nil, moves = {}, moveN = {}}
local btnsScanned = false

local function hasAnyMove(ui)
    return ui and (ui.moveButtons[1] or ui.moveButtons[2] or ui.moveButtons[3] or ui.moveButtons[4]) and true or false
end

local function findBattleUI()
    local battleGui = getBattleGui()
    if not battleGui then btnsScanned = false; return nil end

    local result = { runButton = nil, fightButton = nil, moveButtons = {}, moveNames = {} }

    if btnsScanned then
        local valid = true
        pcall(function()
            if cachedBtns.run and not cachedBtns.run.Parent then valid = false end
            if cachedBtns.fight and not cachedBtns.fight.Parent then valid = false end
        end)
        if valid then
            pcall(function()
                if cachedBtns.run and cachedBtns.run.Parent and cachedBtns.run.Parent.Visible then
                    result.runButton = cachedBtns.run
                end
                if cachedBtns.fight and cachedBtns.fight.Parent then
                    local anc = cachedBtns.fight.Parent
                    local v = true
                    while anc and anc ~= battleGui do
                        if anc:IsA("GuiObject") and not anc.Visible then v = false; break end
                        anc = anc.Parent
                    end
                    if v then result.fightButton = cachedBtns.fight end
                end
                for i = 1, 4 do
                    local mb = cachedBtns.moves[i]
                    if mb and mb.Parent and mb.Parent.Visible then
                        result.moveButtons[i] = mb
                        result.moveNames[i] = cachedBtns.moveN[i]
                    end
                end
            end)
            if not cachedBtns.moves[1] and not cachedBtns.moves[2]
               and not cachedBtns.moves[3] and not cachedBtns.moves[4] then
                btnsScanned = false
            else
                return result
            end
        end
        btnsScanned = false
    end

    pcall(function()
        local moveSlots = {Move1=1, Move2=2, Move3=3, Move4=4}
        for _, desc in ipairs(battleGui:GetDescendants()) do
            if desc:IsA("ImageButton") and desc.Name == "Button" and desc.Parent then
                local pn = desc.Parent.Name
                if pn == "Run" then
                    cachedBtns.run = desc
                    if desc.Parent.Visible then result.runButton = desc end
                elseif moveSlots[pn] then
                    local slot = moveSlots[pn]
                    cachedBtns.moves[slot] = desc
                    if desc.Parent.Visible then
                        result.moveButtons[slot] = desc
                        if not cachedMoveNames[slot] then
                            local txt = desc.Parent:FindFirstChildOfClass("TextLabel")
                            if not txt then txt = desc:FindFirstChildOfClass("TextLabel") end
                            if txt and txt.Text and txt.Text ~= "" then
                                cachedMoveNames[slot] = txt.Text:lower()
                            end
                        end
                        cachedBtns.moveN[slot] = cachedMoveNames[slot]
                        result.moveNames[slot] = cachedMoveNames[slot]
                    end
                elseif pn ~= "SoulMove" then
                    if not cachedBtns.fight then cachedBtns.fight = desc end
                    local anc = desc.Parent
                    local av = true
                    while anc and anc ~= battleGui do
                        if anc:IsA("GuiObject") and not anc.Visible then av = false; break end
                        anc = anc.Parent
                    end
                    if av and not result.fightButton then result.fightButton = desc end
                end
            end
        end
        btnsScanned = true
    end)

    return result
end

local function clickButton(button)
    if not button then return false end
    if firesignal then
        pcall(function() firesignal(button.MouseButton1Click) end)
        pcall(function() firesignal(button.Activated) end)
        if button.Parent then pcall(function() firesignal(button.Parent.MouseButton1Click) end) end
    end
    if fireclick then pcall(function() fireclick(button) end) end
    pcall(function()
        local p, s = button.AbsolutePosition, button.AbsoluteSize
        local cx, cy = p.X + s.X/2, p.Y + s.Y/2
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
        task.wait(0.03)
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
    end)
    pcall(function()
        local inset = game:GetService("GuiService"):GetGuiInset()
        local p, s = button.AbsolutePosition, button.AbsoluteSize
        local cx, cy = p.X + s.X/2, p.Y + s.Y/2 + inset.Y
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
        task.wait(0.03)
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
    end)
    return true
end

-- Unified battle loop: handles both Wild and Trainer with their own mode/slot
local function performAutoAction(battleType)
    local effectiveMode, effectiveSlot

    if battleType == "Wild" then
        if not UI.automateWild or autoMode == "off" then return end
        effectiveMode = autoMode
        effectiveSlot = autoMoveSlot
    elseif battleType == "Trainer" then
        if not UI.automateTrainer or trainerAutoMode == "off" then return end
        effectiveMode = trainerAutoMode
        effectiveSlot = trainerAutoMoveSlot
    else
        return
    end

    if rareFoundPause or pendingAutoAction then return end
    pendingAutoAction = true

    local modeLabel = battleType == "Wild" and "Wild" or "Trainer"
    log("AUTO", "performAutoAction [" .. modeLabel .. "] mode=" .. effectiveMode)

    task.spawn(function()
        local heartbeat = RunService.Heartbeat
        local ui = nil
        local pollStart = tick()
        local maxWait = 30

        while (tick() - pollStart) < maxWait do
            if rareFoundPause then pendingAutoAction = false; return end
            ui = findBattleUI()
            if ui then
                if effectiveMode == "run" and ui.runButton then break end
                if ui.runButton or ui.fightButton then break end
            end
            heartbeat:Wait()
        end

        if not ui or (not ui.runButton and not ui.fightButton) then
            log("AUTO", "[" .. modeLabel .. "] Battle UI not found after " .. maxWait .. "s")
            addBattleLog("⚠ [" .. modeLabel .. "] UI timeout", C.Orange)
            pendingAutoAction = false
            return
        end

        if effectiveMode == "run" then
            if ui.runButton then
                log("AUTO", "[" .. modeLabel .. "] Auto-RUN")
                addBattleLog("🤖 [" .. modeLabel .. "] RUN ▸ fleeing", C.Cyan)
                for attempt = 1, 10 do
                    local freshUI = findBattleUI()
                    if not freshUI or not freshUI.runButton then break end
                    clickButton(freshUI.runButton)
                    task.wait(0.2)
                end
            else
                addBattleLog("⚠ [" .. modeLabel .. "] Run button not found", C.Orange)
            end
            pendingAutoAction = false
            return
        elseif effectiveMode == "move" then
            local turnCount = 0
            local maxTurns = 30

            while turnCount < maxTurns do
                turnCount = turnCount + 1
                if rareFoundPause or (battleType == "Wild" and autoMode ~= "move") or (battleType == "Trainer" and trainerAutoMode ~= "move") then break end

                local turnUI = nil
                local turnStart = tick()
                while (tick() - turnStart) < 10 do
                    if rareFoundPause then break end
                    turnUI = findBattleUI()
                    if turnUI and (turnUI.fightButton or hasAnyMove(turnUI)) then break end
                    heartbeat:Wait()
                end

                if not turnUI or (not turnUI.fightButton and not hasAnyMove(turnUI)) then
                    turnUI = { fightButton = nil, moveButtons = {}, moveNames = {} }
                end

                local clickedSomething = false

                if turnUI.fightButton and not hasAnyMove(turnUI) then
                    if turnCount == 1 then
                        addBattleLog("🤖 [" .. modeLabel .. "] MOVE ▸ fighting...", battleType == "Wild" and C.Green or C.Orange)
                    end
                    clickButton(turnUI.fightButton)
                    clickedSomething = true

                    local moveUI = nil
                    local moveStart = tick()
                    local lastRetry = moveStart
                    while (tick() - moveStart) < 3 do
                        heartbeat:Wait()
                        moveUI = findBattleUI()
                        if moveUI and hasAnyMove(moveUI) then break end
                        if (tick() - lastRetry) >= 0.3 then
                            lastRetry = tick()
                            local retryUI = findBattleUI()
                            if retryUI and retryUI.fightButton and not hasAnyMove(retryUI) then
                                clickButton(retryUI.fightButton)
                            end
                        end
                    end

                    if moveUI and hasAnyMove(moveUI) then
                        local targetSlot = math.clamp(effectiveSlot, 1, 4)
                        if moveUI.moveButtons[targetSlot] then
                            log("AUTO", "[" .. modeLabel .. "] turn " .. turnCount .. " Move" .. targetSlot)
                            addBattleLog("🤖 T" .. turnCount .. " [" .. modeLabel .. "] ▸ Move " .. targetSlot, battleType == "Wild" and C.Green or C.Orange)
                            clickButton(moveUI.moveButtons[targetSlot])
                        else
                            for s = 1, 4 do
                                if moveUI.moveButtons[s] then
                                    addBattleLog("🤖 T" .. turnCount .. " [" .. modeLabel .. "] ▸ Move " .. s .. " (fb)", C.Orange)
                                    clickButton(moveUI.moveButtons[s])
                                    break
                                end
                            end
                        end
                    else
                        addBattleLog("⚠ No move buttons T" .. turnCount, C.Orange)
                    end
                elseif hasAnyMove(turnUI) then
                    clickedSomething = true
                    local targetSlot = math.clamp(effectiveSlot, 1, 4)
                    if turnUI.moveButtons[targetSlot] then
                        clickButton(turnUI.moveButtons[targetSlot])
                        addBattleLog("🤖 T" .. turnCount .. " [" .. modeLabel .. "] ▸ Move " .. targetSlot, battleType == "Wild" and C.Green or C.Orange)
                    else
                        for s = 1, 4 do
                            if turnUI.moveButtons[s] then
                                clickButton(turnUI.moveButtons[s])
                                addBattleLog("🤖 T" .. turnCount .. " ▸ Move " .. s .. " (fb)", C.Orange)
                                break
                            end
                        end
                    end
                end

                if clickedSomething then
                    local vanishStart = tick()
                    local lastMoveRetry = vanishStart
                    while (tick() - vanishStart) < 2 do
                        local vUI = findBattleUI()
                        if not vUI or not hasAnyMove(vUI) then break end
                        if (tick() - lastMoveRetry) >= 0.3 and vUI then
                            lastMoveRetry = tick()
                            local retrySlot = math.clamp(effectiveSlot, 1, 4)
                            if vUI.moveButtons[retrySlot] then
                                clickButton(vUI.moveButtons[retrySlot])
                            else
                                for s = 1, 4 do if vUI.moveButtons[s] then clickButton(vUI.moveButtons[s]); break end end
                            end
                        end
                        heartbeat:Wait()
                    end

                    local waitStart = tick()
                    while (tick() - waitStart) < 30 do
                        if rareFoundPause then break end
                        local checkUI = findBattleUI()
                        if checkUI and (checkUI.fightButton or hasAnyMove(checkUI)) then break end
                        if not checkUI and (tick() - waitStart) > 5 then
                            if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                                log("AUTO", "[" .. modeLabel .. "] battle ended (no UI for 5s)")
                                addBattleLog("🤖 [" .. modeLabel .. "] done (" .. turnCount .. " turns)", battleType == "Wild" and C.Green or C.Orange)
                                break
                            end
                        end
                        heartbeat:Wait()
                    end

                    local finalCheck = findBattleUI()
                    if not finalCheck then
                        log("AUTO", "[" .. modeLabel .. "] ended after " .. turnCount .. " turns")
                        addBattleLog("🤖 [" .. modeLabel .. "] done (" .. turnCount .. " turns)", battleType == "Wild" and C.Green or C.Orange)
                        break
                    end
                end
            end
        end

        task.wait(1)
        if battleState == "active" then
            battleState = "idle"
            stateVal.Text = "Idle"
            stateVal.TextColor3 = C.TextDim
        end
        pendingAutoAction = false
    end)
end

--==================================================
-- BATTLE PROCESSING
--==================================================
local function extractNameAndSide(cmdEntry)
    local cmd = cmdEntry[1]
    if type(cmd) ~= "string" then return nil end
    local cmdL = string.lower(cmd)
    if cmdL ~= "owm" and cmdL ~= "switch" then return nil end

    local rawName, side, infoStr = nil, nil, nil

    for i = 2, math.min(#cmdEntry, 8) do
        local v = cmdEntry[i]
        if type(v) == "string" then
            if (v == "p1" or v == "p2") and not side then
                side = v
            elseif string.find(v, ":%s*.+") then
                local n = v:match(":%s*(.+)$")
                if n then rawName = n end
                if string.find(v, "p1") then side = side or "p1"
                elseif string.find(v, "p2") then side = side or "p2" end
            elseif string.find(v, ", L%d+") then
                infoStr = v
                if not rawName then rawName = v:match("^([^,]+)") end
            end
        elseif type(v) == "table" and not rawName then
            if type(v.name) == "string" then rawName = v.name end
        end
    end

    if rawName then
        return rawName, side, infoStr, extractLoomianName(rawName)
    end
    return nil
end

local KNOWN_COMMANDS = {
    player = true, owm = true, switch = true, start = true,
    move = true, damage = true, ["-damage"] = true,
    turn = true, faint = true, ["end"] = true,
}

local function processBattleCommands(commandTable)
    log("BATTLE", "========== PROCESSING " .. tostring(#commandTable) .. " COMMANDS ==========")
    addBattleLog(">>> " .. tostring(#commandTable) .. " battle cmds <<<", C.Green)

    for _, entry in pairs(commandTable) do
        if type(entry) == "table" and type(entry[1]) == "string" and string.lower(entry[1]) == "start" then
            log("BATTLE", "  NEW BATTLE (start found)")
            resetBattle()
            currentBattle.active = true
            btnsScanned = false  -- reset button cache for new battle
            break
        end
    end

    for _, entry in pairs(commandTable) do
        if type(entry) == "table" and type(entry[1]) == "string" and string.lower(entry[1]) == "player" then
            local side = entry[2]
            local tag = entry[3]
            log("BATTLE", "  player cmd: side=" .. tostring(side) .. " tag=" .. tostring(tag))
            if type(tag) == "string" then
                if string.find(tag, "#Wild") then
                    currentBattle.battleType = "Wild"
                elseif side == "p2" then
                    currentBattle.battleType = "Trainer"
                end
            end
        end
    end

    for _, entry in pairs(commandTable) do
        if type(entry) == "table" and type(entry[1]) == "string" then
            local cmdL = string.lower(entry[1])
            if cmdL == "owm" or cmdL == "switch" then
                local rawName, side, infoStr, displayName = extractNameAndSide(entry)
                if rawName then
                    local stats = parseLoomianStats(infoStr)
                    log("BATTLE", "  " .. entry[1] .. ": name=" .. displayName .. " side=" .. tostring(side))
                    if side == "p2" then
                        currentBattle.enemy = displayName
                        currentBattle.enemyStats = stats
                        currentBattle.enemyRawEntry = entry
                    elseif side == "p1" then
                        currentBattle.player = displayName
                        currentBattle.playerStats = stats
                    else
                        if not currentBattle.enemy then
                            currentBattle.enemy = displayName
                            currentBattle.enemyStats = stats
                            currentBattle.enemyRawEntry = entry
                        elseif not currentBattle.player then
                            currentBattle.player = displayName
                            currentBattle.playerStats = stats
                        end
                    end
                end
            end
        end
    end

    if not currentBattle.enemy then
        for _, entry in pairs(commandTable) do
            if type(entry) == "table" and type(entry[1]) == "string" then
                local cmdL = string.lower(entry[1])
                if cmdL == "move" or cmdL == "damage" or cmdL == "-damage" then
                    for i = 2, #entry do
                        if type(entry[i]) == "string" then
                            local pNum, name = entry[i]:match("p(%d+)%a*:%s*(.+)$")
                            if pNum == "2" and name then
                                currentBattle.enemy = extractLoomianName(name)
                                break
                            end
                        end
                    end
                    if currentBattle.enemy then break end
                end
            end
        end
    end

    -- Mastery tracking
    for _, entry in pairs(commandTable) do
        if type(entry) == "table" and type(entry[1]) == "string" then
            local cmdL = string.lower(entry[1])
            if cmdL == "faint" then
                if type(entry[2]) == "string" and string.find(entry[2], "p2") then
                    sessionKOs = sessionKOs + 1
                    UI.sessionLbl.Text = string.format("Session: %d KOs | %.1fk Damage", sessionKOs, sessionDamage / 1000)
                end
            elseif cmdL == "-damage" or cmdL == "damage" then
                if type(entry[2]) == "string" and string.find(entry[2], "p2") then
                    sessionDamage = sessionDamage + 100
                    UI.sessionLbl.Text = string.format("Session: %d KOs | %.1fk Damage", sessionKOs, sessionDamage / 1000)
                end
            end
        end
    end

    battleState = "active"
    lastBattleTick = tick()
    currentBattle.active = true
    stateVal.Text = "In Battle"
    stateVal.TextColor3 = C.Green

    local enemyName = currentBattle.enemy or "Unknown"
    local playerName = currentBattle.player or "Unknown"
    log("BATTLE", "RESULT: Enemy=" .. enemyName .. " Player=" .. playerName .. " Type=" .. currentBattle.battleType)

    if currentBattle.battleType == "Wild" then
        typeVal.Text = "Wild"; typeVal.TextColor3 = C.Wild
    elseif currentBattle.battleType == "Trainer" then
        typeVal.Text = "Trainer"; typeVal.TextColor3 = C.Trainer
    end

    if enemyName ~= "Unknown" and not currentBattle.enemyProcessed then
        currentBattle.enemyProcessed = true
        cachedMoveNames = {}

        if currentBattle.battleType == "Wild" then
            UI.encounterCount = UI.encounterCount + 1
            UI.encounterVal.Text = tostring(UI.encounterCount)
            table.insert(UI.encounterHistory, 1, { name = enemyName, time = os.date("%X") })
            if #UI.encounterHistory > 10 then table.remove(UI.encounterHistory, 11) end
        end

        -- Multi-layer rare check
        local rareFound = isRareLoomian(enemyName) or isRareModifier(enemyName)
        if not rareFound and currentBattle.enemyRawEntry then
            rareFound = scanEntryForRare(currentBattle.enemyRawEntry)
            if rareFound then log("RARE", "!!! DEEP SCAN caught rare in model/disc data !!!") end
        end

        if rareFound then
            enemyLbl.Text = 'Enemy: <font color="#FFD700">⭐ ' .. enemyName .. ' (RARE!)</font>'
            addBattleLog("⭐ RARE: " .. enemyName, C.Gold)
            rareFoundPause = true
            updateAutoUI()
            if currentEnemy ~= enemyName then
                currentEnemy = enemyName
                raresFoundCount = raresFoundCount + 1
                playRareSound()
                sendNotification("⭐ LumiWare", "RARE: " .. enemyName .. "! Automation PAUSED.", 10)
                addRareLog(enemyName, currentBattle.enemyStats and ("Lv." .. tostring(currentBattle.enemyStats.level)) or nil)
                sendRareWebhook(enemyName, currentBattle.enemyStats and currentBattle.enemyStats.level,
                    currentBattle.enemyStats and currentBattle.enemyStats.gender or "?",
                    UI.encounterCount, formatTime(tick() - UI.huntStartTime))
            end
        else
            enemyLbl.Text = "Enemy: " .. enemyName
            addBattleLog(currentBattle.battleType .. ": " .. enemyName, C.TextDim)
            currentEnemy = nil
            -- Trigger appropriate automation
            if not rareFoundPause then
                performAutoAction(currentBattle.battleType)
            end
        end
    end

    if currentBattle.enemyStats then
        local s = currentBattle.enemyStats
        local g = s.gender == "M" and "♂" or (s.gender == "F" and "♀" or "?")
        enemyStatsLbl.Text = string.format("Lv.%d  %s  HP %d/%d", s.level or 0, g, s.hp or 0, s.maxHP or 0)
    end

    if playerName ~= "Unknown" then
        playerLbl.Text = "Your Loomian: " .. playerName
        if currentBattle.playerStats then
            local s = currentBattle.playerStats
            local g = s.gender == "M" and "♂" or (s.gender == "F" and "♀" or "?")
            playerLbl.Text = playerLbl.Text .. string.format("  (Lv.%d %s HP %d/%d)", s.level or 0, g, s.hp or 0, s.maxHP or 0)
        end
    end

    log("BATTLE", "========== DONE ==========")
end

--==================================================
-- HOOK REMOTES
--==================================================
local hooked = {}
local hookedCount = 0

local function hookEvent(remote)
    if hooked[remote] then return end
    hooked[remote] = true
    hookedCount = hookedCount + 1

    track(remote.OnClientEvent:Connect(function(...)
        local argCount = select("#", ...)
        local allArgs = {}
        for i = 1, argCount do allArgs[i] = select(i, ...) end
        allArgs.n = argCount

        if discoveryMode then
            local parts = {}
            for i = 1, argCount do
                local a = allArgs[i]
                local info = "arg" .. i .. "=" .. type(a)
                if type(a) == "string" then info = info .. '("' .. string.sub(a, 1, 20) .. '")'
                elseif type(a) == "table" then
                    local c = 0
                    for _ in pairs(a) do c = c + 1 end
                    info = info .. "(n=" .. c .. ")"
                end
                table.insert(parts, info)
            end
            addBattleLog("📡 " .. remote.Name .. " | " .. table.concat(parts, ", "), Color3.fromRGB(180, 180, 180))
            if VERBOSE_MODE then
                for i = 1, argCount do
                    local a = allArgs[i]
                    if type(a) == "table" then log("EVT", remote.Name, "arg" .. i .. ":", tablePreview(a)) end
                end
            end
        end

        local isBattle = false
        if type(allArgs[1]) == "string" then
            if string.lower(allArgs[1]):find("battle") then isBattle = true end
        end

        local cmdTable = nil
        for i = 1, argCount do
            local arg = allArgs[i]
            if type(arg) == "table" then
                for k, v in pairs(arg) do
                    if type(v) == "table" then
                        local first = v[1]
                        if type(first) == "string" and KNOWN_COMMANDS[string.lower(first)] then
                            cmdTable = arg; break
                        end
                    elseif type(v) == "string" and string.sub(v, 1, 1) == "[" then
                        local ok2, decoded = pcall(function() return HttpService:JSONDecode(v) end)
                        if ok2 and type(decoded) == "table" and type(decoded[1]) == "string" then
                            local cmd = string.lower(decoded[1])
                            if KNOWN_COMMANDS[cmd] then
                                local decodedTable = {}
                                for key, val in pairs(arg) do
                                    if type(val) == "string" and string.sub(val, 1, 1) == "[" then
                                        local ok3, dec3 = pcall(function() return HttpService:JSONDecode(val) end)
                                        decodedTable[key] = (ok3 and type(dec3) == "table") and dec3 or val
                                    elseif type(val) == "string" and string.sub(val, 1, 1) == "{" then
                                        local ok3, dec3 = pcall(function() return HttpService:JSONDecode(val) end)
                                        decodedTable[key] = (ok3 and type(dec3) == "table") and dec3 or val
                                    else
                                        decodedTable[key] = val
                                    end
                                end
                                cmdTable = decodedTable; break
                            end
                        end
                    end
                end
                if cmdTable then break end
            end
        end

        if cmdTable then
            processBattleCommands(cmdTable)
        elseif isBattle then
            logDebug("BattleEvent no cmd table, arg3=" .. tostring(allArgs[3]))
        end
    end))
end

log("HOOK", "Scanning...")
local c = 0
for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
    if obj:IsA("RemoteEvent") then hookEvent(obj); c = c + 1 end
end
log("HOOK", "Hooked", c, "from ReplicatedStorage")

track(ReplicatedStorage.DescendantAdded:Connect(function(obj)
    if obj:IsA("RemoteEvent") then hookEvent(obj) end
end))

pcall(function()
    for _, obj in ipairs(game:GetService("Workspace"):GetDescendants()) do
        if obj:IsA("RemoteEvent") then hookEvent(obj) end
    end
end)
pcall(function()
    for _, obj in ipairs(player:WaitForChild("PlayerGui"):GetDescendants()) do
        if obj:IsA("RemoteEvent") then hookEvent(obj) end
    end
end)

--==================================================
-- TIMER + SESSION THREADS
--==================================================
local timerThread = task.spawn(function()
    while not _G.LumiWare_StopFlag do
        if not gui.Parent then break end
        local elapsed = tick() - UI.huntStartTime
        timerVal.Text = formatTime(elapsed)
        local minutes = elapsed / 60
        if minutes > 0 then epmVal.Text = string.format("%.1f", UI.encounterCount / minutes) end
        if battleState == "active" and (tick() - lastBattleTick) > 8 then
            battleState = "idle"
            stateVal.Text = "Idle"
            stateVal.TextColor3 = C.TextDim
            if rareFoundPause then
                rareFoundPause = false
                updateAutoUI()
                log("AUTO", "Battle ended: Rare pause lifted.")
            end
        end
        task.wait(1)
    end
end)
if _G.LumiWare_Threads then table.insert(_G.LumiWare_Threads, timerThread) end

local webhookThread = task.spawn(function()
    local lastMs = 0
    while not _G.LumiWare_StopFlag do
        if not gui.Parent then break end
        if UI.encounterCount > 0 and UI.encounterCount % 50 == 0 and UI.encounterCount ~= lastMs then
            lastMs = UI.encounterCount
            sendSessionWebhook(UI.encounterCount, formatTime(tick() - UI.huntStartTime), raresFoundCount)
        end
        task.wait(5)
    end
end)
if _G.LumiWare_Threads then table.insert(_G.LumiWare_Threads, webhookThread) end

-- Try to find previously configured heal remote on startup
if UI.healRemoteName ~= "" then
    task.spawn(function()
        task.wait(3) -- Wait for remotes to be ready
        local found = false
        for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
            if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) and obj.Name == UI.healRemoteName then
                UI.healRemote = obj
                addHealLog("✅ Restored heal remote from config: " .. UI.healRemoteName, C.Teal)
                UI.healSelectedName.Text = "Remote: " .. UI.healRemoteName
                UI.healSelectedName.TextColor3 = C.Teal
                UI.healSelectedPath.Text = getFullPath(obj)
                found = true
                break
            end
        end
        if not found then
            addHealLog("⚠ Saved heal remote not found: " .. UI.healRemoteName, C.Orange)
        end
    end)
end

addBattleLog("Hooked " .. hookedCount .. " remotes — READY", C.Green)
addBattleLog("v4.6: Trainer Auto + Auto-Heal + Config Tab", C.Accent)
log("INFO", "LumiWare " .. VERSION .. " READY | Hooked " .. hookedCount .. " | Player: " .. PLAYER_NAME)
sendNotification("⚡ LumiWare " .. VERSION, "Ready! Hooked " .. hookedCount .. " remotes.\nTrainer Auto + Auto-Heal active.", 6)


--------------------------------------------------------------------------------
-- AUTO FISH MODULE
--------------------------------------------------------------------------------
local waterClickedOriginal = nil
task.spawn(function()
    while not gameAPI do task.wait() end
    if gameAPI.Fishing then
        waterClickedOriginal = gameAPI.Fishing.OnWaterClicked
        
        local waterTarget = nil
        task.spawn(function()
            while task.wait(1) do
                pcall(function()
                    if waterTarget and not waterTarget:IsDescendantOf(workspace) then
                        waterTarget = nil
                    end
                    if gameAPI.DataManager.currentChunk and gameAPI.DataManager.currentChunk.map then
                        for _, p in ipairs(gameAPI.DataManager.currentChunk.map:GetChildren()) do
                            local w = (p.Name == "Water" and p) or p:FindFirstChild("Water")
                            if w and w:FindFirstChild("Mesh") then
                                waterTarget = w
                            end
                        end
                    end
                end)
            end
        end)
        
        -- Hook OnWaterClicked to prevent manual fishing if auto fish is on
        function gameAPI.Fishing.OnWaterClicked(...)
            if gameAPI.MasterControl.WalkEnabled then
                if config.autoFishEnabled then
                    if IrisNotificationMrJack then
                        IrisNotificationMrJack(1, "Notification", "Please Turn Off Auto Fish.", 2)
                    end
                    return
                end
                return waterClickedOriginal(...)
            end
        end
        
        -- Custom Fish MiniGame Handler
        local function performFishMiniGame(customFlag)
            local fishReg = gameAPI.DataManager.currentChunk.regionData.Fishing
            if not fishReg then
                for k, v in pairs(gameAPI.DataManager.currentChunk.regionData) do
                    if type(v) == "table" and k == "Fishing" and v.id then
                        fishReg = v
                        break
                    end
                end
            end
            
            if not fishReg and gameAPI.DataManager.currentChunk.data.regions then
                for _, rData in pairs(gameAPI.DataManager.currentChunk.data.regions) do
                    for k, v in pairs(rData) do
                        if not fishReg and type(v) == "table" and k == "Fishing" and v.id then
                            fishReg = v
                            break
                        end
                    end
                end
            end
            
            local fishId = type(fishReg) == "table" and fishReg.id or fishReg
            
            if waterTarget and fishId then
                local rod = gameAPI.Fishing.rod
                local fshData
                
                if customFlag == "MrJack" then
                    local wPos = waterTarget.Position + Vector3.new(0, waterTarget.Size.Y - 5, 0)
                    local rp = RaycastParams.new()
                    rp.FilterDescendantsInstances = {workspace.Terrain}
                    rp.IgnoreWater = false
                    rp.FilterType = Enum.RaycastFilterType.Whitelist
                    local hit = workspace:Raycast(wPos + Vector3.new(0, 3, 0), Vector3.new(0.001, -10, 0.001), rp)
                    if hit and hit.Material == Enum.Material.Water then
                        wPos = hit.Position
                    end
                    
                    if rod then
                        rod.postPoseUpdates = true
                    else
                        local fModel
                        fModel, _ = gameAPI.Network:get("PDS", "fish", wPos, fishId)
                        rod = fModel and {model = fModel, bobberMain = fModel.Bobber.Main, string = fModel.Bobber.Main.String} or rod
                        gameAPI.Fishing.rod = rod
                    end
                    
                    fshData = select(2, gameAPI.Network:get("PDS", "fish", wPos, fishId))
                    if fshData and gameAPI.Fishing.rod then
                        gameAPI.Fishing.rod.postPoseUpdates = fshData.rep
                    end
                    if rod and rod.model then
                        rod.model.Parent = nil
                    end
                else
                    fshData = {delay = true}
                end
                
                if fshData and fshData.delay then
                    return 0.9, gameAPI.Network:get("PDS", "fshchi", fshData.id), fishReg
                end
            end
            return false
        end

        -- Active fishing loop
        task.spawn(function()
            while task.wait(0.5) do
                pcall(function()
                    if config.autoFishEnabled and gameAPI.PlayerData.completedEvents.mabelRt8 then
                        local pct, doCatch, fReg = performFishMiniGame("MrJack")
                        if pct and config.autoFishEnabled then
                            if doCatch == true then
                                gameAPI.Battle:doWildBattle(fReg, {dontExclaim = true, fshPct = pct})
                            else
                                gameAPI.Network:post("PDS", "reelIn")
                            end
                        end
                        if gameAPI.Fishing.DisableRodModel then
                            gameAPI.Fishing:DisableRodModel(doCatch ~= true and true or nil)
                        end
                    end
                end)
            end
        end)
    end
end)

--------------------------------------------------------------------------------
-- MASTERY PROGRESS HOOK
--------------------------------------------------------------------------------
task.spawn(function()
    while not gameAPI do task.wait() end
    if gameAPI.Menu and gameAPI.Menu.mastery and gameAPI.Menu.mastery.showProgressUpdate then
        local oldMastery = gameAPI.Menu.mastery.showProgressUpdate
        gameAPI.Menu.mastery.showProgressUpdate = function(...)
            if config.masteryDisable then
                return -- Block popups
            end
            return oldMastery(...)
        end
    end
end)



--------------------------------------------------------------------------------
-- DIALOGUE & POPUP INTERCEPTOR (Rewritten to match original exactly)
--
-- CRITICAL INSIGHT from the original obfuscated code (v112/vu106):
-- The original's wrapper NEVER calls the original message/Say function.
-- For deny cases, the original REPLACES the [y/n] text with plain text
-- (removing the [y/n] prefix), then calls original → game shows text but
-- doesn't prompt for Y/N since the prefix is gone → auto-advances.
-- For "give up learning", returns true to auto-answer Yes.
-- For skip dialogue, filters out non-interactive text.
--------------------------------------------------------------------------------
task.spawn(function()
    -- MUST wait for gameAPIReady (not just gameAPI) to ensure aliases are in place
    while not gameAPIReady do task.wait() end
    
    -- Core dialogue processor — returns (processedArgs, shouldShow)
    -- This mirrors vu106 from the original exactly.
    local function processDialogue(funcName, ...)
        local args = {...}
        local processed = {}
        local shouldShow = nil
        
        if type(args[2]) == "string" then
            local msg = args[2]
            
            -- [NoSkip] messages must always be shown
            if msg:sub(1, 8) == "[NoSkip]" then
                return {args[1], msg:sub(9)}, true
            end
            
            -- Handle [y/n] prompts — deny logic
            -- Key: we REPLACE the text (removing [y/n] prefix so game doesn't
            -- prompt for user input), then let it fall through to display.
            if msg:sub(1, 5):lower() == "[y/n]" then
                if config.autoDenySwitch and msg:find("Will you switch Loomians") then
                    args[2] = "Auto Deny Switch Question Enabled!"
                elseif config.autoDenyNick and msg:find("Give a nickname to the") then
                    args[2] = "Auto Deny Nickname Enabled!"
                elseif config.autoDenyMove then
                    if msg:find("reassign its moves") then
                        args[2] = "Auto Deny Reassign Move Enabled!"
                    elseif msg:find(" to give up on learning ") then
                        -- Answer "Yes" to give up learning the move
                        return "Y/N", true
                    end
                end
            end
        end
        
        -- Skip Dialogue mode: filter out non-interactive text
        if config.autoSkipDialogue then
            for _, v in ipairs(args) do
                if type(v) ~= "string" then
                    table.insert(processed, v)
                else
                    local vLower = v:lower()
                    if vLower:sub(1, 5) == "[y/n]" then
                        -- Keep Y/N prompts (unless already handled by deny above)
                        table.insert(processed, v)
                        shouldShow = true
                    elseif vLower:sub(1, 9) == "[gamepad]" then
                        local stripped = v:sub(10)
                        if stripped:sub(1, 4):lower() == "[ma]" or stripped:sub(1, 5) == "[pma]" then
                            table.insert(processed, v)
                            shouldShow = true
                        end
                    elseif vLower:sub(1, 4) == "[ma]" or vLower:sub(1, 5) == "[pma]" then
                        table.insert(processed, v)
                        shouldShow = true
                    end
                    -- Other plain strings are filtered out (skipped)
                end
            end
        else
            -- Skip dialogue is OFF — pass everything through
            processed = args
            shouldShow = true
        end
        
        return processed, shouldShow
    end
    
    -- Hook that wraps the function (matching original's v112 pattern)
    local function hookDialogueFunc(tbl, funcName)
        if not tbl or not tbl[funcName] then return false end
        local original = tbl[funcName]
        tbl[funcName] = function(...)
            local result, shouldShow = processDialogue(funcName, ...)
            
            -- "Y/N" means auto-answer the question
            if result == "Y/N" then
                return shouldShow  -- true = Yes
            end
            
            -- If shouldShow is truthy, call original with processed args
            -- The original function handles displaying and yielding
            if shouldShow then
                setThreadContext(2)
                return original(unpack(result))
            end
            
            -- shouldShow is falsy: dialogue should be skipped.
            -- Don't call original — no yield happens, game continues.
            return
        end
        log("HOOK", "Dialogue function '" .. funcName .. "' hooked on table")
        return true
    end

    -- Try to hook using canonical names first
    local hookedMessage = false
    local hookedSay = false
    local hookedSayLower = false
    
    -- Try BattleGui.message
    if gameAPI.BattleGui then
        hookedMessage = hookDialogueFunc(gameAPI.BattleGui, "message")
    end
    
    -- Try NPCChat.Say / .say
    if gameAPI.NPCChat then
        hookedSay = hookDialogueFunc(gameAPI.NPCChat, "Say")
        hookedSayLower = hookDialogueFunc(gameAPI.NPCChat, "say")
    end
    
    -- FALLBACK: If hooks failed, scan ALL gameAPI sub-tables for matching functions
    if not hookedMessage or (not hookedSay and not hookedSayLower) then
        log("HOOK", "Dialogue fallback: scanning gameAPI for message/Say functions...")
        for k, v in pairs(gameAPI) do
            if type(v) == "table" then
                -- Look for tables with "message" function (BattleGui equivalent)
                if not hookedMessage and type(rawget(v, "message")) == "function" then
                    hookedMessage = hookDialogueFunc(v, "message")
                    if hookedMessage then
                        log("HOOK", "Found 'message' on gameAPI." .. tostring(k))
                        -- Also alias it for future use
                        if not gameAPI.BattleGui then gameAPI.BattleGui = v end
                    end
                end
                -- Look for tables with "Say" function (NPCChat equivalent)
                if not hookedSay and type(rawget(v, "Say")) == "function" then
                    hookedSay = hookDialogueFunc(v, "Say")
                    if hookedSay then
                        log("HOOK", "Found 'Say' on gameAPI." .. tostring(k))
                        if not gameAPI.NPCChat then gameAPI.NPCChat = v end
                    end
                end
                if not hookedSayLower and type(rawget(v, "say")) == "function" then
                    hookedSayLower = hookDialogueFunc(v, "say")
                    if hookedSayLower then
                        log("HOOK", "Found 'say' on gameAPI." .. tostring(k))
                        if not gameAPI.NPCChat then gameAPI.NPCChat = v end
                    end
                end
            end
        end
    end
    
    -- Log final status
    if hookedMessage then log("HOOK", "✓ BattleGui.message dialogue hook active")
    else log("WARN", "✗ Could not find BattleGui.message to hook") end
    if hookedSay or hookedSayLower then log("HOOK", "✓ NPCChat.Say dialogue hook active")
    else log("WARN", "✗ Could not find NPCChat.Say to hook") end
end)



--------------------------------------------------------------------------------
-- AUTO RALLY MODULE (Rewritten with DataManager.setLoading + Utilities.Sync)
-- Matches original's approach exactly: check rallied, build decisions, submit.
--------------------------------------------------------------------------------
task.spawn(function()
    while not gameAPIReady do task.wait() end
    
    task.spawn(function()
        while task.wait(3) do
            pcall(function()
                if not config.autoRally or not gameAPI then return end
                if not gameAPI.Network then return end
                
                local ralliedData = gameAPI.Network:get("PDS", "getRallied")
                if not ralliedData then return end
                
                local monsters = ralliedData.monsters
                if not monsters or not monsters[1] then return end
                
                local decisions = {}
                local loadingKeys = {}
                
                for idx, mon in pairs(monsters) do
                    -- Count max IVs (6 = perfect 40, which is max in Loomian Legacy)
                    local maxIVCount = 0
                    pcall(function()
                        if mon.summ and mon.summ.ivr then
                            for _, iv in pairs(mon.summ.ivr) do
                                if iv == 6 then maxIVCount = maxIVCount + 1 end
                            end
                        end
                    end)
                    
                    local keep = false
                    
                    -- Keep gleaming (mon.gl is truthy for gleam)
                    if config.rallyKeepGleam and mon.gl then
                        keep = true
                    end
                    
                    -- Keep hidden ability (mon.sa is truthy for secret ability)
                    if config.rallyKeepHA and mon.sa then
                        keep = true
                    end
                    
                    -- Decision: 2 = keep, 1 = release
                    decisions[idx] = keep and 2 or 1
                    
                    log("RALLY", string.format("Mon #%s: gl=%s sa=%s ivMax=%d → %s",
                        tostring(idx), tostring(mon.gl), tostring(mon.sa),
                        maxIVCount, keep and "KEEP" or "RELEASE"))
                end
                
                -- Use DataManager.setLoading if available (prevents UI race conditions)
                pcall(function()
                    if gameAPI.DataManager and gameAPI.DataManager.setLoading then
                        gameAPI.DataManager:setLoading(loadingKeys, true)
                    end
                end)
                
                -- Submit decisions
                setThreadContext(2)
                local result = gameAPI.Network:get("PDS", "handleRallied", decisions)
                
                pcall(function()
                    if gameAPI.DataManager and gameAPI.DataManager.setLoading then
                        gameAPI.DataManager:setLoading(loadingKeys, false)
                    end
                end)
                
                if result then
                    pcall(function()
                        if gameAPI.Menu and gameAPI.Menu.rally then
                            gameAPI.Menu.rally.ralliedCount = result
                            if gameAPI.Menu.rally.updateNPCBubble then
                                gameAPI.Menu.rally.updateNPCBubble(result)
                            end
                        end
                    end)
                    log("RALLY", "Handled rallied batch, new count: " .. tostring(result))
                end
                
                -- Show mastery progress if included in response
                pcall(function()
                    if ralliedData.mastery and gameAPI.Menu and gameAPI.Menu.mastery then
                        gameAPI.Menu.mastery:showProgressUpdate(ralliedData.mastery, false)
                    end
                end)
            end)
        end
    end)
end)



--------------------------------------------------------------------------------
-- AUTO ENCOUNTER MODULE
--------------------------------------------------------------------------------
task.spawn(function()
    while not gameAPIReady do task.wait() end
    
    -- Extract onStepTaken from WalkEvents.beginLoop upvalues (matching original approach)
    local stepFunction = nil
    
    -- Strategy 1: Use debug.getinfo to find by name
    pcall(function()
        if gameAPI.WalkEvents and gameAPI.WalkEvents.beginLoop then
            local getInfo = debug.getinfo or (getgenv and getgenv().getinfo)
            if getupvalues then
                local upvals = getupvalues(gameAPI.WalkEvents.beginLoop)
                if type(upvals) == "table" then
                    for _, v in pairs(upvals) do
                        if type(v) == "function" and getInfo then
                            local ok, info = pcall(getInfo, v)
                            if ok and info and info.name == "onStepTaken" then
                                stepFunction = v
                                break
                            end
                        end
                    end
                end
            end
        end
    end)
    
    -- Strategy 2: If debug.getinfo didn't work, try to find by argument count
    if not stepFunction then
        pcall(function()
            if gameAPI.WalkEvents and gameAPI.WalkEvents.beginLoop and getupvalues then
                local upvals = getupvalues(gameAPI.WalkEvents.beginLoop)
                if type(upvals) == "table" then
                    for _, v in pairs(upvals) do
                        if type(v) == "function" then
                            -- onStepTaken takes a single boolean arg; try calling with true
                            -- We can't test it, but if there's only one function upvalue, use it
                            if not stepFunction then
                                stepFunction = v
                            end
                        end
                    end
                end
            end
        end)
    end
    
    if stepFunction then
        log("ENCOUNTER", "Successfully extracted onStepTaken function")
    else
        log("ENCOUNTER", "Could not find onStepTaken — auto encounter will use fallback")
    end
    
    task.spawn(function()
        while task.wait(0.1) do
            pcall(function()
                if not config.autoEncounter or not gameAPI then return end
                
                -- Check preconditions
                local canRun = false
                pcall(function()
                    canRun = gameAPI.MasterControl and gameAPI.MasterControl.WalkEnabled
                        and gameAPI.Menu and gameAPI.Menu.enabled
                        and not (gameAPI.Battle and gameAPI.Battle.currentBattle)
                        and gameAPI.PlayerData and gameAPI.PlayerData.completedEvents
                        and gameAPI.PlayerData.completedEvents.ChooseBeginner
                end)
                if not canRun then return end
                
                -- Check health before encounter (matching original vu25 logic)
                if config.autoHealEnabled then
                    local ok, fullHP = pcall(function()
                        return gameAPI.Network:get("PDS", "areFullHealth")
                    end)
                    if ok and not fullHP then return end
                end
                
                if stepFunction then
                    setThreadContext(2)
                    stepFunction(true)
                end
            end)
        end
    end)
end)



--------------------------------------------------------------------------------
-- EXPLOIT HOOKS (Fast Battle, Unstuck, UMV, Fish)
--------------------------------------------------------------------------------
task.spawn(function()
    while not gameAPIReady do task.wait() end

    -- Background enforcer loop for exploits
    local fishHooked = false
    task.spawn(function()
        while task.wait(0.5) do
            pcall(function()
                -- Skip Fish Minigame (hook once, check config dynamically)
                if not fishHooked and gameAPI.Fishing and gameAPI.Fishing.FishMiniGame then
                    local origFishMini = gameAPI.Fishing.FishMiniGame
                    gameAPI.Fishing.FishMiniGame = function(...)
                        if config.skipFish then
                            -- Skip the minigame and return a successful catch
                            return 0.9, gameAPI.Network:get("PDS", "fshchi", nil), nil
                        end
                        return origFishMini(...)
                    end
                    fishHooked = true
                end
                
                -- Unstuck cooldown removal is already handled in gameAPI init,
                -- but re-enforce in case it gets overwritten
                if config.noUnstuck and gameAPI.Menu and gameAPI.Menu.options then
                    gameAPI.Menu.options.resetLastUnstuckTick = function() end
                end
                
                -- Infinite UMV energy
                if config.infUMV then
                    pcall(function()
                        local mining = gameAPI.DataManager:getModule("Mining")
                        if mining then
                            mining.DecrementBattery = function() end
                            mining.SetBattery = function() end
                        end
                    end)
                end
            end)
        end
    end)
    
    -- Fast Battle Hook (Animations speedup)
    -- The original uses specific parameter indices for the battle object.
    -- BattleClientSprite functions use parameter index 1 (self) which has .battle
    -- BattleClientSide functions use parameter index 1 (self) which has .battle
    pcall(function()
        local function hookAnimWithBattleIdx(tbl, propName, battleParamIdx)
            if tbl and tbl[propName] then
                local old = tbl[propName]
                tbl[propName] = function(...)
                    setThreadContext(2)
                    local args = {...}
                    local battleObj = nil
                    pcall(function()
                        if args[battleParamIdx] and args[battleParamIdx].battle then
                            battleObj = args[battleParamIdx].battle
                        end
                    end)
                    if config.fastBattle and battleObj then
                        battleObj.fastForward = true
                    end
                    local ret = {old(unpack(args))}
                    if battleObj then
                        battleObj.fastForward = false
                    end
                    return unpack(ret)
                end
            end
        end

        -- BattleClientSprite: these functions have the battle holder at specific indices
        local bc = gameAPI.BattleClientSprite
        if bc then
            local spriteAnims = {
                {name = "animFaint", idx = 1},
                {name = "animSummon", idx = 1},
                {name = "animUnsummon", idx = 1},
                {name = "monsterIn", idx = 1},
                {name = "monsterOut", idx = 1},
                {name = "animEmulate", idx = 1},
                {name = "animScapegoat", idx = 1},
                {name = "animScapegoatFade", idx = 1},
                {name = "animRecolor", idx = 1},
            }
            for _, animInfo in ipairs(spriteAnims) do
                hookAnimWithBattleIdx(bc, animInfo.name, animInfo.idx)
            end
        end
        
        -- BattleClientSide: same pattern
        local bs = gameAPI.BattleClientSide
        if bs then
            local sideAnims = {
                {name = "switchOut", idx = 1},
                {name = "faint", idx = 1},
                {name = "swapTo", idx = 1},
                {name = "dragIn", idx = 1},
            }
            for _, animInfo in ipairs(sideAnims) do
                hookAnimWithBattleIdx(bs, animInfo.name, animInfo.idx)
            end
        end
        
        -- Hook BattleGui animations (these should be skipped entirely during fast battle)
        local bgui = gameAPI.BattleGui
        if bgui then
            local guiAnims = {"animWeather", "animStatus", "animAbility", "animBoost", "animHit", "animMove"}
            for _, animName in ipairs(guiAnims) do
                if bgui[animName] then
                    local orig = bgui[animName]
                    bgui[animName] = function(...)
                        setThreadContext(2)
                        if config.fastBattle then return end
                        return orig(...)
                    end
                end
            end
        end
        
        -- Hook setCameraIfLookingAway
        if bgui and bgui.setCameraIfLookingAway then
            local origCam = bgui.setCameraIfLookingAway
            bgui.setCameraIfLookingAway = function(self, battleObj, ...)
                if config.fastBattle and battleObj then
                    battleObj.fastForward = true
                end
                local ret = {origCam(self, battleObj, ...)}
                if battleObj then battleObj.fastForward = false end
                return unpack(ret)
            end
        end
        
        -- Hook setFillbarRatio for instant HP bars during fast battle
        if gameAPI.RoundedFrame and gameAPI.RoundedFrame.setFillbarRatio then
            local origFillbar = gameAPI.RoundedFrame.setFillbarRatio
            gameAPI.RoundedFrame.setFillbarRatio = function(...)
                local args = {...}
                if config.fastBattle then
                    -- Disable animation on the fillbar (arg 3 = animate flag)
                    args[3] = false
                end
                return origFillbar(unpack(args))
            end
        end
        
        log("HOOK", "Fast battle animations hooked successfully")
    end)
end)
