AA = LibStub("AceAddon-3.0"):NewAddon("AucAvg", "AceConsole-3.0", "AceSerializer-3.0")
AA_GUI = {}

local defaults = {
  realm = {
    parsedData = {}
  }
}

function AA:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("AucAvgDB", defaults, true)
  AA:RegisterChatCommand("aa", "CalculateAverage")
end

local function parseData(dataString)
  local results = {}
  for itemID, restOfData in dataString:gmatch("i(%d+)[^/]*%/([^%s]+)") do
    local lowestFourthValue = math.huge 

    for entry in restOfData:gmatch("([^&]+)") do
      local fourthValue = select(4, entry:match("([^,]+),([^,]+),([^,]+),([^,]+)"))
      
      if fourthValue then
        fourthValue = tonumber(fourthValue)
        if fourthValue and fourthValue < lowestFourthValue then
          lowestFourthValue = fourthValue
        end
      end
    end

    if results[itemID] == nil then
      results[itemID] = {lowestFourthValue}
    else 
      table.insert(results[itemID], lowestFourthValue)
    end
  end

  for key, prices in pairs(results) do
    local priceHolder = math.huge
    for _, price in ipairs(prices) do
      if price < priceHolder then
        priceHolder = price
      end
    end
    results[key] = {priceHolder}
  end

  return results
end

function AA:CalculateAverage(input)
  print("Calculating Average...")
  local dataString = ""
  for _, newest in pairs(AuctionDBSaved.ah) do
    if newest.ts == 1731482284 then
      dataString = newest.data
      break
    end
  end
  -- get all the recent auctionHouse scan data's
  -- run parseData func on all dataStrings
  -- merge results of parseData
  -- save it 

  if dataString then
    AA.db.realm.parsedData = parseData(dataString)
  end
  print("Finished Calculating Average!")
end
