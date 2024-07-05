--dofile( "$SURVIVAL_DATA/Scripts/game/managers/UnitManager.lua" ) -- from CreativeBase

dofile( "$SURVIVAL_DATA/Scripts/game/managers/FireManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/PesticideManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_spawns.lua" ) -- TODO: Change this to content evo stuff
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestEntityManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/EventManager.lua" ) -- TODO: analyze this for things?
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WaterManager.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/CreativePathNodeManager.lua")

World = class( nil )
World.terrainScript = "$CONTENT_DATA/Scripts/terrain.lua"
World.cellMinX = -16
World.cellMaxX = 16
World.cellMinY = -16
World.cellMaxY = 16
World.worldBorder = true

World.groundMaterialSet = "$GAME_DATA/Terrain/Materials/gnd_standard_materialset.json"
World.enableSurface = true
World.enableAssets = true
World.enableClutter = true
World.enableNodes = true
World.enableCreations = true
World.enableHarvestables = true
World.enableKinematics = true


function World.server_onCreate( self )
    print("World.server_onCreate",self)
	--print("world sv?",self.sv)
	self.sv = {}
	--print("world self.sv",self.sv)
	self.fireManager = FireManager()
	self.fireManager:sv_onCreate( self )

	self.waterManager = WaterManager()
	self.waterManager:sv_onCreate( self )

	self.pesticideManager = PesticideManager()
	self.pesticideManager:sv_onCreate()

	self.sv.pathNodeManager = CreativePathNodeManager()
	self.sv.pathNodeManager:sv_onCreate( self )

    self.foreignConnections = sm.storage.load( STORAGE_CHANNEL_FOREIGN_CONNECTIONS )
	if self.foreignConnections == nil then
		self.foreignConnections = {}
	end

	self.keptCells = {} -- list of all cells kept
end

function World.client_onCreate( self )
	if self.fireManager == nil then
		assert( not sm.isHost )
		self.fireManager = FireManager()
	end
	self.fireManager:cl_onCreate( self )

	if self.waterManager == nil then
		assert( not sm.isHost )
		self.waterManager = WaterManager()
	end
	self.waterManager:cl_onCreate()

	if self.pesticideManager == nil then
		assert( not sm.isHost )
		self.pesticideManager = PesticideManager()
	end
	self.pesticideManager:cl_onCreate()
end

function World.server_onFixedUpdate( self )
	self.fireManager:sv_onFixedUpdate()
	self.waterManager:sv_onFixedUpdate()
	self.pesticideManager:sv_onWorldFixedUpdate( self )
    g_unitManager:sv_onWorldFixedUpdate( self )
end

function World.client_onFixedUpdate( self )
	self.waterManager:cl_onFixedUpdate()
    g_unitManager:cl_onWorldUpdate( self, deltaTime )
end

function World.client_onUpdate( self, dt )
	g_effectManager:cl_onWorldUpdate( self )
end

function World.sv_n_fireMsg( self, msg )
	self.fireManager:sv_handleMsg( msg )
end

function World.cl_n_fireMsg( self, msg )
	self.fireManager:cl_handleMsg( msg )
end

function World.cl_n_pesticideMsg( self, msg )
	self.pesticideManager[msg.fn]( self.pesticideManager, msg )
end



function World.cl_n_unitMsg( self, msg )
	g_unitManager[msg.fn]( g_unitManager, msg )
end

function World.sv_e_spawnUnit( self, params ) -- TODO: THis could effect mod, stuff begins here (event called here)
	
	for i = 1, params.amount do
		local newUnit = sm.unit.createUnit( params.uuid, params.position, params.yaw, params ) -- just send extra data straight to unit
		if params.chatterData then
			g_unitManager:sv_UnitSpawned(self,newUnit,params)
		end
	end
end

function World.sv_spawnHarvestable( self, params )
	local harvestable = sm.harvestable.createHarvestable( params.uuid, params.position, params.quat )
	if params.harvestableParams then
		harvestable:setParams( params.harvestableParams )
	end
end

function World.sv_spawnBlock( self, params )
	print("block built")
	local block = sm.construction.buildBlock( params.uuid, params.position)
	print("block built")
end


