-- Copyright 2019 Allen Faure
-- This addon is distributed under the GNU General Public license version 3.0
-- You should have received a copy of the GNU General Public License
-- along with this addon.  If not, see https://www.gnu.org/licenses/.

local _, Archivist = ...

-- super simple data store that just holds data

local prototype = {
	id = "simple",
	version = 1,
	Create = function() return {} end,
	Open = function(store) return store end,
	Commit = function(store) return store end,
	Close = function(store) return store end,
}

Archivist:RegisterStoreType(prototype)
