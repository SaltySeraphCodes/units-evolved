dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Ticker.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/CombatAttackState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_meleeattacks.lua" )
dofile "$CONTENT_DATA/Scripts/units/states/PathingState.lua"
--dofile("$CONTENT_DATA/Scripts/Timer.lua") 

--TODO: Possibly have a timer for chats? or do they stay forever until next one?
WocUnit = class( nil )

local RoamStartTimeMin = 40 * 1 -- 1 seconds
local RoamStartTimeMax = 40 * 1.5 -- 1.5 seconds
local FleeTimeMin = 40 * 7 -- 7 seconds
local FleeTimeMax = 40 * 10 -- 10 seconds
local EdibleSearchRadius = 6.0
local EdibleReach = 1.75
local CornPerMilk = 3
local CombatAttackRange = 2 -- Range where the unit will perform attacks
local CombatFollowRange = 10.0 -- Range where the unit will follow and attack the player
local FireRange = 16.0 -- TODO: make dynamic based on spells?
local FireLaneWidth = 0.8
local ShotsPerBarrage = 3
local RangedHeightDiff = 3 -- Height difference where the farmbot considers the target position to be hard to reach
local RangedPitchAngle = 10 -- Angle in degrees where the farmbot considers the target position to be hard to reach
-- 0  = wander/stop
-- 1 = follow
-- 2 = goto
-- 3 = flee
-- 4 = eat
-- 5 = attack
function WocUnit.server_onCreate( self )

	self.target = nil
	self.previousTarget = nil
	self.lastTargetPosition = nil
	self.lastAimPosition = nil
	self.ambushPosition = nil
	self.predictedVelocity = sm.vec3.new( 0, 0, 0 )

	self.username = self.unit.id
	self.userid = self.unit.id

	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end

	-- load params from previous json db when spawning in  for data persistence
	-- state needs translation
	if self.saved.stats == nil then
		self.saved.stats = { hp = 15, maxhp = 100, cornEaten = 0, attackPower = 25, defensePower = 1, actionPoints = 100, maxAp = 100,
							kills = 0, deaths = 0, state = 0, xp = 0, level = 0					
	} -- todo: actually load these up from previous data && Also minimize
	end

	if self.params then
		if self.params.tetherPoint then
			self.homePosition = self.params.tetherPoint + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 )
		end
		if self.params.deathTick then
			self.saved.deathTickTimestamp = self.params.deathTick
		end
	end
	if not self.homePosition then
		self.homePosition = self.unit.character.worldPosition
	end
	if not self.saved.deathTickTimestamp then
		self.saved.deathTickTimestamp = sm.game.getCurrentTick() + DaysInTicks( 30 )
	end

	--print("Server create",self.params.chatterData)
	self.world = self.unit.character:getWorld()
	--print("world??",self.world)
	if self.params ~= nil and self.params.chatterData ~= nil then
		local chatterData = self.params.chatterData
		
		if chatterData.username ~= nil then
			self.username = chatterData.username
			--sm.event.sendToCharacter(self.unit.character, "sv_recieveEvent", {event = "setName", data = self.username} )
		end
		if chatterData.userid ~= nil then
			self.userid = chatterData.userid
			--sm.event.sendToCharacter(self.unit.character, "sv_recieveEvent", {event = "setId", data =self.userid} )
		end

		if chatterData.world and self.world == nil then
			self.world = chatterData.world
			--print("got new world",world)
		end

		-- Set big stats here, 
		self.unit:setPublicData({
			username = (self.username or self.unit.id),
			userid = (self.userid or self.unit.id),
			stats = self.saved.stats
		})
	end
	-- if self.data set self.username and self.userid
	-- call character events
	self.storage:save( self.saved )

	self.unit:setWhiskerData( 4, 60 * math.pi / 180, 1.5, 5.0 )
	self.impactCooldownTicks = 0

	self.stateTicker = Ticker()
	self.stateTicker:init()

	-- Idle
	self.idleState = self.unit:createState( "idle" )
	self.idleState.randomEvents = { { name = "eat", chance = 0.2, interruptible = false, time = 4 }} -- took out random moos { name = "moo", chance = 0.4 } }
							   		
	self.idleState.debugName = "idleState"

	-- Roam
	self.roamTimer = Timer()
	self.roamTimer:start( math.random( RoamStartTimeMin, RoamStartTimeMax ) )
	self.roamState = self.unit:createState( "flockingRoam" )
	self.roamState.tetherPosition = self.homePosition
	self.roamState.roamCenterOffset = 0.0

	-- attack
	self.attackState03 = self.unit:createState( "meleeAttack" )
	self.attackState03.meleeType = melee_sledgehammer
	self.attackState03.event = "standingswipe"
	self.attackState03.damage = 35
	self.attackState03.attackRange = 3.75
	self.attackState03.animationCooldown = 1.86 * 40
	self.attackState03.attackCooldown = 1.75 * 40
	self.attackState03.globalCooldown = 0.0 * 40
	self.attackState03.attackDelay = 0.75 * 40
	
	-- Combat
	self.combatAttackState = CombatAttackState()
	self.combatAttackState:sv_onCreate( self.unit )
	self.combatAttackState.debugName = "combatAttackState"
	self.stateTicker:addState( self.combatAttackState )
	self.combatAttackState:sv_addAttack( self.attackState03 )
	
	-- Flee
	self.fleeState = self.unit:createState( "flee" )
	self.fleeState.movementAngleThreshold = math.rad( 180 )
	
	-- Pathing
	self.pathingState = PathingState()
	self.pathingState:sv_onCreate( self.unit )
	self.pathingState:sv_setTolerance( EdibleReach )
	self.pathingState:sv_setMovementType( "walk" )
	self.pathingState:sv_setWaterAvoidance( false )
	self.pathingState:sv_setWhiskerAvoidance( true )
	self.pathingState.debugName = "pathingState"

	-- Eat
	self.eatEventState = self.unit:createState( "wait" )
	self.eatEventState.debugName = "eatEventState"
	self.eatEventState.time = 4.0
	self.eatEventState.interruptible = false
	self.eatEventState.name = "eat"

	-- Tumble
	initTumble( self )
	
	-- Crushing
	initCrushing( self, DEFAULT_CRUSH_TICK_TIME )
	
	self.currentState = self.idleState
	self.currentState:start()
	--print('loaded',self.username,self.userid)

