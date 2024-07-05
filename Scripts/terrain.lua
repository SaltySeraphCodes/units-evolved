-- Combination of terrain and other things
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/tile_database.lua" )
--dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/processing.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/type_meadow.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/type_forest.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/type_field.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/type_burntForest.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/type_autumnForest.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/type_lake.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/type_desert.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/roads_and_cliffs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/celldata.lua" )

dofile( "$SURVIVAL_DATA/Scripts/terrain/terrain_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/terrain_util2.lua" )
g_isEditor = g_isEditor or false -- this isnt really needed

----------------------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------------------

ERROR_TILE_UUID = sm.uuid.new( "723268d4-8d59-4500-a433-7d900b61c29c" )

CELL_SIZE = 64

local TYPE_MEADOW = 1
local TYPE_FOREST = 2
local TYPE_DESERT = 3
local TYPE_FIELD = 4
local TYPE_BURNTFOREST = 5
local TYPE_AUTUMNFOREST = 6
local TYPE_LAKE = 8


local FENCE_MIN_CELL = -16 -- TODO: change this for larger world
local FENCE_MAX_CELL = 16

local DESERT_FADE_START = ( FENCE_MAX_CELL - 0.2 ) * CELL_SIZE
local DESERT_FADE_END = ( FENCE_MAX_CELL ) * CELL_SIZE
local DESERT_FADE_RANGE = DESERT_FADE_END - DESERT_FADE_START
local GRAPHICS_CELL_PADDING = 6

local function updateDesertFade( iMin, iMax )
	FENCE_MIN_CELL = iMin
	FENCE_MAX_CELL = iMax

	DESERT_FADE_START = ( FENCE_MAX_CELL - 0.2 ) * CELL_SIZE
	DESERT_FADE_END = ( FENCE_MAX_CELL ) * CELL_SIZE
	DESERT_FADE_RANGE = DESERT_FADE_END - DESERT_FADE_START
end


----------------------------------------------------------------------------------------------------
-- Data
----------------------------------------------------------------------------------------------------

local f_uidToPath = {}

local function getOrCreateTileId( path, temp )
	if temp.pathToUid[path] == nil then
		local uid = sm.terrainTile.getTileUuid( path )
		temp.nextLegacyId = temp.nextLegacyId + 1
		temp.pathToUid[path] = uid
		print( "Added tile "..path..": {"..tostring(uid).."}" )
	end
	
	return temp.pathToUid[path]
end

local function setCell(cell, uid )
	g_cellData.uid[cell.y][cell.x] = uid
	g_cellData.xOffset[cell.y][cell.x] = cell.offsetX
	g_cellData.yOffset[cell.y][cell.x] = cell.offsetY
	g_cellData.rotation[cell.y][cell.x] = cell.rotation
end

function setFence( cellX, cellY, dir, seed, temp )
	local path = "$GAME_DATA/Terrain/Tiles/CreativeTiles/Auto/Fence"..dir
	
	if dir == "NE" or dir == "NW" or dir == "SE" or dir == "SW" then
		path = path..".tile"
	elseif dir == "N" or dir == "S" or dir == "E" or dir == "W" then
		local idx = 1 + sm.noise.intNoise2d( cellX, cellY, seed ) % 3
		path = path.."_0"..idx..".tile"
	end
	
	local cellData = { x = cellX, y = cellY, offsetX = 0, offsetY = 0, rotation = 0 }
	
	setCell( cellData, getOrCreateTileId( path, temp ) )
end


----------------------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------------------


function Init()
	--print( "Initializing MY custom evovled terrain" )
	initForestTiles()
	initDesertTiles()
	initMeadowTiles()
	initLakeTiles()
	initFieldTiles()
	initBurntForestTiles()
	initAutumnForestTiles()
	initRoadAndCliffTiles()
end


