-- opus client
-- LocalScript. Куда положить: StarterPlayer > StarterPlayerScripts
-- Открыть/скрыть меню: RightControl.
-- Заменяет предыдущие версии меню (не держите две версии одновременно).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local CONFIG = {
	MenuKey = Enum.KeyCode.RightControl,

	-- переключатели (меняются из меню)
	Enabled = true,
	ShowHighlight = true,
	ShowLabel = true,
	ShowNames = true,
	ShowDistance = true,
	ShowHealth = true,
	ShowTeammates = true,
	ShowBoxes = false,          -- 2D-рамка вокруг игрока на экране
	BoxFill = false,            -- полупрозрачная заливка рамки
	BoxThickness = 1.5,
	ShowTracers = false,        -- линия от края экрана к игроку
	TracerOrigin = "Снизу",     -- "Снизу", "Центр" или "Курсор"
	TracerThickness = 1.5,

	-- числовые/цветовые настройки
	MaxDistance = 1000,
	FillTransparency = 0.7,
	OutlineColor = Color3.fromRGB(255, 255, 255),
	EnemyColor = Color3.fromRGB(255, 60, 60),
	TeamColor = Color3.fromRGB(60, 255, 60),
}

--------------------------------------------------------------------
-- ESP
--------------------------------------------------------------------
-- Roblox одновременно рисует не больше 31 Highlight на весь клиент.
-- Самые близкие игроки получают Highlight, остальным рисуется рамка (у неё лимита нет).
local HIGHLIGHT_LIMIT = 30

-- Все объекты ESP лежат в своей папке, а не внутри персонажей:
-- так их не удаляют скрипты игры и не ломает перезагрузка персонажа.
local espFolder = Instance.new("Folder")
espFolder.Name = "ESP_Local"
espFolder.Parent = workspace

-- 2D-элементы (боксы и трейсеры) рисуются в отдельном ScreenGui поверх мира, но под меню
local espScreen = Instance.new("ScreenGui")
espScreen.Name = "OpusClient_ESP2D"
espScreen.IgnoreGuiInset = true -- координаты совпадают с камерой (WorldToViewportPoint)
espScreen.ResetOnSpawn = false
espScreen.DisplayOrder = 5
espScreen.Parent = playerGui

local tracked = {} -- [Player] = { character, head, humanoid, root, highlight, box, gui, label, barBg, barFill, box2d, tracer }

local function isTeammate(player)
	return player.Team ~= nil and player.Team == localPlayer.Team
end

local function clear(player)
	local data = tracked[player]
	if not data then
		return
	end
	data.highlight:Destroy()
	data.box:Destroy()
	data.gui:Destroy()
	data.box2d:Destroy()
	data.tracer:Destroy()
	tracked[player] = nil
end

-- Не ждёт частей персонажа: если чего-то ещё нет (например, персонаж ещё не догрузился),
-- просто выходит, и периодическая проверка попробует снова.
local function build(player, character)
	clear(player)

	local head = character:FindFirstChild("Head")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not head or not humanoid or not root then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = player.Name .. "_Highlight"
	highlight.Adornee = character
	highlight.FillTransparency = CONFIG.FillTransparency
	highlight.OutlineColor = CONFIG.OutlineColor
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = espFolder

	local box = Instance.new("BoxHandleAdornment")
	box.Name = player.Name .. "_Box"
	box.Adornee = root
	box.Size = Vector3.new(4, 5.5, 2.5)
	box.CFrame = CFrame.new(0, -0.3, 0)
	box.AlwaysOnTop = true
	box.ZIndex = 5
	box.Transparency = 0.65
	box.Visible = false
	box.Parent = espFolder

	local gui = Instance.new("BillboardGui")
	gui.Name = player.Name .. "_Label"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(200, 50)
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.Enabled = false
	gui.Parent = espFolder

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 22)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = gui

	local barBg = Instance.new("Frame")
	barBg.AnchorPoint = Vector2.new(0.5, 0)
	barBg.Position = UDim2.new(0.5, 0, 0, 26)
	barBg.Size = UDim2.fromOffset(80, 6)
	barBg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	barBg.BorderSizePixel = 0
	barBg.Parent = gui

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(60, 255, 60)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg

	local box2d = Instance.new("Frame")
	box2d.Name = player.Name .. "_Box2D"
	box2d.AnchorPoint = Vector2.new(0.5, 0.5)
	box2d.BackgroundTransparency = 1
	box2d.BorderSizePixel = 0
	box2d.Visible = false
	box2d.Parent = espScreen

	local boxStroke = Instance.new("UIStroke")
	boxStroke.Thickness = CONFIG.BoxThickness
	boxStroke.Parent = box2d

	-- тёмная подложка под рамкой, чтобы она была видна на любом фоне
	local boxOutline = Instance.new("Frame")
	boxOutline.AnchorPoint = Vector2.new(0.5, 0.5)
	boxOutline.Position = UDim2.fromScale(0.5, 0.5)
	boxOutline.Size = UDim2.new(1, 2, 1, 2)
	boxOutline.BackgroundTransparency = 1
	boxOutline.ZIndex = 0
	boxOutline.Parent = box2d
	local outlineStroke = Instance.new("UIStroke")
	outlineStroke.Color = Color3.fromRGB(0, 0, 0)
	outlineStroke.Transparency = 0.4
	outlineStroke.Thickness = 1
	outlineStroke.Parent = boxOutline

	local tracer = Instance.new("Frame")
	tracer.Name = player.Name .. "_Tracer"
	tracer.AnchorPoint = Vector2.new(0.5, 0.5)
	tracer.BorderSizePixel = 0
	tracer.Visible = false
	tracer.Parent = espScreen

	tracked[player] = {
		character = character,
		head = head,
		humanoid = humanoid,
		root = root,
		highlight = highlight,
		box = box,
		gui = gui,
		label = label,
		barBg = barBg,
		barFill = barFill,
		box2d = box2d,
		boxStroke = boxStroke,
		tracer = tracer,
		distance = 0,
	}
end

-- Всё ли у игрока на месте: тот же персонаж, части не удалены, объекты ESP не удалены
local function isValid(data, character)
	return data.character == character
		and data.head.Parent == character
		and data.humanoid.Parent == character
		and data.root.Parent == character
		and data.highlight.Parent == espFolder
		and data.box.Parent == espFolder
		and data.gui.Parent == espFolder
		and data.box2d.Parent == espScreen
		and data.tracer.Parent == espScreen
end

local function refreshPlayer(player)
	if player == localPlayer then
		return
	end

	local character = player.Character
	if not character or not character.Parent then
		clear(player)
		return
	end

	local data = tracked[player]
	if not data or not isValid(data, character) then
		build(player, character)
	end
end

local function hook(player)
	if player == localPlayer then
		return
	end
	player.CharacterAdded:Connect(function()
		task.defer(refreshPlayer, player)
	end)
	player.CharacterRemoving:Connect(function()
		clear(player)
	end)
	refreshPlayer(player)
end

for _, player in ipairs(Players:GetPlayers()) do
	hook(player)
end
Players.PlayerAdded:Connect(hook)
Players.PlayerRemoving:Connect(clear)

-- Каждые полсекунды проверяем всех игроков и чиним тех, у кого ESP пропал или не создался
local checkTimer = 0
RunService.Heartbeat:Connect(function(dt)
	checkTimer += dt
	if checkTimer < 0.5 then
		return
	end
	checkTimer = 0

	for _, player in ipairs(Players:GetPlayers()) do
		refreshPlayer(player)
	end
	for player in pairs(tracked) do
		if player.Parent ~= Players then
			clear(player)
		end
	end
end)

local highlightCandidates = {}

RunService.RenderStepped:Connect(function()
	local myCharacter = localPlayer.Character
	local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	-- если вы мертвы или персонаж ещё не появился, считаем расстояние от камеры
	local origin = (myRoot and myRoot.Position) or (camera and camera.CFrame.Position)

	table.clear(highlightCandidates)

	for player, data in pairs(tracked) do
		local visible = CONFIG.Enabled and origin ~= nil and data.head.Parent ~= nil
		local distance = 0

		if visible then
			distance = (data.root.Position - origin).Magnitude
			visible = distance <= CONFIG.MaxDistance and data.humanoid.Health > 0
		end

		local teammate = isTeammate(player)
		if visible and teammate and not CONFIG.ShowTeammates then
			visible = false
		end

		local color = teammate and CONFIG.TeamColor or CONFIG.EnemyColor
		data.distance = distance
		data.color = color
		data.wantHighlight = false
		data.wantBox = false

		if visible and CONFIG.ShowHighlight then
			table.insert(highlightCandidates, data)
		end

		data.gui.Enabled = visible and (CONFIG.ShowLabel or CONFIG.ShowHealth)
		data.label.Visible = CONFIG.ShowLabel
		data.barBg.Visible = CONFIG.ShowHealth

		if visible then
			data.label.TextColor3 = color

			local parts = {}
			if CONFIG.ShowNames then
				table.insert(parts, player.DisplayName)
			end
			if CONFIG.ShowDistance then
				table.insert(parts, string.format("[%d]", math.floor(distance)))
			end

			local health = data.humanoid.Health
			local maxHealth = math.max(data.humanoid.MaxHealth, 1)
			local ratio = math.clamp(health / maxHealth, 0, 1)

			if CONFIG.ShowHealth then
				table.insert(parts, string.format("%d HP", math.ceil(health)))
				data.barFill.Size = UDim2.fromScale(ratio, 1)
				data.barFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(60, 255, 60), ratio)
			end

			data.label.Text = table.concat(parts, " ")
		end

		-- боксы и трейсеры
		local showBox = visible and CONFIG.ShowBoxes and camera ~= nil
		local showTracer = visible and CONFIG.ShowTracers and camera ~= nil
		local boxShown, tracerShown = false, false

		if showBox or showTracer then
			local rootPosition = data.root.Position
			local top = camera:WorldToViewportPoint(rootPosition + Vector3.new(0, 3, 0))
			local bottom = camera:WorldToViewportPoint(rootPosition - Vector3.new(0, 3.5, 0))
			local inFront = top.Z > 0 and bottom.Z > 0

			if showBox and inFront then
				local height = math.abs(bottom.Y - top.Y)
				local width = height * 0.6
				data.box2d.Position = UDim2.fromOffset((top.X + bottom.X) / 2, (top.Y + bottom.Y) / 2)
				data.box2d.Size = UDim2.fromOffset(width, height)
				data.boxStroke.Color = color
				data.boxStroke.Thickness = CONFIG.BoxThickness
				data.box2d.BackgroundColor3 = color
				data.box2d.BackgroundTransparency = CONFIG.BoxFill and 0.85 or 1
				boxShown = true
			end

			if showTracer and inFront then
				local viewport = camera.ViewportSize
				local from
				if CONFIG.TracerOrigin == "Центр" then
					from = viewport / 2
				elseif CONFIG.TracerOrigin == "Курсор" then
					from = UserInputService:GetMouseLocation()
				else
					from = Vector2.new(viewport.X / 2, viewport.Y)
				end
				local to = Vector2.new(bottom.X, bottom.Y)
				local delta = to - from
				local length = delta.Magnitude
				if length > 1 then
					local middle = from + delta / 2
					data.tracer.Position = UDim2.fromOffset(middle.X, middle.Y)
					data.tracer.Size = UDim2.fromOffset(length, CONFIG.TracerThickness)
					data.tracer.Rotation = math.deg(math.atan2(delta.Y, delta.X))
					data.tracer.BackgroundColor3 = color
					tracerShown = true
				end
			end
		end

		data.box2d.Visible = boxShown
		data.tracer.Visible = tracerShown
	end

	-- ближайшие получают Highlight, остальные — рамку
	table.sort(highlightCandidates, function(a, b)
		return a.distance < b.distance
	end)
	for index, data in ipairs(highlightCandidates) do
		if index <= HIGHLIGHT_LIMIT then
			data.wantHighlight = true
		else
			data.wantBox = true
		end
	end

	for _, data in pairs(tracked) do
		data.highlight.Enabled = data.wantHighlight
		data.box.Visible = data.wantBox
		if data.wantHighlight then
			data.highlight.FillColor = data.color
		end
		if data.wantBox then
			data.box.Color3 = data.color
		end
	end
end)

--------------------------------------------------------------------
-- Виртуальная китайская шляпа (конус над головой вашего персонажа)
-- Собирается из стопки тонких дисков, поэтому острие всегда смотрит вверх.
--------------------------------------------------------------------
local HAT = {
	Enabled = false,
	Rainbow = false,
	Color = Color3.fromRGB(255, 90, 90),
	Radius = 1.4,
	Height = 0.9,
	Transparency = 0.35,
	Glow = false,         -- свечение: неоновый материал + свет вокруг
	GlowStrength = 2,     -- сила свечения (0-5)
	Gap = 0.3,       -- зазор между макушкой и краем шляпы (в studs)
	Style = "Конус", -- "Конус", "Купол" или "Цилиндр"
	FirstPersonDistance = 1.5, -- ближе этого расстояния камеры до головы считается видом от первого лица
}

local HAT_STYLES = { "Конус", "Купол", "Цилиндр" }
local HAT_SEGMENTS = 24     -- из скольких треугольников собирается конус (больше — глаже)
local HAT_THICKNESS = 0.05  -- толщина стенки шляпы

-- Рисует треугольник a-b-c из двух клиньев (WedgePart). Возвращает обе детали.
local function makeTriangle(a, b, c)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b

	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))

	local w1 = Instance.new("WedgePart")
	w1.Size = Vector3.new(HAT_THICKNESS, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)

	local w2 = Instance.new("WedgePart")
	w2.Size = Vector3.new(HAT_THICKNESS, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)

	return w1, w2
end

local hat = nil -- { folder, parts, head, radius, height }

local function destroyHat()
	if hat then
		if hat.lightAttachment then
			hat.lightAttachment:Destroy()
		end
		hat.folder:Destroy()
		hat = nil
	end
end

local function addHatPart(folder, parts, head, part)
	part.Material = Enum.Material.SmoothPlastic
	part.CastShadow = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Transparency = 1
	part.Parent = folder

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = part
	weld.Parent = part

	parts[#parts + 1] = part
end

local function buildHat(character)
	destroyHat()

	local head = character:WaitForChild("Head", 5)
	if not head then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "ChinaHat"
	folder.Parent = character

	local parts = {}
	local baseY = head.Size.Y / 2

	if HAT.Style == "Купол" then
		-- половина сферы (нижняя половина спрятана в голове)
		local diameter = HAT.Radius * 2
		local dome = Instance.new("Part")
		dome.Name = "Dome"
		dome.Shape = Enum.PartType.Ball
		dome.Size = Vector3.new(diameter, diameter, diameter)
		dome.CFrame = head.CFrame * CFrame.new(0, baseY + diameter * 0.3, 0)
		addHatPart(folder, parts, head, dome)

	elseif HAT.Style == "Цилиндр" then
		-- тулья
		local top = Instance.new("Part")
		top.Name = "Top"
		top.Shape = Enum.PartType.Cylinder
		top.Size = Vector3.new(HAT.Height, HAT.Radius * 1.3, HAT.Radius * 1.3)
		top.CFrame = head.CFrame * CFrame.new(0, baseY + HAT.Height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
		addHatPart(folder, parts, head, top)

		-- поля (брим)
		local brim = Instance.new("Part")
		brim.Name = "Brim"
		brim.Shape = Enum.PartType.Cylinder
		brim.Size = Vector3.new(0.08, HAT.Radius * 2.6, HAT.Radius * 2.6)
		brim.CFrame = head.CFrame * CFrame.new(0, baseY + 0.04, 0) * CFrame.Angles(0, 0, math.pi / 2)
		addHatPart(folder, parts, head, brim)

	else -- "Конус" — полая тонкая стенка из треугольников, приподнята над головой
		local headCF = head.CFrame
		local rimY = baseY + HAT.Gap
		local tip = (headCF * CFrame.new(0, rimY + HAT.Height, 0)).Position

		for i = 0, HAT_SEGMENTS - 1 do
			local angle1 = (i / HAT_SEGMENTS) * math.pi * 2
			local angle2 = ((i + 1) / HAT_SEGMENTS) * math.pi * 2
			local p1 = (headCF * CFrame.new(math.cos(angle1) * HAT.Radius, rimY, math.sin(angle1) * HAT.Radius)).Position
			local p2 = (headCF * CFrame.new(math.cos(angle2) * HAT.Radius, rimY, math.sin(angle2) * HAT.Radius)).Position

			local w1, w2 = makeTriangle(tip, p1, p2)
			addHatPart(folder, parts, head, w1)
			addHatPart(folder, parts, head, w2)
		end
	end

	-- источник света над головой для свечения
	local lightAttachment = Instance.new("Attachment")
	lightAttachment.Name = "ChinaHatLight"
	lightAttachment.Position = Vector3.new(0, baseY + HAT.Gap + HAT.Height / 2, 0)
	lightAttachment.Parent = head

	local light = Instance.new("PointLight")
	light.Shadows = false
	light.Enabled = false
	light.Parent = lightAttachment

	hat = {
		folder = folder,
		parts = parts,
		head = head,
		lightAttachment = lightAttachment,
		light = light,
		radius = HAT.Radius,
		height = HAT.Height,
		style = HAT.Style,
		gap = HAT.Gap,
	}
end

localPlayer.CharacterAdded:Connect(buildHat)
localPlayer.CharacterRemoving:Connect(destroyHat)
if localPlayer.Character then
	task.spawn(buildHat, localPlayer.Character)
end

RunService.RenderStepped:Connect(function()
	if not hat or not hat.folder.Parent then
		return
	end

	-- если в меню изменили радиус, высоту или форму, собираем шляпу заново
	if hat.radius ~= HAT.Radius or hat.height ~= HAT.Height or hat.style ~= HAT.Style or hat.gap ~= HAT.Gap then
		local character = localPlayer.Character
		if character then
			buildHat(character)
		end
		if not hat then
			return
		end
	end

	local camera = workspace.CurrentCamera
	local firstPerson = camera ~= nil
		and (camera.CFrame.Position - hat.head.Position).Magnitude < HAT.FirstPersonDistance
	local visible = HAT.Enabled and not firstPerson

	local transparency = visible and HAT.Transparency or 1
	local color = HAT.Rainbow and Color3.fromHSV((os.clock() * 0.3) % 1, 0.8, 1) or HAT.Color

	local material = HAT.Glow and Enum.Material.Neon or Enum.Material.SmoothPlastic
	for _, part in ipairs(hat.parts) do
		part.Transparency = transparency
		if visible then
			part.Color = color
			part.Material = material
		end
	end

	hat.light.Enabled = visible and HAT.Glow and HAT.GlowStrength > 0
	hat.light.Color = color
	hat.light.Brightness = HAT.GlowStrength
	hat.light.Range = 4 + HAT.GlowStrength * 2
end)

--------------------------------------------------------------------
-- Полоса за персонажем при ходьбе (Trail)
--------------------------------------------------------------------
local TRAIL = {
	Enabled = false,
	Rainbow = false,
	Color = Color3.fromRGB(90, 170, 255),
	Lifetime = 1.5,      -- сколько секунд полоса остаётся за вами
	Height = 3,          -- высота полосы в studs
	Transparency = 0.2,  -- прозрачность у персонажа; к хвосту полоса плавно исчезает
	Glow = true,         -- свечение (без него полоса освещается как обычный предмет)
	GlowStrength = 1.5,  -- яркость свечения (0-5)
	Style = "Лента", -- "Лента", "Крылья", "Линия" или "Комета"
	FirstPersonDistance = 1.5, -- ближе этого расстояния камеры до головы считается видом от первого лица
}

local TRAIL_STYLES = { "Лента", "Крылья", "Линия", "Комета" }

-- Чем отличаются модели полосы:
--   Horizontal — лента идёт слева направо (иначе сверху вниз)
--   FaceCamera — лента всегда повёрнута к камере (у горизонтальной выключено, иначе она выглядит как вертикальная)
--   WidthScale — ширина от персонажа (0) к хвосту (1)
--   WidthFactor — доля от «Высоты полосы»
local TRAIL_STYLE_SETTINGS = {
	["Лента"] = {
		Horizontal = false,
		FaceCamera = true,
		WidthFactor = 1,
		WidthScale = NumberSequence.new(1),
	},
	["Крылья"] = {
		Horizontal = true,
		FaceCamera = false,
		WidthFactor = 1.4,
		WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0.1),
		}),
	},
	["Линия"] = {
		Horizontal = false,
		FaceCamera = true,
		WidthFactor = 0.12,
		WidthScale = NumberSequence.new(1),
	},
	["Комета"] = {
		Horizontal = false,
		FaceCamera = true,
		WidthFactor = 0.6,
		WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
	},
}
local trailData = nil -- { trail, a0, a1, wings }