end

function WocUnit.server_onRefresh( self )
	print( "-- WocUnit refreshed --",self.userid,self.saved,self.username )
	self.currentState = self.idleState
	self.target = nil
	self.lastTargetPosition = nil
end

function WocUnit.server_onDestroy( self )
	print( "-- WocUnit terminated --",self.username)
	if self.userid then
		--print("sending kill to world",self.world)
		sm.event.sendToWorld(self.world,'sv_e_unit_killed',self.userid)
		sm.event.sendToGame('sv_e_unit_killed',self.userid)
	end

end

function WocUnit.server_onFixedUpdate( self, dt )
	self.unit:setPublicData({ -- TODO: update this only on change?
		username = self.username,
		userid = self.userid,
		stats = self.saved.stats
	})
	--print(self.unit.publicData)

	-- call character events
	if sm.exists( self.unit ) and not self.destroyed then
		if self.saved.deathTickTimestamp and sm.game.getCurrentTick() >= self.saved.deathTickTimestamp then
			self.unit:destroy()
			self.destroyed = true
			return
		end
	end

	if self.unit.character:isSwimming() then
		self.roamState.cliffAvoidance = false
		self.pathingState:sv_setCliffAvoidance( false )
	else
		self.roamState.cliffAvoidance = true
		self.pathingState:sv_setCliffAvoidance( true )
	end

	if updateCrushing( self ) then
		print("homie was crushed! D:")
		self:sv_takeDamage( self.saved.stats.maxhp )
	end
	
	updateTumble( self )
	updateAirTumble( self, self.idleState )

	if self.currentState then
		self.currentState:onFixedUpdate( dt )
		self.unit:setMovementDirection( self.currentState:getMovementDirection() )
		self.unit:setMovementType( self.currentState:getMovementType() )
		self.unit:setFacingDirection( self.currentState:getFacingDirection() )
		
		-- Random roaming during idle
		if self.currentState == self.idleState then
			self.roamTimer:tick() -- or not...
		end
		self.impactCooldownTicks = math.max( self.impactCooldownTicks - 1, 0 )
	end

	if self.saved.stats.cornEaten >= CornPerMilk then
		self.saved.stats.cornEaten = self.saved.stats.cornEaten - CornPerMilk
		self.saved.stats.hp = self.saved.stats.maxhp
		self.saved.deathTickTimestamp = sm.game.getCurrentTick() + DaysInTicks( 30 ) -- Neglected Wocs die after 30 days
		if SurvivalGame then
			local loot = SelectLoot( "loot_woc_milk" )
			SpawnLoot( self.unit, loot )
		end
		self.storage:save( self.saved )
	end