local function initializeCellData( xMin, xMax, yMin, yMax, seed )
	-- Version history:
	-- 2:	Changes integer 'tileId' to 'uid' from tile uuid
	--		Renamed 'tileOffsetX' -> 'xOffset'
	--		Renamed 'tileOffsetY' -> 'yOffset'
	--		Added 'version'
	--		TODO: Implement upgrade

	g_cellData = {
		bounds = { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax },
		seed = seed,
		-- Per Cell
		uid = {},
		xOffset = {},
		yOffset = {},
		rotation = {},
		-- Per Corner
		corners = {},
		version = 2
	}

	-- Cells
	for cellY = yMin, yMax do
		g_cellData.uid[cellY] = {}
		g_cellData.xOffset[cellY] = {}
		g_cellData.yOffset[cellY] = {}
		g_cellData.rotation[cellY] = {}

		for cellX = xMin, xMax do
			g_cellData.uid[cellY][cellX] = sm.uuid.getNil()
			g_cellData.xOffset[cellY][cellX] = 0
			g_cellData.yOffset[cellY][cellX] = 0
			g_cellData.rotation[cellY][cellX] = 0
		end
	end

	for cornerY = yMin, yMax+1 do
		g_cellData.corners[cornerY] = {}
		for cornerX = xMin, xMax+1 do
			g_cellData.corners[cornerY][cornerX] = 0
		end
	end
end


function Create( xMin, xMax, yMin, yMax, seed, data ) -- New Create func
	
	print( "Create custom terrain",data )
	local temp = { pathToUid = {}, nextLegacyId = 1 }

	-- if data worldfile we are in game
	if data.worldFile then
		g_isEditor = false
		print( "Creating custom terrain: " .. data.worldFile )
		jWorld = sm.json.open( data.worldFile )
		
		print( "Bounds X: ["..xMin..", "..xMax.."], Y: ["..yMin..", "..yMax.."]" )
		print( "Seed: "..seed )

		-- v0.5.0: graphicsCellPadding is no longer included in min/max
		xMin =  xMin - GRAPHICS_CELL_PADDING
		xMax =  xMax + GRAPHICS_CELL_PADDING
		yMin =  yMin - GRAPHICS_CELL_PADDING
		yMax =  yMax + GRAPHICS_CELL_PADDING
		
		initializeCellData( xMin, xMax, yMin, yMax, seed )
		LoadTerrain( jWorld )
		updateDesertFade( 
			g_cellData.bounds.xMin + (GRAPHICS_CELL_PADDING-1), 
			g_cellData.bounds.xMax - (GRAPHICS_CELL_PADDING-1) )
		-- Sets up fence (probably will have errors wince fence bigger than world)
		for i = FENCE_MIN_CELL + 1, FENCE_MAX_CELL - 1 do
			setFence( i, FENCE_MIN_CELL, "S", seed, temp )
			setFence( i, FENCE_MAX_CELL, "N", seed, temp )
			setFence( FENCE_MIN_CELL, i, "W", seed, temp )
			setFence( FENCE_MAX_CELL, i, "E", seed, temp )	
		end
		setFence( FENCE_MIN_CELL, FENCE_MIN_CELL, "SW", seed, temp )
		setFence( FENCE_MAX_CELL, FENCE_MIN_CELL, "SE", seed, temp )
		setFence( FENCE_MIN_CELL, FENCE_MAX_CELL, "NW", seed, temp )
		setFence( FENCE_MAX_CELL, FENCE_MAX_CELL, "NE", seed, temp )

		for path, uid in pairs( temp.pathToUid ) do
			f_uidToPath[tostring(uid)] = path
		end
		
		sm.terrainData.save( { f_uidToPath, g_cellData } )
	else -- we are coming from the editor and data will be loaded later
		g_isEditor = true
		print("Create custom terrain for Editor")
		xMin =  xMin - GRAPHICS_CELL_PADDING
		xMax =  xMax + GRAPHICS_CELL_PADDING
		yMin =  yMin - GRAPHICS_CELL_PADDING
		yMax =  yMax + GRAPHICS_CELL_PADDING
		initializeCellData( xMin, xMax, yMin, yMax, seed )
		updateDesertFade( g_cellData.bounds.xMin +5 , g_cellData.bounds.xMax - 5  )
	end
end

