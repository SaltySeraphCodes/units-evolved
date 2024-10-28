BaseChatCharacter = class( nil )

function BaseChatCharacter.client_onRefresh( self )
	print("cl_onRefresh")
	if self.cl.idTag ~= nil then 
		self.cl.idTag:close()
	end
	self:client_onInit()
	--self:cl_init()
end


function BaseChatCharacter.server_onRefresh( self )
	print("bcc sv refresh")
end

function BaseChatCharacter.server_onCreate( self )
	self.character.publicData = {}
	self.sv = {}

	local unit = self.character:getUnit()
	local data = unit:getPublicData()

	if data then
		self.sv.username = data.username
		self.sv.userid = data.userid
		self.network:setClientData( {username = self.sv.username, userid = self.sv.userid} )
	end
	self:sv_onCreate() -- calls child create
end



function BaseChatCharacter.client_onCreate( self )
	self.character.clientPublicData = {}
	self.cl = {}
	self.cl.waterMovementSpeedFraction = 1.0
	self.cl.playerHovering = false -- if player is hovering or not
	local player = self.character:getPlayer()
	if sm.exists( player ) then
		if player ~= sm.localPlayer.getPlayer() then
			local name = player:getName()
			self.character:setNameTag( name ) -- Can remove/hide nametag here
		else
			-- if setNameTag is called here you will be able to see your own name, can be changed during runtime
		end
	end
	self:client_onInit()
	self:cl_onCreate()
end


function BaseChatCharacter.client_onInit(self) -- initialize
	--self.username
	--self.userid
	--self.chatMessage
	--print("client initing",self.username,self.userid)
	self.cl.idTag = sm.gui.createNameTagGui()
	self.cl.tagText = "#aa00ff" .. (self.cl.username or "") .. "\n #ffffff" .. (self.cl.chatMessage or "") -- format to update text
    self.cl.idTag:setHost(self.character) -- sets character
	self.cl.idTag:setRequireLineOfSight( true )
	self.cl.idTag:setMaxRenderDistance( 1000 )
	self.cl.idTag:setText( "Text", self.cl.tagText)
	self.cl.idTag:open()
	self:cl_onInit()
end
--[[
	if self.cl.idTag ~= nil then 
		self.cl.tagText = "#aa00ff" .. (self.cl.username or "") .. "\n #ffffff" .. (self.cl.chatMessage or "") -- format to update text
		self.cl.idTag:setText( "Text", self.cl.tagText)
	end
]]

function BaseChatCharacter.client_onClientDataUpdate( self, data )
	print("updating client data",data)
	self.cl.chatMessage = (data.chatMessage or self.cl.chatMessage)
	self.cl.username = (data.username or self.cl.username)
	self.cl.userid = (data.userid or self.cl.userid)
	self:cl_onClientDataUpdate(data)
end


function BaseChatCharacter.client_onGraphicsLoaded( self )
	self.graphicsLoaded = true
	self:cl_onGraphicsLoaded()
end

function BaseChatCharacter.client_onGraphicsUnloaded( self )
	self.graphicsLoaded = false
	self:cl_onGraphicsUnloaded()
end

function BaseChatCharacter.client_onFixedUpdate( self, deltaTime )
	if not sm.isHost then
		self.cl.waterMovementSpeedFraction = 1.0
		if self.character.clientPublicData and self.character.clientPublicData.waterMovementSpeedFraction then
			self.cl.waterMovementSpeedFraction = self.character.clientPublicData.waterMovementSpeedFraction
		end
	end
	if self.character then
		local isHovering = cl_checkHoverChar(self.character)
		
		if isHovering then 
			self.cl.playerHovering = true -- client_canInteract??
		else
			if self.cl.playerHovering then
				print("removing chat")
				self.network:sendToServer("sv_recieveEvent",{event = "chat", data = " "})
			end
			self.cl.playerHovering = false
		end
	end
	self:cl_onFixedUpdate(deltaTime)
end

function BaseChatCharacter.client_onUpdate( self, deltaTime )
	--print("onu",self.cl.idTag)
	if self.cl.idTag ~= nil then 
		self.cl.tagText = "#aa00ff" .. (self.cl.username or "") .. "\n #ffffff" .. (self.cl.chatMessage or "") -- format to update text
		self.cl.idTag:setText( "Text", self.cl.tagText)
	end

	local totalMovementSpeedFraction = self.cl.waterMovementSpeedFraction
	self.character.movementSpeedFraction = totalMovementSpeedFraction

	if not self.graphicsLoaded then
		return
	end
	self:cl_onUpdate(deltaTime)
end


function BaseChatCharacter.server_onFixedUpdate( self, timeStep ) -- I believe because this isn't overrided
	-- Transfer server public data of water movement to client
	self.cl.waterMovementSpeedFraction = 1.0 -- Is this on ly for player characters??? cuz then I can delete it
	if self.character.publicData and self.character.publicData.waterMovementSpeedFraction then
		self.cl.waterMovementSpeedFraction = self.character.publicData.waterMovementSpeedFraction
	end
	self:sv_onFixedUpdate()
end


function BaseChatCharacter.sv_recieveEvent(self,params)
	--print("Got server event",params)
	if params.event == "setName" then 
		self.cl.username = params.data
	elseif params.event == "setId" then
		self.cl.userid = params.data
	elseif params.event == "setChat" then
		self.cl.chatMessage = params.data
		self.network:setClientData( {chatMessage = params.data})
	elseif params.event == "setState" then
		print("Changing state") --TODO: complete this
	elseif params.event == "explode" then

	end
	-- TODO: do custom indiviidualized events too
end


function BaseChatCharacter.cl_recieveEvent(self,params)
	--print("Got Client event",params)
	if params.event == "setName" then 
		self.cl.username = params.data
	elseif params.event == "setId" then
		self.cl.userid = params.data
	elseif params.event == "chat" then
		self.cl.chatMessage = params.data
	elseif params.event == "setState" then
		print("Changing state") --TODO: complete this
	end
	-- custom individualized events here
end

function BaseChatCharacter.client_onDestroy( self )
	if self.cl.idTag then
		self.cl.idTag:close()
	end
	--print( "Chat Char Destroyed" )
end