dofile( "$SURVIVAL_DATA/Scripts/game/managers/BeaconManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/EffectManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/ElevatorManager.lua"  )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
-- NOTE: Movement speed is only effected in characterset?? need to try other things on it
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_meleeattacks.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/recipes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestEntityManager.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/EventManager.lua" )
-- Custom imports:
dofile( "$CONTENT_DATA/Scripts/Evo_UnitManager.lua" )
dofile( "$CONTENT_DATA/Scripts/Evo_survival_units.lua" )
dofile( "$CONTENT_DATA/Scripts/RespawnManager.lua" )
dofile( "$CONTENT_DATA/Scripts/survival_streamreader.lua") 



---@class Game : GameClass
---@field sv table
---@field cl table
---@field warehouses table
Game = class( nil )
Game.enableLimitedInventory = false
Game.enableRestrictions = true
Game.enableFuelConsumption = false
Game.enableAmmoConsumption = false
Game.enableUpgrade = true
Game.worldScriptFilename = "$CONTENT_DATA/Scripts/World.lua" -- CAN change?
Game.worldScriptClass = "World"
Game.worldFileName = "$CONTENT_DATA/Terrain/Worlds/bigWorldTest.world" -- path to custom worldfile goes here
Game.worldXMin = -16
Game.worldXMax = 16
Game.worldYMin = -16
Game.worldYMax = 16 -- REMEMBER TO UPDATE THIS AND WORLD.lua when making new maps

local SyncInterval = 400 -- 400 ticks | 10 seconds
local IntroFadeDuration = 1.1
local IntroEndFadeDuration = 1.1
local IntroFadeTimeout = 5.0

function Game.server_onCreate( self )
	print( "Game.server_onCreate" )
	self.sv = {}
	self.sv.saved = self.storage:load()
	
	--print( "Saved:", self.sv.saved )

	--[[ OLD world load (go back if broken)
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.data = self.data
		printf( "Seed: %.0f", self.sv.saved.data.seed )
        print("Loading world")
        self.sv.saved.world = sm.world.createWorld( "$CONTENT_DATA/Scripts/World.lua", "World",{ dev =true} )
		--self.sv.saved.world = sm.world.createWorld( "$SURVIVAL_DATA/Scripts/game/worlds/world.lua", "world", { dev = self.sv.saved.data.dev }, self.sv.saved.data.seed ) REMOVE PLZ
		self.storage:save( self.sv.saved )
	end]]
	--print("self data",self.data)
	--print(self.data.worldFile)
	if self.data == nil or self.data.worldFile == nil then
		self.data = {}
		self.data.worldFile = self.worldFileName
	end
	if self.sv.saved == nil then
		local legacyCreativeWorld = sm.world.getLegacyCreativeWorld()
		if legacyCreativeWorld then
			self.sv.saved = {}
			self.sv.saved.keptCells = {}
			self:sv_generateSavedCells() -- auto populates the shtuff
			self.sv.saved.data = self.data
			self.sv.saved.world = legacyCreativeWorld
			self.storage:save( self.sv.saved )
			--print("legacy post asave saved",self.sv.saved)
		else
			self.sv.saved = {}
			self.sv.saved.keptCells = {}
			self:sv_generateSavedCells()
			self.sv.saved.data = self.data
			self.sv.saved.world = sm.world.createWorld( self.worldScriptFilename, self.worldScriptClass, { worldFile = self.data.worldFile }, self.data.seed )
			--print("post gen saved",self.sv.saved)
			self.storage:save( self.sv.saved )
			--print("Post save saved",self.sv.saved)
		end
	end

	

	if not sm.exists( self.sv.saved.world ) then
		sm.world.loadWorld( self.sv.saved.world )
	end
	--print("check saved",self.sv.saved)
	if self.sv.saved.keptCells == nil or self.sv.saved.keptCells == {} or #self.sv.saved.keptCells <= 0 then
		print("Could not find saved cells",self.sv.saved)
		self:sv_generateSavedCells()
		self.storage:save( self.sv.saved )
	end
	--self.data = nil
	g_disableScrapHarvest = true

	if self.sv.saved.data and self.sv.saved.data.dev then
		g_godMode = true
		g_survivalDev = true
		sm.log.info( "Starting Game in DEV mode" )
	end

	self:loadCraftingRecipes()
	g_enableCollisionTumble = true

	g_eventManager = EventManager()
	g_eventManager:sv_onCreate()

	g_respawnManager = RespawnManager()
	g_respawnManager:sv_onCreate( self.sv.saved.world )

	g_beaconManager = BeaconManager()
	g_beaconManager:sv_onCreate()

	print("Starting new unitManager")
	g_unitManager = UnitManager()
	--g_unitManager:sv_onCreate( self.sv.saved.world ) 
	g_unitManager:sv_onCreate( nil, { aggroCreations = true } ) --what difference between world and no world?
	print("pos unitmanagerOncreate")


	g_streamReader = StreamReader() -- Generate stream reader
	g_streamReader:sv_onCreate(self)
    print("Loaded stream Reader",g_streamReader.initialized)


	self.sv.time = sm.storage.load( STORAGE_CHANNEL_TIME )
	if self.sv.time then
		print( "Loaded timeData:" )
		print( self.sv.time )
	else
		self.sv.time = {}
		self.sv.time.timeOfDay = 6 / 24 -- 06:00
		self.sv.time.timeProgress = true
		sm.storage.save( STORAGE_CHANNEL_TIME, self.sv.time )
	end
	self.network:setClientData( { dev = g_survivalDev }, 1 )
	self:sv_updateClientData()

	self.sv.syncTimer = Timer()
	self.sv.syncTimer:start( 0 )
end

function Game.server_onRefresh( self )
	self.sv.time = sm.storage.load( STORAGE_CHANNEL_TIME )
	if self.sv.time then
		print( "Loaded timeData:" )
		print( self.sv.time )
	else
		self.sv.time = {}
		self.sv.time.timeOfDay = 6 / 24 -- 06:00
		self.sv.time.timeProgress = true
		sm.storage.save( STORAGE_CHANNEL_TIME, self.sv.time )
	end
	self.sv.syncTimer = Timer()
	self.sv.syncTimer:start( 0 )

	g_craftingRecipes = nil
	g_refineryRecipes = nil
	print("Refreshing streamReader")
	g_streamReader:sv_onRefresh(self)
	g_unitManager:sv_onRefresh(self)
	self:loadCraftingRecipes()
	print("refresh")
	--print(self.sv.saved)
end

