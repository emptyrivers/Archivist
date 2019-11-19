local addonName, Archivist = "Archivist", {}
-- Our only library!
local LibDeflate = LibStub("LibDeflate")
do -- static value initialization
  _G.Archivist = Archivist

  Archivist.buildDate = "@build-time@"
  Archivist.version = "@project-version@"

  Archivist.prototypes = {}
  Archivist.initqueue = {}
end

function Archivist:Assert(valid, pattern, ...)
  if not valid then
    if pattern then
      error(pattern:format(...), 2)
    else
      error("Archivist encountered an unknown error.", 2)
    end
  end
end

function Archivist:Warn(valid, pattern, ...) -- Like assert, but doesn't interrupt execution
  if not valid then
    if pattern then
      print(pattern:format(...), 2)
    else
      print("Archivist encountered an unknown warning.")
    end
  end
end

function Archivist:IsInitialized()
  return self.initialized
end

function Archivist:Initialize(sv)
  self:Assert(type(sv) == "table", "Attempt to initialize Archivist SavedVariables with a %q instead of a table.", type(sv))
  self.sv = sv
  sv.stores = sv.stores or {}
  self.initialized = true
  for _, prototype in pairs(self.prototypes) do
    self.sv.stores[prototype.id] = self.sv.stores[prototype.id] or {}
    prototype:Init(self.sv.stores[prototype.id])
  end
end

function Archivist:RegisterStoreType(prototype)
  self:Assert(type(prototype) == "table", "Invalid argument #1 to RegisterStoreType: Expected table, got %q instead.", type(prototype))
  -- prototype is now guaranteed to be indexable
  self:Assert(type(prototype.id) == "string", "Invalid prototype field 'id': Expected string, got %q instead.", type(prototype.id))
  self:Assert(type(prototype.version) == "number", "Invalid prototype field 'version': Expected number, got %q instead.", type(prototype.version))
  self:Assert(prototype.version > 0 and prototype.version == math.floor(prototype.version), "Prototype version expected to be a positive integer, but got %d instead.", prototype.version)
  local oldStoreType = self.prototypes[prototype.id]
  self:Assert(not oldStoreType or prototype.version >= oldStoreType.version, "Store type %q already exists with a higher version", oldStoreType and oldStoreType.version)
  -- prototype is now guaranteed to be either new or an Update to existing prototype
  self:Assert(type(prototype.Init) == "function", "Invalid prototype field 'Init': Expected function, got %q instead.", type(prototype.Init))
  self:Assert(type(prototype.Create) == "function", "Invalid prototype field 'Create': Expected function, got %q instead.", type(prototype.Create))
  self:Assert(type(prototype.Open) == "function", "Invalid prototype field 'Open': Expected function, got %q instead.", type(prototype.Open))
  self:Assert(type(prototype.Update) == "function", "Invalid prototype field 'Update': Expected function, got %q instead.", type(prototype.Update))
  self:Assert(type(prototype.Close) == "function", "Invalid prototype field 'Close': Expected function, got %q instead.", type(prototype.Close))
  -- prototype is now guaranteed to have Init, Create, Open, Update functions, and is thus well-formed.
  self.prototypes[prototype.id] = prototype
  if self:IsInitialized() then
    self.sv.stores[prototype.id] = self.sv.stores[prototype.id] or {}
    prototype:Init(self.sv.stores[prototype.id])
  end
end

do -- SV loader/unloader frame
  local SVframe = CreateFrame("frame")
  SVframe:RegisterEvent("ADDON_LOADED")
  SVframe:RegisterEvent("PLAYER_LOGOUT")
  SVframe:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" then
      if addon == addonName then
        if type(ACHV_DB) ~= "table" then
          ACHV_DB = {}
        end
        Archivist:Initialize(ACHV_DB)
      end
    elseif event == "PLAYER_LOGOUT" then
      Archivist:CloseAllStores()
    end
  end)
end

do -- function Archive:GenerateID()
  -- adapted from https://gist.github.com/jrus/3197011
  local function randomHex()
    return ('%x'):format(math.random(0, 0xf))
  end

  function Archivist:GenerateID()
    local template ='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
    return template:gsub('x', randomHex)
  end
end

