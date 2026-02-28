--------------------------------------------------
-- LUMIWARE V4 — Automation Update
-- Battle Detection + Auto-Move/Run/Walk
-- FORMAT: EVT(arg1="BattleEvent", arg2=sessionID,
--   arg3=subCmd, arg4=JSON commandTable)
--------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
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

log("INFO", "Initializing LumiWare v4 for:", PLAYER_NAME)

--------------------------------------------------
-- RARE LOOMIANS
--------------------------------------------------
local RARE_LOOMIANS = {
    "Duskit", "Ikazune", "Mutagon", "Protogon", "Metronette", "Wabalisc",
    "Cephalops", "Elephage", "Gargolem", "Celesting", "Nyxre", "Pyramind",
    "Terracolt", "Garbantis", "Cynamoth", "Avitross", "Snocub", "Eaglit",
    "Vambat", "Weevolt", "Nevermare",
    "Akhalos", "Odasho", "Cosmiore", "Armenti", "Shawchi"
}
local customRares = {}

-- LAYER 1: Name-based rare modifier detection
-- Catches: "Gleam Dripple", "Gamma Grubby", "SA Dripple", etc.
local RARE_MODIFIERS = {
    "gleam", "gleaming", "gamma", "corrupt", "corrupted",
    "alpha", "iridescent", "metallic", "rainbow",
    "sa ", "pn ", "hw ", "ny ",           -- event prefixes
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

-- LAYER 2: Deep scan ANY table/string for gleam/gamma/corrupt keywords
-- This catches model tables like {disc="gleamdisc", ...} or {variant="gamma"}
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
            -- Check key names for variant/gleam/type properties
            if type(k) == "string" then
                local kl = string.lower(k)
                if kl == "variant" or kl == "gleam" or kl == "gamma" or kl == "corrupt"
                    or kl == "issecret" or kl == "isgleam" or kl == "isgamma" then
                    -- If the key is a flag and the value is truthy
                    if v == true or v == 1 or (type(v) == "string" and v ~= "" and v ~= "false" and v ~= "0") then
                        log("RARE", "Deep scan HIT: key=" .. k .. " val=" .. tostring(v))
                        return true
                    end
                end
            end
            -- Recurse into all values
            if deepScanForRare(v, depth + 1) then return true end
        end
    end
    return false
end

-- LAYER 3: Scan a full command entry for any rare indicators
-- Checks name, info string, AND all table args (model, disc, icon)
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
local webhookUrl = ""

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
    
    -- Check for super rare
    for _, r in ipairs(superRares) do
        if string.find(l, r) then return "SUPER RARE" end
    end
    
    -- Check for gleam/gamma modifiers
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
        footer = { text = "LumiWare v4 • " .. os.date("%X") },
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
        footer = { text = "LumiWare v3.1 • " .. os.date("%X") },
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
local autoMode = "off"      -- "off", "move", "run"
local autoMoveSlot = 1       -- 1-4 move slot
local autoWalkEnabled = false
local autoWalkThread = nil
local rareFoundPause = false -- pause automation on rare
local pendingAutoAction = false -- avoid double-firing

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
-- GUI CLEANUP
--------------------------------------------------
local guiName = "LumiWare_Hub_" .. tostring(math.random(1000, 9999))
for _, v in pairs(player:WaitForChild("PlayerGui"):GetChildren()) do
    if string.find(v.Name, "LumiWare_Hub") or v.Name == "BattleLoomianViewer" then v:Destroy() end
end
pcall(function()
    for _, v in pairs(CoreGui:GetChildren()) do
        if string.find(v.Name, "LumiWare_Hub") or v.Name == "BattleLoomianViewer" then v:Destroy() end
    end
end)

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
    BG = Color3.fromRGB(16, 16, 22), TopBar = Color3.fromRGB(24, 24, 34),
    Accent = Color3.fromRGB(120, 80, 255), AccentDim = Color3.fromRGB(80, 50, 180),
    Text = Color3.fromRGB(240, 240, 245), TextDim = Color3.fromRGB(160, 160, 175),
    Panel = Color3.fromRGB(22, 22, 30), PanelAlt = Color3.fromRGB(28, 28, 38),
    Gold = Color3.fromRGB(255, 215, 0), Green = Color3.fromRGB(80, 220, 120),
    Red = Color3.fromRGB(255, 80, 80), Wild = Color3.fromRGB(80, 200, 255),
    Trainer = Color3.fromRGB(255, 160, 60), Orange = Color3.fromRGB(255, 160, 60),
    Cyan = Color3.fromRGB(80, 200, 255),
}

--------------------------------------------------
-- MAIN FRAME
--------------------------------------------------
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.fromOffset(460, 720)
mainFrame.Position = UDim2.fromScale(0.5, 0.5)
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.BackgroundColor3 = C.BG
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Parent = gui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", mainFrame)
stroke.Color = C.Accent
stroke.Thickness = 1.5
stroke.Transparency = 0.4

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
titleLbl.Text = "⚡ LumiWare v4"
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 15
titleLbl.TextColor3 = C.Accent
titleLbl.TextXAlignment = Enum.TextXAlignment.Left

local minBtn = Instance.new("TextButton", topbar)
minBtn.Size = UDim2.fromOffset(28, 28)
minBtn.Position = UDim2.new(1, -66, 0, 4)
minBtn.BackgroundColor3 = C.AccentDim
minBtn.Text = "–"
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 18
minBtn.TextColor3 = C.Text
minBtn.BorderSizePixel = 0
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

local closeBtn = Instance.new("TextButton", topbar)
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 4)
closeBtn.BackgroundColor3 = C.Red
closeBtn.Text = "×"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 18
closeBtn.TextColor3 = C.Text
closeBtn.BorderSizePixel = 0
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

closeBtn.MouseButton1Click:Connect(function()
    local elapsed = tick() - huntStartTime
    sendSessionWebhook(encounterCount, formatTime(elapsed), raresFoundCount)
    gui:Destroy()
end)

-- Drag
local dragging, dragInput, dragStart, startPos
topbar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = mainFrame.Position
        input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
    end
end)
topbar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local d = input.Position - dragStart
        mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

-- TAB SELECTION UI
local tabBar = Instance.new("Frame", mainFrame)
tabBar.Size = UDim2.new(1, -16, 0, 32)
tabBar.Position = UDim2.new(0, 8, 0, 44)
tabBar.BackgroundTransparency = 1

