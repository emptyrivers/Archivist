local _, Archivist = ...

-- super simple data store that just holds data

local prototype = {
	id = "SimpleData",
	version = 1,
	Create = function() return {} end,
	Open = function(store) return store end,
	Commit = function(store) return store end,
	Close = function(store) return store end,
}

Archivist:RegisterStoreType(prototype)
