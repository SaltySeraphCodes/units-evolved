
-- THis is a duplicate for crowd control except it only involve units, can probably integrate them somehow?
dofile("$CONTENT_DATA/Scripts/Timer2.lua") 
dofile("$CONTENT_DATA/Scripts/globals.lua") 

dofile("$SURVIVAL_DATA/Scripts/game/survival_items.lua")
dofile("$SURVIVAL_DATA/Scripts/game/survival_survivalobjects.lua")

StreamReader = class( nil )
local readClock = os.clock 

SREADER_FOLDER = "$CONTENT_DATA/Scripts/StreamReaderData"
chatterDataPath = SREADER_FOLDER.."/chatterData.json" -- unecessary I think
streamChatPath = SREADER_FOLDER.."/streamchat.json"

function StreamReader.sv_onCreate( self,survivalGameData )
    --print("oncreate",survivalGameData)
	if sm.isHost then
		self:onCreate(survivalGameData)
        print("hosting stream reader")
	end
end

-- TODO: Stop reading commands while player is dead
function StreamReader.onCreate( self,survivalGameData ) -- Server_
    --print( "Loading Stream Reader",survivalGameData )
    self.gameData = survivalGameData
    --print('prenetwork',self.network)
    self.network = survivalGameData.network -- Needs more research
    --print("POSTNET",self.network)
    self.readRate = 1 -- Whole seconds in which to wait before reading file again
    self.started = readClock()  
    self.localClock = 0
    self.localMilClock = 0
    self.gotTick = false
    self.gotMilTick = false
    self.lastInstruction = {['id']= -1}
    self.world = survivalGameData.sv.saved.overworld
    self.instructionQue = {}
    
    self.initialized = false

    -- Init timers
    self.spawnLimit = 0 --  if allowed, users can spam in more than one
    self.spawnCooldown = Timer2() -- Maybe not?
    self.spawnCooldown:start(self.spawnLimit)
    self.jsonReadTimeout = 0 -- timeout for read errors

    --Chatter tracking?? will need to pull from unitManager


    self.deathCounter = 0
    self.lives = 100 -- Just in case
    -- stats = 
    local deathStats = 0
    deaths = 0
    if(deathStats ~= nil and type(deathStats) == "number") then
        deaths = deathStats
    end
    self.gameStats = { -- Not entirely sure what to put here
        deaths = deaths,
        bonks = 0,
        robotKills = 0
    }    
    self.playerDead = false
    self.dataChange = false
    
end

function StreamReader.server_onDestroy(self)
    --print("streamreader destroy")
end


function StreamReader.sv_onRefresh( self,survivalGameData )
    print('sreader refresh')
    self:server_onDestroy()
    self:onCreate(survivalGameData)
end

function StreamReader.init(self) -- sv or cl?
    --print("Streamreader init hehe")
end

function StreamReader.sv_readJson(self,fileName)
    local localReadTimeout = 0
    local timeoutLimit = 5
    local status = false
    while localReadTimeout < timeoutLimit do -- timeout
        local status, instructions =  pcall(sm.json.open,fileName )
        if status == true then
            return instructions -- auto exits while, returns nil?
        end
        if status == false then
            print("read failed",localReadTimeout)
            localReadTimeout = localReadTimeout + 1
        end
    end
    sm.log.error("Error reading json, resetting file")
    self:hardResetInstructions() -- clears file and resets
end