local huntTabBtn = Instance.new("TextButton", tabBar)
huntTabBtn.Size = UDim2.new(0.5, -4, 1, 0)
huntTabBtn.Position = UDim2.new(0, 0, 0, 0)
huntTabBtn.BackgroundColor3 = C.Accent
huntTabBtn.Text = "🗡️ HUNT"
huntTabBtn.Font = Enum.Font.GothamBold
huntTabBtn.TextSize = 13
huntTabBtn.TextColor3 = C.Text
huntTabBtn.BorderSizePixel = 0
Instance.new("UICorner", huntTabBtn).CornerRadius = UDim.new(0, 6)

local masteryTabBtn = Instance.new("TextButton", tabBar)
masteryTabBtn.Size = UDim2.new(0.5, -4, 1, 0)
masteryTabBtn.Position = UDim2.new(0.5, 4, 0, 0)
masteryTabBtn.BackgroundColor3 = C.PanelAlt
masteryTabBtn.Text = "📖 MASTERY"
masteryTabBtn.Font = Enum.Font.GothamBold
masteryTabBtn.TextSize = 13
masteryTabBtn.TextColor3 = C.TextDim
masteryTabBtn.BorderSizePixel = 0
Instance.new("UICorner", masteryTabBtn).CornerRadius = UDim.new(0, 6)

-- CONTENT WRAPPER
local contentContainer = Instance.new("Frame", mainFrame)
contentContainer.Name = "ContentContainer"
contentContainer.Size = UDim2.new(1, -16, 1, -84)
contentContainer.Position = UDim2.new(0, 8, 0, 80)
contentContainer.BackgroundTransparency = 1

-- MASTERY FRAME
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

-- HUNT FRAME (Contains old contentFrame layout)
local contentFrame = Instance.new("Frame", contentContainer)
contentFrame.Name = "HuntFrame"
contentFrame.Size = UDim2.new(1, 0, 1, 0)
contentFrame.BackgroundTransparency = 1
contentFrame.Visible = true

-- TAB LOGIC
huntTabBtn.MouseButton1Click:Connect(function()
    contentFrame.Visible = true
    masteryFrame.Visible = false
    huntTabBtn.BackgroundColor3 = C.Accent
    huntTabBtn.TextColor3 = C.Text
    masteryTabBtn.BackgroundColor3 = C.PanelAlt
    masteryTabBtn.TextColor3 = C.TextDim
end)

masteryTabBtn.MouseButton1Click:Connect(function()
    contentFrame.Visible = false
    masteryFrame.Visible = true
    huntTabBtn.BackgroundColor3 = C.PanelAlt
    huntTabBtn.TextColor3 = C.TextDim
    masteryTabBtn.BackgroundColor3 = C.Accent
    masteryTabBtn.TextColor3 = C.Text
end)

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

Instance.new("TextLabel", encounterPanel).Size = UDim2.new(1, -16, 0, 24)
local encTitle = encounterPanel:FindFirstChildOfClass("TextLabel")
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

-- CUSTOM RARE
local customPanel = Instance.new("Frame", contentFrame)
customPanel.Size = UDim2.new(1, 0, 0, 56)
customPanel.Position = UDim2.new(0, 0, 0, 238)
customPanel.BackgroundColor3 = C.Panel
customPanel.BorderSizePixel = 0
Instance.new("UICorner", customPanel).CornerRadius = UDim.new(0, 8)
local ct = Instance.new("TextLabel", customPanel)
ct.Size = UDim2.new(1, -16, 0, 20)
ct.Position = UDim2.new(0, 8, 0, 4)
ct.BackgroundTransparency = 1
ct.Text = "CUSTOM RARE LIST"
ct.Font = Enum.Font.GothamBold
ct.TextSize = 11
ct.TextColor3 = C.Accent
ct.TextXAlignment = Enum.TextXAlignment.Left

local customInput = Instance.new("TextBox", customPanel)
customInput.Size = UDim2.new(1, -90, 0, 26)
customInput.Position = UDim2.new(0, 8, 0, 26)
customInput.BackgroundColor3 = C.PanelAlt
customInput.BorderSizePixel = 0
customInput.PlaceholderText = "e.g. Twilat, Cathorn..."
customInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 110)
customInput.Text = ""
customInput.Font = Enum.Font.Gotham
customInput.TextSize = 12
customInput.TextColor3 = C.Text
customInput.ClearTextOnFocus = false
customInput.TextXAlignment = Enum.TextXAlignment.Left
Instance.new("UICorner", customInput).CornerRadius = UDim.new(0, 5)
Instance.new("UIPadding", customInput).PaddingLeft = UDim.new(0, 6)

local addBtn = Instance.new("TextButton", customPanel)
addBtn.Size = UDim2.fromOffset(36, 26)
addBtn.Position = UDim2.new(1, -82, 0, 26)
addBtn.BackgroundColor3 = C.Green
addBtn.Text = "+"
addBtn.Font = Enum.Font.GothamBold
addBtn.TextSize = 16
addBtn.TextColor3 = C.BG
addBtn.BorderSizePixel = 0
Instance.new("UICorner", addBtn).CornerRadius = UDim.new(0, 5)

local clearBtn = Instance.new("TextButton", customPanel)
clearBtn.Size = UDim2.fromOffset(36, 26)
clearBtn.Position = UDim2.new(1, -42, 0, 26)
clearBtn.BackgroundColor3 = C.Red
clearBtn.Text = "C"
clearBtn.Font = Enum.Font.GothamBold
clearBtn.TextSize = 14
clearBtn.TextColor3 = C.Text
clearBtn.BorderSizePixel = 0
Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(0, 5)

addBtn.MouseButton1Click:Connect(function()
    local input = customInput.Text
    if input == "" then return end
    for word in input:gmatch("[^,]+") do
        local trimmed = word:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then table.insert(customRares, trimmed) end
    end
    customInput.Text = ""
    sendNotification("LumiWare", "Added to custom rare list!", 3)
end)
clearBtn.MouseButton1Click:Connect(function()
    customRares = {}
    sendNotification("LumiWare", "Custom rare list cleared.", 3)
end)

-- WEBHOOK CONFIG
local whPanel = Instance.new("Frame", contentFrame)
whPanel.Size = UDim2.new(1, 0, 0, 56)
whPanel.Position = UDim2.new(0, 0, 0, 300)
whPanel.BackgroundColor3 = C.Panel
whPanel.BorderSizePixel = 0
Instance.new("UICorner", whPanel).CornerRadius = UDim.new(0, 8)
local wt = Instance.new("TextLabel", whPanel)
wt.Size = UDim2.new(1, -16, 0, 20)
wt.Position = UDim2.new(0, 8, 0, 4)
wt.BackgroundTransparency = 1
wt.Text = "📡 DISCORD WEBHOOK"
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
whInput.Text = ""
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
    if webhookUrl ~= "" then
        sendNotification("LumiWare", "Webhook saved!", 3)
        sendWebhook({
            title = "✅ Webhook Connected!", color = 5763719,
            fields = { { name = "Player", value = PLAYER_NAME, inline = true } },
            footer = { text = "LumiWare v3.1" },
        })
    else
        sendNotification("LumiWare", "Webhook cleared.", 3)
    end