local function destroyTrail()
	if trailData then
		trailData.trail:Destroy()
		trailData.a0:Destroy()
		trailData.a1:Destroy()
		trailData = nil
	end
end

local function buildTrail(character)
	destroyTrail()

	local root = character:WaitForChild("HumanoidRootPart", 5)
	if not root then
		return
	end

	local a0 = Instance.new("Attachment")
	a0.Name = "TrailA"
	a0.Parent = root

	local a1 = Instance.new("Attachment")
	a1.Name = "TrailB"
	a1.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = "MovementTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Enabled = TRAIL.Enabled
	trail.Parent = root

	trailData = {
		trail = trail,
		a0 = a0,
		a1 = a1,
		head = character:FindFirstChild("Head") or root,
		style = TRAIL.Style,
	}
end

local function rainbowSequence(offset)
	local keypoints = {}
	for i = 0, 6 do
		keypoints[#keypoints + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((offset + i / 6) % 1, 0.8, 1))
	end
	return ColorSequence.new(keypoints)
end

localPlayer.CharacterAdded:Connect(buildTrail)
localPlayer.CharacterRemoving:Connect(destroyTrail)
if localPlayer.Character then
	task.spawn(buildTrail, localPlayer.Character)
end

RunService.RenderStepped:Connect(function()
	local data = trailData
	-- если в меню сменили стиль полосы, собираем её заново
	if data and data.style ~= TRAIL.Style then
		local character = localPlayer.Character
		if character then
			buildTrail(character)
		end
		data = trailData
	end
	if not data or not data.trail.Parent then
		return
	end

	local trail = data.trail

	local camera = workspace.CurrentCamera
	local firstPerson = camera ~= nil
		and (camera.CFrame.Position - data.head.Position).Magnitude < TRAIL.FirstPersonDistance

	trail.Enabled = TRAIL.Enabled and not firstPerson
	if not TRAIL.Enabled then
		return
	end

	local style = TRAIL_STYLE_SETTINGS[TRAIL.Style] or TRAIL_STYLE_SETTINGS["Лента"]
	local half = TRAIL.Height * style.WidthFactor / 2
	if style.Horizontal then
		data.a0.Position = Vector3.new(-half, 0, 0)
		data.a1.Position = Vector3.new(half, 0, 0)
	else
		data.a0.Position = Vector3.new(0, half, 0)
		data.a1.Position = Vector3.new(0, -half, 0)
	end
	trail.FaceCamera = style.FaceCamera
	trail.WidthScale = style.WidthScale

	trail.Lifetime = TRAIL.Lifetime
	-- в первом лице прячем и уже нарисованные участки полосы
	trail.Transparency = firstPerson and NumberSequence.new(1) or NumberSequence.new({
		NumberSequenceKeypoint.new(0, TRAIL.Transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Color = TRAIL.Rainbow and rainbowSequence(os.clock() * 0.3) or ColorSequence.new(TRAIL.Color)
	trail.LightEmission = TRAIL.Glow and 1 or 0
	trail.LightInfluence = TRAIL.Glow and 0 or 1
	trail.Brightness = TRAIL.Glow and math.max(TRAIL.GlowStrength, 0.1) or 1
end)

--------------------------------------------------------------------
-- Летающие частицы в мире вокруг камеры (видны только вам)
--------------------------------------------------------------------
local PARTICLES = {
	Enabled = false,
	Rainbow = false,
	Color = Color3.fromRGB(255, 255, 255),
	Rate = 60,   -- сколько частиц появляется в секунду
	Size = 0.35, -- размер одной частицы
	Range = 60,  -- размер области вокруг вас (в studs)
	Style = "Искры", -- "Искры", "Снег", "Огоньки" или "Дым"
	Glow = true,         -- свечение частиц
	GlowStrength = 1.5,  -- яркость свечения (0-5)
}

local PARTICLE_STYLES = { "Искры", "Снег", "Огоньки", "Дым" }

-- Невидимая деталь-излучатель, которая следует за камерой.
-- Появившиеся частицы остаются в мире, поэтому при движении вы пролетаете сквозь них.
local particlePart = Instance.new("Part")
particlePart.Name = "WorldParticles"
particlePart.Anchored = true
particlePart.CanCollide = false
particlePart.CanQuery = false
particlePart.CanTouch = false
particlePart.CastShadow = false
particlePart.Transparency = 1
particlePart.Size = Vector3.new(PARTICLES.Range, PARTICLES.Range / 2, PARTICLES.Range)
particlePart.Parent = workspace

local particleEmitter = Instance.new("ParticleEmitter")
particleEmitter.Shape = Enum.ParticleEmitterShape.Box
particleEmitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
particleEmitter.Lifetime = NumberRange.new(4, 7)
particleEmitter.Speed = NumberRange.new(0.5, 2)
particleEmitter.SpreadAngle = Vector2.new(180, 180)
particleEmitter.Drag = 0.5
particleEmitter.Rotation = NumberRange.new(0, 360)
particleEmitter.RotSpeed = NumberRange.new(-30, 30)
particleEmitter.LightEmission = 1
particleEmitter.LightInfluence = 0
particleEmitter.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.15, 0.2),
	NumberSequenceKeypoint.new(0.85, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})
particleEmitter.Size = NumberSequence.new(PARTICLES.Size)
particleEmitter.Rate = PARTICLES.Rate
particleEmitter.Enabled = false
particleEmitter.Parent = particlePart

local PARTICLE_STYLE_SETTINGS = {
	-- Texture — картинка частицы. Встроенные текстуры Roblox; можно заменить на свою "rbxassetid://...".
	["Искры"] = {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Acceleration = Vector3.new(0, 0, 0),
		Speed = NumberRange.new(0.5, 2),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(2, 4),
		RotSpeed = NumberRange.new(-90, 90),
		LightEmission = 1,
		SizeScale = 1,
		MinTransparency = 0.05,
	},
	["Снег"] = {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Acceleration = Vector3.new(0, -4, 0),
		Speed = NumberRange.new(0.2, 0.8),
		SpreadAngle = Vector2.new(25, 25),
		Lifetime = NumberRange.new(5, 9),
		RotSpeed = NumberRange.new(-25, 25),
		LightEmission = 0.2,
		SizeScale = 1.2,
		MinTransparency = 0.1,
	},
	["Огоньки"] = {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Acceleration = Vector3.new(0, 3, 0),
		Speed = NumberRange.new(0.3, 1),
		SpreadAngle = Vector2.new(30, 30),
		Lifetime = NumberRange.new(3, 6),
		RotSpeed = NumberRange.new(-40, 40),
		LightEmission = 1,
		SizeScale = 1.6,
		MinTransparency = 0.15,
	},
	["Дым"] = {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Acceleration = Vector3.new(0, 0.5, 0),
		Speed = NumberRange.new(0.1, 0.4),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(6, 10),
		RotSpeed = NumberRange.new(-10, 10),
		LightEmission = 0,
		SizeScale = 6,
		MinTransparency = 0.7,
	},
}

local lastParticleSize = nil -- пересчитывается при первом кадре

RunService.RenderStepped:Connect(function()
	particleEmitter.Enabled = PARTICLES.Enabled
	if not PARTICLES.Enabled then
		return
	end

	local camera = workspace.CurrentCamera
	if camera then
		particlePart.CFrame = CFrame.new(camera.CFrame.Position)
	end

	local range = PARTICLES.Range
	particlePart.Size = Vector3.new(range, range / 2, range)
	particleEmitter.Rate = PARTICLES.Rate

	local settings = PARTICLE_STYLE_SETTINGS[PARTICLES.Style] or PARTICLE_STYLE_SETTINGS["Искры"]

	local targetSize = PARTICLES.Size * settings.SizeScale
	if targetSize ~= lastParticleSize then
		lastParticleSize = targetSize
		particleEmitter.Size = NumberSequence.new(targetSize)
	end

	if particleEmitter.Texture ~= settings.Texture then
		particleEmitter.Texture = settings.Texture
	end
	particleEmitter.Acceleration = settings.Acceleration
	particleEmitter.Speed = settings.Speed
	particleEmitter.SpreadAngle = settings.SpreadAngle
	particleEmitter.Lifetime = settings.Lifetime
	particleEmitter.RotSpeed = settings.RotSpeed
	-- со свечением частицы светятся сами, без него — освещаются как обычные предметы
	particleEmitter.LightEmission = PARTICLES.Glow and math.max(settings.LightEmission, 0.7) or 0
	particleEmitter.LightInfluence = PARTICLES.Glow and 0 or 1
	particleEmitter.Brightness = PARTICLES.Glow and math.max(PARTICLES.GlowStrength, 0.1) or 1
	particleEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, settings.MinTransparency),
		NumberSequenceKeypoint.new(0.85, settings.MinTransparency),
		NumberSequenceKeypoint.new(1, 1),
	})

	particleEmitter.Color = PARTICLES.Rainbow and rainbowSequence(os.clock() * 0.3)
		or ColorSequence.new(PARTICLES.Color)
end)

--------------------------------------------------------------------
-- Туман (меняется только у вас на экране)
--------------------------------------------------------------------
local Lighting = game:GetService("Lighting")

local FOG = {
	Enabled = false,
	Rainbow = false,
	Start = 0,    -- с какого расстояния начинается туман
	End = 200,    -- на каком расстоянии туман полностью скрывает мир
	Color = Color3.fromRGB(180, 190, 210), -- цвет тумана (выбирается в меню)
	Glow = false,       -- свечение всей картинки (Bloom), пока туман включён
	GlowStrength = 2,   -- сила свечения (0-5)
}

local fogOriginal = nil -- сохранённые настройки игры, чтобы вернуть их при выключении

-- локальный Bloom: светлые и неоновые объекты начинают «светиться ореолом»
local fogBloom = Instance.new("BloomEffect")
fogBloom.Name = "JustVisualsBloom"
fogBloom.Size = 30
fogBloom.Threshold = 0.85
fogBloom.Enabled = false
fogBloom.Parent = Lighting

RunService.RenderStepped:Connect(function()
	if FOG.Enabled then
		if not fogOriginal then
			fogOriginal = {
				start = Lighting.FogStart,
				finish = Lighting.FogEnd,
				color = Lighting.FogColor,
				atmosphere = Lighting:FindFirstChildOfClass("Atmosphere"),
			}
			-- Atmosphere перекрывает обычный туман Lighting, поэтому на время убираем её (только у вас)
			if fogOriginal.atmosphere then
				fogOriginal.atmosphere.Parent = nil
			end
		end

		Lighting.FogStart = FOG.Start
		Lighting.FogEnd = math.max(FOG.End, FOG.Start + 1)
		Lighting.FogColor = FOG.Rainbow and Color3.fromHSV((os.clock() * 0.1) % 1, 0.5, 1)
			or FOG.Color

		fogBloom.Enabled = FOG.Glow and FOG.GlowStrength > 0
		fogBloom.Intensity = FOG.GlowStrength * 0.3
		return
	end

	fogBloom.Enabled = false
	if fogOriginal then
		Lighting.FogStart = fogOriginal.start
		Lighting.FogEnd = fogOriginal.finish
		Lighting.FogColor = fogOriginal.color
		if fogOriginal.atmosphere then
			if fogOriginal.atmosphere:GetAttribute("JustVisualsActive") ~= false then
				fogOriginal.atmosphere.Parent = Lighting
			end
		end
		fogOriginal = nil
	end
end)

--------------------------------------------------------------------
-- Jump Circle: расходящийся круг на земле при прыжке / приземлении (виден только вам)
--------------------------------------------------------------------
local JUMP_CIRCLE = {
	Enabled = false,
	Rainbow = false,
	Color = Color3.fromRGB(255, 255, 255),
	Trigger = "Приземление", -- "Приземление", "Прыжок" или "Оба"
	Radius = 4,        -- до какого радиуса расходится круг (studs)
	Duration = 0.6,    -- сколько секунд живёт круг
	Thickness = 0.2,   -- толщина кольца
	Glow = true,       -- свечение: неоновое кольцо + вспышка света
	GlowStrength = 2,  -- сила свечения (0-5)
}

local JUMP_CIRCLE_TRIGGERS = { "Приземление", "Прыжок", "Оба" }
local JUMP_CIRCLE_SEGMENTS = 32

local circlesFolder = Instance.new("Folder")
circlesFolder.Name = "JumpCircles"
circlesFolder.Parent = workspace

local activeCircles = {}

local function spawnJumpCircle(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end

	-- ищем землю под ногами
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, circlesFolder }
	local result = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)
	local groundY = result and result.Position.Y
		or (root.Position.Y - humanoid.HipHeight - root.Size.Y / 2)
	local center = Vector3.new(root.Position.X, groundY + 0.05, root.Position.Z)

	local color = JUMP_CIRCLE.Color
	local parts = {}
	for i = 1, JUMP_CIRCLE_SEGMENTS do
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = JUMP_CIRCLE.Glow and Enum.Material.Neon or Enum.Material.SmoothPlastic
		part.Color = color
		part.Size = Vector3.new(0.1, 0.05, 0.1)
		part.CFrame = CFrame.new(center)
		part.Parent = circlesFolder
		parts[i] = part
	end

	-- вспышка света в центре круга (гаснет вместе с ним)
	local light = nil
	if JUMP_CIRCLE.Glow and JUMP_CIRCLE.GlowStrength > 0 then
		local lightPart = Instance.new("Part")
		lightPart.Anchored = true
		lightPart.CanCollide = false
		lightPart.CanQuery = false
		lightPart.CanTouch = false
		lightPart.Transparency = 1
		lightPart.Size = Vector3.new(0.1, 0.1, 0.1)
		lightPart.CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0))
		lightPart.Parent = circlesFolder
		table.insert(parts, lightPart)

		light = Instance.new("PointLight")
		light.Shadows = false
		light.Color = color
		light.Parent = lightPart
	end

	table.insert(activeCircles, {
		parts = parts,
		light = light,
		glowStrength = JUMP_CIRCLE.GlowStrength,
		center = center,
		start = os.clock(),
		radius = JUMP_CIRCLE.Radius,
		duration = JUMP_CIRCLE.Duration,
		thickness = JUMP_CIRCLE.Thickness,
		rainbow = JUMP_CIRCLE.Rainbow,
	})
end

local lastJumpCircle = 0

local function hookJumpCircle(character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end

	humanoid.StateChanged:Connect(function(_, newState)
		if not JUMP_CIRCLE.Enabled then
			return
		end

		local trigger = JUMP_CIRCLE.Trigger
		local onLand = newState == Enum.HumanoidStateType.Landed and trigger ~= "Прыжок"
		local onJump = newState == Enum.HumanoidStateType.Jumping and trigger ~= "Приземление"
		if not (onLand or onJump) then
			return
		end

		-- защита от двойного срабатывания за один кадр
		if os.clock() - lastJumpCircle < 0.1 then
			return
		end
		lastJumpCircle = os.clock()

		spawnJumpCircle(character)
	end)
end

localPlayer.CharacterAdded:Connect(hookJumpCircle)
if localPlayer.Character then
	task.spawn(hookJumpCircle, localPlayer.Character)
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()

	for index = #activeCircles, 1, -1 do
		local circle = activeCircles[index]
		local t = (now - circle.start) / circle.duration

		if t >= 1 then
			for _, part in ipairs(circle.parts) do
				part:Destroy()
			end
			table.remove(activeCircles, index)
		else
			local eased = 1 - (1 - t) ^ 3 -- быстро расходится, плавно замедляется
			local radius = 0.3 + (circle.radius - 0.3) * eased
			local segmentLength = 2 * math.pi * radius / JUMP_CIRCLE_SEGMENTS * 1.1
			local color = circle.rainbow and Color3.fromHSV((now * 0.5) % 1, 0.8, 1) or nil

			if circle.light then
				circle.light.Brightness = circle.glowStrength * (1 - t)
				circle.light.Range = 2 + radius * 1.5
				if color then
					circle.light.Color = color
				end
			end

			for k = 1, JUMP_CIRCLE_SEGMENTS do
				local part = circle.parts[k]
				local angle = (k - 1) / JUMP_CIRCLE_SEGMENTS * math.pi * 2
				part.Size = Vector3.new(circle.thickness, 0.05, segmentLength)
				part.CFrame = CFrame.new(circle.center) * CFrame.Angles(0, angle, 0) * CFrame.new(radius, 0, 0)
				part.Transparency = t
				if color then
					part.Color = color
				end
			end
		end
	end
end)

