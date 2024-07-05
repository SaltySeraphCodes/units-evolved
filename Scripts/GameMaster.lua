-- main control for everything
dofile "globals.lua"
dofile "Timer2.lua" 

ZOOM_INSTRUCTIONS = MOD_FOLDER .. "/JsonData/zoomControls.json"
CAMERA_INSTRUCTIONS = MOD_FOLDER .. "/JsonData/cameraInput.json"
Control = class( nil )
Control.maxChildCount = -1
Control.maxParentCount = -11
Control.connectionInput = sm.interactable.connectionType.logic
Control.connectionOutput = sm.interactable.connectionType.logic
Control.colorNormal = sm.color.new( 0xffc0cbff )
Control.colorHighlight = sm.color.new( 0xffb6c1ff )
local clock = os.clock --global clock to benchmark various functional speeds ( for fun)



-- Local helper functions utilities
function round( value )
	return math.floor( value + 0.5 )
end

function Control.client_onCreate( self ) 
	self:client_init()
	--print("Created Race Control CL")
end

function Control.server_onCreate( self ) 
	self:server_init()
	--print("Created Race Control SV")
end

function Control.client_onDestroy(self)
    self:stopVisualization()
    if self.smarCamLoaded then
        self:client_exitCamera()
    end
end

function Control.server_onDestroy(self)
    GAME_CONTROL = nil
    self:sv_exitCamera()
    self:sv_deleteArena() -- force delete arena because data is lost anyways
    --self:stopVisualization() -- Necessary?
end

function Control.client_init( self ) 
	-- metadata
    self.aPressed = false
    self.dPressed = false
    self.sPressed = false
    self.wPressed = false
    self.zoomIn = false
    self.zoomOut = false
    -- Chat command Binding?...
    GAME_CONTROL = self -- move to function?
    -- Bind race stuff to chat commands --TODO: cannot do without game script edding -_-
	--sm.game.bindChatCommand( "/start", {}, "cl_onChatCommand", "Starts SMAR Cars" ) -- has to be called on game star in stuff
    --sm.game.bindChatCommand( "/stop", {}, "cl_onChatCommand", "Stop SMAR Cars" )
    --sm.game.bindChatCommand( "/chatcontrol", { { "bool", "enable", true } }, "cl_onChatCommand", "Toggles the usage of a power interactable vs chat commands to start/stop races" )
    -- Effect Things:
    self.effectChain = {}
    self.debugEffects = {}
    --self.effect = sm.effect.createEffect("Loot - GlowItem")
    --self.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    --self.effect:setPosition(self.location)
    -- Toggle visualize metaGrid

-- Camera things
    self.smarCamLoaded = false
    self.externalControlsEnabled = true -- TODO: Check if on seraph's computer
    self.viewIngCamera = false -- whether camera is being viewed
    self.cameraMode = 0 -- camera viewing mode: 0 = free cam, 1 = race cam

    self.currentCameraIndex = 1 -- Which camera index is currently being active, If there are no cameras, then just skip
	self.currentCamera = nil --Current Camera MetaData
	self.cameraActive = false -- if any Cameras Are being used ( redundent)
	self.onBoardActive = false -- If onboard camera is active

	
	self.focusedRacerID = nil -- ID of racer all cameras are being focused on
	self.focusedRacePos = nil -- The position of the racer all cameras are being focused on
	self.focusPos = false -- Keep camera focused on car set by focusedRacePos
	self.focusRacer = false -- Keep camera focused on Car set by racerID, nomatter the pos
	
	self.droneLocation = nil -- virtual location of the drone
    self.droneOffset = sm.vec3.new(50,25,10) -- virtual offset/movement of drone
    self.droneDirOffset =  sm.vec3.new(0,0,0) -- offsetting direction of drone (use on mousemove n stuff)
	self.droneActive = false -- if viewing drone cam

	self.droneFollowRacerID = nil -- Drone following racer
	self.droneFollowRacePos = nil -- Drone Following racePosition
	self.droneFocusRacerID = nil -- Drone Focus on racer
	self.droneFocusRacePos = nil -- Drone focus on racePos

	self.droneFollowPos = false -- Drone keep focused on following by racePosition
	self.droneFollowRacer = false -- Drone keep focused on following by racerID
	self.droneFocusPos = false -- Keep Drone Focused on focusing by racePos
	self.droneFocusRacer = false -- Keep Drone Focused on focusing by racerID
	
	self.focusedRacerData = nil -- All of the specified focused racer data
    self.followedRacerData = nil -- the racer that is specified for drone follo
	-- Followed racer data?
	--self.raceStatus = getRaceStatus()
	
    self.freecamSpeed = 2
	self.finishCameraActive = false -- If it is currently focusing on finish camera DEPRECIATED

	-- Error states to prevent spam
	self.errorShown = false
	self.hasError = false

    self.dt = 0
    self.camTransTimer = 1
    self.frameCountTime = 0
	--print("Camera Control Init")
    self.all_units = {}

end

function Control.server_init(self)
    self.debug = true
    self.timers = {}
    self.powered = false
    self.chatToggle = false -- whether RC uses powered interactable or chat commands to start/stop cars
    self.started = CLOCK()
    self.localMilClock = 0
    self.controllerSwitch = nil -- interactable that is connected to swtcgh
    self.dataOutputTimer = Timer()
    self.dataOutputTimer:start(1)
    self.outputRealTime = true
   
    -- Arena And game Settings
    self.ArenaSize = 200 -- Size of totalArena
    self.GridSize = 10 -- Number of grid NxN squares
    self.metaGrid = {} -- grid Object
    self.arenaShape = {} -- arena shapes

    self.foodSpawnTime = 10
    self.foodSpawnTimer = Timer()
    self.foodSpawnTimer:start(self.foodSpawnTime)

    self.all_units = {} -- periodically updated

    -- Spawn control
    self.defaultSpawnLocation = sm.vec3.new(50,5,2)--sm.vec3.new(self.ArenaSize/2,self.ArenaSize/2,2) -- spawn direct middle

    print("Game  V1.0 Initialized SV")
    GAME_CONTROL = self 
    -- just cam things
    self.smarCamLoaded = false
    self.externalControlsEnabled = true -- TODO: check if this
    self.viewIngCamera = false -- whether camera is being viewed
    
    -- check and load setting
    self.load_default_settings = false -- whether to reset settings (default false)
    local settings = self:sv_load_simulationSettings()
    if settings == nil  or load_default_settings then
        --print('using default settings',settings,getSimulationSettings)
        settings = getSimulationSettings()
        --print('default',settings)
        self:sv_output_simulationSettings()
    else -- 
        --print("using existing settings")
        setSimulationSettings(settings)
        self:sv_output_simulationSettings()
    end

    
end

function Control.client_onRefresh( self )
	self:client_onDestroy()
	self:client_init()
end

function Control.server_onRefresh( self )
	self:server_onDestroy()
	self:server_init()
end
function Control.client_onClientDataUpdate( self, data )
    self.all_units = data.all_units
end
function sleep(n)  -- n: seconds freezes game?
  local t0 = clock()
  while clock() - t0 <= n do end
end

function Control.asyncSleep(self,func,timeout)
    --print("weait",self.globalTimer,self.gotTick,timeout)
    if timeout == 0 or (self.gotTick and self.globalTimer % timeout == 0 )then 
        --print("timeout",self.globalTimer,self.gotTick,timeout)
        local fin = func(self) -- run function
        return fin
    end
end

function runningAverage(self, num)
	local runningAverageCount = 5
	if self.runningAverageBuffer == nil then self.runningAverageBuffer = {} end
	if self.nextRunningAverage == nil then self.nextRunningAverage = 0 end
	
	self.runningAverageBuffer[self.nextRunningAverage] = num 
	self.nextRunningAverage = self.nextRunningAverage + 1 
	if self.nextRunningAverage >= runningAverageCount then self.nextRunningAverage = 0 end
	
	local runningAverage = 0
	for k, v in pairs(self.runningAverageBuffer) do
	  runningAverage = runningAverage + v
	end
	--if num < 1 then return 0 end
	return runningAverage / runningAverageCount;
end


function Control.sv_saveData(self,data) -- is it possible to save nodeChain into race control, save that object and import it to new worlds?
    --debugPrint(self.debug,"Saving data")
    --debugPrint(self.debug,data)
    local channel = data.channel
    data = self.simpNodeChain -- was data.raceLine --{hello = 1,hey = 2,  happy = 3, hopa = "hdjk"}
    print("saving Track")
    sm.storage.save(channel,data) -- track was channel
    saveData(data,channel) -- worldID?
    print("Track Saved")
end

function Control.loadData(self,channel) -- Loads any data?
    local data = self.network:sendToServer("sv_loadData",channel)
    if data == nil then
        print("Data not found?",channel)
        if data == nil then
            print("all data gone",data)
        end
    end
    return data
end

--visualization helpers
function Control.stopVisualization(self) -- Stops all effects in node chain (specify in future?)
    --debugPrint(self.debug,'stop visualizaition')
    
    for k=1, #self.debugEffects do local v=self.debugEffects[k]
        if v ~= nil then
            if not v:isPlaying() then
                --print("debugStop")
                v:stop()
            end
        end
    end
    
    self.visualizing = false
end

function Control.showVisualization(self) --starts all effects
    --debugPrint(self.debug,"show visualization")
        for k=1, #self.debugEffects do local v=self.debugEffects[k]
            if not v:isPlaying() then
                v:start()
            end
        end
    self.visualizing = true
end

function Control.updateVisualization(self) -- moves/updates effects according to nodeChain
    if self.visualizing then -- only show up on debug for now
        for k=1, #self.debugEffects do local effect=self.debugEffects[k]
            if not effect:isPlaying() then
                effect:start()
            end
        end
    end
end

function Control.hardUpdateVisual(self) -- toggle visuals to gain color
    self:stopVisualization()
    self:showVisualization()
end