end)

-- Forward declarations (needed by automation panel handlers)
local addBattleLog

-- ============================================
-- AUTOMATION PANEL
-- ============================================
local autoPanel = Instance.new("Frame", contentFrame)
autoPanel.Size = UDim2.new(1, 0, 0, 130)
autoPanel.Position = UDim2.new(0, 0, 0, 362)
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

-- Mode label
local modeLabel = Instance.new("TextLabel", autoPanel)
modeLabel.Size = UDim2.new(0, 46, 0, 22)
modeLabel.Position = UDim2.new(0, 8, 0, 26)
modeLabel.BackgroundTransparency = 1
modeLabel.Text = "Mode:"
modeLabel.Font = Enum.Font.GothamBold
modeLabel.TextSize = 11
modeLabel.TextColor3 = C.TextDim
modeLabel.TextXAlignment = Enum.TextXAlignment.Left

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

local offBtn = mkAutoBtn(autoPanel, "OFF", 56, 26, 50)
local moveBtn = mkAutoBtn(autoPanel, "MOVE", 112, 26, 60)
local runBtn = mkAutoBtn(autoPanel, "RUN", 178, 26, 50)

-- Move slot label + textbox
local slotLabel = Instance.new("TextLabel", autoPanel)
slotLabel.Size = UDim2.new(0, 70, 0, 22)
slotLabel.Position = UDim2.new(0, 8, 0, 52)
slotLabel.BackgroundTransparency = 1
slotLabel.Text = "Move Slot:"
slotLabel.Font = Enum.Font.GothamBold
slotLabel.TextSize = 11
slotLabel.TextColor3 = C.TextDim
slotLabel.TextXAlignment = Enum.TextXAlignment.Left

local slotInput = Instance.new("TextBox", autoPanel)
slotInput.Size = UDim2.fromOffset(36, 22)
slotInput.Position = UDim2.new(0, 80, 0, 52)
slotInput.BackgroundColor3 = C.AccentDim
slotInput.Text = tostring(autoMoveSlot)
slotInput.Font = Enum.Font.GothamBold
slotInput.TextSize = 12
slotInput.TextColor3 = C.Text
slotInput.BorderSizePixel = 0
slotInput.PlaceholderText = "1-4"
slotInput.ClearTextOnFocus = false
Instance.new("UICorner", slotInput).CornerRadius = UDim.new(0, 5)

-- Quick slot buttons next to textbox
local slotBtns = {}
for s = 1, 4 do
    local sb = mkAutoBtn(autoPanel, tostring(s), 122 + (s - 1) * 30, 52, 26)
    slotBtns[s] = sb
end

-- Auto-walk toggle
local walkBtn = mkAutoBtn(autoPanel, "🚶 AUTO-WALK: OFF", 8, 78, 140)
local scanBtn = mkAutoBtn(autoPanel, "🔍 SCAN UI", 155, 78, 80)
scanBtn.BackgroundColor3 = C.Orange

-- Status label
local autoStatusLbl = Instance.new("TextLabel", autoPanel)
autoStatusLbl.Size = UDim2.new(1, -16, 0, 22)
autoStatusLbl.Position = UDim2.new(0, 8, 0, 104)
autoStatusLbl.BackgroundTransparency = 1
autoStatusLbl.Text = ""
autoStatusLbl.Font = Enum.Font.Gotham
autoStatusLbl.TextSize = 10
autoStatusLbl.TextColor3 = C.TextDim
autoStatusLbl.TextXAlignment = Enum.TextXAlignment.Left

local function updateAutoUI()
    offBtn.BackgroundColor3 = autoMode == "off" and C.Red or C.AccentDim
    moveBtn.BackgroundColor3 = autoMode == "move" and C.Green or C.AccentDim
    runBtn.BackgroundColor3 = autoMode == "run" and C.Cyan or C.AccentDim
    for s = 1, 4 do
        slotBtns[s].BackgroundColor3 = (autoMoveSlot == s and autoMode == "move") and C.Accent or C.AccentDim
    end
    slotLabel.TextColor3 = autoMode == "move" and C.Text or C.TextDim
    slotInput.Text = tostring(autoMoveSlot)
    walkBtn.BackgroundColor3 = autoWalkEnabled and C.Green or C.AccentDim
    walkBtn.Text = autoWalkEnabled and "🚶 WALKING" or "🚶 AUTO-WALK"
    -- Status text
    if autoMode == "off" then
        autoStatusLbl.Text = "Automation disabled"
    elseif autoMode == "move" then
        autoStatusLbl.Text = "Auto-move slot " .. autoMoveSlot .. (rareFoundPause and " [PAUSED: RARE]" or "")
    elseif autoMode == "run" then
        autoStatusLbl.Text = "Auto-run" .. (rareFoundPause and " [PAUSED: RARE]" or "")
    end
end

offBtn.MouseButton1Click:Connect(function()
    autoMode = "off"
    rareFoundPause = false
    updateAutoUI()
    sendNotification("LumiWare", "Automation OFF", 3)
end)
moveBtn.MouseButton1Click:Connect(function()
    autoMode = "move"
    rareFoundPause = false
    updateAutoUI()
    sendNotification("LumiWare", "Auto-MOVE slot " .. autoMoveSlot, 3)
end)
runBtn.MouseButton1Click:Connect(function()
    autoMode = "run"
    rareFoundPause = false
    updateAutoUI()
    sendNotification("LumiWare", "Auto-RUN enabled", 3)
end)
for s = 1, 4 do
    slotBtns[s].MouseButton1Click:Connect(function()
        autoMoveSlot = s
        updateAutoUI()
    end)
end

slotInput.FocusLost:Connect(function()
    local num = tonumber(slotInput.Text)
    if num and num >= 1 and num <= 4 then
        autoMoveSlot = math.floor(num)
    end
    updateAutoUI()
end)

updateAutoUI()

-- SCAN UI: dump all buttons in PlayerGui
scanBtn.MouseButton1Click:Connect(function()
    log("SCAN", "========== SCANNING PlayerGui ==========")
    addBattleLog("🔍 Scanning PlayerGui for buttons...", C.Orange)
    local pgui = player:FindFirstChild("PlayerGui")
    if not pgui then
        addBattleLog("⚠ PlayerGui not found", C.Red)
        return
    end

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
    sendNotification("LumiWare", "Scan: " .. btnCount .. " buttons found.\nCheck F9 console for full paths.", 5)
end)

