--dofile "$SURVIVAL_DATA/Scripts/game/SurvivalPlayer.lua" -- MOdified version of this
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_camera.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" ) -- TODO: Remove this
--dofile( "$GAME_DATA/Scripts/game/BasePlayer.lua" )
dofile( "$SURVIVAL_DATA/scripts/game/quest_util.lua" )


Player = class( nil )

local FireDamage = 10
local FireDamageCooldown = 40
local PoisonDamage = 10
local PoisonDamageCooldown = 40

local StopTumbleTimerTickThreshold = 1.0 * 40 -- Time to keep tumble active after speed is below threshold
local MaxTumbleTimerTickThreshold = 20.0 * 40 -- Maximum time to keep tumble active before timing out
local TumbleResistTickTime = 3.0 * 40 -- Time that the player will resist tumbling after timing out
local MaxTumbleImpulseSpeed = 35
local RecentTumblesTickTimeInterval = 30.0 * 40 -- Time frame to count amount of tumbles in a row
local MaxRecentTumbles = 3

local StatsTickRate = 40

local PerSecond = StatsTickRate / 40
local PerMinute = StatsTickRate / ( 40 * 60 )

local FoodRecoveryThreshold = 5 -- Recover hp when food is above this value
local FastFoodRecoveryThreshold = 50 -- Recover hp fast when food is above this value
local HpRecovery = 50 * PerMinute
local FastHpRecovery = 75 * PerMinute
local FoodCostPerHpRecovery = 0.2
local FastFoodCostPerHpRecovery = 0.2

local FoodCostPerStamina = 0.02
local WaterCostPerStamina = 0.1
local SprintStaminaCost = 0.7 / 40 -- Per tick while sprinting
local CarryStaminaCost = 1.4 / 40 -- Per tick while carrying

local FoodLostPerSecond = 100 / 3.5 / 24 / 60
local WaterLostPerSecond = 100 / 2.5 / 24 / 60

local BreathLostPerTick = ( 100 / 60 ) / 40

local FatigueDamageHp = 1 * PerSecond
local FatigueDamageWater = 2 * PerSecond
local DrownDamage = 5
local DrownDamageCooldown = 40

local RespawnTimeout = 60 * 40

local RespawnFadeDuration = 0.45
local RespawnEndFadeDuration = 0.45

local RespawnFadeTimeout = 5.0
local RespawnDelay = RespawnFadeDuration * 40
local RespawnEndDelay = 1.0 * 40

local BaguetteSteps = 9



local CameraState =
{
	DEFAULT = 1,
	TUMBLING = 2,
	INTERACTABLE = 3,
	CUTSCENE = 4,
	CUSTOM = 5
}

function Player.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	self.sv.saved = self.sv.saved or {}
	self.sv.saved.stats = self.sv.saved.stats or {
		hp = 100, maxhp = 100,
		food = 100, maxfood = 100,
		water = 100, maxwater = 100,
		breath = 100, maxbreath = 100
	}
	if self.sv.saved.isConscious == nil then self.sv.saved.isConscious = true end
	if self.sv.saved.hasRevivalItem == nil then self.sv.saved.hasRevivalItem = false end
	if self.sv.saved.isNewPlayer == nil then self.sv.saved.isNewPlayer = true end
	if self.sv.saved.inChemical == nil then self.sv.saved.inChemical = false end
	if self.sv.saved.inOil == nil then self.sv.saved.inOil = false end
	if self.sv.saved.tutorialsWatched == nil then self.sv.saved.tutorialsWatched = {} end
	self.storage:save( self.sv.saved )

	self:sv_init()
	self.network:setClientData( self.sv.saved )
end

function Player.server_onRefresh( self )
	self:sv_init()
	self.network:setClientData( self.sv.saved )
end

function Player.sv_init( self )
	self.sv.damageCooldown = Timer()
	self.sv.damageCooldown:start( 3.0 * 40 )

	self.sv.impactCooldown = Timer()
	self.sv.impactCooldown:start( 3.0 * 40 )

	self.sv.fireDamageCooldown = Timer()
	self.sv.fireDamageCooldown:start()

	self.sv.poisonDamageCooldown = Timer()
	self.sv.poisonDamageCooldown:start()

	self.sv.tumbleReset = Timer()
	self.sv.tumbleReset:start( StopTumbleTimerTickThreshold )

	self.sv.maxTumbleTimer = Timer()
	self.sv.maxTumbleTimer:start( MaxTumbleTimerTickThreshold )

	self.sv.resistTumbleTimer = Timer()
	self.sv.resistTumbleTimer:start( TumbleResistTickTime )
	self.sv.resistTumbleTimer.count = TumbleResistTickTime

	self.sv.recentTumbles = {}

    self.sv.staminaSpend = 0

	self.sv.statsTimer = Timer()
	self.sv.statsTimer:start( StatsTickRate )

	self.sv.drownTimer = Timer()
	self.sv.drownTimer:stop()

	self.sv.spawnparams = {}
end

function Player.client_onCreate( self )
	self.cl = {}
	self.cl.cameraState = CameraState.DEFAULT
	self.player.clientPublicData = {}
    self.cl = self.cl or {}
	if self.player == sm.localPlayer.getPlayer() then
		if g_survivalHud then
			g_survivalHud:open()
		end

		self.cl.hungryEffect = sm.effect.createEffect( "Mechanic - StatusHungry" )
		self.cl.thirstyEffect = sm.effect.createEffect( "Mechanic - StatusThirsty" )
		self.cl.underwaterEffect = sm.effect.createEffect( "Mechanic - StatusUnderwater" )
		self.cl.followCutscene = 0.0
		self.cl.tutorialsWatched = {}
	end

	self:cl_init()
