AA = LibStub("AceAddon-3.0"):NewAddon("AucAvg", "AceConsole-3.0", "AceSerializer-3.0")
AA_GUI = {}

local defaults = {
  realm = {
    sevenDayAvg = {}
  }
}

function AA:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("AucAvgDB", defaults, true)
  AA:RegisterChatCommand("aa", "CalculateAverage")
end

local function parseData(dataString, realm, faction)
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
  local realm = GetNormalizedRealmName()
  local faction = UnitFactionGroup("PLAYER")
  local scanData = {}
  local ts = time() - (7 * 24 * 60 * 60)
  for _, data in pairs(AuctionDBSaved.ah) do
    if (data.ts > ts) and (data.realm == realm) and (data.faction == faction) then 
      table.insert(scanData, data)
    end
  end

  -- Organize scans by day
  local dailyResults = {}
  if #scanData >= 1 then
    for _, data in ipairs(scanData) do
      local day = date("%Y-%m-%d", data.ts) -- Group by day
      dailyResults[day] = dailyResults[day] or {}
      table.insert(dailyResults[day], parseData(data.data, realm, faction))
    end
  end

  -- Calculate daily averages
  local dailyAverages = {}
  for day, results in pairs(dailyResults) do
    dailyAverages[day] = AA:mergeAndAverageDailyTables(unpack(results))
  end


  -- Merge daily averages into the final 7-day average
  AA.db.realm.sevenDayAvg[realm .. "-" .. faction] = AA:mergeAndAverageWeeklyTables(dailyAverages)

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

  -- Process each table or numeric average independently
  for date, priceTable in pairs(...) do
    -- Sum the values in the sub-table and count the entries
    for itemID, price in pairs(priceTable) do
      if not mergedData[itemID] then
        mergedData[itemID] = 0
        countData[itemID] = 0
      end

      mergedData[itemID] = mergedData[itemID] + price
      countData[itemID] = countData[itemID] + 1
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

AucAvgGetAuctionInfoByLink = function(link)
  local itemID = select(2, strsplit(":", link)) -- Extract item ID from the item link
  local realm = GetNormalizedRealmName()
  local faction = UnitFactionGroup("PLAYER")
  if not itemID then
      return nil
  end
  local auctionInfo = AA.db.realm.sevenDayAvg[realm .. "-" .. faction][itemID]
  if auctionInfo then
      return { sevenDayAvg = auctionInfo }
  end
  return nil
end

  -- AucAvg
--  if Addon.IsEnabled("AucAvg") and AucAvgGetAuctionInfoByLink then
--    CustomString.InvalidateCache("SevenDayAvg")
--    local function PriceFuncHelper(itemString, key)
--      local itemLink = ItemInfo.GetLink(itemString)
--			if not itemLink then
--				return nil
--			end
--			local info = AucAvgGetAuctionInfoByLink(itemLink)
--			return info and info[key] or nil
--    end
--    local function SevenDayAvgFunc(itemString)
--      return PriceFuncHelper(itemString, "sevenDayAvg")
--    end
--    CustomString.RegisterSource("External", "SevenDayAvg", L["Seven Day Avg"], SevenDayAvgFunc, CustomString.SOURCE_TYPE.PRICE_DB) 
--  end
