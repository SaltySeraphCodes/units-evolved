-- List of globals to be listed and changed here, along with helper functions
CLOCK = os.clock
MOD_FOLDER = "$CONTENT_DATA/" -- ID to open files in content
SREADER_FOLDER = "$CONTENT_DATA/Scripts/StreamReaderData"
chatterDataPath = SREADER_FOLDER.."/chatterData.json" -- unecessary I think
streamChatPath = SREADER_FOLDER.."/streamchat.json"
SIMULATION_DATA_FILE = MOD_FOLDER .. "/jsonData/SimOutput/simulationOutput.json"
SIMULATION_SETTINGS_FILE = SREADER_FOLDER .. "/simulationSettings.json"
--CAMERA_FOLDER = "$CONTENT_d42a91c3-2f86-4923-add5-93d8258b2c08/"
-- SELF FOLDER =- "$CONTENT_5411dc77-fa28-4c61-af84-bcb1415e3476/"
sm.SMARGlobals = {
    LOAD_CAMERA = true, -- REMEMBER TO SET THIS TO FALSE
    SMAR_CAM = -1 -- Smar camera loaded from cinecam mod
}

SIMULATION_SETTINGS ={
    allow_spawn = true,
    peaceful_mode = false,
    allow_explode = false,
    enable_food = false,
    allow_move = true,
    enable_ap = false,
    enable_logout = true,
    show_seraph = false,
    default_spawn = false,
}

AP_USAGE ={ -- ratio of Action point usage
    move = 1,
    attack = 2,
    explode = 5,
    build = 2,
    collect = 2 -- REsource rareness table
}

FOOD_TYPES = {
    corn = {
        uuid = "3232423423",
        hp = 15,
        xp = 5

    }
}


GAME_CONTROL = nil -- Contains race control Object


function getGameControl()
    --if GAME_CONTROL == nil then
    return GAME_CONTROL
end




function mathClamp(min,max,value) -- caps value based off of max and min
    if value > max then
        return max
    elseif value < min then
        return min
    end
    return value
end

function withinBound(location,bound) -- determines if location is within boundaries of bound
	local box1 = {bound.left, bound.left + bound.buffer}
    local box2 = {bound.right, bound.right + bound.buffer}
    local minX = math.min(box1[1].x,box1[2].x,box2[1].x,box2[2].x) -- todo: also store this instead of calculating every time too
	local minY = math.min(box1[1].y,box1[2].y,box2[1].y,box2[2].y)
	local maxX = math.max(box1[1].x,box1[2].x,box2[1].x,box2[2].x) 
	local maxY = math.max(box1[1].y,box1[2].y,box2[1].y,box2[2].y)
	if location.x > minX and location.x < maxX then
		if location.y > minY and location.y < maxY then
			return true
		end
	end
	return false
end

function squareIntersect(location,square) -- determines if location is within boundaries of carBound square
    local minX = math.min(square[1].position.x,square[2].position.x,square[3].position.x,square[4].position.x) -- todo: also store this instead of calculating every time too
	local minY = math.min(square[1].position.y,square[2].position.y,square[3].position.y,square[4].position.y)
	local maxX = math.max(square[1].position.x,square[2].position.x,square[3].position.x,square[4].position.x) 
	local maxY = math.max(square[1].position.y,square[2].position.y,square[3].position.y,square[4].position.y)
	if location.x > minX and location.x < maxX then
		if location.y > minY and location.y < maxY then
			return true
		end
	end
	return false
end



-- format{ front, left, right, back,location,directionF,direction}
function generateBounds(location,dimensions,frontDir,rightDir,padding) -- Generates a 4 node box for front left right and back corners of position
    --print("gen bounds",location,dimensions,frontDir,rightDir,padding,dimensions['front']:length(),dimensions['left']:length())
    local bounds = {
    {['name'] = 'fl', ['position'] = location + (frontDir *  (dimensions['front']:length()*padding) ) + (-rightDir *  dimensions['left']:length()*padding)},
    {['name'] = 'fr', ['position'] = location + (frontDir *  (dimensions['front']:length()*padding) ) + (rightDir *  dimensions['left']:length()*padding)},
    {['name'] = 'bl', ['position'] = location + (-frontDir *  (dimensions['front']:length()*padding) ) + (-rightDir *  dimensions['left']:length()*padding)},
    {['name'] = 'br', ['position'] = location + (-frontDir *  (dimensions['front']:length()*padding) ) + (rightDir *  dimensions['left']:length()*padding)}
    }
    return bounds
end

function getCollisionPotential(selfBox,opBox) -- Determines if bounding box1 colides with box 2
    --print("gettinc colPot",selfBox)
    for k=1, #selfBox do local corner=selfBox[k]
        --print(corner['name'])
        local pos = corner['position']
        if squareIntersect(pos,opBox) then
            return k -- index in selfBox (corner)
        end
    end
    return false
end

-- split("a,b,c", ",") => {"a", "b", "c"}
function split(s, sep)
    local fields = {}
    local sep = sep or " "
    local pattern = string.format("([^%s]+)", sep)
    string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
    return fields
end

function getDistance(vector1,vector2) -- GEts the distance of vector by power
    local diff = vector2 - vector1
    local dist = sm.vec3.length(diff)
    return dist
end