function Game.client_onCreate( self )
	
	self.cl = {}
	self.cl.time = {}
	self.cl.time.timeOfDay = 0.0
	self.cl.time.timeProgress = true

	if not sm.isHost then
		self:loadCraftingRecipes()
		g_enableCollisionTumble = true
	end

	if g_respawnManager == nil then
		assert( not sm.isHost )
		g_respawnManager = RespawnManager()
	end
	g_respawnManager:cl_onCreate()

	if g_beaconManager == nil then
		assert( not sm.isHost )
		g_beaconManager = BeaconManager()
	end
	g_beaconManager:cl_onCreate()

	if g_unitManager == nil then
		assert( not sm.isHost )
		g_unitManager = UnitManager()
	end
	g_unitManager:cl_onCreate()

	g_effectManager = EffectManager()
	g_effectManager:cl_onCreate()

	-- Music effect
	g_survivalMusic = sm.effect.createEffect( "SurvivalMusic" )
	assert(g_survivalMusic)

	-- Survival HUD
	g_survivalHud = sm.gui.createSurvivalHudGui()
	assert(g_survivalHud)
end

function Game.sv_generateSavedCells(self) -- returns list of cells to immediately put in thingy
	--print("generating cells to keep",self.worldYMin,self.worldYMax,self.worldXMin,self.worldXMax)
	for cellY = self.worldYMin, self.worldYMax do
		for cellX = self.worldXMin, self.worldXMax do
			self:sv_keepCell(cellX,cellY,"InitialGen")
		end
	end
end


function Game.bindChatCommands( self )
		sm.game.bindChatCommand( "/ammo", { { "int", "quantity", true } }, "cl_onChatCommand", "Give ammo (default 50)" )
		sm.game.bindChatCommand( "/spudgun", {}, "cl_onChatCommand", "Give the spudgun" )
		sm.game.bindChatCommand( "/gatling", {}, "cl_onChatCommand", "Give the potato gatling gun" )
		sm.game.bindChatCommand( "/shotgun", {}, "cl_onChatCommand", "Give the fries shotgun" )
		sm.game.bindChatCommand( "/sunshake", {}, "cl_onChatCommand", "Give 1 sunshake" )
		sm.game.bindChatCommand( "/baguette", {}, "cl_onChatCommand", "Give 1 revival baguette" )
		sm.game.bindChatCommand( "/keycard", {}, "cl_onChatCommand", "Give 1 keycard" )
		sm.game.bindChatCommand( "/powercore", {}, "cl_onChatCommand", "Give 1 powercore" )
		sm.game.bindChatCommand( "/components", { { "int", "quantity", true } }, "cl_onChatCommand", "Give <quantity> components (default 10)" )
		sm.game.bindChatCommand( "/glowsticks", { { "int", "quantity", true } }, "cl_onChatCommand", "Give <quantity> components (default 10)" )
		sm.game.bindChatCommand( "/tumble", { { "bool", "enable", true } }, "cl_onChatCommand", "Set tumble state" )
		sm.game.bindChatCommand( "/god", {}, "cl_onChatCommand", "Mechanic characters will take no damage" )
		sm.game.bindChatCommand( "/respawn", {}, "cl_onChatCommand", "Respawn at last bed (or at the crash site)" )
		sm.game.bindChatCommand( "/encrypt", {}, "cl_onChatCommand", "Restrict interactions in all warehouses" )
		sm.game.bindChatCommand( "/decrypt", {}, "cl_onChatCommand", "Unrestrict interactions in all warehouses" )
		sm.game.bindChatCommand( "/limited", {}, "cl_onChatCommand", "Use the limited inventory" )
		sm.game.bindChatCommand( "/unlimited", {}, "cl_onChatCommand", "Use the unlimited inventory" )
		sm.game.bindChatCommand( "/ambush", { { "number", "magnitude", true }, { "int", "wave", true } }, "cl_onChatCommand", "Starts a 'random' encounter" )
		--sm.game.bindChatCommand( "/recreate", {}, "cl_onChatCommand", "Recreate world" )
		sm.game.bindChatCommand( "/timeofday", { { "number", "timeOfDay", true } }, "cl_onChatCommand", "Sets the time of the day as a fraction (0.5=mid day)" )
		sm.game.bindChatCommand( "/timeprogress", { { "bool", "enabled", true } }, "cl_onChatCommand", "Enables or disables time progress" )
		sm.game.bindChatCommand( "/day", {}, "cl_onChatCommand", "Disable time progression and set time to daytime" )
		sm.game.bindChatCommand( "/spawn", { { "string", "unitName", true }, { "int", "amount", true } }, "cl_onChatCommand", "Spawn a unit: 'woc', 'tapebot', 'totebot', 'haybot'" )
		sm.game.bindChatCommand( "/harvestable", { { "string", "harvestableName", true } }, "cl_onChatCommand", "Create a harvestable: 'tree', 'stone'" )
		sm.game.bindChatCommand( "/cleardebug", {}, "cl_onChatCommand", "Clear debug draw objects" )
		sm.game.bindChatCommand( "/export", { { "string", "name", false } }, "cl_onChatCommand", "Exports blueprint $SURVIVAL_DATA/LocalBlueprints/<name>.blueprint" )
		sm.game.bindChatCommand( "/import", { { "string", "name", false } }, "cl_onChatCommand", "Imports blueprint $SURVIVAL_DATA/LocalBlueprints/<name>.blueprint" )
		sm.game.bindChatCommand( "/starterkit", {}, "cl_onChatCommand", "Spawn a starter kit" )
		sm.game.bindChatCommand( "/mechanicstartkit", {}, "cl_onChatCommand", "Spawn a starter kit for starting at mechanic station" )
		sm.game.bindChatCommand( "/pipekit", {}, "cl_onChatCommand", "Spawn a pipe kit" )
		sm.game.bindChatCommand( "/foodkit", {}, "cl_onChatCommand", "Spawn a food kit" )
		sm.game.bindChatCommand( "/seedkit", {}, "cl_onChatCommand", "Spawn a seed kit" )
		sm.game.bindChatCommand( "/die", {}, "cl_onChatCommand", "Kill the player" )
		sm.game.bindChatCommand( "/sethp", { { "number", "hp", false } }, "cl_onChatCommand", "Set player hp value" )
		sm.game.bindChatCommand( "/setwater", { { "number", "water", false } }, "cl_onChatCommand", "Set player water value" )
		sm.game.bindChatCommand( "/setfood", { { "number", "food", false } }, "cl_onChatCommand", "Set player food value" )
		sm.game.bindChatCommand( "/aggroall", {}, "cl_onChatCommand", "All hostile units will be made aware of the player's position" )
		sm.game.bindChatCommand( "/goto", { { "string", "name", false } }, "cl_onChatCommand", "Teleport to predefined position" )
		sm.game.bindChatCommand( "/raid", { { "int", "level", false }, { "int", "wave", true }, { "number", "hours", true } }, "cl_onChatCommand", "Start a level <level> raid at player position at wave <wave> in <delay> hours." )
		sm.game.bindChatCommand( "/stopraid", {}, "cl_onChatCommand", "Cancel all incoming raids" )
		sm.game.bindChatCommand( "/disableraids", { { "bool", "enabled", false } }, "cl_onChatCommand", "Disable raids if true" )
		sm.game.bindChatCommand( "/camera", {}, "cl_onChatCommand", "Spawn a SplineCamera tool" )
		sm.game.bindChatCommand( "/noaggro", { { "bool", "enable", true } }, "cl_onChatCommand", "Toggles the player as a target" )
		sm.game.bindChatCommand( "/killall", {}, "cl_onChatCommand", "Kills all spawned units" )

		sm.game.bindChatCommand( "/printglobals", {}, "cl_onChatCommand", "Print all global lua variables" )
		sm.game.bindChatCommand( "/clearpathnodes", {}, "cl_onChatCommand", "Clear all path nodes in world" )
		sm.game.bindChatCommand( "/enablepathpotatoes", { { "bool", "enable", true } }, "cl_onChatCommand", "Creates path nodes at potato hits in world and links to previous node" )

		sm.game.bindChatCommand( "/activatequest",  { { "string", "name", true } }, "cl_onChatCommand", "Activate quest" )
		sm.game.bindChatCommand( "/completequest",  { { "string", "name", true } }, "cl_onChatCommand", "Complete quest" )

		sm.game.bindChatCommand( "/settilebool",  { { "string", "name", false }, { "bool", "value", false } }, "cl_onChatCommand", "Set named tile value at player position as a bool" )
		sm.game.bindChatCommand( "/settilefloat",  { { "string", "name", false }, { "number", "value", false } }, "cl_onChatCommand", "Set named tile value at player position as a floating point number" )
		sm.game.bindChatCommand( "/settilestring",  { { "string", "name", false }, { "string", "value", false } }, "cl_onChatCommand", "Set named tile value at player position as a bool" )
		sm.game.bindChatCommand( "/printtilevalues",  {}, "cl_onChatCommand", "Print all tile values at player position" )
		sm.game.bindChatCommand( "/reloadcell", {{ "int", "x", true }, { "int", "y", true }}, "cl_onChatCommand", "Reload cells at self or {x,y}" )
		sm.game.bindChatCommand( "/tutorialstartkit", {}, "cl_onChatCommand", "Spawn a starter kit for building a scrap car" )
		sm.game.bindChatCommand( "/noaggrocreations", { { "bool", "enable", true } }, "cl_onChatCommand", "Toggles whether the Tapebots will shoot at creations" )
		sm.game.bindChatCommand( "/popcapsules", { { "string", "filter", true } }, "cl_onChatCommand", "Opens all capsules. An optional filter controls which type of capsules to open: 'bot', 'animal'" )
		sm.game.bindChatCommand( "/place", { { "string", "harvestable", false } }, "cl_onChatCommand", "Places a harvestable at the aimed position. Must be placed on the ground. The harvestable parameter controls which harvestable to place: 'stone', 'tree', 'birch', 'leafy', 'spruce', 'pine'" )
		
		sm.game.bindChatCommand( "/keepcell",  {}, "cl_onChatCommand", "save/load current cell location	" )
		sm.game.bindChatCommand( "/keepcells",  {}, "cl_onChatCommand", "save/load all saved cells	" )

		sm.game.bindChatCommand( "/deletecell",  {}, "cl_onChatCommand", "delete individual cell" )
		sm.game.bindChatCommand( "/deletecells",  {}, "cl_onChatCommand", "Delete all save/loaded cells" )

		sm.game.bindChatCommand( "/listcells",  {}, "cl_onChatCommand", "lists all savec cells" )

		
		if sm.isHost then
			self.clearEnabled = false
			sm.game.bindChatCommand( "/allowclear", { { "bool", "enable", true } }, "cl_onChatCommand", "Enabled/Disables the /clear command" )
			sm.game.bindChatCommand( "/clear", {}, "cl_onChatCommand", "Remove all shapes in the world. It must first be enabled with /allowclear" )
		end
		
		--print("Chat cmd bound")