function Control.generateEffect(self,location,color) -- Creates new effect at param location
    
    local effect = sm.effect.createEffect("Loot - GlowItem")
    effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    effect:setScale(sm.vec3.new(0,0,0))
    local color = (color or sm.color.new("AFAFAFFF"))
    
   -- local testUUID = sm.uuid.new("42c8e4fc-0c38-4aa8-80ea-1835dd982d7c")
    --effect:setParameter( "uuid", testUUID) -- Eventually trade out to calculate from force
    --effect:setParameter( "Color", color )
    if location == nil then
        effect:setPosition(sm.vec3.new(0,0,0)) -- remove too
        effect:setParameter( "Color", sm.color.new("ff3333FF") )
        return effect
    end
    effect:setPosition(location) -- remove too
    effect:setParameter( "Color", color )
    return effect
end


function Control.createEffectLine(self,from,to,color) --
    print("effect line generating")
    local distance = getDistance(from,to)
    local direction = (to - from):normalize()
    local step = 3
    for k = 0, distance,step do
        local pos = from +(direction * k)
        table.insert(self.debugEffects,self:generateEffect(pos,(color or sm.color.new('00ffffff'))))
    end

end


function Control.cl_placeDot(self,params)
    --print("placind debug dot",params)
    local location = params.location
    local color = params.color
    table.insert(self.debugEffects,self:generateEffect(location,(color or sm.color.new('00ffffff'))))
end

function Control.cl_showEdgeMatrix(self,edgeMatrix) -- places dots at corner of edge matrix
    -- Top left, blue
    local color = sm.color.new('0000ffff')
    table.insert(self.debugEffects,self:generateEffect(sm.vec3.new(edgeMatrix.X1,edgeMatrix.Y1,1),color))
    -- Top right, green
    local color = sm.color.new('00ff00ff')
    table.insert(self.debugEffects,self:generateEffect(sm.vec3.new(edgeMatrix.X2,edgeMatrix.Y1,1),color))
    -- bottom left, yellow
    local color = sm.color.new('ffff00ff')
    table.insert(self.debugEffects,self:generateEffect(sm.vec3.new(edgeMatrix.X1,edgeMatrix.Y2,1),color))
    -- bottom right, purple
    local color = sm.color.new('ff00ffff')
    table.insert(self.debugEffects,self:generateEffect(sm.vec3.new(edgeMatrix.X2,edgeMatrix.Y2,1),color))
end
-----

function Control.sv_sendCommand(self,command) -- sends a command to Driver Command Structure: {Car [id or -1/0? for all], type [racestatus..etc], value [0,1]}
    -- parse recipients
    local recipients = command.car
    if recipients[1] == -1 then -- send all
        local allDrivers = getAllDrivers()
        for k=1, #allDrivers do local v=allDrivers[k]
            v:sv_recieveCommand(command)
        end
    else -- send to just one
        local drivers = getDriversFromIdList(command.car)
        for k=1, #drivers do local v=drivers[k]
            v:sv_recieveCommand(command)
        end
    end
end

-- CAMERA THINGS
function Control.cl_sendCameraCommand(self,command) --client sends a command obj {com, val} to camera
    --print("sending cam",self.smarCamLoaded,command)
    --print(getSmarCam())
    if self.smarCamLoaded then
        getSmarCam():cl_recieveCommand(command)
    end
end

function Control.sv_sendCameraCommand(self,command) --server sends a command obj {com, val} to camera
    --print("sv sending cam")
    if self.smarCamLoaded then
        getSmarCam():sv_recieveCommand(command)
    end
end

function Control.cl_setZoomInState(self,state)
    --print("zoomIn = ",state)
    self.zoomIn = state
end

function Control.cl_setZoomOutState(self,state)
    --print("zoomOut = ",state)
    self.zoomOut = state
end

function Control.sv_setZoomInState(self,val)
    local state = false
    if val == 1 then
        state = true
    end
    self.network:sendToClients("cl_setZoomInState",state) --TODO maybe have pcall here for aborting versus stopping -- TODO: Find out how often this is called
end


function Control.sv_setZoomOutState(self,val)
    local state = false
    if val == 1 then
        state = true
    end
    self.network:sendToClients("cl_setZoomOutState",state) --TODO maybe have pcall here for aborting versus stopping -- make efficient
end

function Control.cl_setZoom(self)
    --print(self.zoomIn,self.zoomOut)
    local zoomSpeed = 0.1
    if (self.zoomIn and self.zoomOut) or  (not self.zoomIn and not self.zoomOut) then -- add self.zooming attribute, indicate zoom
        self:cl_sendCameraCommand({command="SetZoom",value=0})
    end
    if self.zoomIn then
        --print("send zoom in")
        self:cl_sendCameraCommand({command="SetZoom",value=zoomSpeed})
    end

    if self.zoomOut then
        self:cl_sendCameraCommand({command="SetZoom",value=-zoomSpeed})
    end
end

function Control.cl_moveCamera(self)
    local moveVec = sm.vec3.new(0,0,0)
    if self.aPressed then 
        moveVec = (moveVec - sm.camera.getRight())
    end
    if self.dPressed then -- rip
        moveVec = (moveVec + sm.camera.getRight())
    end

    if self.wPressed then 
        moveVec = (moveVec + sm.camera.getDirection()) 
    end

    if self.sPressed then
        moveVec = (moveVec - sm.camera.getDirection()) 
    end

    if self.spacePressed then -- move up -- Why do I care about shiftpressed? [...and not self.shiftPressed]
        moveVec = sm.vec3.new(moveVec["x"], moveVec["y"], moveVec["z"] + 1) 
    end

    if self.ePressed then -- move up
        moveVec = sm.vec3.new(moveVec["x"], moveVec["y"], moveVec["z"] - 1)
    end 

    --print("movement",self.aPressed,self.dPressed,self.wPressed,self.sPressed,self.spacePressed,self.ePressed)
    return moveVec * self.freecamSpeed
end

---
function  Control.sv_recieveCommand( self,command ) -- recieves command/data from car (similar structure as send, but just received)
   --print("Race Control recieved command",command)
    if command.type == "add_racer" then -- adding car to race, send back race status as ack
        self:sv_sendCommand({car = command.car, type = "raceStatus", value = self.raceStatus})
    end
    if command.type == "get_raceStatus" then --
        self:sv_sendCommand({car = command.car, type = "raceStatus", value = self.raceStatus})
    end

    if command.type == "lap_cross" then -- racer has crossed lap
        self:processLapCross(command.car,command.value)
    end

    if command.type == "set_caution_pos" then -- racer has crossed lap
        self:setCautionPositions(command.car,command.value)
    end

    if command.type == "set_formation_pos" then -- racer has crossed lap
        self:setFormationPositions(command.car,command.value)
    end

end


function Control.findLogicCon(self) -- returns connection that is logic
    local parents = self.interactable:getParents()
    if #parents == 0 then
        --no parents
    elseif  #parents == 1 then 
        -- one parent
    end

	for k=1, #parents do local v=parents[k]--for k, v in pairs(parents) do
		local parentColor =  tostring(sm.shape.getColor(v:getShape()))
        if v:hasOutputType(sm.interactable.connectionType.logic) then -- found switch
            return v
        else
            --
        end
    end
end

function Control.server_onFixedUpdate(self)
    self:tickClock() -- seconds
    self:tickMilliseconds(0.5) -- miliseconds
    if getSmarCam() ~= nil and getSmarCam() ~= -1 then -- either constanlty check or only check when flag is false
        if not self.smarCamLoaded then
            self.smarCamLoaded = true
            print("smar cam loaded",getSmarCam()~= -1)
        end
    else
        if self.smarCamLoaded then
            print("smar cam Lost",self.smarCamLoaded)
            self.smarCamLoaded = false
        else
            --print("no cam loaded")
        end
    end

    if self.smarCamLoaded or self.externalControlsEnabled then
        self:sv_ReadJson()
        self:sv_readZoomJson()
    end

    -- TODO: Check count of parent, throws error if more than one
    local switch = self:findLogicCon() -- Check if switch on
    if switch == nil then
        if self.powered or self.raceStatus ~= 0 then
            --print("switch destroyed while things on i think")
        end 
    else
        if self.controllerSwitch == nil then
            self.controllerSwitch = switch
        end
        local power = switch:isActive() -- Lets have switch control but also not cont
        if power == nil then -- assume off
            if self.powered or self.raceStatus ~= 0 then
            end
        elseif power then -- switch on
            if self.raceStatus == 0 or self.powered == false then
            end
        elseif power == false then
            if self.powered or self.raceStatus ~= 0 then
            end
        else
            print("HUH?")
        end
    end
    -- Determine if self exists
    local gameControl = getGameControl()
    if gameControl == nil then -- turn error on
        print("Defining RC")
        GAME_CONTROL = self
    else -- TUrn error off
        
        --print("defined RC")
    end
    
end

