local QBCore = exports['qbx-core']:GetCoreObject()

local Rental = {}
Rental.__index = Rental

function Rental:new(config)
    local self = setmetatable({}, Rental)
    self.config = config
    self.rentedVehicles = {}
    return self
end

function Rental:generatePlate()
    local plate
    repeat
        plate = string.format("RENT%03d", math.random(0, 9999))
    until not self.rentedVehicles[plate]
    return plate
end

function Rental:handleRentRequest(src, data)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false, "Player not found" end

    local location = self.config.RentalLocations[data.location]
    if not location then return false, "Invalid rental location" end

    local vehicle = data.vehicle
    if not vehicle then return false, "Invalid vehicle data" end

    local paymentMeth = data.paymentType or 'bank'
    if not Player.Functions.RemoveMoney(paymentMeth, vehicle.price) then
        return false, "Not enough money in " .. paymentMeth
    end
    
    local plate = self:generatePlate()

    self.rentedVehicles[plate] = {
        owner = src,
        vehicle = vehicle.model,
        price = vehicle.price,
        rentedAt = os.time() -- Use later?
    }

    return true, {
        model = vehicle.model,
        plate = plate,
        location = data.location
    }
end

function Rental:registerEvents()
    RegisterNetEvent('lx-rental:server:rentVehicle', function(data)
        local src = source
        local success, resp = self:handleRentRequest(src, data)
        if success then
            TriggerClientEvent('lx-rental:client:requestSpawnPoint', src, resp.model, resp.plate, resp.location)
        else
            TriggerClientEvent('QBCore:Notify', src, resp or 'Rental failed', 'error')
        end
    end)

    RegisterNetEvent('lx-rental:server:giveKeys', function(netId)
        local src = source
        local vehicle = NetworkGetEntityFromNetworkId(netId)
        if vehicle and DoesEntityExist(vehicle) then
            local success = exports.qbx_vehiclekeys:GiveKeys(src, vehicle)
            if success then
                print("Keys given to player " .. src)
            else
                print("Failed to give keys to player " .. src)
            end
        else
            print("Invalid vehicle entity for keys")
        end
    end)

    RegisterNetEvent('lx-rental:server:giveRentalPapers', function(plate)
        local src = source
        local metadata = {
            description = 'Rental Papers for: ' .. plate,
            plate = plate
        }
    
        exports.ox_inventory:AddItem(src, 'rentalpapers', 1, metadata)
    end)

    AddEventHandler('onResourceStart', function(resourceName)
        if resourceName == GetCurrentResourceName() then
            self:onResourceStart()
        end
    end)
end


function Rental:onResourceStart()
    --eh uhr
end


local rentalInstance = Rental:new(Config)
rentalInstance:registerEvents()
