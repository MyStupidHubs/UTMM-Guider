-- Troque pela URL RAW onde UTMM_Guider.lua for hospedado.
local URL = "RAW_URL_DO_UTMM_GUIDER"

assert(type(URL) == "string" and string.find(URL, "http", 1, true) == 1,
    "[UTMM Guider] Configure a URL RAW do script no loader.")

local source = game:HttpGet(URL)
assert(type(source) == "string" and #source > 1000 and string.find(source, "UTMM Guider", 1, true),
    "[UTMM Guider] Falha ao baixar o script principal.")

loadstring(source, "UTMM Guider")()
