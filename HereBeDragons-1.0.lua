-- HereBeDragons is a data API for the World of Warcraft mapping system

local MAJOR, MINOR = "HereBeDragons-1.0", 1
assert(LibStub, MAJOR .. " requires LibStub")

local HereBeDragons = LibStub:NewLibrary(MAJOR, MINOR)
if not HereBeDragons then return end

HereBeDragons.eventFrame = HereBeDragons.eventFrame or CreateFrame("Frame")

HereBeDragons.mapData       = HereBeDragons.mapData or {}
HereBeDragons.mapToID       = HereBeDragons.mapToID or {}
HereBeDragons.idToMap       = HereBeDragons.idToMap or {}
HereBeDragons.mapLocalized  = HereBeDragons.mapLocalized or {}
HereBeDragons.microDungeons = HereBeDragons.microDungeons or {}
HereBeDragons.transforms    = HereBeDragons.transforms or {}

local PI2 = math.pi * 2

-- Override instance ids for phased content
local instanceIDOverrides = {
    -- Draenor
    [1152] = 1116, -- Horde Garrison 1
    [1153] = 1116, -- Horde Garrison 2
    [1154] = 1116, -- Horde Garrison 3
    [1158] = 1116, -- Alliance Garrison 1
    [1159] = 1116, -- Alliance Garrison 2
    [1160] = 1116, -- Alliance Garrison 3
    [1464] = 1116, -- Tanaan
    [1465] = 1116, -- Tanaan
}

-- gather map info
local mapData = HereBeDragons.mapData -- table { width, height, left, top }
local mapToID, idToMap = HereBeDragons.mapToID, HereBeDragons.idToMap
local mapLocalized = HereBeDragons.mapLocalized
local microDungeons = HereBeDragons.microDungeons
local transforms = HereBeDragons.transforms
do
    local function processTransforms()
        for _, tID in ipairs(GetWorldMapTransforms()) do
            local terrainMapID, newTerrainMapID, _, _, transformMinY, transformMaxY, transformMinX, transformMaxX, offsetY, offsetX = GetWorldMapTransformInfo(tID)
            if offsetY ~= 0 or offsetX ~= 0 then
                local transform = {
                    instanceID = terrainMapID,
                    newInstanceID = newTerrainMapID,
                    minY = transformMinY,
                    maxY = transformMaxY,
                    minX = transformMinX,
                    maxX = transformMaxX,
                    offsetY = offsetY,
                    offsetX = offsetX
                }
                table.insert(transforms, transform)
            end
        end
    end

    local function applyMapTransforms(instanceID, left, right, top, bottom)
        for _, transformData in ipairs(transforms) do
            if transformData.instanceID == instanceID then
                if transformData.minX <= left and transformData.maxX >= right and transformData.minY <= top and transformData.maxY >= bottom then
                    instanceID = transformData.newInstanceID
                    left   = left   + transformData.offsetX
                    right  = right  + transformData.offsetX
                    top    = top    + transformData.offsetY
                    bottom = bottom + transformData.offsetY
                    break
                end
            end
        end
        return instanceID, left, right, top, bottom
    end

    -- gather the data of one zone (by mapID)
    local function processZone(id)
        if not id or mapData[id] then return end

        SetMapByID(id)
        local mapFile = GetMapInfo()
        local numFloors = GetNumDungeonMapLevels()
        idToMap[id] = mapFile

        if not mapToID[mapFile] then mapToID[mapFile] = id end
        mapLocalized[id] = GetMapNameByID(id)

        local instanceID = GetAreaMapInfo(id)
        local C = GetCurrentMapContinent()
        local Z, left, top, right, bottom = GetCurrentMapZone()
        if (left and top and right and bottom and (left ~= 0 or top ~= 0 or right ~= 0 or bottom ~= 0)) then
            instanceID, left, right, top, bottom = applyMapTransforms(instanceID, left, right, top, bottom)
            mapData[id] = { left - right, top - bottom, left, top }
        else
            mapData[id] = { 0, 0, 0, 0 }
        end

        mapData[id].instance = instanceID
        mapData[id].C = C or -100
        mapData[id].Z = Z or -100

        if mapData[id].C > 0 and mapData[id].Z > 0 and not microDungeons[instanceID] then
            microDungeons[instanceID] = {}
        end

        if numFloors == 0 and GetCurrentMapDungeonLevel() == 1 then
            numFloors = 1
            mapData[id].fakefloor = true
        end

        if DungeonUsesTerrainMap() then
            numFloors = numFloors - 1
        end

        mapData[id].floors = {}
        if numFloors > 0 then
            for f = 1, numFloors do
                SetDungeonMapLevel(f)
                local _, right, bottom, left, top = GetCurrentMapDungeonLevel()
                if left and top and right and bottom then
                    mapData[id].floors[f] = { left - right, top - bottom, left, top }
                    mapData[id].floors[f].instance = mapData[id].instance
                end
            end
        end
    end

    local function processMicroDungeons()
        for _, dID in ipairs(GetDungeonMaps()) do
            local floorIndex, minX, maxX, minY, maxY, terrainMapID, parentWorldMapID, flags = GetDungeonMapInfo(dID)

            -- apply transform
            terrainMapID, maxX, minX, maxY, minY = applyMapTransforms(terrainMapID, maxX, minX, maxY, minY)

            -- check if this zone can have microdungeons
            if microDungeons[terrainMapID] then
                microDungeons[terrainMapID][floorIndex] = { maxX - minX, maxY - minY, maxX, maxY }
                microDungeons[terrainMapID][floorIndex].instance = terrainMapID
            end
        end
    end

    local function gatherMapData()
        -- load transforms
        processTransforms()

        -- load the main zones
        -- these should be processed first so they take precedence in the mapFile lookup table
        local continents = {GetMapContinents()}
        for i = 1, #continents, 2 do
            processZone(continents[i])
            local zones = {GetMapZones((i + 1) / 2)}
            for z = 1, #zones, 2 do
                processZone(zones[z])
            end
        end

        -- process all other zones, this includes dungeons and more
        local areas = GetAreaMaps()
        for idx, zoneID in pairs(areas) do
            processZone(zoneID)
        end

        -- and finally, the microdungeons
        processMicroDungeons()
    end

    gatherMapData()
