-- Framework detection, shared by the server and client side of the core.
Core = { Name = GetCurrentResourceName() }

local function running(resource)
    local state = GetResourceState(resource)
    return state == 'started' or state == 'starting'
end
Core.IsRunning = running

local frameworks = {
    { name = 'esx', resource = 'es_extended' },
    -- qbx_core also provides qb-core, so it has to be checked first.
    { name = 'qbox', resource = 'qbx_core' },
    { name = 'qb', resource = 'qb-core' },
}

local function detect()
    local wanted = Config.Framework
    if wanted and wanted ~= 'auto' then return wanted end
    for _, fw in ipairs(frameworks) do
        if running(fw.resource) then return fw.name end
    end
    return 'standalone'
end

Core.Framework = detect()

function Core.UsesOxInventory()
    if Config.Inventory == 'ox_inventory' then return true end
    if Config.Inventory == 'framework' then return false end
    return running('ox_inventory')
end

function Core.Debug(...)
    if Config.Debug then print(('[%s]'):format(Core.Name), ...) end
end

-- Jobs in one shape for every framework:
-- { name, label, grade, gradeName, gradeLabel, salary, onDuty, isBoss }
local bossGrades = {}
for _, grade in ipairs(Config.BossGrades or {}) do bossGrades[grade] = true end

function Core.NormalizeJob(job)
    if type(job) ~= 'table' or not job.name then return nil end

    if Core.Framework == 'esx' then
        return {
            name = job.name,
            label = job.label or job.name,
            grade = tonumber(job.grade) or 0,
            gradeName = job.grade_name or '',
            gradeLabel = job.grade_label or job.grade_name or '',
            salary = tonumber(job.grade_salary) or 0,
            onDuty = job.onDuty == true,
            isBoss = bossGrades[job.grade_name] == true,
        }
    end

    local grade = type(job.grade) == 'table' and job.grade or {}
    return {
        name = job.name,
        label = job.label or job.name,
        grade = tonumber(grade.level) or tonumber(job.grade) or 0,
        gradeName = grade.name or '',
        gradeLabel = grade.name or '',
        salary = tonumber(job.payment) or 0,
        onDuty = job.onduty == true,
        isBoss = job.isboss == true,
    }
end

if IsDuplicityVersion() then CreateThread(function()
    print(('[%s] framework: ^2%s^7, inventory: ^2%s^7'):format(Core.Name, Core.Framework,
        Core.UsesOxInventory() and 'ox_inventory' or 'framework'))
end) end
