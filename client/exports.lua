-- Every Core.Client function is an export: exports.yecoyz_core:GetJob(), or Core.GetJob() in resources that load
-- '@yecoyz_core/import.lua'.
for name, fn in pairs(Core.Client) do
    exports(name, fn)
end