function getMidpoint(locA,locB) -- Returns vec3 contianing the midpoint of two vectors
	local midpoint = sm.vec3.new((locA.x +locB.x)/2 ,(locA.y+locB.y)/2,locA.z)
	return midpoint
end

function checkMin(previous,current)
    if previous == nil and current == nil then
        print("CheckMin of two nils error")
        return 0
    end

    if previous == nil or current == nil then
        return (current or previous)
    end

    if current < previous then
        return current
    else
        return previous
    end
end

function getNextItem(linkedList,itemIndex,direction) -- Gets {direction} items ahead/behind in a linked list (handles wrapping)
    local nextIndex = 1
    if direction >= 0 then
        nextIndex = (itemIndex + direction -1 ) % #linkedList +1 -- because lua rrays -_-
    else
        nextIndex = (itemIndex + direction + #linkedList -1) %#linkedList + 1
    end
    return linkedList[nextIndex]
end

function getNextIndex(totalIndexes,currentIndex,direction) -- Gets {direction} items ahead/behind in a linked list (handles wrapping)
    local nextIndex = 1
    if direction >= 0 then
        nextIndex = (currentIndex + direction -1 ) % totalIndexes +1 -- because lua rrays -_-
    else
        nextIndex = (currentIndex + direction + totalIndexes -1) %totalIndexes + 1
    end
    return nextIndex    
end

-- camera (probably same cam)

function setSmarCam(cam)
    sm.SMARGlobals.SMAR_CAM = cam
    --print("set smar cam",SMAR_CAM)
end

function getSmarCam()
    return  sm.SMARGlobals.SMAR_CAM
end

-- Unit helpers



-- Simulation settings
function getSimulationSettings()
    local settings = SIMULATION_SETTINGS
    return settings
end

function setSimulationSetting(setting,value) -- sets individual settings
    SIMULATION_SETTINGS[setting] = value
    --print("Set SIM SETTING: ",setting,value)
    return value
end


function setSimulationSettings(settings) -- sets full settings
    SIMULATION_SETTINGS = settings
    return SIMULATION_SETTINGS
end


-- coordinate parsing
function parseCoordinates(str,gameControl) -- Returns coord version, vec3{x,y,1} from n,n n-n
    local squareMatch = split(str,",")
    if squareMatch and #squareMatch == 2 then
        local numX = tonumber(squareMatch[1])
        local numY = tonumber(squareMatch[2])
        return 1, sm.vec3.new(numX,numY,1)
    end
    local posMatch = split(str,"-")
    if posMatch and #posMatch == 2 then
        local numX = tonumber(posMatch[1])
        local numY = tonumber(posMatch[2])
        return 2, sm.vec3.new(numX,numY,1)   
    end

    print("Improper coordinates",str)
    return nil 
end

-- Grid helpers

function getSquareCoords(pos,edgeMatrix,metaGrid)
    local square = getSquare({pos.x,pos.y},metaGrid)
    if square == nil then return nil end
    return square.center
end

function getExactCoords(pos,edgeMatrix)
    local pos2 = gridToWorldTranslate(edgeMatrix,pos)
    if pos2 == nil then return nil end
    return pos2
end

function getSquare(location,metaGrid) -- location is {row,col}
    if metaGrid == nil then print("metagrid nil") return end
    if #metaGrid <=1 then print("small metagrid") return end
    -- validate and get row
    if location[1] <=0 or location[1] >#metaGrid[1] then
        print(location[1],"not in metaGrid",#metaGrid[1])
        return
    end
    local row = metaGrid[location[1]]
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


-- convert 1-100 grid to world posiion
function gridToWorldTranslate(edgeMatrix,location) -- Translates grid locations (0-100) input is vector, returns vector
    if edgeMatrix == nil then return end
    if location == nil then return end
    local xTranslate = edgeMatrix.X1
    local yTranslate = edgeMatrix.Y1
    local worldLocX = xTranslate - location.x
    local worldLocY = yTranslate + location.y
    local newLocation = sm.vec3.new(worldLocX,worldLocY,location.z) -- same z
    return newLocation
end

-- convert world position to 1-100 grid
function worldToGridTranslate(edgeMatrix,location) -- Translates world locations  to (0-100) input vec3, returns vvec3
    local xTranslate = edgeMatrix.X1
    local yTranslate = edgeMatrix.Y1
    local worldLocX = xTranslate - location.x
    local worldLocY = location.y - yTranslate
    local newLocation = sm.vec3.new(worldLocX,worldLocY,location.z) -- same z
    return newLocation
end
---- Racer meta data helps
function sortRacersByRacePos(inTable)
    table.sort(inTable, racePosCompare)
	return inTable
end

function sortRacersByCameraPoints(inTable)
    table.sort(inTable,cameraPointCompare)
    return inTable
end

function sortCamerasByDistance(inTable)
    table.sort(inTable,camerasDistanceCompare)
    return inTable
end

function racerIDCompare(a,b)
	return a['id'] < b['id']
end 

function racePosCompare(a,b)
	return a['racePosition'] < b['racePosition']
end 

function cameraPointCompare(a,b) -- sort so biggest is first
    return a['points'] > b['points']
end

function camerasDistanceCompare(a,b)
    return a['distance'] < b['distance']
end
-- Need a check min or some way to figure out which is which
-- *See SMARL FRICTION RESEARCH for data chart
print("loaded globals and helpers")