end

function Player.client_onRefresh( self )
	self:cl_init()
	sm.gui.hideGui( false )
	sm.camera.setCameraState( sm.camera.state.default )
	sm.localPlayer.setLockedControls( false )
end

function Player.cl_init( self ) 
    self.useCutsceneCamera = false
	self.progress = 0
	self.nodeIndex = 1
	self.currentCutscene = {}

	self.cl.revivalChewCount = 0
end

function Player.cl_n_onEvent( self, data )

	local function getCharParam()
		if self.player:isMale() then
			return 1
		else
			return 2
		end
	end

	local function playSingleHurtSound( effect, pos, damage )
		local params = {
			["char"] = getCharParam(),
			["damage"] = damage
		}
		sm.effect.playEffect( effect, pos, sm.vec3.zero(), sm.quat.identity(), sm.vec3.one(), params )
	end

	if data.event == "drown" then
		playSingleHurtSound( "Mechanic - HurtDrown", data.pos, data.damage )
	elseif data.event == "fatigue" then
		playSingleHurtSound( "Mechanic - Hurthunger", data.pos, data.damage)
	elseif data.event == "shock" then
		playSingleHurtSound( "Mechanic - Hurtshock", data.pos, data.damage )
	elseif data.event == "impact" then
		playSingleHurtSound( "Mechanic - Hurt", data.pos, data.damage )
	elseif data.event == "fire" then
		playSingleHurtSound( "Mechanic - HurtFire", data.pos, data.damage )
	elseif data.event == "poison" then
		playSingleHurtSound( "Mechanic - Hurtpoision", data.pos, data.damage )
	end
end

function Player.client_onClientDataUpdate( self, data )
	if sm.localPlayer.getPlayer() == self.player then
		self.cl.inChemical = data.inChemical
		self.cl.inOil = data.inOil
	end
    
    if sm.localPlayer.getPlayer() == self.player then

		if self.cl.stats == nil then self.cl.stats = data.stats end -- First time copy to avoid nil errors

		if g_survivalHud then
			g_survivalHud:setSliderData( "Health", data.stats.maxhp * 10 + 1, data.stats.hp * 10 )
			g_survivalHud:setSliderData( "Food", data.stats.maxfood * 10 + 1, data.stats.food * 10 )
			g_survivalHud:setSliderData( "Water", data.stats.maxwater * 10 + 1, data.stats.water * 10 )
			g_survivalHud:setSliderData( "Breath", data.stats.maxbreath * 10 + 1, data.stats.breath * 10 )
		end

		if self.cl.hasRevivalItem ~= data.hasRevivalItem then
			self.cl.revivalChewCount = 0
		end

		if self.player.character then
			local charParam = self.player:isMale() and 1 or 2
			self.cl.underwaterEffect:setParameter( "char", charParam )
			self.cl.hungryEffect:setParameter( "char", charParam )
			self.cl.thirstyEffect:setParameter( "char", charParam )

			if data.stats.breath <= 15 and not self.cl.underwaterEffect:isPlaying() and data.isConscious then
				self.cl.underwaterEffect:start()
			elseif ( data.stats.breath > 15 or not data.isConscious ) and self.cl.underwaterEffect:isPlaying() then
				self.cl.underwaterEffect:stop()
			end
			if data.stats.food <= 5 and not self.cl.hungryEffect:isPlaying() and data.isConscious then
				self.cl.hungryEffect:start()
			elseif ( data.stats.food > 5 or not data.isConscious ) and self.cl.hungryEffect:isPlaying() then
				self.cl.hungryEffect:stop()
			end
			if data.stats.water <= 5 and not self.cl.thirstyEffect:isPlaying() and data.isConscious then
				self.cl.thirstyEffect:start()
			elseif ( data.stats.water > 5 or not data.isConscious ) and self.cl.thirstyEffect:isPlaying() then
				self.cl.thirstyEffect:stop()
			end
		end

		if data.stats.food <= 5 and self.cl.stats.food > 5 then
			sm.gui.displayAlertText( "#{ALERT_HUNGER}", 5 )
		end
		if data.stats.water <= 5 and self.cl.stats.water > 5 then
			sm.gui.displayAlertText( "#{ALERT_THIRST}", 5 )
		end

		if data.stats.hp < self.cl.stats.hp and data.stats.breath == 0 then
			sm.gui.displayAlertText( "#{DAMAGE_BREATH}", 1 )
		elseif data.stats.hp < self.cl.stats.hp and data.stats.food == 0 then
			sm.gui.displayAlertText( "#{DAMAGE_HUNGER}", 1 )
		elseif data.stats.hp < self.cl.stats.hp and data.stats.water == 0 then
			sm.gui.displayAlertText( "#{DAMAGE_THIRST}", 1 )
		end

		self.cl.stats = data.stats
		self.cl.isConscious = data.isConscious
		self.cl.hasRevivalItem = data.hasRevivalItem

		sm.localPlayer.setBlockSprinting( data.stats.food == 0 or data.stats.water == 0 )
        -- Removed tutorial shiz
	end
end

function Player.client_onUpdate( self, dt )
	if self.player == sm.localPlayer.getPlayer() then
		self:cl_localPlayerUpdate( dt )
	end
end