function World.server_onCellCreated( self, x, y ) -- Believe this function only spawns random units on created cell
    --print("ON Cell Created??")
	local tags = sm.cell.getTags( x, y )
	local cell = { x = x, y = y, worldId = self.world.id, isStartArea = valueExists( tags, "STARTAREA" ), isPoi = valueExists( tags, "POI" ) }

	self.fireManager:sv_onCellLoaded( x, y )
	self.waterManager:sv_onCellLoaded( x, y )
	self.sv.pathNodeManager:sv_loadPathNodesOnCell( x, y ) -- TODO: Remove this or remove below code (both are loading path nodes kinda)
	-- Randomize stacks
	local stackedList = sm.cell.getInteractablesByAnyUuid( x, y, {
		obj_consumable_gas, obj_consumable_battery,
		obj_consumable_fertilizer, obj_consumable_chemical,
		obj_consumable_inkammo,
		obj_consumable_soilbag,
		obj_plantables_potato,
		obj_seed_banana, obj_seed_blueberry, obj_seed_orange, obj_seed_pineapple,
		obj_seed_carrot, obj_seed_redbeet, obj_seed_tomato, obj_seed_broccoli,
		obj_seed_potato
	} )
	local stackFn = {
		[tostring(obj_consumable_fertilizer)] = randomStackAmount20,
		[tostring(obj_consumable_inkammo)] = function() return randomStackAmount( 32, 48, 64 ) end,
		[tostring(obj_consumable_soilbag)] = randomStackAmountAvg2,
		[tostring(obj_plantables_potato)] = randomStackAmountAvg10,
	}

	for _,stacked in ipairs( stackedList ) do
		local fn = stackFn[tostring( stacked.shape.uuid )]
		if fn then
			stacked.shape.stackedAmount = fn()
		else
			stacked.shape.stackedAmount = randomStackAmount5()
		end
	end

	local tags = sm.cell.getTags( x, y )
	self:sv_loadSpawnersOnCell( x, y )
	local cell = { x = x, y = y, worldId = self.world.id,  isStartArea = valueExists( tags, "STARTAREA" ), isPoi = valueExists( tags, "POI" ) }
	if not cell.isStartArea then
		SpawnFromNodeOnCellLoaded( cell, "TAPEBOT" )
		if x > -8 or y > -8 or valueExists( tags, "SCRAPYARD" ) then
			SpawnFromNodeOnCellLoaded( cell, "FARMBOT" )
		end
	end
	g_unitManager:sv_onWorldCellLoaded( self, x, y )
	--self.packingStationManager:sv_onCellLoaded( x, y )

	if getDayCycleFraction() == 0.0 then
		--g_unitManager:sv_requestTempUnitsOnCell( x, y )
	end

	local result, msg = pcall( function() self:sv_loadPathNodesOnCell( x, y ) end )
	if not result then
		sm.log.error( "Failed to load path nodes on cell: "..msg )
	end
end





function World.client_onCellLoaded( self, x, y )
    --print("Client onCellloaded")
	self.fireManager:cl_onCellLoaded( x, y )
	self.waterManager:cl_onCellLoaded( x, y )
	g_effectManager:cl_onWorldCellLoaded( self, x, y )
	--QuestEntityManager.Cl_OnWorldCellLoaded( self, x, y )
end

function World.server_onCellLoaded( self, x, y )
	--print(self)
	sm.event.sendToGame("sv_e_loadCell",{['x'] = x, ['y'] = y})
    --print("Server oncellloaded")
	local tags = sm.cell.getTags( x, y )
	local cell = { x = x, y = y, worldId = self.world.id, isStartArea = valueExists( tags, "STARTAREA" ), isPoi = valueExists( tags, "POI" ) }
	
	self.fireManager:sv_onCellReloaded( x, y )
	self.waterManager:sv_onCellReloaded( x, y ) -- missing unitmanager cell reload??
end

function reloadCallback( world, x, y, result)
	print("Relaod callbacl",x,y,result)
	return result
end

function World.server_onCellUnloaded( self, x, y )
	--print(self) -- Unit manager
	sm.event.sendToGame("sv_e_unloadCell",{['x'] = x, ['y'] = y}) -- may have issues with fire/water manager for fast load/unload
	--QuestEntityManager.Sv_OnWorldCellUnloaded( self, x, y )
	self.fireManager:sv_onCellUnloaded( x, y )
	self.waterManager:sv_onCellUnloaded( x, y )
end

function World.client_onCellUnloaded( self, x, y )
    --print("client cell unlaodded")
	g_effectManager:cl_onWorldCellUnloaded( self, x, y )
	--QuestEntityManager.Cl_OnWorldCellUnloaded( self, x, y )
	self.waterManager:cl_onCellUnloaded( x, y )
end

