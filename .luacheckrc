exclude_files = {
	".luacheckrc",
	"Archivist/libs/*",
}
globals = {
	"Archivist",
	"ACHV_DB",
	"debugprofilestop",
	"CreateFrame",
	"geterrorhandler",
	"LibStub",
	"strsplit",
	"tInvert",
	"time",
}

ignore = {
	"212/self", -- unused argument "self"
	"542", -- empty if branch
	"631", -- line is too long
}