-- OUTGOING REMOTE SPY: hook FireServer to see what client sends
pcall(function()
    local oldFire
    if hookfunction then
        local remoteEventMeta = getrawmetatable(Instance.new("RemoteEvent"))
        if remoteEventMeta then
            -- Use namecall hook instead
        end
    end

    -- Try namecall hook (most compatible)
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
            end
            return oldNamecall(self, ...)
        end)
        log("HOOK", "Outgoing remote spy installed (namecall)")
    else
        log("HOOK", "hookmetamethod not available — outgoing spy disabled")
    end
end)

-- BATTLE LOG (shifted down)
local blPanel = Instance.new("Frame", contentFrame)
blPanel.Size = UDim2.new(1, 0, 0, 100)
blPanel.Position = UDim2.new(0, 0, 0, 498)
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
            if ch:IsA("TextLabel") then ch:Destroy() blCount = blCount - 1 break end
        end
    end
end

-- CONTROLS (shifted down)
local ctrlPanel = Instance.new("Frame", contentFrame)
ctrlPanel.Size = UDim2.new(1, 0, 0, 36)
ctrlPanel.Position = UDim2.new(0, 0, 0, 604)
ctrlPanel.BackgroundColor3 = C.Panel
ctrlPanel.BorderSizePixel = 0
Instance.new("UICorner", ctrlPanel).CornerRadius = UDim.new(0, 8)
local cl = Instance.new("UIListLayout", ctrlPanel)
cl.FillDirection = Enum.FillDirection.Horizontal
cl.HorizontalAlignment = Enum.HorizontalAlignment.Center
cl.VerticalAlignment = Enum.VerticalAlignment.Center
cl.Padding = UDim.new(0, 6)

local function mkBtn(parent, text)
    local b = Instance.new("TextButton", parent)
    b.Size = UDim2.new(0.3, -6, 0, 26)
    b.BackgroundColor3 = C.AccentDim
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.TextColor3 = C.Text
    b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    return b
end

local resetBtn = mkBtn(ctrlPanel, "🔄 RESET")
local discoveryBtn = mkBtn(ctrlPanel, "🔍 DISCOVERY")
local verboseBtn = mkBtn(ctrlPanel, "📝 VERBOSE")

resetBtn.MouseButton1Click:Connect(function()
    encounterCount = 0; huntStartTime = tick(); raresFoundCount = 0
    encounterHistory = {}; currentEnemy = nil; resetBattle()
    encounterVal.Text = "0"; epmVal.Text = "0.0"; timerVal.Text = "0m 00s"
    typeVal.Text = "N/A"; typeVal.TextColor3 = C.TextDim
    stateVal.Text = "Idle"; stateVal.TextColor3 = C.TextDim
    enemyLbl.Text = "Enemy: Waiting for battle..."
    enemyStatsLbl.Text = ""; playerLbl.Text = "Your Loomian: —"
    addBattleLog("Session reset", C.Accent)
end)
discoveryBtn.MouseButton1Click:Connect(function()
    discoveryMode = not discoveryMode
    discoveryBtn.BackgroundColor3 = discoveryMode and C.Orange or C.AccentDim
    discoveryBtn.Text = discoveryMode and "🔍 DISC: ON" or "🔍 DISCOVERY"
    addBattleLog("Discovery: " .. tostring(discoveryMode), C.Orange)
end)
verboseBtn.MouseButton1Click:Connect(function()
    VERBOSE_MODE = not VERBOSE_MODE
    verboseBtn.BackgroundColor3 = VERBOSE_MODE and C.Orange or C.AccentDim
    verboseBtn.Text = VERBOSE_MODE and "📝 VERB: ON" or "📝 VERBOSE"
end)

-- MINIMIZE
local fullSize = UDim2.fromOffset(460, 720)
minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Size = UDim2.fromOffset(460, 36) }):Play()
        contentFrame.Visible = false; minBtn.Text = "+"
    else
        contentFrame.Visible = true
        TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Size = fullSize }):Play()
        minBtn.Text = "–"
    end
end)

-- TIMER
task.spawn(function()
    while gui.Parent do
        local elapsed = tick() - huntStartTime
        timerVal.Text = formatTime(elapsed)
        local minutes = elapsed / 60
        if minutes > 0 then epmVal.Text = string.format("%.1f", encounterCount / minutes) end
        if battleState == "active" and (tick() - lastBattleTick) > 5 then
            battleState = "idle"
            stateVal.Text = "Idle"
            stateVal.TextColor3 = C.TextDim
            
            -- Battle is truly over, unpause automation if we paused for a rare
            if rareFoundPause then
                rareFoundPause = false
                updateAutoUI()
                log("AUTO", "Battle ended: Rare pause lifted. Resuming automation.")
            end
        end
        task.wait(1)
    end
end)
-- SESSION WEBHOOK
task.spawn(function()
    local lastMs = 0
    while gui.Parent do
        if encounterCount > 0 and encounterCount % 50 == 0 and encounterCount ~= lastMs then
            lastMs = encounterCount
            sendSessionWebhook(encounterCount, formatTime(tick() - huntStartTime), raresFoundCount)
        end
        task.wait(5)
    end
end)

--------------------------------------------------
-- AUTO-WALK: Circle Movement
--------------------------------------------------
local function startAutoWalk()
    if autoWalkThread then return end
    autoWalkThread = task.spawn(function()
        log("INFO", "Auto-walk started")
        local char = player.Character or player.CharacterAdded:Wait()
        local humanoid = char:WaitForChild("Humanoid")
        local rootPart = char:WaitForChild("HumanoidRootPart")
        local center = rootPart.Position
        local radius = 6
        local numPoints = 6
        local pointIndex = 0

        while autoWalkEnabled and gui.Parent do
            -- Pause during battles
            if battleState == "active" then
                -- Release shift while in battle
                pcall(function()
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
                end)
                task.wait(0.5)
            else
                -- Refresh character reference
                char = player.Character
                if not char then task.wait(1)
                else
                    humanoid = char:FindFirstChild("Humanoid")
                    rootPart = char:FindFirstChild("HumanoidRootPart")
                    if not humanoid or not rootPart or humanoid.Health <= 0 then
                        task.wait(1)
                    else
                        -- Hold shift for sprinting
                        pcall(function()
                            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
                        end)

                        -- Calculate next waypoint in circle
                        local angle = (pointIndex / numPoints) * math.pi * 2
                        local targetPos = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
                        pointIndex = (pointIndex + 1) % numPoints

                        humanoid:MoveTo(targetPos)

                        -- Wait for move to complete or timeout
                        local moveStart = tick()
                        local reached = false
                        local conn
                        conn = humanoid.MoveToFinished:Connect(function()
                            reached = true
                        end)
                        while not reached and (tick() - moveStart) < 2 and autoWalkEnabled do
                            task.wait(0.1)
                        end
                        if conn then conn:Disconnect() end
                        task.wait(0.05)
                    end
                end
            end
        end
        -- Release shift when stopping
        pcall(function()
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
        end)
        log("INFO", "Auto-walk stopped")
    end)