end

function WocUnit.server_onUnitUpdate( self, dt )
	if not sm.exists( self.unit ) then
		return
	end

	-- attacking overrides

if self.target and not sm.exists( self.target ) then
	self.target = nil
	self.lastTargetPosition = nil
end

local inFireRange = false
local atUnreachableHeight = false
local inCombatFollowRange = false
local inCombatAttackRange = false
local inSprintRange = false
if self.target then
	self.lastTargetPosition = self.target.character.worldPosition
end

if  self.lastTargetPosition then
	local targetChar = self.target.character
	local fromToTarget = self.lastTargetPosition - self.unit.character.worldPosition
	local predictionScale = fromToTarget:length() / math.max( self.unit.character.velocity:length(), 1.0 )
	local predictedPosition = self.lastTargetPosition + self.predictedVelocity * predictionScale
	local desiredDirection = predictedPosition - self.unit.character.worldPosition
	local targetRadius = 0.0
	if targetChar and type( targetChar ) == "Character" then
		targetRadius = targetChar:getRadius()
	end

	inFireRange = fromToTarget:length() - targetRadius <= FireRange
	inCombatFollowRange = fromToTarget:length() - targetRadius <= CombatFollowRange
	inCombatAttackRange = fromToTarget:length() - targetRadius <= CombatAttackRange
	--print(inCombatAttackRange)
	if inCombatAttackRange then	
		self.saved.stats.state = 5
		local flatFromToTarget = sm.vec3.new( fromToTarget.x, fromToTarget.y, 0 )
		flatFromToTarget = ( flatFromToTarget:length() >= FLT_EPSILON ) and flatFromToTarget:normalize() or self.unit.character.direction
		local flatDesiredDirection = sm.vec3.new( desiredDirection.x, desiredDirection.y, 0 )
		flatDesiredDirection = ( flatDesiredDirection:length() >= FLT_EPSILON ) and flatDesiredDirection:normalize() or self.unit.character.direction
		
		local pitchAngle = math.deg( math.acos( flatFromToTarget:dot( fromToTarget:normalize() ) ) )
		atUnreachableHeight = pitchAngle >= RangedPitchAngle and math.abs( fromToTarget.z ) >= RangedHeightDiff
		-- set delay & knockback depending on tool?

		local attackStrength =  self.saved.stats.attackPower
		local atkorigin = self.unit.character.worldPosition + self.unit.character.direction * 0.875 - sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.375 )
		local attackRange = 5
		local attackDirection = self.unit.character.direction * attackRange
		local attackDelay = 0
		local knockback = 3000
		--print("atatckking")
		sm.melee.meleeAttack( melee_sledgehammer,attackStrength, atkorigin,attackDirection, self.unit, attackDelay, knockback )
		self.target = nil
		self.lastTargetPosition = nil
		self.isFollowing = nil
	else
		--print('chasing')
		self.isFollowing = self.target
	end

	-- unset target, depending on hit or miss...

