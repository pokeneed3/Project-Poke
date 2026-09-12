if game.GameId == 9931749389 then
	loadstring(
		game:HttpGet("https://raw.githubusercontent.com/pokeneed3/Project-Poke/main/ProjectPokeDungeonQuest.Lua")
	)()
elseif game.GameId == 279565647 then
	loadstring(
		game:HttpGet(
			"https://raw.githubusercontent.com/pokeneed3/Project-Poke/main/ProjectPokeLuckyBlockBattleGrounds.Lua"
		)
	)()
else
	return
	-- Load Universal script instead
	--loadstring(game:HttpGet("https://raw.githubusercontent.com/pokeneed3/Project-Poke/main/Universal.Lua"))()
end
