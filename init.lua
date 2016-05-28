--tyrant_claim integration for tyrant
--adds "chunk"-based private area protection.
--[[for chunks to claim:
player uses protector tool
set first corner chunk
player uses protector tool a second time
set second corner chunk
calculate "cost" for all claimed chunks
show confirmation "claim n chunks?will cost ..., will span from y=pos+50 to y=pos-50,yes, no"
then: all chunks claimed added to a list
if player has no area yet:
>show setup display name
tyrant_claim.areas={
	[player_name]={
		name="display name of area",
		allow_activate="list_of_pnames_separated_with_spaces",
		allow_inventories="list_of_pnames_separated_with_spaces",
		allow_all="list_of_pnames_separated_with_spaces",
		claim={
			[chunkxpos]={
				[chunkzpos]={
					ymin=int,
					ymax=int
				}
			}
		}
	}
}
formspec:
<name_of_area>[edit]
<field allow_activate>
<field allow_inventories>
<field allow_all>
[save]
]]

-- Boilerplate to support localized strings if intllib mod is installed.
local S
if minetest.get_modpath("intllib") then
	S = intllib.Getter()
else
	-- If you use insertions, but not insertion escapes this will work:
	S = function(s,a,...)a={a,...}return s:gsub("@(%d+)",function(n)return a[tonumber(n)]end)end
end

tyrant_claim={}
tyrant_claim.settings={
	--TestDollar taken for a chunk
	cost_per_chunk=100,
	
	--settings for height of claimed chunk. the default setting makes the whole world column be owned by the player.
	use_absolute_y=true,
	--true:use abs_ymax and abs_ymin as absolute height values
	--false:take current player y and range range_up/range_down nodes up and down.
	
	abs_ymax=31000,
	abs_ymin=-31000,
	
	range_down=50,
	range_up=50,
}

minetest.register_privilege("claim", {
	description = "Can claim chunks.",
})

tyrant_claim.fpath=minetest.get_worldpath().."/tyrant_claim"
local file, err = io.open(tyrant_claim.fpath, "r")
if not file then
	tyrant_claim.areas = {}
	local er=err or "Unknown Error"
	print("[tyrant_claim]Failed loading areas file "..er)
else
	tyrant_claim.areas = minetest.deserialize(file:read("*a"))
	if type(tyrant_claim.areas) ~= "table" then
		tyrant_claim.areas={}
	end
	file:close()
end


tyrant_claim.save = function()
local datastr = minetest.serialize(tyrant_claim.areas)
if not datastr then
	minetest.log("error", "[tyrant_claim] Failed to serialize area data!")
	return
end
local file, err = io.open(tyrant_claim.fpath, "w")
if err then
	return err
end
file:write(datastr)
file:close()
end

tyrant_claim.save_cntdn=10
minetest.register_globalstep(function(dtime)

--and it will save everything
if tyrant_claim.save_cntdn<=0 then
	tyrant_claim.save()
	tyrant_claim.save_cntdn=10 --10 seconds interval!
end
tyrant_claim.save_cntdn=tyrant_claim.save_cntdn-dtime
end)

tyrant_claim.tochunkpos=function(pos)
	local rpos=vector.round(pos)
	return {x=math.floor(rpos.x/16), z=math.floor(rpos.z/16)}
end
tyrant_claim.tonodepos_min=function(cpos, y)
	return {x=cpos.x*16, y=y, z=cpos.z*16}
end
tyrant_claim.tonodepos_max=function(cpos, y)
	return {x=cpos.x*16, y=y, z=cpos.z*16}
end
tyrant_claim.sort_coords=function(c1, c2)
	return
		{x=math.min(c1.x, c2.x), y=math.min(c1.y or 0, c2.y or 0), z=math.min(c1.z, c2.z)},
		{x=math.max(c1.x, c2.x), y=math.max(c1.y or 0, c2.y or 0), z=math.max(c1.z, c2.z)}
end


tyrant_claim.firstmarker_chunk={}