function Archivist:Create(storeType, id)
  self:Assert(type(storeType) == "string" and self.prototypes[storeType], "Store type must be registered before loading data.")
  self:Assert(id == nil or type(id) == "string" and not self.sv.stores[storeType][id], "A storeType already exists with that id. Did you mean to call Archivist:Open?")
  local store = self.prototypes[storeType]:Create()
  self:Assert(type(store) == "table", "Failed to create a new store of type %q.", storeType)
  if id == nil then
    id = self:GenerateID()
  end
  self.sv.stores[storeType][id] = store
  return store
end

function Archivist:Open(storeType, id, callback)
  self:Assert(type(storeType) == "string" and self.prototypes[storeType], "Store type must be registered before opening a store.")
  self:Assert(type(id) == "string" and self.sv.stores[storeType][id], "Store ID does not exist in the archive. Did you mean to call Archivist:Create?")
  local store = self.sv.stores[storeType][id]
  return self:DeArchive(storeType, store, callback)
end

function Archivist:Delete(storeType, id, force)
  self:Warn(type(storeType == "string") and self.sv.stores[storeType], "There are no stores of that type to delete.")
  self:Assert(force or self.prototypes[storeType], "Store type should be registered before deleting a store. Call Delete again with arg #3 == true to override this.")
  if id and storeType and self.sv.stores[storeType] then
    self.sv.stores[storeType][id] = nil
  end
end

function Archivist:Load(storeType, id, callback, ...)
  -- opens or creates a storeType, depending on what is appropriate
  -- this is the main entry point for other addons
  self:Assert(type(storeType) == "string" and self.prototypes[storeType], "Store type must be registered before loading data.")
  self:Assert(id == nil or type(id) == "string", "Store ID must be a string if provided.")
  self:Assert(not callback or type(callback) == "function", "Load callback must be a function if provided.")
  if id == nil or not self.sv.stores[storeType][id] then
    local newStore = self:Create(storeType, id)
    if callback then
      callback(newStore, ...)
    end
  else
    local savedData = self.sv.stores[storeType][id]
    local job = coroutine.create(function()
      local data = self:DeArchive(savedData)
      coroutine.yield()
      local store = self.prototypes[storeType]:Open(data)
      coroutine.yield()
      if type(callback) == "function" then
        callback(store)
      end
    end)
    self:RunJob(job)
  end
end

do -- function Archivist:Archive(data)
  local tinsert, tconcat = table.insert, table.concat
  -- serialized string looks like
  -- <obj1>,<obj2>,...,<objN>,<value>
  -- (in most cases <value> will be just &1)
  -- <objN> is a series of 0 or more ^<value>:<value> pairs
  -- the contents of the string between ^ or : and the next magic character is a string,
  -- unless the first char is the magic #, in which case it is a number.
  -- @ becomes boolean true, $ becomes false
  -- when deserializing, the result of <value> is our result
  local function replace(c) return "\\"..c end
  local function serialize(value)
    local seenObjects = {}
    local serializedObjects = {}
    local function inner(val)
      local valType = type(val)
      if valType == "boolean" then
        return val and "@" or "$"
      elseif valType == "number" then
        return "#" .. val
      elseif valType == "string" then
        -- escape all characters that might be confused as magic otherwise
        return (val:gsub("[\\&,^@$#:]", replace))
      elseif valType == "table" then
        if not seenObjects[val] then
          -- cross referencing is a thing. Not to hard to serialize but do be careful
          local index = #serializedObjects + 1
          seenObjects[val] = index
          local serialized = {}
          serializedObjects[index] = "" -- so that later inserts go to the correct spot
          for k,v in pairs(val) do
            tinsert(serialized, "^" .. inner(k))
            tinsert(serialized, ":" .. inner(v))
          end
          serializedObjects[index] = tconcat(serialized)
        end
        return "&" .. seenObjects[val]
      end
    end
    tinsert(serializedObjects, inner(value))
    return tconcat(serializedObjects, ',')
  end

  function Archivist:Archive(data)
    local serialized = serialize(data)
    local compressed = LibDeflate:CompressDeflate(serialized)
    return compressed
  end
end