function World.sv_e_markBag( self, params )
	self.network:sendToClient( params.player, "cl_n_markBag", params )
end

function World.cl_n_markBag( self, params )
	g_respawnManager:cl_markBag( params )
end

function World.sv_e_unmarkBag( self, params )
	self.network:sendToClient( params.player, "cl_n_unmarkBag", params )
end

function World.cl_n_unmarkBag( self, params )
	g_respawnManager:cl_unmarkBag( params )
end

-- Beacons
function World.sv_e_createBeacon( self, params )
	if params.player and sm.exists( params.player ) then
		self.network:sendToClient( params.player, "cl_n_createBeacon", params )
	else
		self.network:sendToClients( "cl_n_createBeacon", params )
	end
end

function World.cl_n_createBeacon( self, params )
	g_beaconManager:cl_createBeacon( params )
end

function World.sv_e_destroyBeacon( self, params )
	if params.player and sm.exists( params.player ) then
		self.network:sendToClient( params.player, "cl_n_destroyBeacon", params )
	else
		self.network:sendToClients( "cl_n_destroyBeacon", params )
	end
end

function World.cl_n_destroyBeacon( self, params )
	g_beaconManager:cl_destroyBeacon( params )
end

function World.sv_e_unloadBeacon( self, params )
	if params.player and sm.exists( params.player ) then
		self.network:sendToClient( params.player, "cl_n_unloadBeacon", params )
	else
		self.network:sendToClients( "cl_n_unloadBeacon", params )
	end
end

function World.cl_n_unloadBeacon( self, params )
	g_beaconManager:cl_unloadBeacon( params )
end

function World.server_onProjectileFire( self, firePos, fireVelocity, _, attacker, projectileUuid )
	if isAnyOf( projectileUuid, g_potatoProjectiles ) then
		local units = sm.unit.getAllUnits()
		for i, unit in ipairs( units ) do
			if InSameWorld( self.world, unit ) then
				sm.event.sendToUnit( unit, "sv_e_worldEvent", { eventName = "projectileFire", firePos = firePos, fireVelocity = fireVelocity, projectileUuid = projectileUuid, attacker = attacker })
			end
		end
	end
end

function World.server_onInteractableCreated( self, interactable )
	g_unitManager:sv_onInteractableCreated( interactable )
	--QuestEntityManager.Sv_OnInteractableCreated( interactable )
end

function World.server_onInteractableDestroyed( self, interactable )
	g_unitManager:sv_onInteractableDestroyed( interactable )
	--QuestEntityManager.Sv_OnInteractableDestroyed( interactable )
end

function World.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, target, projectileUuid )

	-- Spawn loot from projectiles with loot user data
	if userData and userData.lootUid then
		local normal = -hitVelocity:normalize()
		local zSignOffset = math.min( sign( normal.z ), 0 ) * 0.5
		local offset = sm.vec3.new( 0, 0, zSignOffset )
		local lootHarvestable = sm.harvestable.createHarvestable( hvs_loot, hitPos + offset, sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), sm.vec3.new( 0, 0, 1 ) ) )
		lootHarvestable:setParams( { uuid = userData.lootUid, quantity = userData.lootQuantity, epic = userData.epic  } )
	end

	-- Notify units about projectile hit
	if isAnyOf( projectileUuid, g_potatoProjectiles ) then -- TODO: effects units (more than just potato projectiles addd tape n stuff too)
		local units = sm.unit.getAllUnits()
		for i, unit in ipairs( units ) do
			if InSameWorld( self.world, unit ) then
				sm.event.sendToUnit( unit, "sv_e_worldEvent", { eventName = "projectileHit", hitPos = hitPos, hitTime = hitTime, hitVelocity = hitVelocity, attacker = attacker, damage = damage })
			end
		end
	end

	if projectileUuid == projectile_pesticide then
		local forward = sm.vec3.new( 0, 1, 0 )
		local randomDir = forward:rotateZ( math.random( 0, 359 ) )
		local effectPos = hitPos
		local success, result = sm.physics.raycast( hitPos + sm.vec3.new( 0, 0, 0.1 ), hitPos - sm.vec3.new( 0, 0, PESTICIDE_SIZE.z * 0.5 ), nil, sm.physics.filter.static + sm.physics.filter.dynamicBody )
		if success then
			effectPos = result.pointWorld + sm.vec3.new( 0, 0, PESTICIDE_SIZE.z * 0.5 )
		end
		self.pesticideManager:sv_addPesticide( self, effectPos, sm.vec3.getRotation( forward, randomDir ) )
	end

	if projectileUuid == projectile_glowstick then
		sm.harvestable.createHarvestable( hvs_remains_glowstick, hitPos, sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), hitVelocity:normalize() ) )
	end

	if projectileUuid == projectile_explosivetape then
		sm.physics.explode( hitPos, 500, 20, 6.0, 25.0, "RedTapeBot - ExplosivesHit" )
	end