tyrant_claim.placemarker=function(pos, player)
	local pname=player:get_player_name()
	if not tyrant_claim.firstmarker_chunk[pname] then
		tyrant_claim.firstmarker_chunk[pname]=tyrant_claim.tochunkpos(pos)
		minetest.chat_send_player(pname, S("Placed first corner of area at @1, set the second oopposite corner or click again to claim this chunk only.", minetest.pos_to_string(pos)))
		return false
	else
		tyrant_claim.claim_chunks_within(player:get_player_name(), tyrant_claim.firstmarker_chunk[pname], tyrant_claim.tochunkpos(pos), math.floor(pos.y))
	end
end
tyrant_claim.claim_chunks_within=function(pname, chunkpos1, chunkpos2, ypos)
	local cpos1, cpos2=tyrant_claim.sort_coords(chunkpos1, chunkpos2)
	local rpp1=tyrant_claim.tonodepos_min(cpos1, ypos-50)
	local rpp2=tyrant_claim.tonodepos_max(cpos2, ypos+50)
	local hpr=tyrant.get_area_priority_inside(rpp1, rpp2)
	local area=math.abs(cpos2.x-cpos1.x+1)*math.abs(cpos2.z-cpos1.z+1)
	local cost=tyrant_claim.settings.cost_per_chunk*area
	
	local ymin=tyrant_claim.settings.use_absolute_y and tyrant_claim.settings.abs_ymin or ypos-tyrant_claim.settings.range_down
	local ymax=tyrant_claim.settings.use_absolute_y and tyrant_claim.settings.abs_ymax or ypos+tyrant_claim.settings.range_up
	if hpr>=2 then
		tyrant.fs_message(pname, S("The area you've chosen intersects with one or more existing areas!"))
		tyrant_claim.firstmarker_chunk[pname]=nil
		return
	elseif economy.moneyof(pname)<cost then
		tyrant.fs_message(pname, "Insufficient funds: @1 chunks cost @2ŧ, you only have @3ŧ.", area, cost, economy.moneyof(pname))
		tyrant_claim.firstmarker_chunk[pname]=nil
		return
	else
		minetest.show_formspec(pname, "tyrant_claim_confirm_"..cpos1.x.."_"..cpos1.z.."_"..cpos2.x.."_"..cpos2.z.."_"..ypos, 
		"size[6,5]"..
		"label[0.5,0.5;"..S("You are buying @1 Chunks (16x16 nodes) from y=@2 to @3.", area, ymin, ymax).."]"..
		"label[0.5,1;"..S("They range from @1 to @2", minetest.pos_to_string(rpp1), minetest.pos_to_string(rpp2)).."]"..
		"label[0.5,1.5;"..S("This costs @1ŧ", cost).."]"..
		"button_exit[0.5,2;3,1;buy;"..S("Buy!").."]"..
		"button_exit[0.5,3;3,1;cancel;"..S("Cancel").."]")
	end