function Old_Create( xMin, xMax, yMin, yMax, seed, data ) -- old create file (remove old)
	print("Teerrraiiin custom create world")
	g_uuidToPath = {}
	g_cellData = {
		bounds = { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax },
		seed = seed,
		-- Per Cell
		uid = {},
		xOffset = {},
		yOffset = {},
		rotation = {}
	}

	for cellY = yMin, yMax do
		g_cellData.uid[cellY] = {}
		g_cellData.xOffset[cellY] = {}
		g_cellData.yOffset[cellY] = {}
		g_cellData.rotation[cellY] = {}

		for cellX = xMin, xMax do
			g_cellData.uid[cellY][cellX] = sm.uuid.getNil()
			g_cellData.xOffset[cellY][cellX] = 0
			g_cellData.yOffset[cellY][cellX] = 0
			g_cellData.rotation[cellY][cellX] = 0
		end
	end

	local jWorld = sm.json.open( "$CONTENT_DATA/Terrain/Worlds/example.world") -- now stored in data.worldFile?
	--print("Loading jworld")
	for _, cell in pairs( jWorld.cellData ) do
		if cell.path ~= "" then
			print("Inserting",cell)
			local uid = sm.terrainTile.getTileUuid( cell.path )
			g_cellData.uid[cell.y][cell.x] = uid
			g_cellData.xOffset[cell.y][cell.x] = cell.offsetX
			g_cellData.yOffset[cell.y][cell.x] = cell.offsetY
			g_cellData.rotation[cell.y][cell.x] = cell.rotation

			g_uuidToPath[tostring(uid)] = cell.path
		end
	end

	sm.terrainData.save( { g_uuidToPath, g_cellData } )
	--print("saved terraindata")
end


-------------------------------
function TryUpgradeLegacyData() -- REturns error, ma
	legacy_idToPath = sm.terrainData.legacy_loadTerrainData( 1 )
	legacy_cellData = sm.terrainData.legacy_loadTerrainData( 2 )
	
	if legacy_idToPath ~= nil and legacy_cellData ~= nil then
		print( "Found Legacy Custom Terrain data, attempting upgrade" )
		local temp = { pathToUid = {}, nextLegacyId = 1 }

		for id, path in pairs( legacy_idToPath ) do
			path = UpgradeCreativeTilePath( path )
			AddTile( id, path  ) -- For UpgradeCellData
			getOrCreateTileId( path, temp ) -- For f_uidToPath
		end
		
		if( UpgradeCellData( legacy_cellData ) ) then
			for path, uid in pairs( temp.pathToUid ) do
				f_uidToPath[tostring(uid)] = path
			end

			-- Store legacy data as version 0.6.0 format
			sm.terrainData.save( { f_uidToPath, legacy_cellData } )
			return true
		end
	end
	return false
end



function Load() --- New load
	print( "Loading custom terrain",sm.terrainData.exists())

	if sm.terrainData.exists() or TryUpgradeLegacyData() then -- remove legacyTry if not needed
		local terrainData = sm.terrainData.load()

		f_uidToPath = terrainData[1]
		g_cellData = terrainData[2]
		
		updateDesertFade(
			g_cellData.bounds.xMin + (GRAPHICS_CELL_PADDING-1) , 
			g_cellData.bounds.xMax - (GRAPHICS_CELL_PADDING-1) )
		return true
	end

	print( "No terrain data found" )
	return false
end

function Old_Load() -- Old load
	print("load terrain",sm.terrainData.exists())
	if sm.terrainData.exists() then
		local data = sm.terrainData.load()
		g_uuidToPath = data[1]
		g_cellData = data[2]
		return true
	end
	return false
end


-------------------------
local groundTypeGeneration = {}
groundTypeGeneration[TYPE_MEADOW] = getMeadowTileIdAndRotation
groundTypeGeneration[TYPE_FOREST] = getForestTileIdAndRotation
groundTypeGeneration[TYPE_DESERT] = getDesertTileIdAndRotation
groundTypeGeneration[TYPE_FIELD] = getFieldTileIdAndRotation
groundTypeGeneration[TYPE_BURNTFOREST] = getBurntForestTileIdAndRotation
groundTypeGeneration[TYPE_AUTUMNFOREST] = getAutumnForestTileIdAndRotation
groundTypeGeneration[TYPE_LAKE] = getLakeTileIdAndRotation

