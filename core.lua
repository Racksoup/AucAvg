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
  local scanData = {}
  local ts = time() - (7 * 24 * 60 * 60)
  for _, data in pairs(AuctionDBSaved.ah) do
    if data.ts > ts then 
      table.insert(scanData, data)
    end
  end

  -- Organize scans by day
  local dailyResults = {}
  if #scanData >= 1 then
    for _, data in ipairs(scanData) do
      local day = date("%Y-%m-%d", data.ts) -- Group by day
      dailyResults[day] = dailyResults[day] or {}
      table.insert(dailyResults[day], parseData(data.data))
    end
  end

  -- Calculate daily averages
  local dailyAverages = {}
  for day, results in pairs(dailyResults) do
    dailyAverages[day] = AA:mergeAndAverageDailyTables(unpack(results))
  end

  -- print ****************************
  for day, data in pairs(dailyAverages) do
    print("Day:", day)
    
    local count = 0
    for itemID, prices in pairs(data) do
      print("  ItemID:", itemID, "Price:", prices) -- Adjust as needed if `prices` is a table
      count = count + 1
      if count >= 5 then  -- Limit to 5 items per day
        print("  ... and more")
        break
      end
    end
  end

  -- Merge daily averages into the final 7-day average
  AA.db.realm.parsedData = AA:mergeAndAverageWeeklyTables(dailyAverages)

  print("Finished Calculating Average!")
end

function AA:mergeAndAverageDailyTables(...)
    local mergedData = {}
    local countData = {}

    -- Iterate over all tables provided as arguments
    for _, tbl in ipairs({...}) do
        for itemID, values in pairs(tbl) do
            -- Initialize in mergedData and countData if not already present
            if not mergedData[itemID] then
                mergedData[itemID] = 0
                countData[itemID] = 0
            end
            -- Sum the values in the sub-table and count the entries
            for _, price in ipairs(values) do
                mergedData[itemID] = mergedData[itemID] + price
                countData[itemID] = countData[itemID] + 1
            end
        end
    end

    -- Calculate the average for each item
    for itemID, total in pairs(mergedData) do
        if countData[itemID] > 0 then
            mergedData[itemID] = total / countData[itemID]
        end
    end

    return mergedData
end

function AA:mergeAndAverageWeeklyTables(...)
  local mergedData = {}
  local countData = {}

  -- Unpack and print the arguments properly
  local args = {...}
  print("Received arguments:")
  for i, dailyAverage in ipairs(args) do
    print("Table " .. i .. ":")
    for itemID, avgPrice in pairs(dailyAverage) do
      print("  ItemID:", itemID, "Price:", avgPrice)
    end
  end

  -- Process each table or numeric average independently
  for _, dailyAverage in pairs(args) do
    if dailyAverage then
      for itemID, avgPrice in pairs(dailyAverage) do
        if not mergedData[itemID] then
          mergedData[itemID] = 0
          countData[itemID] = 0
        end

        -- Add the daily average price directly
        mergedData[itemID] = mergedData[itemID] + avgPrice
        countData[itemID] = countData[itemID] + 1
      end
    end
  end

  -- Calculate the overall 7-day weighted average for each item
  for itemID, total in pairs(mergedData) do
    if countData[itemID] > 0 then
      mergedData[itemID] = total / countData[itemID]
    end
  end

  return mergedData
end