--------------------------------------------------------------------
-- Custom Sky: свой вид неба и освещения (раздел Visuals, меняется только у вас)
--------------------------------------------------------------------
local SKY, SKY_PRESET_ORDER
do
	SKY = {
		Enabled = false,
		Preset = "Закат",
		Clouds = true,       -- облака
		MovingSun = false,   -- солнце/луна движутся по небу
		SunSpeed = 2,        -- сколько игровых часов проходит за минуту
	}

	SKY_PRESET_ORDER = { "День", "Рассвет", "Закат", "Ночь", "Космос", "Фэнтези", "Шторм" }

	local rgb = Color3.fromRGB
	local PRESETS = {
		["День"] = {
			Lighting = { ClockTime = 13, Brightness = 3, Ambient = rgb(120, 125, 140), OutdoorAmbient = rgb(140, 145, 160), ColorShift_Top = rgb(255, 255, 255) },
			Atmosphere = { Density = 0.3, Offset = 0.25, Color = rgb(199, 215, 255), Decay = rgb(106, 112, 125), Glare = 0, Haze = 1 },
			Sky = { StarCount = 0, SunAngularSize = 21, MoonAngularSize = 11 },
			Clouds = { Cover = 0.5, Density = 0.6, Color = rgb(255, 255, 255) },
		},
		["Рассвет"] = {
			Lighting = { ClockTime = 6.4, Brightness = 2, Ambient = rgb(110, 90, 110), OutdoorAmbient = rgb(160, 120, 120), ColorShift_Top = rgb(255, 190, 150) },
			Atmosphere = { Density = 0.35, Offset = 0.4, Color = rgb(255, 190, 170), Decay = rgb(130, 90, 120), Glare = 0.4, Haze = 1.8 },
			Sky = { StarCount = 300, SunAngularSize = 26, MoonAngularSize = 11 },
			Clouds = { Cover = 0.55, Density = 0.6, Color = rgb(255, 200, 190) },
		},
		["Закат"] = {
			Lighting = { ClockTime = 18.2, Brightness = 2, Ambient = rgb(90, 70, 90), OutdoorAmbient = rgb(150, 100, 90), ColorShift_Top = rgb(255, 170, 100) },
			Atmosphere = { Density = 0.4, Offset = 0.5, Color = rgb(255, 170, 120), Decay = rgb(120, 60, 80), Glare = 0.6, Haze = 2.2 },
			Sky = { StarCount = 800, SunAngularSize = 30, MoonAngularSize = 11 },
			Clouds = { Cover = 0.6, Density = 0.7, Color = rgb(255, 170, 130) },
		},
		["Ночь"] = {
			Lighting = { ClockTime = 0, Brightness = 0.5, Ambient = rgb(25, 30, 55), OutdoorAmbient = rgb(35, 45, 80), ColorShift_Top = rgb(60, 80, 160) },
			Atmosphere = { Density = 0.25, Offset = 0, Color = rgb(20, 25, 60), Decay = rgb(10, 10, 30), Glare = 0, Haze = 0.5 },
			Sky = { StarCount = 5000, SunAngularSize = 21, MoonAngularSize = 20 },
			Clouds = { Cover = 0.3, Density = 0.4, Color = rgb(60, 70, 110) },
		},
		["Космос"] = {
			Lighting = { ClockTime = 0, Brightness = 0.3, Ambient = rgb(40, 30, 70), OutdoorAmbient = rgb(50, 40, 90), ColorShift_Top = rgb(120, 90, 255) },
			Atmosphere = { Density = 0.05, Offset = 0, Color = rgb(10, 5, 30), Decay = rgb(40, 20, 90), Glare = 0, Haze = 0 },
			Sky = { StarCount = 10000, SunAngularSize = 21, MoonAngularSize = 40 },
			Clouds = { Cover = 0, Density = 0, Color = rgb(255, 255, 255) },
		},
		["Фэнтези"] = {
			Lighting = { ClockTime = 20, Brightness = 1.5, Ambient = rgb(80, 60, 120), OutdoorAmbient = rgb(120, 80, 170), ColorShift_Top = rgb(200, 120, 255) },
			Atmosphere = { Density = 0.5, Offset = 0.3, Color = rgb(190, 120, 255), Decay = rgb(60, 200, 220), Glare = 0.3, Haze = 2.8 },
			Sky = { StarCount = 3000, SunAngularSize = 15, MoonAngularSize = 35 },
			Clouds = { Cover = 0.7, Density = 0.8, Color = rgb(220, 160, 255) },
		},
		["Шторм"] = {
			Lighting = { ClockTime = 14, Brightness = 1, Ambient = rgb(80, 85, 95), OutdoorAmbient = rgb(90, 95, 105), ColorShift_Top = rgb(160, 170, 190) },
			Atmosphere = { Density = 0.55, Offset = 0.1, Color = rgb(120, 125, 135), Decay = rgb(70, 72, 80), Glare = 0, Haze = 3 },
			Sky = { StarCount = 0, SunAngularSize = 21, MoonAngularSize = 11 },
			Clouds = { Cover = 0.9, Density = 0.95, Color = rgb(110, 112, 120) },
		},
	}

	local LIGHTING_PROPS = { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ColorShift_Top" }
	local CLOUD_PROPS = { "Cover", "Density", "Color" }

	local original = nil      -- настройки игры, чтобы вернуть их при выключении
	local mySky, myAtmosphere, myClouds = nil, nil, nil
	local timeOffset = 0
	local lastPreset = nil

	local function enableSky()
		original = { lighting = {}, clouds = nil }
		for _, property in ipairs(LIGHTING_PROPS) do
			original.lighting[property] = Lighting[property]
		end

		-- свой Sky и Atmosphere; игровые временно убираем (только у вас)
		original.sky = Lighting:FindFirstChildOfClass("Sky")
		if original.sky then
			original.sky.Parent = nil
		end
		original.atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if original.atmosphere then
			original.atmosphere.Parent = nil
		end

		mySky = Instance.new("Sky")
		mySky.Name = "JustVisualsSky"
		mySky.CelestialBodiesShown = true
		mySky.Parent = Lighting

		myAtmosphere = Instance.new("Atmosphere")
		myAtmosphere.Name = "JustVisualsAtmosphere"
		myAtmosphere:SetAttribute("JustVisualsActive", true)
		myAtmosphere.Parent = Lighting

		local terrainClouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
		if terrainClouds then
			original.clouds = { object = terrainClouds, enabled = terrainClouds.Enabled }
			for _, property in ipairs(CLOUD_PROPS) do
				original.clouds[property] = terrainClouds[property]
			end
			myClouds = terrainClouds
		else
			myClouds = Instance.new("Clouds")
			myClouds.Name = "JustVisualsClouds"
			myClouds.Parent = workspace.Terrain
		end

		timeOffset = 0
	end

	local function disableSky()
		for property, value in pairs(original.lighting) do
			Lighting[property] = value
		end

		mySky:Destroy()
		mySky = nil
		if original.sky then
			original.sky.Parent = Lighting
		end

		-- туман мог временно спрятать нашу атмосферу — помечаем её неактивной, чтобы он её не вернул
		myAtmosphere:SetAttribute("JustVisualsActive", false)
		myAtmosphere.Parent = nil
		myAtmosphere = nil
		if original.atmosphere then
			original.atmosphere.Parent = Lighting
		end

		if original.clouds then
			local clouds = original.clouds.object
			clouds.Enabled = original.clouds.enabled
			for _, property in ipairs(CLOUD_PROPS) do
				clouds[property] = original.clouds[property]
			end
		elseif myClouds then
			myClouds:Destroy()
		end
		myClouds = nil
		original = nil
	end

	RunService.RenderStepped:Connect(function(dt)
		if not SKY.Enabled then
			if original then
				disableSky()
			end
			return
		end
		if not original then
			enableSky()
		end

		local preset = PRESETS[SKY.Preset] or PRESETS["Закат"]
		if SKY.Preset ~= lastPreset then
			lastPreset = SKY.Preset
			timeOffset = 0
		end

		for property, value in pairs(preset.Lighting) do
			Lighting[property] = value
		end
		if SKY.MovingSun then
			timeOffset += dt * SKY.SunSpeed / 60
			Lighting.ClockTime = (preset.Lighting.ClockTime + timeOffset) % 24
		end

		for property, value in pairs(preset.Atmosphere) do
			myAtmosphere[property] = value
		end
		for property, value in pairs(preset.Sky) do
			mySky[property] = value
		end

		myClouds.Enabled = SKY.Clouds and preset.Clouds.Cover > 0
		for property, value in pairs(preset.Clouds) do
			myClouds[property] = value
		end
	end)
end

--------------------------------------------------------------------
-- Меню
--------------------------------------------------------------------
-- Оформление в стиле «стеклянной» тёмно-бордовой панели:
-- сверху логотип, поиск и профиль; слева дерево разделов; справа сетка карточек-модулей в две колонки.
-- Клик по карточке включает/выключает функцию, «⋮» открывает её настройки.

local C = {
	bgTop = Color3.fromRGB(92, 32, 44),
	bgBottom = Color3.fromRGB(38, 14, 20),
	panel = Color3.fromRGB(30, 11, 16),
	card = Color3.fromRGB(80, 30, 40),
	cardHover = Color3.fromRGB(98, 38, 50),
	inner = Color3.fromRGB(52, 19, 27),
	accent = Color3.fromRGB(250, 90, 106),
	accentDim = Color3.fromRGB(140, 56, 70),
	off = Color3.fromRGB(104, 76, 82),
	text = Color3.fromRGB(255, 250, 251),
	sub = Color3.fromRGB(226, 204, 209),
	line = Color3.fromRGB(160, 88, 100),
}

-- Внешний вид меню (раздел Themes), сохраняется в конфиги
local MENU_STYLE = {
	Theme = "Бордовый",
	Blur = true, -- размытие мира за открытым меню
}

local function new(className, props)
	local obj = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			obj[key] = value
		end
	end
	if props.Parent then
		obj.Parent = props.Parent
	end
	return obj
end

local function round(obj, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = obj })
end

local function outline(obj, color, transparency)
	return new("UIStroke", {
		Color = color,
		Transparency = transparency,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = obj,
	})
end

-- Иконки из простых фигур (без картинок). Возвращает функцию, которая перекрашивает иконку.
local function drawIcon(parent, kind, size)
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local fills, strokes = {}, {}
	local full = UDim.new(1, 0)
	local s = size
	local thin = math.max(2, math.floor(s * 0.16 + 0.5))

	local function fill(dx, dy, w, h, radius, rotation)
		local part = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, dx, 0.5, dy),
			Size = UDim2.fromOffset(w, h),
			BorderSizePixel = 0,
			Rotation = rotation or 0,
			Parent = holder,
		})
		if radius then
			new("UICorner", { CornerRadius = radius, Parent = part })
		end
		table.insert(fills, part)
	end

	local function ring(w)
		local part = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(w, w),
			BackgroundTransparency = 1,
			Parent = holder,
		})
		new("UICorner", { CornerRadius = full, Parent = part })
		table.insert(strokes, new("UIStroke", { Thickness = math.max(1, thin - 1), Parent = part }))
	end

	if kind == "eye" then
		ring(s * 0.85)
		fill(0, 0, s * 0.34, s * 0.34, full)
	elseif kind == "ring" then
		ring(s * 0.8)
	elseif kind == "diamond" then
		fill(0, 0, s * 0.62, s * 0.62, UDim.new(0, 2), 45)
	elseif kind == "dots" then
		for _, d in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			fill(d[1] * s * 0.22, d[2] * s * 0.22, s * 0.32, s * 0.32, full)
		end
	elseif kind == "bars" then
		for i = -1, 1 do
			fill(0, i * s * 0.3, s * 0.85, thin, full)
		end
	elseif kind == "plus" then
		fill(0, 0, s * 0.85, thin, full)
		fill(0, 0, thin, s * 0.85, full)
	elseif kind == "x" then
		fill(0, 0, s * 0.85, thin, full, 45)
		fill(0, 0, s * 0.85, thin, full, -45)
	elseif kind == "kebab" then -- три точки вертикально (меню карточки)
		for i = -1, 1 do
			fill(0, i * s * 0.32, thin + 1, thin + 1, full)
		end
	elseif kind == "search" then -- лупа
		local lens = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, -s * 0.1, 0.5, -s * 0.1),
			Size = UDim2.fromOffset(s * 0.58, s * 0.58),
			BackgroundTransparency = 1,
			Parent = holder,
		})
		new("UICorner", { CornerRadius = full, Parent = lens })
		table.insert(strokes, new("UIStroke", { Thickness = math.max(1, thin - 1), Parent = lens }))
		fill(s * 0.25, s * 0.25, s * 0.34, thin, full, 45)
	elseif kind == "chevron" then -- «v»; поворачивайте holder, чтобы получить < или >
		fill(-s * 0.16, 0, s * 0.5, thin, full, 45)
		fill(s * 0.16, 0, s * 0.5, thin, full, -45)
	elseif kind == "square" then -- пустой квадрат (бокс)
		local square = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(s * 0.62, s * 0.8),
			BackgroundTransparency = 1,
			Parent = holder,
		})
		table.insert(strokes, new("UIStroke", { Thickness = math.max(1, thin - 1), Parent = square }))
	elseif kind == "tracer" then -- линия снизу к точке
		fill(0, s * 0.05, s * 0.75, thin, full, -60)
		fill(s * 0.2, -s * 0.3, thin + 2, thin + 2, full)
	elseif kind == "palette" then
		fill(0, -s * 0.22, s * 0.36, s * 0.36, full)
		fill(-s * 0.22, s * 0.16, s * 0.36, s * 0.36, full)
		fill(s * 0.22, s * 0.16, s * 0.36, s * 0.36, full)
	else -- "dot"
		fill(0, 0, s * 0.5, s * 0.5, full)
	end

	return function(color)
		for _, part in ipairs(fills) do
			part.BackgroundColor3 = color
		end
		for _, stroke in ipairs(strokes) do
			stroke.Color = color
		end
	end
end

-- Логотип: тёмный скруглённый квадрат, внутри белый ромб, разрезанный тонкими щелями на 4 части.
local LOGO_BG = Color3.fromRGB(14, 8, 10)
local LOGO_MARK = Color3.fromRGB(245, 240, 241)

local function drawLogoMark(square, size)
	local markSize = math.floor(size * 0.5 + 0.5)
	local gap = math.max(1, math.floor(size * 0.04 + 0.5))
	local tile = (markSize - gap) / 2

	local mark = new("Frame", {
		Name = "LogoMark",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(markSize, markSize),
		Rotation = 45,
		BackgroundTransparency = 1,
		Parent = square,
	})

	for row = 0, 1 do
		for column = 0, 1 do
			local piece = new("Frame", {
				Position = UDim2.fromOffset(column * (tile + gap), row * (tile + gap)),
				Size = UDim2.fromOffset(tile, tile),
				BackgroundColor3 = LOGO_MARK,
				BorderSizePixel = 0,
				Parent = mark,
			})
			round(piece, math.max(1, math.floor(size * 0.02)))
		end
	end

	return mark
end

--------------------------------------------------------------------
-- Каркас окна
--------------------------------------------------------------------
local screenGui = new("ScreenGui", {
	Name = "ESP_Menu",
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, -- содержимое окна всегда поверх самого окна
	ResetOnSpawn = false,
	DisplayOrder = 100,
	Parent = playerGui,
})

local frame = new("Frame", {
	Name = "Window",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), -- по центру экрана
	Size = UDim2.fromOffset(600, 400),
	BackgroundTransparency = 1, -- сам контейнер прозрачный, фон — отдельным слоем ниже
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Parent = screenGui,
})
round(frame, 12)
outline(frame, C.line, 0.35)

-- Фон окна — отдельный слой в самом низу, под всем содержимым.
-- Окно — обычный Frame: цвет фона никак не влияет на текст, карточки и иконки.
local windowBackground = new("Frame", {
	Name = "Background",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.04,
	BorderSizePixel = 0,
	ZIndex = 0,
	Parent = frame,
})
round(windowBackground, 12)
new("UIGradient", {
	Color = ColorSequence.new(C.bgTop, C.bgBottom),
	Rotation = 55,
	Parent = windowBackground,
})

-- Верхняя панель: логотип, поиск, профиль
local topBar = new("Frame", {
	Size = UDim2.new(1, 0, 0, 48),
	BackgroundTransparency = 1,
	Parent = frame,
})

new("Frame", { -- разделитель под верхней панелью
	Position = UDim2.new(0, 0, 1, -1),
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = C.line,
	BackgroundTransparency = 0.6,
	BorderSizePixel = 0,
	Parent = topBar,
})

local logo = new("Frame", {
	Position = UDim2.fromOffset(14, 11),
	Size = UDim2.fromOffset(26, 26),
	BackgroundColor3 = LOGO_BG,
	BorderSizePixel = 0,
	Parent = topBar,
})
round(logo, 6)
outline(logo, C.line, 0.5)
drawLogoMark(logo, 26)

new("TextLabel", {
	Position = UDim2.fromOffset(48, 0),
	Size = UDim2.fromOffset(108, 48),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = C.text,
	Text = "opus client",
	Parent = topBar,
})

local searchBox = new("Frame", {
	Position = UDim2.fromOffset(162, 9),
	Size = UDim2.new(1, -162 - 176, 0, 30),
	BackgroundColor3 = C.panel,
	BackgroundTransparency = 0.3,
	BorderSizePixel = 0,
	Parent = topBar,
})
round(searchBox, 8)
outline(searchBox, C.line, 0.6)

local searchIcon = new("Frame", {
	Position = UDim2.fromOffset(8, 7),
	Size = UDim2.fromOffset(16, 16),
	BackgroundTransparency = 1,
	Parent = searchBox,
})
drawIcon(searchIcon, "search", 14)(C.sub)

local search = new("TextBox", {
	Position = UDim2.fromOffset(28, 0),
	Size = UDim2.new(1, -36, 1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = C.text,
	PlaceholderText = "Поиск...",
	PlaceholderColor3 = C.sub,
	ClearTextOnFocus = false,
	Text = "",
	Parent = searchBox,
})

new("TextLabel", {
	Position = UDim2.new(1, -170, 0, 8),
	Size = UDim2.fromOffset(120, 18),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = C.text,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Text = localPlayer.DisplayName,
	Parent = topBar,
})

new("TextLabel", {
	Position = UDim2.new(1, -170, 0, 25),
	Size = UDim2.fromOffset(120, 14),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = C.sub,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Text = "@" .. localPlayer.Name,
	Parent = topBar,
})

local avatar = new("ImageLabel", {
	Position = UDim2.new(1, -44, 0, 8),
	Size = UDim2.fromOffset(32, 32),
	BackgroundColor3 = C.card,
	BorderSizePixel = 0,
	Parent = topBar,
})
round(avatar, 16)
outline(avatar, C.accent, 0.3)

task.spawn(function()
	local ok, image = pcall(function()
		return Players:GetUserThumbnailAsync(localPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
	end)
	if ok then
		avatar.Image = image
	end
end)

-- Перетаскивание окна за верхнюю панель
local dragging, dragStart, startPos
topBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = frame.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging
		and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		frame.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end
end)

--------------------------------------------------------------------
-- Боковая панель (дерево разделов)
--------------------------------------------------------------------
local sidebar = new("Frame", {
	Position = UDim2.fromOffset(0, 48),
	Size = UDim2.new(0, 150, 1, -48),
	BackgroundColor3 = C.panel,
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	Parent = frame,
})
round(sidebar, 12)

new("Frame", { -- разделитель справа от боковой панели
	Position = UDim2.new(1, -1, 0, 0),
	Size = UDim2.new(0, 1, 1, 0),
	BackgroundColor3 = C.line,
	BackgroundTransparency = 0.6,
	BorderSizePixel = 0,
	Parent = sidebar,
})

local sidebarList = new("Frame", {
	Size = UDim2.new(1, 0, 1, -30),
	BackgroundTransparency = 1,
	Parent = sidebar,
})
new("UIPadding", {
	PaddingTop = UDim.new(0, 10),
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 9),
	Parent = sidebarList,
})
new("UIListLayout", {
	Padding = UDim.new(0, 2),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = sidebarList,
})