end


function World.sv_e_clear( self )
	for _, body in ipairs( sm.body.getAllBodies() ) do
		for _, shape in ipairs( body:getShapes() ) do
			shape:destroyShape()
		end
	end
end


function World.server_onMelee( self, hitPos, attacker, target, damage, power, hitDirection, hitNormal )
	-- print("Melee hit in Overworld!")
	-- print(hitPos)
	-- print(attacker)
	-- print(damage)
	-- print(target)

	if attacker and sm.exists( attacker ) and target and sm.exists( target ) then
		if type( target ) == "Shape" and type( attacker) == "Unit" then
			local targetPlayer = nil
			if target.interactable and target.interactable:hasSeat() then
				local targetCharacter = target.interactable:getSeatCharacter()
				if targetCharacter then
					targetPlayer = targetCharacter:getPlayer()
				end
			end
			if targetPlayer then
				sm.event.sendToPlayer( targetPlayer, "sv_e_receiveDamage", { damage = damage } )
			end

		end
	end
end

function World.server_onCollision( self, objectA, objectB, collisionPosition, objectAPointVelocity, objectBPointVelocity, collisionNormal )
	g_unitManager:sv_onWorldCollision( self, objectA, objectB, collisionPosition, objectAPointVelocity, objectBPointVelocity, collisionNormal )
end

