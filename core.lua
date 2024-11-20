local AA = LibStub("AceAddon-3.0"):NewAddon("AucAvg", "AceConsole-3.0", "AceSerializer-3.0")
local AA_GUI = {}

local defaults = {
  realm = {
  }
}

function AA:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("AucAvgDB", defaults, true)
  AA:RegisterChatCommand("aa", "CalculateAverage")
  --self.db:ResetDB()
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
  local timeSpans = {7, 14, 30, 90, 180}
  local now = time()

  -- make all averages
  for _, days in ipairs(timeSpans) do  
    local ts = now - (days * 24 * 60 * 60)
    local scanData = {}

    -- get scans within date range, correct realm
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
      dailyAverages[day] = AA:averageOneDay(unpack(results))
    end

    -- Calculate dailys into final averages, save data
    local dbField = (days == 7 and "oneWeekAvg") or 
                  (days == 14 and "twoWeekAvg") or
                  (days == 30 and "oneMonthAvg") or
                  (days == 90 and "threeMonthAvg") or 
                  (days == 180 and "sixMonthAvg")
    print(dbField)
    if AA.db.realm[faction] == nil then AA.db.realm[faction] = {} end
    AA.db.realm[faction][dbField] = AA:averageAllDays(dailyAverages)
  end

  print("Finished Calculating Average!")
end

function AA:averageOneDay(...)
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

function AA:averageAllDays(dailyAverages)
  local mergedData = {}
  local countData = {}

  -- Filter outliers globally
  local filteredAverages = AA:filterOutliersGlobally(dailyAverages)

  -- Process each table or numeric average independently
  for date, priceTable in pairs(filteredAverages) do
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

  -- Calculate the overall weighted average for each item
  for itemID, total in pairs(mergedData) do
    if countData[itemID] > 0 then
      mergedData[itemID] = total / countData[itemID]
    end
  end

  return mergedData
end

function AA:filterOutliersGlobally(dailyAverages)
  -- Gather all prices for each itemID globally
  local allPrices = {}
  for _, dailyTable in pairs(dailyAverages) do
    for itemID, price in pairs(dailyTable) do
      allPrices[itemID] = allPrices[itemID] or {}
      table.insert(allPrices[itemID], price)
    end
  end

  -- Calculate the median for each itemID
  local medians = {}
  local function calculateMedian(prices)
    table.sort(prices)
    local n = #prices
    if n % 2 == 0 then
      return (prices[n / 2] + prices[n / 2 + 1]) / 2
    else
      return prices[math.ceil(n / 2)]
    end
  end

  for itemID, prices in pairs(allPrices) do
    medians[itemID] = calculateMedian(prices)
  end

  -- Filter outliers based on the global median
  local filteredData = {}
  for day, dailyTable in pairs(dailyAverages) do
    filteredData[day] = {}
    for itemID, price in pairs(dailyTable) do
      local median = medians[itemID]
      local lowerBound = median / 2.3
      local upperBound = median * 2.3

      if price >= lowerBound and price <= upperBound then
        filteredData[day][itemID] = price
      end
    end
  end

  return filteredData
end

AucAvgGetAuctionInfoByLink = function(link, key)
  local itemID = select(2, strsplit(":", link)) -- Extract item ID from the item link
  local realm = GetNormalizedRealmName()
  local faction = UnitFactionGroup("PLAYER")
  if not itemID then
      return nil
  end
  local auctionInfo = AA.db.realm[faction][key][itemID]
  if auctionInfo then
      return { [key] = auctionInfo }
  end
  return nil
end

--  -- AucAvg
--  if Addon.IsEnabled("AucAvg") and AucAvgGetAuctionInfoByLink then
--    CustomString.InvalidateCache("OneWeekAvg")
--    CustomString.InvalidateCache("TwoWeekAvg")
--    CustomString.InvalidateCache("OneMonthAvg")
--    CustomString.InvalidateCache("ThreeMonthAvg")
--    CustomString.InvalidateCache("SixMonthAvg")
--    local function PriceFuncHelper(itemString, key)
--      local itemLink = ItemInfo.GetLink(itemString)
--			if not itemLink then
--				return nil
--			end
--			local info = AucAvgGetAuctionInfoByLink(itemLink, key)
--			return info and info[key] or nil
--    end
--    local function OneWeekAvgFunc(itemString)
--      return PriceFuncHelper(itemString, "oneWeekAvg")
--    end
--    local function TwoWeekAvgFunc(itemString)
--      return PriceFuncHelper(itemString, "twoWeekAvg")
--    end
--    local function OneMonthAvgFunc(itemString)
--      return PriceFuncHelper(itemString, "oneMonthAvg")
--    end
--    local function ThreeMonthAvgFunc(itemString)
--      return PriceFuncHelper(itemString, "threeMonthAvg")
--    end
--    local function SixMonthAvgFunc(itemString)
--      return PriceFuncHelper(itemString, "sixMonthAvg")
--    end
--    CustomString.RegisterSource("External", "OneWeekAvg", "One Week Avg", OneWeekAvgFunc, CustomString.SOURCE_TYPE.PRICE_DB) 
--    CustomString.RegisterSource("External", "TwoWeekAvg", "Two Week Avg", TwoWeekAvgFunc, CustomString.SOURCE_TYPE.PRICE_DB) 
--    CustomString.RegisterSource("External", "OneMonthAvg", "One Month Avg", OneMonthAvgFunc, CustomString.SOURCE_TYPE.PRICE_DB) 
--    CustomString.RegisterSource("External", "ThreeMonthAvg", "Three Month Avg", ThreeMonthAvgFunc, CustomString.SOURCE_TYPE.PRICE_DB) 
--    CustomString.RegisterSource("External", "SixMonthAvg", "Six Month Avg", SixMonthAvgFunc, CustomString.SOURCE_TYPE.PRICE_DB) 
--  end