end

function Game.client_onClientDataUpdate( self, clientData, channel )
	--print("clientdataupdate",channel)
	if channel == 2 then
		self.cl.time = clientData.time
	elseif channel == 1 then
		g_survivalDev = clientData.dev
		--print("\n Binding chat commands \n")
		self:bindChatCommands()
	end
end


function Game.loadCraftingRecipes( self )
	LoadCraftingRecipes({
		workbench = "$SURVIVAL_DATA/CraftingRecipes/workbench.json",
		dispenser = "$SURVIVAL_DATA/CraftingRecipes/dispenser.json",
		cookbot = "$SURVIVAL_DATA/CraftingRecipes/cookbot.json",
		craftbot = "$SURVIVAL_DATA/CraftingRecipes/craftbot.json",
		dressbot = "$SURVIVAL_DATA/CraftingRecipes/dressbot.json"
	})
end

function Game.server_onFixedUpdate( self, timeStep )
	-- Update time
 	local prevTime = self.sv.time.timeOfDay
	if self.sv.time.timeProgress then
		self.sv.time.timeOfDay = self.sv.time.timeOfDay + timeStep / DAYCYCLE_TIME
	end
	local newDay = self.sv.time.timeOfDay >= 1.0
	if newDay then
		self.sv.time.timeOfDay = math.fmod( self.sv.time.timeOfDay, 1 )
	end

	if self.sv.time.timeOfDay >= DAYCYCLE_DAWN and prevTime < DAYCYCLE_DAWN then
		g_unitManager:sv_initNewDay()
	end

	-- Ambush
	--if not g_survivalDev then
	--	for _,ambush in ipairs( AMBUSHES ) do
	--		if self.sv.time.timeOfDay >= ambush.time and ( prevTime < ambush.time or newDay ) then
	--			self:sv_ambush( { magnitude = ambush.magnitude, wave = ambush.wave } )
	--		end
	--	end
	--end

	-- Client and save sync
	self.sv.syncTimer:tick()
	if self.sv.syncTimer:done() then
		self.sv.syncTimer:start( SyncInterval )
		sm.storage.save( STORAGE_CHANNEL_TIME, self.sv.time )
		self:sv_updateClientData()
	end

	--g_elevatorManager:sv_onFixedUpdate()





	if g_unitManager then 
		g_unitManager:sv_onFixedUpdate()
	end

	if g_eventManager then
		g_eventManager:sv_onFixedUpdate()
	end

	if g_streamReader then
		if g_streamReader.initialized then
			g_streamReader:sv_onFixedUpdate()
		end
	end
end

function Game.client_onFixedUpdate(self,dt)
	if g_streamReader then
		g_streamReader:cl_onFixedUpdate()
	end
end

function Game.sv_updateClientData( self )
	self.network:setClientData( { time = self.sv.time }, 2 )
end