new("TextLabel", {
	Position = UDim2.new(0, 0, 1, -28),
	Size = UDim2.new(1, 0, 0, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextColor3 = C.sub,
	Text = "RightControl — скрыть меню",
	Parent = sidebar,
})

-- Группы разделов (как «Modules» и «Server» в примере): заголовок + вложенные пункты с линией дерева
local groups = {}
local groupOrder = 0

local function createGroup(name, iconKind)
	groupOrder += 1

	local header = new("TextButton", {
		LayoutOrder = groupOrder * 2 - 1,
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = C.accentDim,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Parent = sidebarList,
	})
	round(header, 7)

	local iconHolder = new("Frame", {
		Position = UDim2.new(0, 8, 0.5, -9),
		Size = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		Parent = header,
	})
	local setIcon = drawIcon(iconHolder, iconKind, 14)

	local label = new("TextLabel", {
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.new(1, -52, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.sub,
		Text = name,
		Parent = header,
	})

	local arrow = new("Frame", {
		Position = UDim2.new(1, -22, 0.5, -7),
		Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1,
		Parent = header,
	})
	drawIcon(arrow, "chevron", 10)(C.sub)

	local list = new("Frame", {
		LayoutOrder = groupOrder * 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = sidebarList,
	})
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	new("UIPadding", { PaddingBottom = UDim.new(0, 8), Parent = list })

	header.MouseButton1Click:Connect(function()
		list.Visible = not list.Visible
		arrow.Rotation = list.Visible and 0 or -90
	end)
	header.MouseEnter:Connect(function()
		label.TextColor3 = C.text
	end)
	header.MouseLeave:Connect(function()
		label.TextColor3 = groups[name].active and C.text or C.sub
	end)

	groups[name] = { header = header, label = label, setIcon = setIcon, list = list, sections = {}, active = false }
	return groups[name]
end

createGroup("Modules", "diamond")
createGroup("Settings", "plus")

--------------------------------------------------------------------
-- Правая часть: хлебные крошки, сетка карточек и страницы настроек
--------------------------------------------------------------------
local content = new("Frame", {
	Position = UDim2.fromOffset(162, 48),
	Size = UDim2.new(1, -174, 1, -58),
	BackgroundTransparency = 1,
	Parent = frame,
})

local backButton = new("TextButton", {
	Position = UDim2.fromOffset(0, 6),
	Size = UDim2.fromOffset(22, 22),
	BackgroundColor3 = C.card,
	BackgroundTransparency = 0.2,
	AutoButtonColor = true,
	Text = "",
	Visible = false,
	Parent = content,
})
round(backButton, 6)
local backIcon = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(12, 12),
	Rotation = 90, -- «v», повёрнутая на 90°, становится «<»
	BackgroundTransparency = 1,
	Parent = backButton,
})
drawIcon(backIcon, "chevron", 10)(C.text)

local breadcrumb = new("TextLabel", {
	Position = UDim2.fromOffset(2, 6),
	Size = UDim2.new(1, -2, 0, 22),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = C.sub,
	RichText = true,
	Text = "",
	Parent = content,
})

local counterLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -6, 0, 6),
	Size = UDim2.fromOffset(170, 22),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = C.sub,
	RichText = true,
	Text = "",
	Parent = content,
})

local function makeScroller(name)
	local scroller = new("ScrollingFrame", {
		Name = name,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		Parent = content,
	})
	new("UIPadding", {
		PaddingTop = UDim.new(0, 1),
		PaddingLeft = UDim.new(0, 1),
		PaddingRight = UDim.new(0, 7),
		PaddingBottom = UDim.new(0, 2),
		Parent = scroller,
	})
	return scroller
end

local sections = {}      -- [название] = { grid, cards, nav }
local uiRefreshers = {}  -- функции, которые перерисовывают элементы меню по текущим значениям
local sectionOrder = 0
local currentSection = nil
local currentModule = nil -- открытая страница настроек

local function updateCounter()
	local section = sections[currentSection]
	if currentModule or not section or #section.modules == 0 then
		counterLabel.Text = ""
		return
	end
	local on = 0
	for _, def in ipairs(section.modules) do
		if def.source[def.key] then
			on += 1
		end
	end
	counterLabel.Text = string.format('<font color="#FFFAFB"><b>%d</b></font> из %d включено', on, #section.modules)
end

local function crumbs(...)
	local section = sections[currentSection]
	local parts = { section and section.group or "Modules" }
	for _, part in ipairs({ ... }) do
		table.insert(parts, part)
	end
	local last = table.remove(parts)
	local text = table.concat(parts, "  /  ")
	return text .. '  /  <font color="#FFFAFB"><b>' .. last .. "</b></font>"
end

local function showGrid()
	if currentModule then
		currentModule.page.Visible = false
		currentModule = nil
	end
	for name, section in pairs(sections) do
		section.grid.Visible = name == currentSection
	end
	backButton.Visible = false
	breadcrumb.Position = UDim2.fromOffset(2, 6)
	breadcrumb.Text = crumbs(currentSection)
	updateCounter()
end

local function selectSection(name)
	currentSection = name
	for sectionName, section in pairs(sections) do
		local active = sectionName == name
		section.nav.setIcon(active and C.accent or C.sub)
		section.nav.label.TextColor3 = active and C.text or C.sub
		section.nav.label.Font = active and Enum.Font.GothamBold or Enum.Font.Gotham
		section.nav.pill.Visible = active
	end
	for _, group in pairs(groups) do
		group.active = group.sections[name] == true
		group.header.BackgroundTransparency = group.active and 0.35 or 1
		group.label.TextColor3 = group.active and C.text or C.sub
		group.setIcon(group.active and C.accent or C.sub)
	end
	showGrid()
end

local function openSettings(module)
	for _, section in pairs(sections) do
		section.grid.Visible = false
	end
	if currentModule then
		currentModule.page.Visible = false
	end
	currentModule = module
	module.page.Visible = true
	backButton.Visible = true
	breadcrumb.Position = UDim2.fromOffset(30, 6)
	breadcrumb.Text = crumbs(currentSection, module.name)
	updateCounter()
end

backButton.MouseButton1Click:Connect(showGrid)

-- Поиск по названию и описанию карточек текущего раздела
search:GetPropertyChangedSignal("Text"):Connect(function()
	if currentModule then
		showGrid()
	end
	local query = search.Text:lower()
	for _, section in pairs(sections) do
		for _, card in ipairs(section.cards) do
			local haystack = (card.name .. " " .. card.desc):lower()
			card.frame.Visible = query == "" or haystack:find(query, 1, true) ~= nil
		end
	end
end)

local SECTION_ICONS = {
	ESP = "eye",
	Visuals = "diamond",
	Misc = "dots",
	Config = "bars",
	Themes = "palette",
}

local function createSection(name, groupName)
	sectionOrder += 1
	groupName = groupName or "Modules"
	local group = groups[groupName]
	group.sections[name] = true

	local nav = new("TextButton", {
		LayoutOrder = sectionOrder,
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Parent = group.list,
	})

	-- мягкая подложка под активным пунктом
	local pill = new("Frame", {
		Position = UDim2.fromOffset(24, 3),
		Size = UDim2.new(1, -24, 1, -6),
		BackgroundColor3 = C.accentDim,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Visible = false,
		Parent = nav,
	})
	round(pill, 6)

	new("Frame", { -- вертикальная линия дерева
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = C.line,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = nav,
	})

	new("Frame", { -- горизонтальная ветка дерева
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(8, 1),
		BackgroundColor3 = C.line,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = nav,
	})

	local iconHolder = new("Frame", {
		Position = UDim2.new(0, 28, 0.5, -7),
		Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1,
		Parent = nav,
	})
	local setIcon = drawIcon(iconHolder, SECTION_ICONS[name] or "dot", 11)
	setIcon(C.sub)

	local label = new("TextLabel", {
		Position = UDim2.fromOffset(48, 0),
		Size = UDim2.new(1, -48, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.sub,
		Text = name,
		Parent = nav,
	})

	local grid = makeScroller(name .. "_Grid")
	new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -5, 0, 66),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})

	sections[name] = {
		grid = grid,
		cards = {},
		modules = {},
		group = groupName,
		nav = { setIcon = setIcon, label = label, pill = pill },
	}

	nav.MouseEnter:Connect(function()
		if currentSection ~= name then
			label.TextColor3 = C.text
		end
	end)
	nav.MouseLeave:Connect(function()
		if currentSection ~= name then
			label.TextColor3 = C.sub
		end
	end)

	nav.MouseButton1Click:Connect(function()
		selectSection(name)
	end)

	return sections[name]
end

--------------------------------------------------------------------
-- Строки страницы настроек
--------------------------------------------------------------------
-- Звуки при включении/выключении функций (раздел Misc)
local SoundService = game:GetService("SoundService")

local SOUNDS = {
	Enabled = true,
	Style = "Пинг",  -- "Пинг", "Клик" или "Кнопка"
	Volume = 0.5,
	OnPitch = 1.25,  -- высота звука при включении
	OffPitch = 0.85, -- высота звука при выключении
}

local SOUND_STYLES = { "Пинг", "Клик", "Кнопка" }

-- Встроенные звуки Roblox. Можно заменить на свои "rbxassetid://...".
local SOUND_IDS = {
	["Пинг"] = "rbxasset://sounds/electronicpingshort.wav",
	["Клик"] = "rbxasset://sounds/clickfast.wav",
	["Кнопка"] = "rbxasset://sounds/button.wav",
}

local toggleSound = Instance.new("Sound")
toggleSound.Name = "MenuToggleSound"
toggleSound.Parent = SoundService

local function playToggleSound(on)
	if not SOUNDS.Enabled then
		return
	end
	toggleSound.SoundId = SOUND_IDS[SOUNDS.Style] or SOUND_IDS["Пинг"]
	toggleSound.Volume = SOUNDS.Volume
	toggleSound.PlaybackSpeed = on and SOUNDS.OnPitch or SOUNDS.OffPitch
	toggleSound.TimePosition = 0
	toggleSound:Play()
end

local COLOR_PRESETS = {
	Color3.fromRGB(255, 90, 90),    -- красный
	Color3.fromRGB(255, 160, 60),   -- оранжевый
	Color3.fromRGB(255, 230, 90),   -- жёлтый
	Color3.fromRGB(90, 220, 120),   -- зелёный
	Color3.fromRGB(90, 230, 230),   -- голубой
	Color3.fromRGB(90, 170, 255),   -- синий
	Color3.fromRGB(170, 110, 255),  -- фиолетовый
	Color3.fromRGB(255, 120, 200),  -- розовый
	Color3.fromRGB(255, 255, 255),  -- белый
	Color3.fromRGB(180, 190, 210),  -- серо-голубой
	Color3.fromRGB(60, 60, 70),     -- тёмно-серый
	Color3.fromRGB(15, 15, 15),     -- чёрный
}

local function settingRow(page, labelText, height)
	local row = new("Frame", {
		LayoutOrder = #page:GetChildren(),
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = C.card,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Parent = page,
	})
	round(row, 8)
	outline(row, C.line, 0.7)

	new("TextLabel", {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -140, 0, 38),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.text,
		Text = labelText,
		Parent = row,
	})

	return row
end

local function toggleSetting(page, labelText, key, source)
	local row = settingRow(page, labelText, 38)

	local pill = new("Frame", {
		Position = UDim2.new(1, -50, 0.5, -9),
		Size = UDim2.fromOffset(36, 18),
		BackgroundColor3 = C.off,
		BorderSizePixel = 0,
		Parent = row,
	})
	round(pill, 9)

	local knob = new("Frame", {
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = C.text,
		BorderSizePixel = 0,
		Parent = pill,
	})
	round(knob, 7)

	local button = new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Parent = row,
	})

	local function refresh()
		local on = source[key]
		pill.BackgroundColor3 = on and C.accent or C.off
		knob.Position = on and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
	end

	button.MouseButton1Click:Connect(function()
		source[key] = not source[key]
		refresh()
		playToggleSound(source[key])
	end)
	refresh()
	table.insert(uiRefreshers, refresh)
end

-- Строка с текстовым полем (например, имя питомца)
local function textSetting(page, labelText, key, maxLength, source)
	local row = settingRow(page, labelText, 38)

	local box = new("TextBox", {
		Position = UDim2.new(1, -142, 0.5, -12),
		Size = UDim2.fromOffset(130, 24),
		BackgroundColor3 = C.inner,
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = C.text,
		PlaceholderText = "пусто",
		PlaceholderColor3 = C.sub,
		ClearTextOnFocus = false,
		Text = tostring(source[key]),
		Parent = row,
	})
	round(box, 6)
	outline(box, C.line, 0.6)

	box.FocusLost:Connect(function()
		source[key] = string.sub(box.Text, 1, maxLength)
		box.Text = source[key]
	end)

	table.insert(uiRefreshers, function()
		box.Text = tostring(source[key])
	end)
end

-- Строка с кнопкой-действием (например, «Проверить звук»)
local function actionSetting(page, labelText, buttonText, callback)
	local row = settingRow(page, labelText, 38)

	local button = new("TextButton", {
		Position = UDim2.new(1, -122, 0.5, -12),
		Size = UDim2.fromOffset(110, 24),
		BackgroundColor3 = C.accent,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = C.text,
		Text = buttonText,
		Parent = row,
	})
	round(button, 6)

	button.MouseButton1Click:Connect(callback)
end

local function numberSetting(page, labelText, key, minValue, maxValue, source)
	local row = settingRow(page, labelText, 38)

	local box = new("TextBox", {
		Position = UDim2.new(1, -78, 0.5, -12),
		Size = UDim2.fromOffset(66, 24),
		BackgroundColor3 = C.inner,
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = C.text,
		ClearTextOnFocus = false,
		Text = tostring(source[key]),
		Parent = row,
	})
	round(box, 6)
	outline(box, C.line, 0.6)

	box.FocusLost:Connect(function()
		local value = tonumber(box.Text)
		if value then
			source[key] = math.clamp(value, minValue, maxValue)
		end
		box.Text = tostring(source[key])
	end)

	table.insert(uiRefreshers, function()
		box.Text = tostring(source[key])
	end)
end

local function choiceSetting(page, labelText, key, options, source)
	local row = settingRow(page, labelText, 38)

	local button = new("TextButton", {
		Position = UDim2.new(1, -122, 0.5, -12),
		Size = UDim2.fromOffset(110, 24),
		BackgroundColor3 = C.inner,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = C.text,
		Parent = row,
	})
	round(button, 6)
	outline(button, C.line, 0.6)

	local function refresh()
		button.Text = tostring(source[key]) .. "  >"
	end

	button.MouseButton1Click:Connect(function()
		local index = table.find(options, source[key]) or 1
		source[key] = options[index % #options + 1]
		refresh()
	end)
	refresh()
	table.insert(uiRefreshers, refresh)
end

local function colorSetting(page, labelText, key, source)
	local row = settingRow(page, labelText, 94)

	local grid = new("Frame", {
		Position = UDim2.fromOffset(12, 36),
		Size = UDim2.new(1, -24, 0, 52),
		BackgroundTransparency = 1,
		Parent = row,
	})
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(28, 22),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})

	local swatches = {}
	local function refresh()
		for _, swatch in ipairs(swatches) do
			swatch.stroke.Enabled = source[key] == swatch.color
		end
	end

	for index, color in ipairs(COLOR_PRESETS) do
		local swatch = new("TextButton", {
			LayoutOrder = index,
			AutoButtonColor = false,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Text = "",
			Parent = grid,
		})
		round(swatch, 5)
		local stroke = new("UIStroke", {
			Color = C.text,
			Thickness = 2,
			Enabled = false,
			Parent = swatch,
		})
		swatches[index] = { color = color, stroke = stroke }

		swatch.MouseButton1Click:Connect(function()
			source[key] = color
			refresh()
		end)
	end
	refresh()
	table.insert(uiRefreshers, refresh)
end

--------------------------------------------------------------------
-- Карточка-модуль
--------------------------------------------------------------------
local TweenService = game:GetService("TweenService")

local MODULE_ICONS = {
	["ESP"] = "eye",
	["Подсветка"] = "diamond",
	["Текст над головой"] = "bars",
	["Имена"] = "bars",
	["Дистанция"] = "ring",
	["Здоровье"] = "plus",
	["Союзники"] = "dots",
	["Боксы"] = "square",
	["Трейсеры"] = "tracer",
	["China Hat"] = "diamond",
	["Trail"] = "bars",
	["Jump Circle"] = "ring",
	["Particles"] = "dots",
	["Fog"] = "bars",
	["Custom Sky"] = "ring",
	["Watermark"] = "bars",
	["Custom Cursor"] = "plus",
	["Target ESP"] = "eye",
	["Custom Pet"] = "dot",
	["Hit Effect"] = "x",
	["Toggle Sounds"] = "dots",
	["Размытие фона"] = "ring",
}

local function addModule(section, def)
	-- def = { name, desc, source, key, settings = function(page) ... end }
	local card = new("TextButton", {
		LayoutOrder = #section.cards + 1,
		BackgroundColor3 = C.card,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = section.grid,
	})
	round(card, 8)
	local cardStroke = outline(card, C.line, 0.65)
	local cardScale = new("UIScale", { Parent = card })

	-- плашка с иконкой, как в примере
	local icon = new("Frame", {
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = C.accentDim,
		BorderSizePixel = 0,
		Parent = card,
	})
	round(icon, 6)
	local setIcon = drawIcon(icon, def.icon or MODULE_ICONS[def.name] or "dot", 12)

	local title = new("TextLabel", {
		Position = UDim2.fromOffset(40, 8),
		Size = UDim2.new(1, -70, 0, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = C.text,
		Text = def.name,
		Parent = card,
	})

	new("TextLabel", {
		Position = UDim2.fromOffset(12, 32),
		Size = UDim2.new(1, -24, 0, 28),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = C.sub,
		Text = def.desc,
		Parent = card,
	})

	local module = { name = def.name, page = nil }

	if def.settings then
		local dots = new("TextButton", {
			Position = UDim2.new(1, -28, 0, 6),
			Size = UDim2.fromOffset(22, 22),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 2,
			Parent = card,
		})
		drawIcon(dots, "kebab", 14)(C.sub)

		local page = makeScroller(def.name .. "_Settings")
		new("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = page,
		})
		def.settings(page)
		module.page = page

		dots.MouseButton1Click:Connect(function()
			openSettings(module)
		end)
	end

	local function refresh()
		local on = def.source[def.key]
		icon.BackgroundColor3 = on and C.accent or C.accentDim
		icon.BackgroundTransparency = on and 0 or 0.25
		setIcon(on and C.text or C.sub)
		title.TextColor3 = C.text
		cardStroke.Color = on and C.accent or C.line
		cardStroke.Transparency = on and 0.3 or 0.65
	end

	card.MouseButton1Click:Connect(function()
		def.source[def.key] = not def.source[def.key]
		refresh()
		updateCounter()
		playToggleSound(def.source[def.key])
		if def.onToggle then
			def.onToggle(def.source[def.key])
		end
	end)

	local hoverInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	card.MouseEnter:Connect(function()
		TweenService:Create(card, hoverInfo, { BackgroundColor3 = C.cardHover }):Play()
		TweenService:Create(cardScale, hoverInfo, { Scale = 1.025 }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, hoverInfo, { BackgroundColor3 = C.card }):Play()
		TweenService:Create(cardScale, hoverInfo, { Scale = 1 }):Play()
	end)

	refresh()
	table.insert(uiRefreshers, refresh)
	table.insert(uiRefreshers, updateCounter)
	table.insert(section.modules, def)
	table.insert(section.cards, { frame = card, name = def.name, desc = def.desc })