end
minetest.register_on_player_receive_fields(function(player, formname, fields)
	local x1, z1, x2, z2, ypos=string.match(formname, "tyrant_claim_confirm_([^_]*)_([^_]*)_([^_]*)_([^_]*)_([^_]*)")
	if x1 and z1 and x2 and z2 and fields.buy then
		local pname=player:get_player_name()
		local cpos1, cpos2=tyrant_claim.sort_coords({x=x1, z=z1}, {x=x2, z=z2})
		local rpp1=tyrant_claim.tonodepos_min(cpos1, ypos-50)
		local rpp2=tyrant_claim.tonodepos_max(cpos2, ypos+50)
		local hpr=tyrant.get_area_priority_inside(rpp1, rpp2)
		local area=(cpos2.x-cpos1.x)*(cpos2.z-cpos1.z)
		local cost=tyrant_claim.settings.cost_per_chunk*area
		
		local ymin=tyrant_claim.settings.use_absolute_y and tyrant_claim.settings.abs_ymin or ypos-tyrant_claim.settings.range_down
		local ymax=tyrant_claim.settings.use_absolute_y and tyrant_claim.settings.abs_ymax or ypos+tyrant_claim.settings.range_up
		if hpr>=2 then
			tyrant.fs_message(pname, S("The area you've chosen intersects with one or more existing areas!"))
			tyrant_claim.firstmarker_chunk[pname]=nil
			return
		elseif not economy.canpay(pname, cost) then
			tyrant.fs_message(pname, "Insufficient funds: @1 chunks cost @2ŧ, you only have @3ŧ.", area, cost, economy.moneyof(pname))
			tyrant_claim.firstmarker_chunk[pname]=nil
			return
		else
			for cntx=cpos1.x, cpos2.x do
				for cntz=cpos1.z, cpos2.z do
					if not tyrant_claim.areas[pname] then
						tyrant_claim.areas[pname]={
							name=S("Area of @1",pname),
							allow_activate="",
							allow_inventories="",
							allow_all="",
							claim={},
						}
						tyrant_claim.show_edit_area_name(pname)
					end
					if not tyrant_claim.areas[pname].claim[cntx] then tyrant_claim.areas[pname].claim[cntx]={} end
					tyrant_claim.areas[pname].claim[cntx][cntz]={ymin=ymin, ymax=ymin}
				end
			end
			economy.withdraw(pname, cost, S("Bought some private area"))
		end
	elseif formname=="tyrant_claim_manager" then
		local pname=player:get_player_name()
		if fields.save then
			tyrant_claim.areas[pname].allow_activate=fields.activate
			tyrant_claim.areas[pname].allow_inventories=fields.inventory
			tyrant_claim.areas[pname].allow_all=fields.all
		elseif fields.chname then
			tyrant_claim.show_edit_area_name(pname);
		end
	elseif formname=="tyrant_claim_editname" then
		local pname=player:get_player_name()
		tyrant_claim.areas[pname].name=fields.newname or (tyrant_claim.areas[pname] and tyrant_claim.areas[pname].name or "")
	end
end)

tyrant_claim.give_self_protection_stuff=function(pname)
	tyrant_claim.firstmarker_chunk[pname]=nil
	local inv=minetest.get_player_by_name(pname):get_inventory()
	if not inv:contains_item("main", "tyrant_claim:selfprotector") then
		inv:add_item("main", "tyrant_claim:selfprotector 1");
	end
	return true, S("Given marker tool and reset corners!")
