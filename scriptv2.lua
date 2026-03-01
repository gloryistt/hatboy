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
    healRemoteName = "",         -- Scanned heal remote name
    healRemotePath = "",         -- Full path
    autoHealMethod = "remote",   -- "remote" or "button"
    healButtonPath = "",
    automateTrainer = true,
    automateWild = true,
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
-- RARE LOOMIANS
--------------------------------------------------
local RARE_LOOMIANS = {
    "Duskit", "Ikazune", "Mutagon", "Metronette", "Wabalisc",
    "Cephalops", "Elephage", "Gargolem", "Celesting", "Nyxre", "Pyramind",
    "Terracolt", "Garbantis", "Avitross", "Snocub", "Eaglit", "Grimyuline",
    "Vambat", "Weevolt", "Nevermare", "Ikazune", "Protogon", "Mimask", "Odoyaga", "Yari",
    "Akhalos", "Odasho", "Cosmiore", "Dakuda", "Shawchi", "Arceros", "Galacadia"
}
local customRares = config.customRares or {}

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
    for _, r in ipairs(customRares) do
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
local encounterCount = 0
local huntStartTime = tick()
local currentEnemy = nil
local isMinimized = false
local battleState = "idle"
local lastBattleTick = 0
local raresFoundCount = 0
local encounterHistory = {}
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

-- NEW v4.6: Auto-heal
local autoHealEnabled = config.autoHealEnabled or false
local autoHealThreshold = config.autoHealThreshold or 30
local healRemote = nil
local healRemoteName = config.healRemoteName or ""
local healRemotePath = config.healRemotePath or ""
local scannedHealRemotes = {}  -- list of {name, path, remote}
local autoHealMethod = config.autoHealMethod or "remote"
local healButtonPath = config.healButtonPath or ""
local lastHealTime = 0
local healCooldown = 10  -- seconds between heals

-- Battle filter flags
local automateTrainer = (config.automateTrainer ~= false)
local automateWild = (config.automateWild ~= false)

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
local mainScale = Instance.new("UIScale", mainFrame)
mainScale.Scale = 0.9

Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)
createShadow(mainFrame, 15, Vector2.new(0, 4))
local stroke = Instance.new("UIStroke", mainFrame)
stroke.Color = C.Accent
stroke.Thickness = 1.5
stroke.Transparency = 0.5

-- SPLASH
local splashFrame = Instance.new("Frame", mainFrame)
splashFrame.Size = UDim2.fromScale(1, 1)
splashFrame.BackgroundTransparency = 0
splashFrame.BackgroundColor3 = C.BG
splashFrame.ZIndex = 100
Instance.new("UICorner", splashFrame).CornerRadius = UDim.new(0, 12)
local splashGrad = Instance.new("UIGradient", splashFrame)
splashGrad.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, C.AccentDim),
    ColorSequenceKeypoint.new(1, C.BG)
}
splashGrad.Rotation = 90

local splashLogo = Instance.new("TextLabel", splashFrame)
splashLogo.Size = UDim2.fromScale(1, 1)
splashLogo.BackgroundTransparency = 1
splashLogo.Text = "⚡ LumiWare " .. VERSION
splashLogo.Font = Enum.Font.GothamBlack
splashLogo.TextSize = 34
splashLogo.TextColor3 = C.Text
splashLogo.ZIndex = 101

local splashUIScale = Instance.new("UIScale", splashLogo)
splashUIScale.Scale = 0.8

task.spawn(function()
    TweenService:Create(mainFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {GroupTransparency = 0}):Play()
    TweenService:Create(splashUIScale, TweenInfo.new(1.2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Scale = 1.05}):Play()
    task.wait(1.5)
    TweenService:Create(splashFrame, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundTransparency = 1}):Play()
    TweenService:Create(splashLogo, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 1}):Play()
    TweenService:Create(mainScale, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
    task.wait(0.6)
    splashFrame:Destroy()
end)

-- TOPBAR
local topbar = Instance.new("Frame", mainFrame)
topbar.Size = UDim2.new(1, 0, 0, 36)
topbar.BackgroundColor3 = C.TopBar
topbar.BorderSizePixel = 0
Instance.new("UICorner", topbar).CornerRadius = UDim.new(0, 10)
local topFill = Instance.new("Frame", topbar)
topFill.Size = UDim2.new(1, 0, 0, 10)
topFill.Position = UDim2.new(0, 0, 1, -10)
topFill.BackgroundColor3 = C.TopBar
topFill.BorderSizePixel = 0

local titleLbl = Instance.new("TextLabel", topbar)
titleLbl.Size = UDim2.new(1, -80, 1, 0)
titleLbl.Position = UDim2.new(0, 12, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "⚡ LumiWare " .. VERSION
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 15
titleLbl.TextColor3 = C.Accent
titleLbl.TextXAlignment = Enum.TextXAlignment.Left

local minBtn = Instance.new("TextButton", topbar)
minBtn.Size = UDim2.fromOffset(28, 28)
minBtn.Position = UDim2.new(1, -66, 0, 4)
minBtn.BackgroundColor3 = C.PanelAlt
minBtn.Text = "–"
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 18
minBtn.TextColor3 = C.Text
minBtn.BorderSizePixel = 0
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)
addHoverEffect(minBtn, C.PanelAlt, C.AccentDim)

local closeBtn = Instance.new("TextButton", topbar)
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 4)
closeBtn.BackgroundColor3 = C.PanelAlt
closeBtn.Text = "×"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 18
closeBtn.TextColor3 = C.Text
closeBtn.BorderSizePixel = 0
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
addHoverEffect(closeBtn, C.PanelAlt, C.Red)

closeBtn.MouseButton1Click:Connect(function()
    local elapsed = tick() - huntStartTime
    sendSessionWebhook(encounterCount, formatTime(elapsed), raresFoundCount)
    gui:Destroy()
end)

-- Drag
local dragging, dragInput, dragStart, startPos
track(topbar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = mainFrame.Position
        track(input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end))
    end