local function evaluateTileType( x, y, corners, type, fn )
	local typeSE = bit.tobit( corners[y  ][x+1] == type and 8 or 0 )
	local typeSW = bit.tobit( corners[y  ][x  ] == type and 4 or 0 )
	local typeNW = bit.tobit( corners[y+1][x  ] == type and 2 or 0 )
	local typeNE = bit.tobit( corners[y+1][x+1] == type and 1 or 0 )
	local typeBits = bit.bor( typeSE, typeSW, typeNW, typeNE )

	local tileId, rotation = fn( typeBits, sm.noise.intNoise2d( x, y, g_cellData.seed + 2854 ), sm.noise.intNoise2d( x, y, g_cellData.seed + 9439 ) )
	return tileId, rotation
end


function LoadTerrain( terrainData )
	if terrainData.cellData == nil then
		return
	end
	local terrainTileList = { pathToUid = {}, nextLegacyId = 1 }

	if terrainData.cornerData then
		terrainData.corners = {}

		for i = 1, #terrainData.cornerData do
			local cd = terrainData.cornerData[i]
			local x = cd["x"]
			local y = cd["y"]
			g_cellData.corners[y][x] = cd["type"]
		end
	end

	for _, cell in pairs( terrainData.cellData ) do
		setCell( cell, sm.uuid.getNil() )

		if cell.path ~= "" then
			setCell( cell,  getOrCreateTileId( cell.path, terrainTileList ) )
		else
			-- if ground is painted, set to correct type
			for biome, func in pairs( groundTypeGeneration ) do
				local uid, rotation = evaluateTileType( cell.x, cell.y, g_cellData.corners, biome, func )
				if not uid:isNil() then
					cell.rotation = rotation
					setCell( cell, uid )
				end
			end
		end
	end


	for path, uid in pairs( terrainTileList.pathToUid ) do
		f_uidToPath[tostring(uid)] = path
	end
end
------------------------------------------------



function GetTilePath( uid )
	if not uid:isNil() then
		return g_uuidToPath[tostring(uid)]
	end
	return ""
end

function GetCellTileUidAndOffset( cellX, cellY )
	if InsideCellBounds( cellX, cellY ) then
		return	g_cellData.uid[cellY][cellX],
				g_cellData.xOffset[cellY][cellX],
				g_cellData.yOffset[cellY][cellX]
	end
	return sm.uuid.getNil(), 0, 0
end

function GetTileLoadParamsFromWorldPos( x, y, lod )
	local cellX, cellY = GetCell( x, y )
	local uid, tileCellOffsetX, tileCellOffsetY = GetCellTileUidAndOffset( cellX, cellY )
	local rx, ry = InverseRotateLocal( cellX, cellY, x - cellX * CELL_SIZE, y - cellY * CELL_SIZE )
	if lod then
		return  uid, tileCellOffsetX, tileCellOffsetY, lod, rx, ry
	else
		return  uid, tileCellOffsetX, tileCellOffsetY, rx, ry
	end
end

function GetTileLoadParamsFromCellPos( cellX, cellY, lod )
	local uid, tileCellOffsetX, tileCellOffsetY = GetCellTileUidAndOffset( cellX, cellY )
	if lod then
		return  uid, tileCellOffsetX, tileCellOffsetY, lod
	else
		return  uid, tileCellOffsetX, tileCellOffsetY
	end
end

function GetHeightAt( x, y, lod )
	return sm.terrainTile.getHeightAt( GetTileLoadParamsFromWorldPos( x, y, lod ) )
end

function GetColorAt( x, y, lod )
	return sm.terrainTile.getColorAt( GetTileLoadParamsFromWorldPos( x, y, lod ) )
end

function GetMaterialAt( x, y, lod )
	return sm.terrainTile.getMaterialAt( GetTileLoadParamsFromWorldPos( x, y, lod ) )
end

function GetClutterIdxAt( x, y )
	return sm.terrainTile.getClutterIdxAt( GetTileLoadParamsFromWorldPos( x, y ) )
end

