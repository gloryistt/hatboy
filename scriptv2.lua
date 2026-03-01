--------------------------------------------------
-- LUMIWARE V4.6 — Enhanced Update
-- Fixed: Lua 200-local-register limit
-- Trainer Auto | Config Tab | Auto-Heal | Filters
--------------------------------------------------
local Svc = {
    Players   = game:GetService("Players"),
    RS        = game:GetService("ReplicatedStorage"),
    Tween     = game:GetService("TweenService"),
    CoreGui   = game:GetService("CoreGui"),
    StarterGui= game:GetService("StarterGui"),
    Sound     = game:GetService("SoundService"),
    UIS       = game:GetService("UserInputService"),
    Http      = game:GetService("HttpService"),
    Run       = game:GetService("RunService"),
    VIM       = game:GetService("VirtualInputManager"),
    GUI       = game:GetService("GuiService"),
}

local VERSION    = "v4.6"
local player     = Svc.Players.LocalPlayer
local PLAYER_NAME = player.Name

--------------------------------------------------
-- CONFIG
--------------------------------------------------
local CFG_FILE = "LumiWare_v46_Config.json"
local DEFAULT_CFG = {
    webhookUrl="", pingIds="",
    autoMode="off", autoMoveSlot=1,
    trainerAutoMode="off", trainerAutoMoveSlot=1,
    autoWalk=false, discoveryMode=false, customRares={},
    autoHealEnabled=false, autoHealThreshold=30,
    healRemoteName="", healRemotePath="", autoHealMethod="remote",
    automateTrainer=true, automateWild=true,
}
local cfg = {}
for k,v in pairs(DEFAULT_CFG) do cfg[k]=v end
if isfile and readfile and writefile then
    pcall(function()
        if isfile(CFG_FILE) then
            local ok, dec = pcall(function() return Svc.Http:JSONDecode(readfile(CFG_FILE)) end)
            if ok and type(dec)=="table" then for k,v in pairs(dec) do cfg[k]=v end end
        else writefile(CFG_FILE, Svc.Http:JSONEncode(DEFAULT_CFG)) end
    end)
end
local function saveConfig()
    if writefile then pcall(function() writefile(CFG_FILE, Svc.Http:JSONEncode(cfg)) end) end
end
local function resetCfgDefault()
    for k,v in pairs(DEFAULT_CFG) do cfg[k]=v end
    saveConfig()
end

--------------------------------------------------
-- LOGGING
--------------------------------------------------
local VERBOSE = false
local function log(cat,...) print("[LumiWare]["..cat.."]",...) end
local function logD(...) if VERBOSE then log("DBG",...) end end

log("INFO","LumiWare "..VERSION.." starting for: "..PLAYER_NAME)

--------------------------------------------------
-- STATE (consolidated into tables)
--------------------------------------------------
local State = {
    encounterCount=0, huntStart=tick(), currentEnemy=nil,
    isMinimized=false, battleState="idle", lastBattleTick=0,
    raresFound=0, encounterHistory={}, discoveryMode=false,
    sessionKOs=0, sessionDamage=0,
    pendingAutoAction=false, rareFoundPause=false,
}
local Auto = {
    wildMode   = cfg.autoMode or "off",
    wildSlot   = cfg.autoMoveSlot or 1,
    trMode     = cfg.trainerAutoMode or "off",
    trSlot     = cfg.trainerAutoMoveSlot or 1,
    walkEnabled= false, walkThread=nil,
    trainerOn  = (cfg.automateTrainer ~= false),
    wildOn     = (cfg.automateWild ~= false),
}
local Heal = {
    enabled    = cfg.autoHealEnabled or false,
    threshold  = cfg.autoHealThreshold or 30,
    remote     = nil,
    remoteName = cfg.healRemoteName or "",
    remotePath = cfg.healRemotePath or "",
    method     = cfg.autoHealMethod or "remote",
    lastTime   = 0, cooldown=10,
    scanned    = {},
}
local Battle = {
    active=false, enemy=nil, player=nil,
    enemyStats=nil, playerStats=nil,
    battleType="N/A", enemyProcessed=false, enemyRawEntry=nil,
}
local Webhook = { url = cfg.webhookUrl or "" }
local customRares = cfg.customRares or {}

local function resetBattle()
    Battle={active=false,enemy=nil,player=nil,
        enemyStats=nil,playerStats=nil,
        battleType="N/A",enemyProcessed=false,enemyRawEntry=nil}
end

--------------------------------------------------
-- RARE DATA
--------------------------------------------------
local RARE_LOOMIANS = {
    "Duskit","Ikazune","Mutagon","Metronette","Wabalisc",
    "Cephalops","Elephage","Gargolem","Celesting","Nyxre","Pyramind",
    "Terracolt","Garbantis","Avitross","Snocub","Eaglit","Grimyuline",
    "Vambat","Weevolt","Nevermare","Protogon","Mimask","Odoyaga","Yari",
    "Akhalos","Odasho","Cosmiore","Dakuda","Shawchi","Arceros","Galacadia"
}
local RARE_MOD = {"gleam","gleaming","gamma","corrupt","corrupted","alpha",
    "iridescent","metallic","rainbow","sa ","pn ","hw ","ny ","secret","shiny","radiant"}
local RARE_KW  = {"gleam","gamma","corrupt","alpha","iridescent","metallic",
    "rainbow","shiny","radiant","secret"}

local function isRareMod(name)
    if type(name)~="string" then return false end
    local l=name:lower()
    for _,m in ipairs(RARE_MOD) do if l:find(m) then return true end end
    return false
end

local function deepScanRare(val,depth)
    if depth>5 then return false end
    depth=depth or 0
    if type(val)=="string" then
        local l=val:lower()
        for _,kw in ipairs(RARE_KW) do if l:find(kw) then return true end end
    elseif type(val)=="table" then
        for k,v in pairs(val) do
            if type(k)=="string" then
                local kl=k:lower()
                if kl=="variant" or kl=="gleam" or kl=="gamma" or kl=="corrupt"
                   or kl=="issecret" or kl=="isgleam" or kl=="isgamma" then
                    if v==true or v==1 or (type(v)=="string" and v~="" and v~="false" and v~="0") then
                        return true end
                end
            end
            if deepScanRare(v,depth+1) then return true end
        end
    end
    return false
end

local function scanEntryRare(entry)
    if type(entry)~="table" then return false end
    for i=1,#entry do
        local v=entry[i]
        if type(v)=="string" and isRareMod(v) then return true end
        if type(v)=="table"  and deepScanRare(v,0) then return true end
    end
    return false
end

local function isRareLoomian(name)
    local l=name:lower()
    for _,r in ipairs(RARE_LOOMIANS) do if l:find(r:lower()) then return true end end
    for _,r in ipairs(customRares)    do if l:find(r:lower()) then return true end end
    return false
end

--------------------------------------------------
-- MASTERY DATA
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
    D="Discover all stages",E="Earn Experience",R="Rally",K="KO Loomians",
    C="Capture",DD="Deal Damage",KSE="KO w/ Super Effective",DC="Deal Crits",
    LU="Level Up",FB="Form Perfect Bond",BU="Burn Loomians",PA="Paralyze",
    SL="Put to Sleep",PO="Poison Loomians",FR="Inflict Frostbite"
}