function Control.client_onFixedUpdate(self) -- key press readings and what not clientside
   -- MOve
   -- If freeCam on then
    --print("RC cl fixedBefore")
    self:updateVisualization()
    if self.smarCamLoaded then
        if self.viewIngCamera then
            self:cl_setZoom()
            if self.droneActive or self.onBoardActive then -- if drone mode active, overide
                
                local movement = self:cl_moveCamera()
                --print(movement:length())
                if movement ~= nil and movement:length() ~= 0 then 
                    --print("changin moves",movement) 
                    self.droneOffset = self.droneOffset + (movement/2) -- TODO: Somehow have orientation lock?
                end
                if self.droneFollowPos then
                -- Set new droneLocation?
                end
            elseif self.cameraMode == 0 then -- and in free cam mode
                local movement = self:cl_moveCamera()
                if movement ~= 0 and movement ~= nil then
                    --print("Camera mode 0 Setting Pos")
                    self:cl_sendCameraCommand({command = "MoveCamera", value=movement})
                end
            elseif self.cameraMode == 1 then -- raceCamMode -- TODO: probably just remove all of thie
                --print("racecam mode",self.currentCamera,#ALL_CAMERAS)
                if #ALL_CAMERAS > 0 and self.currentCamera == nil then
                    --print("swittchingto camera 1")
                    self:switchToCameraIndex(1) -- go to first camera
                end
            end
        end

    end
    --print("RC cl fixedAfter")
    
end

function Control.client_onUpdate(self,dt)
    --print("RC cl onUpdate before")
    if self.viewIngCamera then
        sm.gui.setInteractionText( "" )
        sm.gui.setInteractionText( "" )
    end
    self.frameCountTime =  self.frameCountTime + 1
    local goalOffset = nil
    self.dt = dt
    
    if self.cameraMode == 1 and not (self.droneActive or self.onBoardActive) then -- raceCam
        --print("on raceCam",self.currentCamera.location)
        if self.currentCamera == nil then return end -- just ccut off
        goalOffset = self:getFutureGoal(self.currentCamera.location)
        --print("Calculating goalOffset",self.currentCamera.cameraID,goalOffset,sm.camera.getDirection())
        
        if goalOffset == nil then
            return
        end
        if self.focusRacer then
            self:calculateFocus()
        end
        --print("update pos",goalOffset)
        self:updateCameraPos(goalOffset,dt)
    elseif self.droneActive then
        self:droneExecuteFollowRacer()
        -- used self.droneLocation, what if we used current camera location instead?
        local camPos = sm.camera.getPosition()
        if self.camTransTimer == 1 then -- within the frame of goal
            camPos = self.droneLocation
        end
        -- hold off on currentCamDir until after a few frames, use droneLocation at first
        --print("Getting goal",self.camTransTimer,camPos)
        goalOffset = self:getFutureGoal(camPos)
        self:updateCameraPos(goalOffset,dt) -- can just moive duplicates outside of ifelse
    elseif self.onBoardActive then
        --TODO: perform checking foer valid car funcion and what not
        local camPos = sm.camera.getPosition() -- Can move this up outside of function
        goalOffset = self:getFutureGoal(camPos)
        self:updateCameraPos(goalOffset,dt)
    end

end

-- networking
function Control.sv_ping(self,ping) -- get ing
    print("rc got sv piong",ping)
end

function Control.cl_ping(self,ping) -- get ing
    print("rc got cl ping",ping)
    self.network:sendToServer("sv_ping",ping)
end

function Control.client_showMessage( self, params )
	sm.gui.chatMessage( params )
end

function Control.cl_onChatCommand( self, params )
	if params[1] == "/start" then -- start racers
        -- maybe have timer?? idk
        console.log("CL_Starting Race") -- maybe alert client too?
		
		self.network:sendToServer( "sv_n_onChatCommand", params )
	elseif params[1] == "/stop" then -- stop racers
		console.log("CL_Stopping Race") -- may
        self.network:sendToServer( "sv_n_onChatCommand", params )

	elseif params[1] == "/chatcontrol" then -- toggles chat command controls
		console.log("CL_toggling controls") -- check if server client
        self.network:sendToServer( "sv_n_onChatCommand", params )
	else
        print("SM Command not recognized")
		--self.network:sendToServer( "sv_n_onChatCommand", params )
	end
end

function Control.sv_n_onChatCommand( self, params, player )
	if params[1] == "/start" then -- start racers
        -- maybe have timer?? idk
        if self.chatToggle then 
            self:sv_startRace()
        else
            self.network:sendToClients( "client_showMessage", "Chat controls are disabled, enable with /chatcontrol") -- TODO: Make individual client and not all?
        end
	elseif params[1] == "/stop" then -- stop racers
        if self.chatToggle then 
            self:sv_stopRace()
        else
            self.network:sendToClients( "client_showMessage", "Chat controls are disabled, enable with /chatcontrol") -- TODO: Make individual client and not all?
        end

	elseif params[1] == "/chatcontrol" then -- toggles chat command controls
		self.chatToggle = ( not self.chatToggle)
        self.network:sendToClients( "client_showMessage", "Chat controls are disabled, enable with /chatcontrol") -- TODO: Make individual client and not all?
        print("Chat controls set to "..self.chatToggle)
        self.network:sendToClients( "client_showMessage", "Chat Control is  " .. ( self.chatToggle and "Enabled" or "Disabled" ) ) -- TODO: Make individual client and not all?
	end


end

function Control.sv_sendAlert(self,msg) -- sends alert message to all clients (individual clients not recognized yet)
    --self.network:sendToClients("cl_showAlert",msg) --TODO maybe have pcall here for aborting versus stopping
end

function Control.cl_showAlert(self,msg) -- client recieves alert
    print("Displaying",msg)
    sm.gui.displayAlertText(msg,3) --TODO: Uncomment this before pushing to production
end

function Control.performTimedOutput(self)
    self.dataOutputTimer:tick()
    self.foodSpawnTimer:tick()

    if self.dataOutputTimer:done() then
        self:sv_performTimedFuncts()
        self.dataOutputTimer:start(1)
    end
    --print(self.foodSpawnTimer:done(),SIMULATION_SETTINGS.enable_food)
    if self.foodSpawnTimer:done() and SIMULATION_SETTINGS.enable_food then
        self:sv_spawnRandomFood()
        self.foodSpawnTimer:start(self.foodSpawnTime)
    end
end

function Control.tickMilliseconds(self,milCount) -- ticks off every second that has passed (server)
    local now = clock()
	local floorCheck = self.localMilClock + milCount--round(now-self.started)
    --print((now-self.started) -floorCheck, self.localMilClock)
    if now-self.started>= floorCheck and self.localMilClock ~= floorCheck then -- self.localMilClock ~= floorCheck then
        self.gotMilTick = true
        self.localMilClock = floorCheck
        if (now-self.started) - floorCheck > 1 then
            print("big tick adjust",now-self.started,self.localMilClock)
            self.localMilClock = now-self.started
        end
        --print("tick")
        self:performTimedOutput()
    else
		self.gotMilTick = false
		self.localClock = floorCheck
    end
end
function Control.tickClock(self) -- Just tin case
    local floorCheck = math.floor(clock() - self.started) 
        --print(floorCheck,self.globalTimer)
        
    if self.globalTimer ~= floorCheck then
        self.gotTick = true
        self.globalTimer = floorCheck
        --print("tok")
        --self:performTimedOutput()
    else
        self.gotTick = false
        self.globalTimer = floorCheck
    end
    if self.debug then
    end
            
end

function Control.sv_performTimedFuncts(self)
    --print("doing tick thing")
    if self.outputRealTime then -- only do so when wanted
        self:sv_output_simulationData()
    end
end


function Control.sv_spawnRandomFood(self) -- spawns food randomly TODO: make only when grid
    if self.ArenaSize == nil or self.edgeMatrix == nil then return end
    local posX = math.random(1,self.ArenaSize)
    local posY = math.random(1,self.ArenaSize)
    local worldPos = self:sv_gridToWorldTranslate(self.edgeMatrix,sm.vec3.new(posX,posY,1)) -- figure out floor height
    local foodItem = sm.uuid.new("fe8bfeba-850b-4827-9785-10e2468c9c23") -- corn
    print("building random food",posX,posY)
    sm.shape.createPart(foodItem,worldPos)

end

function Control.sv_performAutoFocus(self) -- auto camera focusing
    --print("auto focus")
    local sorted_drivers = getDriversByCameraPoints()
    if sorted_drivers == nil then return end
    if #sorted_drivers < 1 then return end
    local firstDriver = getDriverFromId(sorted_drivers[1].driver)
    --print("got winning driver",firstDriver.tagText,sorted_drivers[1]['points'])
    -- If firstdriver is the same as last first driver (current focus, do not reset timer)
    if self.focusedRacerID and self.focusedRacerID == firstDriver.id then
        --print("repeat driver",firstDriver.tagText) -- does not change focus or reset timer
    else
        --print("new driver",firstDriver.tagText)
        self.network:sendToClients("cl_setCameraFocus",firstDriver.id)
        --print("restart timer",self.autoFocusDelay)
        self.autoFocusTimer:start(self.autoFocusDelay)
    end
    -- else set driver as focus and reset autocamTimer
end


function Control.sv_performAutoSwitch(self) -- auto camera switching to closest or different view -- TODO: add param of input
    --print('auto switch')
    if self.focusedRacerData then
        local focusRacerPos = self.focusedRacerData.location
        local camerasInDist = self:getCamerasClose(focusRacerPos) -- returns list of cameras close to specified distance
        local closestCam = camerasInDist[1]
        if closestCam == nil then return end
        local distFromCamera = closestCam.distance
        local chosenCamera = closestCam.camera
        --print(self.focusedRacerData.tagText,"Dist from cam",distFromCamera,chosenCamera.cameraID)
        -- TODO: add filtering here LOS: raycast, if there is no cameras close or have visibility, switch to drone/onboard
        -- Get more race like camera:
        -- Get closest node to camera, filter if camera is in front of car by having larger node value
        local distanceCutoff = 60 -- threshold from camera to switch to drone
        
        if distFromCamera > distanceCutoff then
            local mode = math.random(2, 4) -- random for now but can add heuristic to switch
            --print("random switch",mode)
            if mode == 2 then mode = 1 end
            self:sv_toggleCameraMode(mode)
        end

        if self.currentCamera and self.currentCamera.cameraID == chosenCamera.cameraID then
            --print("same camera")
        else
            --print('switching to')
            self.network:sendToClients("cl_switchCamera",chosenCamera.cameraID)
            --print("restarting cam",self.autoSwitchDelay)
            self.autoFocusTimer:start(self.autoFocusDelay/2) -- restart focus timer but not as long
        end
        self.autoSwitchTimer:start(self.autoSwitchDelay) -- re does delay anyways
    end
    
end

-- TODO: Create autoZoom that zooms in on "further racers"

function Control.sv_setAutoFocus(self,value)
    self.autoCameraFocus = value
    print("Setting auto focus",self.autoCameraFocus)
end

function Control.sv_setAutoSwitch(self,value)
    self.autoCameraSwitch = value
    print("Setting auto switch",self.autoCameraSwitch)
end


function Control.client_onInteract(self,character,state)
    --sm.camera.setShake(1)
    -- sm.gui.setInteractionText( "" ) TODO: add this when going in camera mode onUpdate
    
    if ALL_CAMERAS then
        --print(" cam sort")
        sortCameras()
    end
    
    if state then
        if character:isCrouching() then -- ghetto way to load into camera mode
            --print(state,self.smarCamLoaded)
             if self.smarCamLoaded then
                --print("start viewing cam")
                --getSmarCam():cl_ping("Viewing")
                self:cl_sendCameraCommand({command="EnterCam", value = true})
                sm.localPlayer.getPlayer():getCharacter():setLockingInteractable(self.interactable) -- wokrs??
                self.viewIngCamera = true
                self.frameCountTime = 0
                self.camTransTimer = 1
             end
        else
             --self.network:sendToServer("sv_Test",1)
             --print('displaying hud's)
            -- Check whats going on in /after game
           -- if self.RaceMenu then 
            --    self.RaceMenu:open()
            --else
                print("no menue??")
           -- end
        end
    end
end

function Control.sv_exitCamera(self)
    self.network:sendToClients('client_exitCamera')
end

function Control.client_exitCamera(self) -- stops viewing camera
    self:cl_sendCameraCommand({command="ExitCam", value = false})
    sm.localPlayer.getPlayer():getCharacter():setLockingInteractable(nil) -- wokrs??
    sm.camera.setCameraState(1)
    self.viewIngCamera = false
    print("exiting cam mode")
end

function Control.sv_toggleSetting(self,key) -- toggles setting based off of key
    local settingKeys = {'allow_spawn','enable_peaceful','allow_explode','enable_food','allow_move',
    'enable_ap','enable_logout','show_seraph','default_spawn','enable_peaceful'}
    if key>=1 and key <=10 then
        local result = setSimulationSetting(settingKeys[key],not SIMULATION_SETTINGS[settingKeys[key]])
        self.network:sendToClients('cl_aletSettingToggle',{key,result})
        self:sv_output_simulationSettings()
    end
end

function Control.cl_aletSettingToggle(self,data)
    --print("Setting Toggled",data)
    local settingNames = {'Spawning','Peaceful Mode','Exploding','Food','Cow Movement',
    'Action Points','Logging Off','Showing Seraph','Default Spawn Location','NOT A BUTTON'}
    local alertText = settingNames[data[1]] .. (data[2] and " Enabled" or " Disabled")
    --print("outputting:",alertText)
    self:cl_showAlert(alertText)
end

function Control.client_onAction(self, key, state) -- On Keypress. Only used for major functions, the rest will be read by the camera
	--if not sm.isHost then -- Just avoid anythign that isnt the host for now TODO: Figure out why its lagging...
	--	return
	--end
    --print("got keypress",state,key)
	if key == 0 then -- Shift key/alt key/any unrecognized key
	 self.shiftPressed = state -- REMOVE THIS! will have keypress reader
	elseif key == 1 then -- A key
		if self.spacePressed and self.shiftPressed then
            self.aPressed = state
		elseif self.spacePressed then
            self.aPressed = state
		elseif self.shiftPressed then
            self.aPressed = state
		else
            self.aPressed = state
		end
	elseif key == 2 then -- D Key
		if self.spacePressed and self.shiftPressed then
            self.dPressed = state
		elseif self.spacePressed then
            self.dPressed = state 
		elseif self.shiftPressed then
            self.dPressed = state
		else
            self.dPressed = state -- lol
		end
	elseif key == 3 then -- W Key
		if self.spacePressed and self.shiftPressed then
            self.wPressed = state
		elseif self.spacePressed then
            self.wPressed = state
		elseif self.shiftPressed then
            self.wPressed = state
		else -- None pressed
            self.wPressed = state
		end
	elseif key == 4 then -- S Key
		if self.spacePressed and self.shiftPressed then
            self.sPressed = state
		elseif self.spacePressed then
            self.sPressed = state
		elseif self.shiftPressed then
            self.sPressed = state
		else
            self.sPressed = state
		end

 --[[ Number Key toggles
            Normal (world alterations):
                1(5): place Arena: places pre defines arena at camera raycast location (replaces already built)
                2(6): delete Arena: deletes arena (prevents new cows from spawning?)
                3(7): Build Wall: builds wall (horizontal, vertical, cancel toggle)
                4(8): Kill Entity: kills entity camera raycast (TODO)
                5(9): Place Corn: places corn at camera raycast (TODO)
                6(10): place bot: places haybot? at camera raycast (TODO)
            Shift (settings alterations):
                1(5): Toggle Spawn: toggles ability for users to log in
                2(6): Toggle Peace: toggles abilities for users to lose health (does not diable attacks)
                3(7): Toggle Explode: toggles explosion abilities 
                4(8): Toggle Food: toggles random food spawning
                5(9): Toggle Move: toggles ability for users to move
                6(10): Enable AP: toggles ability to drain action points per action
                7(11): toggle leave: toggles ability for users to log out
                8(12): showSeraph: toggles display visualization to show seraphs player dot
                9(13): Toggle Default spawn location: tells all cows to spawn at (gamecontrol defined) location instead of random
            ]]
	elseif key >= 5 and key <= 14 and state then -- Number Keys 1-0
        local convertedKey = key - 4
		if self.spacePressed and self.shiftPressed then
		elseif self.spacePressed then 
		elseif self.shiftPressed then -- Settings alterations
            self.network:sendToServer("sv_toggleSetting",convertedKey)
		else -- World alterations
            local actionFuncts = {'allow_spawn','enable_peaceful','allow_explode','enable_food','allow_move',
            'enable_ap','enable_logout','show_seraph','default_spawn','enable_peaceful'} -- TODO: figure this out
            if key == 5 then -- 1
                local camPos = sm.camera.getPosition()                
                local camDir = sm.camera.getDirection()
                local size = self.ArenaSize -- max is probably 250 but can go bigger
                local center = sm.vec3.new(0,0,0)
                local rayCastValid, rayCastResult =sm.physics.raycast(camPos,camPos +camDir *1000) 
                if rayCastValid then
                    center = rayCastResult.pointWorld
                end
                local params = {
                    center = center,
                    size = size
                }
                local color = sm.color.new('ff0000ff')
                --table.insert(self.debugEffects,self:generateEffect(center,(color or sm.color.new('ff0000ff'))))


                local center = params.center
                local size = params.size
                local edgeMatrix = {X1=center.x+(size/2), Y1=center.y-(size/2), X2=center.x-(size/2), Y2=center.y+(size/2)}
                --self:cl_showEdgeMatrix(edgeMatrix)
                self.network:sendToServer("sv_createArena",params)
                self:hardUpdateVisual()
            end

            if key == 6 then -- 2
                print("creating debug line")
                local camPos = sm.camera.getPosition()                
                local camDir = sm.camera.getDirection()
                self:createEffectLine(camPos,camPos +camDir *1000)
                self:hardUpdateVisual()
            end

            if key == 7 then -- 3
                print('deleting arena')
                self.network:sendToServer("sv_deleteArena")
            end

            if key == 14 then
                print('exiting camera')
                self:client_exitCamera()
            end
            --self.camTransTimer = 1
            --self.network:sendToServer("sv_setAutoSwitch",false)
            --self:switchToCameraIndex(convertedIndex)
		end
		
	elseif key == 15 then -- 'E' Pressed
		if self.spacePressed and self.shiftPressed then -- Finish Cam?
            self.ePressed = state
		elseif self.spacePressed then
            self.ePressed = state
		elseif self.shiftPressed then
            self.ePressed = state
		else -- nothing pressed
            self.ePressed = state
		end

	elseif key == 16 then -- SpacePressed
		self.spacePressed = state
	elseif key == 18 and state then -- Right Click,
		if self.spacePressed and self.shiftPressed then
		elseif self.spacePressed then
		elseif self.shiftPressed then
		else
		end
	elseif key == 19 and state then -- Left Click, 
		if self.spacePressed and self.shiftPressed then
		elseif self.spacePressed then
		elseif self.shiftPressed then
		else
		end
		
	elseif key == 20 then -- Scroll wheel up/ X 
        if self.freecamSpeed < 0.099 then
            self.freecamSpeed = self.freecamSpeed + 0.01
        elseif self.freecamSpeed < 49.99 then
            self.freecamSpeed = self.freecamSpeed + 0.1
        end
		if self.spacePressed and self.shiftPressed then -- optional for more functionality
            --self.zoomIn = state
		elseif self.spacePressed then
            --self.zoomIn = state
		elseif self.shiftPressed then
           -- self.zoomIn = state
		else -- None pressed
		end
	elseif key == 21 then --scrool wheel down % C Pressed  freecam move speed
        if self.freecamSpeed > 0.19 then
            self.freecamSpeed = self.freecamSpeed - 0.1
        elseif self.freecamSpeed > 0.019 then
            self.freecamSpeed = self.freecamSpeed - 0.01
        elseif self.freecamSpeed > 0.001 then
            self.freecamSpeed = self.freecamSpeed - 0.001
        end

		if self.spacePressed and self.shiftPressed then -- Optional just in case something happens
            --self.zoomOut = state 
		elseif self.spacePressed then
            --self.zoomOut = state 
		elseif self.shiftPressed then
            --self.zoomOut = state 
		else -- None pressed
		end
	end
	return true
end

-- JSON 
function Control.sv_readZoomJson(self) -- BETTER IDEA: only begin reading when keypress unrecognized
    --print("RC readZoomJson")
    local status, instructions =  pcall(sm.json.open,ZOOM_INSTRUCTIONS) -- Could pcall whole function
    if status == false then -- Error doing json open
        --print("Got error reading zoom JSON")
        return nil
    else
        --print("got instruct",instructions)
        if instructions ~= nil then --0 Possibly only trigger when not alredy there (will need to read client zoomState)
            zoomIn = instructions['zoomIn']
            zoomOut = instructions['zoomOut']
            if zoomIn == "true" then
                --print("zooming in")
                self:sv_setZoomInState(1)
            else
                self:sv_setZoomInState(0)
            end

            if zoomOut == "true" then
                --print("zooming out")
                self:sv_setZoomOutState(1)
            else
                self:sv_setZoomOutState(0)
            end

            return
        else
            print("zoom Instructions are nil??")
            return nil
        end
    end
    --print("RC read zoomJSON after")
end

-- Outputting game data: needed stuff, grid information, cow information, env info?
--[[ object will look like:
{
    "ai": { (arena information)
        "s": size,
        "g": gridSize,
        "c": center, // unsure if necessary? (do math to recreate virtual grid in js)
    },
    "mg": { (metagrid)
        "g": convertgridToJson() // gets square information and data in simplified array
    },
    "ci": { (cow info)
        "c": [] getAllcowstojson() // gets state, convertedLocation, and attributeinfo of player characters in simplified json array
    }

}
]]


function Control.sv_output_simulationData(self) --outputs simulation data
    --print("outputing data")
    local metaGrid = self:sv_exportMetaGrid() -- minimized self.metaGrid
    local cowData = self:sv_exportCowData() -- minimized cow data
    local outputData = {
        ["ai"]={ --(arena information)
            ["s"]= self.ArenaSize,
            ["g"]= self.GridSize
        },
        ["mg"]= {-- (minimized metagrid)
            ["g"]= metaGrid,
            ["e"]= self.edgeMatrix
        },
        ["ci"]= { -- (cow info)
            ["c"]= cowData -- // gets state, convertedLocation, and attributeinfo of player characters in simplified json array
        }
    
    }
    if outputData ~= {} then
        --local outputString = sm.json.writeJsonString(outputData)
        --self:sv_output_data(outputString)

        sm.json.save(outputData,SIMULATION_DATA_FILE)
    end
end

function Control.sv_load_simulationSettings(self) --outputs simulation settings
    local status, data =  pcall(sm.json.open,SIMULATION_SETTINGS_FILE)
    if status == false or self.load_default_settings then -- Error doing json open
        print("Got error reading instructions JSON")
        return nil
    end
    if data then -- # use len of data
        print("Settings found",data)
        SIMULATION_SETTINGS = data
    else
        print('settings not found')
    end
end

function Control.sv_output_simulationSettings(self) --outputs simulation settings
    --print("svcing settings",SIMULATION_SETTINGS)
    local settings = getSimulationSettings()
    --print('?',settings)
    if settings ~= nil and settings ~= {} then
        sm.json.save(settings,SIMULATION_SETTINGS_FILE)
    else
        print("Settings not found",settings,SIMULATION_SETTINGS)
    end
end


function Control.sv_output_data(self,outputString) -- logs data
    print()
    sm.log.info(outputString)
end


function Control.sv_ReadQualJson(self)
    --print("RC sv readjson before")
    local status, data =  pcall(sm.json.open,QUALIFYING_DATA) -- Could pcall whole function
    if status == false then -- Error doing json open
        print("Got error reading qualifying JSON") -- try again?
        return nil
    else
        print("Got Qual data",data)
        -- send data to cars
        return data
    end
end


function Control.sv_ReadJson(self)
    --print("RC sv readjson before",CAMERA_INSTRUCTIONS)
    local status, instructions =  pcall(sm.json.open,CAMERA_INSTRUCTIONS) -- Could pcall whole function
    if status == false then -- Error doing json open
        --print("Got error reading instructions JSON")
        return nil
    else
        --print("got instruct",instructions)
        sm.json.save("[]", CAMERA_INSTRUCTIONS) -- technically not just camera instructions
        if instructions ~= nil then --0 Possibly only trigger when not alredy there (will need to read client zoomState)
            local instruction = instructions['command']
            if instruction == "exit" then
                self:sv_exitCamera()
            elseif instruction == "focusCycle" then
                local direction = instructions['value']
                --print("focus cycing",direction)
                self:sv_cycleFocus(direction)
            elseif instruction == "camCycle" then
                local direction = instructions['value']
                print("cam cycing",direction)
                self:sv_cycleCamera(direction)
            elseif instruction == "cMode" then
                local mode = tonumber(instructions['value'])
                --print("toggle camera mode") 
                -- turn off auto switch??
                self:sv_toggleCameraMode(mode)
            elseif instruction == "raceMode" then -- 0 is stop, 1 is go, 2 is caution? 3 is formation
                local raceMode = tonumber(instructions['value'])
                --print("changing mraceMode",raceMode,sv_toggleRaceMode)
                self:sv_toggleRaceMode(raceMode)
            elseif instruction == "autoFocus" then -- turn on/off auto focus
                print('set auto focus',instructions)
                local mode = tonumber(instructions['value'])
                if mode == 1 then -- turn on auto switch
                    self.autoCameraFocus = true
                elseif mode == 2 then -- just run auto focus function once ( or turn off if useless)
                    self:sv_performAutoFocus()
                end
            elseif instruction == "autoSwitch" then
                print("auto switch",instructions)
                local mode = tonumber(instructions['value'])
                if mode == 1 then -- turn on auto switch
                    self.autoCameraSwitch = true
                elseif mode == 2 then -- just run auto switch function once ( or turn off if useless)
                    self:sv_performAutoSwitch()
                end
            end
            return
        else
            print("camera Instructions are nil??")
            return nil
        end
    end
    --print("RC sv readjson after")
end

function Control.sv_SaveJson(self)

end


-- camera and car following stuff
function Control.sv_cycleFocus(self,direciton) -- calls iterate camera
    -- turn off automated if on
    self.autoCameraFocus = false
    self.network:sendToClients("cl_cycleFocus",direciton)
    -- remove isFocused (should be SV)
end 

function Control.sv_setFocused(self,last_racerID) -- sv conflicting race condition sometimes??
    if last_racerID ~= nil then
        local racer = getDriverFromId(last_racerID)
        if racer then
            racer.isFocused = false
        end
    end
    
    if self.focusedRacerData ~= nil then
        local racer = getDriverFromId(self.focusedRacerData.id)
        if racer then
            racer.isFocused = true
        end
    end
end


function Control.cl_cycleFocus(self,direction) -- Cycle Which racer to Focus on ( NON Drone Function), Itterates by position
	if self.focusedRacePos == nil then 
		print("Defaulting RacePos Focus to 1")
		self.focusedRacePos = 1
	end
	local totalRacers = #ALL_DRIVERS
	
	local nextRacerPos = self.focusedRacePos + direction
	--print(self.focusedRacePos + direction)
	if nextRacerPos == 0 or nextRacerPos > totalRacers then
		print("Iterate focus On Pos Overflow/UnderFlow Error",nextRacerPos) 
		nextRacerPos = self.focusedRacePos -- prevent from index over/underflow by keeping still, cycling could create confusion
		return
	end
	--print("Iterating Focus to next Pos:",nextRacerPos)
	local nextRacer = getDriverByPos(nextRacerPos)
	--print(nextRacer)
	if nextRacer == nil then
		--print(Error getting next racer)
		-- Means that the racers POS are 0 or error
		return
	end
    self.network:sendToServer("sv_setFocused",self.focusedRacerID) -- sends to server driver focus stats
	self.focusedRacerData = nextRacer
	self.focusedRacePos = nextRacerPos
	self.focusedRacerID =nextRacer.id
	self.focusPos = true
	self.focusRacer = false
	-- Also sets drone? or have it separate, Both focuses and follows drone
	self.droneFollowRacerID = nextRacer.id 
	self.droneFollowRacePos = nextRacerPos
	self.droneFocusRacerID = nextRacer.id 
	self.droneFocusRacePos = nextRacerPos 

	self.droneFollowPos = true 
	self.droneFollowRacer = false 
	self.droneFocusPos = true 
	self.droneFocusRacer = false 

    

	self:focusAllCameras(nextRacer) -- TODO: get this
end

function Control.focusCameraOnPos(self,racePos) -- CL Grabs Racers from racerData by RacerID, pulls racer
	--print("finding drive rby pos",racePos)
    local racer = getDriverByPos(racePos) -- Racer Index is just populated as they are added in
	if racer == nil then
		racer = getDriverByPos(0) -- Defaults to 0?
		return
	end
	if racer.racePosition == nil then
		print("Racer has no RacePos",racer)
		return
	end
    self.network:sendToServer("sv_setFocused",self.focusedRacerID)
    --*print("Settinf focus on pos",racer.id)
	self.focusedRacerData = racer
	self.focusedRacePos = racer.racePosition
	self.focusedRacerID = racer.id
	self.focusPos = true
	self.focusRacer = false
	-- Also sets drone? or have it separate, Both focuses and follows drone
	self.droneFollowRacerID = racer.id 
	self.droneFollowRacePos = racer.racePosition
	self.droneFocusRacerID = racer.id 
	self.droneFocusRacePos = racer.racePosition

	self.droneFollowPos = true 
	self.droneFollowRacer = false 
	self.droneFocusPos = true 
	self.droneFocusRacer = false
	self:focusAllCameras(racer)
end

function Control.focusCameraOnRacerIndex(self,id) -- CL Grabs Racers from racerData by RacerID, pulls racer
	local racer = getDriverFromId(id) -- Racer Index is just populated as they are added in
	if racer == nil then
		print("Camera Focus on racer index Error")
		return
	end
	if racer.racePosition == nil then
		print("Racer has no RacePos",racer.id)
		return
	end
    self.network:sendToServer("sv_setFocused",self.focusedRacerID)
	self.focusedRacerData = racer
	self.focusedRacePos = racer.racePosition
	self.focusedRacerID = racer.id
	self.focusPos = false
	self.focusRacer = true
	-- Also sets drone? or have it separate, Both focuses and follows drone
	self.droneFollowRacerID = racer.id 
	self.droneFollowRacePos = racer.racePosition
	self.droneFocusRacerID = racer.id 
	self.droneFocusRacePos = racer.racePosition

	self.droneFollowPos = false 
	self.droneFollowRacer = true 
	self.droneFocusPos = false 
	self.droneFocusRacer = true

	self:focusAllCameras(racer)
end

function Control.setDroneFollowRacerIndex(self,id) -- Tells the drone to follow whatever index it is
	local racer = getDriverFromId(id) -- Racer Index is just populated as they are added in
	if racer == nil then
		print("Drone follow racer index Error",id)
		return
	end
	if racer.racePosition == nil then
		print("Drone Racer has no RacePos",racer.id)
		return
	end

	-- Also sets drone? or have it separate, Both focuses and follows drone
	self.droneFollowRacerID = racer.id 
	self.droneFollowRacePos = racer.racePosition

	self.droneFollowPos = false 
	self.droneFollowRacer = true 

	self.droneData:setFollow(racer)
end

function Control.setDroneFollowFocusedRacer(self) -- Tells the drone to follow whatever Car it is focused on
	local racer = getDriverFromId(self.focusedRacerID) -- Racer Index is just populated as they are added in
	if racer == nil then
		print("Drone follow Focused racer index Error",self.focusedRacerID)
		return
	end
	if racer.racePosition == nil then
		print("Drone Racer has no RacePos",racer.id)
		return
	end
    self.droneLocation = racer.location + self.droneOffset -- default offset set on init -- puts initial location a bit off and higher than racer`
	-- Also sets drone? or have it separate, Both focuses and follows drone
	self.droneFollowRacerID = racer.id 
	self.droneFollowRacePos = racer.racePosition

	self.droneFollowPos = false 
	self.droneFollowRacer = true
end

function Control.droneExecuteFollowRacer(self) -- runs onfixedupdate and focuses on drone
    local racer = getDriverFromId(self.focusedRacerID) -- OR self. followedRacerID
	if racer == nil then
		print("Drone follow Focused racer index Error",self.focusedRacerID)
		return
	end
	if racer.racePosition == nil then
		print("Drone Racer has no RacePos",racer.id)
		return
	end
    -- If self.droneFollowRacer vs pos?
    self.droneLocation = racer.location + self.droneOffset -- puts initial location a bit off and higher than racer`
	
end

function Control.focusAllCameras(self, racer) --Sets all Cameras to focus on a racer
	local racerID = racer.id
	local racePos = racer.racePosition

	if racer.id == nil then
		print("Setting Camera focus nill/invalid racer")
		return
	end 
	--[[Drone Focusing is be done inside getter goal.
	--for k=1, #ALL_CAMERAS do local v=ALL_CAMERAS[k]-- Foreach camera, set their individual focus/power
		if v.focusID ~= racerID then
			--print(v.power,racePos)
			v:setFocus(racerID)
		end
	end]]
end

function Control.switchToFinishCam(self) -- Unsure if to make separate cam for this?
	self.finishCameraActive = true
    -- send command to switch to camera
end

function Control.toggleDroneCam(self) -- Sets Camera and posistion for drone cam, (no longer toggle, only on)     
    --print("switching to drone")
    --TODO: FAULT, Switching directly from drone mode to Race mode (on sDeck) causes the focus/Goal to be offset. 
    if self.droneLocation == nil then
        --print("Initializing Drone")
        if self.focusedRacerID == nil then -- no racer focused
            local driver = getAllDrivers()[1] -- just grab first driver out of all -- TDODOERRORCASE if no drivers will break
            if driver == nil then -- could not find drivers
                print("drone init error, no focusable drivers")
                -- set location to 0 0 0
                self.droneLocation = sm.vec3.new(0,0,25) + self.droneOffset -- have it reset to focused somewhere aat all times
                return -- just return error
            else 
                print("Set up new follow drone")
                self.droneLocation = driver.location
                print("set up dronelocation",self.droneLocation) -- set up focus Racer()
            end
        else -- ound focused racer
            --print("Settind drone to follow focused racer")
            self:setDroneFollowFocusedRacer()
        end 

    end
    
    if self.focusedRacerData == nil then
        print("Drone Error focus on racer")
        return
    end
    --*print("focusing",self.focusedRacerData.location,self.droneLocation)
    local racerlocation = self.focusedRacerData.location
    --local droneLocation = self.droneData.location
    local camPos = sm.camera.getPosition()
    local goalOffset = self:getFutureGoal(self.droneLocation)
    
    local camDir = sm.camera.getDirection()
    dirMovement1 = sm.vec3.lerp(camDir,goalOffset,1) -- COuld probably just hard code as 1
    self:cl_sendCameraCommand({command="setPos",value=self.droneLocation}) -- lerp drone location>?
	self:cl_sendCameraCommand({command="setDir",value=dirMovement1}) -- TODO: get this to get focus on car and send directions to cam
    --print("set dronelocation",self.droneLocation)
end

function Control.loadDroneData(self) -- Just checks and grabs Drone Data [Unused so far]
	if droneInfo then -- Scalablility?
		if #droneInfo == 1 then
			self.droneData = droneInfo[1]
			if self.droneData == nil then print("Error Reading Drone Data") end
		else
			print("No Drones Found")
		end
	else
		print("Drone Info Table not created")
	end
end

function Control.toggleOnBoardCam(self) -- Toggles on board for whichever racer is focused
    if self.focusedRacerData == nil then -- no racer focused
        print("Initializing onBOard")
        self:focusCameraOnPos(1)
    else -- ound focused racer
        -- already init
    end 
    local racer = self.focusedRacerData
    if racer == nil then return end
    if racer.shape == nil then return end
    local location = racer.shape:getWorldPosition()
    local rvel = racer.velocity
    local carDir = racer.shape:getAt()
    --print("locZ",newLoc)
    local newCamPos = location + (carDir / 10) + (rvel * 1) + sm.vec3.new(0,0,1.4)
    --locMovement = sm.vec3.lerp(camLoc,newCamPos,dt)
    --dirMovement = sm.vec3.lerp(camDir,carDir,1)
    --print(dirMovement)
    self:cl_sendCameraCommand({command="setPos",value=newCamPos})
    self:cl_sendCameraCommand({command="setDir",value=carDir})
   
end


function Control.switchToCamera(self,camera) -- Client Switches to camera based on object
    --print("switching to camera",camera)
    if camera == nil then 
		print("Camera not found",camera)
		return
	end
    if camera.cameraID == nil then
		print("Error when switching to camera",camera)
		return
	end
    self.onBoardActive = false
	self.droneActive = false
	self.currentCameraIndex = getCameraIndexFromId(camera.cameraID)
	--print("switching to camera:",self.currentCameraIndex)
	self:setNewCamera(camera)
end

function Control.switchToCameraIndex(self, cameraIndex) -- Client switches to certain cameras based on  inddex (up to 10) 0-9
	--cameraIndex = cameraIndex + 1 -- Accounts for stupid non zero indexed arrays
	--print("Doing camIndex",cameraIndex)
    local totalCams = #ALL_CAMERAS
	if cameraIndex > #ALL_CAMERAS or cameraIndex <= 0 then
		print("Camera Switch Indexing Error",cameraIndex)
		cameraIndex = 1
	end
	local camera = ALL_CAMERAS[cameraIndex]
	if camera == nil then 
		print("Camera not found",cameraIndex)
		return
	end
	if camera.cameraID == nil then
		print("Error when switching to camera",camera,cameraIndex)
		return
	end
    --print("switching to cam",camera)

	self.onBoardActive = false
	self.droneActive = false
	self.currentCameraIndex = cameraIndex - 1
	print("switching to camera:",cameraIndex,self.currentCameraIndex)
	self:setNewCameraIndex(cameraIndex - 1)
end

function Control.sv_cycleCamera(self,direciton) -- calls iterate camera
    self.autoCameraSwitch = false -- turn off auto switching
    self.network:sendToClients("cl_cycleCamera",direciton)
end

function Control.cl_setCameraFocus(self,id) -- calls to set camera to focus on id
    self:focusCameraOnRacerIndex(id)
end

function Control.cl_switchCamera(self,id)
    local camera = getCameraFromId(id)
    self:switchToCamera(camera)
end

function Control.cl_cycleCamera(self, direction)
    self.camTransTimer = 1
	if self.droneActive then
		print("exit Cycle Drone")
		self.droneActive = false
		self.onBoardActive = false

	end
	if self.onBoardActive then
		self.onBoardActive = false
	end
	local totalCam = #ALL_CAMERAS
	--print(totalCam,self.currentCameraIndex)
	local nextIndex = (self.currentCameraIndex + direction ) %totalCam
	--print("next index",nextIndex)
	if nextIndex > totalCam then
		print("Camera Index Error")
		return
	end
	self:setNewCameraIndex(nextIndex)
	
end

function Control.setNewCameraIndex(self, cameraIndex) -- Switches to roadside camera based off of its index
    --print(self.currentCameraIndex,cameraIndex)D
    --print("\n\n'")
    local avg_dt = 0.016666
    self.currentCameraIndex = cameraIndex
	if ALL_CAMERAS == nil or #ALL_CAMERAS == 0 then
		print("No Cameras Found")
		return
	end
	local cameraToView = ALL_CAMERAS[self.currentCameraIndex + 1]
	--print("viewing cam", self.currentCameraIndex + 1) -- use cam dir?
	if cameraToView == nil then
		print("Error connecting to road Cam",self.currentCameraIndex)
		return
	end
	self.currentCamera = cameraToView
	local camLoc = cameraToView.location
	--camLoc.z = camLoc.z + 2.1 -- Offsets it to be above cam
    goalOffset = self:getFutureGoal(camLoc)
    goalSet1 = self:getGoal()

    local camDir = sm.camera.getDirection()
    dirMovement1 = sm.vec3.lerp(camDir,goalOffset,self.camTransTimer) -- COuld probably just hard code as 1
    self:cl_sendCameraCommand({command="setPos",value=camLoc})
	self:cl_sendCameraCommand({command="setDir",value=dirMovement1}) -- TODO: get this to get focus on car and send directions to cam
end

function Control.setNewCamera(self, camera) -- Switches to roadside camera directly
    local avg_dt = 0.016666 -- ???
	if camera == nil then
		print("Error connecting to road Cam",self.currentCameraIndex,camera)
		return
	end
	self.currentCamera = camera
	local camLoc = camera.location
	--camLoc.z = camLoc.z + 2.1 -- Offsets it to be above cam
    goalOffset = self:getFutureGoal(camLoc)
    goalSet1 = self:getGoal()

    local camDir = sm.camera.getDirection()
    dirMovement1 = sm.vec3.lerp(camDir,goalOffset,self.camTransTimer) -- COuld probably just hard code as 1
    self:cl_sendCameraCommand({command="setPos",value=camLoc})
	self:cl_sendCameraCommand({command="setDir",value=dirMovement1}) -- TODO: get this to get focus on car and send directions to cam
end


function Control.getCamerasClose(self,position) -- returns cameras in position
    if ALL_CAMERAS == nil or #ALL_CAMERAS == 0 then
		print("No Cameras Found")
		return {}
	end
    local sortedCameras = {}
    for k=1, #ALL_CAMERAS do local v=ALL_CAMERAS[k]-- Foreach camera, set their individual focus/power
		local dis = getDistance(position,v.location)
        table.insert(sortedCameras,{camera=v,distance=dis})
    end
    --print("sorting cameras close",sortedCameras)
    sortedCameras = sortCamerasByDistance(sortedCameras)
    --print("sorted cameras",sortedCameras)
    return sortedCameras
end


-- CameraMovement functions
function Control.sv_toggleCameraMode(self,mode) -- toggles between race and free cam - Drone cam will be separate toggle
    self.network:sendToClients("cl_toggleCameraMode",mode)
end

function Control.cl_toggleCameraMode(self,mode) -- client side toggles it
    if not self.focusedRacerData then
        --print("finding racer")
        self:focusCameraOnPos(1)
    end
    if mode == 0 then --race cam
        self.droneActive = false
        self.onBoardActive = false 
        self.cameraMode = 1
        self.camTransTimer = 1 -- Change this to be on toggle anyways?
        self.frameCountTime = 0
        --print("setting to race cam",self.currentCameraIndex)
        self:switchToCameraIndex((self.currentCameraIndex or 1))
    elseif mode == 1 then -- Drone cam
        self.droneActive = true
        self.onBoardActive = false 
        self.cameraMode = 1
        self.camTransTimer = 1 -- Change this to be on toggle anyways?
        self.frameCountTime = 0
        self:toggleDroneCam()
    elseif mode == 2 then -- Freee cam
        self.droneActive = false
        self.onBoardActive = false 
        self.cameraMode = 0
        self.camTransTimer = 1 -- Change this to be on toggle anyways?
        self.frameCountTime = 0
    elseif mode == 3 then -- Onboard cam
        --print("Activate dash cam")
        self.onBoardActive = true
        self.droneActive = false
        self.cameraMode = 1
        self.camTransTimer = 1 -- Change this to be on toggle anyways?
        self.frameCountTime = 0
        self:toggleOnBoardCam()
    end

    
    self:cl_sendCameraCommand({command="setMode", value=self.cameraMode})
end

function Control.calculateFocus(self)
	local racer = self.focusedRacerData -- Racer Index is just populated as they are added in
	if racer == nil then
		print("Calculating Focus on racer index Error")
		return
	end
	if racer.racePosition == nil and not self.errorShown then
		print("CFocus has no RacePos",racer)
		self.errorShown = true
		return
	end
	self:focusAllCameras(racer)

end

function Control.getFutureGoal(self,camLocation) -- gets goal based on new location
    local racer = self.focusedRacerData
	-- If droneactive get droneFocusData
	
	if racer == nil then 
		if #ALL_DRIVERS > 0 then
			racer = ALL_DRIVERS[1]
			self.hasError = false
		else
			if not self.hasError then
				print("No Focused Racer")
				self.hasError = true
			end
			return nil
		end
	end
	if racer.id == nil  then
		if self.hasError == false then
			print("malformed racer") -- Add hasError?
			self.hasError = true
		end
		return nil
	else
		self.hasError = false
	end
	--print(carID)
	local location = racer.shape:getWorldPosition()
	local goalOffset =  location - camLocation
    local dir = sm.camera.getDirection()
    --print("GoalSend:",goalOffset,camLocation,dir)
	return goalOffset
end

function Control.getGoal( self) -- Finds focused car and takes location based on that
	local racer = self.focusedRacerData
	-- If droneactive get droneFocusData
	
	if racer == nil then 
		if #ALL_DRIVERS > 0 then
			racer = ALL_DRIVERS[1]
			self.hasError = false
		else
			if not self.hasError then
				print("No Focused Racer")
				self.hasError = true
			end
			return nil
		end
	end
	if racer.id == nil  then
		if self.hasError == false then
			print("malformed racer") -- Add hasError?
			self.hasError = true
		end
		return nil
	else
		self.hasError = false
	end
	--print(carID)
	local location = racer.location
	
	local camLoc = sm.camera.getPosition()
	local goalOffset =  location - camLoc
	--print(camLoc)
    --print("goal?",goalOffset,racer.id,self.hasError,self.focusedRacerData)
	return goalOffset
end

function Control.updateCameraPos(self,goal,dt)
	--print(self.droneActive,dt,self.currentCamera,self.cameraActive)
    if goal == nil then return end
    local camDir = sm.camera.getDirection()
    local camLoc = sm.camera.getPosition()
    local dirDT = dt *0.3
    local dirMovement = nil
	local locMovement = nil
	
		
    if self.droneActive then
        --print("dact")
        local goalLocation = self.droneLocation
        if goalLocation == nil then
            print("drone has no loc onupdate")
            return
        end
        local smooth = 1
        local mSmooth = 1
        if self.frameCountTime > 5 then
            smooth =dt *0.2
            mSmooth = dt
        end

        

        dirMovement = sm.vec3.lerp(camDir,goal,smooth)--self.camTransTimer
        --camLoc.z = camLoc.z-0.15 -- not sure what this is for
        locMovement = sm.vec3.lerp(camLoc,goalLocation,mSmooth)
        --print(dirMovement,goal)
        --camLoc -- 
        --print("DroneSendB",sm.camera.getPosition(),sm.camera.getDirection()) -- grab locMovement`
        self:cl_sendCameraCommand({command="setPos",value=locMovement})
        self:cl_sendCameraCommand({command="setDir",value=dirMovement})
        --`print("DroneSendA",sm.camera.getPosition(),sm.camera.getDirection())
    
    elseif self.onBoardActive then
        if self.focusedRacerData == nil then 
            print("No focus racer")
            return 
        end
        local racer = self.focusedRacerData
        if racer == nil then return end
        local location = racer.shape:getWorldPosition()-- gets front location
        local frontLength = (racer.carDimensions or 1)
        if racer.carDimensions ~= nil then 
            local rotation  =  racer.carDimensions['center']['rotation']
            local newRot =  rotation * racer.shape:getAt()
            location = racer.shape:getWorldPosition() + (newRot * racer.carDimensions['center']['length'])
            frontLength = racer.carDimensions['front']:length()/3 -- Division reduces length
        end
        local frontLoc = location - (racer.shape:getAt()*self.freecamSpeed)

        local rvel = racer.velocity
        local carDir = racer.shape:getAt()
        local dvel = carDir - camDir --racer.angularVelocity
        --print("locZ",dvel:length())
        local newCamPos = frontLoc + (rvel * 1) + sm.vec3.new(0,0,1.3)
        local newCamDir = camDir + (dvel *9)
        local smooth = 1
        local mSmooth = 1
        if self.frameCountTime > 1 then
            smooth =dt * 1.5
            mSmooth = dt*1.1
        end

        locMovement = sm.vec3.lerp(camLoc,newCamPos,mSmooth)
        --locMovement.z = location.z + 1.4
        --print(location.z,locMovement.z)
        dirMovement = sm.vec3.lerp(camDir,newCamDir,smooth)
        --print(dirMovement)
        self:cl_sendCameraCommand({command="setPos",value=locMovement})
        self:cl_sendCameraCommand({command="setDir",value=dirMovement})
    else
        -- location is alreadyh set
        dirMovement = sm.vec3.lerp(camDir,goal,self.camTransTimer)
        --print("not drone active Setting Dir")
        self:cl_sendCameraCommand({command="setDir",value=dirMovement})
    end
        
    self.camTransTimer = dirDT -- works only with 1 frame yasss!

end

-- Game  control functs

function Control.sv_spawnHarvestable( self, params )
	local harvestable = sm.harvestable.createHarvestable( params.uuid, params.position, params.quat )
	if params.harvestableParams then
		harvestable:setParams( params.harvestableParams )
	end
end

function Control.sv_spawnBlock( self, params )
    --sm.construction.buildBlock( params.uuid, params.position)
    local shape = sm.shape.createBlock(params.uuid, sm.vec3.new(1,1,1), params.position, nil, false,true)
	--print("block built",shape)
end

function Control.sv_spawnWall( self, params )
    --sm.construction.buildBlock( params.uuid, params.position)
    local shape = nil
    if params.direciton == 1 then -- if wall horizontal 
        shape = sm.shape.createBlock(params.uuid, sm.vec3.new(params.length,1,params.height), params.position, nil, false,true)
    elseif params.direciton == 2 then -- if wall vertical 
        shape = sm.shape.createBlock(params.uuid, sm.vec3.new(1,params.length,params.height), params.position, nil, false,true)
    end
	--print("block built",shape)
    return shape
end

function generateEdgeMatrix(center,size)
    local edgeMatrix = {X1=center.x+(size/2), Y1=center.y-(size/2), X2=center.x-(size/2), Y2=center.y+(size/2)}
    return edgeMatrix
end

function Control.sv_createArena(self,params) -- Creates block arena
    if self.arenaShape then self:sv_deleteArena() end -- delete old arena
    print("creating arena:",params)
	local center = params.center
	local size = params.size
    local height = 5 -- TODO: make param
    local metaluuid= "c0dfdea5-a39d-433a-b94a-299345a5df46"
    local wooduuid= "df953d9c-234f-4ac2-af5e-f0490b223e71"
    local material = sm.uuid.new(metaluuid)
    
    local edgeMatrix = generateEdgeMatrix(center,size)
    self.edgeMatrix = edgeMatrix -- TODO: rename to arenaEdgeMatrix (or store in arena obj)
    local arenaObj = {}
	-- create arena in fun way
	-- Top wall
    local location = sm.vec3.new(edgeMatrix.X2,edgeMatrix.Y1,0)
    local direction = 1 -- 1 = horizontal, 2 = vertical
    local params = {uuid=material,
                    position=location,
                    direciton=direction,
                    length=size*4,
                    height = height}
    local topWall = self:sv_spawnWall(params)
    
    -- Bottom Wall
    location = sm.vec3.new(edgeMatrix.X2,edgeMatrix.Y2,0)
    direction = 1 -- 1 = horizontal, 2 = vertical
    params = {uuid=material,
                position=location,
                direciton=direction,
                length=size*4,
                height = height}
    local bottomWall = self:sv_spawnWall(params)

    -- Left Wall
    location = sm.vec3.new(edgeMatrix.X1,edgeMatrix.Y1,0)
    direction = 2 -- 1 = horizontal, 2 = vertical
    params = {uuid=material,
                position=location,
                direciton=direction,
                length=size*4,
                height = height}
    local leftWall = self:sv_spawnWall(params)

    -- Right Wall
    location = sm.vec3.new(edgeMatrix.X2,edgeMatrix.Y1,0)
    direction = 2 -- 1 = horizontal, 2 = vertical
    params = {uuid=material,
                position=location,
                direciton=direction,
                length=size*4,
                height = height}
    local rightWall = self:sv_spawnWall(params)
	
    --table.insert(arenaObj,{leftWall,rightWall,bottomWall,topWall})
    self.arenaShape = {leftWall,rightWall,bottomWall,topWall} -- arenaObj if wanting multiple arena
    --table.insert(self.allArenas,arenaObj)
    -- Create virtual matrix
    self.metaGrid = self:sv_createGrid(center,size,edgeMatrix)
    --local square = self:sv_getSquare({10,10}) -- get first square (x y)
    --local worldLoc = self:sv_gridToWorldTranslate(self.edgeMatrix,sm.vec3.new(50,50,1))
    --self.network:sendToClients("cl_placeDot",{location = worldLoc + sm.vec3.new(0,0,2),color=sm.color.new("1d0fff")})
    --local gridPos = self:sv_worldToGridTranslate(self.edgeMatrix,worldLoc)
    --print("Got gridPos",gridPos)
end
-- Meta Grid creation
function Control.sv_createGrid(self,center,arenaSize,edgeMatrix) -- creates arena using global siz
    local squareSize = arenaSize/self.GridSize
    local xEnd = edgeMatrix.X2
    local yEnd =edgeMatrix.Y2
    local metaGrid = {} -- 2d array
    local centerX = edgeMatrix.X1 - squareSize/2
    local centerY = edgeMatrix.Y1 + squareSize/2
    --self.network:sendToClients("cl_placeDot",{location = sm.vec3.new(centerX,centerY,0.5),color=sm.color.new("aa3ffeff")})
    for xLoc = centerX, xEnd, getSign(xEnd-centerX)*squareSize do
        local rowTable = {}
        for yLoc = centerY, yEnd, getSign(yEnd-centerY)*squareSize do
            local square ={
                center = sm.vec3.new(xLoc,yLoc,0.1),
                size = squareSize,
                edgeMatrix = generateEdgeMatrix(sm.vec3.new(xLoc,yLoc,0.1),squareSize),
                data = {}
            }
            --print("placing",square)
            table.insert(rowTable,square)
            --self.network:sendToClients("cl_placeDot",{location = square.center,color=sm.color.new("aa3ffeff")})
            --self.network:sendToClients("cl_showEdgeMatrix",square.edgeMatrix)
        end
        table.insert(metaGrid,rowTable)
    end
    --print("got grid",metaGrid)
    return metaGrid
end

-- Arena deletion
function Control.sv_deleteArena(self) -- deletes current arena and mnetadata TODO: delete old arena on new creation??
    for k=1, #self.arenaShape do local wall=self.arenaShape[k] 
        wall:destroyShape()
    end
    self.metaGrid = {}
    self.arenaShape = {}
    self.edgeMatrix = nil
    print("deleted arena")
end

-- Grid lookup
function Control.sv_getSquare(self,location) -- location is {row,col}
    if self.metaGrid == nil then return end
    if #self.metaGrid <=1 then return end
    -- validate and get row
    if location[1] <=0 or location[1] >#self.metaGrid[1] then
        print(location[1],"not in metaGrid",#self.metaGrid[1])
        return
    end
    local row = self.metaGrid[location[1]]
    if row == nil then
        print('bad row',row,location[1])
        return
    end
    if location[2] <=0 or location[2] >#row then
        print(location[2],"not in metaGrid",#row)
        return
    end 
    local col = row[location[2]]
    if col == nil then
        print("bad col",col,location)
        return 
    end
    return col

end

function Control.returnAllUnits(self)
    return self.all_units
end

function Control.returnArenaSize(self)
    return self.ArenaSize
end

function Control.returnEdgeMatrix(self)
    return self.edgeMatrix
end

function Control.returnMetaGrid(self)
    return self.metaGrid
end


function Control.sv_getSquareCoords(self,pos)
    local square = self:sv_getSquare({pos.x,pos.y})
    return square.center
end
-- convert 1-100 grid to world posiion
function Control.sv_gridToWorldTranslate(self,edgeMatrix,location) -- Translates grid locations (0-100) input is vector, returns vector
    if edgeMatrix == nil then return end
    if location == nil then return end
    local xTranslate = edgeMatrix.X1
    local yTranslate = edgeMatrix.Y1
    --print(xTranslate,yTranslate)
    local worldLocX = xTranslate - location.x
    local worldLocY = yTranslate + location.y
    local newLocation = sm.vec3.new(worldLocX,worldLocY,location.z) -- same z
    --print("set new location",newLocation,location)
    --self.network:sendToClients("cl_placeDot",{location = newLocation,color=sm.color.new("aa3ffeff")})
    return newLocation
end

-- convert world position to 1-100 grid
function Control.sv_worldToGridTranslate(self,edgeMatrix,location) -- Translates world locations  to (0-100) input vec3, returns vvec3
    local xTranslate = edgeMatrix.X1
    local yTranslate = edgeMatrix.Y1
    --print(xTranslate,yTranslate)
    local worldLocX = xTranslate - location.x
    local worldLocY = location.y - yTranslate
    local newLocation = sm.vec3.new(worldLocX,worldLocY,location.z) -- same z
    -- convert to world coords again
    --self.network:sendToClients("cl_placeDot",{location = newLocation,color=sm.color.new("aa3ffeff")})
    --print("set new location",newLocation,location)
    return newLocation
end

-- data conversion

function Control.sv_exportMetaGrid(self) -- turns metagrid into minimifed obj
    local metaGrid = self.metaGrid
    local outputGrid = {} -- in case we want default

    if metaGrid == nil then return outputGrid end
    local xLoc = 1
    local yLoc = 1
    for xLoc = 1, #metaGrid do -- TODO: make more efficient like just setting pixelCenter already in metaGrid
        local rowTable = {}
        for yLoc = 1, #metaGrid[xLoc]do
            local oldSquare = metaGrid[xLoc][yLoc]
            if oldSquare == nil then return outputGrid end
            local centerLoc = self:sv_worldToGridTranslate(self.edgeMatrix,oldSquare.center)
            --print("converting",oldSquare,centerLoc)
            local newSquare = {
                c={['x']=centerLoc.x,['y']=centerLoc.y},
                s=oldSquare.size,
                d=oldSquare.data -- todo: convert this data to json readable obj
            }
            table.insert(rowTable,newSquare)
            --self.network:sendToClients("cl_placeDot",{location = square.center,color=sm.color.new("aa3ffeff")})
            --self.network:sendToClients("cl_showEdgeMatrix",square.edgeMatrix)
        end
        table.insert(outputGrid,rowTable)
    end
    return outputGrid
end

-- cow data format
--[[
    cow = {
        username,
        userid,
        stats,
        location,
    }

]]


function Control.sv_exportCowData(self) -- simplifies cow data (location, state, stats)
    if #self.arenaShape <1 then --only really run when arena involved
        return {}
    end
    local all_units = sm.unit.getAllUnits() 
    local allNPCS = {}
    local all_playerunits = {}
    local outputData = {}

    for k=1, #all_units do local unit=all_units[k]--filter player units
        local unitData = unit:getPublicData()
        --print("checking",unit,unitData) 
        if unitData and unitData['userid'] then
            if unitData['userid'] then -- THis is an actual unit
                table.insert(all_playerunits,unit)
                table.insert(allNPCS,{
                    ['unit'] =unit,
                    ['username']=tostring(unitData['username'])
                })
            end
        end
    end
    self.all_units = allNPCS
    self.network:setClientData({['all_units']=self.all_units}) -- TODO: only run when new unit is spawnwd
    for k=1, #all_playerunits do local punit=all_playerunits[k]--build new data
        local unitData = punit:getPublicData()
        local location = self:sv_worldToGridTranslate(self.edgeMatrix,punit.character:getWorldPosition())
        local unitOutput = {
            n = unitData.username,
            i = unitData.userid,
            p ={['x']=location.x,['y']=location.y},
            s = unitData.stats -- TODO: minimize stats obj
        }
        if #unitData >0 then
            if unitData['userid'] then -- THis is an actual unit
                table.insert(all_playerunits,unit)
            end
        end
        table.insert(outputData,unitOutput)
    end

    return outputData
end