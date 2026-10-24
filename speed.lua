--[[
    Speed Hack Test Payload + Anti-Cheat Detector  (one file)

    Runs in two contexts automatically:
      * SERVER  -> runs the anti-cheat detector (paste into a Script
                   in ServerScriptService, or run it as a server Script)
      * CLIENT  -> runs the speed test payload (run via executor)

    So one raw file does both jobs depending on where it executes.
]]

--------------------------------------------------
-- CONFIG  (change these)
--------------------------------------------------
local CONFIG = {
    -- ==== client payload ====
    SPEED           = 100,    -- WalkSpeed you want (Roblox default = 16)
    JUMP_POWER      = 50,     -- JumpPower you want  (Roblox default = 50)
    USE_JUMP_HEIGHT = false,  -- true = use JumpHeight instead of JumpPower
    JUMP_HEIGHT     = 7.2,    -- only used when USE_JUMP_HEIGHT = true

    -- ==== server detector ====
    MAX_WALKSPEED = 24,   -- your legit WalkSpeed cap (default 16, +tolerance)
    MAX_SPEED     = 24,   -- max studs/sec you allow
    TOLERANCE     = 1.5,  -- multiplier so lag/slopes don't false-positive
    STRIKES       = 3,    -- failed movement checks in a row before acting
}
--------------------------------------------------

local Players = game:GetService("Players")

--=====================================================================
-- SERVER  ->  ANTI-CHEAT DETECTION
--=====================================================================
if game:GetService("RunService"):IsServer() then
    local RunService = game:GetService("RunService")

    -- Layer 1: property check. Catches naive WalkSpeed writes, because the
    -- client's value replicates up to the server.
    local function watchProperty(player)
        player.CharacterAdded:Connect(function(character)
            local humanoid = character:WaitForChild("Humanoid")
            humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
                if humanoid.WalkSpeed > CONFIG.MAX_WALKSPEED then
                    warn(("[AC] %s set WalkSpeed to %d"):format(player.Name, humanoid.WalkSpeed))
                    humanoid.WalkSpeed = 16 -- correct it server-side
                    -- flag/punish the player here
                end
            end)
        end)
    end

    -- Layer 2: movement check. Catches speed regardless of how it's faked,
    -- and is what makes the server "kick back".
    local state = {} -- [player] = { lastPos, strikes }

    local function trackMovement(player)
        player.CharacterAdded:Connect(function(character)
            local hrp = character:WaitForChild("HumanoidRootPart")
            state[player] = { lastPos = hrp.Position, strikes = 0 }

            RunService.Heartbeat:Connect(function(dt)
                local data = state[player]
                if not data or not hrp.Parent or dt <= 0 then return end

                local moved = (hrp.Position - data.lastPos).Magnitude
                data.lastPos = hrp.Position

                local speed = moved / dt
                if speed > CONFIG.MAX_SPEED * CONFIG.TOLERANCE then
                    data.strikes += 1
                    if data.strikes >= CONFIG.STRIKES then
                        warn(("[AC] %s moving at %.1f studs/s"):format(player.Name, speed))
                        -- teleport back / kick here
                        data.strikes = 0
                    end
                else
                    data.strikes = 0
                end
            end)
        end)
    end

    Players.PlayerAdded:Connect(watchProperty)
    Players.PlayerAdded:Connect(trackMovement)
    for _, p in Players:GetPlayers() do
        watchProperty(p)
        trackMovement(p)
    end

    print("[SpeedScript] Server detector running.")

--=====================================================================
-- CLIENT  ->  TEST PAYLOAD
--=====================================================================
else
    local RunService = game:GetService("RunService")
    local LocalPlayer = Players.LocalPlayer

    -- Keep WalkSpeed (and jump) forced on a Humanoid for as long as it lives.
    local function bindCharacter(character)
        local humanoid = character:WaitForChild("Humanoid", 10)
        if not humanoid then
            warn("[SpeedScript] Character has no Humanoid.")
            return
        end

        if CONFIG.USE_JUMP_HEIGHT then
            humanoid.UseJumpPower = false
            humanoid.JumpHeight = CONFIG.JUMP_HEIGHT
        else
            humanoid.UseJumpPower = true
            humanoid.JumpPower = CONFIG.JUMP_POWER
        end

        -- Re-apply every frame so a one-time game reset can't stick.
        task.spawn(function()
            while humanoid and humanoid.Parent do
                humanoid.WalkSpeed = CONFIG.SPEED
                RunService.RenderStepped:Wait()
            end
        end)
    end

    if LocalPlayer.Character then
        bindCharacter(LocalPlayer.Character)
    end
    LocalPlayer.CharacterAdded:Connect(bindCharacter)

    print("[SpeedScript] Client payload running. Speed =", CONFIG.SPEED)
end