end

--------------------------------------------------------------------
-- Раздел ESP
--------------------------------------------------------------------
local espSection = createSection("ESP")

addModule(espSection, {
	name = "ESP",
	desc = "Показывает игроков сквозь стены.",
	source = CONFIG,
	key = "Enabled",
	settings = function(page)
		numberSetting(page, "Макс. дистанция", "MaxDistance", 50, 5000, CONFIG)
	end,
})
addModule(espSection, {
	name = "Подсветка",
	desc = "Подсвечивает силуэты игроков.",
	source = CONFIG,
	key = "ShowHighlight",
})
addModule(espSection, {
	name = "Текст над головой",
	desc = "Подпись с информацией над игроком.",
	source = CONFIG,
	key = "ShowLabel",
})
addModule(espSection, {
	name = "Имена",
	desc = "Отображаемое имя игрока в подписи.",
	source = CONFIG,
	key = "ShowNames",
})
addModule(espSection, {
	name = "Дистанция",
	desc = "Расстояние до игрока в studs.",
	source = CONFIG,
	key = "ShowDistance",
})
addModule(espSection, {
	name = "Здоровье",
	desc = "Полоска и число HP над игроком.",
	source = CONFIG,
	key = "ShowHealth",
})
addModule(espSection, {
	name = "Боксы",
	desc = "Рамка вокруг каждого игрока на экране.",
	source = CONFIG,
	key = "ShowBoxes",
	settings = function(page)
		toggleSetting(page, "Заливка", "BoxFill", CONFIG)
		numberSetting(page, "Толщина", "BoxThickness", 1, 5, CONFIG)
	end,
})
addModule(espSection, {
	name = "Трейсеры",
	desc = "Линии от края экрана к игрокам.",
	source = CONFIG,
	key = "ShowTracers",
	settings = function(page)
		choiceSetting(page, "Откуда линии", "TracerOrigin", { "Снизу", "Центр", "Курсор" }, CONFIG)
		numberSetting(page, "Толщина", "TracerThickness", 1, 5, CONFIG)
	end,
})
addModule(espSection, {
	name = "Союзники",
	desc = "Показывать игроков своей команды.",
	source = CONFIG,
	key = "ShowTeammates",
})

--------------------------------------------------------------------
-- Раздел Visuals
--------------------------------------------------------------------
local visualsSection = createSection("Visuals")

addModule(visualsSection, {
	name = "China Hat",
	desc = "Шляпа над головой вашего персонажа.",
	source = HAT,
	key = "Enabled",
	settings = function(page)
		choiceSetting(page, "Форма", "Style", HAT_STYLES, HAT)
		toggleSetting(page, "Радужная", "Rainbow", HAT)
		colorSetting(page, "Цвет", "Color", HAT)
		toggleSetting(page, "Glow", "Glow", HAT)
		numberSetting(page, "Сила свечения", "GlowStrength", 0, 5, HAT)
		numberSetting(page, "Радиус", "Radius", 0.5, 4, HAT)
		numberSetting(page, "Высота", "Height", 0.3, 3, HAT)
		numberSetting(page, "Зазор", "Gap", 0, 2, HAT)
		numberSetting(page, "Прозрачность", "Transparency", 0, 1, HAT)
	end,
})
addModule(visualsSection, {
	name = "Trail",
	desc = "Светящийся след за персонажем.",
	source = TRAIL,
	key = "Enabled",
	settings = function(page)
		choiceSetting(page, "Тип", "Style", TRAIL_STYLES, TRAIL)
		toggleSetting(page, "Радужная", "Rainbow", TRAIL)
		colorSetting(page, "Цвет", "Color", TRAIL)
		toggleSetting(page, "Glow", "Glow", TRAIL)
		numberSetting(page, "Сила свечения", "GlowStrength", 0, 5, TRAIL)
		numberSetting(page, "Время жизни, с", "Lifetime", 0.2, 5, TRAIL)
		numberSetting(page, "Высота", "Height", 0.5, 4, TRAIL)
		numberSetting(page, "Прозрачность", "Transparency", 0, 1, TRAIL)
	end,
})
addModule(visualsSection, {
	name = "Jump Circle",
	desc = "Кольцо на земле при прыжке.",
	source = JUMP_CIRCLE,
	key = "Enabled",
	settings = function(page)
		choiceSetting(page, "Когда появляется", "Trigger", JUMP_CIRCLE_TRIGGERS, JUMP_CIRCLE)
		toggleSetting(page, "Радужный", "Rainbow", JUMP_CIRCLE)
		colorSetting(page, "Цвет", "Color", JUMP_CIRCLE)
		toggleSetting(page, "Glow", "Glow", JUMP_CIRCLE)
		numberSetting(page, "Сила свечения", "GlowStrength", 0, 5, JUMP_CIRCLE)
		numberSetting(page, "Радиус", "Radius", 1, 15, JUMP_CIRCLE)
		numberSetting(page, "Время, с", "Duration", 0.2, 3, JUMP_CIRCLE)
		numberSetting(page, "Толщина", "Thickness", 0.05, 1, JUMP_CIRCLE)
	end,
})
addModule(visualsSection, {
	name = "Particles",
	desc = "Летающие частицы вокруг вас.",
	source = PARTICLES,
	key = "Enabled",
	settings = function(page)
		choiceSetting(page, "Тип", "Style", PARTICLE_STYLES, PARTICLES)
		toggleSetting(page, "Радужные", "Rainbow", PARTICLES)
		colorSetting(page, "Цвет", "Color", PARTICLES)
		toggleSetting(page, "Glow", "Glow", PARTICLES)
		numberSetting(page, "Сила свечения", "GlowStrength", 0, 5, PARTICLES)
		numberSetting(page, "Количество", "Rate", 5, 500, PARTICLES)
		numberSetting(page, "Размер", "Size", 0.1, 2, PARTICLES)
		numberSetting(page, "Область", "Range", 20, 200, PARTICLES)
	end,
})
addModule(visualsSection, {
	name = "Fog",
	desc = "Свой туман и его цвет.",
	source = FOG,
	key = "Enabled",
	settings = function(page)
		toggleSetting(page, "Радужный", "Rainbow", FOG)
		colorSetting(page, "Цвет", "Color", FOG)
		toggleSetting(page, "Glow (Bloom)", "Glow", FOG)
		numberSetting(page, "Сила свечения", "GlowStrength", 0, 5, FOG)
		numberSetting(page, "Начало", "Start", 0, 2000, FOG)
		numberSetting(page, "Конец", "End", 10, 5000, FOG)
	end,
})

addModule(visualsSection, {
	name = "Custom Sky",
	desc = "Свой вид неба и освещения.",
	source = SKY,
	key = "Enabled",
	settings = function(page)
		choiceSetting(page, "Небо", "Preset", SKY_PRESET_ORDER, SKY)
		toggleSetting(page, "Облака", "Clouds", SKY)
		toggleSetting(page, "Движение солнца", "MovingSun", SKY)
		numberSetting(page, "Скорость (часов в минуту)", "SunSpeed", 0.1, 60, SKY)
	end,
})

--------------------------------------------------------------------
-- Watermark: логотип, FPS, пинг и время на экране (раздел Misc)
--------------------------------------------------------------------
local WATERMARK, WATERMARK_POSITIONS
do
	WATERMARK = {
		Enabled = true,
		ShowLogo = true,
		ShowFPS = true,
		ShowPing = true,
		ShowTime = true,
		ShowSeconds = false,
		Position = "Слева сверху",
	}

	WATERMARK_POSITIONS = { "Слева сверху", "Справа сверху", "Слева снизу", "Справа снизу" }
	local WATERMARK_ANCHORS = {
		["Слева сверху"] = { Vector2.new(0, 0), UDim2.new(0, 12, 0, 12) },
		["Справа сверху"] = { Vector2.new(1, 0), UDim2.new(1, -12, 0, 12) },
		["Слева снизу"] = { Vector2.new(0, 1), UDim2.new(0, 12, 1, -12) },
		["Справа снизу"] = { Vector2.new(1, 1), UDim2.new(1, -12, 1, -12) },
	}

	local watermarkGui = new("ScreenGui", {
		Name = "JustVisuals_Watermark",
		ResetOnSpawn = false,
		DisplayOrder = 90,
		Parent = playerGui,
	})

	local watermarkBar = new("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 28),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Parent = watermarkGui,
	})
	round(watermarkBar, 8)
	outline(watermarkBar, C.line, 0.35)
	new("UIGradient", {
		Color = ColorSequence.new(C.bgTop, C.bgBottom),
		Rotation = 20,
		Parent = watermarkBar,
	})
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 10),
		Parent = watermarkBar,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = watermarkBar,
	})

	-- Один элемент полоски: разделитель слева, значение и подпись
	local function watermarkItem(order)
		local holder = new("Frame", {
			LayoutOrder = order,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundTransparency = 1,
			Parent = watermarkBar,
		})
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = holder,
		})

		local divider = new("Frame", {
			LayoutOrder = 0,
			Size = UDim2.fromOffset(1, 14),
			BackgroundColor3 = C.line,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			Parent = holder,
		})

		local value = new("TextLabel", {
			LayoutOrder = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = C.text,
			RichText = true,
			Text = "",
			Parent = holder,
		})

		return { holder = holder, divider = divider, value = value }
	end

	-- логотип
	local logoItem = watermarkItem(1)
	logoItem.divider:Destroy()
	logoItem.divider = nil
	local logoSquare = new("Frame", {
		LayoutOrder = 0,
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = LOGO_BG,
		BorderSizePixel = 0,
		Parent = logoItem.holder,
	})
	round(logoSquare, 4)
	drawLogoMark(logoSquare, 18)
	logoItem.value.Font = Enum.Font.GothamBlack
	logoItem.value.Text = "opus client"

	local fpsItem = watermarkItem(2)
	local pingItem = watermarkItem(3)
	local timeItem = watermarkItem(4)

	local watermarkItems = {
		{ item = logoItem, key = "ShowLogo" },
		{ item = fpsItem, key = "ShowFPS" },
		{ item = pingItem, key = "ShowPing" },
		{ item = timeItem, key = "ShowTime" },
	}

	local function subText(text)
		return '<font color="#E2CCD1" size="11">' .. text .. "</font>"
	end

	local function speedColor(good, value, okLimit, badLimit, higherIsBetter)
		local isGood = higherIsBetter and value >= okLimit or (not higherIsBetter and value <= okLimit)
		local isBad = higherIsBetter and value < badLimit or (not higherIsBetter and value > badLimit)
		if isGood then
			return "#7EE2A0"
		elseif isBad then
			return "#FF6B7A"
		end
		return "#FFD27A"
	end

	local frameCount = 0
	local fpsTimer = 0
	local currentFps = 0

	RunService.RenderStepped:Connect(function(dt)
		frameCount += 1
		fpsTimer += dt
		if fpsTimer < 0.5 then
			return
		end
		currentFps = math.floor(frameCount / fpsTimer + 0.5)
		frameCount = 0
		fpsTimer = 0

		watermarkGui.Enabled = WATERMARK.Enabled
		if not WATERMARK.Enabled then
			return
		end

		-- положение на экране
		local anchor = WATERMARK_ANCHORS[WATERMARK.Position] or WATERMARK_ANCHORS["Слева сверху"]
		watermarkBar.AnchorPoint = anchor[1]
		watermarkBar.Position = anchor[2]

		-- видимость элементов и разделителей (у первого видимого разделителя нет)
		local firstVisible = true
		for _, entry in ipairs(watermarkItems) do
			local shown = WATERMARK[entry.key]
			entry.item.holder.Visible = shown
			if shown then
				if entry.item.divider then
					entry.item.divider.Visible = not firstVisible
				end
				firstVisible = false
			end
		end

		-- FPS
		fpsItem.value.Text = string.format('<font color="%s">%d</font> %s',
			speedColor(nil, currentFps, 50, 30, true), currentFps, subText("fps"))

		-- пинг (время туда и обратно до сервера)
		local ok, ping = pcall(function()
			return localPlayer:GetNetworkPing()
		end)
		local pingMs = ok and math.floor(ping * 1000 + 0.5) or 0
		pingItem.value.Text = string.format('<font color="%s">%d</font> %s',
			speedColor(nil, pingMs, 80, 180, false), pingMs, subText("ms"))

		-- время
		timeItem.value.Text = os.date(WATERMARK.ShowSeconds and "%H:%M:%S" or "%H:%M")
	end)
end

--------------------------------------------------------------------
-- Кастомный курсор (раздел Misc)
--------------------------------------------------------------------
local CURSOR, CURSOR_STYLES
do
	CURSOR = {
		Enabled = false,
		Style = "Крестик", -- "Точка", "Крестик", "Круг" или "Ромб"
		Rainbow = false,
		Color = Color3.fromRGB(255, 90, 90),
		Size = 18,          -- размер курсора в пикселях
		Thickness = 2,      -- толщина линий
		Outline = true,     -- тёмная обводка, чтобы курсор был виден на любом фоне
		Spin = false,       -- медленное вращение
		Transparency = 0,
	}

	CURSOR_STYLES = { "Точка", "Крестик", "Круг", "Ромб" }

	local cursorGui = new("ScreenGui", {
		Name = "JustVisuals_Cursor",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 500, -- поверх меню и заставки
		Enabled = false,
		Parent = playerGui,
	})

	local cursorRoot = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = cursorGui,
	})

	local cursorShapes = {} -- { object, stroke (для контурных фигур) }
	local cursorBuiltFor = nil
	local cursorHidDefault = false

	local function cursorFill(position, size, circle)
		local part = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = size,
			BorderSizePixel = 0,
			Parent = cursorRoot,
		})
		if circle then
			new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = part })
		end
		if CURSOR.Outline then
			new("UIStroke", {
				Color = Color3.fromRGB(0, 0, 0),
				Transparency = 0.35,
				Thickness = 1,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Parent = part,
			})
		end
		table.insert(cursorShapes, { object = part })
		return part
	end

	local function cursorOutlineShape(size, circle, rotation)
		-- тёмная подложка под контуром
		if CURSOR.Outline then
			local back = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(size, size),
				BackgroundTransparency = 1,
				Rotation = rotation or 0,
				Parent = cursorRoot,
			})
			if circle then
				new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = back })
			end
			new("UIStroke", {
				Color = Color3.fromRGB(0, 0, 0),
				Transparency = 0.35,
				Thickness = CURSOR.Thickness + 2,
				Parent = back,
			})
		end

		local shape = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
			Rotation = rotation or 0,
			Parent = cursorRoot,
		})
		if circle then
			new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = shape })
		end
		local stroke = new("UIStroke", {
			Thickness = CURSOR.Thickness,
			Parent = shape,
		})
		table.insert(cursorShapes, { object = shape, stroke = stroke })
	end

	local function buildCursor()
		for _, child in ipairs(cursorRoot:GetChildren()) do
			child:Destroy()
		end
		table.clear(cursorShapes)

		local size = CURSOR.Size
		local thickness = CURSOR.Thickness
		cursorRoot.Size = UDim2.fromOffset(size, size)

		if CURSOR.Style == "Точка" then
			local dot = math.max(thickness * 2, math.floor(size / 3))
			cursorFill(UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(dot, dot), true)

		elseif CURSOR.Style == "Круг" then
			cursorOutlineShape(size, true)
			local dot = thickness + 2
			cursorFill(UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(dot, dot), true)

		elseif CURSOR.Style == "Ромб" then
			cursorOutlineShape(math.floor(size * 0.7), false, 45)

		else -- "Крестик": четыре линии с промежутком в центре
			local gap = math.max(2, math.floor(size * 0.18))
			local length = math.max(2, math.floor(size / 2 - gap))
			local offset = gap + length / 2
			cursorFill(UDim2.new(0.5, 0, 0.5, -offset), UDim2.fromOffset(thickness, length))
			cursorFill(UDim2.new(0.5, 0, 0.5, offset), UDim2.fromOffset(thickness, length))
			cursorFill(UDim2.new(0.5, -offset, 0.5, 0), UDim2.fromOffset(length, thickness))
			cursorFill(UDim2.new(0.5, offset, 0.5, 0), UDim2.fromOffset(length, thickness))
		end

		cursorBuiltFor = table.concat({ CURSOR.Style, size, thickness, tostring(CURSOR.Outline) }, "|")
	end

	RunService.RenderStepped:Connect(function()
		local enabled = CURSOR.Enabled and UserInputService.MouseEnabled
		cursorGui.Enabled = enabled

		if not enabled then
			-- возвращаем обычный курсор Roblox
			if cursorHidDefault then
				UserInputService.MouseIconEnabled = true
				cursorHidDefault = false
			end
			return
		end

		UserInputService.MouseIconEnabled = false
		cursorHidDefault = true

		local key = table.concat({ CURSOR.Style, CURSOR.Size, CURSOR.Thickness, tostring(CURSOR.Outline) }, "|")
		if key ~= cursorBuiltFor then
			buildCursor()
		end

		local mouse = UserInputService:GetMouseLocation()
		cursorRoot.Position = UDim2.fromOffset(mouse.X, mouse.Y)
		cursorRoot.Rotation = CURSOR.Spin and (os.clock() * 120) % 360 or 0

		local color = CURSOR.Rainbow and Color3.fromHSV((os.clock() * 0.3) % 1, 0.8, 1) or CURSOR.Color
		for _, shape in ipairs(cursorShapes) do
			if shape.stroke then
				shape.stroke.Color = color
				shape.stroke.Transparency = CURSOR.Transparency
			else
				shape.object.BackgroundColor3 = color
				shape.object.BackgroundTransparency = CURSOR.Transparency
			end
		end
	end)
end