end))
track(topbar.InputChanged:Connect(function(input)
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
local tabBar = Instance.new("Frame", mainFrame)
tabBar.Size = UDim2.new(1, -16, 0, 30)
tabBar.Position = UDim2.new(0, 8, 0, 44)
tabBar.BackgroundTransparency = 1
local tabLayout = Instance.new("UIListLayout", tabBar)
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
tabLayout.Padding = UDim.new(0, 4)

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

local huntTabBtn = mkTabBtn(tabBar, "🗡️ HUNT")
local masteryTabBtn = mkTabBtn(tabBar, "📖 MASTERY")
local healTabBtn = mkTabBtn(tabBar, "💊 HEAL")
local cfgTabBtn = mkTabBtn(tabBar, "⚙️ CONFIG")

-- CONTENT WRAPPER
local contentContainer = Instance.new("Frame", mainFrame)
contentContainer.Name = "ContentContainer"
contentContainer.Size = UDim2.new(1, -16, 1, -82)
contentContainer.Position = UDim2.new(0, 8, 0, 78)
contentContainer.BackgroundTransparency = 1

-- forward decl for addBattleLog
local addBattleLog

--==================================================
-- MASTERY FRAME
--==================================================
local masteryFrame = Instance.new("Frame", contentContainer)
masteryFrame.Size = UDim2.new(1, 0, 1, 0)
masteryFrame.BackgroundTransparency = 1
masteryFrame.Visible = false

local masterySearch = Instance.new("TextBox", masteryFrame)
masterySearch.Size = UDim2.new(1, 0, 0, 36)
masterySearch.BackgroundColor3 = C.Panel
masterySearch.Text = ""
masterySearch.PlaceholderText = "🔍 Search Loomian..."
masterySearch.Font = Enum.Font.GothamBold
masterySearch.TextSize = 13
masterySearch.TextColor3 = C.Text
masterySearch.BorderSizePixel = 0
masterySearch.ClearTextOnFocus = false
Instance.new("UICorner", masterySearch).CornerRadius = UDim.new(0, 6)
local searchPadding = Instance.new("UIPadding", masterySearch)
searchPadding.PaddingLeft = UDim.new(0, 12)

local masterySessionPanel = Instance.new("Frame", masteryFrame)
masterySessionPanel.Size = UDim2.new(1, 0, 0, 24)
masterySessionPanel.Position = UDim2.new(0, 0, 0, 44)
masterySessionPanel.BackgroundTransparency = 1
local sessionLbl = Instance.new("TextLabel", masterySessionPanel)
sessionLbl.Size = UDim2.new(1, 0, 1, 0)
sessionLbl.BackgroundTransparency = 1
sessionLbl.Text = "Session: 0 KOs | 0.0k Damage"
sessionLbl.Font = Enum.Font.GothamBold
sessionLbl.TextSize = 11
sessionLbl.TextColor3 = C.TextDim
sessionLbl.TextXAlignment = Enum.TextXAlignment.Left

local masteryScroll = Instance.new("ScrollingFrame", masteryFrame)
masteryScroll.Size = UDim2.new(1, 0, 1, -76)
masteryScroll.Position = UDim2.new(0, 0, 0, 76)
masteryScroll.BackgroundTransparency = 1
masteryScroll.BorderSizePixel = 0
masteryScroll.ScrollBarThickness = 4
masteryScroll.ScrollBarImageColor3 = C.AccentDim

local masteryListLayout = Instance.new("UIListLayout", masteryScroll)
masteryListLayout.SortOrder = Enum.SortOrder.LayoutOrder
masteryListLayout.Padding = UDim.new(0, 8)

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
    for _, v in ipairs(masteryScroll:GetChildren()) do
        if v:IsA("Frame") then v:Destroy() end
    end
    local results = searchMastery(query)
    if not query or query == "" then results = MASTERY_DATA end
    local count = 0
    for i = 1, math.min(#results, 50) do
        local card = renderMasteryFamily(results[i])
        card.Parent = masteryScroll
        count = count + 1
    end
    masteryScroll.CanvasSize = UDim2.new(0, 0, 0, count * 118)
end

masterySearch:GetPropertyChangedSignal("Text"):Connect(function()
    populateMasteryList(masterySearch.Text)
end)
populateMasteryList("")

--==================================================
-- CONFIG TAB FRAME (NEW)
--==================================================
local cfgFrame = Instance.new("ScrollingFrame", contentContainer)
cfgFrame.Size = UDim2.new(1, 0, 1, 0)
cfgFrame.BackgroundTransparency = 1
cfgFrame.BorderSizePixel = 0
cfgFrame.ScrollBarThickness = 4
cfgFrame.ScrollBarImageColor3 = C.AccentDim
cfgFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
cfgFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
cfgFrame.Visible = false
local cfgLayout = Instance.new("UIListLayout", cfgFrame)
cfgLayout.SortOrder = Enum.SortOrder.LayoutOrder
cfgLayout.Padding = UDim.new(0, 8)

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
local cfgSummSec, _ = mkCfgSection(cfgFrame, "📋 CURRENT CONFIG", C.Accent)
cfgSummSec.Size = UDim2.new(1, -8, 0, 200)

local cfgAutoModeRow, cfgAutoModeVal = mkCfgRow(cfgSummSec, 30, "Wild Auto Mode:", config.autoMode, C.Green)
local cfgTrainerModeRow, cfgTrainerModeVal = mkCfgRow(cfgSummSec, 56, "Trainer Auto Mode:", config.trainerAutoMode, C.Orange)
local cfgWildSlotRow, cfgWildSlotVal = mkCfgRow(cfgSummSec, 82, "Wild Move Slot:", config.autoMoveSlot, C.Text)
local cfgTrainerSlotRow, cfgTrainerSlotVal = mkCfgRow(cfgSummSec, 108, "Trainer Move Slot:", config.trainerAutoMoveSlot, C.Text)
local cfgHealRow, cfgHealVal = mkCfgRow(cfgSummSec, 134, "Auto-Heal:", config.autoHealEnabled and "ON" or "OFF", C.Teal)
local cfgThreshRow, cfgThreshVal = mkCfgRow(cfgSummSec, 160, "Heal Threshold:", config.autoHealThreshold .. "%", C.Teal)

-- Section 2: Webhook Config
local cfgWhSec, _ = mkCfgSection(cfgFrame, "📡 WEBHOOK CONFIG", C.Cyan)
cfgWhSec.Size = UDim2.new(1, -8, 0, 96)

local cfgWhInput = Instance.new("TextBox", cfgWhSec)
cfgWhInput.Size = UDim2.new(1, -80, 0, 26)
cfgWhInput.Position = UDim2.new(0, 8, 0, 30)
cfgWhInput.BackgroundColor3 = C.PanelAlt
cfgWhInput.BorderSizePixel = 0
cfgWhInput.PlaceholderText = "Discord webhook URL..."
cfgWhInput.Text = config.webhookUrl or ""
cfgWhInput.Font = Enum.Font.Gotham
cfgWhInput.TextSize = 10
cfgWhInput.TextColor3 = C.Text
cfgWhInput.ClearTextOnFocus = false
cfgWhInput.TextXAlignment = Enum.TextXAlignment.Left
Instance.new("UICorner", cfgWhInput).CornerRadius = UDim.new(0, 5)
Instance.new("UIPadding", cfgWhInput).PaddingLeft = UDim.new(0, 6)

local cfgWhSave = mkSmallBtn(cfgWhSec, "SAVE", 0, 30, 60, 26, C.Cyan)
cfgWhSave.Position = UDim2.new(1, -68, 0, 30)
cfgWhSave.TextColor3 = C.BG

local cfgPingInput = Instance.new("TextBox", cfgWhSec)
cfgPingInput.Size = UDim2.new(1, -16, 0, 22)
cfgPingInput.Position = UDim2.new(0, 8, 0, 64)
cfgPingInput.BackgroundColor3 = C.PanelAlt
cfgPingInput.BorderSizePixel = 0
cfgPingInput.PlaceholderText = "Ping user IDs (e.g. <@12345>) or @everyone"
cfgPingInput.Text = config.pingIds or ""
cfgPingInput.Font = Enum.Font.Gotham
cfgPingInput.TextSize = 10
cfgPingInput.TextColor3 = C.Text
cfgPingInput.ClearTextOnFocus = false
cfgPingInput.TextXAlignment = Enum.TextXAlignment.Left
Instance.new("UICorner", cfgPingInput).CornerRadius = UDim.new(0, 5)
Instance.new("UIPadding", cfgPingInput).PaddingLeft = UDim.new(0, 6)

-- Section 3: Custom Rares
local cfgRareSec, _ = mkCfgSection(cfgFrame, "⭐ CUSTOM RARES", C.Gold)
cfgRareSec.Size = UDim2.new(1, -8, 0, 80)

local cfgRareInput = Instance.new("TextBox", cfgRareSec)
cfgRareInput.Size = UDim2.new(1, -100, 0, 26)
cfgRareInput.Position = UDim2.new(0, 8, 0, 30)
cfgRareInput.BackgroundColor3 = C.PanelAlt
cfgRareInput.BorderSizePixel = 0
cfgRareInput.PlaceholderText = "e.g. Twilat, Cathorn..."
cfgRareInput.Text = ""
cfgRareInput.Font = Enum.Font.Gotham
cfgRareInput.TextSize = 11
cfgRareInput.TextColor3 = C.Text
cfgRareInput.ClearTextOnFocus = false
cfgRareInput.TextXAlignment = Enum.TextXAlignment.Left
Instance.new("UICorner", cfgRareInput).CornerRadius = UDim.new(0, 5)
Instance.new("UIPadding", cfgRareInput).PaddingLeft = UDim.new(0, 6)

local cfgRareAdd = mkSmallBtn(cfgRareSec, "+ ADD", 0, 30, 42, 26, C.Green)
cfgRareAdd.Position = UDim2.new(1, -90, 0, 30)
cfgRareAdd.TextColor3 = C.BG
local cfgRareClear = mkSmallBtn(cfgRareSec, "CLEAR", 0, 30, 42, 26, C.Red)
cfgRareClear.Position = UDim2.new(1, -44, 0, 30)

local cfgRareCountLbl = Instance.new("TextLabel", cfgRareSec)
cfgRareCountLbl.Size = UDim2.new(1, -16, 0, 18)
cfgRareCountLbl.Position = UDim2.new(0, 8, 0, 58)
cfgRareCountLbl.BackgroundTransparency = 1
cfgRareCountLbl.Font = Enum.Font.Gotham
cfgRareCountLbl.TextSize = 10
cfgRareCountLbl.TextColor3 = C.TextDim
cfgRareCountLbl.TextXAlignment = Enum.TextXAlignment.Left

local function updateRareCount()
    cfgRareCountLbl.Text = #customRares .. " custom rares: " .. (
        #customRares > 0 and table.concat(customRares, ", ") or "(none)"
    )
end
updateRareCount()

-- Section 4: Save/Reset
local cfgSaveSec, _ = mkCfgSection(cfgFrame, "💾 SAVE / RESET CONFIG", C.Green)
cfgSaveSec.Size = UDim2.new(1, -8, 0, 80)

local cfgSaveBtn = mkSmallBtn(cfgSaveSec, "💾 SAVE ALL", 8, 30, 130, 28, C.Green)
cfgSaveBtn.TextColor3 = C.BG
cfgSaveBtn.TextSize = 12
local cfgResetBtn = mkSmallBtn(cfgSaveSec, "🔄 RESET DEFAULTS", 0, 30, 150, 28, C.Red)
cfgResetBtn.Position = UDim2.new(1, -158, 0, 30)
cfgResetBtn.TextSize = 11

local cfgStatusLbl = Instance.new("TextLabel", cfgSaveSec)
cfgStatusLbl.Size = UDim2.new(1, -16, 0, 18)
cfgStatusLbl.Position = UDim2.new(0, 8, 0, 60)
cfgStatusLbl.BackgroundTransparency = 1
cfgStatusLbl.Text = "Config saved at: never"
cfgStatusLbl.Font = Enum.Font.Gotham
cfgStatusLbl.TextSize = 10
cfgStatusLbl.TextColor3 = C.TextDim
cfgStatusLbl.TextXAlignment = Enum.TextXAlignment.Left

-- Section 5: Bot Filters
local cfgFilterSec, _ = mkCfgSection(cfgFrame, "🎯 BATTLE TYPE FILTER", C.Pink)
cfgFilterSec.Size = UDim2.new(1, -8, 0, 80)

local wildFilterBtn = mkSmallBtn(cfgFilterSec, "Wild: ON", 8, 30, 100, 26, automateWild and C.Wild or C.PanelAlt)
local trainerFilterBtn = mkSmallBtn(cfgFilterSec, "Trainer: ON", 116, 30, 100, 26, automateTrainer and C.Trainer or C.PanelAlt)

local cfgFilterLbl = Instance.new("TextLabel", cfgFilterSec)
cfgFilterLbl.Size = UDim2.new(1, -16, 0, 18)
cfgFilterLbl.Position = UDim2.new(0, 8, 0, 58)
cfgFilterLbl.BackgroundTransparency = 1
cfgFilterLbl.Text = "Controls which battle types trigger automation"
cfgFilterLbl.Font = Enum.Font.Gotham
cfgFilterLbl.TextSize = 10
cfgFilterLbl.TextColor3 = C.TextDim
cfgFilterLbl.TextXAlignment = Enum.TextXAlignment.Left

--==================================================
-- HEAL TAB FRAME (NEW v4.6)
--==================================================
local healFrame = Instance.new("ScrollingFrame", contentContainer)
healFrame.Size = UDim2.new(1, 0, 1, 0)
healFrame.BackgroundTransparency = 1
healFrame.BorderSizePixel = 0
healFrame.ScrollBarThickness = 4
healFrame.ScrollBarImageColor3 = C.AccentDim
healFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
healFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
healFrame.Visible = false
local healTabLayout = Instance.new("UIListLayout", healFrame)
healTabLayout.SortOrder = Enum.SortOrder.LayoutOrder
healTabLayout.Padding = UDim.new(0, 8)

-- Section: Auto-Heal Toggle
local healToggleSec = Instance.new("Frame", healFrame)
healToggleSec.Size = UDim2.new(1, -8, 0, 90)
healToggleSec.BackgroundColor3 = C.Panel
healToggleSec.BorderSizePixel = 0
Instance.new("UICorner", healToggleSec).CornerRadius = UDim.new(0, 8)

local healToggleLbl = Instance.new("TextLabel", healToggleSec)
healToggleLbl.Size = UDim2.new(1, -16, 0, 24)
healToggleLbl.Position = UDim2.new(0, 8, 0, 4)
healToggleLbl.BackgroundTransparency = 1
healToggleLbl.Text = "💊 AUTO-HEAL"
healToggleLbl.Font = Enum.Font.GothamBold
healToggleLbl.TextSize = 12
healToggleLbl.TextColor3 = C.Teal
healToggleLbl.TextXAlignment = Enum.TextXAlignment.Left

local healOnBtn = mkSmallBtn(healToggleSec, "ENABLE", 8, 30, 80, 26, autoHealEnabled and C.Teal or C.AccentDim)
local healOffBtn = mkSmallBtn(healToggleSec, "DISABLE", 96, 30, 80, 26, not autoHealEnabled and C.Red or C.AccentDim)

local healThreshLbl = Instance.new("TextLabel", healToggleSec)
healThreshLbl.Size = UDim2.new(0, 100, 0, 22)
healThreshLbl.Position = UDim2.new(0, 8, 0, 60)
healThreshLbl.BackgroundTransparency = 1
healThreshLbl.Text = "Heal when HP <"
healThreshLbl.Font = Enum.Font.Gotham
healThreshLbl.TextSize = 11
healThreshLbl.TextColor3 = C.TextDim
healThreshLbl.TextXAlignment = Enum.TextXAlignment.Left

local healThreshInput = Instance.new("TextBox", healToggleSec)
healThreshInput.Size = UDim2.fromOffset(50, 22)
healThreshInput.Position = UDim2.new(0, 112, 0, 60)
healThreshInput.BackgroundColor3 = C.PanelAlt
healThreshInput.BorderSizePixel = 0
healThreshInput.Text = tostring(autoHealThreshold)
healThreshInput.Font = Enum.Font.GothamBold
healThreshInput.TextSize = 12
healThreshInput.TextColor3 = C.Teal
healThreshInput.ClearTextOnFocus = false
healThreshInput.TextXAlignment = Enum.TextXAlignment.Center
Instance.new("UICorner", healThreshInput).CornerRadius = UDim.new(0, 5)

local healThreshPctLbl = Instance.new("TextLabel", healToggleSec)
healThreshPctLbl.Size = UDim2.fromOffset(20, 22)
healThreshPctLbl.Position = UDim2.new(0, 166, 0, 60)
healThreshPctLbl.BackgroundTransparency = 1
healThreshPctLbl.Text = "%"
healThreshPctLbl.Font = Enum.Font.GothamBold
healThreshPctLbl.TextSize = 12
healThreshPctLbl.TextColor3 = C.Teal

-- Section: Heal Remote Scanner
local healScanSec = Instance.new("Frame", healFrame)
healScanSec.Size = UDim2.new(1, -8, 0, 120)
healScanSec.BackgroundColor3 = C.Panel
healScanSec.BorderSizePixel = 0
Instance.new("UICorner", healScanSec).CornerRadius = UDim.new(0, 8)

local healScanTitle = Instance.new("TextLabel", healScanSec)
healScanTitle.Size = UDim2.new(1, -16, 0, 24)
healScanTitle.Position = UDim2.new(0, 8, 0, 4)
healScanTitle.BackgroundTransparency = 1
healScanTitle.Text = "🔍 HEAL REMOTE SCANNER"
healScanTitle.Font = Enum.Font.GothamBold
healScanTitle.TextSize = 12
healScanTitle.TextColor3 = C.Teal
healScanTitle.TextXAlignment = Enum.TextXAlignment.Left

local healScanBtn = mkSmallBtn(healScanSec, "🔍 SCAN REMOTES", 8, 30, 140, 26, C.Teal)
healScanBtn.TextColor3 = C.BG
local healScanBtnBtn = mkSmallBtn(healScanSec, "🔍 SCAN BUTTONS", 156, 30, 140, 26, C.Cyan)
healScanBtnBtn.TextColor3 = C.BG

local healScanStatusLbl = Instance.new("TextLabel", healScanSec)
healScanStatusLbl.Size = UDim2.new(1, -16, 0, 18)
healScanStatusLbl.Position = UDim2.new(0, 8, 0, 62)
healScanStatusLbl.BackgroundTransparency = 1
healScanStatusLbl.Text = "▸ Press Scan to find heal remotes"
healScanStatusLbl.Font = Enum.Font.Gotham
healScanStatusLbl.TextSize = 10
healScanStatusLbl.TextColor3 = C.TextDim
healScanStatusLbl.TextXAlignment = Enum.TextXAlignment.Left

-- Heal remote list (scrollable)
local healRemoteScroll = Instance.new("ScrollingFrame", healScanSec)
healRemoteScroll.Size = UDim2.new(1, -16, 0, 40)
healRemoteScroll.Position = UDim2.new(0, 8, 0, 78)
healRemoteScroll.BackgroundColor3 = C.PanelAlt
healRemoteScroll.BorderSizePixel = 0
healRemoteScroll.ScrollBarThickness = 3
healRemoteScroll.ScrollBarImageColor3 = C.Teal
healRemoteScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
healRemoteScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Instance.new("UICorner", healRemoteScroll).CornerRadius = UDim.new(0, 5)
local healRemoteLayout = Instance.new("UIListLayout", healRemoteScroll)
healRemoteLayout.SortOrder = Enum.SortOrder.LayoutOrder
healRemoteLayout.Padding = UDim.new(0, 2)

-- Section: Selected Heal Remote Display
local healSelectedSec = Instance.new("Frame", healFrame)
healSelectedSec.Size = UDim2.new(1, -8, 0, 100)
healSelectedSec.BackgroundColor3 = C.Panel
healSelectedSec.BorderSizePixel = 0
Instance.new("UICorner", healSelectedSec).CornerRadius = UDim.new(0, 8)

local healSelectedTitle = Instance.new("TextLabel", healSelectedSec)
healSelectedTitle.Size = UDim2.new(1, -16, 0, 24)
healSelectedTitle.Position = UDim2.new(0, 8, 0, 4)
healSelectedTitle.BackgroundTransparency = 1
healSelectedTitle.Text = "✅ SELECTED HEAL SOURCE"
healSelectedTitle.Font = Enum.Font.GothamBold
healSelectedTitle.TextSize = 12
healSelectedTitle.TextColor3 = C.Teal
healSelectedTitle.TextXAlignment = Enum.TextXAlignment.Left

local healSelectedName = Instance.new("TextLabel", healSelectedSec)
healSelectedName.Size = UDim2.new(1, -16, 0, 18)
healSelectedName.Position = UDim2.new(0, 8, 0, 30)
healSelectedName.BackgroundTransparency = 1
healSelectedName.Text = healRemoteName ~= "" and ("Remote: " .. healRemoteName) or "None selected"
healSelectedName.Font = Enum.Font.GothamBold
healSelectedName.TextSize = 12
healSelectedName.TextColor3 = healRemoteName ~= "" and C.Teal or C.TextDim
healSelectedName.TextXAlignment = Enum.TextXAlignment.Left

local healSelectedPath = Instance.new("TextLabel", healSelectedSec)
healSelectedPath.Size = UDim2.new(1, -16, 0, 16)
healSelectedPath.Position = UDim2.new(0, 8, 0, 50)
healSelectedPath.BackgroundTransparency = 1
healSelectedPath.Text = healRemotePath ~= "" and healRemotePath or "Path: —"
healSelectedPath.Font = Enum.Font.Code
healSelectedPath.TextSize = 9
healSelectedPath.TextColor3 = C.TextDim
healSelectedPath.TextXAlignment = Enum.TextXAlignment.Left
healSelectedPath.TextTruncate = Enum.TextTruncate.AtEnd

local healTestBtn = mkSmallBtn(healSelectedSec, "🧪 TEST HEAL NOW", 8, 70, 140, 22, C.Teal)
healTestBtn.TextColor3 = C.BG
local healClearBtn = mkSmallBtn(healSelectedSec, "❌ CLEAR", 0, 70, 70, 22, C.Red)
healClearBtn.Position = UDim2.new(1, -78, 0, 70)

-- Section: Auto-Heal Log
local healLogSec = Instance.new("Frame", healFrame)
healLogSec.Size = UDim2.new(1, -8, 0, 100)
healLogSec.BackgroundColor3 = C.Panel
healLogSec.BorderSizePixel = 0
Instance.new("UICorner", healLogSec).CornerRadius = UDim.new(0, 8)

local healLogTitle = Instance.new("TextLabel", healLogSec)
healLogTitle.Size = UDim2.new(1, -16, 0, 24)
healLogTitle.Position = UDim2.new(0, 8, 0, 4)
healLogTitle.BackgroundTransparency = 1
healLogTitle.Text = "📋 HEAL LOG"
healLogTitle.Font = Enum.Font.GothamBold
healLogTitle.TextSize = 12
healLogTitle.TextColor3 = C.Teal
healLogTitle.TextXAlignment = Enum.TextXAlignment.Left

local healLogScroll = Instance.new("ScrollingFrame", healLogSec)
healLogScroll.Size = UDim2.new(1, -16, 1, -32)
healLogScroll.Position = UDim2.new(0, 8, 0, 28)
healLogScroll.BackgroundTransparency = 1
healLogScroll.ScrollBarThickness = 3
healLogScroll.ScrollBarImageColor3 = C.Teal
healLogScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
healLogScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
local healLogLayout = Instance.new("UIListLayout", healLogScroll)
healLogLayout.SortOrder = Enum.SortOrder.LayoutOrder
healLogLayout.Padding = UDim.new(0, 2)

local healLogOrder = 0
local function addHealLog(text, color)
    healLogOrder = healLogOrder + 1
    local item = Instance.new("TextLabel")
    item.Size = UDim2.new(1, 0, 0, 16)
    item.BackgroundTransparency = 1
    item.Text = "[" .. os.date("%X") .. "] " .. text
    item.Font = Enum.Font.Code
    item.TextSize = 10
    item.TextColor3 = color or C.Teal
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.TextTruncate = Enum.TextTruncate.AtEnd
    item.LayoutOrder = healLogOrder
    item.Parent = healLogScroll
end

--==================================================
-- HUNT FRAME
--==================================================
local contentFrame = Instance.new("Frame", contentContainer)
contentFrame.Name = "HuntFrame"
contentFrame.Size = UDim2.new(1, 0, 1, 0)
contentFrame.BackgroundTransparency = 1
contentFrame.Visible = true

-- TAB SWITCH LOGIC
local function switchTab(active)
    local tabs = {hunt=contentFrame, mastery=masteryFrame, heal=healFrame, cfg=cfgFrame}
    local btns = {hunt=huntTabBtn, mastery=masteryTabBtn, heal=healTabBtn, cfg=cfgTabBtn}
    for name, frame in pairs(tabs) do
        frame.Visible = (name == active)
        TweenService:Create(btns[name], TweenInfo.new(0.2), {
            BackgroundColor3 = (name == active) and C.Accent or C.PanelAlt,
            TextColor3 = (name == active) and C.Text or C.TextDim,
        }):Play()
    end
end

huntTabBtn.MouseButton1Click:Connect(function() switchTab("hunt") end)
masteryTabBtn.MouseButton1Click:Connect(function() switchTab("mastery") end)
healTabBtn.MouseButton1Click:Connect(function() switchTab("heal") end)
cfgTabBtn.MouseButton1Click:Connect(function() switchTab("cfg") end)
switchTab("hunt")

-- STATS BAR
local statsBar = Instance.new("Frame", contentFrame)
statsBar.Size = UDim2.new(1, 0, 0, 50)
statsBar.BackgroundColor3 = C.Panel
statsBar.BorderSizePixel = 0
Instance.new("UICorner", statsBar).CornerRadius = UDim.new(0, 8)
local statsLayout = Instance.new("UIListLayout", statsBar)
statsLayout.FillDirection = Enum.FillDirection.Horizontal
statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
statsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
statsLayout.Padding = UDim.new(0, 4)

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

local encounterVal = makeStatCell(statsBar, "ENCOUNTERS", "0", C.Green)
local epmVal = makeStatCell(statsBar, "ENC/MIN", "0.0", C.Text)
local timerVal = makeStatCell(statsBar, "HUNT TIME", "0m 00s", C.Text)
local typeVal = makeStatCell(statsBar, "BATTLE", "N/A", C.TextDim)
local stateVal = makeStatCell(statsBar, "STATUS", "Idle", C.TextDim)

-- ENCOUNTER PANEL
local encounterPanel = Instance.new("Frame", contentFrame)
encounterPanel.Size = UDim2.new(1, 0, 0, 90)
encounterPanel.Position = UDim2.new(0, 0, 0, 56)
encounterPanel.BackgroundColor3 = C.Panel
encounterPanel.BorderSizePixel = 0
Instance.new("UICorner", encounterPanel).CornerRadius = UDim.new(0, 8)
local encTitle = Instance.new("TextLabel", encounterPanel)
encTitle.Size = UDim2.new(1, -16, 0, 24)
encTitle.Position = UDim2.new(0, 8, 0, 4)
encTitle.BackgroundTransparency = 1
encTitle.Text = "CURRENT ENCOUNTER"
encTitle.Font = Enum.Font.GothamBold
encTitle.TextSize = 11
encTitle.TextColor3 = C.Accent
encTitle.TextXAlignment = Enum.TextXAlignment.Left

local enemyLbl = Instance.new("TextLabel", encounterPanel)
enemyLbl.Size = UDim2.new(1, -16, 0, 22)
enemyLbl.Position = UDim2.new(0, 8, 0, 28)
enemyLbl.BackgroundTransparency = 1
enemyLbl.Text = "Enemy: Waiting for battle..."
enemyLbl.Font = Enum.Font.GothamMedium
enemyLbl.TextSize = 15
enemyLbl.TextColor3 = C.Text
enemyLbl.TextXAlignment = Enum.TextXAlignment.Left
enemyLbl.RichText = true

local enemyStatsLbl = Instance.new("TextLabel", encounterPanel)
enemyStatsLbl.Size = UDim2.new(1, -16, 0, 18)
enemyStatsLbl.Position = UDim2.new(0, 8, 0, 48)
enemyStatsLbl.BackgroundTransparency = 1
enemyStatsLbl.Text = ""
enemyStatsLbl.Font = Enum.Font.Gotham
enemyStatsLbl.TextSize = 12
enemyStatsLbl.TextColor3 = C.TextDim
enemyStatsLbl.TextXAlignment = Enum.TextXAlignment.Left

local playerLbl = Instance.new("TextLabel", encounterPanel)
playerLbl.Size = UDim2.new(1, -16, 0, 18)
playerLbl.Position = UDim2.new(0, 8, 0, 68)
playerLbl.BackgroundTransparency = 1
playerLbl.Text = "Your Loomian: —"
playerLbl.Font = Enum.Font.Gotham
playerLbl.TextSize = 12
playerLbl.TextColor3 = C.TextDim
playerLbl.TextXAlignment = Enum.TextXAlignment.Left

-- RARE LOG
local logPanel = Instance.new("Frame", contentFrame)
logPanel.Size = UDim2.new(1, 0, 0, 80)
logPanel.Position = UDim2.new(0, 0, 0, 152)
logPanel.BackgroundColor3 = C.Panel
logPanel.BorderSizePixel = 0
Instance.new("UICorner", logPanel).CornerRadius = UDim.new(0, 8)
local logTitle = Instance.new("TextLabel", logPanel)
logTitle.Size = UDim2.new(1, -16, 0, 24)
logTitle.Position = UDim2.new(0, 8, 0, 4)
logTitle.BackgroundTransparency = 1
logTitle.Text = "⭐ RARE FINDER LOG"
logTitle.Font = Enum.Font.GothamBold
logTitle.TextSize = 11
logTitle.TextColor3 = C.Gold
logTitle.TextXAlignment = Enum.TextXAlignment.Left
local rareScroll = Instance.new("ScrollingFrame", logPanel)
rareScroll.Size = UDim2.new(1, -16, 1, -32)
rareScroll.Position = UDim2.new(0, 8, 0, 28)
rareScroll.BackgroundTransparency = 1
rareScroll.ScrollBarThickness = 3
rareScroll.ScrollBarImageColor3 = C.Accent
rareScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
rareScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
local logLayout = Instance.new("UIListLayout", rareScroll)
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Padding = UDim.new(0, 3)

local logOrder = 0
local function addRareLog(name, extraInfo)
    logOrder = logOrder + 1
    local item = Instance.new("TextLabel")
    item.Size = UDim2.new(1, 0, 0, 20)
    item.BackgroundTransparency = 1
    item.Text = "⭐ [" .. os.date("%X") .. "] " .. name .. (extraInfo and (" — " .. extraInfo) or "")
    item.Font = Enum.Font.GothamMedium
    item.TextSize = 12
    item.TextColor3 = C.Gold
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.LayoutOrder = logOrder
    item.Parent = rareScroll
end

-- WEBHOOK PANEL (compact, in hunt tab)
local whPanel = Instance.new("Frame", contentFrame)
whPanel.Size = UDim2.new(1, 0, 0, 56)
whPanel.Position = UDim2.new(0, 0, 0, 238)
whPanel.BackgroundColor3 = C.Panel
whPanel.BorderSizePixel = 0
Instance.new("UICorner", whPanel).CornerRadius = UDim.new(0, 8)
local wt = Instance.new("TextLabel", whPanel)
wt.Size = UDim2.new(1, -16, 0, 20)
wt.Position = UDim2.new(0, 8, 0, 4)
wt.BackgroundTransparency = 1
wt.Text = "📡 WEBHOOK"
wt.Font = Enum.Font.GothamBold
wt.TextSize = 11
wt.TextColor3 = C.Cyan
wt.TextXAlignment = Enum.TextXAlignment.Left
local whInput = Instance.new("TextBox", whPanel)
whInput.Size = UDim2.new(1, -60, 0, 26)
whInput.Position = UDim2.new(0, 8, 0, 26)
whInput.BackgroundColor3 = C.PanelAlt
whInput.BorderSizePixel = 0
whInput.PlaceholderText = "Paste webhook URL..."
whInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 110)
whInput.Text = config.webhookUrl or ""
whInput.Font = Enum.Font.Gotham
whInput.TextSize = 11
whInput.TextColor3 = C.Text
whInput.ClearTextOnFocus = false
whInput.TextXAlignment = Enum.TextXAlignment.Left
Instance.new("UICorner", whInput).CornerRadius = UDim.new(0, 5)
Instance.new("UIPadding", whInput).PaddingLeft = UDim.new(0, 6)
local whSave = Instance.new("TextButton", whPanel)
whSave.Size = UDim2.fromOffset(42, 26)
whSave.Position = UDim2.new(1, -50, 0, 26)
whSave.BackgroundColor3 = C.Cyan
whSave.Text = "SET"
whSave.Font = Enum.Font.GothamBold
whSave.TextSize = 11
whSave.TextColor3 = C.BG
whSave.BorderSizePixel = 0
Instance.new("UICorner", whSave).CornerRadius = UDim.new(0, 5)
whSave.MouseButton1Click:Connect(function()
    webhookUrl = whInput.Text
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
local autoPanel = Instance.new("Frame", contentFrame)
autoPanel.Size = UDim2.new(1, 0, 0, 180)
autoPanel.Position = UDim2.new(0, 0, 0, 300)
autoPanel.BackgroundColor3 = C.Panel
autoPanel.BorderSizePixel = 0
Instance.new("UICorner", autoPanel).CornerRadius = UDim.new(0, 8)

local autoTitle = Instance.new("TextLabel", autoPanel)
autoTitle.Size = UDim2.new(1, -16, 0, 20)
autoTitle.Position = UDim2.new(0, 8, 0, 4)
autoTitle.BackgroundTransparency = 1
autoTitle.Text = "🤖 AUTOMATION"
autoTitle.Font = Enum.Font.GothamBold
autoTitle.TextSize = 11
autoTitle.TextColor3 = Color3.fromRGB(255, 120, 255)
autoTitle.TextXAlignment = Enum.TextXAlignment.Left

-- Wild Battle Auto
local wildSectionLbl = Instance.new("TextLabel", autoPanel)
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

local wildOffBtn  = mkAutoBtn(autoPanel, "OFF",  8,  44, 44)
local wildMoveBtn = mkAutoBtn(autoPanel, "MOVE", 58, 44, 52)
local wildRunBtn  = mkAutoBtn(autoPanel, "RUN",  116, 44, 44)

addHoverEffect(wildOffBtn, C.AccentDim, C.Red)
addHoverEffect(wildMoveBtn, C.AccentDim, C.Green)
addHoverEffect(wildRunBtn, C.AccentDim, C.Cyan)

local wildSlotLbl = Instance.new("TextLabel", autoPanel)
wildSlotLbl.Size = UDim2.new(0, 32, 0, 22)
wildSlotLbl.Position = UDim2.new(0, 166, 0, 44)
wildSlotLbl.BackgroundTransparency = 1
wildSlotLbl.Text = "Slot:"
wildSlotLbl.Font = Enum.Font.GothamBold
wildSlotLbl.TextSize = 10
wildSlotLbl.TextColor3 = C.TextDim

local wildSlotBtns = {}
for s = 1, 4 do
    local sb = mkAutoBtn(autoPanel, tostring(s), 200 + (s-1)*26, 44, 22)
    wildSlotBtns[s] = sb
end

-- Trainer Battle Auto (NEW)
local trainerSectionLbl = Instance.new("TextLabel", autoPanel)
trainerSectionLbl.Size = UDim2.new(0.4, 0, 0, 16)
trainerSectionLbl.Position = UDim2.new(0, 8, 0, 74)
trainerSectionLbl.BackgroundTransparency = 1
trainerSectionLbl.Text = "🎖️ TRAINER:"
trainerSectionLbl.Font = Enum.Font.GothamBold
trainerSectionLbl.TextSize = 10
trainerSectionLbl.TextColor3 = C.Trainer
trainerSectionLbl.TextXAlignment = Enum.TextXAlignment.Left

local trOffBtn  = mkAutoBtn(autoPanel, "OFF",  8,  92, 44)
local trMoveBtn = mkAutoBtn(autoPanel, "MOVE", 58, 92, 52)
local trRunBtn  = mkAutoBtn(autoPanel, "RUN",  116, 92, 44)

addHoverEffect(trOffBtn, C.AccentDim, C.Red)
addHoverEffect(trMoveBtn, C.AccentDim, C.Orange)
addHoverEffect(trRunBtn, C.AccentDim, C.Cyan)

local trSlotLbl = Instance.new("TextLabel", autoPanel)
trSlotLbl.Size = UDim2.new(0, 32, 0, 22)
trSlotLbl.Position = UDim2.new(0, 166, 0, 92)
trSlotLbl.BackgroundTransparency = 1
trSlotLbl.Text = "Slot:"
trSlotLbl.Font = Enum.Font.GothamBold
trSlotLbl.TextSize = 10
trSlotLbl.TextColor3 = C.TextDim

local trSlotBtns = {}
for s = 1, 4 do
    local sb = mkAutoBtn(autoPanel, tostring(s), 200 + (s-1)*26, 92, 22)
    trSlotBtns[s] = sb
end

-- Auto-walk + Scan row
local walkBtn = mkAutoBtn(autoPanel, "🚶 AUTO-WALK: OFF", 8, 122, 140)
local scanBtn = mkAutoBtn(autoPanel, "🔍 SCAN UI", 155, 122, 80)
scanBtn.BackgroundColor3 = C.PanelAlt
addHoverEffect(scanBtn, C.PanelAlt, C.Accent)

-- Status
local autoStatusLbl = Instance.new("TextLabel", autoPanel)
autoStatusLbl.Size = UDim2.new(1, -16, 0, 22)
autoStatusLbl.Position = UDim2.new(0, 8, 0, 152)
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
    trOffBtn.BackgroundColor3  = trainerAutoMode == "off"  and C.Red    or C.AccentDim
    trMoveBtn.BackgroundColor3 = trainerAutoMode == "move" and C.Orange or C.AccentDim
    trRunBtn.BackgroundColor3  = trainerAutoMode == "run"  and C.Cyan   or C.AccentDim
    for s = 1, 4 do
        trSlotBtns[s].BackgroundColor3 = (trainerAutoMoveSlot == s and trainerAutoMode == "move") and C.Accent or C.AccentDim
    end
    walkBtn.BackgroundColor3 = autoWalkEnabled and C.Green or C.PanelAlt
    walkBtn.Text = autoWalkEnabled and "🚶 WALKING" or "🚶 AUTO-WALK"

    local wild_s = autoMode == "off" and "Wild: OFF" or ("Wild: " .. string.upper(autoMode) .. " /" .. autoMoveSlot)
    local trainer_s = trainerAutoMode == "off" and "Trainer: OFF" or ("Trainer: " .. string.upper(trainerAutoMode) .. " /" .. trainerAutoMoveSlot)
    autoStatusLbl.Text = wild_s .. "  |  " .. trainer_s .. (rareFoundPause and "  [⏸ RARE PAUSE]" or "")

    -- Update config UI
    cfgAutoModeVal.Text = autoMode
    cfgAutoModeVal.TextColor3 = autoMode == "off" and C.Red or C.Green
    cfgTrainerModeVal.Text = trainerAutoMode
    cfgTrainerModeVal.TextColor3 = trainerAutoMode == "off" and C.Red or C.Orange
    cfgWildSlotVal.Text = tostring(autoMoveSlot)
    cfgTrainerSlotVal.Text = tostring(trainerAutoMoveSlot)
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
track(trOffBtn.MouseButton1Click:Connect(function()
    trainerAutoMode = "off"; config.trainerAutoMode = trainerAutoMode; saveConfig(); updateAutoUI()
end))
track(trMoveBtn.MouseButton1Click:Connect(function()
    trainerAutoMode = "move"; config.trainerAutoMode = trainerAutoMode; saveConfig(); updateAutoUI()
    sendNotification("LumiWare", "Trainer Auto-MOVE slot " .. trainerAutoMoveSlot, 3)
end))
track(trRunBtn.MouseButton1Click:Connect(function()
    trainerAutoMode = "run"; config.trainerAutoMode = trainerAutoMode; saveConfig(); updateAutoUI()
    sendNotification("LumiWare", "Trainer Auto-RUN enabled", 3)
end))
for s = 1, 4 do
    track(trSlotBtns[s].MouseButton1Click:Connect(function()
        trainerAutoMoveSlot = s; config.trainerAutoMoveSlot = s; saveConfig(); updateAutoUI()
    end))
    addHoverEffect(trSlotBtns[s], C.PanelAlt, C.AccentDim)
end

updateAutoUI()

-- BATTLE LOG
local blPanel = Instance.new("Frame", contentFrame)
blPanel.Size = UDim2.new(1, 0, 0, 100)
blPanel.Position = UDim2.new(0, 0, 0, 486)
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
local ctrlPanel = Instance.new("Frame", contentFrame)
ctrlPanel.Size = UDim2.new(1, 0, 0, 36)
ctrlPanel.Position = UDim2.new(0, 0, 0, 592)
ctrlPanel.BackgroundColor3 = C.Panel
ctrlPanel.BorderSizePixel = 0
Instance.new("UICorner", ctrlPanel).CornerRadius = UDim.new(0, 8)
local cl = Instance.new("UIListLayout", ctrlPanel)
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
local resetBtn    = mkCtrlBtn(ctrlPanel, "🔄 RESET")
local discoveryBtn = mkCtrlBtn(ctrlPanel, "🔍 DISCOVERY")
local verboseBtn  = mkCtrlBtn(ctrlPanel, "📝 VERBOSE")

track(resetBtn.MouseButton1Click:Connect(function()
    encounterCount = 0; huntStartTime = tick(); raresFoundCount = 0
    encounterHistory = {}; currentEnemy = nil; resetBattle()
    encounterVal.Text = "0"; epmVal.Text = "0.0"; timerVal.Text = "0m 00s"
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
track(minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {Size = UDim2.fromOffset(480, 36)}):Play()
        contentContainer.Visible = false; tabBar.Visible = false; minBtn.Text = "+"
    else
        contentContainer.Visible = true; tabBar.Visible = true
        TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {Size = fullSize}):Play()
        minBtn.Text = "–"
    end
end))

--==================================================
-- CONFIG TAB LOGIC
--==================================================
local function refreshConfigUI()
    cfgAutoModeVal.Text = autoMode
    cfgAutoModeVal.TextColor3 = autoMode == "off" and C.Red or C.Green
    cfgTrainerModeVal.Text = trainerAutoMode
    cfgTrainerModeVal.TextColor3 = trainerAutoMode == "off" and C.Red or C.Orange
    cfgWildSlotVal.Text = tostring(autoMoveSlot)
    cfgTrainerSlotVal.Text = tostring(trainerAutoMoveSlot)
    cfgHealVal.Text = autoHealEnabled and "ON" or "OFF"
    cfgHealVal.TextColor3 = autoHealEnabled and C.Teal or C.TextDim
    cfgThreshVal.Text = tostring(autoHealThreshold) .. "%"
    wildFilterBtn.BackgroundColor3 = automateWild and C.Wild or C.PanelAlt
    wildFilterBtn.Text = automateWild and "Wild: ON" or "Wild: OFF"
    trainerFilterBtn.BackgroundColor3 = automateTrainer and C.Trainer or C.PanelAlt
    trainerFilterBtn.Text = automateTrainer and "Trainer: ON" or "Trainer: OFF"
    updateRareCount()
end

cfgWhSave.MouseButton1Click:Connect(function()
    webhookUrl = cfgWhInput.Text
    config.webhookUrl = webhookUrl
    config.pingIds = cfgPingInput.Text
    saveConfig()
    sendNotification("LumiWare", "Webhook saved!", 3)
end)

cfgRareAdd.MouseButton1Click:Connect(function()
    local input = cfgRareInput.Text
    if input == "" then return end
    for word in input:gmatch("[^,]+") do
        local trimmed = word:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then table.insert(customRares, trimmed) end
    end
    config.customRares = customRares
    cfgRareInput.Text = ""
    updateRareCount()
    sendNotification("LumiWare", "Added to rare list!", 3)
end)

cfgRareClear.MouseButton1Click:Connect(function()
    customRares = {}
    config.customRares = customRares
    updateRareCount()
    sendNotification("LumiWare", "Custom rares cleared.", 3)
end)

cfgSaveBtn.MouseButton1Click:Connect(function()
    config.autoMode = autoMode
    config.autoMoveSlot = autoMoveSlot
    config.trainerAutoMode = trainerAutoMode
    config.trainerAutoMoveSlot = trainerAutoMoveSlot
    config.autoHealEnabled = autoHealEnabled
    config.autoHealThreshold = autoHealThreshold
    config.customRares = customRares
    config.webhookUrl = webhookUrl
    config.pingIds = cfgPingInput.Text
    config.automateTrainer = automateTrainer
    config.automateWild = automateWild
    config.healRemoteName = healRemoteName
    config.healRemotePath = healRemotePath
    saveConfig()
    cfgStatusLbl.Text = "✅ Config saved at: " .. os.date("%X")
    cfgStatusLbl.TextColor3 = C.Green
    sendNotification("LumiWare", "Config saved!", 3)
    task.delay(3, function()
        cfgStatusLbl.TextColor3 = C.TextDim
    end)
end)

cfgResetBtn.MouseButton1Click:Connect(function()
    resetConfigToDefault()
    autoMode = "off"; trainerAutoMode = "off"
    autoMoveSlot = 1; trainerAutoMoveSlot = 1
    autoHealEnabled = false; autoHealThreshold = 30
    customRares = {}; webhookUrl = ""
    automateTrainer = true; automateWild = true
    updateAutoUI()
    refreshConfigUI()
    cfgStatusLbl.Text = "🔄 Reset to defaults at: " .. os.date("%X")
    cfgStatusLbl.TextColor3 = C.Orange
    sendNotification("LumiWare", "Config reset to defaults.", 4)
end)

wildFilterBtn.MouseButton1Click:Connect(function()
    automateWild = not automateWild
    config.automateWild = automateWild
    wildFilterBtn.BackgroundColor3 = automateWild and C.Wild or C.PanelAlt
    wildFilterBtn.Text = automateWild and "Wild: ON" or "Wild: OFF"
end)
trainerFilterBtn.MouseButton1Click:Connect(function()
    automateTrainer = not automateTrainer
    config.automateTrainer = automateTrainer
    trainerFilterBtn.BackgroundColor3 = automateTrainer and C.Trainer or C.PanelAlt
    trainerFilterBtn.Text = automateTrainer and "Trainer: ON" or "Trainer: OFF"
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
        healRemoteName = name
        healRemotePath = path
        healRemote = remote
        autoHealMethod = isButton and "button" or "remote"
        config.healRemoteName = healRemoteName
        config.healRemotePath = healRemotePath
        config.autoHealMethod = autoHealMethod
        saveConfig()
        healSelectedName.Text = (isButton and "Button: " or "Remote: ") .. name
        healSelectedName.TextColor3 = C.Teal
        healSelectedPath.Text = path
        selectBtn.BackgroundColor3 = C.Teal
        selectBtn.Text = "✓ SET"
        addHealLog("✅ Selected: " .. name, C.Teal)
        sendNotification("LumiWare", "Heal source set: " .. name, 4)
    end))

    row.Parent = healRemoteScroll