function Player.cl_localPlayerUpdate( self, dt )
	local character = self.player:getCharacter()

	local alwaysUpdate = false
	local wantedCameraState = CameraState.DEFAULT
	local wantedCameraData = {
		hideGui = false,
		cameraState = sm.camera.state.default,
		lockedControls = false }

	if self.player.clientPublicData.cutsceneCameraData then
		wantedCameraState = CameraState.CUTSCENE
		wantedCameraData = self.player.clientPublicData.cutsceneCameraData
		alwaysUpdate = true
	elseif self.player.clientPublicData.interactableCameraData then
		wantedCameraState = CameraState.INTERACTABLE
		wantedCameraData = self.player.clientPublicData.interactableCameraData
		alwaysUpdate = true
	elseif character and character:isTumbling() then
		wantedCameraState = CameraState.TUMBLING
		wantedCameraData.cameraState = sm.camera.state.forcedTP
	elseif self.player.clientPublicData.customCameraData then
		wantedCameraState = CameraState.CUSTOM
		wantedCameraData = self.player.clientPublicData.customCameraData
		alwaysUpdate = true
		self.player.clientPublicData.customCameraData = nil
	end

	if self.cl.cameraState ~= wantedCameraState or alwaysUpdate then
		self.cl.cameraState = wantedCameraState
		if wantedCameraData.hideGui ~= nil then
			sm.gui.hideGui( wantedCameraData.hideGui )
		end
		if wantedCameraData.cameraState then
			sm.camera.setCameraState( wantedCameraData.cameraState )
		end
		if wantedCameraData.cameraPosition then
			sm.camera.setPosition( wantedCameraData.cameraPosition )
		end
		if wantedCameraData.cameraRotation then
			sm.camera.setRotation( wantedCameraData.cameraRotation )
		end
		if wantedCameraData.cameraDirection then
			sm.camera.setDirection( wantedCameraData.cameraDirection )
		end
		if wantedCameraData.cameraFov then
			sm.camera.setFov( wantedCameraData.cameraFov )
		end
		if wantedCameraData.lockedControls ~= nil then
			sm.localPlayer.setLockedControls( wantedCameraData.lockedControls )
		end
	end

	if character and character:isSwimming() and not self.cl.inChemical and not self.cl.inOil then
		self:cl_n_fillWater()
	end

    self:cl_updateCamera( dt )

	local character = self.player:getCharacter()
	if character and not self.cl.isConscious then
		local keyBindingText =  sm.gui.getKeyBinding( "Use", true )
		if self.cl.hasRevivalItem then
			if self.cl.revivalChewCount < BaguetteSteps then
				sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_EAT} ("..self.cl.revivalChewCount.."/10)" )
			else
				sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_REVIVE}" )
			end
		else
			sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_RESPAWN}" )
		end
	end

	if character then
		self.cl.underwaterEffect:setPosition( character.worldPosition )
		self.cl.hungryEffect:setPosition( character.worldPosition )
		self.cl.thirstyEffect:setPosition( character.worldPosition )
	end
end

function Player.client_onInteract( self, character, state ) 
    if state == true then
		if not self.cl.isConscious then
			if self.cl.hasRevivalItem then
				if self.cl.revivalChewCount >= BaguetteSteps then
					self.network:sendToServer( "sv_n_revive" )
				end
				self.cl.revivalChewCount = self.cl.revivalChewCount + 1
				self.network:sendToServer( "sv_onEvent", { type = "character", data = "chew" } )
			else
				self.network:sendToServer( "sv_n_tryRespawn" )
			end
		end
	end


end