end

local function stopAutoWalk()
    autoWalkEnabled = false
    if autoWalkThread then
        pcall(function() task.cancel(autoWalkThread) end)
        autoWalkThread = nil
    end
    pcall(function()
        local char = player.Character
        if char then
            local h = char:FindFirstChild("Humanoid")
            local rp = char:FindFirstChild("HumanoidRootPart")
            if h and rp then h:MoveTo(rp.Position) end
        end
    end)
    -- Release shift
    pcall(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
    end)
end

walkBtn.MouseButton1Click:Connect(function()
    autoWalkEnabled = not autoWalkEnabled
    updateAutoUI()
    if autoWalkEnabled then
        startAutoWalk()
        sendNotification("LumiWare", "Auto-walk ON — walking in circles", 3)
        addBattleLog("🚶 Auto-walk ON", C.Green)
    else
        stopAutoWalk()
        sendNotification("LumiWare", "Auto-walk OFF", 3)
        addBattleLog("🚶 Auto-walk OFF", C.TextDim)
    end
end)

--------------------------------------------------
-- AUTO-BATTLE: Find & Click Game UI Buttons
-- From scan: buttons are at
--   PlayerGui/MainGui/Frame/BattleGui/Run/Button
--   PlayerGui/MainGui/Frame/BattleGui/Move1/Button
--   PlayerGui/MainGui/Frame/BattleGui/Move2/Button
--   PlayerGui/MainGui/Frame/BattleGui/Move3/Button
--   PlayerGui/MainGui/Frame/BattleGui/Move4/Button
-- All are ImageButtons.
--------------------------------------------------
local function isVisible(obj)
    if not obj then return false end
    if obj:IsA("GuiObject") and not obj.Visible then return false end
    if obj.Parent and obj.Parent:IsA("GuiObject") and not obj.Parent.Visible then return false end
    return true
end

local function findBattleUI()
    local pgui = player:FindFirstChild("PlayerGui")
    if not pgui then
        log("AUTO", "findBattleUI: no PlayerGui")
        return nil
    end

    local result = {
        runButton = nil,
        fightButton = nil,
        moveButtons = {},
        moveNames = {},
    }

    -- METHOD 1: Fast Recursive search (Fastest for deeply nested dynamic GUI)
    local battleGui = pgui:FindFirstChild("BattleGui", true)

    if not battleGui then
        return nil
    end

    -- Run button: BattleGui/Run/Button
    local runContainer = battleGui:FindFirstChild("Run")
    if runContainer and isVisible(runContainer) then
        local runBtn = runContainer:FindFirstChild("Button")
        if runBtn and isVisible(runBtn) then
            result.runButton = runBtn
        end
    end

    -- Fight button: BattleGui/Fight/Button
    local fightContainer = battleGui:FindFirstChild("Fight")
    if fightContainer and isVisible(fightContainer) then
        local fBtn = fightContainer:FindFirstChild("Button")
        if fBtn and isVisible(fBtn) then
            result.fightButton = fBtn
        end
    end
    -- Fallback: scan all direct children for Fight-like containers OR unnamed ImageLabels
    if not result.fightButton then
        for _, child in ipairs(battleGui:GetChildren()) do
            if isVisible(child) then
                local cname = child.Name:lower()
                -- It's either explicitly named "fight/attack" OR it's just an ImageLabel containing a Button, 
                -- but NOT one of the known others (Run, Bag, Loomians, Items)
                if cname == "fight" or string.find(cname, "fight") or string.find(cname, "attack") or 
                   (child:IsA("ImageLabel") and cname ~= "run" and cname ~= "bag" and cname ~= "loomians" and cname ~= "items") then
                    
                    local btn = child:FindFirstChild("Button")
                    if btn and isVisible(btn) then
                        result.fightButton = btn
                        break
                    end
                end
            end
        end
    end

    -- Move buttons: BattleGui/Move1/Button through Move4/Button
    for i = 1, 4 do
        local moveContainer = battleGui:FindFirstChild("Move" .. i)
        if moveContainer and isVisible(moveContainer) then
            local moveBtn = moveContainer:FindFirstChild("Button")
            if moveBtn and isVisible(moveBtn) then
                result.moveButtons[i] = moveBtn
                
                -- Try to find the TextLabel containing the move's name
                local txt = moveContainer:FindFirstChildOfClass("TextLabel")
                if not txt and moveBtn then
                    txt = moveBtn:FindFirstChildOfClass("TextLabel")
                end
                if txt and txt.Text then
                    result.moveNames[i] = txt.Text:lower()
                end
            end
        end
    end

    return result
end

local function clickButton(button)
    if not button then return false end
    local success = false
    pcall(function()
        -- Method 1: fireclick (common executor function)
        if fireclick then
            fireclick(button)
            success = true
            return
        end
        -- Method 2: firesignal
        if firesignal then
            firesignal(button.MouseButton1Click)
            success = true
            return
        end
        -- Method 3: VirtualInputManager
        local absPos = button.AbsolutePosition
        local absSize = button.AbsoluteSize
        local cx = absPos.X + absSize.X / 2
        local cy = absPos.Y + absSize.Y / 2
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
        success = true
    end)
    return success
end