function World.sv_e_onChatCommand( self, params ) -- server event and not server callback
	if params[1] == "/starterkit" then
		local chest = sm.shape.createPart( obj_container_smallchest, params.player.character.worldPosition + sm.vec3.new( 0, 0, 2 ), sm.quat.identity() )
		chest.color = sm.color.new( 1, 0.5, 0 )
		local container = chest.interactable:getContainer()

		sm.container.beginTransaction()
		sm.container.collect( container, blk_scrapwood, 100 )
		sm.container.collect( container, jnt_bearing, 6 )
		sm.container.collect( container, obj_scrap_smallwheel, 4 )
		sm.container.collect( container, obj_scrap_driverseat, 1 )
		sm.container.collect( container, tool_connect, 1 )
		sm.container.collect( container, obj_scrap_gasengine, 1 )
		sm.container.collect( container, obj_consumable_gas, 10 )
		sm.container.endTransaction()

	elseif params[1] == "/mechanicstartkit" then
		local chest = sm.shape.createPart( obj_container_smallchest, params.player.character.worldPosition + sm.vec3.new( 0, 0, 2 ), sm.quat.identity() )
		chest.color = sm.color.new( 0, 0, 0 )
		local container = chest.interactable:getContainer()

		sm.container.beginTransaction()
		sm.container.collect( container, obj_consumable_sunshake, 5 )

		sm.container.collect( container, blk_scrapwood, 256 )
		sm.container.collect( container, blk_scrapwood, 256 )
		sm.container.collect( container, blk_scrapmetal, 256 )
		sm.container.collect( container, blk_glass, 20 )

		sm.container.collect( container, obj_consumable_component, 10 )
		sm.container.collect( container, obj_consumable_gas, 20 )
		sm.container.collect( container, obj_resource_circuitboard, 10 )
		sm.container.collect( container, obj_resource_circuitboard, 10 )
		sm.container.collect( container, obj_consumable_chemical, 20 )
		sm.container.collect( container, obj_resource_corn, 20 )
		sm.container.collect( container, obj_resource_flower, 20 )

		sm.container.collect( container, obj_consumable_soilbag, 15 )
		sm.container.collect( container, obj_plantables_carrot, 10 )
		sm.container.collect( container, obj_plantables_tomato, 10 )
		sm.container.collect( container, obj_seed_tomato, 20 )
		sm.container.collect( container, obj_seed_carrot, 20 )
		sm.container.collect( container, obj_seed_redbeet, 10 )
		sm.container.endTransaction()
	elseif params[1] == "/tutorialstartkit" then
		local chest = sm.shape.createPart( obj_container_smallchest, params.player.character.worldPosition + sm.vec3.new( 0, 0, 2 ), sm.quat.identity() )
		chest.color = sm.color.new( 1, 1, 1 )
		local container = chest.interactable:getContainer()

		sm.container.beginTransaction()
		sm.container.collect( container, sm.uuid.new( "e83a22c5-8783-413f-a199-46bc30ca8dac"), 1 ) -- Tutorial part
		sm.container.collect( container, blk_scrapwood, 38 )
		sm.container.collect( container, jnt_bearing, 6 )
		sm.container.collect( container, obj_scrap_smallwheel, 4 )
		sm.container.collect( container, obj_scrap_driverseat, 1 )
		sm.container.collect( container, obj_scrap_gasengine, 1 )

		sm.container.collect( container, tool_connect, 1 )
		sm.container.collect( container, obj_consumable_gas, 4 )

		sm.container.endTransaction()

	elseif params[1] == "/pipekit" then
		local chest = sm.shape.createPart( obj_container_smallchest, params.player.character.worldPosition + sm.vec3.new( 0, 0, 2 ), sm.quat.identity() )
		chest.color = sm.color.new( 0, 0, 1 )
		local container = chest.interactable:getContainer()

		sm.container.beginTransaction()
		sm.container.collect( container, obj_pneumatic_pump, 1 )
		sm.container.collect( container, obj_pneumatic_pipe_03, 10 )
		sm.container.collect( container, obj_pneumatic_pipe_bend, 5 )
		sm.container.endTransaction()

	elseif params[1] == "/foodkit" then
		local chest = sm.shape.createPart( obj_container_smallchest, params.player.character.worldPosition + sm.vec3.new( 0, 0, 2 ), sm.quat.identity() )
		chest.color = sm.color.new( 1, 1, 0 )
		local container = chest.interactable:getContainer()

		sm.container.beginTransaction()
		sm.container.collect( container, obj_plantables_banana, 10 )
		sm.container.collect( container, obj_plantables_blueberry, 10 )
		sm.container.collect( container, obj_plantables_orange, 10 )
		sm.container.collect( container, obj_plantables_pineapple, 10 )
		sm.container.collect( container, obj_plantables_carrot, 10 )
		sm.container.collect( container, obj_plantables_redbeet, 10 )
		sm.container.collect( container, obj_plantables_tomato, 10 )
		sm.container.collect( container, obj_plantables_broccoli, 10 )
		sm.container.collect( container, obj_consumable_sunshake, 5 )
		sm.container.collect( container, obj_consumable_carrotburger, 5 )
		sm.container.collect( container, obj_consumable_pizzaburger, 5 )
		sm.container.collect( container, obj_consumable_longsandwich, 5 )
		sm.container.collect( container, obj_consumable_milk, 5 )
		sm.container.collect( container, obj_resource_steak, 5 )
		sm.container.endTransaction()

	elseif params[1] == "/seedkit" then
		local chest = sm.shape.createPart( obj_container_smallchest, params.player.character.worldPosition + sm.vec3.new( 0, 0, 2 ), sm.quat.identity() )
		chest.color = sm.color.new( 0, 1, 0 )
		local container = chest.interactable:getContainer()

		sm.container.beginTransaction()
		sm.container.collect( container, obj_seed_banana, 20 )
		sm.container.collect( container, obj_seed_blueberry, 20 )
		sm.container.collect( container, obj_seed_orange, 20 )
		sm.container.collect( container, obj_seed_pineapple, 20 )
		sm.container.collect( container, obj_seed_carrot, 20 )
		sm.container.collect( container, obj_seed_redbeet, 20 )
		sm.container.collect( container, obj_seed_tomato, 20 )
		sm.container.collect( container, obj_seed_broccoli, 20 )
		sm.container.collect( container, obj_seed_potato, 20 )
		sm.container.collect( container, obj_consumable_soilbag, 50 )
		sm.container.endTransaction()

	elseif params[1] == "/clearpathnodes" then
		sm.pathfinder.clearWorld()

	elseif params[1] == "/enablepathpotatoes" then
		if params[2] ~= nil then
			self.enablePathPotatoes = params[2]
		end
		if self.enablePathPotatoes then
			sm.gui.chatMessage( "enablepathpotatoes is on" )
		else
			sm.gui.chatMessage( "enablepathpotatoes is off" )
		end

	elseif params[1] == "/aggroall" then
		local units = sm.unit.getAllUnits()
		for _, unit in ipairs( units ) do
			sm.event.sendToUnit( unit, "sv_e_receiveTarget", { targetCharacter = params.player.character } )
		end
		sm.gui.chatMessage( "Units in overworld are aware of PLAYER" .. tostring( params.player.id ) .. " position." )

	elseif params[1] == "/settilebool" or params[1] == "/settilefloat" or params[1] == "/settilestring" then
		if g_eventManager then
			local x = math.floor( params.player.character.worldPosition.x / 64 )
			local y = math.floor( params.player.character.worldPosition.y / 64 )

			local tileStorageKey = g_eventManager:sv_getTileStorageKey( self.world.id, x, y )

			if tileStorageKey then
				g_eventManager:sv_setValue( tileStorageKey, params[2], params[3] )
				sm.gui.chatMessage( "Set tile "..tileStorageKey.." value '"..params[2].."' to "..tostring( params[3] ) )
			else
				sm.log.error( "No tile storage key found!" )
			end
		end
		
	elseif params[1] == "/printtilevalues" then
		if g_eventManager then
			local x = math.floor( params.player.character.worldPosition.x / 64 )
			local y = math.floor( params.player.character.worldPosition.y / 64 )

			local tileStorageKey = g_eventManager:sv_getTileStorageKey( self.world.id, x, y )

			if tileStorageKey then
				local tileStorage = g_eventManager:sv_getTileStorage( tileStorageKey )
				print( "Tile storage values:" )
				print( tileStorage )
				sm.gui.chatMessage( "Tile values printed to console" )
			else
				sm.log.error( "No tile storage key found!" )
			end
		end
	elseif params[1] == "/killall" then
		local units = sm.unit.getAllUnits()
		for _, unit in ipairs( units ) do
			unit:destroy()
		end
	end
    if params[1] == "/raid" then
		print("raids no work here")
		print( "Starting raid level", params[2], "in, wave", params[3] or 1, " in", params[4] or ( 10 / 60 ), "hours" )
		--local position = params.player.character.worldPosition - sm.vec3.new( 0, 0, params.player.character:getHeight() / 2 )
		--g_unitManager:sv_beginRaidCountdown( self, position, params[2], params[3] or 1, ( params[4] or ( 10 / 60 ) ) * 60 * 40 )

	elseif params[1] == "/stopraid" then
		print( "Cancelling all raid" )
		g_unitManager:sv_cancelRaidCountdown( self )
	elseif params[1] == "/disableraids" then
		print( "Disable raids set to", params[2] )
		g_unitManager.disableRaids = params[2]

	elseif params[1] == "/place" then
		local harvestableUuid = selectHarvestableToPlace( params[2] )
		if harvestableUuid and params.aimPosition then
			local from = params.aimPosition + sm.vec3.new( 0, 0, 16.0 )
			local to = params.aimPosition - sm.vec3.new( 0, 0, 16.0 )
			local success, result = sm.physics.raycast( from, to, nil, sm.physics.filter.default )
			if success and result.type == "terrainSurface" then
				local harvestableYZRotation = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), sm.vec3.new( 0, 0, 1 ) )
				local harvestableRotation = sm.quat.fromEuler( sm.vec3.new( 0, math.random( 0, 359 ), 0 ) )
				local placePosition = result.pointWorld
				if params[2] == "stone" then
					placePosition = placePosition + sm.vec3.new( 0, 0, 2.0 )
				end
				sm.harvestable.createHarvestable( harvestableUuid, placePosition, harvestableYZRotation * harvestableRotation )
			end
		end
	
	end