function Player.server_onFixedUpdate( self, dt )
	local character = self.player:getCharacter()
	if character then
		self:sv_updateTumbling()
	end

	self.sv.damageCooldown:tick()
	self.sv.impactCooldown:tick()
	self.sv.fireDamageCooldown:tick()
	self.sv.poisonDamageCooldown:tick()

    if g_survivalDev and not self.sv.saved.isConscious and not self.sv.saved.hasRevivalItem then
		if sm.container.canSpend( self.player:getInventory(), obj_consumable_longsandwich, 1 ) then
			if sm.container.beginTransaction() then
				sm.container.spend( self.player:getInventory(), obj_consumable_longsandwich, 1, true )
				if sm.container.endTransaction() then
					self.sv.saved.hasRevivalItem = true
					self.player:sendCharacterEvent( "baguette" )
					self.network:setClientData( self.sv.saved )
				end
			end
		end
	end

	-- Delays the respawn so clients have time to fade to black
	if self.sv.respawnDelayTimer then
		self.sv.respawnDelayTimer:tick()
		if self.sv.respawnDelayTimer:done() then
			self:sv_e_respawn()
			self.sv.respawnDelayTimer = nil
		end
	end

	-- End of respawn sequence
	if self.sv.respawnEndTimer then
		self.sv.respawnEndTimer:tick()
		if self.sv.respawnEndTimer:done() then
			self.network:sendToClient( self.player, "cl_n_endFadeToBlack", { duration = RespawnEndFadeDuration } )
			self.sv.respawnEndTimer = nil;
		end
	end

	-- If respawn failed, restore the character
	if self.sv.respawnTimeoutTimer then
		self.sv.respawnTimeoutTimer:tick()
		if self.sv.respawnTimeoutTimer:done() then
			self:sv_e_onSpawnCharacter()
		end
	end

	local character = self.player:getCharacter()
	-- Update breathing
	if character then
		if character:isDiving() then
			self.sv.saved.stats.breath = math.max( self.sv.saved.stats.breath - BreathLostPerTick, 0 )
			if self.sv.saved.stats.breath == 0 then
				self.sv.drownTimer:tick()
				if self.sv.drownTimer:done() then
					if self.sv.saved.isConscious then
						print( "'Player' is drowning!" )
						self:sv_takeDamage( DrownDamage, "drown" )
					end
					self.sv.drownTimer:start( DrownDamageCooldown )
				end
			end
		else
			self.sv.saved.stats.breath = self.sv.saved.stats.maxbreath
			self.sv.drownTimer:start( DrownDamageCooldown )
		end

		-- Spend stamina on sprinting
		if character:isSprinting() then
			self.sv.staminaSpend = self.sv.staminaSpend + SprintStaminaCost
		end

		-- Spend stamina on carrying
		if not self.player:getCarry():isEmpty() then
			self.sv.staminaSpend = self.sv.staminaSpend + CarryStaminaCost
		end
	end

	-- Update stamina, food and water stats
	if character and self.sv.saved.isConscious and not g_godMode then
		self.sv.statsTimer:tick()
		if self.sv.statsTimer:done() then
			self.sv.statsTimer:start( StatsTickRate )

			-- Recover health from food
			if self.sv.saved.stats.food > FoodRecoveryThreshold then
				local fastRecoveryFraction = 0

				-- Fast recovery when food is above fast threshold
				if self.sv.saved.stats.food > FastFoodRecoveryThreshold then
					local recoverableHp = math.min( self.sv.saved.stats.maxhp - self.sv.saved.stats.hp, FastHpRecovery )
					local foodSpend = math.min( recoverableHp * FastFoodCostPerHpRecovery, math.max( self.sv.saved.stats.food - FastFoodRecoveryThreshold, 0 ) )
					local recoveredHp = foodSpend / FastFoodCostPerHpRecovery

					self.sv.saved.stats.hp = math.min( self.sv.saved.stats.hp + recoveredHp, self.sv.saved.stats.maxhp )
					self.sv.saved.stats.food = self.sv.saved.stats.food - foodSpend
					fastRecoveryFraction = ( recoveredHp ) / FastHpRecovery
				end

				-- Normal recovery -- TODO: Just set Food and water to max at all times and let health heal more slowly?
				local recoverableHp = math.min( self.sv.saved.stats.maxhp - self.sv.saved.stats.hp, HpRecovery * ( 1 - fastRecoveryFraction ) )
				local foodSpend = math.min( recoverableHp * FoodCostPerHpRecovery, math.max( self.sv.saved.stats.food - FoodRecoveryThreshold, 0 ) )
				local recoveredHp = foodSpend / FoodCostPerHpRecovery

				self.sv.saved.stats.hp = math.min( self.sv.saved.stats.hp + recoveredHp, self.sv.saved.stats.maxhp )
				self.sv.saved.stats.food = self.sv.saved.stats.food - foodSpend
			end

			-- Spend water and food on stamina usage
			self.sv.saved.stats.water = math.max( self.sv.saved.stats.water - self.sv.staminaSpend * WaterCostPerStamina, 0 )
			self.sv.saved.stats.food = math.max( self.sv.saved.stats.food - self.sv.staminaSpend * FoodCostPerStamina, 0 )
			self.sv.staminaSpend = 0

			-- Decrease food and water with time
			self.sv.saved.stats.food = math.max( self.sv.saved.stats.food - FoodLostPerSecond, 0 )
			self.sv.saved.stats.water = math.max( self.sv.saved.stats.water - WaterLostPerSecond, 0 )

			local fatigueDamageFromHp = false
			if self.sv.saved.stats.food <= 0 then
				self:sv_takeDamage( FatigueDamageHp, "fatigue" )
				fatigueDamageFromHp = true
			end
			if self.sv.saved.stats.water <= 0 then
				if not fatigueDamageFromHp then
					self:sv_takeDamage( FatigueDamageWater, "fatigue" )
				end
			end

			self.storage:save( self.sv.saved )
			self.network:setClientData( self.sv.saved )
		end
	end
end

function Player.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if type( attacker ) == "Unit" or ( type( attacker ) == "Shape" and isTrapProjectile( projectileUuid ) ) then
		self:sv_takeDamage( damage, "shock" )
	end
	if self.player.character:isTumbling() then
		ApplyKnockback( self.player.character, hitVelocity:normalize(), 2000 )
	end

	if projectileUuid == projectile_water  then
		self.network:sendToClient( self.player, "cl_n_fillWater" )
	end


end

function Player.cl_n_fillWater( self )
	if self.player == sm.localPlayer.getPlayer() then
		if sm.localPlayer.getActiveItem() == obj_tool_bucket_empty then
			local params = {}
			if sm.game.getLimitedInventory() then
				params.playerInventory = sm.localPlayer.getInventory()
			else
				params.playerInventory = sm.localPlayer.getHotbar()
			end
			params.slotIndex = sm.localPlayer.getSelectedHotbarSlot()
			params.previousUid = obj_tool_bucket_empty
			params.nextUid = obj_tool_bucket_water
			params.previousQuantity = 1
			params.nextQuantity = 1
			self.network:sendToServer( "sv_n_exchangeItem", params )
		end
	end
end

function Player.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if not sm.exists( attacker ) then
		return
	end

	print("'Player' took melee damage haha u suck")
	if type( attacker ) == "Unit" then
		self:sv_takeDamage( damage, "impact" )
	else
		local playerCharacter = self.player.character
		if sm.exists( playerCharacter ) then
			self.network:sendToClients( "cl_n_onEvent", { event = "impact", pos = playerCharacter.worldPosition, damage = damage * 0.01 } )
		end
	end

	-- Melee impulse
	if attacker then
		ApplyKnockback( self.player.character, hitDirection, power )
	end

