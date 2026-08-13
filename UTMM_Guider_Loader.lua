local URL = "https://raw.githubusercontent.com/MyStupidHubs/UTMM-Guider/main/UTMM_Guider.lua"
local source = game:HttpGet(URL)
assert(type(source) == "string" and #source > 1000, "[UTMM Guider] Falha ao baixar o script.")
loadstring(source, "UTMM Guider")()