end

-- Transform a set of coordinates based on the defined map transformations
local function applyCoordinateTransforms(x, y, instanceID)
    for _, transformData in ipairs(transforms) do
        if transformData.instanceID == instanceID then
            if transformData.minX <= x and transformData.maxX >= x and transformData.minY <= y and transformData.maxY >= y then
                instanceID = transformData.newInstanceID
                x = x + transformData.offsetX
                y = y + transformData.offsetY
                break
            end
        end
    end
    if instanceIDOverrides[instanceID] then
        instanceID = instanceIDOverrides[instanceID]
    end
    return x, y, instanceID
end

-- get the data table for a map and its level (floor)
local function getMapDataTable(mapID, level)
    if not mapID or mapID == WORLDMAP_COSMIC_ID then return nil end
    if type(mapID) == "string" then
        mapID = mapToID[mapID]
    end
    local data = mapData[mapID]
    if not data then return nil end

    if (level == nil or level == 0) and data.fakefloor then
        level = 1
    end

    if level and level > 0 then
        if data.floors[level] then
            return data.floors[level]
        elseif microDungeons[data.instance] and microDungeons[data.instance][level] then
            return microDungeons[data.instance][level]
        end
    else
        return data
    end
end
HereBeDragons.getMapDataTable = getMapDataTable

--- Return the localized zone name for a given mapID or mapFile
-- @param mapID numeric mapID or mapFile
function HereBeDragons:GetLocalizedMap(mapID)
    if mapID == WORLDMAP_COSMIC_ID then return WORLD_MAP end
    if type(mapID) == "string" then
        mapID = mapToID[mapID]
    end
    return mapLocalized[mapID]
end

--- Return the map id to a mapFile
-- @param mapFile Map File
function HereBeDragons:GetMapIDFromFile(mapFile)
    return mapToID[mapFile]
end