end

-- Scan for heal remotes
healScanBtn.MouseButton1Click:Connect(function()
    -- Clear existing list
    for _, v in ipairs(healRemoteScroll:GetChildren()) do
        if not v:IsA("UIListLayout") then v:Destroy() end
    end
    scannedHealRemotes = {}

    healScanStatusLbl.Text = "⏳ Scanning for heal remotes..."
    healScanStatusLbl.TextColor3 = C.Orange

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
            healScanStatusLbl.Text = "⚠ No heal remotes found. Try entering a heal center first."
            healScanStatusLbl.TextColor3 = C.Orange
        else
            healScanStatusLbl.Text = "✅ Found " .. found .. " heal remote(s). Click USE to select."
            healScanStatusLbl.TextColor3 = C.Teal
        end

        healScanSec.Size = UDim2.new(1, -8, 0, math.max(120, 80 + found * 22))
        healRemoteScroll.Size = UDim2.new(1, -16, 0, math.min(60, math.max(22, found * 22)))
    end)
end)

-- Scan for heal buttons in PlayerGui
healScanBtnBtn.MouseButton1Click:Connect(function()
    for _, v in ipairs(healRemoteScroll:GetChildren()) do
        if not v:IsA("UIListLayout") then v:Destroy() end
    end
    scannedHealRemotes = {}

    healScanStatusLbl.Text = "⏳ Scanning for heal buttons..."
    healScanStatusLbl.TextColor3 = C.Cyan

    task.spawn(function()
        local found = 0
        local pgui = player:FindFirstChild("PlayerGui")
        if not pgui then
            healScanStatusLbl.Text = "⚠ PlayerGui not found"
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
            healScanStatusLbl.Text = "⚠ No heal buttons found. Go near a heal center and scan again."
            healScanStatusLbl.TextColor3 = C.Orange
        else
            healScanStatusLbl.Text = "✅ Found " .. found .. " heal button(s). Click USE to select."
            healScanStatusLbl.TextColor3 = C.Cyan
        end

        healScanSec.Size = UDim2.new(1, -8, 0, math.max(120, 80 + found * 22))
        healRemoteScroll.Size = UDim2.new(1, -16, 0, math.min(60, math.max(22, found * 22)))
    end)
end)

