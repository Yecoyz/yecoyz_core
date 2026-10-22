-- Every Core.Server function is an export: exports.yecoyz_core:GetIdentifier(source), or Core.GetIdentifier(source)
-- in resources that load '@yecoyz_core/import.lua'.
for name, fn in pairs(Core.Server) do
    exports(name, fn)
end
