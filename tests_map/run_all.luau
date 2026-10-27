--!nonstrict
local T = require("./TestRunner")
require("./Map.spec")
local ok = T.report()
if not ok then
	error("테스트 실패")
end
return ok