local function searchMastery(query)
    if not query or query=="" then return MASTERY_DATA end
    local q=query:lower(); local out={}
    for _,e in ipairs(MASTERY_DATA) do if e.f:lower():find(q) then out[#out+1]=e end end
    return out
end

--------------------------------------------------
-- HELPERS
--------------------------------------------------
local function notify(t,msg,dur)
    pcall(function() Svc.StarterGui:SetCore("SendNotification",{Title=t,Text=msg,Duration=dur or 5}) end)
end

local function playRare()
    pcall(function()
        local s=Instance.new("Sound"); s.SoundId="rbxassetid://6518811702"
        s.Volume=1; s.Parent=Svc.Sound; s:Play()
        task.delay(3,function() s:Destroy() end)
    end)
end

local function fmtTime(s)
    local h=math.floor(s/3600); local m=math.floor((s%3600)/60); local sc=math.floor(s%60)
    return h>0 and ("%dh %02dm %02ds"):format(h,m,sc) or ("%dm %02ds"):format(m,sc)
end

local function nameFormat(str)
    if not str then return "Unknown" end
    return str:gsub("-"," "):gsub("(%a)([%w_]*)",function(a,b) return a:upper()..b end)
end

local function parseStats(info)
    if type(info)~="string" then return nil end
    local name,lv,rest=info:match("^(.+), L(%d+), (.+)$")
    if not lv then return nil end
    local g=rest:match("^(%a)") or "?"
    local hp,mhp=rest:match("(%d+)/(%d+)")
    return {name=name,level=tonumber(lv),gender=g,hp=tonumber(hp),maxHP=tonumber(mhp)}
end

local function tblPreview(tbl,depth)
    depth=depth or 0; if depth>2 then return "{...}" end
    local parts,c={},0
    for k,v in pairs(tbl) do
        c=c+1; if c>6 then parts[#parts+1]="..."; break end
        parts[#parts+1]=tostring(k).."="..(type(v)=="table" and tblPreview(v,depth+1) or tostring(v))
    end
    return "{"..table.concat(parts,", ").."}"
end

local function getPath(obj)
    local p=obj.Name; local cur=obj.Parent
    while cur and cur~=game do p=cur.Name.."/"..p; cur=cur.Parent end
    return p
end

--------------------------------------------------
-- WEBHOOK
--------------------------------------------------
local function sendWebhook(embed, content)
    if Webhook.url=="" then return end
    pcall(function()
        local pl={username="LumiWare",embeds={embed}}
        if content then pl.content=content end
        local body=Svc.Http:JSONEncode(pl)
        local fn=(syn and syn.request) or (http and http.request) or request or http_request
        if fn then fn({Url=Webhook.url,Method="POST",Headers={["Content-Type"]="application/json"},Body=body}) end
    end)
end

local function rarityTier(name)
    local l=name:lower()
    local sr={"duskit","ikazune","mutagon","protogon","metronette","wabalisc",
        "cephalops","elephage","gargolem","celesting","nyxre","odasho","cosmiore","nevermare","akhalos"}
    for _,r in ipairs(sr) do if l:find(r) then return "SUPER RARE" end end
    if l:find("gamma")  then return "GAMMA RARE" end
    if l:find("gleam")  then return "GLEAMING RARE" end
    if l:find("corrupt")then return "CORRUPT" end
    if l:find("sa ") or l:find("secret") then return "SECRET ABILITY" end
    return "RARE"
end

local function webhookRare(name,lv,gender,enc,hTime)
    local rt=rarityTier(name)
    sendWebhook({title="⭐ "..rt.." FOUND!",description="**"..name.."** detected!",color=16766720,
        fields={{name="Rarity",value=rt,inline=true},{name="Loomian",value=name,inline=true},
            {name="Level",value=tostring(lv or "?"),inline=true},{name="Gender",value=gender or "?",inline=true},
            {name="Encounters",value=tostring(enc),inline=true},{name="Hunt Time",value=hTime or "?",inline=true},
            {name="Player",value=PLAYER_NAME,inline=true}},
        footer={text="LumiWare "..VERSION.." • "..os.date("%X")}},
    "@everyone")
end

local function webhookSession(enc,hTime,rares)
    sendWebhook({title="📊 Session Summary",color=7930367,
        fields={{name="Encounters",value=tostring(enc),inline=true},
            {name="Hunt Time",value=hTime,inline=true},{name="Rares",value=tostring(rares),inline=true},
            {name="Player",value=PLAYER_NAME,inline=true}},
        footer={text="LumiWare "..VERSION.." • "..os.date("%X")}})
end

--------------------------------------------------
-- CLEANUP
--------------------------------------------------
if _G.LumiWare_Cleanup then pcall(_G.LumiWare_Cleanup) end

local allConns={}
local function track(c) allConns[#allConns+1]=c; return c end

_G.LumiWare_Cleanup=function()
    for _,c in ipairs(allConns) do pcall(function() c:Disconnect() end) end
    allConns={}
    pcall(function()
        if _G.LumiWare_Threads then
            for _,t in ipairs(_G.LumiWare_Threads) do task.cancel(t) end
            _G.LumiWare_Threads={}
        end
    end)
    pcall(function()
        if _G.LumiWare_WalkThread then task.cancel(_G.LumiWare_WalkThread); _G.LumiWare_WalkThread=nil end
    end)
    pcall(function() _G.LumiWare_StopFlag=true end)
    pcall(function()
        for _,v in pairs(player:WaitForChild("PlayerGui"):GetChildren()) do
            if v.Name:find("LumiWare_Hub") or v.Name=="BattleLoomianViewer" then v:Destroy() end
        end
    end)
    pcall(function()
        for _,v in pairs(Svc.CoreGui:GetChildren()) do
            if v.Name:find("LumiWare_Hub") or v.Name=="BattleLoomianViewer" then v:Destroy() end
        end
    end)
    pcall(function() Svc.VIM:SendKeyEvent(false,Enum.KeyCode.LeftShift,false,game) end)
end

do -- immediate cleanup of orphaned GUIs
    for _,v in pairs(player:WaitForChild("PlayerGui"):GetChildren()) do
        if v.Name:find("LumiWare_Hub") or v.Name=="BattleLoomianViewer" then v:Destroy() end
    end
    pcall(function()
        for _,v in pairs(Svc.CoreGui:GetChildren()) do
            if v.Name:find("LumiWare_Hub") or v.Name=="BattleLoomianViewer" then v:Destroy() end
        end
    end)
end

_G.LumiWare_StopFlag=false
_G.LumiWare_Threads={}

--------------------------------------------------
-- GUI SETUP
--------------------------------------------------
local gui=Instance.new("ScreenGui")
gui.Name="LumiWare_Hub_"..tostring(math.random(1000,9999))
gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true
if not pcall(function() gui.Parent=Svc.CoreGui end) then gui.Parent=player:WaitForChild("PlayerGui") end

-- THEME
local C={
    BG=Color3.fromRGB(13,13,18), Top=Color3.fromRGB(20,20,28),
    Accent=Color3.fromRGB(110,80,255), AccentDim=Color3.fromRGB(75,55,180),
    Text=Color3.fromRGB(245,245,250), Dim=Color3.fromRGB(150,150,165),
    Panel=Color3.fromRGB(20,20,26), PanelAlt=Color3.fromRGB(26,26,34),
    Gold=Color3.fromRGB(255,210,50), Green=Color3.fromRGB(60,215,120),
    Red=Color3.fromRGB(255,75,90), Wild=Color3.fromRGB(70,190,255),
    Trainer=Color3.fromRGB(255,150,60), Cyan=Color3.fromRGB(70,190,255),
    Pink=Color3.fromRGB(255,100,200), Teal=Color3.fromRGB(50,220,190),
}

-- UI factory helpers (these are functions, not locals for each widget)
local function corner(p,r) Instance.new("UICorner",p).CornerRadius=UDim.new(0,r or 8) end
local function lbl(p,props)
    local l=Instance.new("TextLabel",p)
    l.BackgroundTransparency=1
    for k,v in pairs(props) do l[k]=v end
    return l
end
local function btn(p,props)
    local b=Instance.new("TextButton",p)
    b.BorderSizePixel=0
    for k,v in pairs(props) do b[k]=v end
    return b
end
local function box(p,props)
    local b=Instance.new("TextBox",p)
    b.BorderSizePixel=0; b.ClearTextOnFocus=false
    for k,v in pairs(props) do b[k]=v end
    return b
end
local function frame(p,props)
    local f=Instance.new("Frame",p)
    f.BorderSizePixel=0
    for k,v in pairs(props) do f[k]=v end
    return f
end
local function scroll(p,props)
    local s=Instance.new("ScrollingFrame",p)
    s.BorderSizePixel=0; s.ScrollBarThickness=4; s.ScrollBarImageColor3=C.AccentDim
    s.AutomaticCanvasSize=Enum.AutomaticSize.Y; s.CanvasSize=UDim2.new(0,0,0,0)
    for k,v in pairs(props) do s[k]=v end
    return s
end
local function listLayout(p,props)
    local l=Instance.new("UIListLayout",p)
    l.SortOrder=Enum.SortOrder.LayoutOrder
    if props then for k,v in pairs(props) do l[k]=v end end
    return l
end
local function hover(b,def,hov)
    local ti=TweenInfo.new(0.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
    track(b.MouseEnter:Connect(function() Svc.Tween:Create(b,ti,{BackgroundColor3=hov}):Play() end))
    track(b.MouseLeave:Connect(function() Svc.Tween:Create(b,ti,{BackgroundColor3=def}):Play() end))
end
local function mkBtn(p,text,xOff,yOff,w,h,col)
    local b=btn(p,{
        Size=UDim2.fromOffset(w or 60,h or 22),
        Position=UDim2.new(0,xOff,0,yOff),
        BackgroundColor3=col or C.AccentDim,
        Text=text, Font=Enum.Font.GothamBold, TextSize=10, TextColor3=C.Text,
    })
    corner(b,5); return b
end

-- MAIN FRAME
local mainFrame=Instance.new("CanvasGroup",gui)
mainFrame.Size=UDim2.fromOffset(480,740)
mainFrame.Position=UDim2.fromScale(0.5,0.5)
mainFrame.AnchorPoint=Vector2.new(0.5,0.5)
mainFrame.BackgroundColor3=C.BG
mainFrame.BorderSizePixel=0
mainFrame.GroupTransparency=1
corner(mainFrame,12)

do -- shadow + stroke
    local sh=Instance.new("ImageLabel",mainFrame)
    sh.BackgroundTransparency=1; sh.Image="rbxassetid://1316045217"
    sh.ImageColor3=Color3.new(0,0,0); sh.ImageTransparency=0.5
    sh.ScaleType=Enum.ScaleType.Slice; sh.SliceCenter=Rect.new(10,10,118,118)
    sh.Position=UDim2.new(0,-12,0,-8); sh.Size=UDim2.new(1,30,1,30); sh.ZIndex=0
    local sk=Instance.new("UIStroke",mainFrame)
    sk.Color=C.Accent; sk.Thickness=1.5; sk.Transparency=0.5
end

local mainScale=Instance.new("UIScale",mainFrame); mainScale.Scale=0.9

-- SPLASH
do
    local splash=frame(mainFrame,{Size=UDim2.fromScale(1,1),BackgroundColor3=C.BG,ZIndex=100})
    corner(splash,12)
    local sg=Instance.new("UIGradient",splash)
    sg.Color=ColorSequence.new{ColorSequenceKeypoint.new(0,C.AccentDim),ColorSequenceKeypoint.new(1,C.BG)}
    sg.Rotation=90
    local sl=lbl(splash,{Size=UDim2.fromScale(1,1),Text="⚡ LumiWare "..VERSION,
        Font=Enum.Font.GothamBlack,TextSize=34,TextColor3=C.Text,ZIndex=101})
    local ss=Instance.new("UIScale",sl); ss.Scale=0.8
    task.spawn(function()
        Svc.Tween:Create(mainFrame,TweenInfo.new(0.4,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{GroupTransparency=0}):Play()
        Svc.Tween:Create(ss,TweenInfo.new(1.2,Enum.EasingStyle.Exponential,Enum.EasingDirection.Out),{Scale=1.05}):Play()
        task.wait(1.5)
        Svc.Tween:Create(splash,TweenInfo.new(0.6,Enum.EasingStyle.Sine),{BackgroundTransparency=1}):Play()
        Svc.Tween:Create(sl,TweenInfo.new(0.4),{TextTransparency=1}):Play()
        Svc.Tween:Create(mainScale,TweenInfo.new(0.6,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
        task.wait(0.6); splash:Destroy()
    end)
end

-- TOPBAR
local topbar=frame(mainFrame,{Size=UDim2.new(1,0,0,36),BackgroundColor3=C.Top})
corner(topbar,10)
frame(topbar,{Size=UDim2.new(1,0,0,10),Position=UDim2.new(0,0,1,-10),BackgroundColor3=C.Top})
lbl(topbar,{Size=UDim2.new(1,-80,1,0),Position=UDim2.new(0,12,0,0),
    Text="⚡ LumiWare "..VERSION,Font=Enum.Font.GothamBold,TextSize=15,
    TextColor3=C.Accent,TextXAlignment=Enum.TextXAlignment.Left})

local minBtn=btn(topbar,{Size=UDim2.fromOffset(28,28),Position=UDim2.new(1,-66,0,4),
    BackgroundColor3=C.PanelAlt,Text="–",Font=Enum.Font.GothamBold,TextSize=18,TextColor3=C.Text})
corner(minBtn,6); hover(minBtn,C.PanelAlt,C.AccentDim)

local closeBtn=btn(topbar,{Size=UDim2.fromOffset(28,28),Position=UDim2.new(1,-34,0,4),
    BackgroundColor3=C.PanelAlt,Text="×",Font=Enum.Font.GothamBold,TextSize=18,TextColor3=C.Text})
corner(closeBtn,6); hover(closeBtn,C.PanelAlt,C.Red)
closeBtn.MouseButton1Click:Connect(function()
    webhookSession(State.encounterCount,fmtTime(tick()-State.huntStart),State.raresFound)
    gui:Destroy()
end)

-- Drag
do
    local dragging,dragInput,dragStart,startPos
    track(topbar.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true; dragStart=input.Position; startPos=mainFrame.Position
            track(input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end))
        end
    end))
    track(topbar.InputChanged:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then dragInput=input end
    end))
    track(Svc.UIS.InputChanged:Connect(function(input)
        if input==dragInput and dragging then
            local d=input.Position-dragStart
            mainFrame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
        end
    end))
end

-- TAB BAR
local tabBar=frame(mainFrame,{Size=UDim2.new(1,-16,0,30),Position=UDim2.new(0,8,0,44),BackgroundTransparency=1})
local tabLayout2=Instance.new("UIListLayout",tabBar)
tabLayout2.FillDirection=Enum.FillDirection.Horizontal
tabLayout2.VerticalAlignment=Enum.VerticalAlignment.Center
tabLayout2.Padding=UDim.new(0,4)

local function mkTabBtn(text)
    local b=btn(tabBar,{Size=UDim2.new(0.25,-3,1,0),BackgroundColor3=C.PanelAlt,
        Text=text,Font=Enum.Font.GothamBold,TextSize=10,TextColor3=C.Dim})
    corner(b,6); return b
end
local Tabs={
    huntBtn=mkTabBtn("🗡️ HUNT"),
    mastBtn=mkTabBtn("📖 MASTERY"),
    healBtn=mkTabBtn("💊 HEAL"),
    cfgBtn =mkTabBtn("⚙️ CONFIG"),
}

local contentWrap=frame(mainFrame,{Size=UDim2.new(1,-16,1,-82),Position=UDim2.new(0,8,0,78),BackgroundTransparency=1})

-- forward-declare UI elements needed across sections
local UI={}  -- stores all cross-referenced UI elements

--==================================================
-- MASTERY FRAME
--==================================================
local mastFrame=frame(contentWrap,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=false})
do
    local msearch=box(mastFrame,{Size=UDim2.new(1,0,0,36),BackgroundColor3=C.Panel,
        PlaceholderText="🔍 Search Loomian...",Font=Enum.Font.GothamBold,TextSize=13,
        TextColor3=C.Text,PlaceholderColor3=C.Dim})
    corner(msearch,6); Instance.new("UIPadding",msearch).PaddingLeft=UDim.new(0,12)

    UI.sessionLbl=lbl(mastFrame,{Size=UDim2.new(1,0,0,22),Position=UDim2.new(0,0,0,44),
        Text="Session: 0 KOs | 0.0k Damage",Font=Enum.Font.GothamBold,TextSize=11,TextColor3=C.Dim,
        TextXAlignment=Enum.TextXAlignment.Left})

    local mscroll=scroll(mastFrame,{Size=UDim2.new(1,0,1,-74),Position=UDim2.new(0,0,0,74),
        BackgroundTransparency=1,ScrollBarImageColor3=C.AccentDim})
    listLayout(mscroll,{Padding=UDim.new(0,8)})

    local function renderFamily(data)
        local card=frame(mscroll,{Size=UDim2.new(1,-8,0,110),BackgroundColor3=C.Panel})
        corner(card,6)
        lbl(card,{Size=UDim2.new(1,-16,0,24),Position=UDim2.new(0,8,0,4),
            Text=data.f:gsub("/","→"),Font=Enum.Font.GothamBold,TextSize=13,
            TextColor3=C.Accent,TextXAlignment=Enum.TextXAlignment.Left})
        for i,t in ipairs(data.t) do
            local typ,amt,rwd=t[1],t[2],t[3]
            local row=frame(card,{Size=UDim2.new(1,-16,0,18),Position=UDim2.new(0,8,0,26+(i-1)*20),BackgroundTransparency=1})
            lbl(row,{Size=UDim2.fromOffset(20,18),Text="☐",Font=Enum.Font.GothamBold,TextSize=14,TextColor3=C.Dim})
            local tn=TASK_NAMES[typ] or typ
            if typ=="E" then tn="Earn "..amt.." EXP"
            elseif typ=="D" and amt>0 then tn="Discover "..amt.." stages"
            elseif typ=="R" then tn="Rally "..amt.." times"
            elseif typ=="DD" then tn="Deal "..amt.." Damage"
            elseif typ=="C" then tn="Capture "..amt..(amt==1 and " time" or " times")
            elseif typ=="DC" then tn="Deal "..amt.." Critical Hits"
            elseif typ=="LU" then tn="Level up "..amt.." times"
            elseif typ=="K" then tn="KO "..amt.." Loomians" end
            lbl(row,{Size=UDim2.new(1,-60,1,0),Position=UDim2.fromOffset(24,0),
                Text=tn,Font=Enum.Font.Gotham,TextSize=11,TextColor3=C.Text,TextXAlignment=Enum.TextXAlignment.Left})
            lbl(row,{Size=UDim2.fromOffset(40,18),Position=UDim2.new(1,-40,0,0),
                Text=rwd.." MP",Font=Enum.Font.GothamBold,TextSize=10,TextColor3=C.Gold,
                TextXAlignment=Enum.TextXAlignment.Right})
        end
        return card
    end

    local function populate(query)
        for _,v in ipairs(mscroll:GetChildren()) do if v:IsA("Frame") then v:Destroy() end end
        local res=searchMastery(query)
        local n=0
        for i=1,math.min(#res,50) do renderFamily(res[i]).Parent=mscroll; n=n+1 end
        mscroll.CanvasSize=UDim2.new(0,0,0,n*118)
    end
    msearch:GetPropertyChangedSignal("Text"):Connect(function() populate(msearch.Text) end)
    populate("")
end

--==================================================
-- CONFIG FRAME
--==================================================
local cfgFrame2=scroll(contentWrap,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=false,ScrollBarImageColor3=C.AccentDim})
listLayout(cfgFrame2,{Padding=UDim.new(0,8)})

-- helper to make a section card
local function cfgSection(title,h,titleColor)
    local sec=frame(cfgFrame2,{Size=UDim2.new(1,-8,0,h),BackgroundColor3=C.Panel})
    corner(sec,8)
    lbl(sec,{Size=UDim2.new(1,-16,0,26),Position=UDim2.new(0,8,0,2),
        Text=title,Font=Enum.Font.GothamBold,TextSize=12,TextColor3=titleColor or C.Accent,
        TextXAlignment=Enum.TextXAlignment.Left})
    return sec
end
local function cfgRowVal(parent,yOff,labelText,valText,valColor)
    local f=frame(parent,{Size=UDim2.new(1,-16,0,20),Position=UDim2.new(0,8,0,yOff),BackgroundTransparency=1})
    lbl(f,{Size=UDim2.new(0.6,0,1,0),Text=labelText,Font=Enum.Font.Gotham,TextSize=11,TextColor3=C.Dim,TextXAlignment=Enum.TextXAlignment.Left})
    local v=lbl(f,{Size=UDim2.new(0.4,0,1,0),Position=UDim2.new(0.6,0,0,0),Text=tostring(valText),
        Font=Enum.Font.GothamBold,TextSize=11,TextColor3=valColor or C.Text,TextXAlignment=Enum.TextXAlignment.Right})
    return v
end

-- Summary section
local cfgSum=cfgSection("📋 CURRENT CONFIG",170,C.Accent)
UI.cfgAutoModeVal    = cfgRowVal(cfgSum,30,"Wild Auto Mode:",cfg.autoMode,C.Green)
UI.cfgTrainerModeVal = cfgRowVal(cfgSum,54,"Trainer Auto Mode:",cfg.trainerAutoMode,C.Trainer)
UI.cfgWildSlotVal    = cfgRowVal(cfgSum,78,"Wild Move Slot:",cfg.autoMoveSlot,C.Text)
UI.cfgTrainerSlotVal = cfgRowVal(cfgSum,102,"Trainer Move Slot:",cfg.trainerAutoMoveSlot,C.Text)
UI.cfgHealVal        = cfgRowVal(cfgSum,126,"Auto-Heal:",cfg.autoHealEnabled and "ON" or "OFF",C.Teal)
UI.cfgThreshVal      = cfgRowVal(cfgSum,150,"Heal Threshold:",cfg.autoHealThreshold.."%",C.Teal)

-- Webhook section
local cfgWh=cfgSection("📡 WEBHOOK",96,C.Cyan)
local cfgWhInput=box(cfgWh,{Size=UDim2.new(1,-72,0,24),Position=UDim2.new(0,8,0,30),
    BackgroundColor3=C.PanelAlt,Text=cfg.webhookUrl or "",PlaceholderText="Discord webhook URL...",
    Font=Enum.Font.Gotham,TextSize=10,TextColor3=C.Text,TextXAlignment=Enum.TextXAlignment.Left})
corner(cfgWhInput,5); Instance.new("UIPadding",cfgWhInput).PaddingLeft=UDim.new(0,6)
local cfgWhSave=mkBtn(cfgWh,"SAVE",0,30,60,24,C.Cyan)
cfgWhSave.Position=UDim2.new(1,-68,0,30); cfgWhSave.TextColor3=C.BG
local cfgPingInput=box(cfgWh,{Size=UDim2.new(1,-16,0,20),Position=UDim2.new(0,8,0,60),
    BackgroundColor3=C.PanelAlt,PlaceholderText="Ping IDs e.g. <@12345> or @everyone",
    Text=cfg.pingIds or "",Font=Enum.Font.Gotham,TextSize=9,TextColor3=C.Text,TextXAlignment=Enum.TextXAlignment.Left})
corner(cfgPingInput,5); Instance.new("UIPadding",cfgPingInput).PaddingLeft=UDim.new(0,6)

-- Custom rares
local cfgRareSec=cfgSection("⭐ CUSTOM RARES",80,C.Gold)
local cfgRareInput=box(cfgRareSec,{Size=UDim2.new(1,-100,0,24),Position=UDim2.new(0,8,0,30),
    BackgroundColor3=C.PanelAlt,PlaceholderText="e.g. Twilat, Cathorn...",
    Font=Enum.Font.Gotham,TextSize=11,TextColor3=C.Text,TextXAlignment=Enum.TextXAlignment.Left})
corner(cfgRareInput,5); Instance.new("UIPadding",cfgRareInput).PaddingLeft=UDim.new(0,6)
local cfgRareAdd  = mkBtn(cfgRareSec,"+ ADD",  0,30,42,24,C.Green); cfgRareAdd.Position=UDim2.new(1,-90,0,30); cfgRareAdd.TextColor3=C.BG
local cfgRareClear= mkBtn(cfgRareSec,"CLEAR",  0,30,42,24,C.Red  ); cfgRareClear.Position=UDim2.new(1,-44,0,30)
UI.cfgRareCountLbl=lbl(cfgRareSec,{Size=UDim2.new(1,-16,0,18),Position=UDim2.new(0,8,0,58),
    Font=Enum.Font.Gotham,TextSize=10,TextColor3=C.Dim,TextXAlignment=Enum.TextXAlignment.Left})

-- Save/Reset
local cfgSaveSec=cfgSection("💾 SAVE / RESET",76,C.Green)
local cfgSaveBtn =mkBtn(cfgSaveSec,"💾 SAVE ALL",8,30,130,26,C.Green); cfgSaveBtn.TextColor3=C.BG; cfgSaveBtn.TextSize=11
local cfgResetBtn=mkBtn(cfgSaveSec,"🔄 RESET",0,30,130,26,C.Red); cfgResetBtn.Position=UDim2.new(1,-138,0,30); cfgResetBtn.TextSize=11
UI.cfgStatusLbl=lbl(cfgSaveSec,{Size=UDim2.new(1,-16,0,18),Position=UDim2.new(0,8,0,58),
    Text="Config last saved: never",Font=Enum.Font.Gotham,TextSize=10,TextColor3=C.Dim,TextXAlignment=Enum.TextXAlignment.Left})

-- Battle Filter
local cfgFiltSec=cfgSection("🎯 BATTLE FILTER",76,C.Pink)
UI.wildFilterBtn   =mkBtn(cfgFiltSec,"Wild: ON",8,30,100,24,Auto.wildOn and C.Wild or C.PanelAlt)
UI.trainerFilterBtn=mkBtn(cfgFiltSec,"Trainer: ON",116,30,100,24,Auto.trainerOn and C.Trainer or C.PanelAlt)
lbl(cfgFiltSec,{Size=UDim2.new(1,-16,0,18),Position=UDim2.new(0,8,0,56),
    Text="Toggle which battle types trigger automation",Font=Enum.Font.Gotham,TextSize=10,TextColor3=C.Dim,TextXAlignment=Enum.TextXAlignment.Left})

--==================================================
-- HEAL FRAME
--==================================================
local healFrame2=scroll(contentWrap,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=false,ScrollBarImageColor3=C.Teal})
listLayout(healFrame2,{Padding=UDim.new(0,8)})

local function healSection(title,h)
    local s=frame(healFrame2,{Size=UDim2.new(1,-8,0,h),BackgroundColor3=C.Panel}); corner(s,8)
    lbl(s,{Size=UDim2.new(1,-16,0,26),Position=UDim2.new(0,8,0,2),Text=title,
        Font=Enum.Font.GothamBold,TextSize=12,TextColor3=C.Teal,TextXAlignment=Enum.TextXAlignment.Left})
    return s
end

-- Toggle
local hTogSec=healSection("💊 AUTO-HEAL",90)
UI.healOnBtn  = mkBtn(hTogSec,"ENABLE",  8,30,80,24,Heal.enabled and C.Teal or C.AccentDim)
UI.healOffBtn = mkBtn(hTogSec,"DISABLE",96,30,80,24,not Heal.enabled and C.Red or C.AccentDim)
lbl(hTogSec,{Size=UDim2.fromOffset(110,22),Position=UDim2.new(0,8,0,60),
    Text="Heal when HP <",Font=Enum.Font.Gotham,TextSize=11,TextColor3=C.Dim,TextXAlignment=Enum.TextXAlignment.Left})
UI.healThreshInput=box(hTogSec,{Size=UDim2.fromOffset(50,22),Position=UDim2.new(0,118,0,60),
    BackgroundColor3=C.PanelAlt,Text=tostring(Heal.threshold),Font=Enum.Font.GothamBold,
    TextSize=12,TextColor3=C.Teal,TextXAlignment=Enum.TextXAlignment.Center})
corner(UI.healThreshInput,5)
lbl(hTogSec,{Size=UDim2.fromOffset(16,22),Position=UDim2.new(0,172,0,60),
    Text="%",Font=Enum.Font.GothamBold,TextSize=12,TextColor3=C.Teal})

-- Scanner
local hScanSec=healSection("🔍 HEAL SCANNER",118)
UI.healScanRemBtn = mkBtn(hScanSec,"🔍 SCAN REMOTES",  8,30,140,24,C.Teal); UI.healScanRemBtn.TextColor3=C.BG
UI.healScanBtnBtn = mkBtn(hScanSec,"🔍 SCAN BUTTONS",156,30,140,24,C.Cyan); UI.healScanBtnBtn.TextColor3=C.BG
UI.healScanStatus = lbl(hScanSec,{Size=UDim2.new(1,-16,0,18),Position=UDim2.new(0,8,0,60),
    Text="▸ Press Scan while near a heal center",Font=Enum.Font.Gotham,TextSize=10,TextColor3=C.Dim,
    TextXAlignment=Enum.TextXAlignment.Left})
UI.healRemoteScroll=scroll(hScanSec,{Size=UDim2.new(1,-16,0,38),Position=UDim2.new(0,8,0,78),
    BackgroundColor3=C.PanelAlt,ScrollBarThickness=3,ScrollBarImageColor3=C.Teal,
    AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(0,0,0,0)})
corner(UI.healRemoteScroll,5); listLayout(UI.healRemoteScroll,{Padding=UDim.new(0,2)})

-- Selected
local hSelSec=healSection("✅ SELECTED HEAL SOURCE",98)
UI.healSelName=lbl(hSelSec,{Size=UDim2.new(1,-16,0,20),Position=UDim2.new(0,8,0,30),
    Text=Heal.remoteName~="" and "Remote: "..Heal.remoteName or "None selected",
    Font=Enum.Font.GothamBold,TextSize=12,
    TextColor3=Heal.remoteName~="" and C.Teal or C.Dim,TextXAlignment=Enum.TextXAlignment.Left})
UI.healSelPath=lbl(hSelSec,{Size=UDim2.new(1,-16,0,16),Position=UDim2.new(0,8,0,52),
    Text=Heal.remotePath~="" and Heal.remotePath or "Path: —",Font=Enum.Font.Code,TextSize=9,
    TextColor3=C.Dim,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd})
UI.healTestBtn =mkBtn(hSelSec,"🧪 TEST HEAL NOW",8,72,140,22,C.Teal); UI.healTestBtn.TextColor3=C.BG
UI.healClearBtn=mkBtn(hSelSec,"❌ CLEAR",0,72,70,22,C.Red); UI.healClearBtn.Position=UDim2.new(1,-78,0,72)

-- Heal log
local hLogSec=healSection("📋 HEAL LOG",100)
UI.healLogScroll=scroll(hLogSec,{Size=UDim2.new(1,-16,1,-30),Position=UDim2.new(0,8,0,28),
    BackgroundTransparency=1,ScrollBarThickness=3,ScrollBarImageColor3=C.Teal})
listLayout(UI.healLogScroll,{Padding=UDim.new(0,2)})
local healLogOrd=0
local function addHealLog(text,color)
    healLogOrd=healLogOrd+1
    local it=lbl(UI.healLogScroll,{Size=UDim2.new(1,0,0,16),
        Text="["..os.date("%X").."] "..text,Font=Enum.Font.Code,TextSize=10,
        TextColor3=color or C.Teal,TextXAlignment=Enum.TextXAlignment.Left,
        TextTruncate=Enum.TextTruncate.AtEnd})
    it.LayoutOrder=healLogOrd
end

--==================================================
-- HUNT FRAME
--==================================================
local huntFrame=frame(contentWrap,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=true})

-- Tab switcher
local function switchTab(active)
    local map={hunt=huntFrame,mastery=mastFrame,heal=healFrame2,cfg=cfgFrame2}
    local bmap={hunt=Tabs.huntBtn,mastery=Tabs.mastBtn,heal=Tabs.healBtn,cfg=Tabs.cfgBtn}
    for name,fr in pairs(map) do
        fr.Visible=(name==active)
        Svc.Tween:Create(bmap[name],TweenInfo.new(0.2),{
            BackgroundColor3=(name==active) and C.Accent or C.PanelAlt,
            TextColor3=(name==active) and C.Text or C.Dim}):Play()
    end
end
Tabs.huntBtn.MouseButton1Click:Connect(function() switchTab("hunt") end)
Tabs.mastBtn.MouseButton1Click:Connect(function() switchTab("mastery") end)
Tabs.healBtn.MouseButton1Click:Connect(function() switchTab("heal") end)
Tabs.cfgBtn.MouseButton1Click:Connect(function()  switchTab("cfg") end)
switchTab("hunt")

-- STATS BAR
do
    local sb=frame(huntFrame,{Size=UDim2.new(1,0,0,50),BackgroundColor3=C.Panel}); corner(sb,8)
    local sl2=Instance.new("UIListLayout",sb)
    sl2.FillDirection=Enum.FillDirection.Horizontal
    sl2.HorizontalAlignment=Enum.HorizontalAlignment.Center
    sl2.VerticalAlignment=Enum.VerticalAlignment.Center
    sl2.Padding=UDim.new(0,4)
    local function statCell(lbText,valText,col)
        local cell=frame(sb,{Size=UDim2.new(0.2,-4,1,-8),BackgroundColor3=C.PanelAlt}); corner(cell,6)
        lbl(cell,{Size=UDim2.new(1,0,0.45,0),Position=UDim2.new(0,0,0,2),Text=lbText,
            Font=Enum.Font.Gotham,TextSize=9,TextColor3=C.Dim})
        return lbl(cell,{Size=UDim2.new(1,0,0.55,0),Position=UDim2.new(0,0,0.4,0),
            Name="Value",Text=valText,Font=Enum.Font.GothamBold,TextSize=13,TextColor3=col or C.Text})
    end
    UI.encVal   = statCell("ENCOUNTERS","0",C.Green)
    UI.epmVal   = statCell("ENC/MIN","0.0",C.Text)
    UI.timerVal = statCell("HUNT TIME","0m 00s",C.Text)
    UI.typeVal  = statCell("BATTLE","N/A",C.Dim)
    UI.stateVal = statCell("STATUS","Idle",C.Dim)
end

-- ENCOUNTER PANEL
do
    local ep=frame(huntFrame,{Size=UDim2.new(1,0,0,90),Position=UDim2.new(0,0,0,56),BackgroundColor3=C.Panel}); corner(ep,8)
    lbl(ep,{Size=UDim2.new(1,-16,0,22),Position=UDim2.new(0,8,0,4),Text="CURRENT ENCOUNTER",
        Font=Enum.Font.GothamBold,TextSize=11,TextColor3=C.Accent,TextXAlignment=Enum.TextXAlignment.Left})
    UI.enemyLbl=lbl(ep,{Size=UDim2.new(1,-16,0,22),Position=UDim2.new(0,8,0,26),
        Text="Enemy: Waiting for battle...",Font=Enum.Font.GothamMedium,TextSize=15,
        TextColor3=C.Text,TextXAlignment=Enum.TextXAlignment.Left,RichText=true})
    UI.enemyStatsLbl=lbl(ep,{Size=UDim2.new(1,-16,0,18),Position=UDim2.new(0,8,0,48),
        Font=Enum.Font.Gotham,TextSize=12,TextColor3=C.Dim,TextXAlignment=Enum.TextXAlignment.Left})
    UI.playerLbl=lbl(ep,{Size=UDim2.new(1,-16,0,18),Position=UDim2.new(0,8,0,68),
        Text="Your Loomian: —",Font=Enum.Font.Gotham,TextSize=12,TextColor3=C.Dim,TextXAlignment=Enum.TextXAlignment.Left})
end

-- RARE LOG
do
    local rp=frame(huntFrame,{Size=UDim2.new(1,0,0,80),Position=UDim2.new(0,0,0,152),BackgroundColor3=C.Panel}); corner(rp,8)
    lbl(rp,{Size=UDim2.new(1,-16,0,22),Position=UDim2.new(0,8,0,4),Text="⭐ RARE FINDER LOG",
        Font=Enum.Font.GothamBold,TextSize=11,TextColor3=C.Gold,TextXAlignment=Enum.TextXAlignment.Left})
    UI.rareScroll=scroll(rp,{Size=UDim2.new(1,-16,1,-30),Position=UDim2.new(0,8,0,28),
        BackgroundTransparency=1,ScrollBarThickness=3,ScrollBarImageColor3=C.Accent,
        AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(0,0,0,0)})
    listLayout(UI.rareScroll,{Padding=UDim.new(0,3)})
end
local rareLogOrd=0
local function addRareLog(name,extra)
    rareLogOrd=rareLogOrd+1
    local it=lbl(UI.rareScroll,{Size=UDim2.new(1,0,0,20),
        Text="⭐ ["..os.date("%X").."] "..name..(extra and " — "..extra or ""),
        Font=Enum.Font.GothamMedium,TextSize=12,TextColor3=C.Gold,TextXAlignment=Enum.TextXAlignment.Left})
    it.LayoutOrder=rareLogOrd
end

-- WEBHOOK (compact in hunt tab)
do
    local wp=frame(huntFrame,{Size=UDim2.new(1,0,0,54),Position=UDim2.new(0,0,0,238),BackgroundColor3=C.Panel}); corner(wp,8)
    lbl(wp,{Size=UDim2.new(1,-16,0,20),Position=UDim2.new(0,8,0,4),Text="📡 WEBHOOK",
        Font=Enum.Font.GothamBold,TextSize=11,TextColor3=C.Cyan,TextXAlignment=Enum.TextXAlignment.Left})
    UI.whInput=box(wp,{Size=UDim2.new(1,-58,0,24),Position=UDim2.new(0,8,0,26),
        BackgroundColor3=C.PanelAlt,PlaceholderText="Paste webhook URL...",
        PlaceholderColor3=C.Dim,Text=cfg.webhookUrl or "",Font=Enum.Font.Gotham,
        TextSize=11,TextColor3=C.Text,TextXAlignment=Enum.TextXAlignment.Left})
    corner(UI.whInput,5); Instance.new("UIPadding",UI.whInput).PaddingLeft=UDim.new(0,6)
    local whSaveBtn=btn(wp,{Size=UDim2.fromOffset(42,24),Position=UDim2.new(1,-50,0,26),
        BackgroundColor3=C.Cyan,Text="SET",Font=Enum.Font.GothamBold,TextSize=11,TextColor3=C.BG}); corner(whSaveBtn,5)
    whSaveBtn.MouseButton1Click:Connect(function()
        Webhook.url=UI.whInput.Text; cfg.webhookUrl=Webhook.url
        if Webhook.url~="" then
            notify("LumiWare","Webhook saved!",3)
            sendWebhook({title="✅ Webhook Connected!",color=5763719,
                fields={{name="Player",value=PLAYER_NAME,inline=true}},footer={text="LumiWare "..VERSION}})
        else notify("LumiWare","Webhook cleared.",3) end
    end)
end

-- AUTOMATION PANEL
local wildSlotBtns={}
local trSlotBtns={}
local walkBtn2, autoStatusLbl2, scanBtn2

do
    local ap=frame(huntFrame,{Size=UDim2.new(1,0,0,178),Position=UDim2.new(0,0,0,298),BackgroundColor3=C.Panel}); corner(ap,8)
    lbl(ap,{Size=UDim2.new(1,-16,0,20),Position=UDim2.new(0,8,0,4),Text="🤖 AUTOMATION",
        Font=Enum.Font.GothamBold,TextSize=11,TextColor3=C.Pink,TextXAlignment=Enum.TextXAlignment.Left})

    -- Wild
    lbl(ap,{Size=UDim2.new(0,60,0,16),Position=UDim2.new(0,8,0,26),Text="🌿 WILD:",
        Font=Enum.Font.GothamBold,TextSize=10,TextColor3=C.Wild,TextXAlignment=Enum.TextXAlignment.Left})
    UI.wOff =mkBtn(ap,"OFF",  8, 44,44,22,C.Red);   hover(UI.wOff, C.AccentDim,C.Red)
    UI.wMove=mkBtn(ap,"MOVE",58, 44,52,22,C.AccentDim); hover(UI.wMove,C.AccentDim,C.Green)
    UI.wRun =mkBtn(ap,"RUN", 116,44,44,22,C.AccentDim); hover(UI.wRun, C.AccentDim,C.Cyan)
    lbl(ap,{Size=UDim2.fromOffset(30,22),Position=UDim2.new(0,165,0,44),Text="Slot:",
        Font=Enum.Font.GothamBold,TextSize=10,TextColor3=C.Dim})
    for s=1,4 do
        wildSlotBtns[s]=mkBtn(ap,tostring(s),197+(s-1)*26,44,22,22,C.AccentDim); hover(wildSlotBtns[s],C.PanelAlt,C.AccentDim)
    end

    -- Trainer
    lbl(ap,{Size=UDim2.new(0,70,0,16),Position=UDim2.new(0,8,0,72),Text="🎖️ TRAINER:",
        Font=Enum.Font.GothamBold,TextSize=10,TextColor3=C.Trainer,TextXAlignment=Enum.TextXAlignment.Left})
    UI.tOff =mkBtn(ap,"OFF",  8, 90,44,22,C.Red);   hover(UI.tOff, C.AccentDim,C.Red)
    UI.tMove=mkBtn(ap,"MOVE",58, 90,52,22,C.AccentDim); hover(UI.tMove,C.AccentDim,C.Trainer)
    UI.tRun =mkBtn(ap,"RUN", 116,90,44,22,C.AccentDim); hover(UI.tRun, C.AccentDim,C.Cyan)
    lbl(ap,{Size=UDim2.fromOffset(30,22),Position=UDim2.new(0,165,0,90),Text="Slot:",
        Font=Enum.Font.GothamBold,TextSize=10,TextColor3=C.Dim})
    for s=1,4 do
        trSlotBtns[s]=mkBtn(ap,tostring(s),197+(s-1)*26,90,22,22,C.AccentDim); hover(trSlotBtns[s],C.PanelAlt,C.AccentDim)
    end

    walkBtn2 = mkBtn(ap,"🚶 AUTO-WALK",8,118,138,22,C.PanelAlt); hover(walkBtn2,C.AccentDim,C.Accent)
    scanBtn2 = mkBtn(ap,"🔍 SCAN UI",153,118,80,22,C.PanelAlt); hover(scanBtn2,C.PanelAlt,C.Accent)

    autoStatusLbl2=lbl(ap,{Size=UDim2.new(1,-16,0,22),Position=UDim2.new(0,8,0,144),
        Font=Enum.Font.Gotham,TextSize=10,TextColor3=C.Dim,TextXAlignment=Enum.TextXAlignment.Left})
end

-- BATTLE LOG
local addBattleLog
do
    local bp=frame(huntFrame,{Size=UDim2.new(1,0,0,100),Position=UDim2.new(0,0,0,482),BackgroundColor3=C.Panel}); corner(bp,8)
    lbl(bp,{Size=UDim2.new(1,-16,0,20),Position=UDim2.new(0,8,0,4),Text="⚔️ BATTLE LOG",
        Font=Enum.Font.GothamBold,TextSize=11,TextColor3=C.Green,TextXAlignment=Enum.TextXAlignment.Left})
    local bscroll=scroll(bp,{Size=UDim2.new(1,-16,1,-28),Position=UDim2.new(0,8,0,24),
        BackgroundTransparency=1,ScrollBarThickness=3,ScrollBarImageColor3=C.Green,
        AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(0,0,0,0)})
    listLayout(bscroll,{Padding=UDim.new(0,2)})
    local bOrd,bCnt=0,0
    addBattleLog=function(text,color)
        bOrd=bOrd+1; bCnt=bCnt+1
        local it=lbl(bscroll,{Size=UDim2.new(1,0,0,16),
            Text="["..os.date("%X").."] "..text,Font=Enum.Font.Code,TextSize=10,
            TextColor3=color or C.Dim,TextXAlignment=Enum.TextXAlignment.Left,
            TextTruncate=Enum.TextTruncate.AtEnd})
        it.LayoutOrder=bOrd
        if bCnt>40 then
            for _,ch in ipairs(bscroll:GetChildren()) do
                if ch:IsA("TextLabel") then ch:Destroy(); bCnt=bCnt-1; break end
            end
        end
    end
end

-- CONTROLS
do
    local cp=frame(huntFrame,{Size=UDim2.new(1,0,0,34),Position=UDim2.new(0,0,0,588),BackgroundColor3=C.Panel}); corner(cp,8)
    local cl2=Instance.new("UIListLayout",cp)
    cl2.FillDirection=Enum.FillDirection.Horizontal
    cl2.HorizontalAlignment=Enum.HorizontalAlignment.Center
    cl2.VerticalAlignment=Enum.VerticalAlignment.Center
    cl2.Padding=UDim.new(0,6)
    local function ctrlBtn(text)
        local b=btn(cp,{Size=UDim2.new(0.33,-6,0,24),BackgroundColor3=C.AccentDim,
            Text=text,Font=Enum.Font.GothamBold,TextSize=10,TextColor3=C.Text}); corner(b,5); return b
    end
    local resetBtn=ctrlBtn("🔄 RESET")
    local discBtn =ctrlBtn("🔍 DISCOVERY")
    local verbBtn =ctrlBtn("📝 VERBOSE")
    track(resetBtn.MouseButton1Click:Connect(function()
        State.encounterCount=0; State.huntStart=tick(); State.raresFound=0
        State.encounterHistory={}; State.currentEnemy=nil; resetBattle()
        UI.encVal.Text="0"; UI.epmVal.Text="0.0"; UI.timerVal.Text="0m 00s"
        UI.typeVal.Text="N/A"; UI.typeVal.TextColor3=C.Dim
        UI.stateVal.Text="Idle"; UI.stateVal.TextColor3=C.Dim
        UI.enemyLbl.Text="Enemy: Waiting for battle..."
        UI.enemyStatsLbl.Text=""; UI.playerLbl.Text="Your Loomian: —"
        addBattleLog("Session reset",C.Accent)
    end))
    track(discBtn.MouseButton1Click:Connect(function()
        State.discoveryMode=not State.discoveryMode
        discBtn.BackgroundColor3=State.discoveryMode and C.Trainer or C.AccentDim
        discBtn.Text=State.discoveryMode and "🔍 DISC:ON" or "🔍 DISCOVERY"
    end))
    track(verbBtn.MouseButton1Click:Connect(function()
        VERBOSE=not VERBOSE
        verbBtn.BackgroundColor3=VERBOSE and C.Trainer or C.AccentDim
        verbBtn.Text=VERBOSE and "📝 VERB:ON" or "📝 VERBOSE"
    end))
end

-- MINIMIZE
track(minBtn.MouseButton1Click:Connect(function()
    State.isMinimized=not State.isMinimized
    if State.isMinimized then
        Svc.Tween:Create(mainFrame,TweenInfo.new(0.25,Enum.EasingStyle.Quint),{Size=UDim2.fromOffset(480,36)}):Play()
        contentWrap.Visible=false; tabBar.Visible=false; minBtn.Text="+"
    else
        contentWrap.Visible=true; tabBar.Visible=true
        Svc.Tween:Create(mainFrame,TweenInfo.new(0.25,Enum.EasingStyle.Quint),{Size=UDim2.fromOffset(480,740)}):Play()
        minBtn.Text="–"
    end
end))

--==================================================
-- updateAutoUI
--==================================================
local function updateAutoUI()
    UI.wOff.BackgroundColor3  = Auto.wildMode=="off"  and C.Red    or C.AccentDim
    UI.wMove.BackgroundColor3 = Auto.wildMode=="move" and C.Green  or C.AccentDim
    UI.wRun.BackgroundColor3  = Auto.wildMode=="run"  and C.Cyan   or C.AccentDim
    for s=1,4 do
        wildSlotBtns[s].BackgroundColor3=(Auto.wildSlot==s and Auto.wildMode=="move") and C.Accent or C.AccentDim
    end
    UI.tOff.BackgroundColor3  = Auto.trMode=="off"  and C.Red     or C.AccentDim
    UI.tMove.BackgroundColor3 = Auto.trMode=="move" and C.Trainer or C.AccentDim
    UI.tRun.BackgroundColor3  = Auto.trMode=="run"  and C.Cyan    or C.AccentDim
    for s=1,4 do
        trSlotBtns[s].BackgroundColor3=(Auto.trSlot==s and Auto.trMode=="move") and C.Accent or C.AccentDim
    end
    walkBtn2.BackgroundColor3=Auto.walkEnabled and C.Green or C.PanelAlt
    walkBtn2.Text=Auto.walkEnabled and "🚶 WALKING" or "🚶 AUTO-WALK"

    local ws=Auto.wildMode=="off" and "Wild:OFF" or ("Wild:"..Auto.wildMode:upper().."/"..Auto.wildSlot)
    local ts=Auto.trMode=="off"   and "Trainer:OFF" or ("Trainer:"..Auto.trMode:upper().."/"..Auto.trSlot)
    autoStatusLbl2.Text=ws.."  |  "..ts..(State.rareFoundPause and "  [⏸ RARE]" or "")

    -- sync config display
    UI.cfgAutoModeVal.Text=Auto.wildMode; UI.cfgAutoModeVal.TextColor3=Auto.wildMode=="off" and C.Red or C.Green
    UI.cfgTrainerModeVal.Text=Auto.trMode; UI.cfgTrainerModeVal.TextColor3=Auto.trMode=="off" and C.Red or C.Trainer
    UI.cfgWildSlotVal.Text=tostring(Auto.wildSlot)
    UI.cfgTrainerSlotVal.Text=tostring(Auto.trSlot)
    UI.wildFilterBtn.BackgroundColor3=Auto.wildOn and C.Wild or C.PanelAlt
    UI.wildFilterBtn.Text=Auto.wildOn and "Wild: ON" or "Wild: OFF"
    UI.trainerFilterBtn.BackgroundColor3=Auto.trainerOn and C.Trainer or C.PanelAlt
    UI.trainerFilterBtn.Text=Auto.trainerOn and "Trainer: ON" or "Trainer: OFF"
end

-- Wire automation buttons
track(UI.wOff.MouseButton1Click:Connect(function()  Auto.wildMode="off";  cfg.autoMode="off";  saveConfig(); State.rareFoundPause=false; updateAutoUI() end))
track(UI.wMove.MouseButton1Click:Connect(function() Auto.wildMode="move"; cfg.autoMode="move"; saveConfig(); updateAutoUI(); notify("LumiWare","Wild MOVE/"..Auto.wildSlot,3) end))
track(UI.wRun.MouseButton1Click:Connect(function()  Auto.wildMode="run";  cfg.autoMode="run";  saveConfig(); updateAutoUI(); notify("LumiWare","Wild RUN",3) end))
for s=1,4 do
    track(wildSlotBtns[s].MouseButton1Click:Connect(function() Auto.wildSlot=s; cfg.autoMoveSlot=s; saveConfig(); updateAutoUI() end))
end
track(UI.tOff.MouseButton1Click:Connect(function()  Auto.trMode="off";  cfg.trainerAutoMode="off";  saveConfig(); updateAutoUI() end))
track(UI.tMove.MouseButton1Click:Connect(function() Auto.trMode="move"; cfg.trainerAutoMode="move"; saveConfig(); updateAutoUI(); notify("LumiWare","Trainer MOVE/"..Auto.trSlot,3) end))
track(UI.tRun.MouseButton1Click:Connect(function()  Auto.trMode="run";  cfg.trainerAutoMode="run";  saveConfig(); updateAutoUI(); notify("LumiWare","Trainer RUN",3) end))
for s=1,4 do
    track(trSlotBtns[s].MouseButton1Click:Connect(function() Auto.trSlot=s; cfg.trainerAutoMoveSlot=s; saveConfig(); updateAutoUI() end))
end
track(UI.wildFilterBtn.MouseButton1Click:Connect(function()
    Auto.wildOn=not Auto.wildOn; cfg.automateWild=Auto.wildOn; updateAutoUI()
end))
track(UI.trainerFilterBtn.MouseButton1Click:Connect(function()
    Auto.trainerOn=not Auto.trainerOn; cfg.automateTrainer=Auto.trainerOn; updateAutoUI()
end))
updateAutoUI()

-- Config tab buttons
local function refreshRareCount()
    UI.cfgRareCountLbl.Text=#customRares.." rares: "..(#customRares>0 and table.concat(customRares,", ") or "(none)")
end
refreshRareCount()

cfgRareAdd.MouseButton1Click:Connect(function()
    local t=cfgRareInput.Text; if t=="" then return end
    for w in t:gmatch("[^,]+") do local tr=w:match("^%s*(.-)%s*$"); if tr and tr~="" then customRares[#customRares+1]=tr end end
    cfg.customRares=customRares; cfgRareInput.Text=""; refreshRareCount(); notify("LumiWare","Added!",3)
end)
cfgRareClear.MouseButton1Click:Connect(function()
    customRares={}; cfg.customRares=customRares; refreshRareCount(); notify("LumiWare","Cleared.",3)
end)
cfgWhSave.MouseButton1Click:Connect(function()
    Webhook.url=cfgWhInput.Text; cfg.webhookUrl=Webhook.url; cfg.pingIds=cfgPingInput.Text; saveConfig()
    notify("LumiWare","Webhook saved!",3)
end)
cfgSaveBtn.MouseButton1Click:Connect(function()
    cfg.autoMode=Auto.wildMode; cfg.autoMoveSlot=Auto.wildSlot
    cfg.trainerAutoMode=Auto.trMode; cfg.trainerAutoMoveSlot=Auto.trSlot
    cfg.autoHealEnabled=Heal.enabled; cfg.autoHealThreshold=Heal.threshold
    cfg.customRares=customRares; cfg.webhookUrl=Webhook.url
    cfg.pingIds=cfgPingInput.Text
    cfg.automateTrainer=Auto.trainerOn; cfg.automateWild=Auto.wildOn
    cfg.healRemoteName=Heal.remoteName; cfg.healRemotePath=Heal.remotePath; cfg.autoHealMethod=Heal.method
    saveConfig()
    UI.cfgStatusLbl.Text="✅ Saved at "..os.date("%X"); UI.cfgStatusLbl.TextColor3=C.Green
    notify("LumiWare","Config saved!",3)
    task.delay(4,function() UI.cfgStatusLbl.TextColor3=C.Dim end)
end)
cfgResetBtn.MouseButton1Click:Connect(function()
    resetCfgDefault()
    Auto.wildMode="off"; Auto.trMode="off"; Auto.wildSlot=1; Auto.trSlot=1
    Heal.enabled=false; Heal.threshold=30; customRares={}; Webhook.url=""
    Auto.wildOn=true; Auto.trainerOn=true
    updateAutoUI(); refreshRareCount()
    UI.cfgHealVal.Text="OFF"; UI.cfgHealVal.TextColor3=C.Dim
    UI.cfgThreshVal.Text="30%"
    UI.cfgStatusLbl.Text="🔄 Reset at "..os.date("%X"); UI.cfgStatusLbl.TextColor3=C.Trainer
    notify("LumiWare","Config reset to defaults.",4)
end)

--==================================================
-- HEAL SYSTEM
--==================================================
local HEAL_KW={"heal","nurse","restore","recovery","clinic","center","loomacenter","inn","rest","fullrestore"}
local HEAL_BTN_KW={"heal","nurse","restore","yes","confirm","rest"}
local function looksHeal(name,path)
    local nl,pl=name:lower(),(path or ""):lower()
    for _,k in ipairs(HEAL_KW) do if nl:find(k) or pl:find(k) then return true end end
    return false
end

local function addHealEntry(name,path,remote,isBtn)
    local entry={name=name,path=path,remote=remote,isButton=isBtn}
    Heal.scanned[#Heal.scanned+1]=entry
    local row=frame(UI.healRemoteScroll,{Size=UDim2.new(1,-4,0,20),BackgroundTransparency=1})
    lbl(row,{Size=UDim2.new(1,-54,1,0),Text=(isBtn and "🔘 " or "📡 ")..name,
        Font=Enum.Font.Code,TextSize=9,TextColor3=isBtn and C.Cyan or C.Teal,
        TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd})
    local selBtn=btn(row,{Size=UDim2.fromOffset(48,16),Position=UDim2.new(1,-50,0,2),
        BackgroundColor3=C.AccentDim,Text="USE",Font=Enum.Font.GothamBold,TextSize=9,TextColor3=C.Text}); corner(selBtn,4)
    track(selBtn.MouseButton1Click:Connect(function()
        Heal.remoteName=name; Heal.remotePath=path; Heal.remote=remote
        Heal.method=isBtn and "button" or "remote"
        cfg.healRemoteName=name; cfg.healRemotePath=path; cfg.autoHealMethod=Heal.method; saveConfig()
        UI.healSelName.Text=(isBtn and "Button: " or "Remote: ")..name; UI.healSelName.TextColor3=C.Teal
        UI.healSelPath.Text=path; selBtn.BackgroundColor3=C.Teal; selBtn.Text="✓ SET"
        addHealLog("✅ Selected: "..name,C.Teal); notify("LumiWare","Heal source set: "..name,4)
        UI.cfgHealVal.Text="Remote set"; UI.cfgHealVal.TextColor3=C.Teal
    end))
end

local function performHeal()
    if not Heal.remote then addHealLog("⚠ No heal source!",C.Red); return false end
    if Heal.method=="button" then
        pcall(function()
            local p,s=Heal.remote.AbsolutePosition,Heal.remote.AbsoluteSize
            local cx,cy=p.X+s.X/2,p.Y+s.Y/2
            Svc.VIM:SendMouseButtonEvent(cx,cy,0,true,game,1); task.wait(0.05)
            Svc.VIM:SendMouseButtonEvent(cx,cy,0,false,game,1)
        end)
        addHealLog("💊 Heal button clicked",C.Teal)
    else
        pcall(function()
            if Heal.remote:IsA("RemoteEvent") then Heal.remote:FireServer()
            else Heal.remote:InvokeServer() end
        end)
        addHealLog("💊 Remote fired: "..Heal.remoteName,C.Teal)
    end
    Heal.lastTime=tick(); return true
end

local function doScan(scanButtons)
    for _,v in ipairs(UI.healRemoteScroll:GetChildren()) do
        if not v:IsA("UIListLayout") then v:Destroy() end
    end
    Heal.scanned={}
    UI.healScanStatus.Text="⏳ Scanning..."
    task.spawn(function()
        local found=0
        if not scanButtons then
            local function scanSvc(svc)
                pcall(function()
                    for _,obj in ipairs(svc:GetDescendants()) do
                        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                            local path=getPath(obj)
                            if looksHeal(obj.Name,path) then
                                addHealEntry(obj.Name,path,obj,false); found=found+1
                                addHealLog("Remote: "..obj.Name,C.Teal)
                            end
                        end
                    end
                end)
            end
            scanSvc(Svc.RS); scanSvc(workspace)
            pcall(function() scanSvc(player:WaitForChild("PlayerGui")) end)
        else
            local pgui=player:FindFirstChild("PlayerGui")
            if pgui then
                local function scanNode(inst,depth)
                    if depth>15 then return end
                    for _,ch in ipairs(inst:GetChildren()) do
                        if ch:IsA("TextButton") or ch:IsA("ImageButton") then
                            local nm,tx=ch.Name,(ch:IsA("TextButton") and ch.Text or "")
                            local nl,tl=nm:lower(),tx:lower()
                            for _,k in ipairs(HEAL_BTN_KW) do
                                if nl:find(k) or tl:find(k) then
                                    local path=getPath(ch)
                                    addHealEntry(nm.." ["..tx.."]",path,ch,true); found=found+1
                                    addHealLog("Button: "..nm.." ("..tx..")",C.Cyan); break
                                end
                            end
                        end
                        scanNode(ch,depth+1)
                    end
                end
                scanNode(pgui,0)
            end
        end
        UI.healScanStatus.Text=found==0 and "⚠ None found — try near a heal center" or ("✅ Found "..found.." source(s) — click USE to select")
        UI.healScanStatus.TextColor3=found==0 and C.Trainer or C.Teal
    end)
end

UI.healScanRemBtn.MouseButton1Click:Connect(function() doScan(false) end)
UI.healScanBtnBtn.MouseButton1Click:Connect(function() doScan(true) end)
UI.healTestBtn.MouseButton1Click:Connect(function() addHealLog("🧪 Manual test",C.Trainer); performHeal() end)
UI.healClearBtn.MouseButton1Click:Connect(function()
    Heal.remote=nil; Heal.remoteName=""; Heal.remotePath=""
    cfg.healRemoteName=""; cfg.healRemotePath=""; saveConfig()
    UI.healSelName.Text="None selected"; UI.healSelName.TextColor3=C.Dim
    UI.healSelPath.Text="Path: —"; addHealLog("Cleared",C.Dim)
end)
UI.healOnBtn.MouseButton1Click:Connect(function()
    Heal.enabled=true; cfg.autoHealEnabled=true; saveConfig()
    UI.healOnBtn.BackgroundColor3=C.Teal; UI.healOffBtn.BackgroundColor3=C.AccentDim
    UI.cfgHealVal.Text="ON"; UI.cfgHealVal.TextColor3=C.Teal
    notify("LumiWare","Auto-Heal ON (< "..Heal.threshold.."%)",4)
    addHealLog("✅ Auto-Heal ON",C.Teal)
end)
UI.healOffBtn.MouseButton1Click:Connect(function()
    Heal.enabled=false; cfg.autoHealEnabled=false; saveConfig()
    UI.healOnBtn.BackgroundColor3=C.AccentDim; UI.healOffBtn.BackgroundColor3=C.Red
    UI.cfgHealVal.Text="OFF"; UI.cfgHealVal.TextColor3=C.Dim
    addHealLog("❌ Auto-Heal OFF",C.Dim)
end)
UI.healThreshInput.FocusLost:Connect(function()
    local v=tonumber(UI.healThreshInput.Text)
    if v and v>=1 and v<=99 then
        Heal.threshold=math.floor(v); cfg.autoHealThreshold=Heal.threshold; saveConfig()
        UI.cfgThreshVal.Text=tostring(Heal.threshold).."%"
    else UI.healThreshInput.Text=tostring(Heal.threshold) end
end)

-- SCAN UI button
scanBtn2.MouseButton1Click:Connect(function()
    addBattleLog("🔍 Scanning buttons...",C.Trainer)
    task.spawn(function()
        local pgui=player:FindFirstChild("PlayerGui"); if not pgui then return end
        local n=0
        local function sc(inst,path,depth)
            if depth>15 then return end
            for _,ch in ipairs(inst:GetChildren()) do
                local cp=path.."/"..ch.Name
                if ch:IsA("TextButton") or ch:IsA("ImageButton") then
                    n=n+1
                    local tx=ch:IsA("TextButton") and ch.Text or "[Img]"
                    log("SCAN",("[%s] %s | text=%q"):format(ch.Visible and "V" or "H",cp,tx))
                    addBattleLog("🔘 "..ch.Name.." | "..tx,C.Trainer)
                end
                sc(ch,cp,depth+1)
            end
        end
        sc(pgui,"PlayerGui",0)
        addBattleLog("🔍 "..n.." buttons (F9 for paths)",C.Trainer)
        notify("LumiWare","Scan: "..n.." buttons — check F9",5)
    end)
end)

--==================================================
-- OUTGOING SPY + HEAL AUTODETECT
--==================================================
pcall(function()
    if hookmetamethod then
        local old; old=hookmetamethod(game,"__namecall",function(self,...)
            local method=getnamecallmethod()
            if method=="FireServer" and self:IsA("RemoteEvent") then
                if State.discoveryMode and self.Name=="EVT" then
                    local args={...}; local parts={}
                    for i=1,math.min(#args,6) do
                        parts[#parts+1]="arg"..i.."="..(type(args[i])=="string" and '"'..args[i]:sub(1,20)..'"' or type(args[i]))
                    end
                    addBattleLog("📤 "..self.Name.." | "..table.concat(parts,", "),Color3.fromRGB(255,180,80))
                end
                pcall(function()
                    if Heal.remoteName=="" and looksHeal(self.Name,getPath(self)) then
                        addHealEntry(self.Name,getPath(self),self,false)
                        UI.healScanStatus.Text="✅ Auto-detected: "..self.Name; UI.healScanStatus.TextColor3=C.Teal
                        addHealLog("🔍 Auto-detected: "..self.Name,C.Teal)
                    end
                end)
            end
            return old(self,...)
        end)
        log("HOOK","Namecall spy installed")
    end
end)

--==================================================
-- AUTO-WALK
--==================================================
local function startWalk()
    if Auto.walkThread then return end
    Auto.walkThread=task.spawn(function()
        _G.LumiWare_WalkThread=Auto.walkThread
        local char=player.Character or player.CharacterAdded:Wait()
        local hum=char:WaitForChild("Humanoid")
        local rp=char:WaitForChild("HumanoidRootPart")
        local center=rp.Position; local r=6; local n=12; local pi=0
        while Auto.walkEnabled and gui.Parent do
            if State.battleState=="active" then
                pcall(function() Svc.VIM:SendKeyEvent(false,Enum.KeyCode.LeftShift,false,game) end)
                task.wait(0.5)
            else
                char=player.Character; if not char then task.wait(1)
                else
                    hum=char:FindFirstChild("Humanoid"); rp=char:FindFirstChild("HumanoidRootPart")
                    if not hum or not rp or hum.Health<=0 then task.wait(1)
                    else
                        pcall(function() Svc.VIM:SendKeyEvent(true,Enum.KeyCode.LeftShift,false,game) end)
                        local angle=(pi/n)*math.pi*2
                        local target=center+Vector3.new(math.cos(angle)*r,0,math.sin(angle)*r)
                        pi=(pi+1)%n; hum:MoveTo(target)
                        local ms=tick()
                        while Auto.walkEnabled and (tick()-ms)<2 do
                            Svc.Run.Heartbeat:Wait()
                            if not rp or not rp.Parent then break end
                            if (rp.Position-target).Magnitude<2 then break end
                        end
                    end
                end
            end
        end
        pcall(function() Svc.VIM:SendKeyEvent(false,Enum.KeyCode.LeftShift,false,game) end)
    end)
end
local function stopWalk()
    Auto.walkEnabled=false
    if Auto.walkThread then pcall(function() task.cancel(Auto.walkThread) end); Auto.walkThread=nil end
    pcall(function()
        local ch=player.Character; if ch then
            local h=ch:FindFirstChild("Humanoid"); local r2=ch:FindFirstChild("HumanoidRootPart")
            if h and r2 then h:MoveTo(r2.Position) end
        end
    end)
    pcall(function() Svc.VIM:SendKeyEvent(false,Enum.KeyCode.LeftShift,false,game) end)
end
walkBtn2.MouseButton1Click:Connect(function()
    Auto.walkEnabled=not Auto.walkEnabled; cfg.autoWalk=Auto.walkEnabled; saveConfig(); updateAutoUI()
    if Auto.walkEnabled then startWalk(); addBattleLog("🚶 Walk ON",C.Green)
    else stopWalk(); addBattleLog("🚶 Walk OFF",C.Dim) end
end)

--==================================================
-- BATTLE UI FINDER
--==================================================
local BtnCache={run=nil,fight=nil,moves={},moveN={}}
local btnsScanned=false
local cachedBG=nil; local bgDumped=false
local cachedMoveNames={}

local function getBG()
    if cachedBG then
        local ok,ok2=pcall(function() return cachedBG.Parent~=nil end)
        if ok and ok2 then return cachedBG end; cachedBG=nil
    end
    local pgui=player:FindFirstChild("PlayerGui"); if not pgui then return nil end
    local bg=nil
    pcall(function()
        local m=pgui:FindFirstChild("MainGui"); if m then local f=m:FindFirstChild("Frame"); if f then bg=f:FindFirstChild("BattleGui") end end
    end)
    if not bg then pcall(function() bg=pgui:FindFirstChild("BattleGui",true) end) end
    if bg then
        cachedBG=bg
        if not bgDumped then bgDumped=true; pcall(function()
            log("AUTO","=== BattleGui children ===")
            for _,ch in ipairs(bg:GetChildren()) do log("AUTO","  "..ch.Name.." ("..ch.ClassName..") V="..tostring(ch.Visible)) end
        end) end
    end
    return bg
end

local function hasMove(ui) return ui and (ui.moveButtons[1] or ui.moveButtons[2] or ui.moveButtons[3] or ui.moveButtons[4]) and true or false end

local function findUI()
    local bg=getBG(); if not bg then btnsScanned=false; return nil end
    local res={runButton=nil,fightButton=nil,moveButtons={},moveNames={}}
    if btnsScanned then
        local valid=true
        pcall(function()
            if BtnCache.run and not BtnCache.run.Parent then valid=false end
            if BtnCache.fight and not BtnCache.fight.Parent then valid=false end
        end)
        if valid then
            pcall(function()
                if BtnCache.run and BtnCache.run.Parent and BtnCache.run.Parent.Visible then res.runButton=BtnCache.run end
                if BtnCache.fight and BtnCache.fight.Parent then
                    local anc=BtnCache.fight.Parent; local v=true
                    while anc and anc~=bg do if anc:IsA("GuiObject") and not anc.Visible then v=false break end; anc=anc.Parent end
                    if v then res.fightButton=BtnCache.fight end
                end
                for i=1,4 do local mb=BtnCache.moves[i]; if mb and mb.Parent and mb.Parent.Visible then res.moveButtons[i]=mb; res.moveNames[i]=BtnCache.moveN[i] end end
            end)
            if not BtnCache.moves[1] and not BtnCache.moves[2] and not BtnCache.moves[3] and not BtnCache.moves[4] then btnsScanned=false
            else return res end
        end; btnsScanned=false
    end
    pcall(function()
        local ms={Move1=1,Move2=2,Move3=3,Move4=4}
        for _,desc in ipairs(bg:GetDescendants()) do
            if desc:IsA("ImageButton") and desc.Name=="Button" and desc.Parent then
                local pn=desc.Parent.Name
                if pn=="Run" then BtnCache.run=desc; if desc.Parent.Visible then res.runButton=desc end
                elseif ms[pn] then
                    local sl=ms[pn]; BtnCache.moves[sl]=desc
                    if desc.Parent.Visible then
                        res.moveButtons[sl]=desc
                        if not cachedMoveNames[sl] then
                            local tx=desc.Parent:FindFirstChildOfClass("TextLabel") or desc:FindFirstChildOfClass("TextLabel")
                            if tx and tx.Text and tx.Text~="" then cachedMoveNames[sl]=tx.Text:lower() end
                        end
                        BtnCache.moveN[sl]=cachedMoveNames[sl]; res.moveNames[sl]=cachedMoveNames[sl]
                    end
                elseif pn~="SoulMove" then
                    if not BtnCache.fight then BtnCache.fight=desc end
                    local anc=desc.Parent; local av=true
                    while anc and anc~=bg do if anc:IsA("GuiObject") and not anc.Visible then av=false break end; anc=anc.Parent end
                    if av and not res.fightButton then res.fightButton=desc end
                end
            end
        end; btnsScanned=true
    end)
    return res
end

local function clickBtn(button)
    if not button then return false end
    if firesignal then
        pcall(function() firesignal(button.MouseButton1Click) end)
        pcall(function() firesignal(button.Activated) end)
        if button.Parent then pcall(function() firesignal(button.Parent.MouseButton1Click) end) end
    end
    if fireclick then pcall(function() fireclick(button) end) end
    pcall(function()
        local p,s=button.AbsolutePosition,button.AbsoluteSize
        local cx,cy=p.X+s.X/2,p.Y+s.Y/2
        Svc.VIM:SendMouseButtonEvent(cx,cy,0,true,game,1); task.wait(0.03)
        Svc.VIM:SendMouseButtonEvent(cx,cy,0,false,game,1)
    end)
    pcall(function()
        local ins=Svc.GUI:GetGuiInset()
        local p,s=button.AbsolutePosition,button.AbsoluteSize
        local cx,cy=p.X+s.X/2,p.Y+s.Y/2+ins.Y
        Svc.VIM:SendMouseButtonEvent(cx,cy,0,true,game,1); task.wait(0.03)
        Svc.VIM:SendMouseButtonEvent(cx,cy,0,false,game,1)
    end)
    return true
end

local function performAuto(battleType)
    local mode,slot
    if battleType=="Wild" then
        if not Auto.wildOn or Auto.wildMode=="off" then return end
        mode=Auto.wildMode; slot=Auto.wildSlot
    elseif battleType=="Trainer" then
        if not Auto.trainerOn or Auto.trMode=="off" then return end
        mode=Auto.trMode; slot=Auto.trSlot
    else return end

    if State.rareFoundPause or State.pendingAutoAction then return end
    State.pendingAutoAction=true
    local tag="["..battleType.."]"

    task.spawn(function()
        local hb=Svc.Run.Heartbeat
        local ui=nil; local ps=tick()
        while (tick()-ps)<30 do
            if State.rareFoundPause then State.pendingAutoAction=false; return end
            ui=findUI()
            if ui then
                if mode=="run" and ui.runButton then break end
                if ui.runButton or ui.fightButton then break end
            end
            hb:Wait()
        end
        if not ui or (not ui.runButton and not ui.fightButton) then
            addBattleLog("⚠ "..tag.." UI timeout",C.Trainer); State.pendingAutoAction=false; return
        end

        if mode=="run" then
            if ui.runButton then
                addBattleLog("🤖 "..tag.." RUN",C.Cyan)
                for _=1,10 do
                    local fu=findUI(); if not fu or not fu.runButton then break end
                    clickBtn(fu.runButton); task.wait(0.2)
                end
            else addBattleLog("⚠ "..tag.." no Run btn",C.Trainer) end
            State.pendingAutoAction=false; return
        end

        -- MOVE loop
        local col=battleType=="Wild" and C.Green or C.Trainer
        local turns=0
        while turns<30 do
            turns=turns+1
            if State.rareFoundPause then break end
            if battleType=="Wild" and Auto.wildMode~="move" then break end
            if battleType=="Trainer" and Auto.trMode~="move" then break end

            local tui=nil; local ts=tick()
            while (tick()-ts)<10 do
                if State.rareFoundPause then break end
                tui=findUI(); if tui and (tui.fightButton or hasMove(tui)) then break end; hb:Wait()
            end
            if not tui or (not tui.fightButton and not hasMove(tui)) then tui={fightButton=nil,moveButtons={},moveNames={}} end

            local clicked=false
            if tui.fightButton and not hasMove(tui) then
                if turns==1 then addBattleLog("🤖 "..tag.." FIGHT...",col) end
                clickBtn(tui.fightButton); clicked=true
                local ms=tick(); local lr=ms
                while (tick()-ms)<3 do
                    hb:Wait(); local mu=findUI()
                    if mu and hasMove(mu) then tui=mu break end
                    if (tick()-lr)>=0.3 then lr=tick(); local ru=findUI(); if ru and ru.fightButton and not hasMove(ru) then clickBtn(ru.fightButton) end end
                end
                if hasMove(tui) then
                    local sl=math.clamp(slot,1,4)
                    if tui.moveButtons[sl] then
                        addBattleLog("🤖 T"..turns.." "..tag.." M"..sl,col); clickBtn(tui.moveButtons[sl])
                    else
                        for s2=1,4 do if tui.moveButtons[s2] then addBattleLog("🤖 T"..turns.." M"..s2.."(fb)",col); clickBtn(tui.moveButtons[s2]); break end end
                    end
                end
            elseif hasMove(tui) then
                clicked=true
                local sl=math.clamp(slot,1,4)
                if tui.moveButtons[sl] then clickBtn(tui.moveButtons[sl]); addBattleLog("🤖 T"..turns.." "..tag.." M"..sl,col)
                else for s2=1,4 do if tui.moveButtons[s2] then clickBtn(tui.moveButtons[s2]); break end end end
            end

            if clicked then
                local vs=tick(); local lr2=vs
                while (tick()-vs)<2 do
                    local vu=findUI(); if not vu or not hasMove(vu) then break end
                    if (tick()-lr2)>=0.3 then lr2=tick()
                        local ru=findUI(); local sl2=math.clamp(slot,1,4)
                        if ru then (ru.moveButtons[sl2] and clickBtn(ru.moveButtons[sl2])) or (function() for s2=1,4 do if ru.moveButtons[s2] then clickBtn(ru.moveButtons[s2]); break end end end)() end
                    end
                    hb:Wait()
                end
                local ws=tick()
                while (tick()-ws)<30 do
                    if State.rareFoundPause then break end
                    local cu=findUI()
                    if cu and (cu.fightButton or hasMove(cu)) then break end
                    if not cu and (tick()-ws)>5 then
                        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                            addBattleLog("🤖 "..tag.." done("..turns.."t)",col); break
                        end
                    end
                    hb:Wait()
                end
                if not findUI() then addBattleLog("🤖 "..tag.." done("..turns.."t)",col); break end
            end
        end

        task.wait(1)
        if State.battleState=="active" then State.battleState="idle"; UI.stateVal.Text="Idle"; UI.stateVal.TextColor3=C.Dim end
        State.pendingAutoAction=false
    end)
end

--==================================================
-- BATTLE PROCESSING
--==================================================
local function extractSide(entry)
    local cmd=entry[1]; if type(cmd)~="string" then return nil end
    local cmdL=cmd:lower(); if cmdL~="owm" and cmdL~="switch" then return nil end
    local rawName,side,infoStr
    for i=2,math.min(#entry,8) do
        local v=entry[i]
        if type(v)=="string" then
            if (v=="p1" or v=="p2") and not side then side=v
            elseif v:find(":%s*.+") then
                local n=v:match(":%s*(.+)$"); if n then rawName=n end
                if v:find("p1") then side=side or "p1" elseif v:find("p2") then side=side or "p2" end
            elseif v:find(", L%d+") then
                infoStr=v; if not rawName then rawName=v:match("^([^,]+)") end
            end
        elseif type(v)=="table" and not rawName then
            if type(v.name)=="string" then rawName=v.name end
        end
    end
    if rawName then return rawName,side,infoStr,nameFormat(rawName) end
end

local KNOWN_CMD={player=true,owm=true,switch=true,start=true,move=true,
    damage=true,["-damage"]=true,turn=true,faint=true,["end"]=true}

local function processBattle(cmds)
    addBattleLog(">>> "..tostring(#cmds).." cmds <<<",C.Green)
    for _,e in pairs(cmds) do
        if type(e)=="table" and type(e[1])=="string" and e[1]:lower()=="start" then
            resetBattle(); Battle.active=true; btnsScanned=false; break
        end
    end
    for _,e in pairs(cmds) do
        if type(e)=="table" and type(e[1])=="string" and e[1]:lower()=="player" then
            local side,tag=e[2],e[3]
            if type(tag)=="string" then
                if tag:find("#Wild") then Battle.battleType="Wild"
                elseif side=="p2" then Battle.battleType="Trainer" end
            end
        end
    end
    for _,e in pairs(cmds) do
        if type(e)=="table" and type(e[1])=="string" then
            local cmdL=e[1]:lower()
            if cmdL=="owm" or cmdL=="switch" then
                local rawN,side,info,dispN=extractSide(e)
                if rawN then
                    local stats=parseStats(info)
                    if side=="p2" then Battle.enemy=dispN; Battle.enemyStats=stats; Battle.enemyRawEntry=e
                    elseif side=="p1" then Battle.player=dispN; Battle.playerStats=stats
                    else
                        if not Battle.enemy then Battle.enemy=dispN; Battle.enemyStats=stats; Battle.enemyRawEntry=e
                        elseif not Battle.player then Battle.player=dispN; Battle.playerStats=stats end
                    end
                end
            end
        end
    end
    if not Battle.enemy then
        for _,e in pairs(cmds) do
            if type(e)=="table" and type(e[1])=="string" then
                local cl=e[1]:lower()
                if cl=="move" or cl=="damage" or cl=="-damage" then
                    for i=2,#e do
                        if type(e[i])=="string" then
                            local pn,n=e[i]:match("p(%d+)%a*:%s*(.+)$")
                            if pn=="2" and n then Battle.enemy=nameFormat(n); break end
                        end
                    end
                    if Battle.enemy then break end
                end
            end
        end
    end
    for _,e in pairs(cmds) do
        if type(e)=="table" and type(e[1])=="string" then
            local cl=e[1]:lower()
            if cl=="faint" then
                if type(e[2])=="string" and e[2]:find("p2") then
                    State.sessionKOs=State.sessionKOs+1
                    UI.sessionLbl.Text=("Session: %d KOs | %.1fk Dmg"):format(State.sessionKOs,State.sessionDamage/1000)
                end
            elseif cl=="-damage" or cl=="damage" then
                if type(e[2])=="string" and e[2]:find("p2") then
                    State.sessionDamage=State.sessionDamage+100
                    UI.sessionLbl.Text=("Session: %d KOs | %.1fk Dmg"):format(State.sessionKOs,State.sessionDamage/1000)
                end
            end
        end
    end

    State.battleState="active"; State.lastBattleTick=tick(); Battle.active=true
    UI.stateVal.Text="In Battle"; UI.stateVal.TextColor3=C.Green

    if Battle.battleType=="Wild" then UI.typeVal.Text="Wild"; UI.typeVal.TextColor3=C.Wild
    elseif Battle.battleType=="Trainer" then UI.typeVal.Text="Trainer"; UI.typeVal.TextColor3=C.Trainer end

    local eN=Battle.enemy or "Unknown"
    local pN=Battle.player or "Unknown"

    if eN~="Unknown" and not Battle.enemyProcessed then
        Battle.enemyProcessed=true; cachedMoveNames={}

        if Battle.battleType=="Wild" then
            State.encounterCount=State.encounterCount+1
            UI.encVal.Text=tostring(State.encounterCount)
            table.insert(State.encounterHistory,1,{name=eN,time=os.date("%X")})
            if #State.encounterHistory>10 then table.remove(State.encounterHistory,11) end
        end

        local rare=isRareLoomian(eN) or isRareMod(eN)
        if not rare and Battle.enemyRawEntry then
            rare=scanEntryRare(Battle.enemyRawEntry)
            if rare then log("RARE","Deep scan caught rare!") end
        end

        if rare then
            UI.enemyLbl.Text='Enemy: <font color="#FFD700">⭐ '..eN..' (RARE!)</font>'
            addBattleLog("⭐ RARE: "..eN,C.Gold)
            State.rareFoundPause=true; updateAutoUI()
            if State.currentEnemy~=eN then
                State.currentEnemy=eN; State.raresFound=State.raresFound+1
                playRare(); notify("⭐ LumiWare","RARE: "..eN.."! Auto PAUSED.",10)
                addRareLog(eN,Battle.enemyStats and ("Lv."..tostring(Battle.enemyStats.level)) or nil)
                webhookRare(eN,Battle.enemyStats and Battle.enemyStats.level,
                    Battle.enemyStats and Battle.enemyStats.gender or "?",
                    State.encounterCount,fmtTime(tick()-State.huntStart))
            end
        else
            UI.enemyLbl.Text="Enemy: "..eN
            addBattleLog(Battle.battleType..": "..eN,C.Dim)
            State.currentEnemy=nil
            if not State.rareFoundPause then performAuto(Battle.battleType) end
        end
    end

    if Battle.enemyStats then
        local s=Battle.enemyStats
        local g=s.gender=="M" and "♂" or (s.gender=="F" and "♀" or "?")
        UI.enemyStatsLbl.Text=("Lv.%d  %s  HP %d/%d"):format(s.level or 0,g,s.hp or 0,s.maxHP or 0)
    end
    if pN~="Unknown" then
        UI.playerLbl.Text="Your Loomian: "..pN
        if Battle.playerStats then
            local s=Battle.playerStats
            local g=s.gender=="M" and "♂" or (s.gender=="F" and "♀" or "?")
            UI.playerLbl.Text=UI.playerLbl.Text..(" (Lv.%d %s HP %d/%d)"):format(s.level or 0,g,s.hp or 0,s.maxHP or 0)
        end
    end
end

--==================================================
-- HOOK REMOTES
--==================================================
local hooked={}; local hookedCount=0

local function hookEvent(remote)
    if hooked[remote] then return end; hooked[remote]=true; hookedCount=hookedCount+1
    track(remote.OnClientEvent:Connect(function(...)
        local ac=select("#",...)
        local args={}; for i=1,ac do args[i]=select(i,...) end; args.n=ac

        if State.discoveryMode then
            local parts={}
            for i=1,ac do
                local a=args[i]; local info="arg"..i.."="..type(a)
                if type(a)=="string" then info=info..'("'..a:sub(1,20)..'")'
                elseif type(a)=="table" then local c=0; for _ in pairs(a) do c=c+1 end; info=info.."(n="..c..")" end
                parts[#parts+1]=info
            end
            addBattleLog("📡 "..remote.Name.." | "..table.concat(parts,", "),Color3.fromRGB(180,180,180))
        end

        local isBattle=type(args[1])=="string" and args[1]:lower():find("battle") and true or false
        local cmdTable=nil

        for i=1,ac do
            local arg=args[i]
            if type(arg)=="table" then
                for k,v in pairs(arg) do
                    if type(v)=="table" then
                        local f=v[1]; if type(f)=="string" and KNOWN_CMD[f:lower()] then cmdTable=arg; break end
                    elseif type(v)=="string" and v:sub(1,1)=="[" then
                        local ok,dec=pcall(function() return Svc.Http:JSONDecode(v) end)
                        if ok and type(dec)=="table" and type(dec[1])=="string" and KNOWN_CMD[dec[1]:lower()] then
                            local dt={}
                            for k2,v2 in pairs(arg) do
                                if type(v2)=="string" and (v2:sub(1,1)=="[" or v2:sub(1,1)=="{") then
                                    local ok2,d2=pcall(function() return Svc.Http:JSONDecode(v2) end)
                                    dt[k2]=(ok2 and type(d2)=="table") and d2 or v2
                                else dt[k2]=v2 end
                            end
                            cmdTable=dt; break
                        end
                    end
                end
                if cmdTable then break end
            end
        end

        if cmdTable then processBattle(cmdTable) elseif isBattle then logD("BattleEvent no cmdTable") end
    end))
end

log("HOOK","Scanning...")
local c2=0
for _,obj in ipairs(Svc.RS:GetDescendants()) do if obj:IsA("RemoteEvent") then hookEvent(obj); c2=c2+1 end end
track(Svc.RS.DescendantAdded:Connect(function(obj) if obj:IsA("RemoteEvent") then hookEvent(obj) end end))
pcall(function() for _,obj in ipairs(workspace:GetDescendants()) do if obj:IsA("RemoteEvent") then hookEvent(obj) end end end)
pcall(function() for _,obj in ipairs(player:WaitForChild("PlayerGui"):GetDescendants()) do if obj:IsA("RemoteEvent") then hookEvent(obj) end end end)
log("HOOK","Hooked "..c2)

--==================================================
-- THREADS
--==================================================
local function spawnThread(fn)
    local t=task.spawn(fn)
    if _G.LumiWare_Threads then _G.LumiWare_Threads[#_G.LumiWare_Threads+1]=t end
    return t
end

spawnThread(function()
    while not _G.LumiWare_StopFlag do
        if not gui.Parent then break end
        local elapsed=tick()-State.huntStart
        UI.timerVal.Text=fmtTime(elapsed)
        local mins=elapsed/60
        if mins>0 then UI.epmVal.Text=("%.1f"):format(State.encounterCount/mins) end
        if State.battleState=="active" and (tick()-State.lastBattleTick)>8 then
            State.battleState="idle"; UI.stateVal.Text="Idle"; UI.stateVal.TextColor3=C.Dim
            if State.rareFoundPause then State.rareFoundPause=false; updateAutoUI(); log("AUTO","Rare pause lifted") end
        end
        task.wait(1)
    end
end)

spawnThread(function()
    local last=0
    while not _G.LumiWare_StopFlag do
        if not gui.Parent then break end
        if State.encounterCount>0 and State.encounterCount%50==0 and State.encounterCount~=last then
            last=State.encounterCount
            webhookSession(State.encounterCount,fmtTime(tick()-State.huntStart),State.raresFound)
        end
        task.wait(5)
    end
end)

spawnThread(function()
    while not _G.LumiWare_StopFlag do
        if not gui.Parent then break end
        if Heal.enabled and Heal.remote and State.battleState~="active" then
            if Battle.playerStats and Battle.playerStats.hp and Battle.playerStats.maxHP then
                local pct=(Battle.playerStats.hp/Battle.playerStats.maxHP)*100
                if pct<Heal.threshold and (tick()-Heal.lastTime)>Heal.cooldown then
                    addHealLog(("⚠ HP %.0f%% — healing!"):format(pct),C.Trainer); performHeal()
                end
            end
        end
        task.wait(3)
    end
end)

-- Restore saved heal remote
if Heal.remoteName~="" then
    spawnThread(function()
        task.wait(3)
        for _,obj in ipairs(Svc.RS:GetDescendants()) do
            if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) and obj.Name==Heal.remoteName then
                Heal.remote=obj
                UI.healSelName.Text="Remote: "..Heal.remoteName; UI.healSelName.TextColor3=C.Teal
                UI.healSelPath.Text=getPath(obj)
                addHealLog("✅ Restored: "..Heal.remoteName,C.Teal); return
            end
        end
        addHealLog("⚠ Saved remote not found: "..Heal.remoteName,C.Trainer)
    end)
end

addBattleLog("Hooked "..hookedCount.." remotes — READY",C.Green)
addBattleLog(VERSION..": Trainer Auto | Auto-Heal | Config Tab",C.Accent)
log("INFO","LumiWare "..VERSION.." READY | "..hookedCount.." remotes | "..PLAYER_NAME)
notify("⚡ LumiWare "..VERSION,"Ready! "..hookedCount.." remotes hooked.\nTrainer Auto + Auto-Heal active.",6)
