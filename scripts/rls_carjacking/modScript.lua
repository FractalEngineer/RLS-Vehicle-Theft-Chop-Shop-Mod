-- RLS 2.8 no longer auto-discovers add-ons under career/modules.
local extensionName = "career_modules_carjacking"

core_jobsystem.create(function(job)
  job.sleep(0.25)
  if not extensions.isExtensionLoaded(extensionName) then
    extensions.load(extensionName)
  end
  setExtensionUnloadMode(extensionName, "manual")
end)