--------------------------------------------------------------------
-- Target ESP: частицы вокруг игроков в заданном радиусе от вас (раздел Misc, видно только вам)
--------------------------------------------------------------------
local TARGET_ESP, TARGET_MODES, TARGET_STYLES
do
	TARGET_ESP = {
		Enabled = false,
		Mode = "Все в радиусе", -- "Все в радиусе" или "Ближайший"
		Style = "Орбиты",       -- "Орбиты", "Спираль", "Искры" или "Огоньки"
		Radius = 30,             -- в каком радиусе от вас (studs) игроки получают эффект
		Rainbow = false,
		Color = Color3.fromRGB(255, 90, 90),
		Count = 6,               -- сколько шариков в «Орбитах» и «Спирали»
		Size = 0.35,             -- размер частиц
		Speed = 2,               -- скорость вращения
		Glow = true,
		ShowTeammates = true,
	}

	TARGET_MODES = { "Все в радиусе", "Ближайший" }
	TARGET_STYLES = { "Орбиты", "Спираль", "Искры", "Огоньки" }
	local TARGET_TEXTURES = {
		["Искры"] = "rbxasset://textures/particles/sparkles_main.dds",
		["Огоньки"] = "rbxasset://textures/particles/fire_main.dds",
	}

	local targetFolder = Instance.new("Folder")
	targetFolder.Name = "TargetESP_Local"
	targetFolder.Parent = workspace

	local targets = {} -- [Player] = { style, count, size, orbs = {Part}, holder, emitter }

	local function destroyTarget(player)
		local data = targets[player]
		if not data then
			return
		end
		for _, orb in ipairs(data.orbs) do
			orb:Destroy()
		end
		if data.holder then
			data.holder:Destroy()
		end
		targets[player] = nil
	end

	local function buildTarget(player)
		destroyTarget(player)

		local data = {
			style = TARGET_ESP.Style,
			count = TARGET_ESP.Count,
			size = TARGET_ESP.Size,
			orbs = {},
		}

		if data.style == "Орбиты" or data.style == "Спираль" then
			for i = 1, data.count do
				local orb = Instance.new("Part")
				orb.Shape = Enum.PartType.Ball
				orb.Size = Vector3.new(data.size, data.size, data.size)
				orb.Anchored = true
				orb.CanCollide = false
				orb.CanQuery = false
				orb.CanTouch = false
				orb.CastShadow = false
				orb.Parent = targetFolder
				data.orbs[i] = orb
			end
		else
			-- невидимая деталь вокруг игрока, из объёма которой вылетают частицы
			local holder = Instance.new("Part")
			holder.Anchored = true
			holder.CanCollide = false
			holder.CanQuery = false
			holder.CanTouch = false
			holder.Transparency = 1
			holder.Size = Vector3.new(3, 5, 3)
			holder.Parent = targetFolder

			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = TARGET_TEXTURES[data.style]
			emitter.Shape = Enum.ParticleEmitterShape.Box
			emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			emitter.Rate = 25
			emitter.Lifetime = NumberRange.new(0.8, 1.4)
			emitter.Speed = NumberRange.new(0.3, 1.2)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Rotation = NumberRange.new(0, 360)
			emitter.RotSpeed = NumberRange.new(-60, 60)
			emitter.Acceleration = data.style == "Огоньки" and Vector3.new(0, 4, 0) or Vector3.zero
			emitter.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, data.size * 3),
				NumberSequenceKeypoint.new(1, 0),
			})
			emitter.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			})
			emitter.Parent = holder

			data.holder = holder
			data.emitter = emitter
		end

		targets[player] = data
	end

	local targetWanted = {}

	RunService.RenderStepped:Connect(function()
		table.clear(targetWanted)

		if TARGET_ESP.Enabled then
			local myCharacter = localPlayer.Character
			local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
			local camera = workspace.CurrentCamera
			local origin = (myRoot and myRoot.Position) or (camera and camera.CFrame.Position)

			local nearestPlayer, nearestDistance = nil, math.huge
			if origin then
				for _, player in ipairs(Players:GetPlayers()) do
					local character = player.Character
					local root = character and character:FindFirstChild("HumanoidRootPart")
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					local allowed = TARGET_ESP.ShowTeammates or not isTeammate(player)

					if player ~= localPlayer and root and humanoid and humanoid.Health > 0 and allowed then
						local distance = (root.Position - origin).Magnitude
						if distance <= TARGET_ESP.Radius then
							if TARGET_ESP.Mode == "Ближайший" then
								if distance < nearestDistance then
									nearestPlayer, nearestDistance = player, distance
								end
							else
								targetWanted[player] = root
							end
						end
					end
				end
			end

			if nearestPlayer then
				targetWanted[nearestPlayer] = nearestPlayer.Character.HumanoidRootPart
			end
		end

		-- убираем эффект у тех, кто вышел из радиуса
		for player in pairs(targets) do
			if not targetWanted[player] then
				destroyTarget(player)
			end
		end

		local now = os.clock()
		local color = TARGET_ESP.Rainbow and Color3.fromHSV((now * 0.3) % 1, 0.8, 1) or TARGET_ESP.Color
		local material = TARGET_ESP.Glow and Enum.Material.Neon or Enum.Material.SmoothPlastic

		for player, root in pairs(targetWanted) do
			local data = targets[player]
			if not data or data.style ~= TARGET_ESP.Style or data.count ~= TARGET_ESP.Count or data.size ~= TARGET_ESP.Size then
				buildTarget(player)
				data = targets[player]
			end

			local center = root.Position
			if data.holder then
				data.holder.CFrame = CFrame.new(center)
				data.emitter.Color = ColorSequence.new(color)
				data.emitter.LightEmission = TARGET_ESP.Glow and 1 or 0
				data.emitter.LightInfluence = TARGET_ESP.Glow and 0 or 1
			else
				local count = #data.orbs
				for i, orb in ipairs(data.orbs) do
					local phase = (i - 1) / count
					local angle = now * TARGET_ESP.Speed + phase * math.pi * 2
					local height
					if data.style == "Спираль" then
						-- шарики поднимаются по спирали снизу вверх и начинают заново
						height = ((now * TARGET_ESP.Speed * 0.25 + phase) % 1) * 6 - 3
					else
						-- орбиты слегка покачиваются вверх-вниз
						height = math.sin(now * TARGET_ESP.Speed + phase * math.pi * 2) * 1.2
					end
					orb.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * 2.5, height, math.sin(angle) * 2.5))
					orb.Color = color
					orb.Material = material
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(destroyTarget)
end

--------------------------------------------------------------------
-- Custom Pet: виртуальный питомец, который летает рядом с вами (раздел Misc, виден только вам)
--------------------------------------------------------------------
local PET, PET_STYLES, PET_SIDES
do
	PET = {
		Enabled = false,
		Style = "Шарик",      -- "Шарик", "Кубик" или "Дрон"
		Name = "Pet",         -- имя над питомцем (пусто — без имени)
		Rainbow = false,
		Color = Color3.fromRGB(255, 90, 90),
		Glow = false,
		Size = 1.2,           -- размер питомца
		Side = "Справа",      -- "Справа", "Слева" или "Сзади"
		FollowSpeed = 6,      -- как быстро догоняет (больше — резвее)
		Bobbing = true,       -- покачивание в воздухе
	}

	PET_STYLES = { "Шарик", "Кубик", "Дрон" }
	PET_SIDES = { "Справа", "Слева", "Сзади" }
	local PET_OFFSETS = {
		["Справа"] = Vector3.new(3, 1.2, 1),
		["Слева"] = Vector3.new(-3, 1.2, 1),
		["Сзади"] = Vector3.new(0, 1.8, 3.5),
	}

	local petFolder = Instance.new("Folder")
	petFolder.Name = "CustomPet_Local"
	petFolder.Parent = workspace

	local pet = nil -- { parts = { {part, offset, colored, spin} }, label, position, style, size }

	local function destroyPet()
		if pet then
			for _, entry in ipairs(pet.parts) do
				entry.part:Destroy()
			end
			pet.anchorPart:Destroy()
			pet = nil
		end
	end

	local function petPart(parts, shape, size, offset, colored, spin)
		local part = Instance.new("Part")
		part.Shape = shape
		part.Size = size
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = colored and PET.Color or Color3.fromRGB(20, 20, 24)
		part.Parent = petFolder
		table.insert(parts, { part = part, offset = offset, colored = colored, spin = spin })
		return part
	end

	local function buildPet(startPosition)
		destroyPet()

		local s = PET.Size
		local parts = {}
		local Ball, Block, Cylinder = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
		local up = CFrame.Angles(0, 0, math.pi / 2) -- поворачивает ось цилиндра вертикально

		if PET.Style == "Кубик" then
			petPart(parts, Block, Vector3.new(s, s, s), CFrame.new(), true)
			petPart(parts, Ball, Vector3.one * 0.2 * s, CFrame.new(-0.22 * s, 0.12 * s, -0.5 * s), false)
			petPart(parts, Ball, Vector3.one * 0.2 * s, CFrame.new(0.22 * s, 0.12 * s, -0.5 * s), false)
			petPart(parts, Block, Vector3.new(0.3 * s, 0.06 * s, 0.05 * s), CFrame.new(0, -0.15 * s, -0.5 * s), false)

		elseif PET.Style == "Дрон" then
			petPart(parts, Block, Vector3.new(0.9 * s, 0.45 * s, 0.9 * s), CFrame.new(), true)
			petPart(parts, Block, Vector3.new(0.55 * s, 0.14 * s, 0.06 * s), CFrame.new(0, 0.04 * s, -0.46 * s), false)
			petPart(parts, Cylinder, Vector3.new(0.25 * s, 0.08 * s, 0.08 * s), CFrame.new(0, 0.34 * s, 0) * up, false)
			-- винт вращается
			petPart(parts, Block, Vector3.new(1.3 * s, 0.04 * s, 0.14 * s), CFrame.new(0, 0.48 * s, 0), true, true)

		else -- "Шарик"
			petPart(parts, Ball, Vector3.one * s, CFrame.new(), true)
			petPart(parts, Ball, Vector3.one * 0.2 * s, CFrame.new(-0.2 * s, 0.12 * s, -0.42 * s), false)
			petPart(parts, Ball, Vector3.one * 0.2 * s, CFrame.new(0.2 * s, 0.12 * s, -0.42 * s), false)
			petPart(parts, Cylinder, Vector3.new(0.35 * s, 0.06 * s, 0.06 * s), CFrame.new(0, 0.62 * s, 0) * up, false)
			petPart(parts, Ball, Vector3.one * 0.16 * s, CFrame.new(0, 0.82 * s, 0), true)
		end

		-- невидимая точка над питомцем для имени
		local anchorPart = Instance.new("Part")
		anchorPart.Anchored = true
		anchorPart.CanCollide = false
		anchorPart.CanQuery = false
		anchorPart.CanTouch = false
		anchorPart.Transparency = 1
		anchorPart.Size = Vector3.new(0.1, 0.1, 0.1)
		anchorPart.Parent = petFolder

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(140, 22)
		billboard.StudsOffset = Vector3.new(0, 0.9 * s + 0.6, 0)
		billboard.Adornee = anchorPart
		billboard.Parent = anchorPart

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13
		label.TextStrokeTransparency = 0.4
		label.TextColor3 = C.text
		label.Parent = billboard

		pet = {
			parts = parts,
			anchorPart = anchorPart,
			label = label,
			position = startPosition,
			style = PET.Style,
			size = PET.Size,
		}
	end

	RunService.RenderStepped:Connect(function(dt)
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if not PET.Enabled or not root then
			destroyPet()
			return
		end

		local offset = PET_OFFSETS[PET.Side] or PET_OFFSETS["Справа"]
		local targetPosition = root.CFrame:PointToWorldSpace(offset)

		if not pet or pet.style ~= PET.Style or pet.size ~= PET.Size then
			buildPet(targetPosition)
		end

		-- плавно догоняем; если игрок телепортировался — прыгаем сразу
		if (targetPosition - pet.position).Magnitude > 60 then
			pet.position = targetPosition
		else
			local alpha = 1 - math.exp(-PET.FollowSpeed * dt)
			pet.position = pet.position:Lerp(targetPosition, alpha)
		end

		local now = os.clock()
		local bob = PET.Bobbing and math.sin(now * 2.5) * 0.25 or 0
		local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		if look.Magnitude < 0.01 then
			look = Vector3.new(0, 0, -1)
		end
		local center = pet.position + Vector3.new(0, bob, 0)
		local petCFrame = CFrame.lookAt(center, center + look.Unit)

		local color = PET.Rainbow and Color3.fromHSV((now * 0.3) % 1, 0.8, 1) or PET.Color
		local material = PET.Glow and Enum.Material.Neon or Enum.Material.SmoothPlastic

		for _, entry in ipairs(pet.parts) do
			local cf = petCFrame * entry.offset
			if entry.spin then
				cf = cf * CFrame.Angles(0, now * 18, 0)
			end
			entry.part.CFrame = cf
			if entry.colored then
				entry.part.Color = color
				entry.part.Material = material
			end
		end

		pet.anchorPart.CFrame = CFrame.new(center)
		pet.label.Text = PET.Name
		pet.label.Visible = PET.Name ~= ""
	end)
end

--------------------------------------------------------------------
-- Hit Effect: эффект, когда вы наносите урон игроку (раздел Misc, видно только вам)
--
-- Как скрипт узнаёт, что урон нанесли именно вы:
--   1) если в ReplicatedStorage есть RemoteEvent "JustVisualsHit" и сервер вызывает
--      JustVisualsHit:FireClient(атакующий, персонажЖертвы, урон) — это самый точный способ;
--   2) иначе — по стандартной метке Roblox "creator" (ObjectValue в Humanoid жертвы),
--      которую ставит большинство классических оружий.
-- Режим «Любой урон» показывает эффект при любой потере здоровья у других игроков.
--------------------------------------------------------------------
local HIT_EFFECT, HIT_MODES, HIT_STYLES, playHitEffect
do
	local Debris = game:GetService("Debris")
	local TweenService = game:GetService("TweenService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	HIT_EFFECT = {
		Enabled = false,
		Mode = "Мои удары",           -- "Мои удары" или "Любой урон"
		Style = "Вспышка + искры",    -- "Вспышка", "Искры", "Вспышка + искры" или "Без эффекта"
		Rainbow = false,
		Color = Color3.fromRGB(255, 90, 90),
		ShowDamage = true,            -- всплывающие числа урона
		Hitmarker = true,             -- крестик-хитмаркер у курсора
		Sound = true,
		Volume = 0.6,
	}

	HIT_MODES = { "Мои удары", "Любой урон" }
	HIT_STYLES = { "Вспышка", "Искры", "Вспышка + искры", "Без эффекта" }

	local hitFolder = Instance.new("Folder")
	hitFolder.Name = "HitEffects_Local"
	hitFolder.Parent = workspace

	local hitSound = Instance.new("Sound")
	hitSound.Name = "HitSound"
	hitSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	hitSound.Parent = SoundService

	local function hitColor()
		return HIT_EFFECT.Rainbow and Color3.fromHSV((os.clock() * 0.3) % 1, 0.8, 1) or HIT_EFFECT.Color
	end

	local function flashCharacter(character, color)
		local highlight = Instance.new("Highlight")
		highlight.Adornee = character
		highlight.FillColor = color
		highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
		highlight.FillTransparency = 0.25
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = hitFolder

		TweenService:Create(highlight, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FillTransparency = 1,
			OutlineTransparency = 1,
		}):Play()
		Debris:AddItem(highlight, 0.35)
	end

	local function sparkBurst(position, color)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.5, 0.5, 0.5)
		part.CFrame = CFrame.new(position)
		part.Parent = hitFolder

		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Enabled = false
		emitter.Color = ColorSequence.new(color)
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Lifetime = NumberRange.new(0.25, 0.45)
		emitter.Speed = NumberRange.new(8, 16)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Drag = 6
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Parent = part
		emitter:Emit(20)

		Debris:AddItem(part, 1)
	end

	local function damageNumber(position, damage, color)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.1, 0.1, 0.1)
		part.CFrame = CFrame.new(position + Vector3.new((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2))
		part.Parent = hitFolder

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(100, 30)
		billboard.StudsOffset = Vector3.new(0, 1, 0)
		billboard.AlwaysOnTop = true
		billboard.Adornee = part
		billboard.Parent = part

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextSize = 20
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.3
		label.Text = "-" .. tostring(math.max(1, math.floor(damage + 0.5)))
		label.Parent = billboard

		local info = TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(billboard, info, { StudsOffset = Vector3.new(0, 3.2, 0) }):Play()
		TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		Debris:AddItem(part, 0.8)
	end

	local function showHitmarker(root, color)
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(34, 34)
		billboard.AlwaysOnTop = true
		billboard.Adornee = root
		billboard.Parent = hitFolder

		local marker = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(22, 22),
			BackgroundTransparency = 1,
			Rotation = 45,
			Parent = billboard,
		})
		local scale = new("UIScale", { Scale = 1.4, Parent = marker })

		-- четыре коротких штриха крестом с пустым центром
		local bars = {}
		for _, spec in ipairs({
			{ UDim2.new(0.5, 0, 0, 3), UDim2.fromOffset(2, 7) },
			{ UDim2.new(0.5, 0, 1, -3), UDim2.fromOffset(2, 7) },
			{ UDim2.new(0, 3, 0.5, 0), UDim2.fromOffset(7, 2) },
			{ UDim2.new(1, -3, 0.5, 0), UDim2.fromOffset(7, 2) },
		}) do
			local bar = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = spec[1],
				Size = spec[2],
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				Parent = marker,
			})
			new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Transparency = 0.4, Parent = bar })
			table.insert(bars, bar)
		end

		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(0.15, function()
			for _, bar in ipairs(bars) do
				TweenService:Create(bar, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
			end
		end)
		Debris:AddItem(billboard, 0.4)
	end

	function playHitEffect(character, damage)
		if not HIT_EFFECT.Enabled or not character then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		local head = character:FindFirstChild("Head")
		if not root then
			return
		end

		local color = hitColor()
		local style = HIT_EFFECT.Style

		if style == "Вспышка" or style == "Вспышка + искры" then
			flashCharacter(character, color)
		end
		if style == "Искры" or style == "Вспышка + искры" then
			sparkBurst(root.Position, color)
		end
		if HIT_EFFECT.ShowDamage then
			damageNumber((head or root).Position, damage or 0, color)
		end
		if HIT_EFFECT.Hitmarker then
			showHitmarker(root, color)
		end
		if HIT_EFFECT.Sound then
			hitSound.Volume = HIT_EFFECT.Volume
			hitSound.PlaybackSpeed = 1.5 + math.random() * 0.2
			hitSound.TimePosition = 0
			hitSound:Play()
		end
	end

	-- Способ 1: сигнал от сервера
	local hitRemote = nil
	task.spawn(function()
		hitRemote = ReplicatedStorage:WaitForChild("JustVisualsHit", 5)
		if hitRemote and hitRemote:IsA("RemoteEvent") then
			hitRemote.OnClientEvent:Connect(function(character, damage)
				if HIT_EFFECT.Mode == "Мои удары" then
					playHitEffect(character, tonumber(damage) or 0)
				end
			end)
		else
			hitRemote = nil
		end
	end)

	-- Способ 2: следим за здоровьем других игроков.
	-- Метка creator часто висит на игроке ещё пару секунд после удара, и если в это время его
	-- ранит кто-то другой (или он упадёт), раньше эффект срабатывал «случайно».
	-- Теперь удар засчитывается, только если метка поставлена только что
	-- ИЛИ вы сами атаковали (клик / использование инструмента) меньше секунды назад.
	local lastAttackTime = -math.huge

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			lastAttackTime = os.clock()
		end
	end)

	local function hookTool(tool)
		if tool:IsA("Tool") then
			tool.Activated:Connect(function()
				lastAttackTime = os.clock()
			end)
		end
	end
	local function hookToolContainer(container)
		for _, child in ipairs(container:GetChildren()) do
			hookTool(child)
		end
		container.ChildAdded:Connect(hookTool)
	end
	task.spawn(function()
		hookToolContainer(localPlayer:WaitForChild("Backpack"))
	end)
	localPlayer.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			hookToolContainer(child)
		end
	end)
	localPlayer.CharacterAdded:Connect(hookToolContainer)
	if localPlayer.Character then
		hookToolContainer(localPlayer.Character)
	end

	local hitConnections = {} -- [Player] = { соединения }

	local function unwatch(player)
		local list = hitConnections[player]
		if list then
			for _, connection in ipairs(list) do
				connection:Disconnect()
			end
			hitConnections[player] = nil
		end
	end

	local function watchCharacter(player, character)
		unwatch(player)

		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or player.Character ~= character then
			return
		end

		local list = {}
		hitConnections[player] = list
		local lastTagTime = -math.huge

		local function checkTag(tag)
			if tag.Name == "creator" and tag:IsA("ObjectValue") and tag.Value == localPlayer then
				lastTagTime = os.clock()
			end
		end

		table.insert(list, humanoid.ChildAdded:Connect(function(child)
			checkTag(child)
			if child:IsA("ObjectValue") then
				table.insert(list, child.Changed:Connect(function()
					checkTag(child)
				end))
			end
		end))

		local lastHealth = humanoid.Health
		table.insert(list, humanoid.HealthChanged:Connect(function(health)
			local damage = lastHealth - health
			lastHealth = health
			if damage <= 0 or not HIT_EFFECT.Enabled then
				return
			end

			if HIT_EFFECT.Mode == "Любой урон" then
				playHitEffect(character, damage)
			elseif not hitRemote then
				local now = os.clock()
				local creator = humanoid:FindFirstChild("creator")
				local taggedByMe = creator and creator:IsA("ObjectValue") and creator.Value == localPlayer
				local freshTag = now - lastTagTime < 0.4
				local justAttacked = now - lastAttackTime < 1
				if taggedByMe and (freshTag or justAttacked) then
					playHitEffect(character, damage)
				end
			end
		end))
	end

	local function watchPlayer(player)
		if player == localPlayer then
			return
		end
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(unwatch)
end

