
dofile( "$SURVIVAL_DATA/Scripts/Game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/Game/util/Timer.lua" )
--dofile( "$CONTENT_DATA/Scripts/Evo_UnitManager.lua" )
dofile( "$CONTENT_DATA/Scripts/Evo_survival_units.lua" ) -- TODO: CHANGE THIS
dofile("$CONTENT_DATA/Scripts/Game.lua")


---@class Brain : BrainClass
---@field sv table
---@field cl table

Brain = class( nil )
Brain.worldXMin = -16
Brain.worldXMax = 16
Brain.worldYMin = -16
Brain.worldYMax = 16 -- REMEMBER TO UPDATE THIS AND WORLD.lua when making new maps

Brain.maxChildCount = -1
Brain.maxParentCount = -11
Brain.connectionInput = sm.interactable.connectionType.logic
Brain.connectionOutput = sm.interactable.connectionType.logic
Brain.colorNormal = sm.color.new( 0xffc0cbff )
Brain.colorHighlight = sm.color.new( 0xffb6c1ff )


function Brain.server_onCreate( self )
	print( "Brain.server_onCreate HELP" )
	self.sv = {}
	self.sv.saved = self.storage:load()
	
	if self.data == nil then
		self.data = {}
	end
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.data = self.data
		self.storage:save( self.sv.saved )
	end
	--print("unit manager?",g_unitManager)
	self:server_init()
end

function Brain.server_onRefresh( self )
	print("brain refresh")
	--print(self.sv.saved)
	self:server_init()
end

function Brain.client_onCreate( self )
	-- HUD FOR RTS STUFF HERE?
end

function Brain.client_onClientDataUpdate( self, clientData, channel )
	print("Brainclientdataupdate",channel)
end

function Brain.server_init(self)
	print("brain init")
	self.powered = false
	print("self",self)
	self.world = sm.world.getCurrentWorld()
	self.memory = {} -- reset memory
	-- ADD Self to Game manager
end

function Brain.sv_spawnUnit(self,params)
	sm.event.sendToWorld( params.world, "sv_e_spawnUnit", params )
end

function Brain.server_onFixedUpdate( self, timeStep )
	-- Tick clocks/timers here
	local switch = self:findLogicCon() -- Check if switch on
	
    if switch == nil then
        if self.powered then
            print("Brain powerLoss")
			self.powered = false
        end 
    else
        local power = switch:isActive()
        if power == nil then -- assume off
            if self.powered then
                print("Power loss")
				self.powered = false
            end
        elseif power then -- switch on
            if self.powered == false then
               print("Turn on")
			   -- DEBUG spawn test
			   local spawnParams = {
				uuid = unit_cursed_farmbot,
				world = self.world,
				position = self.shape:getWorldPosition()+ sm.vec3.new(4,5,10), -- do random radius
				yaw = 0.0,
				amount = 1
			}
			   self:sv_spawnUnit(spawnParams)
			   self.powered = true
            end
        elseif power == false then
            if self.powered  == true then
                print("Turning off")
				self.powered = false
            end
        else
            print("HUH?")
        end
    end

end


function Brain.findLogicCon(self) -- returns connection that is logic
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

function Brain.sv_updateClientData( self )
	self.network:setClientData( { time = self.sv.time }, 2 )
end

function Brain.client_onUpdate( self, dt )
end


function Brain.sv_sendAlert(self,msg) -- sends alert message to all clients (individual clients not recognized yet)
    self.network:sendToClients("cl_showAlert",msg) --TODO maybe have pcall here for aborting versus stopping
end

function Brain.cl_showAlert( self, msg )
	sm.gui.chatMessage( msg )
end




function Brain.client_onAction(self, key, state) -- On Keypress. Only used for major functions, the rest will be read by the camera
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

	elseif key >= 5 and key <= 14 and state then -- Number Keys 1-0
		local convertedIndex = key - 4
		if self.spacePressed and self.shiftPressed then
		elseif self.spacePressed then 
		elseif self.shiftPressed then
		else -- Direct switch to camera number (up to 10)
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
		if self.spacePressed and self.shiftPressed then -- optional for more functionality
           
		elseif self.spacePressed then
            
		elseif self.shiftPressed then
           
		else -- None pressed
		end
	elseif key == 21 then --scrool wheel down % C Pressed  freecam move speed
		if self.spacePressed and self.shiftPressed then -- Optional just in case something happens
		elseif self.spacePressed then
		elseif self.shiftPressed then
		else -- None pressed
		end
	end
	return true
end



function Brain.client_onInteract(self,character,state)
    --sm.camera.setShake(1)
    -- sm.gui.setInteractionText( "" ) TODO: add this when going in camera mode onUpdate
    if state then
        if character:isCrouching() then -- ghetto way to load into camera mode
        else
			print("Yes?")
        end
    end
end

















