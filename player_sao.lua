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

-- ia_humanoid/player_sao.lua

--- Emulates falling damage logic found in PlayerSAO
-- @param self The entity table
-- @param dtime Delta time from on_step
function ia_humanoid.handle_falling_damage(self, dtime)
    local pos = self.object:get_pos()
    local vel = self.object:get_velocity()
    if not pos or not vel then return end

    -- Initialize tracking variables
    self._last_y_vel = self._last_y_vel or 0

    -- Detection: If we were falling and now we aren't (or we hit something)
    -- We check if the velocity drop was significant.
    local impact = self._last_y_vel - vel.y

    -- In Luanti, falling damage usually triggers when colliding with a surface.
    -- If current Y velocity is ~0 (or positive) and we were falling fast:
    if vel.y >= -0.1 and self._last_y_vel < -4.0 then
        -- Standard Luanti calculation:
        -- Damage = (Impact Speed - Safe Speed) * Multiplier
        local safe_speed = 4.0
        local multiplier = 2.0
        local impact_speed = math.abs(self._last_y_vel)

        if impact_speed > safe_speed then
            local damage = math.floor((impact_speed - safe_speed) * multiplier)

            -- Apply 3d_armor's feather fall if applicable
            -- We check the name registry we just built
            local name = self:get_player_name()
            if armor.def[name] and armor.def[name].feather > 0 then
                -- Feather fall typically reduces or negates fall damage
                damage = 0
                -- Optional: log the save
                minetest.log("action", "[ia_humanoid] " .. name .. " feather-falled.")
            end

            if damage > 0 then
                minetest.log("action", string.format("[ia_humanoid] %s took %d fall damage (impact: %.2f)",
                    name, damage, impact_speed))

                -- Use set_hp to trigger armor/death logic
                self:set_hp(self:get_hp() - damage)

                -- Play thud sound
                minetest.sound_play("default_hard_footstep", {
                    pos = pos,
                    gain = 1.0,
                    max_hear_distance = 10,
                })
            end
        end
    end

    -- Update last velocity for next step
    self._last_y_vel = vel.y
end

-- Update the existing breathing helper to include the new call
function ia_humanoid.handle_environment_effects(self, dtime)
    ia_humanoid.handle_breathing_and_drowning(self, dtime)
    ia_humanoid.handle_falling_damage(self, dtime)
end