end

	-- also follow test
	if self.isFollowing then
		self.saved.stats.state = 1
		if not sm.exists( self.isFollowing ) then
			self.isFollowing = nil
			return
		end
		local targetLocation = self.isFollowing:getCharacter():getWorldPosition() -- should be universal
		local distanceFromTarget = ( self.unit.character.worldPosition - targetLocation ):length2()
		if distanceFromTarget > 100 then
			self.pathingState:sv_setMovementType( "sprint" )
		elseif distanceFromTarget <=4 then
			self.pathingState:sv_setMovementType( "walk" )
		end
		if	distanceFromTarget > 2 and not self.fleeFrom  then
			self.pathingState:sv_setDestination( targetLocation)
		else
		end
	end
	-- end followtest

	-- goto 
	if self.isGoto then
		self.saved.stats.state = 2
		local targetLocation = self.isGoto -- should already be vec3
		--print("woc going to",targetLocation)
		local distanceFromTarget = ( self.unit.character.worldPosition - targetLocation ):length2()
		if distanceFromTarget > 100 then
			self.pathingState:sv_setMovementType( "sprint" )
		elseif distanceFromTarget <10 then
			self.pathingState:sv_setMovementType( "walk" )
		end
		if	distanceFromTarget > 5 and not self.fleeFrom  then -- play with this until feeling it
			self.pathingState:sv_setDestination( targetLocation)
		else
			self.saved.stats.state = 0
			self.isGoto = nil
		end
	end

	if self.currentState then
		self.currentState:onUnitUpdate( dt )
	end

	if self.unit.character:isTumbling() then
		return
	end

	-- Find corn -- overridden by commands
	-- DRAFT
	--[[
		self.desiredAction = wander ()
		if wandering, then go to idle state and keep finding corn
			if self.desiredAction = follow then make state walk if close but run if far, using target
				-- flee will find and set fleefrom, just need to do follow properly
	]]

	local targetCorn, cornInRange FindNearbyEdible( self.unit.character, obj_resource_corn, EdibleSearchRadius, EdibleReach )
				-- TODO: reduce edible search radius?
	local prevState = self.currentState
	local done, result = self.currentState:isDone()
	local abortState = 	(
							( self.fleeFrom ) or
							( ( self.currentState == self.pathingState or self.currentState == self.roamState ) and cornInRange )
						)
	if ( done or abortState ) then
		-- Select state
		if self.fleeFrom then
			self.saved.stats.state = 3
			self:sv_flee( self.fleeFrom )
			prevState = self.currentState
			self.fleeFrom = nil
			--print('fleestate')
		elseif self.currentState == self.fleeState or self.currentState == self.eatEventState then
			--print("otherstaet")
			self.currentState = self.idleState
		elseif targetCorn then
			--print("corntarget")
			self.saved.stats.state = 4
			if cornInRange then
				self.currentState = self.eatEventState
				self.saved.stats.cornEaten = self.saved.stats.cornEaten + 1
				targetCorn:destroyShape()
				self.saved.hp = self.saved.stats.hp + 25
				self.storage:save( self.saved )
			else
				self.pathingState:sv_setDestination( targetCorn.worldPosition )
				self.currentState = self.pathingState
			end
		elseif self.roamTimer:done() and not ( self.currentState == self.idleState and result == "started" ) then
			self.saved.stats.state = 0
			self.roamTimer:start( math.random( RoamStartTimeMin, RoamStartTimeMax ) )
			self.currentState = self.roamState -- ENable or disable Roaming here
			--print("wocroam")

		elseif self.isFollowing then  -- and self.followTarget
			--[[ follow prototype]]
			self.saved.stats.state = 1
			--local player = sm.player.getAllPlayers()[1]
			--local location = player:getCharacter():getWorldPosition()
			if not sm.exists( self.isFollowing ) then
				self.isFollowing = nil
				return
			end
			local targetLocation = self.isFollowing:getCharacter():getWorldPosition() -- should be universal
			local distanceFromTarget = ( self.unit.character.worldPosition - targetLocation ):length2()
			if distanceFromTarget > 15 then
				self.pathingState:sv_setDestination( targetLocation)
				self.currentState = self.pathingState -- TDODO: may cause random bugs
				self.currentState:start()
			end

		elseif self.isGoto then  -- BUG: cow stops on /stop and does not go again
			self.saved.stats.state = 2
			local targetLocation = self.isGoto -- should be universal
			local distanceFromTarget = ( self.unit.character.worldPosition - targetLocation ):length2()
			if distanceFromTarget > 3 then
				self.pathingState:sv_setDestination( targetLocation)
				self.currentState = self.pathingState -- TDODO: may cause random bugs
				self.currentState:start()
			end

		elseif not ( self.currentState == self.roamState and result == "roaming" ) then -- TODO: integrate followstae better
			self.saved.stats.state = 0
			self.currentState = self.idleState -- Original IDLE.
		end
	end

	if prevState ~= self.currentState then
		prevState:stop()
		self.saved.stats.state = 0
		self.currentState:start()
		if DEBUG_AI_STATES then
			print( self.currentState.debugName )
		end
	end
