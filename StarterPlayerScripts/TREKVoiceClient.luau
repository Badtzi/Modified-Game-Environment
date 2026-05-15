local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer

repeat task.wait() until shared.S and shared.S.TREK_Remotes
local Remotes = shared.S.TREK_Remotes
local VoicePlayBroadcast = Remotes:WaitForChild("VoicePlayBroadcast")


local SUBTITLE_CONFIG = {
	Size = UDim2.new(0, 240, 0, 40),
	StudsOffset = Vector3.new(0, 3, 0),
	TextColor = Color3.fromRGB(255, 255, 255),
	TextStrokeColor = Color3.fromRGB(0, 0, 0),
	TextStrokeTransparency = 0,
	BackgroundColor = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.4,
	TextSize = 18,
	Font = Enum.Font.GothamMedium,
	FadeDuration = 0.25,  -- Fade-out time when subtitle is about to end
}


local function createSubtitleGui(speakerCharacter, text, duration)
	if not speakerCharacter then return end
	if not text or text == "" then return end

	local head = speakerCharacter:FindFirstChild("Head")
	if not head then return end

	-- Clean up any existing subtitle for this speaker first
	local existing = head:FindFirstChild("VoiceSubtitle")
	if existing then existing:Destroy() end

	local gui = Instance.new("BillboardGui")
	gui.Name = "VoiceSubtitle"
	gui.Adornee = head
	gui.Size = SUBTITLE_CONFIG.Size
	gui.StudsOffset = SUBTITLE_CONFIG.StudsOffset
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 80  -- Only visible within 80 studs

	local label = Instance.new("TextLabel")
	label.Parent = gui
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundColor3 = SUBTITLE_CONFIG.BackgroundColor
	label.BackgroundTransparency = SUBTITLE_CONFIG.BackgroundTransparency
	label.BorderSizePixel = 0
	label.Text = text
	label.TextColor3 = SUBTITLE_CONFIG.TextColor
	label.TextStrokeColor3 = SUBTITLE_CONFIG.TextStrokeColor
	label.TextStrokeTransparency = SUBTITLE_CONFIG.TextStrokeTransparency
	label.TextSize = SUBTITLE_CONFIG.TextSize
	label.Font = SUBTITLE_CONFIG.Font
	label.TextWrapped = true

	-- Rounded corners
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	gui.Parent = head

	-- Auto-cleanup after duration
	Debris:AddItem(gui, duration + SUBTITLE_CONFIG.FadeDuration)
end

local function playSoundOnSpeaker(speakerCharacter, soundTemplate)
	if not speakerCharacter or not soundTemplate then return end

	local head = speakerCharacter:FindFirstChild("Head")
	if not head then return end

	-- Clone the template so we don't mess with the original
	local sound = soundTemplate:Clone()
	sound.Parent = head
	sound:Play()

	-- Auto-cleanup once the sound finishes
	local cleanupTime = (sound.TimeLength > 0 and sound.TimeLength or 5) + 1
	Debris:AddItem(sound, cleanupTime)
end

VoicePlayBroadcast.OnClientEvent:Connect(function(speaker, soundTemplate, subtitleText, duration)
	if not speaker then return end
	if not soundTemplate or not soundTemplate:IsA("Sound") then return end

	local character = speaker.Character
	if not character then return end

	playSoundOnSpeaker(character, soundTemplate)

	if subtitleText and subtitleText ~= "" then
		createSubtitleGui(character, subtitleText, duration or 3)
	end
end)