end


local function GetWaitlistKey( id, x, y )
	return id..","..x..","..y
end

function World.sv_loadPathNodesOnCell( self, x, y )
    --print("Loading path nodes on cell")
	local waypoints = sm.cell.getNodesByTag( x, y, "WAYPOINT" )
	if #waypoints == 0 then
		return
	end

	local pathNodes = {}
	for _, waypoint in ipairs( waypoints ) do
		assert( waypoint.params.connections, "Waypoint nodes expected to have the CONNECTION tag aswell" )
		pathNodes[waypoint.params.connections.id] = sm.pathNode.createPathNode( waypoint.position, waypoint.scale.x )
	end

	local waypointCells = {}

	local shouldSaveForeign = false
	local shouldSaveCell = false

	local foreignCells = {}

	for _,waypoint in ipairs( waypoints ) do
		local id = waypoint.params.connections.id
		assert( sm.exists( pathNodes[id] ) )
		-- For each other node connected to this node
		for _,other in ipairs( waypoint.params.connections.otherIds ) do

			if (type(other) == "table") then
				if pathNodes[other.id] then -- Node exist in cell, connect
					assert( sm.exists( pathNodes[other.id] ) )
					pathNodes[id]:connect( pathNodes[other.id], other.actions, other.conditions )
				else -- Node dosent exist in this cell

					-- Add myself to the foreign connections
					local key = GetWaitlistKey( other.id, x + other.cell[1], y + other.cell[2] )
					if self.foreignConnections[key] == nil then
						self.foreignConnections[key] = {}
					end

					table.insert( self.foreignConnections[key], { pathnode = pathNodes[id], actions = other.actions, conditions = other.conditions } )
					shouldSaveForeign = true

					-- Mark foreign cell
					foreignCells[CellKey(x + other.cell[1], y + other.cell[2])] = { x = x + other.cell[1], y = y + other.cell[2] }

				end
			else
				assert( pathNodes[other] )
				pathNodes[id]:connect( pathNodes[other] )
			end			
		end

		-- If we still have foreign connections to us
		if waypoint.params.connections.ccount then

			local key = GetWaitlistKey( id, x, y )
			local foreignConnections = self.foreignConnections[key]
			if foreignConnections then
				for idx, connection in reverse_ipairs( foreignConnections ) do
					if sm.exists( connection.pathnode ) then
						connection.pathnode:connect( pathNodes[id], connection.actions, connection.conditions )
						waypoint.params.connections.ccount = waypoint.params.connections.ccount - 1
						table.remove( foreignConnections, idx )
						shouldSaveForeign = true
					end
				end
				if #foreignConnections == 0 then
					self.foreignConnections[key] = nil
					shouldSaveForeign = true
				end
			end

			if waypoint.params.connections.ccount > 0 then
				table.insert( waypointCells, { pathnode = pathNodes[id], connections = waypoint.params.connections } )
				shouldSaveCell = true
			end

		end
	end

	if shouldSaveCell then
		sm.storage.save( { STORAGE_CHANNEL_WAYPOINT_CELLS, self.world.id, CellKey( x, y ) }, waypointCells )
		shouldSaveCell = false
	end

	if shouldSaveForeign then
		sm.storage.save( STORAGE_CHANNEL_FOREIGN_CONNECTIONS, self.foreignConnections )
		shouldSaveForeign = false
	end

	for _, v in pairs( foreignCells ) do
		self:sv_reloadPathNodesOnCell( v.x, v.y )
	end