local function performAutoAction()
    if autoMode == "off" or rareFoundPause or pendingAutoAction then return end
    if currentBattle.battleType ~= "Wild" then return end

    pendingAutoAction = true
    log("AUTO", "performAutoAction triggered, mode=" .. autoMode)

    task.spawn(function()
        -- Poll for battle UI buttons to appear
        local ui = nil
        local pollStart = tick()
        local maxWait = 30

        while (tick() - pollStart) < maxWait do
            if rareFoundPause or autoMode == "off" then
                pendingAutoAction = false
                return
            end

            ui = findBattleUI()
            if ui then
                if autoMode == "run" and ui.runButton then
                    log("AUTO", "Battle UI ready for RUN after " .. string.format("%.1f", tick() - pollStart) .. "s")
                    break
                elseif ui.runButton or ui.fightButton then
                    log("AUTO", "Battle UI ready after " .. string.format("%.1f", tick() - pollStart) .. "s")
                    break
                end
            end

            task.wait(0.1)
        end

        if not ui or (not ui.runButton and not ui.fightButton) then
            log("AUTO", "Battle UI not found after " .. maxWait .. "s")
            addBattleLog("⚠ Auto: Battle UI timed out", C.Orange)
            pendingAutoAction = false
            return
        end

        if autoMode == "run" then
            if ui.runButton then
                log("AUTO", "Auto-RUN: clicking Run")
                addBattleLog("🤖 Auto-RUN ▸ fleeing", C.Cyan)
                clickButton(ui.runButton)
            else
                addBattleLog("⚠ Auto: Run button not found", C.Orange)
            end
        elseif autoMode == "move" then
            -- BATTLE LOOP: repeat Fight → Move each turn until battle ends
            local turnCount = 0
            local maxTurns = 20 -- safety limit

            while turnCount < maxTurns do
                turnCount = turnCount + 1
                if rareFoundPause or autoMode ~= "move" then break end

                -- Re-scan UI each turn (wait up to 10s for it to reappear if transitioning)
                local turnUI = nil
                local turnStart = tick()
                while (tick() - turnStart) < 10 do
                    if rareFoundPause or autoMode ~= "move" then break end
                    turnUI = findBattleUI()
                    if turnUI and (turnUI.fightButton or #turnUI.moveButtons > 0) then break end
                    task.wait(0.1)
                end

                if not turnUI or (not turnUI.fightButton and #turnUI.moveButtons == 0) then
                    log("AUTO", "Auto-MOVE: No UI found, assuming cutscene/animation. Waiting...")
                    -- Don't break here, let the bottom wait loop handle the patience
                    turnUI = { fightButton = nil, moveButtons = {}, moveNames = {} }
                end

                -- STEP 1: Click Fight if present, OR if we magically already have moves open, click them
                if turnUI.fightButton and #turnUI.moveButtons == 0 then
                    log("AUTO", "Auto-MOVE turn " .. turnCount .. ": clicking Fight")
                    if turnCount == 1 then
                        addBattleLog("🤖 Auto-MOVE ▸ fighting...", C.Green)
                    end
                    clickButton(turnUI.fightButton)

                    -- STEP 2: Wait for move buttons to appear (and Fight button to vanish)
                    local moveUI = nil
                    local moveStart = tick()
                    while (tick() - moveStart) < 5 do
                        task.wait(0.05) -- Very fast poll
                        moveUI = findBattleUI()
                        -- Explicitly wait for the Fight button to disappear AND moves to appear
                        if moveUI and not moveUI.fightButton and (#moveUI.moveButtons > 0) then
                            -- Instant break, no wait! 
                            break
                        end
                    end

                    if moveUI and (#moveUI.moveButtons > 0) then
                        local targetSlot = autoMoveSlot
                        
                        -- If the user typed a string instead of a number, try to map it to a slot
                        if type(autoMoveSlot) == "string" and not tonumber(autoMoveSlot) then
                            local searchName = string.lower(autoMoveSlot)
                            for s = 1, 4 do
                                if moveUI.moveNames[s] and string.find(moveUI.moveNames[s], searchName) then
                                    targetSlot = s
                                    break
                                end
                            end
                            -- Fallback to slot 1 if the name wasn't found
                            if type(targetSlot) == "string" then targetSlot = 1 end
                        else
                            targetSlot = tonumber(autoMoveSlot) or 1
                        end
                        
                        targetSlot = math.clamp(targetSlot, 1, 4)

                        if moveUI.moveButtons[targetSlot] then
                            log("AUTO", "Auto-MOVE turn " .. turnCount .. ": Move" .. targetSlot)
                            addBattleLog("🤖 Turn " .. turnCount .. " ▸ Move " .. targetSlot, C.Green)
                            clickButton(moveUI.moveButtons[targetSlot])
                        else
                            for s = 1, 4 do
                                if moveUI.moveButtons[s] then
                                    addBattleLog("🤖 Turn " .. turnCount .. " ▸ Move " .. s .. " (fb)", C.Green)
                                    clickButton(moveUI.moveButtons[s])
                                    break
                                end
                            end
                        end
                    else
                        addBattleLog("⚠ No move buttons turn " .. turnCount, C.Orange)
                        -- Don't break, just let the wait loop run
                    end
                elseif #turnUI.moveButtons > 0 then
                    -- We already handled moves in the first block if they existed
                    local targetSlot = autoMoveSlot
                    if type(autoMoveSlot) == "string" and not tonumber(autoMoveSlot) then
                        local searchName = string.lower(autoMoveSlot)
                        for s = 1, 4 do
                            if turnUI.moveNames[s] and string.find(turnUI.moveNames[s], searchName) then
                                targetSlot = s
                                break
                            end
                        end
                        if type(targetSlot) == "string" then targetSlot = 1 end
                    else
                        targetSlot = tonumber(autoMoveSlot) or 1
                    end
                    targetSlot = math.clamp(targetSlot, 1, 4)

                    if turnUI.moveButtons[targetSlot] then
                        clickButton(turnUI.moveButtons[targetSlot])
                        addBattleLog("🤖 Turn " .. turnCount .. " ▸ Move " .. targetSlot, C.Green)
                    else
                        for s = 1, 4 do
                            if turnUI.moveButtons[s] then
                                clickButton(turnUI.moveButtons[s])
                                addBattleLog("🤖 Turn " .. turnCount .. " ▸ Move " .. s .. " (fb)", C.Green)
                                break
                            end
                        end
                    end
                end

                -- Wait for the UI to disappear (meaning the move was selected and animations are starting)
                local vanishStart = tick()
                while (tick() - vanishStart) < 5 do
                    local vUI = findBattleUI()
                    if not vUI or (#vUI.moveButtons == 0 and not vUI.fightButton) then
                        break
                    end
                    task.wait(0.05)
                end

                -- Now wait for the animations to finish and the next turn to start
                local waitStart = tick()
                local battleEnded = false
                while (tick() - waitStart) < 30 do -- Increased timeout for long attack animations
                    if rareFoundPause or autoMode ~= "move" then break end
                    local checkUI = findBattleUI()
                    if checkUI and (checkUI.fightButton or checkUI.runButton) then
                        log("AUTO", "Next turn ready")
                        break
                    elseif not checkUI and (tick() - waitStart) > 5 then
                        -- Check if we're actually back in the overworld (battle over)
                        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                            -- Simple heuristic: if we've been waiting 5+ seconds without UI, and we have our character, battle is probably over
                            -- We will let the main loop re-verify
                        end
                    end
                    task.wait(0.2)
                end

                -- Check if battle ended
                local finalCheck = findBattleUI()
                if not finalCheck and (tick() - waitStart) >= 30 then
                    -- If we strictly timed out after 30 seconds with NO UI, it's safe to assume battle is over 
                    -- (or the game broke, in which case we should abort anyway)
                    log("AUTO", "Battle ended after " .. turnCount .. " turns (timeout)")
                    addBattleLog("🤖 Battle done (" .. turnCount .. " turns)", C.Green)
                    break
                elseif finalCheck and not finalCheck.fightButton and not finalCheck.runButton and #finalCheck.moveButtons == 0 then
                    -- We see the UI, but it has no buttons. It might just be an animation still, so we DON'T break
                    -- It will loop back up to turnCount + 1 and hit the 10-second turn check wait.
                    log("AUTO", "Turn " .. turnCount .. " ended, looping to next")
                end
            end
        end

        -- After action fires, reset state for auto-walk to resume
        task.wait(1)
        if battleState == "active" then
            battleState = "idle"
            stateVal.Text = "Idle"
            stateVal.TextColor3 = C.TextDim
            log("AUTO", "Battle state reset to idle after auto-action")
        end

        pendingAutoAction = false
    end)
end

--------------------------------------------------
-- BATTLE PROCESSING (THE CORE FIX)
--
-- From discovery logs, the actual data is:
--   arg4 = { {cmd, ...}, {cmd, ...}, ... }
-- Where commands are:
--   {"player", "p2", "#Wild", 0}
--   {"player", "p1", "glo", 0}
--   {"owm", "p1", "1p1: Dripple", "Dripple, L13, M;41/44;...", {disc=..., name=..., scale=...}, 0}
--   {"start"}
--   {"switch", "1p2a: Grubby", "Grubby, L5, M;18/18;...", {disc=..., name=...}, {icon=...}}
--
-- KEY DIFFERENCE: "owm" has side as entry[2], identifier as entry[3]
--                 "switch" has identifier as entry[2] (contains side like "p2a")
--------------------------------------------------

local function extractNameAndSide(cmdEntry)
    -- Returns: rawName, side ("p1"/"p2"), infoStr, displayName
    local cmd = cmdEntry[1]
    if type(cmd) ~= "string" then return nil end
    local cmdL = string.lower(cmd)

    if cmdL ~= "owm" and cmdL ~= "switch" then return nil end

    local rawName = nil
    local side = nil
    local infoStr = nil

    -- Scan ALL string args to find: side, identifier (has ":"), and info string (has ", L")
    for i = 2, math.min(#cmdEntry, 8) do
        local v = cmdEntry[i]
        if type(v) == "string" then
            -- Pure side: "p1" or "p2"
            if (v == "p1" or v == "p2") and not side then
                side = v
            -- Identifier with colon: "1p1a: Dripple" or "1p2a: Grubby"
            elseif string.find(v, ":%s*.+") then
                local n = v:match(":%s*(.+)$")
                if n then rawName = n end
                -- Extract side from identifier too
                if string.find(v, "p1") then side = side or "p1"
                elseif string.find(v, "p2") then side = side or "p2" end
            -- Info string: "Dripple, L13, M;41/44;..."
            elseif string.find(v, ", L%d+") then
                infoStr = v
                -- Can also get name from info string
                if not rawName then
                    rawName = v:match("^([^,]+)")
                end
            end
        elseif type(v) == "table" and not rawName then
            -- Model table: might have .name
            if type(v.name) == "string" then
                rawName = v.name
            end
        end
    end

    if rawName then
        return rawName, side, infoStr, extractLoomianName(rawName)
    end
    return nil
end

local function processBattleCommands(commandTable)
    log("BATTLE", "========== PROCESSING " .. tostring(#commandTable) .. " COMMANDS ==========")
    addBattleLog(">>> " .. tostring(#commandTable) .. " battle cmds <<<", C.Green)

    -- Check for "start" -> new battle
    for _, entry in pairs(commandTable) do
        if type(entry) == "table" and type(entry[1]) == "string" and string.lower(entry[1]) == "start" then
            log("BATTLE", "  NEW BATTLE (start found)")
            resetBattle()
            currentBattle.active = true
            break
        end
    end

    -- Process "player" commands first (to establish battle type)
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

    -- Process "owm" and "switch" commands (Loomian data)
    -- ALSO: deep scan each enemy entry for gleam/corrupt/gamma
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
                        currentBattle.enemyRawEntry = entry  -- save for deep scan
                        log("BATTLE", "    -> ENEMY: " .. displayName)
                    elseif side == "p1" then
                        currentBattle.player = displayName
                        currentBattle.playerStats = stats
                        log("BATTLE", "    -> PLAYER: " .. displayName)
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
                else
                    log("BATTLE", "  " .. entry[1] .. ": FAILED to extract name")
                    for idx = 1, math.min(#entry, 6) do
                        log("BATTLE", "    [" .. idx .. "] type=" .. type(entry[idx]) .. " val=" .. tostring(entry[idx]))
                    end
                end
            end
        end
    end

    -- Also try to get enemy name from "move" / "damage" commands if still unknown
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
                                log("BATTLE", "  enemy from " .. cmdL .. ": " .. currentBattle.enemy)
                                break
                            end
                        end
                    end
                    if currentBattle.enemy then break end
                end
            end
        end
    end

    -- TRACK MASTERY (Damage and KOs)
    for _, entry in pairs(commandTable) do
        if type(entry) == "table" and type(entry[1]) == "string" then
            local cmdL = string.lower(entry[1])
            if cmdL == "faint" then
                if type(entry[2]) == "string" and string.find(entry[2], "p2") then
                    sessionKOs = sessionKOs + 1
                    sessionLbl.Text = string.format("Session: %d KOs | %.1fk Damage", sessionKOs, sessionDamage / 1000)
                    log("MASTERY", "Enemy fainted! Session KOs: " .. sessionKOs)
                end
            elseif cmdL == "-damage" or cmdL == "damage" then
                if type(entry[2]) == "string" and string.find(entry[2], "p2") then
                    -- Often the damage text is just "45/100" (remaining HP).
                    -- For now, increment by a fixed 100 per hit just to show progression.
                    sessionDamage = sessionDamage + 100
                    sessionLbl.Text = string.format("Session: %d KOs | %.1fk Damage", sessionKOs, sessionDamage / 1000)
                end
            end
        end
    end

    -- Mark active
    battleState = "active"
    lastBattleTick = tick()
    currentBattle.active = true
    stateVal.Text = "In Battle"
    stateVal.TextColor3 = C.Green

    local enemyName = currentBattle.enemy or "Unknown"
    local playerName = currentBattle.player or "Unknown"

    log("BATTLE", "RESULT: Enemy=" .. enemyName .. " Player=" .. playerName .. " Type=" .. currentBattle.battleType)

    -- Update display
    if currentBattle.battleType == "Wild" then
        typeVal.Text = "Wild"; typeVal.TextColor3 = C.Wild
    elseif currentBattle.battleType == "Trainer" then
        typeVal.Text = "Trainer"; typeVal.TextColor3 = C.Trainer
    end

    if enemyName ~= "Unknown" and not currentBattle.enemyProcessed then
        currentBattle.enemyProcessed = true

        if currentBattle.battleType == "Wild" then
            encounterCount = encounterCount + 1
            encounterVal.Text = tostring(encounterCount)
            table.insert(encounterHistory, 1, { name = enemyName, time = os.date("%X") })
            if #encounterHistory > 10 then table.remove(encounterHistory, 11) end
        end

        -- MULTI-LAYER RARE CHECK:
        -- 1. Is the enemy name in the rare list?
        -- 2. Does the name contain a rare modifier (gleam/gamma/etc)?
        -- 3. Deep scan the raw command entry (model tables, disc names, etc.)
        local rareFound = isRareLoomian(enemyName) or isRareModifier(enemyName)
        if not rareFound and currentBattle.enemyRawEntry then
            rareFound = scanEntryForRare(currentBattle.enemyRawEntry)
            if rareFound then
                log("RARE", "!!! DEEP SCAN caught rare in model/disc data !!!")
            end
        end
        if rareFound then
            enemyLbl.Text = 'Enemy: <font color="#FFD700">⭐ ' .. enemyName .. ' (RARE!)</font>'
            addBattleLog("⭐ RARE: " .. enemyName, C.Gold)
            -- PAUSE automation on rare!
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
            -- Trigger auto-action on non-rare wild encounter
            if currentBattle.battleType == "Wild" and autoMode ~= "off" and not rareFoundPause then
                performAutoAction()
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

--------------------------------------------------
-- HOOK REMOTES
-- CRITICAL: Do NOT use vararg forwarding to helper
-- functions — Roblox executors break it.
-- Instead, capture args into a table IMMEDIATELY
-- at the top of the callback.
--------------------------------------------------
local hooked = {}
local hookedCount = 0

local KNOWN_COMMANDS = {
    player = true, owm = true, switch = true, start = true,
    move = true, damage = true, ["-damage"] = true,
    turn = true, faint = true, ["end"] = true,
}

local function hookEvent(remote)
    if hooked[remote] then return end
    hooked[remote] = true
    hookedCount = hookedCount + 1

    remote.OnClientEvent:Connect(function(...)
        -- ============================================
        -- STEP 0: Capture ALL args into a table IMMEDIATELY
        -- Do not rely on ... after this point.
        -- ============================================
        local argCount = select("#", ...)
        local allArgs = {}
        for i = 1, argCount do
            allArgs[i] = select(i, ...)
        end
        allArgs.n = argCount

        -- Discovery logging
        if discoveryMode then
            local parts = {}
            for i = 1, argCount do
                local a = allArgs[i]
                local info = "arg" .. i .. "=" .. type(a)
                if type(a) == "string" then
                    info = info .. '("' .. string.sub(a, 1, 20) .. '")'
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
                    if type(a) == "table" then
                        log("EVT", remote.Name, "arg" .. i .. ":", tablePreview(a))
                    end
                end
            end
        end

        -- ============================================
        -- STEP 1: Is this a battle event?
        -- ============================================
        local isBattle = false
        if type(allArgs[1]) == "string" then
            if string.lower(allArgs[1]):find("battle") then
                isBattle = true
            end
        end

        -- ============================================
        -- STEP 2: Find and decode the command table
        -- CRITICAL: Battle commands are JSON-ENCODED
        -- STRINGS, not Lua tables! e.g.:
        --   arg4[1] = '["player","p2","#Wild",0]'
        --   arg4[2] = '["player","p1","glo",0]'
        -- We must JSONDecode each entry first.
        -- ============================================
        local cmdTable = nil

        for i = 1, argCount do
            local arg = allArgs[i]
            if type(arg) == "table" then
                -- Check entries: are they JSON strings or Lua tables?
                for k, v in pairs(arg) do
                    if type(v) == "table" then
                        -- Already a Lua table (unlikely based on diagnostics, but handle it)
                        local first = v[1]
                        if type(first) == "string" and KNOWN_COMMANDS[string.lower(first)] then
                            log("BATTLE", ">>> FOUND native cmd table in arg" .. i)
                            cmdTable = arg
                            break
                        end
                    elseif type(v) == "string" and string.sub(v, 1, 1) == "[" then
                        -- JSON-encoded string! Try to decode it
                        local ok, decoded = pcall(function()
                            return HttpService:JSONDecode(v)
                        end)
                        if ok and type(decoded) == "table" and type(decoded[1]) == "string" then
                            local cmd = string.lower(decoded[1])
                            if KNOWN_COMMANDS[cmd] then
                                log("BATTLE", ">>> FOUND JSON cmd table in arg" .. i .. " (cmd=" .. decoded[1] .. ")")
                                -- Decode ALL entries in this table
                                local decodedTable = {}
                                for key, val in pairs(arg) do
                                    if type(val) == "string" and string.sub(val, 1, 1) == "[" then
                                        local ok2, dec2 = pcall(function()
                                            return HttpService:JSONDecode(val)
                                        end)
                                        if ok2 and type(dec2) == "table" then
                                            decodedTable[key] = dec2
                                        else
                                            decodedTable[key] = val
                                        end
                                    elseif type(val) == "string" and string.sub(val, 1, 1) == "{" then
                                        local ok2, dec2 = pcall(function()
                                            return HttpService:JSONDecode(val)
                                        end)
                                        if ok2 and type(dec2) == "table" then
                                            decodedTable[key] = dec2
                                        else
                                            decodedTable[key] = val
                                        end
                                    else
                                        decodedTable[key] = val
                                    end
                                end
                                cmdTable = decodedTable
                                break
                            end
                        end
                    end
                end
                if cmdTable then break end
            end
        end

        -- ============================================
        -- STEP 3: Process battle data if found
        -- ============================================
        if cmdTable then
            processBattleCommands(cmdTable)
        elseif isBattle then
            logDebug("BattleEvent no cmd table, arg3=" .. tostring(allArgs[3]))
        end
    end)
end

-- Hook all
log("HOOK", "Scanning...")
local c = 0
for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
    if obj:IsA("RemoteEvent") then hookEvent(obj) c = c + 1 end
end
log("HOOK", "Hooked", c, "from ReplicatedStorage")

ReplicatedStorage.DescendantAdded:Connect(function(obj)
    if obj:IsA("RemoteEvent") then hookEvent(obj) end
end)

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

addBattleLog("Hooked " .. hookedCount .. " remotes — READY", C.Green)
log("INFO", "LumiWare v4 READY | Hooked " .. hookedCount .. " | Player: " .. PLAYER_NAME)
sendNotification("⚡ LumiWare v4", "Hooked " .. hookedCount .. " remotes.\nBattle detection + automation ready.", 6)