--- Return the mapFile to a map ID
-- @param mapID Map ID
function HereBeDragons:GetMapFileFromID(mapID)
    return idToMap[mapID]
end

--- Get the size of the zone
-- @param mapID Map ID or MapFile of the zone
-- @param level Optional map level
-- @return width, height of the zone, in yards
function HereBeDragons:GetZoneSize(mapID, level)
    local data = getMapDataTable(mapID, level)
    if not data then return 0, 0 end

    return data[1], data[2]
end

function HereBeDragons:GetAllMapIDs()
    local t = {}
    for id in pairs(mapData) do
        table.insert(t, id)
    end
    return t
end

--- Convert local/point coordinates to world coordinates in yards
-- @param x X position on 0-1 point coordinates
-- @param y Y position in 0-1 point coordinates
-- @param zone MapID or MapFile of the zone
-- @param level Optional level of the zone
-- @param transform Apply map transforms
function HereBeDragons:GetWorldCoordinatesFromZone(x, y, zone, level, transform)
    local data = getMapDataTable(zone, level)
    if not data then return nil, nil, nil end

    local width, height, left, top = data[1], data[2], data[3], data[4]
    x, y = left - width * x, top - height * y

    return x, y, data.instance
end

--- Convert world coordinates to local/point zone coordinates
-- @param x Global X position
-- @param y Global Y position
-- @param zone MapID or MapFile of the zone
-- @param level Optional level of the zone
function HereBeDragons:GetZoneCoordinatesFromWorld(x, y, zone, level)
    local data = getMapDataTable(zone, level)
    if not data then return nil, nil end

    local width, height, left, top = data[1], data[2], data[3], data[4]
    x, y = (left - x) / width, (top - y) / height

    -- verify the coordinates fall into the zone
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil, nil end

    return x, y
end

--- Return the distance from an origin position to a destination position in the same instance/continent.
-- @param instanceID instance ID
-- @param oX origin X
-- @param oY origin Y
-- @param dX destination X
-- @param dY destination Y
-- @return distance, deltaX, deltaY
function HereBeDragons:GetWorldDistance(instanceID, oX, oY, dX, dY)
    local deltaX, deltaY = dX - oX, dY - oY
    return (deltaX * deltaX + deltaY * deltaY)^0.5, deltaX, deltaY
end
--- Return the distance between two points in the same zone
-- @param zone zone map id or mapfile
-- @param level optional zone level (floor)
-- @param oX origin X, in local zone/point coordinates
-- @param oY origin Y, in local zone/point coordinates
-- @param dX destination X, in local zone/point coordinates
-- @param dY destination Y, in local zone/point coordinates
-- @return distance, deltaX, deltaY in yards
function HereBeDragons:GetZoneDistance(zone, level, oX, oY, dX, dY)
    local data = getMapDataTable(zone, level)
    if not data then return nil, nil, nil end

    local x = (dX - oX) * data[1]
    local y = (dY - oY) * data[2]
    return (x*x + y*y)^0.5, x, y
end

--- Return the angle and distance from an origin position to a destination position in the same instance/continent.
-- @param instanceID instance ID
-- @param oX origin X
-- @param oY origin Y
-- @param dX destination X
-- @param dY destination Y
-- @return angle, distance where angle is in radians and distance in yards
function HereBeDragons:GetWorldVector(instanceID, oX, oY, dX, dY)
    local distance, deltaX, deltaY = self:GetWorldDistance(instanceID, oX, oY, dX, dY)
    if not distance then return nil, nil end

    -- calculate the angle from deltaY and deltaX
    local angle = math.atan2(deltaX, -deltaY)

    -- normalize the angle
    if angle > 0 then
        angle = PI2 - angle
    else
        angle = -angle
    end

    return angle, distance
end

--- Get the current world position of the player
-- The position is transformed to the current continent, if applicable
-- @return x, y, instanceID
function HereBeDragons:GetPlayerWorldPosition()
    -- get the current position
    local y, x, z, instanceID = UnitPosition("player")

    -- return transformed coordinates
    return applyCoordinateTransforms(x, y, instanceID)
end