end

function World.sv_reloadPathNodesOnCell( self, x, y )
	
	local waypointCells = sm.storage.load( { STORAGE_CHANNEL_WAYPOINT_CELLS, self.world.id, CellKey( x, y ) } )
	if waypointCells == nil then
		return
	end

	-- print("CELLS:", x, y )
	-- print( waypointCells )
	-- print("FOREIGN CONNECTIONS:")
	-- print( self.foreignConnections )

	local shouldSaveForeign = false
	local shouldSaveCell = false

	for idx, node in reverse_ipairs( waypointCells ) do
		if sm.exists( node.pathnode ) then
			assert( node.connections.ccount > 0 )
			local key = GetWaitlistKey( node.connections.id, x, y )
			local foreignConnections = self.foreignConnections[key]
			if foreignConnections then
				for foreignIdx, connection in reverse_ipairs( foreignConnections ) do
					if sm.exists( connection.pathnode ) then
						
						connection.pathnode:connect( node.pathnode, connection.actions, connection.conditions )
						node.connections.ccount = node.connections.ccount - 1
						shouldSaveCell = true

						table.remove( foreignConnections, foreignIdx )
						shouldSaveForeign = true
					end
				end
				if #foreignConnections == 0 then
					self.foreignConnections[key] = nil
					shouldSaveForeign = true
				end
			end

		end

		if node.connections.ccount == 0 then
			table.remove( waypointCells, idx )
			shouldSaveCell = true
		end
	end

	if shouldSaveCell then
		if #waypointCells == 0 then
			waypointCells = nil
		end
		sm.storage.save( { STORAGE_CHANNEL_WAYPOINT_CELLS, self.world.id, CellKey( x, y ) }, waypointCells )
		shouldSaveCell = false
	end

	if shouldSaveForeign then
		sm.storage.save( STORAGE_CHANNEL_FOREIGN_CONNECTIONS, self.foreignConnections )
		shouldSaveForeign = false
	end

end