-- Perform heal action
local function performHeal()
    if not healRemote then
        addHealLog("⚠ No heal source selected!", C.Red)
        return false
    end
    if autoHealMethod == "button" then
        pcall(function()
            local p, s = healRemote.AbsolutePosition, healRemote.AbsoluteSize
            local cx, cy = p.X + s.X/2, p.Y + s.Y/2
            VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
            task.wait(0.05)
            VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
        end)
        addHealLog("💊 Heal button clicked", C.Teal)
    else
        pcall(function()
            if healRemote:IsA("RemoteEvent") then
                healRemote:FireServer()
            elseif healRemote:IsA("RemoteFunction") then
                healRemote:InvokeServer()
            end
        end)
        addHealLog("💊 Heal remote fired: " .. healRemoteName, C.Teal)
    end
    lastHealTime = tick()
    return true
end

-- Test heal
healTestBtn.MouseButton1Click:Connect(function()
    addHealLog("🧪 Manual heal test triggered", C.Orange)
    performHeal()
end)

healClearBtn.MouseButton1Click:Connect(function()
    healRemote = nil
    healRemoteName = ""
    healRemotePath = ""
    config.healRemoteName = ""
    config.healRemotePath = ""
    saveConfig()
    healSelectedName.Text = "None selected"
    healSelectedName.TextColor3 = C.TextDim
    healSelectedPath.Text = "Path: —"
    addHealLog("Heal source cleared", C.TextDim)
end)