end

function WocUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if not sm.exists( self.unit ) or not sm.exists( attacker ) then
		return
	end
	if damage > 0 then
		--if self.fleeFrom == nil then
		--	self.fleeFrom = attacker -- Removed woc auto flee
			self.unit:sendCharacterEvent( "hit" )
		--end
	end

	self:sv_takeDamage( damage )
end




function WocUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if not sm.exists( self.unit ) or not sm.exists( attacker ) then
		return
	end
	--[[ retaliation script
	for _, allyUnit in ipairs( sm.unit.getAllUnits() ) do
		if sm.exists( allyUnit ) and self.unit ~= allyUnit and allyUnit.character and InSameWorld( self.unit, allyUnit) then
			local inAllyRange = ( allyUnit.character.worldPosition - self.unit.character.worldPosition ):length() <= 50
			if inAllyRange then
				print("got new target",allyUnit,self.target)
				self.target = allyUnit
				--sm.event.sendToUnit( allyUnit, "sv_e_receiveTarget", { targetCharacter = targetCharacter, sendingUnit = self.unit } )
				--print("got",self.target,targetCharacter)
			end
		end
	end
	foundTarget = true

	--]]
	



	if self.fleeFrom == nil then
		--self.fleeFrom = attacker
		self.unit:sendCharacterEvent( "hit" )
	end

	startTumble( self, SMALL_TUMBLE_TICK_TIME, self.idleState )
	self:sv_takeDamage( damage ) -- TODO: add defense here
	ApplyKnockback( self.unit.character, hitDirection, power )
end

function WocUnit.server_onExplosion( self, center, destructionLevel )
	if not sm.exists( self.unit ) then
		return
	end
	if self.fleeFrom == nil then
		--self.fleeFrom = center
		self.unit:sendCharacterEvent( "hit" )
	end

	startTumble( self, LARGE_TUMBLE_TICK_TIME, self.idleState )
	local knockbackDirection = ( self.unit.character.worldPosition - center ):normalize()
	
	--print("onexp",destructionLevel,25000*destructionLevel)
	if self.unit.character:isTumbling() then -- TODO: can set tumbling here
		ApplyKnockback( self.unit.character, knockbackDirection, 4000 * destructionLevel )
	--else
	--	ApplyKnockback( self.unit.character, knockbackDirection, 5000 * destructionLevel )
	end

	self:sv_takeDamage( destructionLevel*15 )
end

function WocUnit.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	if not sm.exists( self.unit ) then
		return
	end

	if self.impactCooldownTicks > 0 then
		return
	end

	local damage, tumbleTicks, tumbleVelocity, impactReaction = CharacterCollision( self.unit.character, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal, self.saved.stats.maxhp )
	if damage > 0 or tumbleTicks > 0 then
		self.impactCooldownTicks = 6
	end
	if damage > 0 then
		print("'WocUnit' took", damage, "collision damage")
		self:sv_takeDamage( damage )
	end
	if tumbleTicks > 0 then
		if startTumble( self, tumbleTicks, self.idleState, tumbleVelocity ) then
			if type( other ) == "Shape" and sm.exists( other ) and other.body:isDynamic() then
				sm.physics.applyImpulse( other.body, impactReaction * other.body.mass, true, collisionPosition - other.body.worldPosition )
			end
		end
	end
end

function WocUnit.server_onCollisionCrush( self )
	if not sm.exists( self.unit ) then
		return
	end
	onCrush( self )
end

function WocUnit.sv_flee( self, from )
	if not sm.exists( self.unit ) or not sm.exists( from ) then
		return
	end
	self.currentState:stop()
	self.currentState = self.fleeState
	self.fleeState.fleeFrom = from
	self.fleeState.maxFleeTime = math.random( FleeTimeMin, FleeTimeMax ) / 40
	self.fleeState.maxDeviation = 45 * math.pi / 180
	self.currentState:start()