--------------------------------------------------------------------
-- Раздел Misc
--------------------------------------------------------------------
local miscSection = createSection("Misc")

addModule(miscSection, {
	name = "Watermark",
	desc = "Логотип, FPS, пинг и время на экране.",
	source = WATERMARK,
	key = "Enabled",
	settings = function(page)
		toggleSetting(page, "Логотип", "ShowLogo", WATERMARK)
		toggleSetting(page, "FPS", "ShowFPS", WATERMARK)
		toggleSetting(page, "Пинг", "ShowPing", WATERMARK)
		toggleSetting(page, "Время", "ShowTime", WATERMARK)
		toggleSetting(page, "Секунды во времени", "ShowSeconds", WATERMARK)
		choiceSetting(page, "Положение", "Position", WATERMARK_POSITIONS, WATERMARK)
	end,
})

addModule(miscSection, {
	name = "Custom Cursor",
	desc = "Свой курсор вместо стандартного.",
	source = CURSOR,
	key = "Enabled",
	settings = function(page)
		choiceSetting(page, "Форма", "Style", CURSOR_STYLES, CURSOR)
		toggleSetting(page, "Радужный", "Rainbow", CURSOR)
		colorSetting(page, "Цвет", "Color", CURSOR)
		numberSetting(page, "Размер", "Size", 6, 48, CURSOR)
		numberSetting(page, "Толщина", "Thickness", 1, 6, CURSOR)
		toggleSetting(page, "Обводка", "Outline", CURSOR)
		toggleSetting(page, "Вращение", "Spin", CURSOR)
		numberSetting(page, "Прозрачность", "Transparency", 0, 0.9, CURSOR)
	end,
})

addModule(miscSection, {
	name = "Target ESP",
	desc = "Частицы вокруг игроков рядом с вами.",
	source = TARGET_ESP,
	key = "Enabled",
	settings = function(page)
		choiceSetting(page, "Кому показывать", "Mode", TARGET_MODES, TARGET_ESP)
		choiceSetting(page, "Частицы", "Style", TARGET_STYLES, TARGET_ESP)
		numberSetting(page, "Радиус", "Radius", 5, 300, TARGET_ESP)
		toggleSetting(page, "Радужные", "Rainbow", TARGET_ESP)
		colorSetting(page, "Цвет", "Color", TARGET_ESP)
		toggleSetting(page, "Glow", "Glow", TARGET_ESP)
		numberSetting(page, "Количество шариков", "Count", 1, 16, TARGET_ESP)
		numberSetting(page, "Размер", "Size", 0.1, 1.5, TARGET_ESP)
		numberSetting(page, "Скорость", "Speed", 0.2, 8, TARGET_ESP)
		toggleSetting(page, "Союзники", "ShowTeammates", TARGET_ESP)
	end,
})

addModule(miscSection, {
	name = "Custom Pet",
	desc = "Виртуальный питомец, который следует за вами.",
	source = PET,
	key = "Enabled",
	settings = function(page)
		choiceSetting(page, "Питомец", "Style", PET_STYLES, PET)
		textSetting(page, "Имя", "Name", 20, PET)
		toggleSetting(page, "Радужный", "Rainbow", PET)
		colorSetting(page, "Цвет", "Color", PET)
		toggleSetting(page, "Glow", "Glow", PET)
		numberSetting(page, "Размер", "Size", 0.5, 3, PET)
		choiceSetting(page, "Где летает", "Side", PET_SIDES, PET)
		numberSetting(page, "Скорость следования", "FollowSpeed", 1, 20, PET)
		toggleSetting(page, "Покачивание", "Bobbing", PET)
	end,
})

addModule(miscSection, {
	name = "Hit Effect",
	desc = "Эффект, когда вы наносите урон игроку.",
	source = HIT_EFFECT,
	key = "Enabled",
	settings = function(page)
		choiceSetting(page, "Когда срабатывает", "Mode", HIT_MODES, HIT_EFFECT)
		choiceSetting(page, "Эффект", "Style", HIT_STYLES, HIT_EFFECT)
		toggleSetting(page, "Радужный", "Rainbow", HIT_EFFECT)
		colorSetting(page, "Цвет", "Color", HIT_EFFECT)
		toggleSetting(page, "Числа урона", "ShowDamage", HIT_EFFECT)
		toggleSetting(page, "Хитмаркер", "Hitmarker", HIT_EFFECT)
		toggleSetting(page, "Звук попадания", "Sound", HIT_EFFECT)
		numberSetting(page, "Громкость", "Volume", 0, 3, HIT_EFFECT)
		actionSetting(page, "Проверить эффект", "На себе", function()
			local enabledBefore = HIT_EFFECT.Enabled
			HIT_EFFECT.Enabled = true
			playHitEffect(localPlayer.Character, 25)
			HIT_EFFECT.Enabled = enabledBefore
		end)
	end,
})

addModule(miscSection, {
	name = "Toggle Sounds",
	desc = "Звук при включении и выключении функций.",
	source = SOUNDS,
	key = "Enabled",
	settings = function(page)
		choiceSetting(page, "Звук", "Style", SOUND_STYLES, SOUNDS)
		numberSetting(page, "Громкость", "Volume", 0, 3, SOUNDS)
		numberSetting(page, "Тон включения", "OnPitch", 0.5, 2, SOUNDS)
		numberSetting(page, "Тон выключения", "OffPitch", 0.5, 2, SOUNDS)
		actionSetting(page, "Проверить звук", "Включение", function()
			playToggleSound(true)
		end)
		actionSetting(page, "Проверить звук", "Выключение", function()
			playToggleSound(false)
		end)
	end,
})

--------------------------------------------------------------------
-- Раздел Config: свои конфиги с названиями
-- Конфиги хранятся на сервере (DataStore), если в игре есть скрипт JustVisualsConfigs.server.lua.
-- Без него они работают, но живут только до выхода из игры.
--------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CONFIG_TABLES = {
	ESP = CONFIG,
	Hat = HAT,
	Trail = TRAIL,
	JumpCircle = JUMP_CIRCLE,
	Particles = PARTICLES,
	Fog = FOG,
	Sounds = SOUNDS,
	Watermark = WATERMARK,
	Cursor = CURSOR,
	TargetESP = TARGET_ESP,
	Pet = PET,
	HitEffect = HIT_EFFECT,
	Menu = MENU_STYLE,
	Sky = SKY,
}
local MAX_CONFIGS = 20
local MAX_NAME_LENGTH = 30

-- Настройки -> обычная таблица (Color3 превращаем в {r, g, b}, клавиши и прочее не сохраняем)
local function serializeSettings()
	local data = {}
	for groupName, source in pairs(CONFIG_TABLES) do
		local group = {}
		for key, value in pairs(source) do
			local valueType = typeof(value)
			if valueType == "boolean" or valueType == "number" or valueType == "string" then
				group[key] = value
			elseif valueType == "Color3" then
				group[key] = {
					__color = true,
					r = math.floor(value.R * 255 + 0.5),
					g = math.floor(value.G * 255 + 0.5),
					b = math.floor(value.B * 255 + 0.5),
				}
			end
		end
		data[groupName] = group
	end
	return data
end

local function applySettings(data)
	for groupName, group in pairs(data) do
		local source = CONFIG_TABLES[groupName]
		if source and type(group) == "table" then
			for key, value in pairs(group) do
				local current = source[key]
				if current ~= nil then
					if typeof(current) == "Color3" and type(value) == "table" and value.__color then
						source[key] = Color3.fromRGB(value.r, value.g, value.b)
					elseif typeof(current) == typeof(value) then
						source[key] = value
					end
				end
			end
		end
	end
	for _, refresh in ipairs(uiRefreshers) do
		refresh()
	end
end

local savedConfigs = {} -- [название] = { data, savedAt }
local autoloadName = nil
local configRemote = ReplicatedStorage:WaitForChild("JustVisualsConfigs", 3)

local function persistConfigs()
	if not configRemote then
		return
	end
	task.spawn(function()
		local ok, result = pcall(function()
			return configRemote:InvokeServer("set", { configs = savedConfigs, autoload = autoloadName })
		end)
		if not ok or result == false then
			warn("opus client: не удалось сохранить конфиги на сервере", result)
		end
	end)
end

local configSection = createSection("Config", "Settings")
local configCards = {} -- { card, page }
local rebuildConfigCards

-- Карточка «Новый конфиг»: поле для названия и кнопка сохранения
local createCard = new("Frame", {
	LayoutOrder = 0,
	BackgroundColor3 = C.card,
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Parent = configSection.grid,
})
round(createCard, 8)
outline(createCard, C.accent, 0.55)

local createTitle = new("TextLabel", {
	Position = UDim2.fromOffset(12, 6),
	Size = UDim2.new(1, -24, 0, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = C.text,
	Text = "Новый конфиг",
	Parent = createCard,
})

local nameBox = new("TextBox", {
	Position = UDim2.fromOffset(12, 32),
	Size = UDim2.new(1, -58, 0, 24),
	BackgroundColor3 = C.inner,
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextColor3 = C.text,
	TextXAlignment = Enum.TextXAlignment.Left,
	PlaceholderText = "Название...",
	PlaceholderColor3 = C.sub,
	ClearTextOnFocus = false,
	Text = "",
	Parent = createCard,
})
round(nameBox, 6)
new("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = nameBox })

local saveButton = new("TextButton", {
	Position = UDim2.new(1, -40, 0, 32),
	Size = UDim2.fromOffset(28, 24),
	BackgroundColor3 = C.accent,
	BorderSizePixel = 0,
	AutoButtonColor = true,
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	TextColor3 = C.text,
	Text = "+",
	Parent = createCard,
})
round(saveButton, 6)

local flashId = 0
local function flashTitle(text, color)
	flashId += 1
	local myId = flashId
	createTitle.Text = text
	createTitle.TextColor3 = color or C.text
	task.delay(1.6, function()
		if flashId == myId then
			createTitle.Text = "Новый конфиг"
			createTitle.TextColor3 = C.text
		end
	end)
end

local function countConfigs()
	local count = 0
	for _ in pairs(savedConfigs) do
		count += 1
	end
	return count
end

local function saveNewConfig()
	local name = nameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then
		flashTitle("Введите название", C.accent)
		return
	end
	if #name > MAX_NAME_LENGTH then
		flashTitle("Слишком длинное название", C.accent)
		return
	end
	if not savedConfigs[name] and countConfigs() >= MAX_CONFIGS then
		flashTitle("Максимум " .. MAX_CONFIGS .. " конфигов", C.accent)
		return
	end

	local existed = savedConfigs[name] ~= nil
	savedConfigs[name] = { data = serializeSettings(), savedAt = os.time() }
	nameBox.Text = ""
	persistConfigs()
	rebuildConfigCards()
	playToggleSound(true)
	flashTitle(existed and "Перезаписан" or "Сохранён")
end

saveButton.MouseButton1Click:Connect(saveNewConfig)
nameBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		saveNewConfig()
	end
end)

local function removeConfigCardsFromSearch()
	for index = #configSection.cards, 1, -1 do
		if configSection.cards[index].isConfig then
			table.remove(configSection.cards, index)
		end
	end
end

rebuildConfigCards = function()
	-- если открыта страница удаляемой карточки — возвращаемся к сетке
	if currentModule and currentModule.isConfig then
		showGrid()
	end

	for _, entry in ipairs(configCards) do
		entry.card:Destroy()
		entry.page:Destroy()
	end
	table.clear(configCards)
	removeConfigCardsFromSearch()

	local names = {}
	for name in pairs(savedConfigs) do
		table.insert(names, name)
	end
	table.sort(names, function(a, b)
		return a:lower() < b:lower()
	end)

	for index, name in ipairs(names) do
		local entry = savedConfigs[name]
		local isAutoload = autoloadName == name
		local descText = "Сохранён " .. os.date("%d.%m %H:%M", entry.savedAt or os.time())
			.. (isAutoload and "  ·  авто" or "")

		local card = new("TextButton", {
			LayoutOrder = index,
			BackgroundColor3 = C.card,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Parent = configSection.grid,
		})
		round(card, 8)

		local icon = new("Frame", {
			Position = UDim2.fromOffset(12, 13),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = isAutoload and C.accent or C.accentDim,
			BorderSizePixel = 0,
			Parent = card,
		})
		round(icon, 3)

		new("TextLabel", {
			Position = UDim2.fromOffset(32, 8),
			Size = UDim2.new(1, -62, 0, 22),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = C.text,
			Text = name,
			Parent = card,
		})

		local desc = new("TextLabel", {
			Position = UDim2.fromOffset(12, 32),
			Size = UDim2.new(1, -24, 0, 28),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 11,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = C.sub,
			Text = descText,
			Parent = card,
		})

		local dots = new("TextButton", {
			Position = UDim2.new(1, -28, 0, 6),
			Size = UDim2.fromOffset(22, 22),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 2,
			Parent = card,
		})
		drawIcon(dots, "kebab", 14)(C.sub)

		local function loadThis()
			applySettings(entry.data)
			playToggleSound(true)
			desc.Text = "Загружен"
			desc.TextColor3 = C.accent
			task.delay(1.6, function()
				if desc.Parent then
					desc.Text = descText
					desc.TextColor3 = C.sub
				end
			end)
		end

		-- страница действий с конфигом
		local page = makeScroller(name .. "_Config")
		new("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = page,
		})
		actionSetting(page, "Загрузить настройки", "Загрузить", function()
			loadThis()
		end)
		actionSetting(page, "Сохранить текущие сюда", "Перезаписать", function()
			savedConfigs[name] = { data = serializeSettings(), savedAt = os.time() }
			persistConfigs()
			playToggleSound(true)
			rebuildConfigCards()
		end)
		actionSetting(page, "Загружать при запуске", isAutoload and "Выключить" or "Включить", function()
			autoloadName = (autoloadName == name) and nil or name
			persistConfigs()
			playToggleSound(autoloadName == name)
			rebuildConfigCards()
		end)
		actionSetting(page, "Удалить конфиг", "Удалить", function()
			savedConfigs[name] = nil
			if autoloadName == name then
				autoloadName = nil
			end
			persistConfigs()
			playToggleSound(false)
			rebuildConfigCards()
		end)

		local module = { name = name, page = page, isConfig = true }
		dots.MouseButton1Click:Connect(function()
			openSettings(module)
		end)

		card.MouseButton1Click:Connect(loadThis)
		card.MouseEnter:Connect(function()
			card.BackgroundColor3 = C.cardHover
		end)
		card.MouseLeave:Connect(function()
			card.BackgroundColor3 = C.card
		end)

		table.insert(configCards, { card = card, page = page })
		table.insert(configSection.cards, { frame = card, name = name, desc = descText, isConfig = true })
	end
end

-- Загружаем сохранённые конфиги с сервера и применяем автозагрузку
task.spawn(function()
	if configRemote then
		local ok, result = pcall(function()
			return configRemote:InvokeServer("get")
		end)
		if ok and type(result) == "table" then
			savedConfigs = type(result.configs) == "table" and result.configs or {}
			autoloadName = result.autoload
		else
			warn("opus client: не удалось получить конфиги с сервера", result)
		end
	end

	rebuildConfigCards()

	if autoloadName and savedConfigs[autoloadName] then
		applySettings(savedConfigs[autoloadName].data)
	end
end)

--------------------------------------------------------------------
-- Раздел Themes: цветовые темы меню и размытие фона
--------------------------------------------------------------------
local updateMenuBlur -- задаётся ниже, в блоке анимации меню