function GetAssetsForCell( cellX, cellY, lod ) -- loading is weird, swqitch to alternate version?
	local assets = sm.terrainTile.getAssetsForCell( GetTileLoadParamsFromCellPos( cellX, cellY, lod ) )
	for _, asset in ipairs( assets ) do
		local rx, ry = RotateLocal( cellX, cellY, asset.pos.x, asset.pos.y )
		asset.pos = sm.vec3.new( rx, ry, asset.pos.z )
		asset.rot = GetRotationQuat( cellX, cellY ) * asset.rot
	end
	return assets
end

function GetNodesForCell( cellX, cellY )
	local nodes = sm.terrainTile.getNodesForCell( GetTileLoadParamsFromCellPos( cellX, cellY ) )
	for _, node in ipairs( nodes ) do
		local rx, ry = RotateLocal( cellX, cellY, node.pos.x, node.pos.y )
		node.pos = sm.vec3.new( rx, ry, node.pos.z )
		node.rot = GetRotationQuat( cellX, cellY ) * node.rot
	end
	return nodes
end

function GetCreationsForCell( cellX, cellY )
	local uid, tileCellOffsetX, tileCellOffsetY = GetCellTileUidAndOffset( cellX, cellY )
	if not uid:isNil() then
		local cellCreations = sm.terrainTile.getCreationsForCell( uid, tileCellOffsetX, tileCellOffsetY )
		for i,creation in ipairs( cellCreations ) do
			local rx, ry = RotateLocal( cellX, cellY, creation.pos.x, creation.pos.y )

			creation.pos = sm.vec3.new( rx, ry, creation.pos.z )
			creation.rot = GetRotationQuat( cellX, cellY ) * creation.rot
		end

		return cellCreations
	end

	return {}
end

function GetHarvestablesForCell( cellX, cellY, lod )
	local harvestables = sm.terrainTile.getHarvestablesForCell( GetTileLoadParamsFromCellPos( cellX, cellY, lod ) )
	for _, harvestable in ipairs( harvestables ) do
		local rx, ry = RotateLocal( cellX, cellY, harvestable.pos.x, harvestable.pos.y )
		harvestable.pos = sm.vec3.new( rx, ry, harvestable.pos.z )
		harvestable.rot = GetRotationQuat( cellX, cellY ) * harvestable.rot
	end
	return harvestables
end

function GetKinematicsForCell( cellX, cellY, lod )
	local kinematics = sm.terrainTile.getKinematicsForCell( GetTileLoadParamsFromCellPos( cellX, cellY, lod ) )
	for _, kinematic in ipairs( kinematics ) do
		local rx, ry = RotateLocal( cellX, cellY, kinematic.pos.x, kinematic.pos.y )
		kinematic.pos = sm.vec3.new( rx, ry, kinematic.pos.z )
		kinematic.rot = GetRotationQuat( cellX, cellY ) * kinematic.rot
	end
	return kinematics
end

function GetDecalsForCell( cellX, cellY, lod )
	local decals = sm.terrainTile.getDecalsForCell( GetTileLoadParamsFromCellPos( cellX, cellY, lod ) )
	for _, decal in ipairs( decals ) do
		local rx, ry = RotateLocal( cellX, cellY, decal.pos.x, decal.pos.y )
		decal.pos = sm.vec3.new( rx, ry, decal.pos.z )
		decal.rot = GetRotationQuat( cellX, cellY ) * decal.rot
	end
	return decals
end


----------------------------------------------------------------------------------------------------
-- Tile Reader Path Getter
----------------------------------------------------------------------------------------------------

function UpgradeCreativeTilePath( path )
	if string.find( path, "$GAME_DATA/Terrain/Tiles/ClassicCreativeTiles/", 1, false ) == nil
			and string.find( path, "$GAME_DATA/Terrain/Tiles/CreativeTiles/", 1, false ) == nil then
				return string.gsub( path, "$GAME_DATA/Terrain/Tiles/", "$GAME_DATA/Terrain/Tiles/ClassicCreativeTiles/", 1 )
		end
	return path
end

function GetTilePath( uid )
	if not uid:isNil() then
		if f_uidToPath[tostring(uid)] then
			return UpgradeCreativeTilePath( f_uidToPath[tostring(uid)] )
		else
			return GetPath( uid )
		end
	end
	return ""
end
