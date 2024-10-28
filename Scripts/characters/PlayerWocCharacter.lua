dofile("BaseChatCharacter.lua")

PlayerWocCharacter = class( BaseChatCharacter )

function PlayerWocCharacter.sv_onCreate( self )
	print("spawned custom Woc char",self)
	--self:server_onRefresh()

	--local unit = self.character:getUnit()
	--local data = unit:getPublicData()

	--if data then
	--	self.username = data.username
	--	self.userid = data.userid
	--	self.network:setClientData( {username = self.username, userid = self.userid} )
	--end

end
 

function PlayerWocCharacter.sv_onRefresh( self )
	print("refreshed pc woc")
end


function PlayerWocCharacter.cl_onClientDataUpdate( self, data )
	print("PWC updating client data",data)
	if data == nil then return end
	--self.chatMessage = (data.chatMessage or self.chatMessage)
	--self.username = (data.username or self.username)
	--self.userid = (data.userid or self.userid)
	
end


function PlayerWocCharacter.cl_onCreate( self )
	self.animations = {}
	print( "-- PlayerWocCharacter created --" )
	self:cl_onRefresh()
	--self:cl_onInit()
end

function PlayerWocCharacter.cl_onInit(self) -- initialize
	--self.username
	--self.userid
	--self.chatMessage
	
	--print("client initing",self.username,self.userid)
	--self.idTag = sm.gui.createNameTagGui()
	--self.tagText = "#aa00ff" .. (self.username or "") .. "\n #ffffff" .. (self.chatMessage or "") -- format to update text
    --self.idTag:setHost(self.character) -- sets character
	--self.idTag:setRequireLineOfSight( true )
	--self.idTag:setMaxRenderDistance( 1000 )
	--self.idTag:setText( "Text", self.tagText)
	--self.idTag:open()
	print("Custom Initialized")
end

function PlayerWocCharacter.cl_onDestroy( self )
	--self.idTag:close()
	print( "-- PlayerWocCharacter destroyed --" )
end

function PlayerWocCharacter.cl_onRefresh( self )
	print( "-- PlayerWocCharacter refreshed --")
	--if self.idTag ~= nil then 
	--	self.idTag:close()
	--end
	--self:client_onInit()
end

function PlayerWocCharacter.cl_onGraphicsLoaded( self )
	self.animations.tinker = {
		info = self.character:getAnimationInfo( "cow_eat_grass" ),
		time = 0,
		weight = 0
	}
	self.animationsLoaded = true

	self.blendSpeed = 5.0
	self.blendTime = 0.2
	
	self.currentAnimation = ""
	
	self.character:setMovementEffects( "$SURVIVAL_DATA/Character/Char_Cow/movement_effects.json" )
	self.eatEffect = sm.effect.createEffect( "Woc - Eating", self.character, "jnt_head" )
	self.mooEffect = sm.effect.createEffect( "Woc - Moo", self.character, "jnt_head" )
	self.graphicsLoaded = true
end

function PlayerWocCharacter.cl_onGraphicsUnloaded( self )
	self.graphicsLoaded = false

	if self.eatEffect then
		self.eatEffect:destroy()
		self.eatEffect = nil
	end
	if self.mooEffect then
		self.mooEffect:destroy()
		self.mooEffect = nil
	end
end

function PlayerWocCharacter.cl_onUpdate( self, deltaTime )
	--print('pcwoc client_onup')
	if not self.graphicsLoaded then
		return
	end

	-- setting name and tag
	--if self.idTag ~= nil then 
	--	self.tagText = "#aa00ff" .. (self.username or "") .. "\n #ffffff" .. (self.chatMessage or "") -- format to update text
	--	self.idTag:setText( "Text", self.tagText)
	--end

	local activeAnimations = self.character:getActiveAnimations()
	--local debugText = "" .. deltaTime
	sm.gui.setCharacterDebugText( self.character, "custom woc",true) -- Clear debug text
	if activeAnimations then
		for i, animation in ipairs( activeAnimations ) do
			if animation.name ~= "" and animation.name ~= "spine_turn" then
				local truncatedWeight = math.floor( animation.weight * 10 + 0.5 ) / 10
				--sm.gui.setCharacterDebugText( self.character, tostring( animation.name .. " : " .. truncatedWeight ), false ) -- Add debug text without clearing
			end
		end
	end

	for name, animation in pairs(self.animations) do
		animation.time = animation.time + deltaTime
	
		if name == self.currentAnimation then
			animation.weight = math.min(animation.weight+(self.blendSpeed * deltaTime), 1.0)
			if animation.time >= animation.info.duration then
				self.currentAnimation = ""
			end
		else
			animation.weight = math.max(animation.weight-(self.blendSpeed * deltaTime ), 0.0)
		end
	
		self.character:updateAnimation( animation.info.name, animation.time, animation.weight )
	end
end

function PlayerWocCharacter.sv_onFixedUpdate(self,timeStep)


end


function PlayerWocCharacter.cl_onFixedUpdate(self,timeStep)


end

function PlayerWocCharacter.testRecieveEvent(self,params)
	print("woc recieved test event",params)
end

function PlayerWocCharacter.sv_recieveEvent(self,params)
	--print("Got server event",params)
	if params.event == "setName" then 
		self.username = params.data
	elseif params.event == "setId" then
		self.userid = params.data
	elseif params.event == "setChat" then
		self.chatMessage = params.data
		self.network:setClientData( {chatMessage = params.data})
	elseif params.event == "setState" then
		print("Changing state") --TODO: complete this

	elseif params.event == "explode" then

	end

end


function PlayerWocCharacter.cl_recieveEvent(self,params)
	--print("Got Client event",params)
	if params.event == "setName" then 
		self.username = params.data
	elseif params.event == "setId" then
		self.userid = params.data
	elseif params.event == "chat" then
		self.chatMessage = params.data
	elseif params.event == "setState" then
		print("Changing state") --TODO: complete this
	end
end



function PlayerWocCharacter.client_onEvent( self, event )
	--print("Recieved Event",event)
	if not self.animationsLoaded then
		return
	end

	if event == "eat" then
		self.currentAnimation = "tinker"
		self.animations.tinker.time = 0
		if self.graphicsLoaded then
			self.eatEffect:start()
		end
	elseif event == "moo" then
		if self.graphicsLoaded then
			self.mooEffect:start()
		end
	elseif event == "hit" then
		self.currentAnimation = ""
		if self.graphicsLoaded then
			self.eatEffect:stop()
		end
	elseif event == "yolo" then
		print("woc recieved yolo")
	end


end

function PlayerWocCharacter.sv_e_unitDebugText( self, text )
	--print("unit debugText event")
	-- No sync cheat
	if self.unitDebugText == nil then
		self.unitDebugText = {}
	end
	local MaxRows = 10
	if #self.unitDebugText == MaxRows then
		for i = 1, MaxRows - 1 do
			self.unitDebugText[i] = self.unitDebugText[i + 1]
		end
		self.unitDebugText[MaxRows] = text
	else
		self.unitDebugText[#self.unitDebugText + 1] = text
	end
end