if game.GameId == 9931749389 then
	assert(
		loadstring(
			game:HttpGet("https://raw.githubusercontent.com/pokeneed3/Project-Poke/main/ProjectPokeDungeonQuest.Lua")
		)
	)()
elseif game.GameId == 279565647 then
	assert(
		loadstring(
			game:HttpGet(
				"https://raw.githubusercontent.com/pokeneed3/Project-Poke/refs/heads/main/ProjectPokeLuckyBlockBattlegrounds.lua"
			)
		)
	)()
else
	-- Load Universal script instead
	assert(
		loadstring(
			game:HttpGet("https://raw.githubusercontent.com/pokeneed3/Project-Poke/main/ProjectPokeUniversal.Lua")
		)
	)()
end