end

function WocUnit.sv_takeDamage( self, damage ) -- use defense stat here
	if self.saved.stats.hp > 0 then
		self.saved.stats.hp = self.saved.stats.hp - damage
		self.saved.stats.hp = math.max( self.saved.stats.hp, 0 )
		print( "'WocUnit' received:", damage, "damage.", self.saved.stats.hp, "/", self.saved.stats.maxhp, "HP" )

		if self.saved.stats.hp <= 0 then
			self:sv_onDeath()
			sm.effect.playEffect( "Woc - Destruct", self.unit.character.worldPosition )
		else
			self.storage:save( self.saved )
			sm.effect.playEffect( "Woc - Panic", self.unit.character.worldPosition )
		end
	end
end

function WocUnit.sv_onDeath( self ) -- Increment death counter
	local character = self.unit:getCharacter()
	if not self.destroyed then
		self.saved.stats.hp = 0
		self.saved.stats.deaths = self.saved.stats.deaths + 1
		-- update and export data
		self.unit:destroy()
		print("'WocUnit' killed!")
		
		if SurvivalGame then
			local loot = SelectLoot( "loot_woc" )
			SpawnLoot( self.unit, loot )
		end
		self.destroyed = true
	end
end


-- custom event recieveing


function WocUnit.sv_recieveEvent(self,params)
	--print("Got unit server event",params)
	if params.event == "setName" then 
		self.name = params.data
		-- if no work then self.unit:sendCharacterEvent( "hit" )
		--sm.event.sendToCharacter(self.unit.character, "sv_recieveEvent", {event = "setName", data = params.data} )
	elseif params.event == "setId" then
		self.userid = params.data
		--sm.event.sendToCharacter(self.unit.character, "sv_recieveEvent", {event = "setId", data = params.data} )
	elseif params.event == "setChat" then
		--print("unit got chat data",params.data)
		if self.unit.character == nil then return end
		self.chatMessage = params.data

		sm.event.sendToCharacter(self.unit.character, "sv_recieveEvent", {event = "setChat", data = params.data} )
		self.unit:sendCharacterEvent( "moo" )
	elseif params.event == "setFollow" then
		--print("Changing state to follow",params.data) --TODO: complete this
		--self.currentState:stop()
		self.target = nil
		self.isGoto = nil
		self.fleeFrom = nil
		self.isFollowing = params.data
	elseif params.event == "setAttack" then -- sets target to attack is
		self.isGoto = nil
		self.fleeFrom = nil
		self.isFollowing = nil
		self.target = params.data
	elseif params.event == "setGoto" then
		--print("Changing state to goto",params.data) --TODO: complete this
		--self.currentState:stop()
		self.fleeFrom = nil
		self.isFollowing = nil
		self.target = nil
		self.isGoto = params.data
	elseif params.event == "setFlee" then
		self.fleeFrom = params.data
		self.isFollowing = nil -- remove that
		self.target = nil
		self.isGoto = nil
	elseif params.event == "setStop" then
		self.currentState:stop()
		self.isFollowing = nil
		self.fleeFrom = nil
		self.isGoto = nil
		self.saved.stats.state = 0
		self.currentState = self.idleState -- Original IDLE.
		self.currentState:start()
	elseif params.event == "explode" then
		sm.effect.playEffect( "Woc - Panic", self.unit.character.worldPosition ) -- probably wont work
		sm.event.sendToCharacter(self.unit.character, "sv_recieveEvent", {event = "explode", data = params.data} )
		self.currentState:stop() -- kills woc from any state
		self.isFollowing = nil
		self.fleeFrom = nil
		self.isGoto = nil
	end
end


function WocUnit.cl_recieveEvent(self,params)
	print("Got unit  Client event",params)
	if params.event == "setName" then 
		self.name = params.data
	elseif params.event == "setId" then
		self.userid = params.data
	elseif params.event == "chat" then
		self.chatMessage = params.data
	elseif params.event == "setState" then
		print("Changing state") --TODO: complete this
	end
end