-- Auto-heal toggle buttons
healOnBtn.MouseButton1Click:Connect(function()
    autoHealEnabled = true
    config.autoHealEnabled = true
    saveConfig()
    healOnBtn.BackgroundColor3 = C.Teal
    healOffBtn.BackgroundColor3 = C.AccentDim
    refreshConfigUI()
    sendNotification("LumiWare", "Auto-Heal ENABLED (< " .. autoHealThreshold .. "%)", 4)
    addHealLog("✅ Auto-Heal ON (< " .. autoHealThreshold .. "%)", C.Teal)
end)

healOffBtn.MouseButton1Click:Connect(function()
    autoHealEnabled = false
    config.autoHealEnabled = false
    saveConfig()
    healOnBtn.BackgroundColor3 = C.AccentDim
    healOffBtn.BackgroundColor3 = C.Red
    refreshConfigUI()
    addHealLog("❌ Auto-Heal OFF", C.TextDim)
end)

healThreshInput.FocusLost:Connect(function()
    local val = tonumber(healThreshInput.Text)
    if val and val >= 1 and val <= 99 then
        autoHealThreshold = math.floor(val)
        config.autoHealThreshold = autoHealThreshold
        saveConfig()
        refreshConfigUI()
    else
        healThreshInput.Text = tostring(autoHealThreshold)
    end
end)

