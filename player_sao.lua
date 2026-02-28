-- ia_humanoid/player_sao.lua
-- https://github.com/luanti-org/luanti/blob/master/src/server/player_sao.cpp

----- Emulates the drowning and breathing logic found in PlayerSAO::step
---- @param self The entity table
---- @param dtime Delta time from on_step
--function ia_humanoid.handle_breathing_and_drowning(self, dtime)
--	minetest.log('ia_humanoid.handle_breathing_and_drowning(dtime='..dtime..')')
--    -- 1. Setup intervals if they don't exist
--    self._breathing_timer = (self._breathing_timer or 0) + dtime
--    self._drowning_timer = (self._drowning_timer or 0) + dtime
--    
--    -- Assertions to ensure we have the necessary properties
--    assert(self.object, "Entity object is nil during breath check")
--    
--    local pos = self.object:get_pos()
--    if not pos then return end
--
--    -- Approximating eye height (standard is ~1.625)
--    local eye_height = self._prop.eye_height or 1.5
--    local head_pos = {x = pos.x, y = pos.y + eye_height, z = pos.z}
--    local node = minetest.get_node(head_pos)
--    local def = minetest.registered_nodes[node.name]
--    
--    -- Determine if the head is in a drowning-capable node (usually water)
--    local is_head_submerged = def and (def.drowning and def.drowning > 0)
--
--    -- 2. DROWNING LOGIC (Runs every 2 seconds, similar to PlayerSAO)
--    if is_head_submerged then
--	    minetest.log('submerged: '..self:get_player_name())
--        if self._drowning_timer >= 2.0 then
--            self._drowning_timer = 0
--            
--            local current_breath = self:get_breath()
--            if current_breath > 0 then
--                self:set_breath(current_breath - 1)
--            else
--                -- No breath left, apply damage
--                local damage = (def and def.drowning) or 1
--                local hp = self:get_hp()
--                
--                -- We use the existing set_hp which likely handles death/armor
--                self:set_hp(hp - damage)
--                
--                -- Optional: Play a sound or particles
--                minetest.sound_play("default_water_footstep", {pos = head_pos, gain = 0.5})
--            end
--        end
--    -- 3. BREATHING LOGIC (Recover breath when not submerged)
--    else
--	    minetest.log('not submerged: '..self:get_player_name())
--        if self._breathing_timer >= 0.5 then
--            self._breathing_timer = 0
--            local current_breath = self:get_breath()
--            local max_breath = self._prop.breath_max or 11
--            
--            if current_breath < max_breath then
--                self:set_breath(current_breath + 1)
--            end
--        end
--    end
--end
--
---- Example integration into your humanoid definition:
---- function mob_definition:on_step(dtime)
----    handle_breathing_and_drowning(self, dtime)
----    ... existing logic ...
---- end
function ia_humanoid.handle_breathing_and_drowning(self, dtime)
    -- Initialize timers on the entity if they don't exist
    self._breathing_timer = (self._breathing_timer or 0) + dtime
    self._drowning_timer = (self._drowning_timer or 0) + dtime

    -- Eye-level node check
    local pos = self.object:get_pos()
    if not pos then return end
    
    local eye_height = self.initial_properties.eye_height or 1.625
    local head_pos = {x = pos.x, y = pos.y + eye_height, z = pos.z}
    
    local node = minetest.get_node_or_nil(head_pos)
    if not node then return end
    
    local def = minetest.registered_nodes[node.name]
    local is_submerged = def and (def.drowning and def.drowning > 0)

    -- Drowning Logic (Every 2 seconds)
    if is_submerged then
        if self._drowning_timer >= 2.0 then
            self._drowning_timer = 0
            local breath = self:get_breath()
            if breath > 0 then
                self:set_breath(breath - 1)
            else
                local damage = def.drowning or 1
                -- This triggers the on_punch/armor logic via set_hp
                self:set_hp(self:get_hp() - damage)
            end
        end
    -- Breathing Logic (Every 0.5 seconds)
    elseif self._breathing_timer >= 0.5 then
        self._breathing_timer = 0
        local breath = self:get_breath()
        local max_breath = 11 -- Default
        if breath < max_breath then
            self:set_breath(breath + 1)
        end
    end
end