end

function Player.server_onExplosion( self, center, destructionLevel )
	print("'Player' took explosion damage")
	--self:sv_startTumble( self, LARGE_TUMBLE_TICK_TIME)
	self.player.character:setTumbling( true )
	self:sv_takeDamage( destructionLevel * 2, "impact" )
	if self.player.character:isTumbling() then -- TODO: can set tumbling here
		local knockbackDirection = ( self.player.character.worldPosition - center ):normalize()
		ApplyKnockback( self.player.character, knockbackDirection, 5000 )
	end
end

function Player.sv_startTumble( self, tumbleTickTime )
	if not self.player.character:isDowned() and self.sv.resistTumbleTimer:done() then
		local currentTick = sm.game.getCurrentTick()
		self.sv.recentTumbles[#self.sv.recentTumbles+1] = currentTick
		local recentTumbles = {}
		for _, tumbleTickTimestamp in ipairs( self.sv.recentTumbles ) do
			if tumbleTickTimestamp >= currentTick - RecentTumblesTickTimeInterval then
				recentTumbles[#recentTumbles+1] = tumbleTickTimestamp
			end
		end
		self.sv.recentTumbles = recentTumbles
		if #self.sv.recentTumbles > MaxRecentTumbles then
			-- Too many tumbles in quick succession, gain temporary tumble immunity
			self.player.character:setTumbling( false )
			self.sv.maxTumbleTimer:reset()
			self.sv.tumbleReset:reset()
			self.sv.resistTumbleTimer:reset()
		else
			self.player.character:setTumbling( true )
			if tumbleTickTime then
				self.sv.tumbleReset:start( tumbleTickTime )
			else
				self.sv.tumbleReset:start( StopTumbleTimerTickThreshold )
			end
			return true
		end
	end
	return false
end

function Player.sv_updateTumbling( self )
	if not self.sv.resistTumbleTimer:done() then
		self.sv.resistTumbleTimer:tick()
	end

	if not self.player.character:isDowned() then
		if self.player.character:isTumbling() then
			self.sv.maxTumbleTimer:tick()
			if self.sv.maxTumbleTimer:done() then
				-- Stuck in the tumble state for too long, gain temporary tumble immunity
				self.player.character:setTumbling( false )
				self.sv.maxTumbleTimer:reset()
				self.sv.tumbleReset:reset()
				self.sv.resistTumbleTimer:reset()
			else
				local tumbleVelocity = self.player.character:getTumblingLinearVelocity()
				if tumbleVelocity:length() < 1.0 then
					self.sv.tumbleReset:tick()

					if self.sv.tumbleReset:done() then
						self.player.character:setTumbling( false )
						self.sv.tumbleReset:reset()
					end
				else
					self.sv.tumbleReset:reset()
				end
			end
		end
	end
end

function Player.sv_n_exchangeItem( self, params )
	if sm.container.beginTransaction() then
		sm.container.spendFromSlot( params.playerInventory, params.slotIndex, params.previousUid, params.previousQuantity, true )
		sm.container.collectToSlot( params.playerInventory, params.slotIndex, params.nextUid, params.nextQuantity, true )
		sm.container.endTransaction()
	end
end

function Player.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal  )
	if not self.player.character or not sm.exists( self.player.character ) then
		return
	end

	if not self.sv.impactCooldown:done() then
		return
	end

	local collisionDamageMultiplier = 0.25
	local maxHp = 100
	if self.sv.saved.stats and self.sv.saved.stats.maxhp then
		maxHp = self.sv.saved.stats.maxhp
	end
	local damage, tumbleTicks, tumbleVelocity, impactReaction = CharacterCollision( self.player.character, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal, maxHp / collisionDamageMultiplier, 24 )
	damage = damage * collisionDamageMultiplier
	if damage > 0 or tumbleTicks > 0 then
		self.sv.impactCooldown:start( 0.25 * 40 )
	end
	if damage > 0 then
		print("'Player' took", damage, "collision damage")
		self:sv_takeDamage( damage, "shock" )
	end
	if g_enableCollisionTumble then
		if tumbleTicks > 0 then
			if self:sv_startTumble( tumbleTicks ) then
				-- Limit tumble velocity
				if tumbleVelocity:length2() > MaxTumbleImpulseSpeed * MaxTumbleImpulseSpeed then
					tumbleVelocity = tumbleVelocity:normalize() * MaxTumbleImpulseSpeed
				end
				self.player.character:applyTumblingImpulse( tumbleVelocity * self.player.character.mass )
				if type( other ) == "Shape" and sm.exists( other ) and other.body:isDynamic() then
					sm.physics.applyImpulse( other.body, impactReaction * other.body.mass, true, collisionPosition - other.body.worldPosition )
				end
			end
		end
	end
end



function Player.server_onInventoryChanges( self, container, changes )
	self.network:sendToClient( self.player, "cl_n_onInventoryChanges", { container = container, changes = changes } )
			
end

function Player.sv_e_staminaSpend( self, stamina )
	if not g_godMode then
		if stamina > 0 then
			self.sv.staminaSpend = self.sv.staminaSpend + stamina
		end
	end
end

function Player.sv_e_receiveDamage( self, damageData )
	self:sv_takeDamage( damageData.damage )
end

function Player.sv_takeDamage( self, damage, source )
    if damage > 0 then
		damage = damage * GetDifficultySettings().playerTakeDamageMultiplier -- NOT SURE ABOUT THIS?
		local character = self.player:getCharacter()
		local lockingInteractable = character:getLockingInteractable()
		if lockingInteractable and lockingInteractable:hasSeat() then
			lockingInteractable:setSeatCharacter( character )
		end

		if not g_godMode and self.sv.damageCooldown:done() then
			if self.sv.saved.isConscious then
				self.sv.saved.stats.hp = math.max( self.sv.saved.stats.hp - damage, 0 )

				print( "'Player' took:", damage, "damage.", self.sv.saved.stats.hp, "/", self.sv.saved.stats.maxhp, "HP" )

				if source then
					self.network:sendToClients( "cl_n_onEvent", { event = source, pos = character:getWorldPosition(), damage = damage * 0.01 } )
				else
					self.player:sendCharacterEvent( "hit" )
				end

				if self.sv.saved.stats.hp <= 0 then
					print( "'Player' knocked out!" )
					self.sv.respawnInteractionAttempted = false
					self.sv.saved.isConscious = false
					character:setTumbling( true )
					character:setDowned( true )
				end

				self.storage:save( self.sv.saved )
				self.network:setClientData( self.sv.saved )
			end
		else
			print( "'Player' resisted", damage, "damage" )
		end
	end

end


function Player.sv_n_revive( self )
	local character = self.player:getCharacter()
	if not self.sv.saved.isConscious and self.sv.saved.hasRevivalItem and not self.sv.spawnparams.respawn then
		print( "Player", self.player.id, "revived" )
		self.sv.saved.stats.hp = self.sv.saved.stats.maxhp
		self.sv.saved.stats.food = self.sv.saved.stats.maxfood
		self.sv.saved.stats.water = self.sv.saved.stats.maxwater
		self.sv.saved.isConscious = true
		self.sv.saved.hasRevivalItem = false
		self.storage:save( self.sv.saved )
		self.network:setClientData( self.sv.saved )
		self.network:sendToClient( self.player, "cl_n_onEffect", { name = "Eat - EatFinish", host = self.player.character } )
		if character then
			character:setTumbling( false )
			character:setDowned( false )
		end
		self.sv.damageCooldown:start( 40 )
		self.player:sendCharacterEvent( "revive" )
	end
end


function Player.sv_e_respawn( self ) 
    if self.sv.spawnparams.respawn then
		if not self.sv.respawnTimeoutTimer then
			self.sv.respawnTimeoutTimer = Timer()
			self.sv.respawnTimeoutTimer:start( RespawnTimeout )
		end
		return
	end
	if not self.sv.saved.isConscious then
		--g_respawnManager:sv_performItemLoss( self.player ) -- Removes item loss
		self.sv.spawnparams.respawn = true

		sm.event.sendToGame( "sv_e_respawn", { player = self.player } )
	else
		print( "Player must be unconscious to respawn" )
	end

end


function Player.sv_n_tryRespawn( self )
	if not self.sv.saved.isConscious and not self.sv.respawnDelayTimer and not self.sv.respawnInteractionAttempted then
		self.sv.respawnInteractionAttempted = true
		self.sv.respawnEndTimer = nil;
		self.network:sendToClient( self.player, "cl_n_startFadeToBlack", { duration = RespawnFadeDuration, timeout = RespawnFadeTimeout } )
		
		self.sv.respawnDelayTimer = Timer()
		self.sv.respawnDelayTimer:start( RespawnDelay )
	end
end

function Player.sv_startFadeToBlack( self, param )
	self.network:sendToClient( self.player, "cl_n_startFadeToBlack", { duration = param.duration, timeout = param.timeout } )
end

function Player.sv_endFadeToBlack( self, param )
	self.network:sendToClient( self.player, "cl_n_endFadeToBlack", { duration = param.duration } )
end

function Player.cl_e_startFadeToBlack( self, param )
	self:cl_n_startFadeToBlack( param )
end

function Player.cl_e_endFadeToBlack( self, param )
	self:cl_n_endFadeToBlack( param )
end

function Player.cl_n_startFadeToBlack( self, param )
	sm.gui.startFadeToBlack( param.duration, param.timeout )
end

function Player.cl_n_endFadeToBlack( self, param )
	sm.gui.endFadeToBlack( param.duration )
end

function Player.sv_e_onSpawnCharacter( self ) 
    if self.sv.saved.isNewPlayer then
		-- Intro cutscene for new player
		if not g_survivalDev then
			--self:sv_e_startLocalCutscene( "camera_approach_crash" )
		end
	elseif self.sv.spawnparams.respawn then
		local playerBed = g_respawnManager:sv_getPlayerBed( self.player ) -- Wont work if no player
		if playerBed and playerBed.shape and sm.exists( playerBed.shape ) and playerBed.shape.body:getWorld() == self.player.character:getWorld() then
			-- Attempt to seat the respawned character in a bed
			self.network:sendToClient( self.player, "cl_seatCharacter", { shape = playerBed.shape  } )
		else
			-- Respawned without a bed
			--self:sv_e_startLocalCutscene( "camera_wakeup_ground" )
            print("No bed, where respawn?")
		end

		self.sv.respawnEndTimer = Timer()
		self.sv.respawnEndTimer:start( RespawnEndDelay )
	
	end

	if self.sv.saved.isNewPlayer or self.sv.spawnparams.respawn then
		print( "New player", self.player.id, "spawned" )
		if self.sv.saved.isNewPlayer then
			self.sv.saved.stats.hp = self.sv.saved.stats.maxhp
			self.sv.saved.stats.food = self.sv.saved.stats.maxfood
			self.sv.saved.stats.water = self.sv.saved.stats.maxwater
		else
			self.sv.saved.stats.hp = 100 -- full stats upon respon
			self.sv.saved.stats.food = 100
			self.sv.saved.stats.water = 100
		end
		self.sv.saved.isConscious = true
		self.sv.saved.hasRevivalItem = false
		self.sv.saved.isNewPlayer = false
		self.storage:save( self.sv.saved )
		self.network:setClientData( self.sv.saved )

		self.player.character:setTumbling( false )
		self.player.character:setDowned( false )
		self.sv.damageCooldown:start( 40 )
	else
		-- Player rejoined the game
		if self.sv.saved.stats.hp <= 0 or not self.sv.saved.isConscious then
			self.player.character:setTumbling( true )
			self.player.character:setDowned( true )
		end
	end

	self.sv.respawnInteractionAttempted = false
	self.sv.respawnDelayTimer = nil
	self.sv.respawnTimeoutTimer = nil
	self.sv.spawnparams = {}

	sm.event.sendToGame( "sv_e_onSpawnPlayerCharacter", self.player )

end


function Player.cl_n_onInventoryChanges( self, params )
	if params.container == sm.localPlayer.getInventory() then
		for i, item in ipairs( params.changes ) do
			if item.difference > 0 then
				g_survivalHud:addToPickupDisplay( item.uuid, item.difference )
			end
		end
	end
end


function Player.cl_seatCharacter( self, params )
	if sm.exists( params.shape ) then
		params.shape.interactable:setSeatCharacter( self.player.character )
	end
end

function Player.sv_e_debug( self, params ) 
    if params.hp then
		self.sv.saved.stats.hp = params.hp
	end
	if params.water then
		self.sv.saved.stats.water = params.water
	end
	if params.food then
		self.sv.saved.stats.food = params.food
	end
	self.storage:save( self.sv.saved )
	self.network:setClientData( self.sv.saved )
end

function Player.sv_e_eat( self, edibleParams )
    if edibleParams.hpGain then
		self:sv_restoreHealth( edibleParams.hpGain )
	end
	if edibleParams.foodGain then
		self:sv_restoreFood( edibleParams.foodGain )

		self.network:sendToClient( self.player, "cl_n_onEffect", { name = "Eat - EatFinish", host = self.player.character } )
	end
	if edibleParams.waterGain then
		self:sv_restoreWater( edibleParams.waterGain )
		-- self.network:sendToClient( self.player, "cl_n_onEffect", { name = "Eat - DrinkFinish", host = self.player.character } )
	end
	self.storage:save( self.sv.saved )
	self.network:setClientData( self.sv.saved )
end

function Player.sv_e_feed( self, params )
    if not self.sv.saved.isConscious and not self.sv.saved.hasRevivalItem then
		if sm.container.beginTransaction() then
			sm.container.spend( params.playerInventory, params.foodUuid, 1, true )
			if sm.container.endTransaction() then
				self.sv.saved.hasRevivalItem = true
				self.player:sendCharacterEvent( "baguette" )
				self.network:setClientData( self.sv.saved )
			end
		end
	end

end


function Player.sv_restoreHealth( self, health )
	if self.sv.saved.isConscious then
		self.sv.saved.stats.hp = self.sv.saved.stats.hp + health
		self.sv.saved.stats.hp = math.min( self.sv.saved.stats.hp, self.sv.saved.stats.maxhp )
		print( "'Player' restored:", health, "health.", self.sv.saved.stats.hp, "/", self.sv.saved.stats.maxhp, "HP" )
	end
end

function Player.sv_restoreFood( self, food )
	if self.sv.saved.isConscious then
		food = food * ( 0.8 + ( self.sv.saved.stats.maxfood - self.sv.saved.stats.food ) / self.sv.saved.stats.maxfood * 0.2 )
		self.sv.saved.stats.food = self.sv.saved.stats.food + food
		self.sv.saved.stats.food = math.min( self.sv.saved.stats.food, self.sv.saved.stats.maxfood )
		print( "'Player' restored:", food, "food.", self.sv.saved.stats.food, "/", self.sv.saved.stats.maxfood, "FOOD" )
	end
end

function Player.sv_restoreWater( self, water )
	if self.sv.saved.isConscious then
		water = water * ( 0.8 + ( self.sv.saved.stats.maxwater - self.sv.saved.stats.water ) / self.sv.saved.stats.maxwater * 0.2 )
		self.sv.saved.stats.water = self.sv.saved.stats.water + water
		self.sv.saved.stats.water = math.min( self.sv.saved.stats.water, self.sv.saved.stats.maxwater )
		print( "'Player' restored:", water, "water.", self.sv.saved.stats.water, "/", self.sv.saved.stats.maxwater, "WATER" )
	end
end


function Player.server_onShapeRemoved( self, removedShapes )
	local numParts = 0
	local numBlocks = 0
	local numJoints = 0



	for _, removedShapeType in ipairs( removedShapes ) do
		if removedShapeType.type == "block"  then
			numBlocks = numBlocks + removedShapeType.amount
		elseif removedShapeType.type == "part"  then
			numParts = numParts + removedShapeType.amount
		elseif removedShapeType.type == "joint"  then
			numJoints = numJoints + removedShapeType.amount
		end
	end

	local staminaSpend = numParts + numJoints + math.sqrt( numBlocks )
	--self:sv_e_staminaSpend( staminaSpend )
end

function Player.sv_e_setRefiningState( self, params )
	local userPlayer = params.user:getPlayer()
	if userPlayer then
		if params.state == true then
			userPlayer:sendCharacterEvent( "refine" )
		else
			userPlayer:sendCharacterEvent( "refineEnd" )
		end
	end
end


function Player.cl_updateCamera( self, dt )
	if self.cl.cutsceneEffect then
        print("in cutscente????")
		local cutscenePos = self.cl.cutsceneEffect:getCameraPosition()
		local cutsceneRotation = self.cl.cutsceneEffect:getCameraRotation()
		local cutsceneFOV = self.cl.cutsceneEffect:getCameraFov()
		if cutscenePos == nil then cutscenePos = sm.camera.getPosition() end
		if cutsceneRotation == nil then cutsceneRotation = sm.camera.getRotation() end
		if cutsceneFOV == nil then cutsceneFOV = sm.camera.getFov() end

		if self.cl.cutsceneEffect:isPlaying() then
			self.cl.followCutscene = math.min( self.cl.followCutscene + dt / CUTSCENE_FADE_IN_TIME, 1.0 )
		else
			self.cl.followCutscene = math.max( self.cl.followCutscene - dt / CUTSCENE_FADE_OUT_TIME, 0.0 )
		end

		local lerpedCameraPosition = sm.vec3.lerp( sm.camera.getDefaultPosition(), cutscenePos, self.cl.followCutscene )
		local lerpedCameraRotation = sm.quat.slerp( sm.camera.getDefaultRotation(), cutsceneRotation, self.cl.followCutscene )
		local lerpedCameraFOV = lerp( sm.camera.getDefaultFov(), cutsceneFOV, self.cl.followCutscene )
		print(self.cl.followCutscene)
		sm.camera.setPosition( lerpedCameraPosition )
		sm.camera.setRotation( lerpedCameraRotation )
		sm.camera.setFov( lerpedCameraFOV )

		if self.cl.followCutscene <= 0.0 and not self.cl.cutsceneEffect:isPlaying() then
			sm.gui.hideGui( false )
			sm.camera.setCameraState( sm.camera.state.default )
			--sm.localPlayer.setLockedControls( false )
			self.cl.cutsceneEffect:destroy()
			self.cl.cutsceneEffect = nil
		end
	else
		self.cl.followCutscene = 0.0
	end
end



function Player.sv_e_onLoot( self, params )
	self.network:sendToClient( self.player, "cl_n_onLoot", params )
end

function Player.cl_n_onLoot( self, params )
	local color
	if params.uuid then
		color = sm.shape.getShapeTypeColor( params.uuid )
	end
	local effectName = params.effectName or "Loot - Pickup"
	sm.effect.playEffect( effectName, params.pos, sm.vec3.zero(), sm.quat.identity(), sm.vec3.one(), { ["Color"] = color } )
end

function Player.sv_e_onMsg( self, msg )
	self.network:sendToClient( self.player, "cl_n_onMsg", msg )
end

function Player.cl_n_onMsg( self, msg )
	sm.gui.displayAlertText( msg )
end

function Player.cl_n_onEffect( self, params )
	if params.host then
		sm.effect.playHostedEffect( params.name, params.host, params.boneName, params.parameters )
	else
		sm.effect.playEffect( params.name, params.position, params.velocity, params.rotation, params.scale, params.parameters )
	end
end

function Player.sv_e_onStayPesticide( self )
	if self.sv.poisonDamageCooldown:done() then
		self:sv_takeDamage( PoisonDamage, "poison" )
		self.sv.poisonDamageCooldown:start( PoisonDamageCooldown )
	end
end

function Player.sv_e_onEnterFire( self )
	if self.sv.fireDamageCooldown:done() then
		self:sv_takeDamage( FireDamage, "fire" )
		self.sv.fireDamageCooldown:start( FireDamageCooldown )
	end
end

function Player.sv_e_onStayFire( self )
	if self.sv.fireDamageCooldown:done() then
		self:sv_takeDamage( FireDamage, "fire" )
		self.sv.fireDamageCooldown:start( FireDamageCooldown )
	end
end

function Player.sv_e_onEnterChemical( self )
	if self.sv.poisonDamageCooldown:done() then
		self:sv_takeDamage( PoisonDamage, "poison" )
		self.sv.poisonDamageCooldown:start( PoisonDamageCooldown )
	end
	self.sv.saved.inChemical = true
	self.network:setClientData( self.sv.saved )
end

function Player.sv_e_onStayChemical( self )
	if self.sv.poisonDamageCooldown:done() then
		self:sv_takeDamage( PoisonDamage, "poison" )
		self.sv.poisonDamageCooldown:start( PoisonDamageCooldown )
	end
end

function Player.sv_e_onExitChemical( self )
	self.sv.saved.inChemical = false
	self.network:setClientData( self.sv.saved )
end

function Player.sv_e_onEnterOil( self )
	self.sv.saved.inOil = true
	self.network:setClientData( self.sv.saved )
end

function Player.sv_e_onExitOil( self )
	self.sv.saved.inOil = false
	self.network:setClientData( self.sv.saved )
end

function Player.client_onCancel( self )
	local myPlayer = sm.localPlayer.getPlayer()
	local myCharacter = myPlayer and myPlayer.character or nil
	if sm.exists( myCharacter ) then
		sm.event.sendToCharacter( myCharacter, "cl_e_onCancel" )
	end
    g_effectManager:cl_cancelAllCinematics()
end

function Player.cl_n_onMessage( self, params )
	local message = params.message or ""
	local displayTime = params.displayTime or 2
	sm.gui.displayAlertText( message, displayTime )
end