function Game.client_onUpdate( self, dt )
	-- Update time
	if self.cl.time.timeProgress then
		self.cl.time.timeOfDay = math.fmod( self.cl.time.timeOfDay + dt / DAYCYCLE_TIME, 1.0 )
	end
	sm.game.setTimeOfDay( self.cl.time.timeOfDay )

	-- Update lighting values
	local index = 1
	while index < #DAYCYCLE_LIGHTING_TIMES and self.cl.time.timeOfDay >= DAYCYCLE_LIGHTING_TIMES[index + 1] do
		index = index + 1
	end
	assert( index <= #DAYCYCLE_LIGHTING_TIMES )

	local light = 0.0
	if index < #DAYCYCLE_LIGHTING_TIMES then
		local p = ( self.cl.time.timeOfDay - DAYCYCLE_LIGHTING_TIMES[index] ) / ( DAYCYCLE_LIGHTING_TIMES[index + 1] - DAYCYCLE_LIGHTING_TIMES[index] )
		light = sm.util.lerp( DAYCYCLE_LIGHTING_VALUES[index], DAYCYCLE_LIGHTING_VALUES[index + 1], p )
	else
		light = DAYCYCLE_LIGHTING_VALUES[index]
	end
	sm.render.setOutdoorLighting( light ) -- make permanent day?
end

function Game.client_showMessage( self, msg )
	sm.gui.chatMessage( msg )
end

function Game.cl_onChatCommand( self, params )
	--print("chag caramanad?",params)
	local unitSpawnNames =
	{
		woc = unit_woc,
		pwoc = unit_player_woc,
		tapebot = unit_tapebot,
		tb = unit_tapebot,
		redtapebot = unit_tapebot_red,
		rtb = unit_tapebot_red,
		totebot = unit_totebot_green,
		green = unit_totebot_green,
		t = unit_totebot_green,
		totered = unit_totebot_red,
		red = unit_totebot_red,
		tr = unit_totebot_red,
		haybot = unit_haybot,
		h = unit_haybot,
		worm = unit_worm,
		farmbot = unit_farmbot,
		f = unit_farmbot,
		cursedfarmbot = unit_cursed_farmbot,
		cf = unit_cursed_farmbot
        -- TODO: Add new "custom units here"




	}

	if params[1] == "/ammo" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_plantables_potato, quantity = ( params[2] or 50 ) } )
	elseif params[1] == "/spudgun" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = tool_spudgun, quantity = 1 } )
	elseif params[1] == "/gatling" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = tool_gatling, quantity = 1 } )
	elseif params[1] == "/shotgun" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = tool_shotgun, quantity = 1 } )
	elseif params[1] == "/sunshake" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_consumable_sunshake, quantity = 1 } )
	elseif params[1] == "/baguette" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_consumable_longsandwich, quantity = 1 } )
	elseif params[1] == "/keycard" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_survivalobject_keycard, quantity = 1 } )
	elseif params[1] == "/camera" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = sm.uuid.new( "5bbe87d3-d60a-48b5-9ca9-0086c80ebf7f" ), quantity = 1 } )
	elseif params[1] == "/powercore" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_survivalobject_powercore, quantity = 1 } )
	elseif params[1] == "/components" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_consumable_component, quantity = ( params[2] or 10 ) } )
	elseif params[1] == "/glowsticks" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_consumable_glowstick, quantity = ( params[2] or 10 ) } )









	elseif params[1] == "/god" then
		self.network:sendToServer( "sv_switchGodMode" )
	elseif params[1] == "/encrypt" then
		self.network:sendToServer( "sv_enableRestrictions", true )
	elseif params[1] == "/decrypt" then
		self.network:sendToServer( "sv_enableRestrictions", false )
	elseif params[1] == "/unlimited" then
		self.network:sendToServer( "sv_setLimitedInventory", false )
	elseif params[1] == "/limited" then
		self.network:sendToServer( "sv_setLimitedInventory", true )
	elseif params[1] == "/ambush" then
		self.network:sendToServer( "sv_ambush", { magnitude = params[2] or 1, wave = params[3] } )
	elseif params[1] == "/recreate" then
		self.network:sendToServer( "sv_recreateWorld", sm.localPlayer.getPlayer() )
	elseif params[1] == "/timeofday" then
		self.network:sendToServer( "sv_setTimeOfDay", params[2] )
	elseif params[1] == "/timeprogress" then
		self.network:sendToServer( "sv_setTimeProgress", params[2] )
	elseif params[1] == "/day" then
		self.network:sendToServer( "sv_setTimeOfDay", 0.5 )
		self.network:sendToServer( "sv_setTimeProgress", false )
	elseif params[1] == "/die" then
		self.network:sendToServer( "sv_killPlayer", { player = sm.localPlayer.getPlayer() })







	elseif params[1] == "/spawn" then
		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast( 100 )
		if rayCastValid then
			local spawnParams = {
				uuid = sm.uuid.getNil(),
				world = sm.localPlayer.getPlayer().character:getWorld(),
				position = rayCastResult.pointWorld,
				yaw = 0.0,
				amount = 1
			}
			--print("spawning params?",spawnParams)
			if unitSpawnNames[params[2]] then
				spawnParams.uuid = unitSpawnNames[params[2]]
				--print("uuid?",spawnParams.uuid,unitSpawnNames[params[2]])
			else
				print("unit does not exist")
				--spawnParams.uuid = sm.uuid.new( params[2] )
			end
			if params[3] then
				spawnParams.amount = params[3]
			end
			--print("spawning unit",spawnParams)
			self.network:sendToServer( "sv_spawnUnit", spawnParams )
		end








	elseif params[1] == "/harvestable" then
		local character = sm.localPlayer.getPlayer().character
		if character then
			local harvestableUuid = sm.uuid.getNil()
			if params[2] == "tree" then
				harvestableUuid = sm.uuid.new( "c4ea19d3-2469-4059-9f13-3ddb4f7e0b79" )
			elseif params[2] == "stone" then
				harvestableUuid = sm.uuid.new( "0d3362ae-4cb3-42ae-8a08-d3f9ed79e274" )
			elseif params[2] == "soil" then
				harvestableUuid = hvs_soil
			elseif params[2] == "fencelong" then
				harvestableUuid = sm.uuid.new( "c0f19413-6d8e-4b20-819a-949553242259" )
			elseif params[2] == "fenceshort" then
				harvestableUuid = sm.uuid.new( "144b5e79-483e-4da6-86ab-c575d0fdcd11" )
			elseif params[2] == "fencecorner" then
				harvestableUuid = sm.uuid.new( "ead875db-59d0-45f5-861e-b3075e1f8434" )
			elseif params[2] == "beehive" then
				harvestableUuid = hvs_farmables_beehive
			elseif params[2] == "cotton" then
				harvestableUuid = hvs_farmables_cottonplant
			elseif params[2] then
				harvestableUuid = sm.uuid.new( params[2] )
			end
			local spawnParams = { world = character:getWorld(), uuid = harvestableUuid, position = character.worldPosition, quat = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), sm.vec3.new( 0, 0, 1 ) )  }
			self.network:sendToServer( "sv_spawnHarvestable", spawnParams )
		end
	elseif params[1] == "/cleardebug" then
		sm.debugDraw.clear()
	elseif params[1] == "/export" then
		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast( 100 )
		if rayCastValid and rayCastResult.type == "body" then
			local importParams = {
				name = params[2],
				body = rayCastResult:getBody()
			}
			self.network:sendToServer( "sv_exportCreation", importParams )
		end
	elseif params[1] == "/import" then
		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast( 100 )
		if rayCastValid then
			local importParams = {
				world = sm.localPlayer.getPlayer().character:getWorld(),
				name = params[2],
				position = rayCastResult.pointWorld
			}
			self.network:sendToServer( "sv_importCreation", importParams )
		end
	elseif params[1] == "/noaggro" then
		if type( params[2] ) == "boolean" then
			self.network:sendToServer( "sv_n_switchAggroMode", { aggroMode = not params[2] } )
		else
			self.network:sendToServer( "sv_n_switchAggroMode", { aggroMode = not sm.game.getEnableAggro() } )
		end
	elseif params[1] == "/reloadcell" then
		local world = sm.localPlayer.getPlayer():getCharacter():getWorld()
		local player = sm.localPlayer.getPlayer()
		local pos = player.character:getWorldPosition();
		local x = params[2] or math.floor( pos.x / 64 )
		local y = params[3] or math.floor( pos.y / 64 )
		self.network:sendToServer( "sv_reloadCell", { x = x, y = y, world = world, player = player } )

	elseif params[1] == "/place" then
			local range = 7.5
			local success, result = sm.localPlayer.getRaycast( range )
			if success then
				params.aimPosition = result.pointWorld
			else
				params.aimPosition = sm.localPlayer.getRaycastStart() + sm.localPlayer.getDirection() * range
			end
			self.network:sendToServer( "sv_n_onChatCommand", params )
	elseif params[1] == "/allowclear" then
			local clearEnabled = not self.clearEnabled
			if type( params[2] ) == "boolean" then
				clearEnabled = params[2]
			end
			self.clearEnabled = clearEnabled
			sm.gui.chatMessage( "/clear is " .. ( self.clearEnabled and "Enabled" or "Disabled" ) )
	elseif params[1] == "/clear" then
			if self.clearEnabled then
				self.clearEnabled = false
				self.cl.confirmClearGui = sm.gui.createGuiFromLayout( "$GAME_DATA/Gui/Layouts/PopUp/PopUp_YN.layout" )
				self.cl.confirmClearGui:setButtonCallback( "Yes", "cl_onClearConfirmButtonClick" )
				self.cl.confirmClearGui:setButtonCallback( "No", "cl_onClearConfirmButtonClick" )
				self.cl.confirmClearGui:setText( "Title", "#{MENU_YN_TITLE_ARE_YOU_SURE}" )
				self.cl.confirmClearGui:setText( "Message", "#{MENU_YN_MESSAGE_CLEAR_MENU}" )
				self.cl.confirmClearGui:open()
			else
				sm.gui.chatMessage( "/clear is disabled. It must first be enabled with /allowclear" )
			end
	else
		self.network:sendToServer( "sv_onChatCommand", params )
	end
