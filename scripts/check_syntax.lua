-- Validate syntax without executing WoW globals or loading the addon.
local path = arg[1] or "Core/VibeFishin.lua"
local chunk, err = loadfile(path)
if not chunk then io.stderr:write(err .. "\n"); os.exit(1) end
print("Lua syntax OK: " .. path)
