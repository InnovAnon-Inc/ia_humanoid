-- IA Humanoid Framework
-- Core dependencies must be loaded before this mod
assert(fakelib        ~= nil)
assert(futil          ~= nil)
assert(ia_names       ~= nil)
assert(name_generator ~= nil)
assert(persistencelib ~= nil)
assert(armor     .on_joinplayer  ~= nil)
assert(armor     .on_leaveplayer ~= nil)
assert(edit_skin .on_joinplayer  ~= nil)
assert(edit_skin .on_leaveplayer ~= nil)
assert(player_api.on_joinplayer  ~= nil)
assert(player_api.on_leaveplayer ~= nil)

ia_humanoid = {}

---------------------------
-- 1. Initialization Logic
---------------------------

local function init_name_generator()
    local namegen_path = minetest.get_modpath("name_generator")
    assert(namegen_path ~= nil)
    local cfg_path     = namegen_path .. "/data/creatures.cfg"
    name_generator.parse_lines(io.lines(cfg_path))
end

init_name_generator()

---------------------------
-- 2. Internal Helpers
---------------------------

-- Generates a name and ensures it is reserved in ia_names
local function generate_human_name(gender)
    assert(gender ~= nil)
    local first, last

    -- Prevent crash if .cfg is missing specific categories
    pcall(function()
        first = name_generator.generate("human "..gender)
        last = name_generator.generate("human surname")
    end)
    assert(first)
    assert(last)

    --local base_name = "ia_" .. first .. "_" .. last
    local base_name = first .. " " .. last
    local final_name = base_name
    local suffix = 1

    -- Ensure uniqueness across players and existing entities
    while not ia_names.is_available(final_name) do
        final_name = base_name .. suffix
        suffix = suffix + 1
    end

    ia_names.reserve(final_name)
    return final_name
end

-- Synchronizes the detached armor inventory back to the fake player's local inventory
local function sync_armor_inventory(player)
    local name = player:get_player_name()
    local det_inv = minetest.get_inventory({type="detached", name=name.."_armor"})
    local player_inv = player:get_inventory()

    if det_inv and player_inv then
	local sz = det_inv:get_size("armor")
        player_inv:set_size("armor", sz)
        for i = 1, sz do
            local stack = det_inv:get_stack("armor", i)
            player_inv:set_stack("armor", i, stack)
        end
    end
end

---------------------------
-- 3. The Lifecycle API
---------------------------
-- Initializes the humanoid "Soul" (Identity, Physicality, Skin, Armor)
function ia_humanoid.init(self, staticdata)
    local data = minetest.deserialize(staticdata) or {}

    -- A. Assign Identity
    self.gender   = data.gender   or ia_gender.generate_human_gender()
    self.mob_name = data.mob_name or generate_human_name(self.gender)

    -- B. Create Volatile Body
    self.fake_player = fakelib.create_player({
        name     = self.mob_name, -- TODO mob_name is the most player-like / entity-like attribute ?
        position = self.object:get_pos(),
	object   = self.object,
    })
    assert(self.fake_player:get_player_name() == self.mob_name)
    if data.state then
        persistencelib.apply_state(self.fake_player, data.state)
    else
        self.fake_player:get_meta():set_string("ia_gender:gender", self.gender)
    end
    assert(self.fake_player:get_meta():get_string("ia_gender:gender") ~= nil)
    --assert(self.fake_player:get_inventory():get_size("armor") > 0)

    player_api.on_joinplayer(self.fake_player)
    player_api.set_model    (self.fake_player, "character.b3d")

    armor     .on_joinplayer(self.fake_player)
    assert(player_api.get_animation(self.fake_player).model == "3d_armor_character.b3d")
    assert(armor.textures[self.mob_name] ~= nil)
    assert(minetest.get_inventory({type="detached", name=self.mob_name.."_armor"}):get_size("armor") > 0)
    sync_armor_inventory(self.fake_player)
    assert(self.fake_player:get_inventory():get_size("armor") > 0)

    edit_skin .on_joinplayer(self.fake_player)
    assert(self.fake_player:get_meta():get_string("edit_skin:skin") ~= nil)

    --self.object:set_properties(self.fake_player:get_properties())
--    armor     .on_joinplayer(self.fake_player)
--    assert(player_api.get_animation(self.fake_player).model == "3d_armor_character.b3d")
--    assert(armor.textures[self.mob_name] ~= nil)
--    --assert(self.fake_player:get_inventory():get_size("armor") > 0)

    -- F. Final Visual Sync
    --armor:set_player_armor(self.fake_player)
    --self.object:set_armor_groups({fleshy = 100})
   
    -- Inside the Dunce entity definition or activation
    self.object:set_acceleration({x = 0, y = -9.81, z = 0})
    futil.log("info", "Humanoid initialized: %s", self.mob_name)
end

-- Captures all persistent data for storage
function ia_humanoid.serialize(self)
--    local skin = edit_skin.player_skins[self.fake_player]
    local state = persistencelib.get_state(self.fake_player)
    
    return minetest.serialize({
	gender = self.gender,
        mob_name = self.mob_name,
--        skin = skin,
        state = state,
    })
end

---------------------------
-- 4. Registration Factory
---------------------------

ia_humanoid.default_props = {
    visual       = "mesh",
    mesh         = "character.b3d",
    textures     = {"character.png"},
    visual_size  = {x=1, y=1},
    collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.7, 0.3},
    stepheight   = 0.6,
    health_max   = 20, -- TODO parametrize ?
    physical     = true,
}

function ia_humanoid.register_humanoid_entity(name, definition)
    -- Merge properties
    local props = table.copy(ia_humanoid.default_props)
    if definition.initial_properties then
        for k, v in pairs(definition.initial_properties) do
            props[k] = v
        end
    end

    local final_def = table.copy(definition)
    final_def.initial_properties = props

    -- Injected Activation
    local user_on_activate = definition.on_activate
    final_def.on_activate = function(self, staticdata, dtime_s)
        ia_humanoid.init(self, staticdata)
        if user_on_activate then
            user_on_activate(self, staticdata, dtime_s)
        end
    end

    -- Injected Persistence
    final_def.get_staticdata = function(self)
        return ia_humanoid.serialize(self)
    end

    -- Injected Combat (3d_armor)
    local user_on_punch = definition.on_punch
    final_def.on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
        armor:punch(self.fake_player, puncher, time_from_last_punch, tool_capabilities)
        if user_on_punch then
            user_on_punch(self, puncher, time_from_last_punch, tool_capabilities, dir)
        end
    end

    minetest.register_entity(name, final_def)
    minetest.log("Registered humanoid entity: "..name)
end

-- In your ia_mob/init.lua or a compatibility file
local old_get_valid_player = armor.get_valid_player
armor.get_valid_player = function(self, player, msg)
	minetest.log('armor.get_valid_player')
    -- If it's one of OUR fake players, bypass the userdata check
    --if fakelib.is_player(player) then
    if player:is_player() then
	    local player_name = player:get_player_name()
	    assert(player_name ~= nil)
	    local inv = minetest.get_inventory({type="detached", name=player:get_player_name().."_armor"})
	    assert(inv ~= nil)
	    minetest.log('armor.get_valid_player fake: '..player_name)
	    return player_name, inv
    end
    -- Otherwise, use the original function
	minetest.log('armor.get_valid_player old')
    return old_get_valid_player(self, player, msg)
end