do -- function Archivist:DeArchive(compressed)
  local escape2unused = {
    ["\\"] = "\001",
    ["&"] = "\002",
    [","] = "\003",
    ["^"] = "\004",
    ["@"] = "\005",
    ["$"] = "\006",
    ["#"] = "\007",
    [":"] = "\008",
  }
  local unused2Escape = tInvert(escape2unused)
  local unused = "[\001-\008]"
  local function unusify(c)
    return escape2unused[c] or c
  end
  local function escapify(c)
    return unused2Escape[c] or c
  end
  local function parse(value, objectList)
    local firstChar = value:sub(1,1)
    local remainder = value:sub(2)
    if firstChar == "@" then
      return true, "BOOL", remainder
    elseif firstChar == "$" then
      return false, "BOOL", remainder
    elseif firstChar == "#" then
      local num, rest = remainder:match("([^\\&,^@$#:]*)(.*)")
      return tonumber(num), "NUMBER", rest
    elseif firstChar == "^" then
      local key, _, rest = parse(remainder, objectList)
      return key, "KEY", rest
    elseif firstChar == ":" then
      local val, _, rest = parse(remainder, objectList)
      return val, "VALUE", rest
    elseif firstChar == "&" then
      local num, rest = remainder:match("([^\\&,^@$#:]*)(.*)")
      return objectList[tonumber(num)], "OBJECT", rest
    else
      local str, rest = value:match("([^\\&,^@$#:]*)(.*)")
      return str:gsub(unused, escapify), "STRING", rest
    end
  end
  local function deserialize(value)
    value = value:gsub("\\([\\&,^@$#:])", unusify)
    local serializedObjects = {strsplit(",", value)}
    local objects = {}
    for i = 1, #serializedObjects - 1 do
      objects[i] = {}
    end
    for index, object in pairs(objects) do
      local serial = serializedObjects[index]
      local mode = "KEY"
      local key
      local newValue, valueType
      while #serial > 0 do
        newValue, valueType, serial = parse(serial, objects)
        Archivist:Assert(valueType == mode, "Encountered unexpected token type while parsing object. Expected %q but got %q.", mode, valueType)
        if valueType == "KEY" then
          key = newValue
          mode = "VALUE"
        else
          mode = "KEY"
          object[key] = newValue
        end
      end
      Archivist:Assert(mode == "KEY", "Encountered end of serialized token unexpectedly.")
    end
    local deserialized, _, remainder = parse(serializedObjects[#serializedObjects], objects)
    Archivist:Assert(#remainder == 0, "Unexpected token at end of serialized string. Expected EOF, got %q.", remainder:sub(1,10))
    return deserialized
  end

  function Archivist:DeArchive(compressed)
    local serialized = LibDeflate:DecompressDeflate(compressed)
    local data = deserialize(serialized)
    return data
  end
end

do -- function Archivist:RunJob(thread), function Archivist:CancelJob(jobID)
  local threadRunner = CreateFrame('frame')
  threadRunner.jobs = {}
  function threadRunner:RunJobs()
    self.running = true
    local anyLeft = false
    local done = false
    local startTime = debugprofilestop()
    while not done do
      for jobID, job in pairs(self.jobs) do
        local ok, msg = coroutine.resume(job)
        if coroutine.status(job) == "dead" then
          self.jobs[jobID] = nil
          if not ok then
            geterrorhandler(msg)
          end
        else
          anyLeft = true
        end
        if debugprofilestop() - startTime >= 10 then
          done = true
          break
        end
      end
    end
    if not anyLeft then
      self:SetScript("OnUpdate", nil)
    end
    self.running = false
  end

  function Archivist:RunJob(job, jobID, synchronous)
    self:Assert(type(job) == "thread" or type(job) == "function", "Job must be a callable object.")
    self:Assert(jobID == nil or type(jobID) == "string", "Job ID must be a string if provided.")
    self:Assert(not threadRunner.jobs[jobID], "A job with id %q is already running. Choose a different job id.", jobID)
    if type(job) == "function" then
      job = coroutine.create(job)
    end
    if synchronous then
      while coroutine.status(job) ~= "dead" do
        coroutine.resume(job)
      end
    else
      threadRunner.jobs[jobID or self:GenerateID()] = job
      threadRunner:SetScript("OnUpdate", threadRunner.RunJobs)
      return jobID
    end
  end

  function Archivist:CancelJob(jobID)
    self:Assert(type(jobID) == "string", "Invalid argument #1 to CancelJob: Expected string, got %s.", type(jobID))
    self:Warn(threadRunner.jobs[jobID], "Job %q isn't currently running. Did you mean to cancel a different job?", jobID)
    threadRunner.jobs[jobID] = nil
  end
end
