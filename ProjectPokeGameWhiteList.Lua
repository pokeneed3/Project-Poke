if game.GameId == 7970033072 then
	assert(
		loadstring(
			game:HttpGet(
				"https://raw.githubusercontent.com/pokeneed3/Project-Poke/refs/heads/main/ProjectPokeTheVeil.Lua"
			)
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