function round(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

function StreamReader.tickMilliseconds(self) -- ticks off every second that has passed (server)
    local now = readClock()
	local floorCheck = round(now-self.started,1)
    if self.localMilClock ~= floorCheck then
        self.gotMilTick = true
    else
		self.gotMilTick = false
		self.localClock = floorCheck
    end
end

function StreamReader.tickSeconds(self) -- ticks off every second that has passed (server)
    local now = readClock()
	local floorCheck = math.floor(now - self.started)
	if self.localClock ~= floorCheck then -- TODO: place all timers into an array and just iterate over them
        self.gotTick = true
        
        self.localClock = floorCheck
        self.spawnCooldown:tick()
	else
		self.gotTick = false
		self.localClock = floorCheck
    end
end

function searchUnitID(unit) -- This is a modified spawn search, replacing normal units with player ones, TODO: Replace these with special bots when ready
    local uuid = nil
    if unit == "woc" then
        uuid = unit_player_woc
    elseif unit == "tapebot"  then
        uuid = unit_tapebot
    elseif unit == "redtapebot" then
        uuid = unit_tapebot_red
    elseif unit == "totebot" then
        uuid = unit_totebot_green
    elseif unit == "haybot" then
        uuid = unit_haybot
    elseif unit == "worm" then
        uuid = unit_worm
    elseif unit == "farmbot"  then
        uuid = unit_farmbot
    end
    return uuid
end

function searchKitParam(kit)
    local instruct = nil
    if kit == "meme" then
        instruct = "/memekit"
    elseif kit == "seed" then
        instruct = "/seedkit"
    elseif kit == "pipe" then
        instruct = "/pipekit"
    elseif kit == "food" then
        instruct = "/foodkit"
    elseif kit == "starter" then
        instruct = "/starterkit"
    elseif kit == "mechanic" then
        instruct = "/mechanicstartkit"
    end
    return instruct
end


function searchGiveParam(give) -- Possibly combine into one gant switch?
    local item = nil
    if give == "shotgun" then
        item = "/shotgun"
    elseif give == "ammo"  then
        item = "/ammo"
    elseif give == "gatling" then
        item = "/gatling" -- TODO: make sure they cant add more than one?
    end
    return item
end

function searchItemID(item)
    local uuid = nil
    if item == 'components' then
        uuid = obj_consumable_component
    end
    return uuid
end


function StreamReader.nameUnitServerTest(self,params)
	print('sreader, nameUnit',params)
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

function StreamReader.cl_findNamedUnit(self,params) -- finds unit among all npc and pcs using username in its public data
    --print('cl game findingNameUnit local',params)
    local unit_username = params['username']
    local all_units = params['units']
    if not unit_username then return end
    if not all_units or #all_units == 0 then return end
    for _, allyUnit in ipairs( all_units ) do
        if allyUnit['username'] and  tostring(allyUnit['username']) == tostring(unit_username) then
            return allyUnit['unit']
        end
    end
end


 
function findUsernameInList(list,target) -- search by username -- TODO: generalize this to searh by key in list with target in Util file
    for key, value in pairs(list) do -- For all the values/"items" in the list, do this:
        if value.username:lower() == target:lower() then -- takes lowercase (no fuzzy matching yet?)
            return value
        end
    end
    return false
end


function StreamReader.runInstructions(self,instructionQue) -- Clients
    --print("Running Instructions",instructionQue,self.instructionQue)
    --print('final test',instructionQue)
    for k=1, #instructionQue do local instruction=instructionQue[k] -- Double check the thing
        self:runInstruction(instruction)
        self.lastInstruction = instruction
    end
end

function StreamReader.runInstruction(self,instruction) -- (client)?
    --print("runing instruction",instruction)
    local altmessage = nil

    local usernameColor = "#ff0000"
    local textColor = "#ffffff"
    local moneyColor = "#3fe30e"
    
    local alertmessage = ""
    if instruction == nil then
        return
    end

    local chatInstruction = "/"..instruction.type

    local chatParam = instruction.params
    local paramList = instruction.params
    
    --print("Recieved instruction",instruction)
    if(type(instruction.params)=="table") then
        chatParam = instruction.params[1]
    end
    if chatParam then 
        if chatParam:sub(1, 1) =="@" then
            chatParam = chatParam:sub(2)
        end
    end
    local chatMessage = {chatInstruction,chatParam}
    if chatInstruction == '/spawn' then -- initialize new unit and add chatter to known units
        if self.spawnCooldown:done() then
            local spawnParams = { -- Spawn specified unit around you...
                uuid = sm.uuid.new( "00000000-0000-0000-0000-000000000000" ),
                world =self.world,
                position = self.playerLocation + sm.vec3.new(sm.noise.randomRange(-5,5),sm.noise.randomRange(-5,5),self.playerLocation.z + 0.5),
                yaw = 0.0,
                amount = 1, --TODO: Give Members chance to spawn up to 10?
                chatterData = instruction
            }
            local gameControl = getGameControl()
            if gameControl then 
                local em = gameControl:returnEdgeMatrix()
                local mg = gameControl:returnMetaGrid()
                local size = gameControl:returnArenaSize()
                local randomX = sm.noise.randomRange(5,size-5)
                local randomY = sm.noise.randomRange(5,size-5)
                local location = sm.vec3.new(randomX,randomY,2) -- TODO: get floor height for terrain places
                location = getExactCoords(location,em) 
                if location then 
                    spawnParams.position = location
                end
            else
                sm.log.error('COW SPAWN: Game control not loaded')
            end


           
            if spawnParams.world == nil then 
                self.world = sm.localPlayer.getPlayer().character:getWorld()
                spawnParams.world = self.world
            end
            spawnParams.uuid = searchUnitID(instruction.params) 
            -- may need to set sv??
            self.network:sendToServer( "sv_spawnUnit", spawnParams )
            self.spawnCooldown:reset() -- resets spawn cooldown
        else
            chatMessage = {"/spawn",self.spawnCooldown}
            chatInstruction = "cooldown"
        end

    elseif chatInstruction == '/login' then -- try to load user data and spawn them in TODO: complete this
        if self.spawnCooldown:done() then
            local spawnParams = { -- Spawn specified unit around you...
                uuid = sm.uuid.new( "00000000-0000-0000-0000-000000000000" ),
                world =self.world,
                position = self.playerLocation + sm.vec3.new(sm.noise.randomRange(-5,5),sm.noise.randomRange(-5,5),self.playerLocation.z + 0.5),
                yaw = 0.0,
                amount = 1, --TODO: Give Members chance to spawn up to 10?
                chatterData = instruction
            }
            local gameControl = getGameControl()
            if gameControl then 
                -- TODO: Load previous location and data from cowData.json
                -- else spawn new loaded cow

                local em = gameControl:returnEdgeMatrix()
                local mg = gameControl:returnMetaGrid()
                local size = gameControl:returnArenaSize()
                local randomX = sm.noise.randomRange(5,size-5)
                local randomY = sm.noise.randomRange(5,size-5)
                local location = sm.vec3.new(randomX,randomY,2) -- TODO: get floor height for terrain places
                location = getExactCoords(location,em) 
                if location then 
                    spawnParams.position = location
                end
            else
                sm.log.error('COW SPAWN: Game control not loaded')
            end
                if spawnParams.world == nil then 
                    self.world = sm.localPlayer.getPlayer().character:getWorld()
                    spawnParams.world = self.world
                end
                spawnParams.uuid = searchUnitID('woc')  -- LOAD DATA HERE TODO
                -- may need to set sv??
                self.network:sendToServer( "sv_spawnUnit", spawnParams )
                self.spawnCooldown:reset() -- resets spawn cooldown
            else
                chatMessage = {"/login",self.spawnCooldown}
                chatInstruction = "cooldown"
            end

    elseif chatInstruction == "/follow" then -- follow seraph or other user
        --print("following user",chatParam)
        local params = {command = 'cancel', data = {target = player, userid = instruction.userid} }
        if chatParam == 'seraph' or chatParam == 'Seraph' then
            --local userid = instruction.userid
            player = sm.localPlayer.getPlayer()
            params = {command = 'follow', data = {target = player, userid = instruction.userid} } 
        else -- wants to follow a different unit
            --print('following unit',chatParam)
            if g_unitManager then 
                local spawnchatters = g_unitManager:sv_get_spawnedChatters()
                if #spawnchatters > 0 then -- try to find user in spawnedchatters
                    local spawnedUnit = findUsernameInList(spawnchatters,chatParam)
                    if spawnedUnit then
                        params = {command = 'follow', data = {target = spawnedUnit.unit, userid = instruction.userid} }
                    else
                        sm.log.error("Could not find user to follow:",chatParam)
                        chatParam = 'cancel'
                    end
                end
            end
        end
        
        if params.command ~= 'cancel' then
            self.network:sendToServer( "sv_sendUnitFollow", params )
            chatMessage = {'following unit'}---
        else
            chatMessage = {'error when following unit'}--- Change to follow parma
        end

    elseif chatInstruction == "/attack" then -- follow seraph or other user
        --print("attacking user",chatParam)
        local params = {command = 'cancel', data = {target = player, userid = instruction.userid} }
        if chatParam == 'seraph' or chatParam == 'Seraph' then
            --print('attacking player')
            --local userid = instruction.userid
            player = sm.localPlayer.getPlayer()
            params = {command = 'attack', data = {target = player, userid = instruction.userid} } 
        else -- wants to attack a different unit
            if g_unitManager then 
                local spawnchatters = g_unitManager:sv_get_spawnedChatters() -- or get named units
                if #spawnchatters > 0 then -- try to find user in spawnedchatters
                    local spawnedUnit = findUsernameInList(spawnchatters,chatParam)
                    if spawnedUnit then
                        params = {command = 'attack', data = {target = spawnedUnit.unit, userid = instruction.userid} }
                    else
                        local gameControl = getGameControl()
                        if gameControl then 
                            local allUnits = gameControl:returnAllUnits()
                            if allUnits then
                                local namedUnit = self:cl_findNamedUnit({['username']=chatParam, ['units']=allUnits})
                                if namedUnit then
                                    params = {command = 'attack', data = {target = namedUnit, userid = instruction.userid} }
                                else
                                    sm.log.error("Could not find user to attack:",chatParam)
                                    chatParam = 'cancel'
                                end
                            end
                        end
                    end
                end
            end
        end
        
        if params.command ~= 'cancel' then
            self.network:sendToServer( "sv_sendUnitAttack", params )
            chatMessage = {'Attacking unit'}---
        else
            chatMessage = {'error when attacking unit'}--- Change to follow parma
        end
    elseif chatInstruction == "/goto" then -- go to position (input will be string with either xx,xx or nnn-nnn for grid or precise)
        local params = nil
        local gameControl = getGameControl()
        if gameControl == nil then 
            print("streamreader no find gameControl")
        end
        if gameControl then 
            print('goto',chatParam)
            local version, coordinates = parseCoordinates(chatParam,gameControl) -- returns vec3
            local em = gameControl:returnEdgeMatrix()
            local mg = gameControl:returnMetaGrid()
            local location
            if version == 1 then -- square 
                location = getSquareCoords(coordinates,em,mg) 
                --print("got square coors",location)
            elseif version == 2 then  -- precises
                location = getExactCoords(coordinates,em) 
                --print("got exact coors",location)
            end
            print('got location',location)
            if location then 
                params = {command = 'goto', data = {target = location, userid = instruction.userid} } 
            end
        end
        print('params?',params,location)
        if params then
            self.network:sendToServer( "sv_sendUnitGoto", params )
            chatMessage = {'moving to unit'}
        else
            chatMessage = {'error when moving unit'}
        end

    elseif chatInstruction == "/flee" then
        local params = {command = 'cancel', data = {target = player, userid = instruction.userid} }
        if chatParam == 'seraph' or chatParam == 'Seraph' then
            --local userid = instruction.userid
            player = sm.localPlayer.getPlayer()
            params = {command = 'flee', data = {target = player, userid = instruction.userid} } 
        else -- wants to follow a different unit
            if g_unitManager then 
                local spawnchatters = g_unitManager:sv_get_spawnedChatters()
                if #spawnchatters > 0 then -- try to find user in spawnedchatters
                    local spawnedUnit = findUsernameInList(spawnchatters,chatParam)
                    if spawnedUnit then
                        params = {command = 'flee', data = {target = spawnedUnit.unit, userid = instruction.userid} }
                    else
                        sm.log.error("Could not find user to flee:",chatParam)
                    end
                end
            end
        end
        
        if params.command ~= 'cancel' then
            self.network:sendToServer( "sv_sendUnitFlee", params )
            chatMessage = {'fleeing unit'}---
        else
            chatMessage = {'error when fleeing unit'}--- Change to follow parma
        end
    elseif chatInstruction == "/attack22" then -- do this for bots only? give cow attack ability? 
        chatMessage = {searchGiveParam(chatParam)} -- change to attack param
    elseif chatInstruction == "/wander" then -- REmoved, same thing as stop really
        print("wander has been removed")
    elseif chatInstruction == "/stop" then
        local params = {command = 'stop', data = {userid = instruction.userid} }
        chatMessage = {'stopping cow'} -- no params
        self.network:sendToServer( "sv_sendUnitStop", params )
    elseif chatInstruction == "/explode" then -- isis tiem
        local params = {command = 'explode', data = {userid = instruction.userid} }
        chatMessage = {'exploded cow'} -- no params
        if self.world ~= nil then
            params.world = self.world
        else
            print("nil world")
        end
        self.network:sendToServer( "sv_sendUnitExplode", params )
    elseif chatInstruction == "/spin" then -- isis tiem
        local params = {command = 'spin', data = {userid = instruction.userid} }
        chatMessage = {'Spinning Cow'} -- no params
        if self.world ~= nil then
            params.world = self.world
        else
            print("nil world")
        end
        self.network:sendToServer( "sv_sendUnitSpin", params )
    elseif chatInstruction == "/chat" then -- chat message will appear with unit, making unit emit noise effect
        if #chatParam > 90 then
           print("long chat, auto add linebreak?")
        end
        chatParams = {
            userid = instruction.userid,
            chat = chatParam
        }
        self.network:sendToServer( "sv_unitChat", chatParams )

    elseif chatInstruction == "/log" then
        sm.gui.chatMessage( usernameColor.."Encountered an Exception: "..textColor..chatParam )
        if (not instruction.amount == 0) then
            sm.gui.chatMessage( usernameColor..instruction.username..textColor.." requires a refund of "..moneyColor..instruction.amount )
        end
    end

    if chatInstruction == "cooldown" then
        --print("is on cooldown",chatMessage[2])
        alertmessage = usernameColor.. instruction.type .. textColor.." cooling down: ".. moneyColor ..chatMessage[2]:remaining() .. textColor .." Seconds Remaining" -- alert player name? just say "/spawn failed"?
    end
   
    -- Alert messages
    local showPayments = (self.showPayments or (instruction.amount > 0)) -- TODO: Move to actual configuration
    local paymentMessage = ""
    if chatInstruction ~= "cooldown" then -- TODO: separate to different function(*s)
        if instruction.type == "spawn" then
            alertmessage = usernameColor..instruction.username..textColor..paymentMessage.." spawned as a "..instruction.params
        elseif instruction.type == 'follow' then
            alertmessage = '' --DEBUG" --usernameColor..instruction.username..textColor..paymentMessage.." is following "..instruction.params
        elseif instruction.type == 'attack' then 
            alertmessage = usernameColor..instruction.username..textColor..paymentMessage.." is attacking "..instruction.params
        elseif instruction.type == 'flee' then
            alertmessage ='' -- DEBUG: --usernameColor..instruction.username..textColor..paymentMessage.." is fleeing " .. instruction.params
        elseif instruction.type == 'stop' then
            alertmessage = '' --DEBUG:--usernameColor..instruction.username..textColor..paymentMessage.." is stopping " -- no params
        end
    end
    if instruction ~= nil then
        print("Ran Instruction:",instruction)
    end
    --local testMessge = "#ff0000Hello"
    if #alertmessage > 0 then
        sm.gui.chatMessage( alertmessage )
    end
end
local CounterCount = 0
function StreamReader.readFileAtInterval(self,interval) --- Reads specified file at interval (sever?)
    if self.gotMilTick then
        local jsonData = self:sv_readJson(streamChatPath)
        if jsonData == nil or jsonData == {} or not jsonData or #jsonData == 0 or jsonData == "{}" or jsonData == "[]" then
            --print("NO data")
            return
        end
    
        local lastInstructionID = jsonData[#jsonData].id
        if self.lastInstruction == nil or lastInstructionID ~= self.lastInstruction.id then
            self.recievedInstruction = true
            --print("Got new instructions",lastInstructionID,self.lastInstruction.id)
            -- Only append instructions that are > than lastInstruction
            for i,j in pairs(jsonData) do
                if self.lastInstruction == nil or j.id > self.lastInstruction.id then
                    --print("using",j)
                    table.insert(self.instructionQue,j)
                else
                    --print("rejected",j)
                end
            end
            --self.instructionQue = jsonData -- Or should I append the new data?
            self.lastInstruction = self.instructionQue[#self.instructionQue]
        end
    end
end

function clearTable(table,lastID)
    for k = 0, lastID do
        for i, j in pairs(table) do
            if k == j.id then
                --print("removing",k)
                table[i] = nil
                --table.remove(table, j)
            end
        end
    end
    --print("Trimmed instructions",table)
    return table
end

function StreamReader.clearInstructions(self)-- Clears the json file of stuff
    local lastInstructions =  self:sv_readJson(streamChatPath)
    if lastInstructions == nil or self.lastInstruction == nil then -- Shorcut this error
        --print("no last instruction",self.lastInstruction)
        return
    end
    local lastInstructionID = self.lastInstruction.id
    local clearedTable = clearTable(lastInstructions,lastInstructionID)
    if clearedTable == nil or clearedTable == {} then
        clearJson = "[]"
    else
        clearJson = clearedTable
    end
    self.instructionQue = clearedTable
	sm.json.save(clearJson, streamChatPath)
end

function StreamReader.hardResetInstructions(self)
    -- Hard resets instructions to []
    sm.json.save(clearJson, streamChatPath)
end

function StreamReader.sv_onFixedUpdate( self, timeStep )    
    -- Server awaiting
    if self.initialized then
        self:tickMilliseconds()
        self:tickSeconds()
        self:readFileAtInterval(self.readRate)
    end
    if self.dataChange then -- output stats to json
        --print("dataChange",self.gameStats) -- TODO: can remove this whol if statement
        self.dataChange = false
    end
end

function StreamReader.cl_onFixedUpdate( self, timeStep ) -- Why client? wouldnt server be faster?
    if self.initialized then
        local dead = self.player:getCharacter():isDowned()
        if dead and not self.playerDead then
            self.deathCounter = self.deathCounter + 1
            self.playerDead = true
            sm.gui.chatMessage("#ffff00You have died #ff0000" .. self.deathCounter .. " #ffff00times")
            self.dataChange = true
        elseif not dead and self.playerDead then
            self.playerDead = false 
        end
    end


    self.move = 0
    local player = sm.localPlayer.getPlayer()
    if self.player == nil then self.player = player end
    if player ~= nil then
        local char = player.character
    
        if char ~= nil then
            local pos = char:getWorldPosition()
           
            local dir = char:getDirection()
            local tel = pos + dir * 5
            local cellX, cellY = math.floor( tel.x/64 ), math.floor( tel.y/64 )
			local telParams = {cellX,cellY,player,tel}
            --self.network:sendToServer( "sv_teleport", telParams )
            if pos ~= nil then -- check type too?
                self.playerLocation = pos
                if not self.initialized then -- everything is loaded
                    self.initialized = true
                    print("StreamReader Initialized")
                end
            end
        end
    end
    -- Await async Functions here
    if self.recievedInstruction then
        --print("recieved instructions",self.instructionQue)
        --local success, message = pcall(self:runInstructions(), self.instructionQue)  USE THIS WHEN Confidently finished
        --print("Instruction result",success,message)
        self:runInstructions(self.instructionQue)
        self:clearInstructions()
        self.recievedInstruction = false   
    end
    --print(self.playerLocation) 
end

function StreamReader.outputData(self,data) -- writes data to json file
    sm.json.save(data,chatterDataPath)
end