end
minetest.register_craftitem("tyrant_claim:selfprotector",{
        description = S(""),
        inventory_image = "tyrant_claim_markertool.png",
        stack_max = 1,
        on_use = function(itemstack, user, pointed_thing)
			if not pointed_thing or not pointed_thing.type=="node" then return end
			local pos=pointed_thing.under
			if not pos then return end
			if tyrant_claim.placemarker(pos, user) then
				itemstack:take_item()
			end
			return itemstack
		end,
    }
)
--register tyrant integration!
tyrant.register_integration("claim", {
	get_all_area_ids=function()
		return false, tyrant_claim.areas
	end,
	get_is_area_at=function(areaid, pos)
		local cpos=tyrant_claim.tochunkpos(pos)
		--areaid equals player name
		return tyrant_claim.areas[areaid] and tyrant_claim.areas[areaid].claim and tyrant_claim.areas[areaid].claim[cpos.x] and tyrant_claim.areas[areaid].claim[cpos.x][cpos.z]
			and tyrant_claim.areas[areaid].claim[cpos.x][cpos.z].ymax>=pos.y and tyrant_claim.areas[areaid].claim[cpos.x][cpos.z].ymin<=pos.y
	end,
	get_area_priority=function(areaid)
		return 2
	end,
	check_permission=function(areaid, name, action)
		if not name or name=="" or not tyrant_claim.areas[areaid] then
			return true
		end
		if name==areaid then
			return true
		end
		if action=="activate" then
			local area=tyrant_claim.areas[areaid]
			return string.match(" "..area.allow_activate.." ", " "..name.." ", 1, true) or string.match(" "..area.allow_all.." ", " "..name.." ", 1, true)
		elseif action=="inv" then
			local area=tyrant_claim.areas[areaid]
			return string.match(" "..area.allow_inventories.." ", " "..name.." ", 1, true) or string.match(" "..area.allow_all.." ", " "..name.." ", 1, true)
		elseif action=="build" then
			local area=tyrant_claim.areas[areaid]
			return string.match(" "..area.allow_all.." ", " "..name.." ", 1, true)
		elseif action=="pvp" then
			return name==areaid--when owner, then allow, else deny.
			--this elseif is not neccessary, but for overlook reasons kept.
		end
		return true--on action=="punch" or "enter"
	end,
	get_area_intersects_with=function(areaid, p1, p2)
		if not tyrant_claim.areas[areaid] or not tyrant_claim.areas[areaid].claim then return false end
		local claim=tyrant_claim.areas[areaid].claim
		for cposx, claimz in pairs(claim) do
			for cposz, chunk in pairs(claimz) do
				local pos1=tyrant_claim.tonodepos_min({x=cposx, z=cposz}, chunk.ymin)
				local pos2=tyrant_claim.tonodepos_max({x=cposx, z=cposz}, chunk.ymax)
				if (p1.x <= pos2.x and p2.x >= pos1.x) and
					(p1.y <= pos2.y and p2.y >= pos1.y) and
					(p1.z <= pos2.z and p2.z >= pos1.z) then
					return true
				end
			end
		end
		return false
	end,
	is_hostile_mob_spawning_allowed=function(areaid)
		return false
	end,
	on_area_info_requested=function(areaid, player_name)
		if areaid==player_name then
			tyrant_claim.show_area_manager(player_name)
		end
	end,
	get_display_name=function(areaid)
		return tyrant_claim.areas[areaid].name
	end
})
tyrant_claim.show_area_manager=function(pname)
	local area=tyrant_claim.areas[pname]
	if not area then
		minetest.chat_send_player(pname, "You don't have an area yet. Use the /protect command to create one or to extend it.")
		return
	end
	minetest.show_formspec(pname, "tyrant_claim_manager", "size[8,8]label[0,0;"..S("Settings for @1's area",pname).."]label[0,5;"..S("Separate player names with spaces or write '@1a' to allow all", "@").."]"
		.."field[0,2;8,1;activate;"..S("Players that may right-click nodes:")..";"..(area.allow_activate or "").."]"
		.."field[0,3;8,1;inventory;"..S("Players that may right-click nodes and change inventories:")..";"..(area.allow_inventories or "").."]"
		.."field[0,4;8,1;all;"..S("Players that may do everything they want:")..";"..(area.allow_all or "").."]"
		.."button_exit[0,6;5,1;save;"..S("Save!").."]"
		.."button[0,7.5;5,1;chname;"..S("Change area name").."]")
end
tyrant_claim.show_edit_area_name=function(pname)
	local area= tyrant_claim.areas[pname]
	minetest.show_formspec(pname, "tyrant_claim_editname", "field[newname;"..S("Type new name:")..";"..(area.name or "").."]")
end

core.register_chatcommand("protect", {
	params = "",
	description = S("Get area protection tool"),
	privs = {claim=true},
	func = function(name, param)
		return tyrant_claim.give_self_protection_stuff(name)
	end,
})
core.register_chatcommand("unclaim", {
	params = "",
	description = S("Sell the chunk in which you are standing."),
	privs = {claim=true},
	func = function(name, param)
		local p= minetest.get_player_by_name(name)
		if not p then return end
		local c=tyrant_claim.tochunkpos(vector.round(p:getpos()))
		if not tyrant_claim.areas[name] or not tyrant_claim.areas[name].claim or not
				tyrant_claim.areas[name].claim[c.x][c.z] then
			return false, S("This one does not belong to you.")
		end
		tyrant_claim.areas[name].claim[c.x][c.z]=nil
		economy.deposit(name, tyrant_claim.settings.cost_per_chunk, S("Sold some private area"))
		return true, S("Sold sucessfully.")
	end,
})
