--

-- ███████╗███╗░░██╗██████╗░███████╗██████╗░  ██╗░░██╗██╗░░░██╗██████╗░
-- ██╔════╝████╗░██║██╔══██╗██╔════╝██╔══██╗  ██║░░██║██║░░░██║██╔══██╗
-- █████╗░░██╔██╗██║██║░░██║█████╗░░██████╔╝  ███████║██║░░░██║██████╦╝
-- ██╔══╝░░██║╚████║██║░░██║██╔══╝░░██╔══██╗  ██╔══██║██║░░░██║██╔══██╗
-- ███████╗██║░╚███║██████╔╝███████╗██║░░██║  ██║░░██║╚██████╔╝██████╦╝
-- ╚══════╝╚═╝░░╚══╝╚═════╝░╚══════╝╚═╝░░╚═╝  ╚═╝░░╚═╝░╚═════╝░╚═════╝░
-- Ender Hub beta outdated message
-- anyways hello + what are you doing here grr
-- Made By Qilex

local gui = Instance.new("ScreenGui")
local frame = Instance.new("Frame")
local title = Instance.new("TextLabel")
local desc = Instance.new("TextLabel")
local copybtn = Instance.new("TextButton")
local closebtn = Instance.new("TextButton")
local corner1 = Instance.new("UICorner")
local corner2 = Instance.new("UICorner")
local corner3 = Instance.new("UICorner")
local corner4 = Instance.new("UICorner")
local corner5 = Instance.new("UICorner")

gui.Name = "EnderHubV2"
gui.Parent = game:GetService("CoreGui")
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

frame.Name = "MainFrame"
frame.Parent = gui
frame.BackgroundColor3 = Color3.fromRGB(0,0,0)
frame.BorderSizePixel = 1
frame.BorderColor3 = Color3.fromRGB(100,100,100)
frame.Position = UDim2.new(0.5,-200,0.5,-125)
frame.Size = UDim2.new(0,400,0,250)
frame.Active = true
frame.Draggable = true

corner1.CornerRadius = UDim.new(0,8)
corner1.Parent = frame

title.Name = "TitleLabel"
title.Parent = frame
title.BackgroundColor3 = Color3.fromRGB(20,20,20)
title.BorderSizePixel = 0
title.Size = UDim2.new(1,0,0,40)
title.Text = "Ender Hub Beta is OutDated"
title.TextColor3 = Color3.fromRGB(255,255,255)
title.TextScaled = true
title.Font = Enum.Font.GothamBold
title.TextWrapped = true

corner2.CornerRadius = UDim.new(0,8)
corner2.Parent = title

desc.Name = "DescriptionLabel"
desc.Parent = frame
desc.BackgroundColor3 = Color3.fromRGB(0,0,0)
desc.BorderSizePixel = 0
desc.Size = UDim2.new(0.9,0,0,80)
desc.Position = UDim2.new(0.05,0,0.25,10)
desc.Text = "Hello There!\nPlease Wait For Ender Hub V2\nand join our discord for updates"
desc.TextColor3 = Color3.fromRGB(200,200,200)
desc.TextScaled = true
desc.Font = Enum.Font.Gotham
desc.TextWrapped = true
desc.LineHeight = 1.2

corner3.CornerRadius = UDim.new(0,6)
corner3.Parent = desc

copybtn.Name = "DiscordButton"
copybtn.Parent = frame
copybtn.BackgroundColor3 = Color3.fromRGB(30,30,30)
copybtn.BorderSizePixel = 1
copybtn.BorderColor3 = Color3.fromRGB(100,100,255)
copybtn.Position = UDim2.new(0.5,-125,0.7,0)
copybtn.Size = UDim2.new(0,250,0,40)
copybtn.Text = "Copy Discord to ClipBoard"
copybtn.TextColor3 = Color3.fromRGB(255,255,255)
copybtn.TextScaled = true
copybtn.Font = Enum.Font.GothamBold
copybtn.AutoButtonColor = false

corner4.CornerRadius = UDim.new(0,6)
corner4.Parent = copybtn

closebtn.Name = "CloseButton"
closebtn.Parent = frame
closebtn.BackgroundColor3 = Color3.fromRGB(40,40,40)
closebtn.BorderSizePixel = 1
closebtn.BorderColor3 = Color3.fromRGB(150,150,150)
closebtn.Position = UDim2.new(1,-35,0,5)
closebtn.Size = UDim2.new(0,30,0,30)
closebtn.Text = "X"
closebtn.TextColor3 = Color3.fromRGB(255,255,255)
closebtn.TextScaled = true
closebtn.Font = Enum.Font.GothamBold
closebtn.AutoButtonColor = false

corner5.CornerRadius = UDim.new(0,4)
corner5.Parent = closebtn

local link = "https://discord.gg/sQ2ayu9F"
local ogcolor = copybtn.BackgroundColor3
local ogbcolor = copybtn.BorderColor3

copybtn.MouseButton1Click:Connect(function()
	local s,e = pcall(function()
		setclipboard(link)
	end)
	if s then
		copybtn.Text = "Copied!"
		copybtn.BackgroundColor3 = Color3.fromRGB(20,80,20)
		copybtn.BorderColor3 = Color3.fromRGB(0,255,0)
		task.wait(1.5)
		copybtn.Text = "Copy Discord to ClipBoard"
		copybtn.BackgroundColor3 = ogcolor
		copybtn.BorderColor3 = ogbcolor
	else
		copybtn.Text = "Failed!"
		copybtn.BackgroundColor3 = Color3.fromRGB(80,20,20)
		copybtn.BorderColor3 = Color3.fromRGB(255,0,0)
		task.wait(1.5)
		copybtn.Text = "Copy Discord to ClipBoard"
		copybtn.BackgroundColor3 = ogcolor
		copybtn.BorderColor3 = ogbcolor
	end
end)

closebtn.MouseButton1Click:Connect(function()
	gui:Destroy()
end)

copybtn.MouseEnter:Connect(function()
	copybtn.BackgroundColor3 = Color3.fromRGB(50,50,50)
	copybtn.BorderColor3 = Color3.fromRGB(150,150,255)
end)

copybtn.MouseLeave:Connect(function()
	copybtn.BackgroundColor3 = ogcolor
	copybtn.BorderColor3 = ogbcolor
end)

closebtn.MouseEnter:Connect(function()
	closebtn.BackgroundColor3 = Color3.fromRGB(80,20,20)
	closebtn.BorderColor3 = Color3.fromRGB(255,100,100)
end)

closebtn.MouseLeave:Connect(function()
	closebtn.BackgroundColor3 = Color3.fromRGB(40,40,40)
	closebtn.BorderColor3 = Color3.fromRGB(150,150,150)
end)