do
	local THEMES = {
		["Бордовый"] = {
			bgTop = Color3.fromRGB(92, 32, 44), bgBottom = Color3.fromRGB(38, 14, 20),
			panel = Color3.fromRGB(30, 11, 16), card = Color3.fromRGB(80, 30, 40),
			cardHover = Color3.fromRGB(98, 38, 50), inner = Color3.fromRGB(52, 19, 27),
			accent = Color3.fromRGB(250, 90, 106), accentDim = Color3.fromRGB(140, 56, 70),
			off = Color3.fromRGB(104, 76, 82), sub = Color3.fromRGB(226, 204, 209),
			line = Color3.fromRGB(160, 88, 100),
		},
		["Полночь"] = {
			bgTop = Color3.fromRGB(36, 50, 104), bgBottom = Color3.fromRGB(14, 18, 42),
			panel = Color3.fromRGB(12, 16, 36), card = Color3.fromRGB(38, 50, 100),
			cardHover = Color3.fromRGB(48, 62, 120), inner = Color3.fromRGB(22, 28, 58),
			accent = Color3.fromRGB(118, 162, 255), accentDim = Color3.fromRGB(62, 86, 160),
			off = Color3.fromRGB(74, 82, 112), sub = Color3.fromRGB(206, 214, 240),
			line = Color3.fromRGB(88, 110, 184),
		},
		["Аметист"] = {
			bgTop = Color3.fromRGB(80, 38, 116), bgBottom = Color3.fromRGB(30, 15, 46),
			panel = Color3.fromRGB(24, 12, 38), card = Color3.fromRGB(72, 36, 104),
			cardHover = Color3.fromRGB(88, 46, 126), inner = Color3.fromRGB(44, 22, 66),
			accent = Color3.fromRGB(198, 134, 255), accentDim = Color3.fromRGB(110, 70, 160),
			off = Color3.fromRGB(96, 78, 114), sub = Color3.fromRGB(222, 206, 240),
			line = Color3.fromRGB(134, 92, 186),
		},
		["Изумруд"] = {
			bgTop = Color3.fromRGB(26, 88, 72), bgBottom = Color3.fromRGB(10, 32, 27),
			panel = Color3.fromRGB(9, 26, 22), card = Color3.fromRGB(30, 78, 65),
			cardHover = Color3.fromRGB(38, 96, 80), inner = Color3.fromRGB(17, 46, 38),
			accent = Color3.fromRGB(88, 232, 170), accentDim = Color3.fromRGB(44, 128, 96),
			off = Color3.fromRGB(72, 98, 90), sub = Color3.fromRGB(204, 234, 222),
			line = Color3.fromRGB(70, 142, 116),
		},
		["Графит"] = {
			bgTop = Color3.fromRGB(66, 66, 74), bgBottom = Color3.fromRGB(26, 26, 30),
			panel = Color3.fromRGB(20, 20, 24), card = Color3.fromRGB(58, 58, 66),
			cardHover = Color3.fromRGB(72, 72, 82), inner = Color3.fromRGB(36, 36, 42),
			accent = Color3.fromRGB(255, 176, 90), accentDim = Color3.fromRGB(130, 96, 64),
			off = Color3.fromRGB(90, 90, 98), sub = Color3.fromRGB(220, 220, 226),
			line = Color3.fromRGB(118, 118, 130),
		},
	}
	local THEME_ORDER = { "Бордовый", "Полночь", "Аметист", "Изумруд", "Графит" }
	local THEME_KEYS = { "bgTop", "bgBottom", "panel", "card", "cardHover", "inner", "accent", "accentDim", "off", "sub", "line" }
	local appliedTheme = "Бордовый"
	local themeCards = {}

	local function colorKey(color)
		return string.format("%d,%d,%d",
			math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
	end

	local function recolor(root, map)
		for _, obj in ipairs(root:GetDescendants()) do
			if obj:IsA("GuiObject") and obj:GetAttribute("KeepColor") then
				continue
			end
			if obj:IsA("GuiObject") then
				local background = map[colorKey(obj.BackgroundColor3)]
				if background then
					obj.BackgroundColor3 = background
				end
				if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
					local textColor = map[colorKey(obj.TextColor3)]
					if textColor then
						obj.TextColor3 = textColor
					end
					if obj:IsA("TextBox") then
						local placeholder = map[colorKey(obj.PlaceholderColor3)]
						if placeholder then
							obj.PlaceholderColor3 = placeholder
						end
					end
				end
				if obj:IsA("ScrollingFrame") then
					local bar = map[colorKey(obj.ScrollBarImageColor3)]
					if bar then
						obj.ScrollBarImageColor3 = bar
					end
				end
			elseif obj:IsA("UIStroke") then
				local strokeColor = map[colorKey(obj.Color)]
				if strokeColor then
					obj.Color = strokeColor
				end
			elseif obj:IsA("UIGradient") then
				local changed, keypoints = false, {}
				for _, keypoint in ipairs(obj.Color.Keypoints) do
					local mapped = map[colorKey(keypoint.Value)]
					changed = changed or mapped ~= nil
					table.insert(keypoints, ColorSequenceKeypoint.new(keypoint.Time, mapped or keypoint.Value))
				end
				if changed then
					obj.Color = ColorSequence.new(keypoints)
				end
			end
		end
	end

	local function refreshThemeCards()
		for name, entry in pairs(themeCards) do
			local active = name == appliedTheme
			entry.stroke.Color = active and C.accent or C.line
			entry.stroke.Transparency = active and 0.2 or 0.65
			entry.badge.Visible = active
			entry.badge.TextColor3 = C.accent
		end
	end

	local function applyTheme(name)
		local theme = THEMES[name]
		if not theme then
			return
		end
		if name ~= appliedTheme then
			local map = {}
			for _, key in ipairs(THEME_KEYS) do
				map[colorKey(C[key])] = theme[key]
			end
			recolor(screenGui, map)
			local watermark = playerGui:FindFirstChild("JustVisuals_Watermark")
			if watermark then
				recolor(watermark, map)
			end
			for _, key in ipairs(THEME_KEYS) do
				C[key] = theme[key]
			end
			appliedTheme = name
		end
		MENU_STYLE.Theme = name
		for _, refresh in ipairs(uiRefreshers) do
			refresh()
		end
		refreshThemeCards()
		if currentSection and not currentModule then
			selectSection(currentSection)
		end
	end

	local themesSection = createSection("Themes", "Settings")

	for index, name in ipairs(THEME_ORDER) do
		local theme = THEMES[name]
		local card = new("TextButton", {
			LayoutOrder = index,
			BackgroundColor3 = C.card,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Parent = themesSection.grid,
		})
		round(card, 8)
		local stroke = outline(card, C.line, 0.65)

		new("TextLabel", {
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.new(1, -80, 0, 20),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.text,
			Text = name,
			Parent = card,
		})

		local badge = new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 8),
			Size = UDim2.fromOffset(70, 20),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = C.accent,
			Text = "активна",
			Visible = false,
			Parent = card,
		})

		-- образцы цветов темы
		for i, key in ipairs({ "bgTop", "card", "accentDim", "accent" }) do
			local swatch = new("Frame", {
				Position = UDim2.fromOffset(12 + (i - 1) * 24, 36),
				Size = UDim2.fromOffset(18, 18),
				BackgroundColor3 = theme[key],
				BorderSizePixel = 0,
				Parent = card,
			})
			round(swatch, 9)
			new("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Transparency = 0.8, Parent = swatch })
			-- образцы не должны перекрашиваться при смене темы
			swatch:SetAttribute("KeepColor", true)
		end

		card.MouseButton1Click:Connect(function()
			applyTheme(name)
			playToggleSound(true)
		end)
		card.MouseEnter:Connect(function()
			card.BackgroundColor3 = C.cardHover
		end)
		card.MouseLeave:Connect(function()
			card.BackgroundColor3 = C.card
		end)

		themeCards[name] = { stroke = stroke, badge = badge }
		table.insert(themesSection.cards, { frame = card, name = name, desc = "тема" })
	end

	addModule(themesSection, {
		name = "Размытие фона",
		desc = "Мир за открытым меню размывается.",
		source = MENU_STYLE,
		key = "Blur",
		onToggle = function()
			if updateMenuBlur then
				updateMenuBlur()
			end
		end,
	})

	refreshThemeCards()

	-- после загрузки конфига применяем сохранённую в нём тему и размытие
	table.insert(uiRefreshers, function()
		if MENU_STYLE.Theme ~= appliedTheme and THEMES[MENU_STYLE.Theme] then
			applyTheme(MENU_STYLE.Theme)
		end
		if updateMenuBlur then
			updateMenuBlur()
		end
	end)
end

selectSection("Visuals")

--------------------------------------------------------------------
-- Анимация появления и скрытия меню
--------------------------------------------------------------------
local TweenService = game:GetService("TweenService")

local windowScale = new("UIScale", { Scale = 1, Parent = frame })

-- Размытие мира за открытым меню
local menuBlur = new("BlurEffect", { Name = "JustVisualsMenuBlur", Size = 0, Parent = game:GetService("Lighting") })
local menuIsOpen = false

updateMenuBlur = function()
	local target = (menuIsOpen and MENU_STYLE.Blur) and 10 or 0
	TweenService:Create(menuBlur, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = target }):Play()
end

local menuOpen = false
local animationId = 0 -- чтобы быстрое повторное нажатие не ломало анимацию

-- Масштаб, при котором окно целиком помещается на экран с отступами
local WINDOW_SIZE = Vector2.new(600, 400)
local SCREEN_MARGIN = 24

local function getFitScale()
	local available = screenGui.AbsoluteSize
	if available.X < 1 or available.Y < 1 then
		return 1
	end
	local scale = math.min(
		(available.X - SCREEN_MARGIN * 2) / WINDOW_SIZE.X,
		(available.Y - SCREEN_MARGIN * 2) / WINDOW_SIZE.Y
	)
	return math.clamp(scale, 0.45, 1)
end

-- Не даёт окну уехать за край экрана (после перетаскивания или смены размера окна игры)
local function clampWindow()
	local available = screenGui.AbsoluteSize
	local half = WINDOW_SIZE * getFitScale() / 2
	local maxX = math.max(0, available.X / 2 - half.X - SCREEN_MARGIN)
	local maxY = math.max(0, available.Y / 2 - half.Y - SCREEN_MARGIN)
	frame.Position = UDim2.new(
		0.5, math.clamp(frame.Position.X.Offset, -maxX, maxX),
		0.5, math.clamp(frame.Position.Y.Offset, -maxY, maxY)
	)
end

screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if menuOpen then
		windowScale.Scale = getFitScale()
		clampWindow()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if menuOpen and (input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch) then
		clampWindow()
	end
end)

--------------------------------------------------------------------
-- Анимация «разбитого стекла», как в примере:
-- закрытие — по окну расходятся трещины (светятся цветом темы), затем осколки с настоящим
-- содержимым меню разлетаются, улетают вглубь (уменьшаются), крутятся и гаснут;
-- открытие — то же самое задом наперёд: осколки прилетают издалека и собираются в окно.
--------------------------------------------------------------------
local SHARD_COLUMNS = 2 -- окно раскалывается на две половины: левую и правую
local SHARD_ROWS = 1
local CRACK_TIME = 0.12     -- сколько длится «трескание» перед разлётом
local CRACK_GAP = 5         -- ширина трещин, пикселей
local FLY_TIME = 0.6        -- сколько осколки летят
local MAX_DELAY = 0.07      -- осколки срываются не одновременно
local SHARD_GRAVITY = 900
local OPEN_TIME = 0.6
local TOTAL_TIME = MAX_DELAY + CRACK_TIME + FLY_TIME

-- слой для осколков: стоит ровно там же, где окно, и масштабируется так же
local shardLayer = new("Frame", {
	Name = "ShardLayer",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 5,
	Parent = screenGui,
})
local shardScale = new("UIScale", { Parent = shardLayer })

local shardPieces = {}
local shardConnection = nil

local function clearShards()
	if shardConnection then
		shardConnection:Disconnect()
		shardConnection = nil
	end
	for _, piece in ipairs(shardPieces) do
		piece.shard:Destroy()
	end
	table.clear(shardPieces)
	shardLayer.Visible = false
end

-- «Снимок» окна: копия того, что сейчас видно (скрытые страницы выкидываем, чтобы было легко)
local function makeSnapshot()
	local snapshot = Instance.new("Frame")
	snapshot.Size = UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y)
	snapshot.BackgroundTransparency = 1
	snapshot.BorderSizePixel = 0

	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UIScale") then
			local ok, copy = pcall(function()
				return child:Clone()
			end)
			if ok and copy then
				copy.Parent = snapshot
			end
		end
	end

	for _, descendant in ipairs(snapshot:GetDescendants()) do
		if descendant.Parent and descendant:IsA("GuiObject") and not descendant.Visible then
			descendant:Destroy()
		end
	end
	return snapshot
end

local function randomCuts(count, jitter)
	local cuts = { 0 }
	for i = 1, count - 1 do
		table.insert(cuts, (i + (math.random() - 0.5) * jitter) / count)
	end
	table.insert(cuts, 1)
	return cuts
end

-- Режем снимок на осколки. У каждого ряда свои разрезы (как кирпичная кладка),
-- поэтому трещины идут неровно, а не ровной сеткой.
local function createShards()
	clearShards()
	shardLayer.Position = frame.Position
	shardScale.Scale = windowScale.Scale
	shardLayer.Visible = true

	local snapshot = makeSnapshot()
	local center = WINDOW_SIZE / 2
	local yCuts = randomCuts(SHARD_ROWS, 0.35)
	local total = SHARD_COLUMNS * SHARD_ROWS

	for row = 1, SHARD_ROWS do
		local xCuts = randomCuts(SHARD_COLUMNS, 0.25)
		for column = 1, SHARD_COLUMNS do
			local x0 = math.floor(xCuts[column] * WINDOW_SIZE.X)
			local x1 = math.floor(xCuts[column + 1] * WINDOW_SIZE.X)
			local y0 = math.floor(yCuts[row] * WINDOW_SIZE.Y)
			local y1 = math.floor(yCuts[row + 1] * WINDOW_SIZE.Y)
			local pieceSize = Vector2.new(x1 - x0, y1 - y0)
			local home = Vector2.new(x0, y0) + pieceSize / 2

			local shard = Instance.new("CanvasGroup")
			shard.AnchorPoint = Vector2.new(0.5, 0.5)
			shard.Position = UDim2.fromOffset(home.X, home.Y)
			shard.Size = UDim2.fromOffset(pieceSize.X, pieceSize.Y)
			shard.BackgroundTransparency = 1
			shard.Parent = shardLayer

			local copy = (#shardPieces == total - 1) and snapshot or snapshot:Clone()
			copy.Position = UDim2.fromOffset(-x0, -y0)
			copy.Parent = shard

			-- светящийся край осколка (как красные края трещин в примере)
			local edge = Instance.new("UIStroke")
			edge.Color = C.accent
			edge.Thickness = 1.5
			edge.Transparency = 1
			edge.Parent = shard

			local depth = Instance.new("UIScale")
			depth.Parent = shard

			local direction = home - center
			direction = direction.Magnitude > 1 and direction.Unit or Vector2.new(0, -1)

			table.insert(shardPieces, {
				shard = shard,
				edge = edge,
				depth = depth,
				home = home,
				direction = direction,
				crackRotation = (math.random() - 0.5) * 5,
				velocity = direction * (260 + math.random() * 80)
					+ Vector2.new(0, -40 - math.random() * 60),
				spin = (direction.X < 0 and -1 or 1) * (25 + math.random() * 20), -- каждая половина заваливается наружу
				farScale = 0.3 + math.random() * 0.25, -- насколько «вглубь» улетает осколок
				delay = math.random() * MAX_DELAY,
			})
		end
	end
end

-- Положение осколка через tau секунд после начала разрушения
local function applyShard(piece, tau)
	local t = math.max(0, tau - piece.delay)
	local crack = math.clamp(t / CRACK_TIME, 0, 1)
	local fly = math.max(0, t - CRACK_TIME)
	local flyProgress = math.clamp(fly / FLY_TIME, 0, 1)

	local offset = piece.direction * CRACK_GAP * crack
		+ piece.velocity * fly
		+ Vector2.new(0, 0.5 * SHARD_GRAVITY * fly * fly)
	local position = piece.home + offset

	piece.shard.Position = UDim2.fromOffset(position.X, position.Y)
	piece.shard.Rotation = piece.crackRotation * crack + piece.spin * fly
	piece.depth.Scale = 1 - (1 - piece.farScale) * flyProgress
	piece.edge.Transparency = 1 - 0.75 * crack
	piece.shard.GroupTransparency = math.clamp((flyProgress - 0.35) / 0.65, 0, 1)
end

local function openMenu()
	animationId += 1
	local myId = animationId
	menuOpen = true
	menuIsOpen = true
	updateMenuBlur()

	windowScale.Scale = getFitScale()
	clampWindow()
	frame.Visible = false
	screenGui.Enabled = true

	createShards()
	for _, piece in ipairs(shardPieces) do
		applyShard(piece, TOTAL_TIME) -- осколки стартуют разлетевшимися
	end

	local started = os.clock()
	shardConnection = RunService.RenderStepped:Connect(function()
		local u = math.clamp((os.clock() - started) / OPEN_TIME, 0, 1)
		local tau = TOTAL_TIME * (1 - u) ^ 2 -- прилетают быстро и мягко «встают» на место
		for _, piece in ipairs(shardPieces) do
			applyShard(piece, tau)
		end
		if u >= 1 then
			clearShards()
			if animationId == myId then
				frame.Visible = true
			end
		end
	end)
end

local function closeMenu()
	animationId += 1
	local myId = animationId
	menuOpen = false
	menuIsOpen = false
	updateMenuBlur()

	createShards()
	frame.Visible = false -- настоящее окно прячем в тот же кадр, осколки выглядят точно так же

	local started = os.clock()
	shardConnection = RunService.RenderStepped:Connect(function()
		local tau = os.clock() - started
		for _, piece in ipairs(shardPieces) do
			applyShard(piece, tau)
		end
		if tau >= TOTAL_TIME then
			clearShards()
			if animationId == myId then
				screenGui.Enabled = false
				frame.Visible = true
			end
		end
	end)
end

--------------------------------------------------------------------
-- Заставка при запуске скрипта: размытие, логотип, название, полоса загрузки
--------------------------------------------------------------------
local introPlaying = false

local function tween(object, time, props, style, direction)
	local t = TweenService:Create(
		object,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

local function playIntro()
	introPlaying = true

	local introGui = new("ScreenGui", {
		Name = "JustVisuals_Intro",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 200,
		Parent = playerGui,
	})

	-- затемнение и размытие мира
	local dim = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(10, 3, 6),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = introGui,
	})
	local blur = new("BlurEffect", { Size = 0, Parent = game:GetService("Lighting") })

	local holder = new("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(320, 200),
		BackgroundTransparency = 1,
		Parent = introGui,
	})

	local logo = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 50),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = LOGO_BG,
		BorderSizePixel = 0,
		Rotation = -90,
		Parent = holder,
	})
	round(logo, 14)
	new("UIStroke", { Color = C.accent, Transparency = 0.4, Thickness = 2, Parent = logo })
	local logoScale = new("UIScale", { Scale = 0, Parent = logo })
	drawLogoMark(logo, 64)

	local titleText = "opus client"
	local title = new("TextLabel", {
		Position = UDim2.new(0, 0, 0, 96),
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 30,
		TextColor3 = C.text,
		Text = "",
		Parent = holder,
	})

	local status = new("TextLabel", {
		Position = UDim2.new(0, 0, 0, 136),
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = C.sub,
		TextTransparency = 1,
		Text = "загрузка модулей...",
		Parent = holder,
	})

	local barBack = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 166),
		Size = UDim2.fromOffset(200, 4),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = holder,
	})
	round(barBack, 2)
	local barFill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.accent,
		BorderSizePixel = 0,
		Parent = barBack,
	})
	round(barFill, 2)

	-- 1. затемнение и размытие
	tween(dim, 0.4, { BackgroundTransparency = 0.35 })
	tween(blur, 0.4, { Size = 14 })
	task.wait(0.25)

	-- 2. логотип выпрыгивает с поворотом
	tween(logoScale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(logo, 0.55, { Rotation = 0 }, Enum.EasingStyle.Back)
	task.wait(0.45)

	-- 3. название печатается по буквам
	for i = 1, #titleText do
		title.Text = string.sub(titleText, 1, i)
		task.wait(0.04)
	end

	-- 4. полоса загрузки
	tween(status, 0.25, { TextTransparency = 0 })
	tween(barBack, 0.25, { BackgroundTransparency = 0.2 })
	tween(barFill, 0.45, { Size = UDim2.fromScale(0.55, 1) }, Enum.EasingStyle.Sine)
	task.wait(0.45)
	status.Text = "применение настроек..."
	tween(barFill, 0.4, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Sine)
	task.wait(0.4)
	status.Text = "готово"
	status.TextColor3 = C.accent
	playToggleSound(true)
	task.wait(0.35)

	-- 5. заставка растворяется, появляется меню
	tween(holder, 0.35, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(dim, 0.45, { BackgroundTransparency = 1 })
	local blurOut = tween(blur, 0.45, { Size = 0 })
	task.wait(0.2)

	introPlaying = false
	openMenu()

	blurOut.Completed:Wait()
	blur:Destroy()
	introGui:Destroy()
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or introPlaying then
		return
	end
	if input.KeyCode == CONFIG.MenuKey then
		if menuOpen then
			closeMenu()
		else
			openMenu()
		end
	end
end)

-- заставка при запуске скрипта, после неё появляется меню
screenGui.Enabled = false
task.spawn(playIntro)
