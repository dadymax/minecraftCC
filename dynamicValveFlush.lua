local Settings = {
    mode = "server",
    -- mode = "switch",
    -- mode = "sensor",
    UID = "gasControl" .. math.random(100000, 999999),
    ListenChannels =  {
        server = 234,
        switch = 235,
        sensor = 236
    }
    
}

function Usage()
  print("some usage text")
end

function GetWirelessModem()
    local listOfSides = rs.getSides()
    for i = 1,6 do
        if peripheral.isPresent(listOfSides[i]) 
            and peripheral.getType(listOfSides[i]) == "modem" 
            and peripheral.call(listOfSides[i], "isWireless")
                then return peripheral.wrap(listOfSides[i])
        end
    end
end

function GetListenChannel()
    return Settings.ListenChannels[Settings.mode]
end

function GetServerChannel()
    return Settings.ListenChannels["server"]
end

function GetSwitchChannel()
    return Settings.ListenChannels["switch"]
end

function GetSwitchPeripheral()
    local listOfSides = rs.getSides()
    local pressurizedTube = "PressurizedTube"
    for i = 1,6 do
        if peripheral.isPresent(listOfSides[i]) 
            and peripheral.getType(listOfSides[i]):find(pressurizedTube)            
                then return peripheral.wrap(listOfSides[i])
        end
    end
end

function GetSensorPeripheral()
    local listOfSides = rs.getSides()
    local dynamicValve = "dynamicValve"
    for i = 1,6 do
        if peripheral.isPresent(listOfSides[i]) 
            and peripheral.getType(listOfSides[i]):find(dynamicValve)            
                then return peripheral.wrap(listOfSides[i])
        end
    end
end

function Server()
    local event, side, channel, replyChannel, message, distance, listenchannel, content
    listenchannel = GetListenChannel()
    content = {}
    
    print("Mode: " .. Settings.mode)    
    print("UID: " .. Settings.UID)

    while true do
        repeat
            event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        until channel == listenchannel
                
        print("Received message: " .. tostring(message["mType"]) .. " from " .. tostring(message["uid"]))
        
        --message may be:
        --	register new sensor/switch
        --	sensor change status
        --  
        -- format: message { type = register/data, uid = sender uid, ruid = receiveruid (may be nil), senderType, fluidtype: string (if register), status: true/false (full/notfull  if data)}

        if message["mType"] == "register" then
            content[message["uid"]] = { sType = senderType, fluidtype = message["fluidtype"], status = message["status"] }
        end
        
        if message["mType"] == "data" then
            content[message["uid"]] = { status = message["status"] }
        end
        
        for key, value in pairs(content) do
   			--print(key .. ": " .. value)
            if value["sType"] == "switch" then
                for key2, value2 in pairs(content) do
                    if value2["sType"] == "sensor" and value2["fluidtype"] == value["fluidtype"] then
                        SendMessage(GetSwitchChannel(), "data", key, value2["fluidtype"], value2["status"])
                        break
                    end
                end
            end
		end
        os.sleep(1)
    end
    
end

function Sensor()
    local event, side, channel, replyChannel, message, distance, listenchannel, content, per, capacity, status, fType
    listenchannel = GetListenChannel()    
    per = GetSensorPeripheral()
    content = per.getStored()
    capacity = per.getTankCapacity()
    threshold = capacity - (capacity / 10)
    fType = content["name"]
    status = false
    
    while not fType or fType == ""  do
        print("Try determine gas type")
        content = per.getBuffer()
        fType = content["name"]
    end

    SendMessage(GetSetverChannel(), "register", nil, fType, status)
    
    print("Mode: " .. Settings.mode)
    print("UID: " .. Settings.UID)
    print("gas type: " .. fType)

    while true do
        content = per.getStored().amount
        if content < threshold and status then
        	status = false
            SendMessage(GetSetverChannel(), "data", nil, fType, status)
        elseif content > (capacity - 10) and not status then
            status = true
            SendMessage(GetSetverChannel(), "data", nil, fType, status)
        end
        os.sleep(1)
    end
end

function Switch()
    local event, side, channel, replyChannel, message, distance, listenchannel, content, per, capacity, status, fType
    listenchannel = GetListenChannel()    
    per = GetSwitchPeripheral()
    status = false
    
    content = per.getBuffer()
    fType = content["name"]

    while not fType or fType == ""  do
        print("Try determine gas type")
        content = per.getBuffer()
        fType = content["name"]
    end
    
    rs.setOutput(peripheral.getName(per), true)
    SendMessage(GetSetverChannel(), "register", nil, fType, status)

    print("Mode: " .. Settings.mode)
    print("UID: " .. Settings.UID)
    print("gas type: " .. fType)
        
    while true do
        repeat
            event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        until channel == listenchannel
                
        print("Received message: " .. tostring(message))
        
        if message["ruid"] == Settings.UID then
            rs.setOutput(peripheral.getName(per), not message["status"])
            print("switched to: " .. tostring(not message["status"]))
        end
        os.sleep(1)
    end
end

function SendMessage(receiver, mType2, receiveruid, fluidtype2, status2)
    modem.transmit(receiver, GetListenChannel(), {mType = mType2, uid = Settings.UID, ruid = receiveruid, senderType = Settings.mode, fluidtype = fluidtype2, status = status2 } )
    print("Message sent: " .. tostring(mType2) .. ". Status: " .. tostring(status2))
end

modem = GetWirelessModem()

if not modem then 
    print("There's no wireless modem around! Connect one and restart.")
    return
    end

local modeswitch = {
    ["server"] = Server,
    ["sensor"] = Sensor,
    ["switch"] = Switch
}    

modem.closeAll()
modem.open(GetListenChannel())

local work = modeswitch[Settings.mode]
work()


