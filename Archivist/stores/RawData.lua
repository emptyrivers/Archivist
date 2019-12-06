-- Copyright 2019 Allen Faure
-- This addon is distributed under the GNU General Public license version 3.0
-- You should have received a copy of the GNU General Public License
-- along with this addon. If not, see https://www.gnu.org/licenses/.

local Archivist = select(2, ...).Archivist

-- super simple data store that just holds data

local prototype = {
	id = "RawData",
	version = 1,
	Create = function(self, data)
		if type(data) ~= "table" then
			data = {}
		end
		return data, data
	end,
	Open = function(self, data) return data end,
	Commit = function(self, store) return store end,
	Close = function(self, store) return store end,
}

Archivist:RegisterStoreType(prototype)
