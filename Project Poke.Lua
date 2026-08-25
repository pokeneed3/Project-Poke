local PLACEIDS = {}

if game.PlaceId == SPECIFIC_PLACE_ID then
else
	-- Load Universal script instead
	loadstring(game:HttpGet("https://raw.githubusercontent.com/yourname/yourrepo/main/Universal.lua"))()
end