function World.sv_loadSpawnersOnCell( self, x, y )
	local nodes = sm.cell.getNodesByTag( x, y, "PLAYER_SPAWN" )
	g_respawnManager:sv_addSpawners( nodes )
	g_respawnManager:sv_setLatestSpawners( nodes )
end

function World.sv_reloadSpawnersOnCell( self, x, y )
	local nodes = sm.cell.getNodesByTag( x, y, "PLAYER_SPAWN" )
	g_respawnManager:sv_setLatestSpawners( nodes )
end

function World.sv_spawnNewCharacter( self, params )
    --print("Spawnning new character?",SURVIVAL_DEV_SPAWN_POINT,START_AREA_SPAWN_POINT)
	local spawnPosition = sm.vec3.new(0,0,10)--g_survivalDev and SURVIVAL_DEV_SPAWN_POINT or START_AREA_SPAWN_POINT
	local yaw = 0
	local pitch = 0

	local nodes = sm.cell.getNodesByTag( params.x, params.y, "PLAYER_SPAWN" )
	if #nodes > 0 then
		local spawnerIndex = ( ( params.player.id - 1 ) % #nodes ) + 1
		local spawnNode = nodes[spawnerIndex]
		spawnPosition = spawnNode.position + sm.vec3.new( 0, 0, 1 ) * 0.7

		local spawnDirection = spawnNode.rotation * sm.vec3.new( 0, 0, 1 )
		--pitch = math.asin( spawnDirection.z )
		yaw = math.atan2( spawnDirection.y, spawnDirection.x ) - math.pi/2
	end

	local character = sm.character.createCharacter( params.player, self.world, spawnPosition, yaw, pitch )
	params.player:setCharacter( character )

end


function World.sv_e_spawnNewCharacter( self, params ) -- TODO: Use this (just rename to sv_spawnNewCharacter)
	print("GOt SVE spawnNewCharacter")
	local spawnRayBegin = sm.vec3.new( params.x, params.y, 1024 )
	local spawnRayEnd = sm.vec3.new( params.x, params.y, -1024 )
	local valid, result = sm.physics.spherecast( spawnRayBegin, spawnRayEnd, 0.3 )
	local pos
	if valid then
		pos = result.pointWorld + sm.vec3.new( 0, 0, 0.4 )
	else
		pos = sm.vec3.new( params.x, params.y, 100 )
	end

	local character = sm.character.createCharacter( params.player, self.world, pos )
	params.player:setCharacter( character )
end



-- Customs

function World.sv_e_unit_killed( self, params ) -- params is unit id
	--print("world killing unit",params)
	if g_unitManager then
		g_unitManager:sv_removeChatterFromGame(params)
	end
end

function World.sv_e_getExplode( self, params )
	if params.unit ~= nil then
		local unit = params.unit
		if InSameWorld( params.world, unit ) then -- TODO: Get actual world
			sm.physics.explode( unit:getCharacter().worldPosition + sm.vec3.new(0,0,0.05) , 7, 10, 12, 50, "RedTapeBot - ExplosivesHit" ) -- potentialluy ignore arena?
		--unit:destroy() -- Failsafe	
		end
	end
end

function World.sv_findNamedUnit(self,unit_username) -- finds unit among all npc and pcs using username in its public data
	for _, allyUnit in ipairs( sm.unit.getAllUnits() ) do
		if sm.exists( allyUnit ) and allyUnit.character then -- does not check for insameWorld or not self (unsure what that will do)
			local unitData = allyUnit:getPublicData()
			if unitData and unitData['username'] then
				if tostring(unitData['username']) == tostring(unit_username) then
					return allyUnit
				end
			end
		end
	end
end

function World.sv_createArena(self,params) -- Creates block arena
	local center = params.center
	local size = params.size
	local edgeMatrix = {X1=center.x-(size/2), Y1=center.y-(size/2), X2=center.x+(size/2), Y2=center.y+(size/2)}
	print("got edge matrix",params,edgeMatrix)

	-- create arena in fun way
	local yLoc
	local xLoc
	
	-- Top wall
	yLoc = edgeMatrix.Y1
	for xLoc = edgeMatrix.X1, edgeMatrix.x2 do
		-- TODO: have z location for loop for height
		local blockLocation = sm.vec3.new(xLoc,yLoc,0.5)
		local material = sm.uuid.new("df953d9c-234f-4ac2-af5e-f0490b223e71") -- Wood
		local params = {uuid=material, position=blockLocation}
		print("building block",posistion)
		local block = self:sv_spawnBlock(params)
	end
		

end