end

function Game.sv_reloadCell( self, params, player )
	print( "sv_reloadCell Reloading cell at {" .. params.x .. " : " .. params.y .. "}" )

	self.sv.saved.world:loadCell( params.x, params.y, player )
	self.network:sendToClients( "cl_reloadCell", params )
end




function Game.cl_reloadCell( self, params )
	print( "cl_reloadCell reloading " .. params.x .. " : " .. params.y )
	for x = -2, 2 do
		for y = -2, 2 do
			params.world:reloadCell( params.x+x, params.y+y, "cl_reloadCellTestCallback" )
		end
	end

end

function Game.cl_reloadCellTestCallback( self, world, x, y, result )
	print( "cl_reloadCellTestCallback" )
	print( "result = " .. result )
end


function Game.sv_giveItem( self, params )
	sm.container.beginTransaction()
	sm.container.collect( params.player:getInventory(), params.item, params.quantity, false )
	sm.container.endTransaction()
end

function Game.cl_n_onJoined( self, params )
	--self.cl.playIntroCinematic = params.newPlayer
end

function Game.client_onLoadingScreenLifted( self )
	g_effectManager:cl_onLoadingScreenLifted()
	self.network:sendToServer( "sv_n_loadingScreenLifted" )
	if self.cl.playIntroCinematic then
		local callbacks = {}
		--callbacks[#callbacks + 1] = { fn = "cl_onCinematicEvent", params = { cinematicName = "cinematic.survivalstart01" }, ref = self }
		--g_effectManager:cl_playNamedCinematic( "cinematic.survivalstart01", callbacks )
	end
end
	
function Game.sv_n_loadingScreenLifted( self, _, player )
    print('loading lifted')
	if not g_survivalDev then
		--QuestManager.Sv_TryActivateQuest( "quest_tutorial" )
	end
	self:sv_keepCells()
end

function Game.cl_onCinematicEvent( self, eventName, params )
	local myPlayer = sm.localPlayer.getPlayer()
	local myCharacter = myPlayer and myPlayer.character or nil
	if eventName == "survivalstart01.dramatics_standup" then
		if sm.exists( myCharacter ) then
			sm.event.sendToCharacter( myCharacter, "cl_e_onEvent", "dramatics_standup" )
		end
	elseif eventName == "survivalstart01.fadeout" then
		sm.event.sendToPlayer( myPlayer, "cl_e_startFadeToBlack", { duration = IntroFadeDuration, timeout = IntroFadeTimeout } )
	elseif eventName == "survivalstart01.fadein" then
		sm.event.sendToPlayer( myPlayer, "cl_n_endFadeToBlack", { duration = IntroEndFadeDuration } )
	end
end







function Game.sv_switchGodMode( self )
	g_godMode = not g_godMode
	self.network:sendToClients( "client_showMessage", "GODMODE: " .. ( g_godMode and "On" or "Off" ) )
end

function Game.sv_n_switchAggroMode( self, params )
	sm.game.setEnableAggro(params.aggroMode )
	self.network:sendToClients( "client_showMessage", "AGGRO: " .. ( params.aggroMode and "On" or "Off" ) )
end

function Game.sv_enableRestrictions( self, state )
	sm.game.setEnableRestrictions( state )
	self.network:sendToClients( "client_showMessage", ( state and "Restricted" or "Unrestricted"  ) )
end

function Game.sv_setLimitedInventory( self, state )
	sm.game.setLimitedInventory( state )
	self.network:sendToClients( "client_showMessage", ( state and "Limited inventory" or "Unlimited inventory"  ) )
end

function Game.sv_ambush( self, params )
	if sm.exists( self.sv.saved.world ) then
		sm.event.sendToWorld( self.sv.saved.world, "sv_ambush", params )
	end
end

function Game.sv_recreateWorld( self, player )
    print("SV RECREATEWORLD")
	local character = player:getCharacter()
	if character:getWorld() == self.sv.saved.world then
		self.sv.saved.world:destroy()
		self.sv.saved.world = sm.world.createWorld( "$CONTENT_DATA/Scripts/World.lua", "world", { dev = g_survivalDev })
		self.storage:save( self.sv.saved )

		local params = { pos = character:getWorldPosition(), dir = character:getDirection() }
		self.sv.saved.world:loadCell( math.floor( params.pos.x/64 ), math.floor( params.pos.y/64 ), player, "sv_recreatePlayerCharacter", params ) -- loads cell then spawn player via callback

		self.network:sendToClients( "client_showMessage", "Recreating world" )
	else
		self.network:sendToClients( "client_showMessage", "Recreate world only allowed for world" )
	end
end

function Game.sv_setTimeOfDay( self, timeOfDay )
	if timeOfDay then
		self.sv.time.timeOfDay = timeOfDay
		self.sv.syncTimer.count = self.sv.syncTimer.ticks -- Force sync
	end
	self.network:sendToClients( "client_showMessage", ( "Time of day set to "..self.sv.time.timeOfDay ) )
end

function Game.sv_setTimeProgress( self, timeProgress )
	if timeProgress ~= nil then
		self.sv.time.timeProgress = timeProgress
		self.sv.syncTimer.count = self.sv.syncTimer.ticks -- Force sync
	end
	self.network:sendToClients( "client_showMessage", ( "Time scale set to "..( self.sv.time.timeProgress and "on" or "off ") ) )
end

function Game.sv_killPlayer( self, params )
	params.damage = 9999
	sm.event.sendToPlayer( params.player, "sv_e_receiveDamage", params )
end

-- TODO: check if/why Cells are being unloaded on player death
-- TODO: make superchat and/or members have special color names/chats?
-- TODO: just make validation go to usernames too to reduce even more post python spam
-- TODO: add explosion command that makes cow exploade
-- TODO: add same stuff to bots (but add attack)
-- TODO: figure out gamemodes

function Game.sv_spawnUnit( self, params )
	--print("Spawning unit",params)
	sm.event.sendToWorld( params.world, "sv_e_spawnUnit", params )
end

function Game.sv_unitChat( self, params )
	if g_unitManager then
		g_unitManager:sv_makeSpeak(params)
	end
end

function Game.sv_sendUnitFollow(self,params) -- sends event to unit
	if g_unitManager then
		g_unitManager:sv_makeFollow(params)
	end
end

function Game.sv_sendUnitAttack(self,params) -- sends event to unit
	--print('got unit attack',params)
	if g_unitManager then
		g_unitManager:sv_makeAttack(params)
	end
end

function Game.sv_sendUnitGoto(self,params) -- sends event to unit
	if g_unitManager then
		g_unitManager:sv_makeGoto(params)
	end
end

function Game.sv_sendUnitStop(self,params) -- sends event to unit
	if g_unitManager then
		g_unitManager:sv_makeStop(params)
	end
end

function Game.sv_sendUnitFlee(self,params)
	if g_unitManager then
		g_unitManager:sv_makeFlee(params)
	end
end

function Game.sv_sendUnitExplode(self,params) -- explodes cow but is world unit i think
	if g_unitManager then
		g_unitManager:sv_makeExplode(params)
	end
	
end
-- Get data from manager
function Game.getSpawnedChatters(self)
	if g_unitManager then
		local spawnedChatters = g_unitManager:sv_get_spawnedChatters()
		if spawnedChatters then
			return spawnedChatters
		end
	end
end


function Game.nameUnitServerTest(self,params)
	print('nameunitserver',params)
	local unit_username = params['username']
    local all_units = params['units']
    if not unit_username then return end
    if not all_units or #all_units == 0 then return end
    for _, allyUnit in ipairs( all_units ) do
		if sm.exists( allyUnit )then -- does not check for insameWorld or not self (unsure what that will do)
			local unitData = allyUnit:getPublicData()
			if unitData and unitData['username'] then
				if tostring(unitData['username']) == tostring(unit_username) then
					return allyUnit
				end
			end
		end
	end
end

function Game.sv_findNamedUnit(self,params) -- finds unit among all npc and pcs using username in its public data
	print('sv game findingNameUnit',params)
    local unit_username = params['username']
    local all_units = params['units']
    if not unit_username then return end
    if not all_units or #all_units == 0 then return end
    for _, allyUnit in ipairs( all_units ) do
		if sm.exists( allyUnit )then -- does not check for insameWorld or not self (unsure what that will do)
			local unitData = allyUnit:getPublicData()
			if unitData and unitData['username'] then
				if tostring(unitData['username']) == tostring(unit_username) then
					return allyUnit
				end
			end
		end
	end
end

function Game.sv_spawnHarvestable( self, params )
	sm.event.sendToWorld( params.world, "sv_spawnHarvestable", params )
end

function Game.sv_exportCreation( self, params )
	local obj = sm.json.parseJsonString( sm.creation.exportToString( params.body ) )
	sm.json.save( obj, "$SURVIVAL_DATA/LocalBlueprints/"..params.name..".blueprint" )
end

function Game.sv_importCreation( self, params )
	sm.creation.importFromFile( params.world, "$SURVIVAL_DATA/LocalBlueprints/"..params.name..".blueprint", params.position )
end

function Game.sv_onChatCommand( self, params, player )
	if params[1] == "/tumble" then
		if params[2] ~= nil then
			player.character:setTumbling( params[2] )
		else
			player.character:setTumbling( not player.character:isTumbling() )
		end
		if player.character:isTumbling() then
			self.network:sendToClients( "client_showMessage", "Player is tumbling" )
		else
			self.network:sendToClients( "client_showMessage", "Player is not tumbling" )
		end

	elseif params[1] == "/sethp" then
		sm.event.sendToPlayer( player, "sv_e_debug", { hp = params[2] } )

	elseif params[1] == "/setwater" then
		sm.event.sendToPlayer( player, "sv_e_debug", { water = params[2] } )

	elseif params[1] == "/setfood" then
		sm.event.sendToPlayer( player, "sv_e_debug", { food = params[2] } )

	elseif params[1] == "/goto" then
		local pos
		if params[2] == "here" then
			pos = player.character:getWorldPosition()
		elseif params[2] == "start" then
			pos = START_AREA_SPAWN_POINT

		else
			self.network:sendToClient( player, "client_showMessage", "Unknown place" )
		end
		if pos then
			local cellX, cellY = math.floor( pos.x/64 ), math.floor( pos.y/64 )
			if not sm.exists( self.sv.saved.world ) then
				sm.world.loadWorld( self.sv.saved.world )
			end
			self.sv.saved.world:loadCell( cellX, cellY, player, "sv_recreatePlayerCharacter", { pos = pos, dir = player.character:getDirection() } )
		end

	elseif params[1] == "/respawn" then
		sm.event.sendToPlayer( player, "sv_e_respawn" )

	elseif params[1] == "/printglobals" then
		print( "Globals:" )
		for k,_ in pairs(_G) do
			print( k )
		end

	elseif params[1] == "/activatequest" then
		local questName = params[2]
		if questName then
			QuestManager.Sv_ActivateQuest( questName )
		end
	elseif params[1] == "/completequest" then
		local questName = params[2]
		if questName then
			QuestManager.Sv_CompleteQuest( questName )
		end
	
	elseif params[1] == "/noaggrocreations" then
		local aggroCreations = not g_unitManager:sv_getHostSettings().aggroCreations
		if type( params[2] ) == "boolean" then
			aggroCreations = not params[2]
		end
		g_unitManager:sv_setHostSettings( { aggroCreations = aggroCreations } )
		self.network:sendToClients( "client_showMessage", "AGGRO CREATIONS: " .. ( aggroCreations and "On" or "Off" ) )
	elseif params[1] == "/popcapsules" then
		g_unitManager:sv_openCapsules( params[2] )
	
	elseif params[1] == "/keepcell" then
		local x = math.floor( player.character.worldPosition.x / 64 )
		local y = math.floor( player.character.worldPosition.y / 64 )
		self:sv_keepCell(x,y,"usercommand") -- pass player too?

	elseif params[1] == "/keepcells" then -- loads all cells
		local x = math.floor( player.character.worldPosition.x / 64 )
		local y = math.floor( player.character.worldPosition.y / 64 )
		self:sv_keepCells("usercommand") -- pass player too?

	elseif params[1] == "/deletecell" then -- delete one cell
		local x = math.floor( player.character.worldPosition.x / 64 )
		local y = math.floor( player.character.worldPosition.y / 64 )
		self:sv_deleteCell(player,x,y)
		print("REmoved cell",index)
	elseif params[1] == "/deletecells" then
		print("deleting all cells")
		self:sv_deleteCells(player)
	
	elseif params[1] == "/listcells" then
		for _,cell in ipairs(self.sv.saved.keptCells) do
			print( cell) -- calls singular deleteCell
		end
	else
		params.player = player
		if sm.exists( player.character ) then
			-- could hhonstly put worldsaving and loading here...
			sm.event.sendToWorld( player.character:getWorld(), "sv_e_onChatCommand", params )
		end
	end
end

-- cell storagae and load
-- CELL LOAD KEEPING ALGORITHM
-- keep list of all saved space
-- unitManager or for every unit in map
-- add all cells around bot to (savedspaces)
-- If there are cells not included, remove from space? (cant force unload)
-- possibly just load all cells really

function Game.sv_loadCell(self,x,y)
	-- make sure cell isnt already loaded...
	if not self:isCellLoaded(x,y) then
		--print("loading cell",x,y) -- if debug on
		self.sv.saved.world:loadCell( x, y,nil)
		self:setCellLoaded(x,y)
	else
		print("Cell already loaded or error finding cell, skipping")
	end
end

function Game.isCellLoaded(self,x,y)
	local index = self:findStoredCell(x,y)
	if index == nil then  print("Cell does not exist") return true end
	loaded =  self.sv.saved.keptCells[index].loaded -- could just return cell already
	--print("cell loaded?",x,y,loaded)
	if loaded then
		return true
	else
		return false
	end
end

function Game.setCellLoaded(self,x,y) -- sets cell as loaded
	local index = self:findStoredCell(x,y)
	if index == nil then  print("Cell does not exist") return true end
	self.sv.saved.keptCells[index].loaded = true -- could just return cell already
	if loaded then
		return true
	else
		return false
	end
end


function Game.sv_keepCell(self,x,y,reason) -- TODO: Make all of these into sv_network calls? -- dont need player>
	-- has callback also can pass player to replace 'nil' if needed
	local cellData = {["x"] = x, ["y"] = y, ["reason"] = reason, ['loaded'] = false}
	local index = self:findStoredCell(x,y)
	if index == nil then -- makes sure is unique
		print("Keeping cell",x,y)
		table.insert( self.sv.saved.keptCells, cellData )
	else
		print("Cell already sved")
	end
	-- doesnt call load on cell
end

function Game.sv_keepCells(self,reason) -- looks over list and loads all stored cells -- DONOT USE
	print("loading all cell",cell) -- TODO: Call this after everything is set up
	for _,cell in ipairs(self.sv.saved.keptCells) do
		x = cell.x
		y = cell.y
		self:sv_loadCell( x, y)
	end
end

function Game.sv_deleteCell(self,x,y) -- releases individual cells
	print("deleting cell",x,y)
	local index = self:findStoredCell(x,y)
	--self.sv.saved.world:releaseCell(x,y) --TODO: function not found, find out how to do this/remove player dummy n stuff
	table.remove( self.sv.saved.keptCells, index )
end


function Game.sv_deleteCells(self) -- Deletes all cells
	print("deleting all cells")
	for _,cell in ipairs(self.sv.saved.keptCells) do
		self:deleteCell( cell.x, cell.y) -- calls singular deleteCell
	end
end


function Game.findStoredCell(self,x,y) -- may have issues being called from game script and not world script...
	--print("finding?",self.sv.saved.keptCells,#self.sv.saved.keptCells)
	for i=1, #self.sv.saved.keptCells do 
		local cell  = self.sv.saved.keptCells [i]
		--print("Looking for cell",i,cell)
		if cell.x == x and cell.y == y then
			--print("Found cell",cell,i)
			return i
		end
	end
end


function Game.sv_e_loadCell( self, params )
	-- Called just in case things need to happen (auto unloads player dummy)
	--self:sv_keepCells()
 end


 function Game.sv_e_unloadCell( self, params ) -- seems to not unload any cells
	--print("game server unloadcell load",params)
	local index = self:findStoredCell(params.x,params.y)
	if index ~= nil then
		--print("Found cell wanted to saved",index,params.x,params.y)
		self:sv_loadCell(params.x,params.y)
	end
 end

function Game.server_onPlayerJoined( self, player, newPlayer )
	print( player.name, "joined the game" )

	if newPlayer then --Player is first time joiners
		local inventory = player:getInventory()

		sm.container.beginTransaction()

		if g_survivalDev then
			--Hotbar
			sm.container.setItem( inventory, 0, tool_sledgehammer, 1 )
			sm.container.setItem( inventory, 1, tool_spudgun, 1 )
			sm.container.setItem( inventory, 7, obj_plantables_potato, 50 )
			sm.container.setItem( inventory, 8, tool_lift, 1 )
			sm.container.setItem( inventory, 9, tool_connect, 1 )

			--Actual inventory
			sm.container.setItem( inventory, 10, tool_paint, 1 )
			sm.container.setItem( inventory, 11, tool_weld, 1 )
		else
			sm.container.setItem( inventory, 0, tool_sledgehammer, 1 )
			sm.container.setItem( inventory, 1, tool_lift, 1 )
		end

		sm.container.endTransaction()

		local spawnPoint = g_survivalDev and SURVIVAL_DEV_SPAWN_POINT or START_AREA_SPAWN_POINT -- YEEEp
        --print("SPawn point??",SURVIVAL_DEV_SPAWN_POINT,START_AREA_SPAWN_POINT)
        spawnPoint = sm.vec3.new(0,0,10)
		if not sm.exists( self.sv.saved.world ) then
			sm.world.loadWorld( self.sv.saved.world )
		end
		self.sv.saved.world:loadCell( math.floor( spawnPoint.x/64 ), math.floor( spawnPoint.y/64 ), player, "sv_createNewPlayer" )
		self.network:sendToClient( player, "cl_n_onJoined", { newPlayer = newPlayer } )
	else
		local inventory = player:getInventory()

		local sledgehammerCount = sm.container.totalQuantity( inventory, tool_sledgehammer )
		if sledgehammerCount == 0 then
			sm.container.beginTransaction()
			sm.container.collect( inventory, tool_sledgehammer, 1 )
			sm.container.endTransaction()
		elseif sledgehammerCount > 1 then
			sm.container.beginTransaction()
			sm.container.spend( inventory, tool_sledgehammer, sledgehammerCount - 1 )
			sm.container.endTransaction()
		end

		local tool_lift_creative = sm.uuid.new( "5cc12f03-275e-4c8e-b013-79fc0f913e1b" )
		local creativeLiftCount = sm.container.totalQuantity( inventory, tool_lift_creative )
		if creativeLiftCount > 0 then
			sm.container.beginTransaction()
			sm.container.spend( inventory, tool_lift_creative, creativeLiftCount )
			sm.container.endTransaction()
		end

		local liftCount = sm.container.totalQuantity( inventory, tool_lift )
		if liftCount == 0 then
			sm.container.beginTransaction()
			sm.container.collect( inventory, tool_lift, 1 )
			sm.container.endTransaction()
		elseif liftCount > 1 then
			sm.container.beginTransaction()
			sm.container.spend( inventory, tool_lift, liftCount - 1 )
			sm.container.endTransaction()
		end
	end
	if player.id > 1 then --Too early for self. Questmanager is not created yet...
		--QuestManager.Sv_OnEvent( QuestEvent.PlayerJoined, { player = player } )
	end
	g_unitManager:sv_onPlayerJoined( player )
end

function Game.server_onPlayerLeft( self, player )
	print( player.name, "left the game" )
	if player.id > 1 then
		--QuestManager.Sv_OnEvent( QuestEvent.PlayerLeft, { player = player } )
	end
	--g_elevatorManager:sv_onPlayerLeft( player )

end


function Game.cl_onClearConfirmButtonClick( self, name )
	if name == "Yes" then
		self.cl.confirmClearGui:close()
		self.network:sendToServer( "sv_clear" )
	elseif name == "No" then
		self.cl.confirmClearGui:close()
	end
	self.cl.confirmClearGui = nil
end

function Game.sv_clear( self, _, player )
	if player.character and sm.exists( player.character ) then
		sm.event.sendToWorld( player.character:getWorld(), "sv_e_clear" )
	end
end


function Game.sv_createNewPlayer( self, world, x, y, player )
	local params = { player = player, x = x, y = y }
	sm.event.sendToWorld( self.sv.saved.world, "sv_spawnNewCharacter", params )
end



function Game.sv_recreatePlayerCharacter( self, world, x, y, player, params )
	local yaw = math.atan2( params.dir.y, params.dir.x ) - math.pi/2
	local pitch = math.asin( params.dir.z )
	local newCharacter = sm.character.createCharacter( player, self.sv.saved.world, params.pos, yaw, pitch )
	player:setCharacter( newCharacter )
	print( "Recreate character in new world" )
	print( params )
end

function Game.sv_e_respawn( self, params )
	if params.player.character and sm.exists( params.player.character ) then
		g_respawnManager:sv_requestRespawnCharacter( params.player )
	else
		local spawnPoint =  sm.vec3.new(0,0,20) --g_survivalDev and SURVIVAL_DEV_SPAWN_POINT or START_AREA_SPAWN_POINT
		if not sm.exists( self.sv.saved.world ) then
			sm.world.loadWorld( self.sv.saved.world )
		end
		self.sv.saved.world:loadCell( math.floor( spawnPoint.x/64 ), math.floor( spawnPoint.y/64 ), params.player, "sv_createNewPlayer" )
	end
end

function Game.sv_loadedRespawnCell( self, world, x, y, player )
	g_respawnManager:sv_respawnCharacter( player, world )
end

function Game.sv_e_onSpawnPlayerCharacter( self, player )
	if player.character and sm.exists( player.character ) then
		g_respawnManager:sv_onSpawnCharacter( player )
		g_beaconManager:sv_onSpawnCharacter( player )
	else
		sm.log.warning("Game.sv_e_onSpawnPlayerCharacter for a character that doesn't exist")
	end
end

function Game.sv_e_markBag( self, params )
	if sm.exists( params.world ) then
		sm.event.sendToWorld( params.world, "sv_e_markBag", params )
	else
		sm.log.warning("Game.sv_e_markBag in a world that doesn't exist")
	end
end

function Game.sv_e_unmarkBag( self, params )
	if sm.exists( params.world ) then
		sm.event.sendToWorld( params.world, "sv_e_unmarkBag", params )
	else
		sm.log.warning("Game.sv_e_unmarkBag in a world that doesn't exist")
	end
end

-- Beacons
function Game.sv_e_createBeacon( self, params )
	if sm.exists( params.beacon.world ) then
		sm.event.sendToWorld( params.beacon.world, "sv_e_createBeacon", params )
	else
		sm.log.warning( "Game.sv_e_createBeacon in a world that doesn't exist" )
	end
end

function Game.sv_e_destroyBeacon( self, params )
	if sm.exists( params.beacon.world ) then
		sm.event.sendToWorld( params.beacon.world, "sv_e_destroyBeacon", params )
	else
		sm.log.warning( "Game.sv_e_destroyBeacon in a world that doesn't exist" )
	end
end

function Game.sv_e_unloadBeacon( self, params )
	if sm.exists( params.beacon.world ) then
		sm.event.sendToWorld( params.beacon.world, "sv_e_unloadBeacon", params )
	else
		sm.log.warning( "Game.sv_e_unloadBeacon in a world that doesn't exist" )
	end
end




-- Custom unit things 
function Game.sv_e_unit_killed( self, params ) -- params is unit id
	--print("Game killing unit",params)
	if g_unitManager then
		g_unitManager:sv_removeChatterFromGame(params)
	end
end
