-- Auto-heal monitor thread
local healMonitorThread = task.spawn(function()
    while not _G.LumiWare_StopFlag do
        if not gui.Parent then break end
        if autoHealEnabled and healRemote and battleState ~= "active" then
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
if _G.LumiWare_Threads then table.insert(_G.LumiWare_Threads, healMonitorThread) end

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
                        if healRemoteName == "" then
                            local path = getFullPath(self)
                            addHealLog("🔍 Auto-detected heal remote: " .. self.Name, C.Teal)
                            addHealRemoteEntry(self.Name, path, self, false)
                            healScanStatusLbl.Text = "✅ Auto-detected: " .. self.Name
                            healScanStatusLbl.TextColor3 = C.Teal
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
-- AUTO-WALK
--==================================================
local function startAutoWalk()
    if autoWalkThread then return end
    autoWalkThread = task.spawn(function()
        _G.LumiWare_WalkThread = autoWalkThread
        log("INFO", "Auto-walk started")
        local char = player.Character or player.CharacterAdded:Wait()
        local humanoid = char:WaitForChild("Humanoid")
        local rootPart = char:WaitForChild("HumanoidRootPart")
        local center = rootPart.Position
        local radius = 6
        local numPoints = 12
        local pointIndex = 0
        local heartbeat = RunService.Heartbeat

        while autoWalkEnabled and gui.Parent do
            if battleState == "active" then
                pcall(function()
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
                end)
                task.wait(0.5)
            else
                char = player.Character
                if not char then task.wait(1)
                else
                    humanoid = char:FindFirstChild("Humanoid")
                    rootPart = char:FindFirstChild("HumanoidRootPart")
                    if not humanoid or not rootPart or humanoid.Health <= 0 then
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
        end
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
        if not automateWild or autoMode == "off" then return end
        effectiveMode = autoMode
        effectiveSlot = autoMoveSlot
    elseif battleType == "Trainer" then
        if not automateTrainer or trainerAutoMode == "off" then return end
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
                    sessionLbl.Text = string.format("Session: %d KOs | %.1fk Damage", sessionKOs, sessionDamage / 1000)
                end
            elseif cmdL == "-damage" or cmdL == "damage" then
                if type(entry[2]) == "string" and string.find(entry[2], "p2") then
                    sessionDamage = sessionDamage + 100
                    sessionLbl.Text = string.format("Session: %d KOs | %.1fk Damage", sessionKOs, sessionDamage / 1000)
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
            encounterCount = encounterCount + 1
            encounterVal.Text = tostring(encounterCount)
            table.insert(encounterHistory, 1, { name = enemyName, time = os.date("%X") })
            if #encounterHistory > 10 then table.remove(encounterHistory, 11) end
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
                    encounterCount, formatTime(tick() - huntStartTime))
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
        local elapsed = tick() - huntStartTime
        timerVal.Text = formatTime(elapsed)
        local minutes = elapsed / 60
        if minutes > 0 then epmVal.Text = string.format("%.1f", encounterCount / minutes) end
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
        if encounterCount > 0 and encounterCount % 50 == 0 and encounterCount ~= lastMs then
            lastMs = encounterCount
            sendSessionWebhook(encounterCount, formatTime(tick() - huntStartTime), raresFoundCount)
        end
        task.wait(5)
    end
end)
if _G.LumiWare_Threads then table.insert(_G.LumiWare_Threads, webhookThread) end

-- Try to find previously configured heal remote on startup
if healRemoteName ~= "" then
    task.spawn(function()
        task.wait(3) -- Wait for remotes to be ready
        local found = false
        for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
            if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) and obj.Name == healRemoteName then
                healRemote = obj
                addHealLog("✅ Restored heal remote from config: " .. healRemoteName, C.Teal)
                healSelectedName.Text = "Remote: " .. healRemoteName
                healSelectedName.TextColor3 = C.Teal
                healSelectedPath.Text = getFullPath(obj)
                found = true
                break
            end
        end
        if not found then
            addHealLog("⚠ Saved heal remote not found: " .. healRemoteName, C.Orange)
        end
    end)
end

addBattleLog("Hooked " .. hookedCount .. " remotes — READY", C.Green)
addBattleLog("v4.6: Trainer Auto + Auto-Heal + Config Tab", C.Accent)
log("INFO", "LumiWare " .. VERSION .. " READY | Hooked " .. hookedCount .. " | Player: " .. PLAYER_NAME)
sendNotification("⚡ LumiWare " .. VERSION, "Ready! Hooked " .. hookedCount .. " remotes.\nTrainer Auto + Auto-Heal active.", 6)
