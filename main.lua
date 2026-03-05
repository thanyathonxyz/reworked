--[[
    Fluent Interface Suite - Rework Edition
    Bundled for executor use.
    
    Original Author: dawid
    Rework: Fluent Rework Team
    License: MIT
--]]

-- Bundler Runtime
local __modules = {}
local __cache = {}
local __script_proxies = {}

local function __get_script_proxy(path)
    if __script_proxies[path] then
        return __script_proxies[path]
    end
    
    local proxy = newproxy(true)
    local mt = getmetatable(proxy)
    local children = {}
    
    mt.__index = function(_, key)
        if key == "Parent" then
            local parent_path = path:match("(.+)%.[^.]+$") or "_ROOT_"
            return __get_script_proxy(parent_path)
        end
        
        local child_path
        if path == "_ROOT_" then
            child_path = key
        else
            child_path = path .. "." .. key
        end
        
        return __get_script_proxy(child_path)
    end
    
    mt.__tostring = function()
        return "Script:" .. path
    end
    
    __script_proxies[path] = proxy
    return proxy
end

local function __require(name)
    if __cache[name] ~= nil then
        return __cache[name]
    end
    
    if __modules[name] then
        local result = __modules[name]()
        if result == nil then result = true end
        __cache[name] = result
        return result
    end
    
    -- Try with _ROOT_ prefix fallback
    if not name:find("%.") and __modules["_ROOT_"] then
        error("Module not found: " .. tostring(name))
    end
    
    error("Module not found: " .. tostring(name))
end

-- Override require for script proxy objects
local __old_require = require
require = function(mod)
    if type(mod) == "string" then
        return __old_require(mod)
    end
    
    -- Handle userdata proxy
    if type(mod) == "userdata" then
        for path, proxy in pairs(__script_proxies) do
            if proxy == mod then
                return __require(path)
            end
        end
    end
    
    return __old_require(mod)
end

__modules["Acrylic"] = function()
	local Acrylic = {
		AcrylicBlur = __require("Acrylic.AcrylicBlur"),
		CreateAcrylic = __require("Acrylic.CreateAcrylic"),
		AcrylicPaint = __require("Acrylic.AcrylicPaint"),
	}
	
	function Acrylic.init()
		local baseEffect = Instance.new("DepthOfFieldEffect")
		baseEffect.FarIntensity = 0
		baseEffect.InFocusRadius = 0.1
		baseEffect.NearIntensity = 1
	
		local depthOfFieldDefaults = {}
	
		function Acrylic.Enable()
			for _, effect in pairs(depthOfFieldDefaults) do
				effect.Enabled = false
			end
			baseEffect.Parent = game:GetService("Lighting")
		end
	
		function Acrylic.Disable()
			for _, effect in pairs(depthOfFieldDefaults) do
				effect.Enabled = effect.enabled
			end
			baseEffect.Parent = nil
		end
	
		local function registerDefaults()
			local function register(object)
				if object:IsA("DepthOfFieldEffect") then
					depthOfFieldDefaults[object] = { enabled = object.Enabled }
				end
			end
	
			for _, child in pairs(game:GetService("Lighting"):GetChildren()) do
				register(child)
			end
	
			if game:GetService("Workspace").CurrentCamera then
				for _, child in pairs(game:GetService("Workspace").CurrentCamera:GetChildren()) do
					register(child)
				end
			end
		end
	
		registerDefaults()
		Acrylic.Enable()
	end
	
	return Acrylic
end

__modules["Acrylic.AcrylicBlur"] = function()
	local Creator = __require("Creator")
	local createAcrylic = __require("Acrylic.CreateAcrylic")
	local viewportPointToWorld, getOffset = unpack(__require("Acrylic.Utils"))
	
	local function createAcrylicBlur(distance)
		local cleanups = {}
	
		distance = distance or 0.001
		local positions = {
			topLeft = Vector2.new(),
			topRight = Vector2.new(),
			bottomRight = Vector2.new(),
		}
		local model = createAcrylic()
		model.Parent = workspace
	
		local function updatePositions(size, position)
			positions.topLeft = position
			positions.topRight = position + Vector2.new(size.X, 0)
			positions.bottomRight = position + size
		end
	
		local function render()
			local res = game:GetService("Workspace").CurrentCamera
			if res then
				res = res.CFrame
			end
			local cond = res
			if not cond then
				cond = CFrame.new()
			end
	
			local camera = cond
			local topLeft = positions.topLeft
			local topRight = positions.topRight
			local bottomRight = positions.bottomRight
	
			local topLeft3D = viewportPointToWorld(topLeft, distance)
			local topRight3D = viewportPointToWorld(topRight, distance)
			local bottomRight3D = viewportPointToWorld(bottomRight, distance)
	
			local width = (topRight3D - topLeft3D).Magnitude
			local height = (topRight3D - bottomRight3D).Magnitude
	
			model.CFrame =
				CFrame.fromMatrix((topLeft3D + bottomRight3D) / 2, camera.XVector, camera.YVector, camera.ZVector)
			model.Mesh.Scale = Vector3.new(width, height, 0)
		end
	
		local function onChange(rbx)
			local offset = getOffset()
			local size = rbx.AbsoluteSize - Vector2.new(offset, offset)
			local position = rbx.AbsolutePosition + Vector2.new(offset / 2, offset / 2)
	
			updatePositions(size, position)
			task.spawn(render)
		end
	
		local function renderOnChange()
			local camera = game:GetService("Workspace").CurrentCamera
			if not camera then
				return
			end
	
			table.insert(cleanups, camera:GetPropertyChangedSignal("CFrame"):Connect(render))
			table.insert(cleanups, camera:GetPropertyChangedSignal("ViewportSize"):Connect(render))
			table.insert(cleanups, camera:GetPropertyChangedSignal("FieldOfView"):Connect(render))
			task.spawn(render)
		end
	
		model.Destroying:Connect(function()
			for _, item in cleanups do
				pcall(function()
					item:Disconnect()
				end)
			end
		end)
	
		renderOnChange()
	
		return onChange, model
	end
	
	return function(distance)
		local Blur = {}
		local onChange, model = createAcrylicBlur(distance)
	
		local comp = Creator.New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		})
	
		Creator.AddSignal(comp:GetPropertyChangedSignal("AbsolutePosition"), function()
			onChange(comp)
		end)
	
		Creator.AddSignal(comp:GetPropertyChangedSignal("AbsoluteSize"), function()
			onChange(comp)
		end)
	
		Blur.AddParent = function(Parent)
			Creator.AddSignal(Parent:GetPropertyChangedSignal("Visible"), function()
				Blur.SetVisibility(Parent.Visible)
			end)
		end
	
		Blur.SetVisibility = function(Value)
			model.Transparency = Value and 0.98 or 1
		end
	
		Blur.Frame = comp
		Blur.Model = model
	
		return Blur
	end
end

__modules["Acrylic.AcrylicPaint"] = function()
	-- [Fluent Rework] AcrylicPaint - Enhanced with larger corners and glow effect
	local Creator = __require("Creator")
	local AcrylicBlur = __require("Acrylic.AcrylicBlur")
	
	local New = Creator.New
	
	return function(props)
		local AcrylicPaint = {}
	
		AcrylicPaint.Frame = New("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 0.9,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,
		}, {
			-- Drop shadow (larger, softer, with accent glow)
			New("ImageLabel", {
				Image = "rbxassetid://8992230677",
				ScaleType = "Slice",
				SliceCenter = Rect.new(Vector2.new(99, 99), Vector2.new(99, 99)),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.new(1, 130, 1, 126),
				Position = UDim2.new(0.5, 0, 0.5, 2),
				BackgroundTransparency = 1,
				ImageColor3 = Color3.fromRGB(0, 0, 0),
				ImageTransparency = 0.55,
				Name = "Shadow",
			}),
	
			-- Accent glow (subtle colored shadow)
			New("ImageLabel", {
				Image = "rbxassetid://8992230677",
				ScaleType = "Slice",
				SliceCenter = Rect.new(Vector2.new(99, 99), Vector2.new(99, 99)),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.new(1, 160, 1, 156),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				BackgroundTransparency = 1,
				ImageTransparency = 0.92,
				Name = "Glow",
				ThemeTag = {
					ImageColor3 = "GlowColor",
				},
			}),
	
			-- Main corner (increased from 8 to 10)
			New("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
	
			-- Background fill
			New("Frame", {
				BackgroundTransparency = 0.45,
				Size = UDim2.fromScale(1, 1),
				Name = "Background",
				ThemeTag = {
					BackgroundColor3 = "AcrylicMain",
				},
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 10),
				}),
			}),
	
			-- Gradient overlay
			New("Frame", {
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = 0.4,
				Size = UDim2.fromScale(1, 1),
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 10),
				}),
				New("UIGradient", {
					Rotation = 90,
					ThemeTag = {
						Color = "AcrylicGradient",
					},
				}),
			}),
	
			-- Noise texture 1
			New("ImageLabel", {
				Image = "rbxassetid://9968344105",
				ImageTransparency = 0.98,
				ScaleType = Enum.ScaleType.Tile,
				TileSize = UDim2.new(0, 128, 0, 128),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 10),
				}),
			}),
	
			-- Noise texture 2
			New("ImageLabel", {
				Image = "rbxassetid://9968344227",
				ImageTransparency = 0.9,
				ScaleType = Enum.ScaleType.Tile,
				TileSize = UDim2.new(0, 128, 0, 128),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ThemeTag = {
					ImageTransparency = "AcrylicNoise",
				},
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 10),
				}),
			}),
	
			-- Border stroke
			New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 2,
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 10),
				}),
				New("UIStroke", {
					Transparency = 0.5,
					Thickness = 1.2,
					ThemeTag = {
						Color = "AcrylicBorder",
					},
				}),
			}),
		})
	
		local Blur
	
		if __require("_ROOT_").UseAcrylic then
			Blur = AcrylicBlur()
			Blur.Frame.Parent = AcrylicPaint.Frame
			AcrylicPaint.Model = Blur.Model
			AcrylicPaint.AddParent = Blur.AddParent
			AcrylicPaint.SetVisibility = Blur.SetVisibility
		end
	
		return AcrylicPaint
	end
end

__modules["Acrylic.CreateAcrylic"] = function()
	local Root = __get_script_proxy("_ROOT_")
	local Creator = __require("Creator")
	
	local function createAcrylic()
		local Part = Creator.New("Part", {
			Name = "Body",
			Color = Color3.new(0, 0, 0),
			Material = Enum.Material.Glass,
			Size = Vector3.new(1, 1, 0),
			Anchored = true,
			CanCollide = false,
			Locked = true,
			CastShadow = false,
			Transparency = 0.98,
		}, {
			Creator.New("SpecialMesh", {
				MeshType = Enum.MeshType.Brick,
				Offset = Vector3.new(0, 0, -0.000001),
			}),
		})
	
		return Part
	end
	
	return createAcrylic
end

__modules["Acrylic.Utils"] = function()
	local function map(value, inMin, inMax, outMin, outMax)
		return (value - inMin) * (outMax - outMin) / (inMax - inMin) + outMin
	end
	
	local function viewportPointToWorld(location, distance)
		local unitRay = game:GetService("Workspace").CurrentCamera:ScreenPointToRay(location.X, location.Y)
		return unitRay.Origin + unitRay.Direction * distance
	end
	
	local function getOffset()
		local viewportSizeY = game:GetService("Workspace").CurrentCamera.ViewportSize.Y
		return map(viewportSizeY, 0, 2560, 8, 56)
	end
	
	return { viewportPointToWorld, getOffset }
end

__modules["Components.Assets"] = function()
	return {
		Close = "rbxassetid://9886659671",
		Min = "rbxassetid://9886659276",
		Max = "rbxassetid://9886659406",
		Restore = "rbxassetid://9886659001",
	}
end

__modules["Components.Button"] = function()
	local Root = __get_script_proxy("_ROOT_")
	local Flipper = __require("Packages.Flipper")
	local Creator = __require("Creator")
	local New = Creator.New
	
	local Spring = Flipper.Spring.new
	
	return function(Theme, Parent, DialogCheck)
		DialogCheck = DialogCheck or false
		local Button = {}
	
		Button.Title = New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
			TextColor3 = Color3.fromRGB(200, 200, 200),
			TextSize = 14,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ThemeTag = {
				TextColor3 = "Text",
			},
		})
	
		Button.HoverFrame = New("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ThemeTag = {
				BackgroundColor3 = "Hover",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		})
	
		Button.Frame = New("TextButton", {
			Size = UDim2.new(0, 0, 0, 32),
			Parent = Parent,
			ThemeTag = {
				BackgroundColor3 = "DialogButton",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			New("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Transparency = 0.65,
				ThemeTag = {
					Color = "DialogButtonBorder",
				},
			}),
			Button.HoverFrame,
			Button.Title,
		})
	
		local Motor, SetTransparency = Creator.SpringMotor(1, Button.HoverFrame, "BackgroundTransparency", DialogCheck)
		Creator.AddSignal(Button.Frame.MouseEnter, function()
			SetTransparency(0.97)
		end)
		Creator.AddSignal(Button.Frame.MouseLeave, function()
			SetTransparency(1)
		end)
		Creator.AddSignal(Button.Frame.MouseButton1Down, function()
			SetTransparency(1)
		end)
		Creator.AddSignal(Button.Frame.MouseButton1Up, function()
			SetTransparency(0.97)
		end)
	
		return Button
	end
end

__modules["Components.Dialog"] = function()
	local UserInputService = game:GetService("UserInputService")
	local Mouse = game:GetService("Players").LocalPlayer:GetMouse()
	local Camera = game:GetService("Workspace").CurrentCamera
	
	local Root = __get_script_proxy("_ROOT_")
	local Flipper = __require("Packages.Flipper")
	local Creator = __require("Creator")
	
	local Spring = Flipper.Spring.new
	local Instant = Flipper.Instant.new
	local New = Creator.New
	
	local Dialog = {
		Window = nil,
	}
	
	function Dialog:Init(Window)
		Dialog.Window = Window
		return Dialog
	end
	
	function Dialog:Create()
		local NewDialog = {
			Buttons = 0,
		}
	
		NewDialog.TintFrame = New("TextButton", {
			Text = "",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 1,
			Parent = Dialog.Window.Root,
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
		})
	
		local TintMotor, TintTransparency = Creator.SpringMotor(1, NewDialog.TintFrame, "BackgroundTransparency", true)
	
		NewDialog.ButtonHolder = New("Frame", {
			Size = UDim2.new(1, -40, 1, -40),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
		}, {
			New("UIListLayout", {
				Padding = UDim.new(0, 10),
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
	
		NewDialog.ButtonHolderFrame = New("Frame", {
			Size = UDim2.new(1, 0, 0, 70),
			Position = UDim2.new(0, 0, 1, -70),
			ThemeTag = {
				BackgroundColor3 = "DialogHolder",
			},
		}, {
			New("Frame", {
				Size = UDim2.new(1, 0, 0, 1),
				ThemeTag = {
					BackgroundColor3 = "DialogHolderLine",
				},
			}),
			NewDialog.ButtonHolder,
		})
	
		NewDialog.Title = New("TextLabel", {
			FontFace = Font.new(
				"rbxasset://fonts/families/GothamSSm.json",
				Enum.FontWeight.SemiBold,
				Enum.FontStyle.Normal
			),
			Text = "Dialog",
			TextColor3 = Color3.fromRGB(240, 240, 240),
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(20, 25),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			ThemeTag = {
				TextColor3 = "Text",
			},
		})
	
		NewDialog.Scale = New("UIScale", {
			Scale = 1,
		})
	
		local ScaleMotor, Scale = Creator.SpringMotor(1.1, NewDialog.Scale, "Scale")
	
		NewDialog.Root = New("CanvasGroup", {
			Size = UDim2.fromOffset(300, 165),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			GroupTransparency = 1,
			Parent = NewDialog.TintFrame,
			ThemeTag = {
				BackgroundColor3 = "Dialog",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			New("UIStroke", {
				Transparency = 0.5,
				ThemeTag = {
					Color = "DialogBorder",
				},
			}),
			NewDialog.Scale,
			NewDialog.Title,
			NewDialog.ButtonHolderFrame,
		})
	
		local RootMotor, RootTransparency = Creator.SpringMotor(1, NewDialog.Root, "GroupTransparency")
	
		function NewDialog:Open()
			__require("_ROOT_").DialogOpen = true
			NewDialog.Scale.Scale = 1.1
			TintTransparency(0.75)
			RootTransparency(0)
			Scale(1)
		end
	
		function NewDialog:Close()
			__require("_ROOT_").DialogOpen = false
			TintTransparency(1)
			RootTransparency(1)
			Scale(1.1)
			NewDialog.Root.UIStroke:Destroy()
			task.wait(0.15)
			NewDialog.TintFrame:Destroy()
		end
	
		function NewDialog:Button(Title, Callback)
			NewDialog.Buttons = NewDialog.Buttons + 1
			Title = Title or "Button"
			Callback = Callback or function() end
	
			local Button = __require("Components.Button")("", NewDialog.ButtonHolder, true)
			Button.Title.Text = Title
	
			for _, Btn in next, NewDialog.ButtonHolder:GetChildren() do
				if Btn:IsA("TextButton") then
					Btn.Size =
						UDim2.new(1 / NewDialog.Buttons, -(((NewDialog.Buttons - 1) * 10) / NewDialog.Buttons), 0, 32)
				end
			end
	
			Creator.AddSignal(Button.Frame.MouseButton1Click, function()
				__require("_ROOT_"):SafeCallback(Callback)
				pcall(function()
					NewDialog:Close()
				end)
			end)
	
			return Button
		end
	
		return NewDialog
	end
	
	return Dialog
end

__modules["Components.Element"] = function()
	-- [Fluent Rework] Element Base - Phase 2 Redesigned
	local Root = __get_script_proxy("_ROOT_")
	local Flipper = __require("Packages.Flipper")
	local Creator = __require("Creator")
	local New = Creator.New
	
	local Spring = Flipper.Spring.new
	
	return function(Title, Desc, Parent, Hover)
		local Element = {}
	
		Element.TitleLabel = New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
			Text = Title,
			TextColor3 = Color3.fromRGB(240, 240, 240),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			ThemeTag = {
				TextColor3 = "Text",
			},
		})
	
		Element.DescLabel = New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
			Text = Desc,
			TextColor3 = Color3.fromRGB(200, 200, 200),
			TextSize = 11,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 14),
			ThemeTag = {
				TextColor3 = "SubText",
			},
		})
	
		Element.LabelHolder = New("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -28, 0, 0),
		}, {
			New("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 1),
			}),
			New("UIPadding", {
				PaddingBottom = UDim.new(0, 12),
				PaddingTop = UDim.new(0, 12),
			}),
			Element.TitleLabel,
			Element.DescLabel,
		})
	
		Element.Border = New("UIStroke", {
			Transparency = 0.6,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Color3.fromRGB(0, 0, 0),
			ThemeTag = {
				Color = "ElementBorder",
			},
		})
	
		Element.Frame = New("TextButton", {
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 0.89,
			BackgroundColor3 = Color3.fromRGB(130, 130, 130),
			Parent = Parent,
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = "",
			LayoutOrder = 7,
			ThemeTag = {
				BackgroundColor3 = "Element",
				BackgroundTransparency = "ElementTransparency",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 6),
			}),
			Element.Border,
			Element.LabelHolder,
		})
	
		function Element:SetTitle(Set)
			Element.TitleLabel.Text = Set
		end
	
		function Element:SetDesc(Set)
			if Set == nil then
				Set = ""
			end
			if Set == "" then
				Element.DescLabel.Visible = false
			else
				Element.DescLabel.Visible = true
			end
			Element.DescLabel.Text = Set
		end
	
		function Element:Destroy()
			Element.Frame:Destroy()
		end
	
		Element:SetTitle(Title)
		Element:SetDesc(Desc)
	
		if Hover then
			local Themes = Root.Themes
			local Motor, SetTransparency = Creator.SpringMotor(
				Creator.GetThemeProperty("ElementTransparency"),
				Element.Frame,
				"BackgroundTransparency",
				false,
				true
			)
	
			Creator.AddSignal(Element.Frame.MouseEnter, function()
				SetTransparency(Creator.GetThemeProperty("ElementTransparency") - Creator.GetThemeProperty("HoverChange"))
			end)
			Creator.AddSignal(Element.Frame.MouseLeave, function()
				SetTransparency(Creator.GetThemeProperty("ElementTransparency"))
			end)
			Creator.AddSignal(Element.Frame.MouseButton1Down, function()
				SetTransparency(Creator.GetThemeProperty("ElementTransparency") + Creator.GetThemeProperty("HoverChange"))
			end)
			Creator.AddSignal(Element.Frame.MouseButton1Up, function()
				SetTransparency(Creator.GetThemeProperty("ElementTransparency") - Creator.GetThemeProperty("HoverChange"))
			end)
		end
	
		return Element
	end
end

__modules["Components.Notification"] = function()
	local Root = __get_script_proxy("_ROOT_")
	local Flipper = __require("Packages.Flipper")
	local Creator = __require("Creator")
	local Acrylic = __require("Acrylic")
	
	local Spring = Flipper.Spring.new
	local Instant = Flipper.Instant.new
	local New = Creator.New
	
	local Notification = {}
	
	function Notification:Init(GUI)
		Notification.Holder = New("Frame", {
			Position = UDim2.new(1, -30, 1, -30),
			Size = UDim2.new(0, 310, 1, -30),
			AnchorPoint = Vector2.new(1, 1),
			BackgroundTransparency = 1,
			Parent = GUI,
		}, {
			New("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				Padding = UDim.new(0, 20),
			}),
		})
	end
	
	function Notification:New(Config)
		Config.Title = Config.Title or "Title"
		Config.Content = Config.Content or "Content"
		Config.SubContent = Config.SubContent or ""
		Config.Duration = Config.Duration or nil
		Config.Buttons = Config.Buttons or {}
		local NewNotification = {
			Closed = false,
		}
	
		NewNotification.AcrylicPaint = Acrylic.AcrylicPaint()
	
		NewNotification.Title = New("TextLabel", {
			Position = UDim2.new(0, 14, 0, 17),
			Text = Config.Title,
			RichText = true,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextTransparency = 0,
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
			TextSize = 13,
			TextXAlignment = "Left",
			TextYAlignment = "Center",
			Size = UDim2.new(1, -12, 0, 12),
			TextWrapped = true,
			BackgroundTransparency = 1,
			ThemeTag = {
				TextColor3 = "Text",
			},
		})
	
		NewNotification.ContentLabel = New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
			Text = Config.Content,
			TextColor3 = Color3.fromRGB(240, 240, 240),
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			TextWrapped = true,
			ThemeTag = {
				TextColor3 = "Text",
			},
		})
	
		NewNotification.SubContentLabel = New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
			Text = Config.SubContent,
			TextColor3 = Color3.fromRGB(240, 240, 240),
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			TextWrapped = true,
			ThemeTag = {
				TextColor3 = "SubText",
			},
		})
	
		NewNotification.LabelHolder = New("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 40),
			Size = UDim2.new(1, -28, 0, 0),
		}, {
			New("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 3),
			}),
			NewNotification.ContentLabel,
			NewNotification.SubContentLabel,
		})
	
		NewNotification.CloseButton = New("TextButton", {
			Text = "",
			Position = UDim2.new(1, -14, 0, 13),
			Size = UDim2.fromOffset(20, 20),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
		}, {
			New("ImageLabel", {
				Image = __require("Components.Assets").Close,
				Size = UDim2.fromOffset(16, 16),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				ThemeTag = {
					ImageColor3 = "Text",
				},
			}),
		})
	
		NewNotification.Root = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			Position = UDim2.fromScale(1, 0),
		}, {
			NewNotification.AcrylicPaint.Frame,
			NewNotification.Title,
			NewNotification.CloseButton,
			NewNotification.LabelHolder,
		})
	
		if Config.Content == "" then
			NewNotification.ContentLabel.Visible = false
		end
	
		if Config.SubContent == "" then
			NewNotification.SubContentLabel.Visible = false
		end
	
		NewNotification.Holder = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 200),
			Parent = Notification.Holder,
		}, {
			NewNotification.Root,
		})
	
		local RootMotor = Flipper.GroupMotor.new({
			Scale = 1,
			Offset = 60,
		})
	
		RootMotor:onStep(function(Values)
			NewNotification.Root.Position = UDim2.new(Values.Scale, Values.Offset, 0, 0)
		end)
	
		Creator.AddSignal(NewNotification.CloseButton.MouseButton1Click, function()
			NewNotification:Close()
		end)
	
		function NewNotification:Open()
			local ContentSize = NewNotification.LabelHolder.AbsoluteSize.Y
			NewNotification.Holder.Size = UDim2.new(1, 0, 0, 58 + ContentSize)
	
			RootMotor:setGoal({
				Scale = Spring(0, { frequency = 5 }),
				Offset = Spring(0, { frequency = 5 }),
			})
		end
	
		function NewNotification:Close()
			if not NewNotification.Closed then
				NewNotification.Closed = true
				task.spawn(function()
					RootMotor:setGoal({
						Scale = Spring(1, { frequency = 5 }),
						Offset = Spring(60, { frequency = 5 }),
					})
					task.wait(0.4)
					if __require("_ROOT_").UseAcrylic then
						NewNotification.AcrylicPaint.Model:Destroy()
					end
					NewNotification.Holder:Destroy()
				end)
			end
		end
	
		NewNotification:Open()
		if Config.Duration then
			task.delay(Config.Duration, function()
				NewNotification:Close()
			end)
		end
		return NewNotification
	end
	
	return Notification
end

__modules["Components.Section"] = function()
	-- [Fluent Rework] Section - Phase 2 Redesigned
	local Root = __get_script_proxy("_ROOT_")
	local Creator = __require("Creator")
	
	local New = Creator.New
	
	return function(Title, Parent)
		local Section = {}
	
		Section.Layout = New("UIListLayout", {
			Padding = UDim.new(0, 4),
		})
	
		Section.Container = New("Frame", {
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.fromOffset(0, 28),
			BackgroundTransparency = 1,
		}, {
			Section.Layout,
		})
	
		Section.Root = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = 7,
			Parent = Parent,
		}, {
			-- Section header with accent line
			New("Frame", {
				Size = UDim2.new(0, 3, 0, 14),
				Position = UDim2.fromOffset(0, 5),
				BackgroundTransparency = 0,
				ThemeTag = {
					BackgroundColor3 = "Accent",
				},
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 2),
				}),
			}),
			New("TextLabel", {
				RichText = true,
				Text = Title,
				TextTransparency = 0,
				FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),
				TextSize = 16,
				TextXAlignment = "Left",
				TextYAlignment = "Center",
				Size = UDim2.new(1, -16, 0, 18),
				Position = UDim2.fromOffset(10, 2),
				ThemeTag = {
					TextColor3 = "Text",
				},
			}),
			Section.Container,
		})
	
		Creator.AddSignal(Section.Layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
			Section.Container.Size = UDim2.new(1, 0, 0, Section.Layout.AbsoluteContentSize.Y)
			Section.Root.Size = UDim2.new(1, 0, 0, Section.Layout.AbsoluteContentSize.Y + 30)
		end)
		return Section
	end
end

__modules["Components.Tab"] = function()
	-- [Fluent Rework] Tab - Phase 2 Redesigned
	local Root = __get_script_proxy("_ROOT_")
	local Flipper = __require("Packages.Flipper")
	local Creator = __require("Creator")
	
	local New = Creator.New
	local Spring = Flipper.Spring.new
	local Instant = Flipper.Instant.new
	local Components = Root.Components
	
	local TabModule = {
		Window = nil,
		Tabs = {},
		Containers = {},
		SelectedTab = 0,
		TabCount = 0,
	}
	
	function TabModule:Init(Window)
		TabModule.Window = Window
		return TabModule
	end
	
	function TabModule:GetCurrentTabPos()
		local TabHolderPos = TabModule.Window.TabHolder.AbsolutePosition.Y
		local TabPos = TabModule.Tabs[TabModule.SelectedTab].Frame.AbsolutePosition.Y
	
		return TabPos - TabHolderPos
	end
	
	function TabModule:New(Title, Icon, Parent)
		local Library = __require("_ROOT_")
		local Window = TabModule.Window
		local Elements = Library.Elements
	
		TabModule.TabCount = TabModule.TabCount + 1
		local TabIndex = TabModule.TabCount
	
		local Tab = {
			Selected = false,
			Name = Title,
			Type = "Tab",
		}
	
		if Library:GetIcon(Icon) then
			Icon = Library:GetIcon(Icon)
		end
	
		if Icon == "" or nil then
			Icon = nil
		end
	
		-- Tab button with improved styling
		Tab.Frame = New("TextButton", {
			Size = UDim2.new(1, 0, 0, 32),
			BackgroundTransparency = 1,
			Parent = Parent,
			ThemeTag = {
				BackgroundColor3 = "Tab",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 7),
			}),
			New("TextLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = Icon and UDim2.new(0, 30, 0.5, 0) or UDim2.new(0, 10, 0.5, 0),
				Text = Title,
				RichText = true,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextTransparency = 0,
				FontFace = Font.new(
					"rbxasset://fonts/families/GothamSSm.json",
					Enum.FontWeight.Regular,
					Enum.FontStyle.Normal
				),
				TextSize = 12,
				TextXAlignment = "Left",
				TextYAlignment = "Center",
				Size = UDim2.new(1, -12, 1, 0),
				BackgroundTransparency = 1,
				ThemeTag = {
					TextColor3 = "Text",
				},
			}),
			New("ImageLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				Size = UDim2.fromOffset(15, 15),
				Position = UDim2.new(0, 8, 0.5, 0),
				BackgroundTransparency = 1,
				Image = Icon and Icon or nil,
				ThemeTag = {
					ImageColor3 = "Text",
				},
			}),
		})
	
		-- Content container for this tab
		local ContainerLayout = New("UIListLayout", {
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
	
		Tab.ContainerFrame = New("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = Window.ContainerHolder,
			Visible = false,
			BottomImage = "rbxassetid://6889812791",
			MidImage = "rbxassetid://6889812721",
			TopImage = "rbxassetid://6276641225",
			ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255),
			ScrollBarImageTransparency = 0.93,
			ScrollBarThickness = 2,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromScale(0, 0),
			ScrollingDirection = Enum.ScrollingDirection.Y,
		}, {
			ContainerLayout,
			New("UIPadding", {
				PaddingRight = UDim.new(0, 8),
				PaddingLeft = UDim.new(0, 1),
				PaddingTop = UDim.new(0, 1),
				PaddingBottom = UDim.new(0, 1),
			}),
		})
	
		Creator.AddSignal(ContainerLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
			Tab.ContainerFrame.CanvasSize = UDim2.new(0, 0, 0, ContainerLayout.AbsoluteContentSize.Y + 2)
		end)
	
		-- Hover/Click animations
		Tab.Motor, Tab.SetTransparency = Creator.SpringMotor(1, Tab.Frame, "BackgroundTransparency")
	
		Creator.AddSignal(Tab.Frame.MouseEnter, function()
			Tab.SetTransparency(Tab.Selected and 0.85 or 0.9)
		end)
		Creator.AddSignal(Tab.Frame.MouseLeave, function()
			Tab.SetTransparency(Tab.Selected and 0.88 or 1)
		end)
		Creator.AddSignal(Tab.Frame.MouseButton1Down, function()
			Tab.SetTransparency(0.93)
		end)
		Creator.AddSignal(Tab.Frame.MouseButton1Up, function()
			Tab.SetTransparency(Tab.Selected and 0.85 or 0.9)
		end)
		Creator.AddSignal(Tab.Frame.MouseButton1Click, function()
			TabModule:SelectTab(TabIndex)
		end)
	
		TabModule.Containers[TabIndex] = Tab.ContainerFrame
		TabModule.Tabs[TabIndex] = Tab
	
		Tab.Container = Tab.ContainerFrame
		Tab.ScrollFrame = Tab.Container
	
		function Tab:AddSection(SectionTitle)
			local Section = { Type = "Section" }
	
			local SectionFrame = require(Components.Section)(SectionTitle, Tab.Container)
			Section.Container = SectionFrame.Container
			Section.ScrollFrame = Tab.Container
	
			setmetatable(Section, Elements)
			return Section
		end
	
		setmetatable(Tab, Elements)
		return Tab
	end
	
	function TabModule:SelectTab(Tab)
		local Window = TabModule.Window
	
		TabModule.SelectedTab = Tab
	
		for _, TabObject in next, TabModule.Tabs do
			TabObject.SetTransparency(1)
			TabObject.Selected = false
		end
		TabModule.Tabs[Tab].SetTransparency(0.88)
		TabModule.Tabs[Tab].Selected = true
	
		Window.TabDisplay.Text = TabModule.Tabs[Tab].Name
		Window.SelectorPosMotor:setGoal(Spring(TabModule:GetCurrentTabPos(), { frequency = 7 }))
	
		-- Tab transition with smoother animation
		task.spawn(function()
			Window.ContainerPosMotor:setGoal(Spring(108, { frequency = 9 }))
			Window.ContainerBackMotor:setGoal(Spring(1, { frequency = 9 }))
			task.wait(0.12)
			for _, Container in next, TabModule.Containers do
				Container.Visible = false
			end
			TabModule.Containers[Tab].Visible = true
			Window.ContainerPosMotor:setGoal(Spring(88, { frequency = 6 }))
			Window.ContainerBackMotor:setGoal(Spring(0, { frequency = 7 }))
		end)
	end
	
	return TabModule
end

__modules["Components.Textbox"] = function()
	local TextService = game:GetService("TextService")
	local Root = __get_script_proxy("_ROOT_")
	local Flipper = __require("Packages.Flipper")
	local Creator = __require("Creator")
	local New = Creator.New
	
	return function(Parent, Acrylic)
		Acrylic = Acrylic or false
		local Textbox = {}
	
		Textbox.Input = New("TextBox", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
			TextColor3 = Color3.fromRGB(200, 200, 200),
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(10, 0),
			ThemeTag = {
				TextColor3 = "Text",
				PlaceholderColor3 = "SubText",
			},
		})
	
		Textbox.Container = New("Frame", {
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Position = UDim2.new(0, 6, 0, 0),
			Size = UDim2.new(1, -12, 1, 0),
		}, {
			Textbox.Input,
		})
	
		Textbox.Indicator = New("Frame", {
			Size = UDim2.new(1, -4, 0, 1),
			Position = UDim2.new(0, 2, 1, 0),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = Acrylic and 0.5 or 0,
			ThemeTag = {
				BackgroundColor3 = Acrylic and "InputIndicator" or "DialogInputLine",
			},
		})
	
		Textbox.Frame = New("Frame", {
			Size = UDim2.new(0, 0, 0, 30),
			BackgroundTransparency = Acrylic and 0.9 or 0,
			Parent = Parent,
			ThemeTag = {
				BackgroundColor3 = Acrylic and "Input" or "DialogInput",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			New("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Transparency = Acrylic and 0.5 or 0.65,
				ThemeTag = {
					Color = Acrylic and "InElementBorder" or "DialogButtonBorder",
				},
			}),
			Textbox.Indicator,
			Textbox.Container,
		})
	
		local function Update()
			local PADDING = 2
			local Reveal = Textbox.Container.AbsoluteSize.X
	
			if not Textbox.Input:IsFocused() or Textbox.Input.TextBounds.X <= Reveal - 2 * PADDING then
				Textbox.Input.Position = UDim2.new(0, PADDING, 0, 0)
			else
				local Cursor = Textbox.Input.CursorPosition
				if Cursor ~= -1 then
					local subtext = string.sub(Textbox.Input.Text, 1, Cursor - 1)
					local width = TextService:GetTextSize(
						subtext,
						Textbox.Input.TextSize,
						Textbox.Input.Font,
						Vector2.new(math.huge, math.huge)
					).X
	
					local CurrentCursorPos = Textbox.Input.Position.X.Offset + width
					if CurrentCursorPos < PADDING then
						Textbox.Input.Position = UDim2.fromOffset(PADDING - width, 0)
					elseif CurrentCursorPos > Reveal - PADDING - 1 then
						Textbox.Input.Position = UDim2.fromOffset(Reveal - width - PADDING - 1, 0)
					end
				end
			end
		end
	
		task.spawn(Update)
	
		Creator.AddSignal(Textbox.Input:GetPropertyChangedSignal("Text"), Update)
		Creator.AddSignal(Textbox.Input:GetPropertyChangedSignal("CursorPosition"), Update)
	
		Creator.AddSignal(Textbox.Input.Focused, function()
			Update()
			Textbox.Indicator.Size = UDim2.new(1, -2, 0, 2)
			Textbox.Indicator.Position = UDim2.new(0, 1, 1, 0)
			Textbox.Indicator.BackgroundTransparency = 0
			Creator.OverrideTag(Textbox.Frame, { BackgroundColor3 = Acrylic and "InputFocused" or "DialogHolder" })
			Creator.OverrideTag(Textbox.Indicator, { BackgroundColor3 = "Accent" })
		end)
	
		Creator.AddSignal(Textbox.Input.FocusLost, function()
			Update()
			Textbox.Indicator.Size = UDim2.new(1, -4, 0, 1)
			Textbox.Indicator.Position = UDim2.new(0, 2, 1, 0)
			Textbox.Indicator.BackgroundTransparency = 0.5
			Creator.OverrideTag(Textbox.Frame, { BackgroundColor3 = Acrylic and "Input" or "DialogInput" })
			Creator.OverrideTag(Textbox.Indicator, { BackgroundColor3 = Acrylic and "InputIndicator" or "DialogInputLine" })
		end)
	
		return Textbox
	end
end

__modules["Components.TitleBar"] = function()
	-- [Fluent Rework] TitleBar - Phase 2 Redesigned
	local Root = __get_script_proxy("_ROOT_")
	local Assets = __require("Components.Assets")
	local Creator = __require("Creator")
	local Flipper = __require("Packages.Flipper")
	
	local New = Creator.New
	local AddSignal = Creator.AddSignal
	
	return function(Config)
		local TitleBar = {}
	
		local Library = __require("_ROOT_")
	
		local function BarButton(Icon, Pos, Parent, Callback)
			local Button = {
				Callback = Callback or function() end,
			}
	
			Button.Frame = New("TextButton", {
				Size = UDim2.new(0, 30, 0, 30),
				AnchorPoint = Vector2.new(1, 0.5),
				BackgroundTransparency = 1,
				Parent = Parent,
				Position = Pos,
				Text = "",
				ThemeTag = {
					BackgroundColor3 = "Text",
				},
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 8),
				}),
				New("ImageLabel", {
					Image = Icon,
					Size = UDim2.fromOffset(14, 14),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Name = "Icon",
					ThemeTag = {
						ImageColor3 = "Text",
					},
				}),
			})
	
			local Motor, SetTransparency = Creator.SpringMotor(1, Button.Frame, "BackgroundTransparency")
	
			AddSignal(Button.Frame.MouseEnter, function()
				SetTransparency(0.92)
			end)
			AddSignal(Button.Frame.MouseLeave, function()
				SetTransparency(1, true)
			end)
			AddSignal(Button.Frame.MouseButton1Down, function()
				SetTransparency(0.95)
			end)
			AddSignal(Button.Frame.MouseButton1Up, function()
				SetTransparency(0.92)
			end)
			AddSignal(Button.Frame.MouseButton1Click, Button.Callback)
	
			Button.SetCallback = function(Func)
				Button.Callback = Func
			end
	
			return Button
		end
	
		TitleBar.Frame = New("Frame", {
			Size = UDim2.new(1, 0, 0, 46),
			BackgroundTransparency = 1,
			Parent = Config.Parent,
		}, {
			-- Title + Subtitle container
			New("Frame", {
				Size = UDim2.new(1, -16, 1, 0),
				Position = UDim2.new(0, 18, 0, 0),
				BackgroundTransparency = 1,
			}, {
				New("UIListLayout", {
					Padding = UDim.new(0, 6),
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Center,
				}),
				-- Main title (slightly larger, bolder)
				New("TextLabel", {
					RichText = true,
					Text = Config.Title,
					FontFace = Font.new(
						"rbxasset://fonts/families/GothamSSm.json",
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					),
					TextSize = 13,
					TextXAlignment = "Left",
					TextYAlignment = "Center",
					Size = UDim2.fromScale(0, 1),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					ThemeTag = {
						TextColor3 = "Text",
					},
				}),
				-- Subtitle (with accent-colored dot separator)
				New("TextLabel", {
					RichText = true,
					Text = "·",
					TextTransparency = 0.3,
					FontFace = Font.new(
						"rbxasset://fonts/families/GothamSSm.json",
						Enum.FontWeight.Bold,
						Enum.FontStyle.Normal
					),
					TextSize = 16,
					TextXAlignment = "Left",
					TextYAlignment = "Center",
					Size = UDim2.fromScale(0, 1),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					ThemeTag = {
						TextColor3 = "Accent",
					},
				}),
				New("TextLabel", {
					RichText = true,
					Text = Config.SubTitle,
					TextTransparency = 0.4,
					FontFace = Font.new(
						"rbxasset://fonts/families/GothamSSm.json",
						Enum.FontWeight.Regular,
						Enum.FontStyle.Normal
					),
					TextSize = 12,
					TextXAlignment = "Left",
					TextYAlignment = "Center",
					Size = UDim2.fromScale(0, 1),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					ThemeTag = {
						TextColor3 = "SubText",
					},
				}),
			}),
			-- Bottom divider line
			New("Frame", {
				BackgroundTransparency = 0.5,
				Size = UDim2.new(1, 0, 0, 1),
				Position = UDim2.new(0, 0, 1, 0),
				ThemeTag = {
					BackgroundColor3 = "TitleBarLine",
				},
			}),
		})
	
		-- Window control buttons (right aligned, centered vertically)
		TitleBar.CloseButton = BarButton(Assets.Close, UDim2.new(1, -8, 0.5, 0), TitleBar.Frame, function()
			Library.Window:Dialog({
				Title = "Close",
				Content = "Are you sure you want to unload the interface?",
				Buttons = {
					{
						Title = "Yes",
						Callback = function()
							Library:Destroy()
						end,
					},
					{
						Title = "No",
					},
				},
			})
		end)
		TitleBar.MaxButton = BarButton(Assets.Max, UDim2.new(1, -42, 0.5, 0), TitleBar.Frame, function()
			Config.Window.Maximize(not Config.Window.Maximized)
		end)
		TitleBar.MinButton = BarButton(Assets.Min, UDim2.new(1, -76, 0.5, 0), TitleBar.Frame, function()
			Library.Window:Minimize()
		end)
	
		return TitleBar
	end
end

__modules["Components.Window"] = function()
	-- [Fluent Rework] Window component - Phase 2 Redesigned
	local UserInputService = game:GetService("UserInputService")
	local Mouse = game:GetService("Players").LocalPlayer:GetMouse()
	local Camera = game:GetService("Workspace").CurrentCamera
	
	local Root = __get_script_proxy("_ROOT_")
	local Flipper = __require("Packages.Flipper")
	local Creator = __require("Creator")
	local Acrylic = __require("Acrylic")
	local Assets = __require("Components.Assets")
	local Components = script.Parent
	
	local Spring = Flipper.Spring.new
	local Instant = Flipper.Instant.new
	local New = Creator.New
	
	return function(Config)
		local Library = __require("_ROOT_")
	
		local Window = {
			Minimized = false,
			Maximized = false,
			Size = Config.Size,
			CurrentPos = 0,
			Position = UDim2.fromOffset(
				Camera.ViewportSize.X / 2 - Config.Size.X.Offset / 2,
				Camera.ViewportSize.Y / 2 - Config.Size.Y.Offset / 2
			),
		}
	
		local Dragging, DragInput, MousePos, StartPos = false
		local Resizing, ResizePos = false
		local MinimizeNotif = false
	
		Window.AcrylicPaint = Acrylic.AcrylicPaint()
	
		-- Tab indicator (accent colored bar on left side of selected tab)
		local Selector = New("Frame", {
			Size = UDim2.fromOffset(3, 0),
			BackgroundColor3 = Color3.fromRGB(76, 194, 255),
			Position = UDim2.fromOffset(0, 17),
			AnchorPoint = Vector2.new(0, 0.5),
			ThemeTag = {
				BackgroundColor3 = "SelectedTabIndicator",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 2),
			}),
		})
	
		local ResizeStartFrame = New("Frame", {
			Size = UDim2.fromOffset(20, 20),
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -20, 1, -20),
		})
	
		-- Tab scrolling container
		Window.TabHolder = New("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ScrollBarImageTransparency = 1,
			ScrollBarThickness = 0,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromScale(0, 0),
			ScrollingDirection = Enum.ScrollingDirection.Y,
		}, {
			New("UIListLayout", {
				Padding = UDim.new(0, 3),
			}),
		})
	
		-- Sidebar frame (tab list area)
		local TabFrame = New("Frame", {
			Size = UDim2.new(0, Config.TabWidth, 1, -76),
			Position = UDim2.new(0, 14, 0, 52),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
		}, {
			Window.TabHolder,
			Selector,
		})
	
		-- Vertical divider between sidebar and content
		local SidebarDivider = New("Frame", {
			Size = UDim2.new(0, 1, 1, -90),
			Position = UDim2.new(0, Config.TabWidth + 18, 0, 48),
			BackgroundTransparency = 0.5,
			ThemeTag = {
				BackgroundColor3 = "SidebarDivider",
			},
		})
	
		-- Current tab display title (in content area)
		Window.TabDisplay = New("TextLabel", {
			RichText = true,
			Text = "Tab",
			TextTransparency = 0,
			FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),
			TextSize = 26,
			TextXAlignment = "Left",
			TextYAlignment = "Center",
			Size = UDim2.new(1, -16, 0, 26),
			Position = UDim2.fromOffset(Config.TabWidth + 30, 54),
			BackgroundTransparency = 1,
			ThemeTag = {
				TextColor3 = "Text",
			},
		})
	
		-- Content container (holds the tab content)
		Window.ContainerHolder = New("CanvasGroup", {
			Size = UDim2.new(1, -Config.TabWidth - 36, 1, -114),
			Position = UDim2.fromOffset(Config.TabWidth + 30, 88),
			BackgroundTransparency = 1,
		})
	
		-- Status bar at bottom
		local StatusBarLabel = New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
			Text = "Fluent Rework v" .. Library.Version,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -20, 1, 0),
			Position = UDim2.fromOffset(14, 0),
			BackgroundTransparency = 1,
			ThemeTag = {
				TextColor3 = "StatusBarText",
			},
		})
	
		local StatusBar = New("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			Position = UDim2.new(0, 0, 1, -24),
			BackgroundTransparency = 0.5,
			ThemeTag = {
				BackgroundColor3 = "StatusBar",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 0),
			}),
			StatusBarLabel,
		})
	
		-- Main window root
		Window.Root = New("Frame", {
			BackgroundTransparency = 1,
			Size = Window.Size,
			Position = Window.Position,
			Parent = Config.Parent,
			Active = true,
		}, {
			Window.AcrylicPaint.Frame,
			Window.TabDisplay,
			Window.ContainerHolder,
			TabFrame,
			SidebarDivider,
			StatusBar,
			ResizeStartFrame,
		})
	
		-- TitleBar
		Window.TitleBar = __require("Components.TitleBar")({
			Title = Config.Title,
			SubTitle = Config.SubTitle,
			Parent = Window.Root,
			Window = Window,
		})
	
		if Library.UseAcrylic then
			Window.AcrylicPaint.AddParent(Window.Root)
		end
	
		-- Size + Position Motors
		local SizeMotor = Flipper.GroupMotor.new({
			X = Window.Size.X.Offset,
			Y = Window.Size.Y.Offset,
		})
	
		local PosMotor = Flipper.GroupMotor.new({
			X = Window.Position.X.Offset,
			Y = Window.Position.Y.Offset,
		})
	
		Window.SelectorPosMotor = Flipper.SingleMotor.new(17)
		Window.SelectorSizeMotor = Flipper.SingleMotor.new(0)
		Window.ContainerBackMotor = Flipper.SingleMotor.new(0)
		Window.ContainerPosMotor = Flipper.SingleMotor.new(94)
	
		SizeMotor:onStep(function(values)
			Window.Root.Size = UDim2.new(0, values.X, 0, values.Y)
		end)
	
		PosMotor:onStep(function(values)
			Window.Root.Position = UDim2.new(0, values.X, 0, values.Y)
		end)
	
		local LastValue = 0
		local LastTime = 0
		Window.SelectorPosMotor:onStep(function(Value)
			Selector.Position = UDim2.new(0, 0, 0, Value + 17)
			local Now = tick()
			local DeltaTime = Now - LastTime
	
			if LastValue ~= nil then
				Window.SelectorSizeMotor:setGoal(Spring((math.abs(Value - LastValue) / (DeltaTime * 60)) + 14))
				LastValue = Value
			end
			LastTime = Now
		end)
	
		Window.SelectorSizeMotor:onStep(function(Value)
			Selector.Size = UDim2.new(0, 3, 0, Value)
		end)
	
		Window.ContainerBackMotor:onStep(function(Value)
			Window.ContainerHolder.GroupTransparency = Value
		end)
	
		Window.ContainerPosMotor:onStep(function(Value)
			Window.ContainerHolder.Position = UDim2.fromOffset(Config.TabWidth + 30, Value)
		end)
	
		-- Maximize / Restore logic
		local OldSizeX
		local OldSizeY
		Window.Maximize = function(Value, NoPos, Instant)
			Window.Maximized = Value
			Window.TitleBar.MaxButton.Frame.Icon.Image = Value and Assets.Restore or Assets.Max
	
			if Value then
				OldSizeX = Window.Size.X.Offset
				OldSizeY = Window.Size.Y.Offset
			end
			local SizeX = Value and Camera.ViewportSize.X or OldSizeX
			local SizeY = Value and Camera.ViewportSize.Y or OldSizeY
			SizeMotor:setGoal({
				X = Flipper[Instant and "Instant" or "Spring"].new(SizeX, { frequency = 6 }),
				Y = Flipper[Instant and "Instant" or "Spring"].new(SizeY, { frequency = 6 }),
			})
			Window.Size = UDim2.fromOffset(SizeX, SizeY)
	
			if not NoPos then
				PosMotor:setGoal({
					X = Spring(Value and 0 or Window.Position.X.Offset, { frequency = 6 }),
					Y = Spring(Value and 0 or Window.Position.Y.Offset, { frequency = 6 }),
				})
			end
		end
	
		-- Drag handling
		Creator.AddSignal(Window.TitleBar.Frame.InputBegan, function(Input)
			if
				Input.UserInputType == Enum.UserInputType.MouseButton1
				or Input.UserInputType == Enum.UserInputType.Touch
			then
				Dragging = true
				MousePos = Input.Position
				StartPos = Window.Root.Position
	
				if Window.Maximized then
					StartPos = UDim2.fromOffset(
						Mouse.X - (Mouse.X * ((OldSizeX - 100) / Window.Root.AbsoluteSize.X)),
						Mouse.Y - (Mouse.Y * (OldSizeY / Window.Root.AbsoluteSize.Y))
					)
				end
	
				Input.Changed:Connect(function()
					if Input.UserInputState == Enum.UserInputState.End then
						Dragging = false
					end
				end)
			end
		end)
	
		Creator.AddSignal(Window.TitleBar.Frame.InputChanged, function(Input)
			if
				Input.UserInputType == Enum.UserInputType.MouseMovement
				or Input.UserInputType == Enum.UserInputType.Touch
			then
				DragInput = Input
			end
		end)
	
		-- Resize handling
		Creator.AddSignal(ResizeStartFrame.InputBegan, function(Input)
			if
				Input.UserInputType == Enum.UserInputType.MouseButton1
				or Input.UserInputType == Enum.UserInputType.Touch
			then
				Resizing = true
				ResizePos = Input.Position
			end
		end)
	
		Creator.AddSignal(UserInputService.InputChanged, function(Input)
			if Input == DragInput and Dragging then
				local Delta = Input.Position - MousePos
				Window.Position = UDim2.fromOffset(StartPos.X.Offset + Delta.X, StartPos.Y.Offset + Delta.Y)
				PosMotor:setGoal({
					X = Instant(Window.Position.X.Offset),
					Y = Instant(Window.Position.Y.Offset),
				})
	
				if Window.Maximized then
					Window.Maximize(false, true, true)
				end
			end
	
			if
				(Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch)
				and Resizing
			then
				local Delta = Input.Position - ResizePos
				local StartSize = Window.Size
	
				local TargetSize = Vector3.new(StartSize.X.Offset, StartSize.Y.Offset, 0) + Vector3.new(1, 1, 0) * Delta
				local TargetSizeClamped =
					Vector2.new(math.clamp(TargetSize.X, 470, 2048), math.clamp(TargetSize.Y, 380, 2048))
	
				SizeMotor:setGoal({
					X = Flipper.Instant.new(TargetSizeClamped.X),
					Y = Flipper.Instant.new(TargetSizeClamped.Y),
				})
			end
		end)
	
		Creator.AddSignal(UserInputService.InputEnded, function(Input)
			if Resizing == true or Input.UserInputType == Enum.UserInputType.Touch then
				Resizing = false
				Window.Size = UDim2.fromOffset(SizeMotor:getValue().X, SizeMotor:getValue().Y)
			end
		end)
	
		Creator.AddSignal(Window.TabHolder.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
			Window.TabHolder.CanvasSize = UDim2.new(0, 0, 0, Window.TabHolder.UIListLayout.AbsoluteContentSize.Y)
		end)
	
		-- Keybind minimize
		Creator.AddSignal(UserInputService.InputBegan, function(Input)
			if
				type(Library.MinimizeKeybind) == "table"
				and Library.MinimizeKeybind.Type == "Keybind"
				and not UserInputService:GetFocusedTextBox()
			then
				if Input.KeyCode.Name == Library.MinimizeKeybind.Value then
					Window:Minimize()
				end
			elseif Input.KeyCode == Library.MinimizeKey and not UserInputService:GetFocusedTextBox() then
				Window:Minimize()
			end
		end)
	
		function Window:Minimize()
			Window.Minimized = not Window.Minimized
			Window.Root.Visible = not Window.Minimized
			if not MinimizeNotif then
				MinimizeNotif = true
				local Key = Library.MinimizeKeybind and Library.MinimizeKeybind.Value or Library.MinimizeKey.Name
				Library:Notify({
					Title = "Interface",
					Content = "Press " .. Key .. " to toggle the interface.",
					Duration = 6
				})
			end
		end
	
		function Window:Destroy()
			if Library.UseAcrylic then
				Window.AcrylicPaint.Model:Destroy()
			end
			Window.Root:Destroy()
		end
	
		-- Dialog system
		local DialogModule = require(Components.Dialog):Init(Window)
		function Window:Dialog(Config)
			local Dialog = DialogModule:Create()
			Dialog.Title.Text = Config.Title
	
			local Content = New("TextLabel", {
				FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
				Text = Config.Content,
				TextColor3 = Color3.fromRGB(240, 240, 240),
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Size = UDim2.new(1, -40, 1, 0),
				Position = UDim2.fromOffset(20, 60),
				BackgroundTransparency = 1,
				Parent = Dialog.Root,
				ClipsDescendants = false,
				ThemeTag = {
					TextColor3 = "Text",
				},
			})
	
			New("UISizeConstraint", {
				MinSize = Vector2.new(300, 165),
				MaxSize = Vector2.new(620, math.huge),
				Parent = Dialog.Root,
			})
	
			Dialog.Root.Size = UDim2.fromOffset(Content.TextBounds.X + 40, 165)
			if Content.TextBounds.X + 40 > Window.Size.X.Offset - 120 then
				Dialog.Root.Size = UDim2.fromOffset(Window.Size.X.Offset - 120, 165)
				Content.TextWrapped = true
				Dialog.Root.Size = UDim2.fromOffset(Window.Size.X.Offset - 120, Content.TextBounds.Y + 150)
			end
	
			for _, Button in next, Config.Buttons do
				Dialog:Button(Button.Title, Button.Callback)
			end
	
			Dialog:Open()
		end
	
		-- Tab system
		local TabModule = require(Components.Tab):Init(Window)
		function Window:AddTab(TabConfig)
			return TabModule:New(TabConfig.Title, TabConfig.Icon, Window.TabHolder)
		end
	
		function Window:SelectTab(Tab)
			TabModule:SelectTab(1)
		end
	
		Creator.AddSignal(Window.TabHolder:GetPropertyChangedSignal("CanvasPosition"), function()
			LastValue = TabModule:GetCurrentTabPos() + 16
			LastTime = 0
			Window.SelectorPosMotor:setGoal(Instant(TabModule:GetCurrentTabPos()))
		end)
	
		return Window
	end
end

__modules["Creator"] = function()
	local Root = __get_script_proxy("_ROOT_")
	local Themes = __require("Themes")
	local Flipper = __require("Packages.Flipper")
	
	local Creator = {
		Registry = {},
		Signals = {},
		TransparencyMotors = {},
		DefaultProperties = {
			ScreenGui = {
				ResetOnSpawn = false,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			},
			Frame = {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderColor3 = Color3.new(0, 0, 0),
				BorderSizePixel = 0,
			},
			ScrollingFrame = {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderColor3 = Color3.new(0, 0, 0),
				ScrollBarImageColor3 = Color3.new(0, 0, 0),
			},
			TextLabel = {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderColor3 = Color3.new(0, 0, 0),
				Font = Enum.Font.SourceSans,
				Text = "",
				TextColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 1,
				TextSize = 14,
			},
			TextButton = {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderColor3 = Color3.new(0, 0, 0),
				AutoButtonColor = false,
				Font = Enum.Font.SourceSans,
				Text = "",
				TextColor3 = Color3.new(0, 0, 0),
				TextSize = 14,
			},
			TextBox = {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderColor3 = Color3.new(0, 0, 0),
				ClearTextOnFocus = false,
				Font = Enum.Font.SourceSans,
				Text = "",
				TextColor3 = Color3.new(0, 0, 0),
				TextSize = 14,
			},
			ImageLabel = {
				BackgroundTransparency = 1,
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderColor3 = Color3.new(0, 0, 0),
				BorderSizePixel = 0,
			},
			ImageButton = {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderColor3 = Color3.new(0, 0, 0),
				AutoButtonColor = false,
			},
			CanvasGroup = {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderColor3 = Color3.new(0, 0, 0),
				BorderSizePixel = 0,
			},
		},
	}
	
	local function ApplyCustomProps(Object, Props)
		if Props.ThemeTag then
			Creator.AddThemeObject(Object, Props.ThemeTag)
		end
	end
	
	function Creator.AddSignal(Signal, Function)
		table.insert(Creator.Signals, Signal:Connect(Function))
	end
	
	function Creator.Disconnect()
		for Idx = #Creator.Signals, 1, -1 do
			local Connection = table.remove(Creator.Signals, Idx)
			Connection:Disconnect()
		end
	end
	
	function Creator.GetThemeProperty(Property)
		if Themes[__require("_ROOT_").Theme][Property] then
			return Themes[__require("_ROOT_").Theme][Property]
		end
		return Themes["Dark"][Property]
	end
	
	function Creator.UpdateTheme()
		for Instance, Object in next, Creator.Registry do
			for Property, ColorIdx in next, Object.Properties do
				Instance[Property] = Creator.GetThemeProperty(ColorIdx)
			end
		end
	
		for _, Motor in next, Creator.TransparencyMotors do
			Motor:setGoal(Flipper.Instant.new(Creator.GetThemeProperty("ElementTransparency")))
		end
	end
	
	function Creator.AddThemeObject(Object, Properties)
		local Idx = #Creator.Registry + 1
		local Data = {
			Object = Object,
			Properties = Properties,
			Idx = Idx,
		}
	
		Creator.Registry[Object] = Data
		Creator.UpdateTheme()
		return Object
	end
	
	function Creator.OverrideTag(Object, Properties)
		Creator.Registry[Object].Properties = Properties
		Creator.UpdateTheme()
	end
	
	function Creator.New(Name, Properties, Children)
		local Object = Instance.new(Name)
	
		-- Default properties
		for Name, Value in next, Creator.DefaultProperties[Name] or {} do
			Object[Name] = Value
		end
	
		-- Properties
		for Name, Value in next, Properties or {} do
			if Name ~= "ThemeTag" then
				Object[Name] = Value
			end
		end
	
		-- Children
		for _, Child in next, Children or {} do
			Child.Parent = Object
		end
	
		ApplyCustomProps(Object, Properties)
		return Object
	end
	
	function Creator.SpringMotor(Initial, Instance, Prop, IgnoreDialogCheck, ResetOnThemeChange)
		IgnoreDialogCheck = IgnoreDialogCheck or false
		ResetOnThemeChange = ResetOnThemeChange or false
		local Motor = Flipper.SingleMotor.new(Initial)
		Motor:onStep(function(value)
			Instance[Prop] = value
		end)
	
		if ResetOnThemeChange then
			table.insert(Creator.TransparencyMotors, Motor)
		end
	
		local function SetValue(Value, Ignore)
			Ignore = Ignore or false
			if not IgnoreDialogCheck then
				if not Ignore then
					if Prop == "BackgroundTransparency" and __require("_ROOT_").DialogOpen then
						return
					end
				end
			end
			Motor:setGoal(Flipper.Spring.new(Value, { frequency = 8 }))
		end
	
		return Motor, SetValue
	end
	
	return Creator
end

__modules["Elements"] = function()
	local Elements = {}
	
	for _, Theme in next, script:GetChildren() do
		table.insert(Elements, require(Theme))
	end
	
	return Elements
end

__modules["Elements.Button"] = function()
	local Root = __get_script_proxy("_ROOT_")
	local Creator = __require("Creator")
	
	local New = Creator.New
	local Components = Root.Components
	
	local Element = {}
	Element.__index = Element
	Element.__type = "Button"
	
	function Element:New(Config)
		assert(Config.Title, "Button - Missing Title")
		Config.Callback = Config.Callback or function() end
	
		local ButtonFrame = require(Components.Element)(Config.Title, Config.Description, self.Container, true)
	
		local ButtonIco = New("ImageLabel", {
			Image = "rbxassetid://10709791437",
			Size = UDim2.fromOffset(16, 16),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			BackgroundTransparency = 1,
			Parent = ButtonFrame.Frame,
			ThemeTag = {
				ImageColor3 = "Text",
			},
		})
	
		Creator.AddSignal(ButtonFrame.Frame.MouseButton1Click, function()
			self.Library:SafeCallback(Config.Callback)
		end)
	
		return ButtonFrame
	end
	
	return Element
end

__modules["Elements.Colorpicker"] = function()
	local UserInputService = game:GetService("UserInputService")
	local TouchInputService = game:GetService("TouchInputService")
	local RunService = game:GetService("RunService")
	local Players = game:GetService("Players")
	
	local RenderStepped = RunService.RenderStepped
	local LocalPlayer = Players.LocalPlayer
	local Mouse = LocalPlayer:GetMouse()
	
	local Root = __get_script_proxy("_ROOT_")
	local Creator = __require("Creator")
	
	local New = Creator.New
	local Components = Root.Components
	
	local Element = {}
	Element.__index = Element
	Element.__type = "Colorpicker"
	
	function Element:New(Idx, Config)
		local Library = self.Library
		assert(Config.Title, "Colorpicker - Missing Title")
		assert(Config.Default, "AddColorPicker: Missing default value.")
	
		local Colorpicker = {
			Value = Config.Default,
			Transparency = Config.Transparency or 0,
			Type = "Colorpicker",
			Title = type(Config.Title) == "string" and Config.Title or "Colorpicker",
			Callback = Config.Callback or function(Color) end,
		}
	
		function Colorpicker:SetHSVFromRGB(Color)
			local H, S, V = Color3.toHSV(Color)
			Colorpicker.Hue = H
			Colorpicker.Sat = S
			Colorpicker.Vib = V
		end
	
		Colorpicker:SetHSVFromRGB(Colorpicker.Value)
	
		local ColorpickerFrame = require(Components.Element)(Config.Title, Config.Description, self.Container, true)
	
		Colorpicker.SetTitle = ColorpickerFrame.SetTitle
		Colorpicker.SetDesc = ColorpickerFrame.SetDesc
	
		local DisplayFrameColor = New("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Colorpicker.Value,
			Parent = ColorpickerFrame.Frame,
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		})
	
		local DisplayFrame = New("ImageLabel", {
			Size = UDim2.fromOffset(26, 26),
			Position = UDim2.new(1, -10, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Parent = ColorpickerFrame.Frame,
			Image = "http://www.roblox.com/asset/?id=14204231522",
			ImageTransparency = 0.45,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(40, 40),
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			DisplayFrameColor,
		})
	
		local function CreateColorDialog()
			local Dialog = require(Components.Dialog):Create()
			Dialog.Title.Text = Colorpicker.Title
			Dialog.Root.Size = UDim2.fromOffset(430, 330)
	
			local Hue, Sat, Vib = Colorpicker.Hue, Colorpicker.Sat, Colorpicker.Vib
			local Transparency = Colorpicker.Transparency
	
			local function CreateInput()
				local Box = require(Components.Textbox)()
				Box.Frame.Parent = Dialog.Root
				Box.Frame.Size = UDim2.new(0, 90, 0, 32)
	
				return Box
			end
	
			local function CreateInputLabel(Text, Pos)
				return New("TextLabel", {
					FontFace = Font.new(
						"rbxasset://fonts/families/GothamSSm.json",
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					),
					Text = Text,
					TextColor3 = Color3.fromRGB(240, 240, 240),
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					Size = UDim2.new(1, 0, 0, 32),
					Position = Pos,
					BackgroundTransparency = 1,
					Parent = Dialog.Root,
					ThemeTag = {
						TextColor3 = "Text",
					},
				})
			end
	
			local function GetRGB()
				local Value = Color3.fromHSV(Hue, Sat, Vib)
				return { R = math.floor(Value.r * 255), G = math.floor(Value.g * 255), B = math.floor(Value.b * 255) }
			end
	
			local SatCursor = New("ImageLabel", {
				Size = UDim2.new(0, 18, 0, 18),
				ScaleType = Enum.ScaleType.Fit,
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Image = "http://www.roblox.com/asset/?id=4805639000",
			})
	
			local SatVibMap = New("ImageLabel", {
				Size = UDim2.fromOffset(180, 160),
				Position = UDim2.fromOffset(20, 55),
				Image = "rbxassetid://4155801252",
				BackgroundColor3 = Colorpicker.Value,
				BackgroundTransparency = 0,
				Parent = Dialog.Root,
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
				SatCursor,
			})
	
			local OldColorFrame = New("Frame", {
				BackgroundColor3 = Colorpicker.Value,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = Colorpicker.Transparency,
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
			})
	
			local OldColorFrameChecker = New("ImageLabel", {
				Image = "http://www.roblox.com/asset/?id=14204231522",
				ImageTransparency = 0.45,
				ScaleType = Enum.ScaleType.Tile,
				TileSize = UDim2.fromOffset(40, 40),
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(112, 220),
				Size = UDim2.fromOffset(88, 24),
				Parent = Dialog.Root,
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
				New("UIStroke", {
					Thickness = 2,
					Transparency = 0.75,
				}),
				OldColorFrame,
			})
	
			local DialogDisplayFrame = New("Frame", {
				BackgroundColor3 = Colorpicker.Value,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 0,
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
			})
	
			local DialogDisplayFrameChecker = New("ImageLabel", {
				Image = "http://www.roblox.com/asset/?id=14204231522",
				ImageTransparency = 0.45,
				ScaleType = Enum.ScaleType.Tile,
				TileSize = UDim2.fromOffset(40, 40),
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(20, 220),
				Size = UDim2.fromOffset(88, 24),
				Parent = Dialog.Root,
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
				New("UIStroke", {
					Thickness = 2,
					Transparency = 0.75,
				}),
				DialogDisplayFrame,
			})
	
			local SequenceTable = {}
	
			for Color = 0, 1, 0.1 do
				table.insert(SequenceTable, ColorSequenceKeypoint.new(Color, Color3.fromHSV(Color, 1, 1)))
			end
	
			local HueSliderGradient = New("UIGradient", {
				Color = ColorSequence.new(SequenceTable),
				Rotation = 90,
			})
	
			local HueDragHolder = New("Frame", {
				Size = UDim2.new(1, 0, 1, -10),
				Position = UDim2.fromOffset(0, 5),
				BackgroundTransparency = 1,
			})
	
			local HueDrag = New("ImageLabel", {
				Size = UDim2.fromOffset(14, 14),
				Image = "http://www.roblox.com/asset/?id=12266946128",
				Parent = HueDragHolder,
				ThemeTag = {
					ImageColor3 = "DialogInput",
				},
			})
	
			local HueSlider = New("Frame", {
				Size = UDim2.fromOffset(12, 190),
				Position = UDim2.fromOffset(210, 55),
				Parent = Dialog.Root,
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
				HueSliderGradient,
				HueDragHolder,
			})
	
			local HexInput = CreateInput()
			HexInput.Frame.Position = UDim2.fromOffset(Config.Transparency and 260 or 240, 55)
			CreateInputLabel("Hex", UDim2.fromOffset(Config.Transparency and 360 or 340, 55))
	
			local RedInput = CreateInput()
			RedInput.Frame.Position = UDim2.fromOffset(Config.Transparency and 260 or 240, 95)
			CreateInputLabel("Red", UDim2.fromOffset(Config.Transparency and 360 or 340, 95))
	
			local GreenInput = CreateInput()
			GreenInput.Frame.Position = UDim2.fromOffset(Config.Transparency and 260 or 240, 135)
			CreateInputLabel("Green", UDim2.fromOffset(Config.Transparency and 360 or 340, 135))
	
			local BlueInput = CreateInput()
			BlueInput.Frame.Position = UDim2.fromOffset(Config.Transparency and 260 or 240, 175)
			CreateInputLabel("Blue", UDim2.fromOffset(Config.Transparency and 360 or 340, 175))
	
			local AlphaInput
			if Config.Transparency then
				AlphaInput = CreateInput()
				AlphaInput.Frame.Position = UDim2.fromOffset(260, 215)
				CreateInputLabel("Alpha", UDim2.fromOffset(360, 215))
			end
	
			local TransparencySlider, TransparencyDrag, TransparencyColor
			if Config.Transparency then
				local TransparencyDragHolder = New("Frame", {
					Size = UDim2.new(1, 0, 1, -10),
					Position = UDim2.fromOffset(0, 5),
					BackgroundTransparency = 1,
				})
	
				TransparencyDrag = New("ImageLabel", {
					Size = UDim2.fromOffset(14, 14),
					Image = "http://www.roblox.com/asset/?id=12266946128",
					Parent = TransparencyDragHolder,
					ThemeTag = {
						ImageColor3 = "DialogInput",
					},
				})
	
				TransparencyColor = New("Frame", {
					Size = UDim2.fromScale(1, 1),
				}, {
					New("UIGradient", {
						Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 0),
							NumberSequenceKeypoint.new(1, 1),
						}),
						Rotation = 270,
					}),
					New("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
				})
	
				TransparencySlider = New("Frame", {
					Size = UDim2.fromOffset(12, 190),
					Position = UDim2.fromOffset(230, 55),
					Parent = Dialog.Root,
					BackgroundTransparency = 1,
				}, {
					New("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
					New("ImageLabel", {
						Image = "http://www.roblox.com/asset/?id=14204231522",
						ImageTransparency = 0.45,
						ScaleType = Enum.ScaleType.Tile,
						TileSize = UDim2.fromOffset(40, 40),
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						Parent = Dialog.Root,
					}, {
						New("UICorner", {
							CornerRadius = UDim.new(1, 0),
						}),
					}),
					TransparencyColor,
					TransparencyDragHolder,
				})
			end
	
			local function Display()
				SatVibMap.BackgroundColor3 = Color3.fromHSV(Hue, 1, 1)
				HueDrag.Position = UDim2.new(0, -1, Hue, -6)
				SatCursor.Position = UDim2.new(Sat, 0, 1 - Vib, 0)
				DialogDisplayFrame.BackgroundColor3 = Color3.fromHSV(Hue, Sat, Vib)
	
				HexInput.Input.Text = "#" .. Color3.fromHSV(Hue, Sat, Vib):ToHex()
				RedInput.Input.Text = GetRGB()["R"]
				GreenInput.Input.Text = GetRGB()["G"]
				BlueInput.Input.Text = GetRGB()["B"]
	
				if Config.Transparency then
					TransparencyColor.BackgroundColor3 = Color3.fromHSV(Hue, Sat, Vib)
					DialogDisplayFrame.BackgroundTransparency = Transparency
					TransparencyDrag.Position = UDim2.new(0, -1, 1 - Transparency, -6)
					AlphaInput.Input.Text = __require("_ROOT_"):Round((1 - Transparency) * 100, 0) .. "%"
				end
			end
	
			Creator.AddSignal(HexInput.Input.FocusLost, function(Enter)
				if Enter then
					local Success, Result = pcall(Color3.fromHex, HexInput.Input.Text)
					if Success and typeof(Result) == "Color3" then
						Hue, Sat, Vib = Color3.toHSV(Result)
					end
				end
				Display()
			end)
	
			Creator.AddSignal(RedInput.Input.FocusLost, function(Enter)
				if Enter then
					local CurrentColor = GetRGB()
					local Success, Result = pcall(Color3.fromRGB, RedInput.Input.Text, CurrentColor["G"], CurrentColor["B"])
					if Success and typeof(Result) == "Color3" then
						if tonumber(RedInput.Input.Text) <= 255 then
							Hue, Sat, Vib = Color3.toHSV(Result)
						end
					end
				end
				Display()
			end)
	
			Creator.AddSignal(GreenInput.Input.FocusLost, function(Enter)
				if Enter then
					local CurrentColor = GetRGB()
					local Success, Result =
						pcall(Color3.fromRGB, CurrentColor["R"], GreenInput.Input.Text, CurrentColor["B"])
					if Success and typeof(Result) == "Color3" then
						if tonumber(GreenInput.Input.Text) <= 255 then
							Hue, Sat, Vib = Color3.toHSV(Result)
						end
					end
				end
				Display()
			end)
	
			Creator.AddSignal(BlueInput.Input.FocusLost, function(Enter)
				if Enter then
					local CurrentColor = GetRGB()
					local Success, Result =
						pcall(Color3.fromRGB, CurrentColor["R"], CurrentColor["G"], BlueInput.Input.Text)
					if Success and typeof(Result) == "Color3" then
						if tonumber(BlueInput.Input.Text) <= 255 then
							Hue, Sat, Vib = Color3.toHSV(Result)
						end
					end
				end
				Display()
			end)
	
			if Config.Transparency then
				Creator.AddSignal(AlphaInput.Input.FocusLost, function(Enter)
					if Enter then
						pcall(function()
							local Value = tonumber(AlphaInput.Input.Text)
							if Value >= 0 and Value <= 100 then
								Transparency = 1 - Value * 0.01
							end
						end)
					end
					Display()
				end)
			end
	
			Creator.AddSignal(SatVibMap.InputBegan, function(Input)
				if
					Input.UserInputType == Enum.UserInputType.MouseButton1
					or Input.UserInputType == Enum.UserInputType.Touch
				then
					while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
						local MinX = SatVibMap.AbsolutePosition.X
						local MaxX = MinX + SatVibMap.AbsoluteSize.X
						local MouseX = math.clamp(Mouse.X, MinX, MaxX)
	
						local MinY = SatVibMap.AbsolutePosition.Y
						local MaxY = MinY + SatVibMap.AbsoluteSize.Y
						local MouseY = math.clamp(Mouse.Y, MinY, MaxY)
	
						Sat = (MouseX - MinX) / (MaxX - MinX)
						Vib = 1 - ((MouseY - MinY) / (MaxY - MinY))
						Display()
	
						RenderStepped:Wait()
					end
				end
			end)
	
			Creator.AddSignal(HueSlider.InputBegan, function(Input)
				if
					Input.UserInputType == Enum.UserInputType.MouseButton1
					or Input.UserInputType == Enum.UserInputType.Touch
				then
					while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
						local MinY = HueSlider.AbsolutePosition.Y
						local MaxY = MinY + HueSlider.AbsoluteSize.Y
						local MouseY = math.clamp(Mouse.Y, MinY, MaxY)
	
						Hue = ((MouseY - MinY) / (MaxY - MinY))
						Display()
	
						RenderStepped:Wait()
					end
				end
			end)
	
			if Config.Transparency then
				Creator.AddSignal(TransparencySlider.InputBegan, function(Input)
					if Input.UserInputType == Enum.UserInputType.MouseButton1 then
						while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
							local MinY = TransparencySlider.AbsolutePosition.Y
							local MaxY = MinY + TransparencySlider.AbsoluteSize.Y
							local MouseY = math.clamp(Mouse.Y, MinY, MaxY)
	
							Transparency = 1 - ((MouseY - MinY) / (MaxY - MinY))
							Display()
	
							RenderStepped:Wait()
						end
					end
				end)
			end
	
			Display()
	
			Dialog:Button("Done", function()
				Colorpicker:SetValue({ Hue, Sat, Vib }, Transparency)
			end)
			Dialog:Button("Cancel")
			Dialog:Open()
		end
	
		function Colorpicker:Display()
			Colorpicker.Value = Color3.fromHSV(Colorpicker.Hue, Colorpicker.Sat, Colorpicker.Vib)
	
			DisplayFrameColor.BackgroundColor3 = Colorpicker.Value
			DisplayFrameColor.BackgroundTransparency = Colorpicker.Transparency
	
			Element.Library:SafeCallback(Colorpicker.Callback, Colorpicker.Value)
			Element.Library:SafeCallback(Colorpicker.Changed, Colorpicker.Value)
		end
	
		function Colorpicker:SetValue(HSV, Transparency)
			local Color = Color3.fromHSV(HSV[1], HSV[2], HSV[3])
	
			Colorpicker.Transparency = Transparency or 0
			Colorpicker:SetHSVFromRGB(Color)
			Colorpicker:Display()
		end
	
		function Colorpicker:SetValueRGB(Color, Transparency)
			Colorpicker.Transparency = Transparency or 0
			Colorpicker:SetHSVFromRGB(Color)
			Colorpicker:Display()
		end
	
		function Colorpicker:OnChanged(Func)
			Colorpicker.Changed = Func
			Func(Colorpicker.Value)
		end
	
		function Colorpicker:Destroy()
			ColorpickerFrame:Destroy()
			Library.Options[Idx] = nil
		end
	
		Creator.AddSignal(ColorpickerFrame.Frame.MouseButton1Click, function()
			CreateColorDialog()
		end)
	
		Colorpicker:Display()
	
		Library.Options[Idx] = Colorpicker
		return Colorpicker
	end
	
	return Element
end

__modules["Elements.Dropdown"] = function()
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")
	local Mouse = game:GetService("Players").LocalPlayer:GetMouse()
	local Camera = game:GetService("Workspace").CurrentCamera
	
	local Root = __get_script_proxy("_ROOT_")
	local Creator = __require("Creator")
	local Flipper = __require("Packages.Flipper")
	
	local New = Creator.New
	local Components = Root.Components
	
	local Element = {}
	Element.__index = Element
	Element.__type = "Dropdown"
	
	function Element:New(Idx, Config)
		local Library = self.Library
	
		local Dropdown = {
			Values = Config.Values,
			Value = Config.Default,
			Multi = Config.Multi,
			Buttons = {},
			Opened = false,
			Type = "Dropdown",
			Callback = Config.Callback or function() end,
		}
	
		local DropdownFrame = require(Components.Element)(Config.Title, Config.Description, self.Container, false)
		DropdownFrame.DescLabel.Size = UDim2.new(1, -170, 0, 14)
	
		Dropdown.SetTitle = DropdownFrame.SetTitle
		Dropdown.SetDesc = DropdownFrame.SetDesc
	
		local DropdownDisplay = New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
			Text = "Value",
			TextColor3 = Color3.fromRGB(240, 240, 240),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -30, 0, 14),
			Position = UDim2.new(0, 8, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ThemeTag = {
				TextColor3 = "Text",
			},
		})
	
		local DropdownIco = New("ImageLabel", {
			Image = "rbxassetid://10709790948",
			Size = UDim2.fromOffset(16, 16),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			BackgroundTransparency = 1,
			ThemeTag = {
				ImageColor3 = "SubText",
			},
		})
	
		local DropdownInner = New("TextButton", {
			Size = UDim2.fromOffset(160, 30),
			Position = UDim2.new(1, -10, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 0.9,
			Parent = DropdownFrame.Frame,
			ThemeTag = {
				BackgroundColor3 = "DropdownFrame",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 6),
			}),
			New("UIStroke", {
				Transparency = 0.5,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				ThemeTag = {
					Color = "InElementBorder",
				},
			}),
			DropdownIco,
			DropdownDisplay,
		})
	
		local DropdownListLayout = New("UIListLayout", {
			Padding = UDim.new(0, 3),
		})
	
		local DropdownScrollFrame = New("ScrollingFrame", {
			Size = UDim2.new(1, -5, 1, -10),
			Position = UDim2.fromOffset(5, 5),
			BackgroundTransparency = 1,
			BottomImage = "rbxassetid://6889812791",
			MidImage = "rbxassetid://6889812721",
			TopImage = "rbxassetid://6276641225",
			ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255),
			ScrollBarImageTransparency = 0.95,
			ScrollBarThickness = 4,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromScale(0, 0),
		}, {
			DropdownListLayout,
		})
	
		local DropdownHolderFrame = New("Frame", {
			Size = UDim2.fromScale(1, 0.6),
			ThemeTag = {
				BackgroundColor3 = "DropdownHolder",
			},
		}, {
			DropdownScrollFrame,
			New("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			New("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				ThemeTag = {
					Color = "DropdownBorder",
				},
			}),
			New("ImageLabel", {
				BackgroundTransparency = 1,
				Image = "http://www.roblox.com/asset/?id=5554236805",
				ScaleType = Enum.ScaleType.Slice,
				SliceCenter = Rect.new(23, 23, 277, 277),
				Size = UDim2.fromScale(1, 1) + UDim2.fromOffset(30, 30),
				Position = UDim2.fromOffset(-15, -15),
				ImageColor3 = Color3.fromRGB(0, 0, 0),
				ImageTransparency = 0.1,
			}),
		})
	
		local DropdownHolderCanvas = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(170, 300),
			Parent = self.Library.GUI,
			Visible = false,
		}, {
			DropdownHolderFrame,
			New("UISizeConstraint", {
				MinSize = Vector2.new(170, 0),
			}),
		})
		table.insert(Library.OpenFrames, DropdownHolderCanvas)
	
		local function RecalculateListPosition()
			local Add = 0
			if Camera.ViewportSize.Y - DropdownInner.AbsolutePosition.Y < DropdownHolderCanvas.AbsoluteSize.Y - 5 then
				Add = DropdownHolderCanvas.AbsoluteSize.Y
					- 5
					- (Camera.ViewportSize.Y - DropdownInner.AbsolutePosition.Y)
					+ 40
			end
			DropdownHolderCanvas.Position =
				UDim2.fromOffset(DropdownInner.AbsolutePosition.X - 1, DropdownInner.AbsolutePosition.Y - 5 - Add)
		end
	
		local ListSizeX = 0
		local function RecalculateListSize()
			if #Dropdown.Values > 10 then
				DropdownHolderCanvas.Size = UDim2.fromOffset(ListSizeX, 392)
			else
				DropdownHolderCanvas.Size = UDim2.fromOffset(ListSizeX, DropdownListLayout.AbsoluteContentSize.Y + 10)
			end
		end
	
		local function RecalculateCanvasSize()
			DropdownScrollFrame.CanvasSize = UDim2.fromOffset(0, DropdownListLayout.AbsoluteContentSize.Y)
		end
	
		RecalculateListPosition()
		RecalculateListSize()
	
		Creator.AddSignal(DropdownInner:GetPropertyChangedSignal("AbsolutePosition"), RecalculateListPosition)
	
		Creator.AddSignal(DropdownInner.MouseButton1Click, function()
			Dropdown:Open()
		end)
	
		Creator.AddSignal(UserInputService.InputBegan, function(Input)
			if
				Input.UserInputType == Enum.UserInputType.MouseButton1
				or Input.UserInputType == Enum.UserInputType.Touch
			then
				local AbsPos, AbsSize = DropdownHolderFrame.AbsolutePosition, DropdownHolderFrame.AbsoluteSize
				if
					Mouse.X < AbsPos.X
					or Mouse.X > AbsPos.X + AbsSize.X
					or Mouse.Y < (AbsPos.Y - 20 - 1)
					or Mouse.Y > AbsPos.Y + AbsSize.Y
				then
					Dropdown:Close()
				end
			end
		end)
	
		local ScrollFrame = self.ScrollFrame
		function Dropdown:Open()
			Dropdown.Opened = true
			ScrollFrame.ScrollingEnabled = false
			DropdownHolderCanvas.Visible = true
			TweenService:Create(
				DropdownHolderFrame,
				TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ Size = UDim2.fromScale(1, 1) }
			):Play()
		end
	
		function Dropdown:Close()
			Dropdown.Opened = false
			ScrollFrame.ScrollingEnabled = true
			DropdownHolderFrame.Size = UDim2.fromScale(1, 0.6)
			DropdownHolderCanvas.Visible = false
		end
	
		function Dropdown:Display()
			local Values = Dropdown.Values
			local Str = ""
	
			if Config.Multi then
				for Idx, Value in next, Values do
					if Dropdown.Value[Value] then
						Str = Str .. Value .. ", "
					end
				end
				Str = Str:sub(1, #Str - 2)
			else
				Str = Dropdown.Value or ""
			end
	
			DropdownDisplay.Text = (Str == "" and "--" or Str)
		end
	
		function Dropdown:GetActiveValues()
			if Config.Multi then
				local T = {}
	
				for Value, Bool in next, Dropdown.Value do
					table.insert(T, Value)
				end
	
				return T
			else
				return Dropdown.Value and 1 or 0
			end
		end
	
		function Dropdown:BuildDropdownList()
			local Values = Dropdown.Values
			local Buttons = {}
	
			for _, Element in next, DropdownScrollFrame:GetChildren() do
				if not Element:IsA("UIListLayout") then
					Element:Destroy()
				end
			end
	
			local Count = 0
	
			for Idx, Value in next, Values do
				local Table = {}
	
				Count = Count + 1
	
				local ButtonSelector = New("Frame", {
					Size = UDim2.fromOffset(4, 14),
					BackgroundColor3 = Color3.fromRGB(76, 194, 255),
					Position = UDim2.fromOffset(-1, 16),
					AnchorPoint = Vector2.new(0, 0.5),
					ThemeTag = {
						BackgroundColor3 = "Accent",
					},
				}, {
					New("UICorner", {
						CornerRadius = UDim.new(0, 2),
					}),
				})
	
				local ButtonLabel = New("TextLabel", {
					FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
					Text = Value,
					TextColor3 = Color3.fromRGB(200, 200, 200),
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					BackgroundColor3 = Color3.fromRGB(255, 255, 255),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Position = UDim2.fromOffset(10, 0),
					Name = "ButtonLabel",
					ThemeTag = {
						TextColor3 = "Text",
					},
				})
	
				local Button = New("TextButton", {
					Size = UDim2.new(1, -5, 0, 32),
					BackgroundTransparency = 1,
					ZIndex = 23,
					Text = "",
					Parent = DropdownScrollFrame,
					ThemeTag = {
						BackgroundColor3 = "DropdownOption",
					},
				}, {
					ButtonSelector,
					ButtonLabel,
					New("UICorner", {
						CornerRadius = UDim.new(0, 6),
					}),
				})
	
				local Selected
	
				if Config.Multi then
					Selected = Dropdown.Value[Value]
				else
					Selected = Dropdown.Value == Value
				end
	
				local BackMotor, SetBackTransparency = Creator.SpringMotor(1, Button, "BackgroundTransparency")
				local SelMotor, SetSelTransparency = Creator.SpringMotor(1, ButtonSelector, "BackgroundTransparency")
				local SelectorSizeMotor = Flipper.SingleMotor.new(6)
	
				SelectorSizeMotor:onStep(function(value)
					ButtonSelector.Size = UDim2.new(0, 4, 0, value)
				end)
	
				Creator.AddSignal(Button.MouseEnter, function()
					SetBackTransparency(Selected and 0.85 or 0.89)
				end)
				Creator.AddSignal(Button.MouseLeave, function()
					SetBackTransparency(Selected and 0.89 or 1)
				end)
				Creator.AddSignal(Button.MouseButton1Down, function()
					SetBackTransparency(0.92)
				end)
				Creator.AddSignal(Button.MouseButton1Up, function()
					SetBackTransparency(Selected and 0.85 or 0.89)
				end)
	
				function Table:UpdateButton()
					if Config.Multi then
						Selected = Dropdown.Value[Value]
						if Selected then
							SetBackTransparency(0.89)
						end
					else
						Selected = Dropdown.Value == Value
						SetBackTransparency(Selected and 0.89 or 1)
					end
	
					SelectorSizeMotor:setGoal(Flipper.Spring.new(Selected and 14 or 6, { frequency = 6 }))
					SetSelTransparency(Selected and 0 or 1)
				end
	
				ButtonLabel.InputBegan:Connect(function(Input)
					if
						Input.UserInputType == Enum.UserInputType.MouseButton1
						or Input.UserInputType == Enum.UserInputType.Touch
					then
						local Try = not Selected
	
						if Dropdown:GetActiveValues() == 1 and not Try and not Config.AllowNull then
						else
							if Config.Multi then
								Selected = Try
								Dropdown.Value[Value] = Selected and true or nil
							else
								Selected = Try
								Dropdown.Value = Selected and Value or nil
	
								for _, OtherButton in next, Buttons do
									OtherButton:UpdateButton()
								end
							end
	
							Table:UpdateButton()
							Dropdown:Display()
	
							Library:SafeCallback(Dropdown.Callback, Dropdown.Value)
							Library:SafeCallback(Dropdown.Changed, Dropdown.Value)
						end
					end
				end)
	
				Table:UpdateButton()
				Dropdown:Display()
	
				Buttons[Button] = Table
			end
	
			ListSizeX = 0
			for Button, Table in next, Buttons do
				if Button.ButtonLabel then
					if Button.ButtonLabel.TextBounds.X > ListSizeX then
						ListSizeX = Button.ButtonLabel.TextBounds.X
					end
				end
			end
			ListSizeX = ListSizeX + 30
	
			RecalculateCanvasSize()
			RecalculateListSize()
		end
	
		function Dropdown:SetValues(NewValues)
			if NewValues then
				Dropdown.Values = NewValues
			end
	
			Dropdown:BuildDropdownList()
		end
	
		function Dropdown:OnChanged(Func)
			Dropdown.Changed = Func
			Func(Dropdown.Value)
		end
	
		function Dropdown:SetValue(Val)
			if Dropdown.Multi then
				local nTable = {}
	
				for Value, Bool in next, Val do
					if table.find(Dropdown.Values, Value) then
						nTable[Value] = true
					end
				end
	
				Dropdown.Value = nTable
			else
				if not Val then
					Dropdown.Value = nil
				elseif table.find(Dropdown.Values, Val) then
					Dropdown.Value = Val
				end
			end
	
			Dropdown:BuildDropdownList()
	
			Library:SafeCallback(Dropdown.Callback, Dropdown.Value)
			Library:SafeCallback(Dropdown.Changed, Dropdown.Value)
		end
	
		function Dropdown:Destroy()
			DropdownFrame:Destroy()
			Library.Options[Idx] = nil
		end
	
		Dropdown:BuildDropdownList()
		Dropdown:Display()
	
		local Defaults = {}
	
		if type(Config.Default) == "string" then
			local Idx = table.find(Dropdown.Values, Config.Default)
			if Idx then
				table.insert(Defaults, Idx)
			end
		elseif type(Config.Default) == "table" then
			for _, Value in next, Config.Default do
				local Idx = table.find(Dropdown.Values, Value)
				if Idx then
					table.insert(Defaults, Idx)
				end
			end
		elseif type(Config.Default) == "number" and Dropdown.Values[Config.Default] ~= nil then
			table.insert(Defaults, Config.Default)
		end
	
		if next(Defaults) then
			for i = 1, #Defaults do
				local Index = Defaults[i]
				if Config.Multi then
					Dropdown.Value[Dropdown.Values[Index]] = true
				else
					Dropdown.Value = Dropdown.Values[Index]
				end
	
				if not Config.Multi then
					break
				end
			end
	
			Dropdown:BuildDropdownList()
			Dropdown:Display()
		end
	
		Library.Options[Idx] = Dropdown
		return Dropdown
	end
	
	return Element
end

__modules["Elements.Input"] = function()
	local Root = __get_script_proxy("_ROOT_")
	local Creator = __require("Creator")
	
	local New = Creator.New
	local AddSignal = Creator.AddSignal
	local Components = Root.Components
	
	local Element = {}
	Element.__index = Element
	Element.__type = "Input"
	
	function Element:New(Idx, Config)
		local Library = self.Library
		assert(Config.Title, "Input - Missing Title")
		Config.Callback = Config.Callback or function() end
	
		local Input = {
			Value = Config.Default or "",
			Numeric = Config.Numeric or false,
			Finished = Config.Finished or false,
			Callback = Config.Callback or function(Value) end,
			Type = "Input",
		}
	
		local InputFrame = require(Components.Element)(Config.Title, Config.Description, self.Container, false)
	
		Input.SetTitle = InputFrame.SetTitle
		Input.SetDesc = InputFrame.SetDesc
	
		local Textbox = require(Components.Textbox)(InputFrame.Frame, true)
		Textbox.Frame.Position = UDim2.new(1, -10, 0.5, 0)
		Textbox.Frame.AnchorPoint = Vector2.new(1, 0.5)
		Textbox.Frame.Size = UDim2.fromOffset(160, 30)
		Textbox.Input.Text = Config.Default or ""
		Textbox.Input.PlaceholderText = Config.Placeholder or ""
	
		local Box = Textbox.Input
	
		function Input:SetValue(Text)
			if Config.MaxLength and #Text > Config.MaxLength then
				Text = Text:sub(1, Config.MaxLength)
			end
	
			if Input.Numeric then
				if (not tonumber(Text)) and Text:len() > 0 then
					Text = Input.Value
				end
			end
	
			Input.Value = Text
			Box.Text = Text
	
			Library:SafeCallback(Input.Callback, Input.Value)
			Library:SafeCallback(Input.Changed, Input.Value)
		end
	
		if Input.Finished then
			AddSignal(Box.FocusLost, function(enter)
				if not enter then
					return
				end
				Input:SetValue(Box.Text)
			end)
		else
			AddSignal(Box:GetPropertyChangedSignal("Text"), function()
				Input:SetValue(Box.Text)
			end)
		end
	
		function Input:OnChanged(Func)
			Input.Changed = Func
			Func(Input.Value)
		end
	
		function Input:Destroy()
			InputFrame:Destroy()
			Library.Options[Idx] = nil
		end
	
		Library.Options[Idx] = Input
		return Input
	end
	
	return Element
end

__modules["Elements.Keybind"] = function()
	local UserInputService = game:GetService("UserInputService")
	
	local Root = __get_script_proxy("_ROOT_")
	local Creator = __require("Creator")
	
	local New = Creator.New
	local Components = Root.Components
	
	local Element = {}
	Element.__index = Element
	Element.__type = "Keybind"
	
	function Element:New(Idx, Config)
		local Library = self.Library
		assert(Config.Title, "KeyBind - Missing Title")
		assert(Config.Default, "KeyBind - Missing default value.")
	
		local Keybind = {
			Value = Config.Default,
			Toggled = false,
			Mode = Config.Mode or "Toggle",
			Type = "Keybind",
			Callback = Config.Callback or function(Value) end,
			ChangedCallback = Config.ChangedCallback or function(New) end,
		}
	
		local Picking = false
	
		local KeybindFrame = require(Components.Element)(Config.Title, Config.Description, self.Container, true)
	
		Keybind.SetTitle = KeybindFrame.SetTitle
		Keybind.SetDesc = KeybindFrame.SetDesc
	
		local KeybindDisplayLabel = New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
			Text = Config.Default,
			TextColor3 = Color3.fromRGB(240, 240, 240),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(0, 0, 0, 14),
			Position = UDim2.new(0, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			ThemeTag = {
				TextColor3 = "Text",
			},
		})
	
		local KeybindDisplayFrame = New("TextButton", {
			Size = UDim2.fromOffset(0, 30),
			Position = UDim2.new(1, -10, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 0.9,
			Parent = KeybindFrame.Frame,
			AutomaticSize = Enum.AutomaticSize.X,
			ThemeTag = {
				BackgroundColor3 = "Keybind",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 5),
			}),
			New("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
			New("UIStroke", {
				Transparency = 0.5,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				ThemeTag = {
					Color = "InElementBorder",
				},
			}),
			KeybindDisplayLabel,
		})
	
		function Keybind:GetState()
			if UserInputService:GetFocusedTextBox() and Keybind.Mode ~= "Always" then
				return false
			end
	
			if Keybind.Mode == "Always" then
				return true
			elseif Keybind.Mode == "Hold" then
				if Keybind.Value == "None" then
					return false
				end
	
				local Key = Keybind.Value
	
				if Key == "MouseLeft" or Key == "MouseRight" then
					return Key == "MouseLeft" and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
						or Key == "MouseRight"
							and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
				else
					return UserInputService:IsKeyDown(Enum.KeyCode[Keybind.Value])
				end
			else
				return Keybind.Toggled
			end
		end
	
		function Keybind:SetValue(Key, Mode)
			Key = Key or Keybind.Key
			Mode = Mode or Keybind.Mode
	
			KeybindDisplayLabel.Text = Key
			Keybind.Value = Key
			Keybind.Mode = Mode
		end
	
		function Keybind:OnClick(Callback)
			Keybind.Clicked = Callback
		end
	
		function Keybind:OnChanged(Callback)
			Keybind.Changed = Callback
			Callback(Keybind.Value)
		end
	
		function Keybind:DoClick()
			Library:SafeCallback(Keybind.Callback, Keybind.Toggled)
			Library:SafeCallback(Keybind.Clicked, Keybind.Toggled)
		end
	
		function Keybind:Destroy()
			KeybindFrame:Destroy()
			Library.Options[Idx] = nil
		end
	
		Creator.AddSignal(KeybindDisplayFrame.InputBegan, function(Input)
			if
				Input.UserInputType == Enum.UserInputType.MouseButton1
				or Input.UserInputType == Enum.UserInputType.Touch
			then
				Picking = true
				KeybindDisplayLabel.Text = "..."
	
				wait(0.2)
	
				local Event
				Event = UserInputService.InputBegan:Connect(function(Input)
					local Key
	
					if Input.UserInputType == Enum.UserInputType.Keyboard then
						Key = Input.KeyCode.Name
					elseif Input.UserInputType == Enum.UserInputType.MouseButton1 then
						Key = "MouseLeft"
					elseif Input.UserInputType == Enum.UserInputType.MouseButton2 then
						Key = "MouseRight"
					end
	
					local EndedEvent
					EndedEvent = UserInputService.InputEnded:Connect(function(Input)
						if
							Input.KeyCode.Name == Key
							or Key == "MouseLeft" and Input.UserInputType == Enum.UserInputType.MouseButton1
							or Key == "MouseRight" and Input.UserInputType == Enum.UserInputType.MouseButton2
						then
							Picking = false
	
							KeybindDisplayLabel.Text = Key
							Keybind.Value = Key
	
							Library:SafeCallback(Keybind.ChangedCallback, Input.KeyCode or Input.UserInputType)
							Library:SafeCallback(Keybind.Changed, Input.KeyCode or Input.UserInputType)
	
							Event:Disconnect()
							EndedEvent:Disconnect()
						end
					end)
				end)
			end
		end)
	
		Creator.AddSignal(UserInputService.InputBegan, function(Input)
			if not Picking and not UserInputService:GetFocusedTextBox() then
				if Keybind.Mode == "Toggle" then
					local Key = Keybind.Value
	
					if Key == "MouseLeft" or Key == "MouseRight" then
						if
							Key == "MouseLeft" and Input.UserInputType == Enum.UserInputType.MouseButton1
							or Key == "MouseRight" and Input.UserInputType == Enum.UserInputType.MouseButton2
						then
							Keybind.Toggled = not Keybind.Toggled
							Keybind:DoClick()
						end
					elseif Input.UserInputType == Enum.UserInputType.Keyboard then
						if Input.KeyCode.Name == Key then
							Keybind.Toggled = not Keybind.Toggled
							Keybind:DoClick()
						end
					end
				end
			end
		end)
	
		Library.Options[Idx] = Keybind
		return Keybind
	end
	
	return Element
end

__modules["Elements.Paragraph"] = function()
	local Root = __get_script_proxy("_ROOT_")
	local Components = Root.Components
	local Flipper = __require("Packages.Flipper")
	local Creator = __require("Creator")
	
	local Paragraph = {}
	Paragraph.__index = Paragraph
	Paragraph.__type = "Paragraph"
	
	function Paragraph:New(Config)
		assert(Config.Title, "Paragraph - Missing Title")
		Config.Content = Config.Content or ""
	
		local Paragraph = require(Components.Element)(Config.Title, Config.Content, Paragraph.Container, false)
		Paragraph.Frame.BackgroundTransparency = 0.92
		Paragraph.Border.Transparency = 0.6
	
		return Paragraph
	end
	
	return Paragraph
end

__modules["Elements.Slider"] = function()
	local UserInputService = game:GetService("UserInputService")
	local Root = __get_script_proxy("_ROOT_")
	local Creator = __require("Creator")
	
	local New = Creator.New
	local Components = Root.Components
	
	local Element = {}
	Element.__index = Element
	Element.__type = "Slider"
	
	function Element:New(Idx, Config)
		local Library = self.Library
		assert(Config.Title, "Slider - Missing Title.")
		assert(Config.Default, "Slider - Missing default value.")
		assert(Config.Min, "Slider - Missing minimum value.")
		assert(Config.Max, "Slider - Missing maximum value.")
		assert(Config.Rounding, "Slider - Missing rounding value.")
	
		local Slider = {
			Value = nil,
			Min = Config.Min,
			Max = Config.Max,
			Rounding = Config.Rounding,
			Callback = Config.Callback or function(Value) end,
			Type = "Slider",
		}
	
		local Dragging = false
	
		local SliderFrame = require(Components.Element)(Config.Title, Config.Description, self.Container, false)
		SliderFrame.DescLabel.Size = UDim2.new(1, -170, 0, 14)
	
		Slider.SetTitle = SliderFrame.SetTitle
		Slider.SetDesc = SliderFrame.SetDesc
	
		local SliderDot = New("ImageLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, -7, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			Image = "http://www.roblox.com/asset/?id=12266946128",
			ThemeTag = {
				ImageColor3 = "Accent",
			},
		})
	
		local SliderRail = New("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(7, 0),
			Size = UDim2.new(1, -14, 1, 0),
		}, {
			SliderDot,
		})
	
		local SliderFill = New("Frame", {
			Size = UDim2.new(0, 0, 1, 0),
			ThemeTag = {
				BackgroundColor3 = "Accent",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		})
	
		local SliderDisplay = New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
			Text = "Value",
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 100, 0, 14),
			Position = UDim2.new(0, -4, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			ThemeTag = {
				TextColor3 = "SubText",
			},
		})
	
		local SliderInner = New("Frame", {
			Size = UDim2.new(1, 0, 0, 4),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			BackgroundTransparency = 0.4,
			Parent = SliderFrame.Frame,
			ThemeTag = {
				BackgroundColor3 = "SliderRail",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			New("UISizeConstraint", {
				MaxSize = Vector2.new(150, math.huge),
			}),
			SliderDisplay,
			SliderFill,
			SliderRail,
		})
	
		Creator.AddSignal(SliderDot.InputBegan, function(Input)
			if
				Input.UserInputType == Enum.UserInputType.MouseButton1
				or Input.UserInputType == Enum.UserInputType.Touch
			then
				Dragging = true
			end
		end)
	
		Creator.AddSignal(SliderDot.InputEnded, function(Input)
			if
				Input.UserInputType == Enum.UserInputType.MouseButton1
				or Input.UserInputType == Enum.UserInputType.Touch
			then
				Dragging = false
			end
		end)
	
		Creator.AddSignal(UserInputService.InputChanged, function(Input)
			if
				Dragging
				and (
					Input.UserInputType == Enum.UserInputType.MouseMovement
					or Input.UserInputType == Enum.UserInputType.Touch
				)
			then
				local SizeScale =
					math.clamp((Input.Position.X - SliderRail.AbsolutePosition.X) / SliderRail.AbsoluteSize.X, 0, 1)
				Slider:SetValue(Slider.Min + ((Slider.Max - Slider.Min) * SizeScale))
			end
		end)
	
		function Slider:OnChanged(Func)
			Slider.Changed = Func
			Func(Slider.Value)
		end
	
		function Slider:SetValue(Value)
			self.Value = Library:Round(math.clamp(Value, Slider.Min, Slider.Max), Slider.Rounding)
			SliderDot.Position = UDim2.new((self.Value - Slider.Min) / (Slider.Max - Slider.Min), -7, 0.5, 0)
			SliderFill.Size = UDim2.fromScale((self.Value - Slider.Min) / (Slider.Max - Slider.Min), 1)
			SliderDisplay.Text = tostring(self.Value)
	
			Library:SafeCallback(Slider.Callback, self.Value)
			Library:SafeCallback(Slider.Changed, self.Value)
		end
	
		function Slider:Destroy()
			SliderFrame:Destroy()
			Library.Options[Idx] = nil
		end
	
		Slider:SetValue(Config.Default)
	
		Library.Options[Idx] = Slider
		return Slider
	end
	
	return Element
end

__modules["Elements.Toggle"] = function()
	local TweenService = game:GetService("TweenService")
	local Root = __get_script_proxy("_ROOT_")
	local Creator = __require("Creator")
	
	local New = Creator.New
	local Components = Root.Components
	
	local Element = {}
	Element.__index = Element
	Element.__type = "Toggle"
	
	function Element:New(Idx, Config)
		local Library = self.Library
		assert(Config.Title, "Toggle - Missing Title")
	
		local Toggle = {
			Value = Config.Default or false,
			Callback = Config.Callback or function(Value) end,
			Type = "Toggle",
		}
	
		local ToggleFrame = require(Components.Element)(Config.Title, Config.Description, self.Container, true)
		ToggleFrame.DescLabel.Size = UDim2.new(1, -54, 0, 14)
	
		Toggle.SetTitle = ToggleFrame.SetTitle
		Toggle.SetDesc = ToggleFrame.SetDesc
	
		local ToggleCircle = New("ImageLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.new(0, 2, 0.5, 0),
			Image = "http://www.roblox.com/asset/?id=12266946128",
			ImageTransparency = 0.5,
			ThemeTag = {
				ImageColor3 = "ToggleSlider",
			},
		})
	
		local ToggleBorder = New("UIStroke", {
			Transparency = 0.5,
			ThemeTag = {
				Color = "ToggleSlider",
			},
		})
	
		local ToggleSlider = New("Frame", {
			Size = UDim2.fromOffset(36, 18),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Parent = ToggleFrame.Frame,
			BackgroundTransparency = 1,
			ThemeTag = {
				BackgroundColor3 = "Accent",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			ToggleBorder,
			ToggleCircle,
		})
	
		function Toggle:OnChanged(Func)
			Toggle.Changed = Func
			Func(Toggle.Value)
		end
	
		function Toggle:SetValue(Value)
			Value = not not Value
			Toggle.Value = Value
	
			Creator.OverrideTag(ToggleBorder, { Color = Toggle.Value and "Accent" or "ToggleSlider" })
			Creator.OverrideTag(ToggleCircle, { ImageColor3 = Toggle.Value and "ToggleToggled" or "ToggleSlider" })
			TweenService:Create(
				ToggleCircle,
				TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{ Position = UDim2.new(0, Toggle.Value and 19 or 2, 0.5, 0) }
			):Play()
			TweenService:Create(
				ToggleSlider,
				TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{ BackgroundTransparency = Toggle.Value and 0 or 1 }
			):Play()
			ToggleCircle.ImageTransparency = Toggle.Value and 0 or 0.5
	
			Library:SafeCallback(Toggle.Callback, Toggle.Value)
			Library:SafeCallback(Toggle.Changed, Toggle.Value)
		end
	
		function Toggle:Destroy()
			ToggleFrame:Destroy()
			Library.Options[Idx] = nil
		end
	
		Creator.AddSignal(ToggleFrame.Frame.MouseButton1Click, function()
			Toggle:SetValue(not Toggle.Value)
		end)
	
		Toggle:SetValue(Toggle.Value)
	
		Library.Options[Idx] = Toggle
		return Toggle
	end
	
	return Element
end

__modules["Icons"] = function()
	-- Curated Lucide icon set for Fluent Rework
	-- Reduced from ~820 to ~120 most commonly used icons
	-- Full icon list: https://lucide.dev/icons/
	-- To add more icons, add entries in the format: ["lucide-name"] = "rbxassetid://ID"
	return {
		assets = {
			-- Navigation & UI
			["lucide-home"] = "rbxassetid://10723407389",
			["lucide-menu"] = "rbxassetid://10734887784",
			["lucide-settings"] = "rbxassetid://10734950309",
			["lucide-settings-2"] = "rbxassetid://10734950020",
			["lucide-search"] = "rbxassetid://10734943674",
			["lucide-filter"] = "rbxassetid://10723375128",
			["lucide-layout-dashboard"] = "rbxassetid://10723424646",
			["lucide-layout-grid"] = "rbxassetid://10723424838",
			["lucide-layout-list"] = "rbxassetid://10723424963",
			["lucide-sidebar"] = "rbxassetid://10734954301",
			["lucide-panel-left"] = "rbxassetid://10734953715",
			["lucide-panel-right"] = "rbxassetid://10734954000",
			["lucide-maximize"] = "rbxassetid://10734886735",
			["lucide-maximize-2"] = "rbxassetid://10734886496",
			["lucide-minimize"] = "rbxassetid://10734895698",
			["lucide-minimize-2"] = "rbxassetid://10734895530",
			["lucide-x"] = "rbxassetid://10747384394",
			["lucide-x-circle"] = "rbxassetid://10747383819",
			["lucide-check"] = "rbxassetid://10709790644",
			["lucide-check-circle"] = "rbxassetid://10709790387",
	
			-- Arrows & Chevrons
			["lucide-chevron-down"] = "rbxassetid://10709790948",
			["lucide-chevron-up"] = "rbxassetid://10709791523",
			["lucide-chevron-left"] = "rbxassetid://10709791281",
			["lucide-chevron-right"] = "rbxassetid://10709791437",
			["lucide-arrow-up"] = "rbxassetid://10709768939",
			["lucide-arrow-down"] = "rbxassetid://10709767827",
			["lucide-arrow-left"] = "rbxassetid://10709768114",
			["lucide-arrow-right"] = "rbxassetid://10709768347",
			["lucide-refresh-cw"] = "rbxassetid://10734933222",
			["lucide-refresh-ccw"] = "rbxassetid://10734933056",
			["lucide-rotate-cw"] = "rbxassetid://10734940654",
	
			-- Actions
			["lucide-plus"] = "rbxassetid://10734924532",
			["lucide-plus-circle"] = "rbxassetid://10734923868",
			["lucide-minus"] = "rbxassetid://10734896206",
			["lucide-minus-circle"] = "rbxassetid://10734895856",
			["lucide-edit"] = "rbxassetid://10734883598",
			["lucide-edit-2"] = "rbxassetid://10723344885",
			["lucide-trash"] = "rbxassetid://10747362393",
			["lucide-trash-2"] = "rbxassetid://10747362241",
			["lucide-copy"] = "rbxassetid://10709812159",
			["lucide-clipboard"] = "rbxassetid://10709799288",
			["lucide-save"] = "rbxassetid://10734941499",
			["lucide-download"] = "rbxassetid://10723344270",
			["lucide-upload"] = "rbxassetid://10747366434",
			["lucide-send"] = "rbxassetid://10734943902",
			["lucide-share"] = "rbxassetid://10734950813",
			["lucide-share-2"] = "rbxassetid://10734950553",
			["lucide-external-link"] = "rbxassetid://10723346684",
			["lucide-link"] = "rbxassetid://10723426722",
			["lucide-undo"] = "rbxassetid://10747365484",
			["lucide-redo"] = "rbxassetid://10734932822",
	
			-- Status & Alerts
			["lucide-info"] = "rbxassetid://10723415903",
			["lucide-alert-circle"] = "rbxassetid://10709752996",
			["lucide-alert-triangle"] = "rbxassetid://10709753149",
			["lucide-help-circle"] = "rbxassetid://10723406988",
			["lucide-bell"] = "rbxassetid://10709775704",
			["lucide-bell-ring"] = "rbxassetid://10709775560",
			["lucide-bell-off"] = "rbxassetid://10709775320",
			["lucide-check-circle-2"] = "rbxassetid://10709790298",
			["lucide-x-octagon"] = "rbxassetid://10747384037",
	
			-- User & People
			["lucide-user"] = "rbxassetid://10747373176",
			["lucide-users"] = "rbxassetid://10747373426",
			["lucide-user-plus"] = "rbxassetid://10747372702",
			["lucide-user-minus"] = "rbxassetid://10747372346",
			["lucide-user-check"] = "rbxassetid://10747371901",
			["lucide-user-x"] = "rbxassetid://10747372992",
	
			-- Gaming & Combat (Common in Roblox scripts)
			["lucide-sword"] = "rbxassetid://10734975486",
			["lucide-swords"] = "rbxassetid://10734975692",
			["lucide-shield"] = "rbxassetid://10734951847",
			["lucide-shield-check"] = "rbxassetid://10734951367",
			["lucide-shield-alert"] = "rbxassetid://10734951173",
			["lucide-shield-off"] = "rbxassetid://10734951684",
			["lucide-target"] = "rbxassetid://10734977012",
			["lucide-crosshair"] = "rbxassetid://10709818534",
			["lucide-gamepad"] = "rbxassetid://10723395457",
			["lucide-gamepad-2"] = "rbxassetid://10723395215",
			["lucide-joystick"] = "rbxassetid://10723416527",
			["lucide-trophy"] = "rbxassetid://10747363809",
			["lucide-crown"] = "rbxassetid://10709818626",
			["lucide-star"] = "rbxassetid://10734966248",
			["lucide-heart"] = "rbxassetid://10723406885",
			["lucide-skull"] = "rbxassetid://10734962068",
			["lucide-flame"] = "rbxassetid://10723376114",
			["lucide-bomb"] = "rbxassetid://10709781460",
			["lucide-wand"] = "rbxassetid://10747376565",
			["lucide-wand-2"] = "rbxassetid://10747376349",
			["lucide-axe"] = "rbxassetid://10709769508",
			["lucide-hammer"] = "rbxassetid://10723405360",
	
			-- Visual & Media
			["lucide-eye"] = "rbxassetid://10723346959",
			["lucide-eye-off"] = "rbxassetid://10723346871",
			["lucide-palette"] = "rbxassetid://10734910430",
			["lucide-paintbrush"] = "rbxassetid://10734910187",
			["lucide-image"] = "rbxassetid://10723415040",
			["lucide-camera"] = "rbxassetid://10709789686",
			["lucide-sun"] = "rbxassetid://10734974297",
			["lucide-moon"] = "rbxassetid://10734897102",
			["lucide-monitor"] = "rbxassetid://10734896881",
	
			-- System & Tools
			["lucide-cog"] = "rbxassetid://10709810948",
			["lucide-wrench"] = "rbxassetid://10747383470",
			["lucide-key"] = "rbxassetid://10723416652",
			["lucide-lock"] = "rbxassetid://10723434711",
			["lucide-unlock"] = "rbxassetid://10747366027",
			["lucide-power"] = "rbxassetid://10734930466",
			["lucide-power-off"] = "rbxassetid://10734930257",
			["lucide-terminal"] = "rbxassetid://10734982144",
			["lucide-code"] = "rbxassetid://10709810463",
			["lucide-code-2"] = "rbxassetid://10709807111",
			["lucide-database"] = "rbxassetid://10709818996",
			["lucide-server"] = "rbxassetid://10734949856",
			["lucide-cpu"] = "rbxassetid://10709813383",
			["lucide-wifi"] = "rbxassetid://10747382504",
			["lucide-wifi-off"] = "rbxassetid://10747382268",
			["lucide-globe"] = "rbxassetid://10723404337",
			["lucide-activity"] = "rbxassetid://10709752035",
			["lucide-gauge"] = "rbxassetid://10723395708",
			["lucide-sliders"] = "rbxassetid://10734963400",
			["lucide-sliders-horizontal"] = "rbxassetid://10734963191",
			["lucide-toggle-left"] = "rbxassetid://10734984834",
			["lucide-toggle-right"] = "rbxassetid://10734985040",
	
			-- File & Folder
			["lucide-file"] = "rbxassetid://10723374641",
			["lucide-file-text"] = "rbxassetid://10723367380",
			["lucide-folder"] = "rbxassetid://10723387563",
			["lucide-folder-open"] = "rbxassetid://10723386277",
	
			-- Communication
			["lucide-message-circle"] = "rbxassetid://10734888000",
			["lucide-message-square"] = "rbxassetid://10734888228",
			["lucide-mail"] = "rbxassetid://10734885430",
	
			-- Movement & Location
			["lucide-map"] = "rbxassetid://10734886202",
			["lucide-map-pin"] = "rbxassetid://10734886004",
			["lucide-compass"] = "rbxassetid://10709811445",
			["lucide-navigation"] = "rbxassetid://10734906744",
			["lucide-move"] = "rbxassetid://10734900011",
			["lucide-locate"] = "rbxassetid://10723434557",
	
			-- Misc
			["lucide-zap"] = "rbxassetid://10747384552",
			["lucide-rocket"] = "rbxassetid://10734934585",
			["lucide-bot"] = "rbxassetid://10709782230",
			["lucide-puzzle"] = "rbxassetid://10734930886",
			["lucide-box"] = "rbxassetid://10709782497",
			["lucide-package"] = "rbxassetid://10734909540",
			["lucide-layers"] = "rbxassetid://10723424505",
			["lucide-clock"] = "rbxassetid://10709805144",
			["lucide-timer"] = "rbxassetid://10734984606",
			["lucide-history"] = "rbxassetid://10723407335",
			["lucide-bookmark"] = "rbxassetid://10709782154",
			["lucide-tag"] = "rbxassetid://10734976528",
			["lucide-hash"] = "rbxassetid://10723405975",
			["lucide-fingerprint"] = "rbxassetid://10723375250",
			["lucide-loader"] = "rbxassetid://10723434070",
			["lucide-sparkle"] = "rbxassetid://10734965572",
		},
	}
end

__modules["Packages.Flipper"] = function()
	local Flipper = {
		SingleMotor = __require("Packages.Flipper.SingleMotor"),
		GroupMotor = __require("Packages.Flipper.GroupMotor"),
	
		Instant = __require("Packages.Flipper.Instant"),
		Linear = __require("Packages.Flipper.Linear"),
		Spring = __require("Packages.Flipper.Spring"),
	
		isMotor = __require("Packages.Flipper.isMotor"),
	}
	
	return Flipper
end

__modules["Packages.Flipper.BaseMotor"] = function()
	local RunService = game:GetService("RunService")
	
	local Signal = __require("Packages.Flipper.Signal")
	
	local noop = function() end
	
	local BaseMotor = {}
	BaseMotor.__index = BaseMotor
	
	function BaseMotor.new()
		return setmetatable({
			_onStep = Signal.new(),
			_onStart = Signal.new(),
			_onComplete = Signal.new(),
		}, BaseMotor)
	end
	
	function BaseMotor:onStep(handler)
		return self._onStep:connect(handler)
	end
	
	function BaseMotor:onStart(handler)
		return self._onStart:connect(handler)
	end
	
	function BaseMotor:onComplete(handler)
		return self._onComplete:connect(handler)
	end
	
	function BaseMotor:start()
		if not self._connection then
			self._connection = RunService.RenderStepped:Connect(function(deltaTime)
				self:step(deltaTime)
			end)
		end
	end
	
	function BaseMotor:stop()
		if self._connection then
			self._connection:Disconnect()
			self._connection = nil
		end
	end
	
	BaseMotor.destroy = BaseMotor.stop
	
	BaseMotor.step = noop
	BaseMotor.getValue = noop
	BaseMotor.setGoal = noop
	
	function BaseMotor:__tostring()
		return "Motor"
	end
	
	return BaseMotor
end

__modules["Packages.Flipper.BaseMotor.spec"] = function()
	return function()
		local RunService = game:GetService("RunService")
	
		local BaseMotor = __require("Packages.Flipper.BaseMotor.BaseMotor")
	
		describe("connection management", function()
			local motor = BaseMotor.new()
	
			it("should hook up connections on :start()", function()
				motor:start()
				expect(typeof(motor._connection)).to.equal("RBXScriptConnection")
			end)
	
			it("should remove connections on :stop() or :destroy()", function()
				motor:stop()
				expect(motor._connection).to.equal(nil)
			end)
		end)
	
		it("should call :step() with deltaTime", function()
			local motor = BaseMotor.new()
	
			local argumentsProvided
			function motor:step(...)
				argumentsProvided = { ... }
				motor:stop()
			end
	
			motor:start()
	
			local expectedDeltaTime = RunService.RenderStepped:Wait()
	
			-- Give it another frame, because connections tend to be invoked later than :Wait() calls
			RunService.RenderStepped:Wait()
	
			expect(argumentsProvided).to.be.ok()
			expect(argumentsProvided[1]).to.equal(expectedDeltaTime)
		end)
	end
end

__modules["Packages.Flipper.GroupMotor"] = function()
	local BaseMotor = __require("Packages.Flipper.BaseMotor")
	local SingleMotor = __require("Packages.Flipper.SingleMotor")
	
	local isMotor = __require("Packages.Flipper.isMotor")
	
	local GroupMotor = setmetatable({}, BaseMotor)
	GroupMotor.__index = GroupMotor
	
	local function toMotor(value)
		if isMotor(value) then
			return value
		end
	
		local valueType = typeof(value)
	
		if valueType == "number" then
			return SingleMotor.new(value, false)
		elseif valueType == "table" then
			return GroupMotor.new(value, false)
		end
	
		error(("Unable to convert %q to motor; type %s is unsupported"):format(value, valueType), 2)
	end
	
	function GroupMotor.new(initialValues, useImplicitConnections)
		assert(initialValues, "Missing argument #1: initialValues")
		assert(typeof(initialValues) == "table", "initialValues must be a table!")
		assert(
			not initialValues.step,
			'initialValues contains disallowed property "step". Did you mean to put a table of values here?'
		)
	
		local self = setmetatable(BaseMotor.new(), GroupMotor)
	
		if useImplicitConnections ~= nil then
			self._useImplicitConnections = useImplicitConnections
		else
			self._useImplicitConnections = true
		end
	
		self._complete = true
		self._motors = {}
	
		for key, value in pairs(initialValues) do
			self._motors[key] = toMotor(value)
		end
	
		return self
	end
	
	function GroupMotor:step(deltaTime)
		if self._complete then
			return true
		end
	
		local allMotorsComplete = true
	
		for _, motor in pairs(self._motors) do
			local complete = motor:step(deltaTime)
			if not complete then
				-- If any of the sub-motors are incomplete, the group motor will not be complete either
				allMotorsComplete = false
			end
		end
	
		self._onStep:fire(self:getValue())
	
		if allMotorsComplete then
			if self._useImplicitConnections then
				self:stop()
			end
	
			self._complete = true
			self._onComplete:fire()
		end
	
		return allMotorsComplete
	end
	
	function GroupMotor:setGoal(goals)
		assert(not goals.step, 'goals contains disallowed property "step". Did you mean to put a table of goals here?')
	
		self._complete = false
		self._onStart:fire()
	
		for key, goal in pairs(goals) do
			local motor = assert(self._motors[key], ("Unknown motor for key %s"):format(key))
			motor:setGoal(goal)
		end
	
		if self._useImplicitConnections then
			self:start()
		end
	end
	
	function GroupMotor:getValue()
		local values = {}
	
		for key, motor in pairs(self._motors) do
			values[key] = motor:getValue()
		end
	
		return values
	end
	
	function GroupMotor:__tostring()
		return "Motor(Group)"
	end
	
	return GroupMotor
end

__modules["Packages.Flipper.GroupMotor.spec"] = function()
	return function()
		local GroupMotor = __require("Packages.Flipper.GroupMotor.GroupMotor")
	
		local Instant = __require("Packages.Flipper.GroupMotor.Instant")
		local Spring = __require("Packages.Flipper.GroupMotor.Spring")
	
		it("should complete when all child motors are complete", function()
			local motor = GroupMotor.new({
				A = 1,
				B = 2,
			}, false)
	
			expect(motor._complete).to.equal(true)
	
			motor:setGoal({
				A = Instant.new(3),
				B = Spring.new(4, { frequency = 7.5, dampingRatio = 1 }),
			})
	
			expect(motor._complete).to.equal(false)
	
			motor:step(1 / 60)
	
			expect(motor._complete).to.equal(false)
	
			for _ = 1, 0.5 * 60 do
				motor:step(1 / 60)
			end
	
			expect(motor._complete).to.equal(true)
		end)
	
		it("should start when the goal is set", function()
			local motor = GroupMotor.new({
				A = 0,
			}, false)
	
			local bool = false
			motor:onStart(function()
				bool = not bool
			end)
	
			motor:setGoal({
				A = Instant.new(1),
			})
	
			expect(bool).to.equal(true)
	
			motor:setGoal({
				A = Instant.new(1),
			})
	
			expect(bool).to.equal(false)
		end)
	
		it("should properly return all values", function()
			local motor = GroupMotor.new({
				A = 1,
				B = 2,
			}, false)
	
			local value = motor:getValue()
	
			expect(value.A).to.equal(1)
			expect(value.B).to.equal(2)
		end)
	
		it("should error when a goal is given to GroupMotor.new", function()
			local success = pcall(function()
				GroupMotor.new(Instant.new(0))
			end)
	
			expect(success).to.equal(false)
		end)
	
		it("should error when a single goal is provided to GroupMotor:step", function()
			local success = pcall(function()
				GroupMotor.new({ a = 1 }):setGoal(Instant.new(0))
			end)
	
			expect(success).to.equal(false)
		end)
	end
end

__modules["Packages.Flipper.Instant"] = function()
	local Instant = {}
	Instant.__index = Instant
	
	function Instant.new(targetValue)
		return setmetatable({
			_targetValue = targetValue,
		}, Instant)
	end
	
	function Instant:step()
		return {
			complete = true,
			value = self._targetValue,
		}
	end
	
	return Instant
end

__modules["Packages.Flipper.Instant.spec"] = function()
	return function()
		local Instant = __require("Packages.Flipper.Instant.Instant")
	
		it("should return a completed state with the provided value", function()
			local goal = Instant.new(1.23)
			local state = goal:step(0.1, { value = 0, complete = false })
			expect(state.complete).to.equal(true)
			expect(state.value).to.equal(1.23)
		end)
	end
end

__modules["Packages.Flipper.Linear"] = function()
	local Linear = {}
	Linear.__index = Linear
	
	function Linear.new(targetValue, options)
		assert(targetValue, "Missing argument #1: targetValue")
	
		options = options or {}
	
		return setmetatable({
			_targetValue = targetValue,
			_velocity = options.velocity or 1,
		}, Linear)
	end
	
	function Linear:step(state, dt)
		local position = state.value
		local velocity = self._velocity -- Linear motion ignores the state's velocity
		local goal = self._targetValue
	
		local dPos = dt * velocity
	
		local complete = dPos >= math.abs(goal - position)
		position = position + dPos * (goal > position and 1 or -1)
		if complete then
			position = self._targetValue
			velocity = 0
		end
	
		return {
			complete = complete,
			value = position,
			velocity = velocity,
		}
	end
	
	return Linear
end

__modules["Packages.Flipper.Linear.spec"] = function()
	return function()
		local SingleMotor = __require("Packages.Flipper.Linear.SingleMotor")
		local Linear = __require("Packages.Flipper.Linear.Linear")
	
		describe("completed state", function()
			local motor = SingleMotor.new(0, false)
	
			local goal = Linear.new(1, { velocity = 1 })
			motor:setGoal(goal)
	
			for _ = 1, 60 do
				motor:step(1 / 60)
			end
	
			it("should complete", function()
				expect(motor._state.complete).to.equal(true)
			end)
	
			it("should be exactly the goal value when completed", function()
				expect(motor._state.value).to.equal(1)
			end)
		end)
	
		describe("uncompleted state", function()
			local motor = SingleMotor.new(0, false)
	
			local goal = Linear.new(1, { velocity = 1 })
			motor:setGoal(goal)
	
			for _ = 1, 59 do
				motor:step(1 / 60)
			end
	
			it("should be uncomplete", function()
				expect(motor._state.complete).to.equal(false)
			end)
		end)
	
		describe("negative velocity", function()
			local motor = SingleMotor.new(1, false)
	
			local goal = Linear.new(0, { velocity = 1 })
			motor:setGoal(goal)
	
			for _ = 1, 60 do
				motor:step(1 / 60)
			end
	
			it("should complete", function()
				expect(motor._state.complete).to.equal(true)
			end)
	
			it("should be exactly the goal value when completed", function()
				expect(motor._state.value).to.equal(0)
			end)
		end)
	end
end

__modules["Packages.Flipper.Signal"] = function()
	local Connection = {}
	Connection.__index = Connection
	
	function Connection.new(signal, handler)
		return setmetatable({
			signal = signal,
			connected = true,
			_handler = handler,
		}, Connection)
	end
	
	function Connection:disconnect()
		if self.connected then
			self.connected = false
	
			for index, connection in pairs(self.signal._connections) do
				if connection == self then
					table.remove(self.signal._connections, index)
					return
				end
			end
		end
	end
	
	local Signal = {}
	Signal.__index = Signal
	
	function Signal.new()
		return setmetatable({
			_connections = {},
			_threads = {},
		}, Signal)
	end
	
	function Signal:fire(...)
		for _, connection in pairs(self._connections) do
			connection._handler(...)
		end
	
		for _, thread in pairs(self._threads) do
			coroutine.resume(thread, ...)
		end
	
		self._threads = {}
	end
	
	function Signal:connect(handler)
		local connection = Connection.new(self, handler)
		table.insert(self._connections, connection)
		return connection
	end
	
	function Signal:wait()
		table.insert(self._threads, coroutine.running())
		return coroutine.yield()
	end
	
	return Signal
end

__modules["Packages.Flipper.Signal.spec"] = function()
	return function()
		local Signal = __require("Packages.Flipper.Signal.Signal")
	
		it("should invoke all connections, instantly", function()
			local signal = Signal.new()
	
			local a, b
	
			signal:connect(function(value)
				a = value
			end)
	
			signal:connect(function(value)
				b = value
			end)
	
			signal:fire("hello")
	
			expect(a).to.equal("hello")
			expect(b).to.equal("hello")
		end)
	
		it("should return values when :wait() is called", function()
			local signal = Signal.new()
	
			spawn(function()
				signal:fire(123, "hello")
			end)
	
			local a, b = signal:wait()
	
			expect(a).to.equal(123)
			expect(b).to.equal("hello")
		end)
	
		it("should properly handle disconnections", function()
			local signal = Signal.new()
	
			local didRun = false
	
			local connection = signal:connect(function()
				didRun = true
			end)
			connection:disconnect()
	
			signal:fire()
			expect(didRun).to.equal(false)
		end)
	end
end

__modules["Packages.Flipper.SingleMotor"] = function()
	local BaseMotor = __require("Packages.Flipper.BaseMotor")
	
	local SingleMotor = setmetatable({}, BaseMotor)
	SingleMotor.__index = SingleMotor
	
	function SingleMotor.new(initialValue, useImplicitConnections)
		assert(initialValue, "Missing argument #1: initialValue")
		assert(typeof(initialValue) == "number", "initialValue must be a number!")
	
		local self = setmetatable(BaseMotor.new(), SingleMotor)
	
		if useImplicitConnections ~= nil then
			self._useImplicitConnections = useImplicitConnections
		else
			self._useImplicitConnections = true
		end
	
		self._goal = nil
		self._state = {
			complete = true,
			value = initialValue,
		}
	
		return self
	end
	
	function SingleMotor:step(deltaTime)
		if self._state.complete then
			return true
		end
	
		local newState = self._goal:step(self._state, deltaTime)
	
		self._state = newState
		self._onStep:fire(newState.value)
	
		if newState.complete then
			if self._useImplicitConnections then
				self:stop()
			end
	
			self._onComplete:fire()
		end
	
		return newState.complete
	end
	
	function SingleMotor:getValue()
		return self._state.value
	end
	
	function SingleMotor:setGoal(goal)
		self._state.complete = false
		self._goal = goal
	
		self._onStart:fire()
	
		if self._useImplicitConnections then
			self:start()
		end
	end
	
	function SingleMotor:__tostring()
		return "Motor(Single)"
	end
	
	return SingleMotor
end

__modules["Packages.Flipper.SingleMotor.spec"] = function()
	return function()
		local SingleMotor = __require("Packages.Flipper.SingleMotor.SingleMotor")
		local Instant = __require("Packages.Flipper.SingleMotor.Instant")
	
		it("should assign new state on step", function()
			local motor = SingleMotor.new(0, false)
	
			motor:setGoal(Instant.new(5))
			motor:step(1 / 60)
	
			expect(motor._state.complete).to.equal(true)
			expect(motor._state.value).to.equal(5)
		end)
	
		it("should invoke onComplete listeners when the goal is completed", function()
			local motor = SingleMotor.new(0, false)
	
			local didComplete = false
			motor:onComplete(function()
				didComplete = true
			end)
	
			motor:setGoal(Instant.new(5))
			motor:step(1 / 60)
	
			expect(didComplete).to.equal(true)
		end)
	
		it("should start when the goal is set", function()
			local motor = SingleMotor.new(0, false)
	
			local bool = false
			motor:onStart(function()
				bool = not bool
			end)
	
			motor:setGoal(Instant.new(5))
	
			expect(bool).to.equal(true)
	
			motor:setGoal(Instant.new(5))
	
			expect(bool).to.equal(false)
		end)
	end
end

__modules["Packages.Flipper.Spring"] = function()
	local VELOCITY_THRESHOLD = 0.001
	local POSITION_THRESHOLD = 0.001
	
	local EPS = 0.0001
	
	local Spring = {}
	Spring.__index = Spring
	
	function Spring.new(targetValue, options)
		assert(targetValue, "Missing argument #1: targetValue")
		options = options or {}
	
		return setmetatable({
			_targetValue = targetValue,
			_frequency = options.frequency or 4,
			_dampingRatio = options.dampingRatio or 1,
		}, Spring)
	end
	
	function Spring:step(state, dt)
		-- Copyright 2018 Parker Stebbins (parker@fractality.io)
		-- github.com/Fraktality/Spring
		-- Distributed under the MIT license
	
		local d = self._dampingRatio
		local f = self._frequency * 2 * math.pi
		local g = self._targetValue
		local p0 = state.value
		local v0 = state.velocity or 0
	
		local offset = p0 - g
		local decay = math.exp(-d * f * dt)
	
		local p1, v1
	
		if d == 1 then -- Critically damped
			p1 = (offset * (1 + f * dt) + v0 * dt) * decay + g
			v1 = (v0 * (1 - f * dt) - offset * (f * f * dt)) * decay
		elseif d < 1 then -- Underdamped
			local c = math.sqrt(1 - d * d)
	
			local i = math.cos(f * c * dt)
			local j = math.sin(f * c * dt)
	
			-- Damping ratios approaching 1 can cause division by small numbers.
			-- To fix that, group terms around z=j/c and find an approximation for z.
			-- Start with the definition of z:
			--    z = sin(dt*f*c)/c
			-- Substitute a=dt*f:
			--    z = sin(a*c)/c
			-- Take the Maclaurin expansion of z with respect to c:
			--    z = a - (a^3*c^2)/6 + (a^5*c^4)/120 + O(c^6)
			--    z ≈ a - (a^3*c^2)/6 + (a^5*c^4)/120
			-- Rewrite in Horner form:
			--    z ≈ a + ((a*a)*(c*c)*(c*c)/20 - c*c)*(a*a*a)/6
	
			local z
			if c > EPS then
				z = j / c
			else
				local a = dt * f
				z = a + ((a * a) * (c * c) * (c * c) / 20 - c * c) * (a * a * a) / 6
			end
	
			-- Frequencies approaching 0 present a similar problem.
			-- We want an approximation for y as f approaches 0, where:
			--    y = sin(dt*f*c)/(f*c)
			-- Substitute b=dt*c:
			--    y = sin(b*c)/b
			-- Now reapply the process from z.
	
			local y
			if f * c > EPS then
				y = j / (f * c)
			else
				local b = f * c
				y = dt + ((dt * dt) * (b * b) * (b * b) / 20 - b * b) * (dt * dt * dt) / 6
			end
	
			p1 = (offset * (i + d * z) + v0 * y) * decay + g
			v1 = (v0 * (i - z * d) - offset * (z * f)) * decay
		else -- Overdamped
			local c = math.sqrt(d * d - 1)
	
			local r1 = -f * (d - c)
			local r2 = -f * (d + c)
	
			local co2 = (v0 - offset * r1) / (2 * f * c)
			local co1 = offset - co2
	
			local e1 = co1 * math.exp(r1 * dt)
			local e2 = co2 * math.exp(r2 * dt)
	
			p1 = e1 + e2 + g
			v1 = e1 * r1 + e2 * r2
		end
	
		local complete = math.abs(v1) < VELOCITY_THRESHOLD and math.abs(p1 - g) < POSITION_THRESHOLD
	
		return {
			complete = complete,
			value = complete and g or p1,
			velocity = v1,
		}
	end
	
	return Spring
end

__modules["Packages.Flipper.Spring.spec"] = function()
	return function()
		local SingleMotor = __require("Packages.Flipper.Spring.SingleMotor")
		local Spring = __require("Packages.Flipper.Spring.Spring")
	
		describe("completed state", function()
			local motor = SingleMotor.new(0, false)
	
			local goal = Spring.new(1, { frequency = 2, dampingRatio = 0.75 })
			motor:setGoal(goal)
	
			for _ = 1, 100 do
				motor:step(1 / 60)
			end
	
			it("should complete", function()
				expect(motor._state.complete).to.equal(true)
			end)
	
			it("should be exactly the goal value when completed", function()
				expect(motor._state.value).to.equal(1)
			end)
		end)
	
		it("should inherit velocity", function()
			local motor = SingleMotor.new(0, false)
			motor._state = { complete = false, value = 0, velocity = -5 }
	
			local goal = Spring.new(1, { frequency = 2, dampingRatio = 1 })
	
			motor:setGoal(goal)
			motor:step(1 / 60)
	
			expect(motor._state.velocity < 0).to.equal(true)
		end)
	end
end

__modules["Packages.Flipper.isMotor"] = function()
	local function isMotor(value)
		local motorType = tostring(value):match("^Motor%((.+)%)$")
	
		if motorType then
			return true, motorType
		else
			return false
		end
	end
	
	return isMotor
end

__modules["Packages.Flipper.isMotor.spec"] = function()
	return function()
		local isMotor = __require("Packages.Flipper.isMotor.isMotor")
	
		local SingleMotor = __require("Packages.Flipper.isMotor.SingleMotor")
		local GroupMotor = __require("Packages.Flipper.isMotor.GroupMotor")
	
		local singleMotor = SingleMotor.new(0)
		local groupMotor = GroupMotor.new({})
	
		it("should properly detect motors", function()
			expect(isMotor(singleMotor)).to.equal(true)
			expect(isMotor(groupMotor)).to.equal(true)
		end)
	
		it("shouldn't detect things that aren't motors", function()
			expect(isMotor({})).to.equal(false)
		end)
	
		it("should return the proper motor type", function()
			local _, singleMotorType = isMotor(singleMotor)
			local _, groupMotorType = isMotor(groupMotor)
	
			expect(singleMotorType).to.equal("Single")
			expect(groupMotorType).to.equal("Group")
		end)
	end
end

__modules["Themes"] = function()
	local Themes = {
		Names = {
			"Dark",
			"Darker",
			"Light",
			"Aqua",
			"Amethyst",
			"Rose",
		},
	}
	
	for _, Theme in next, script:GetChildren() do
		local Required = require(Theme)
		Themes[Required.Name] = Required
	end
	
	return Themes
end

__modules["Themes.Amethyst"] = function()
	return {
		Name = "Amethyst",
		Accent = Color3.fromRGB(97, 62, 167),
	
		AcrylicMain = Color3.fromRGB(20, 20, 20),
		AcrylicBorder = Color3.fromRGB(110, 90, 130),
		AcrylicGradient = ColorSequence.new(Color3.fromRGB(85, 57, 139), Color3.fromRGB(40, 25, 65)),
		AcrylicNoise = 0.92,
	
		TitleBarLine = Color3.fromRGB(95, 75, 110),
		Tab = Color3.fromRGB(160, 140, 180),
	
		Element = Color3.fromRGB(140, 120, 160),
		ElementBorder = Color3.fromRGB(60, 50, 70),
		InElementBorder = Color3.fromRGB(100, 90, 110),
		ElementTransparency = 0.87,
	
		ToggleSlider = Color3.fromRGB(140, 120, 160),
		ToggleToggled = Color3.fromRGB(0, 0, 0),
	
		SliderRail = Color3.fromRGB(140, 120, 160),
	
		DropdownFrame = Color3.fromRGB(170, 160, 200),
		DropdownHolder = Color3.fromRGB(60, 45, 80),
		DropdownBorder = Color3.fromRGB(50, 40, 65),
		DropdownOption = Color3.fromRGB(140, 120, 160),
	
		Keybind = Color3.fromRGB(140, 120, 160),
	
		Input = Color3.fromRGB(140, 120, 160),
		InputFocused = Color3.fromRGB(20, 10, 30),
		InputIndicator = Color3.fromRGB(170, 150, 190),
	
		Dialog = Color3.fromRGB(60, 45, 80),
		DialogHolder = Color3.fromRGB(45, 30, 65),
		DialogHolderLine = Color3.fromRGB(40, 25, 60),
		DialogButton = Color3.fromRGB(60, 45, 80),
		DialogButtonBorder = Color3.fromRGB(95, 80, 110),
		DialogBorder = Color3.fromRGB(85, 70, 100),
		DialogInput = Color3.fromRGB(70, 55, 85),
		DialogInputLine = Color3.fromRGB(175, 160, 190),
	
		Text = Color3.fromRGB(240, 240, 240),
		SubText = Color3.fromRGB(170, 170, 170),
		Hover = Color3.fromRGB(140, 120, 160),
		HoverChange = 0.04,
	
		-- Phase 2: New UI properties
		SidebarDivider = Color3.fromRGB(65, 50, 85),
		StatusBar = Color3.fromRGB(35, 25, 55),
		StatusBarText = Color3.fromRGB(140, 120, 170),
		TabSectionHeader = Color3.fromRGB(130, 110, 155),
		SelectedTabIndicator = Color3.fromRGB(97, 62, 167),
		GlowColor = Color3.fromRGB(97, 62, 167),
	}
end

__modules["Themes.Aqua"] = function()
	return {
		Name = "Aqua",
		Accent = Color3.fromRGB(60, 165, 165),
	
		AcrylicMain = Color3.fromRGB(20, 20, 20),
		AcrylicBorder = Color3.fromRGB(50, 100, 100),
		AcrylicGradient = ColorSequence.new(Color3.fromRGB(60, 140, 140), Color3.fromRGB(40, 80, 80)),
		AcrylicNoise = 0.92,
	
		TitleBarLine = Color3.fromRGB(60, 120, 120),
		Tab = Color3.fromRGB(140, 180, 180),
	
		Element = Color3.fromRGB(110, 160, 160),
		ElementBorder = Color3.fromRGB(40, 70, 70),
		InElementBorder = Color3.fromRGB(80, 110, 110),
		ElementTransparency = 0.84,
	
		ToggleSlider = Color3.fromRGB(110, 160, 160),
		ToggleToggled = Color3.fromRGB(0, 0, 0),
	
		SliderRail = Color3.fromRGB(110, 160, 160),
	
		DropdownFrame = Color3.fromRGB(160, 200, 200),
		DropdownHolder = Color3.fromRGB(40, 80, 80),
		DropdownBorder = Color3.fromRGB(40, 65, 65),
		DropdownOption = Color3.fromRGB(110, 160, 160),
	
		Keybind = Color3.fromRGB(110, 160, 160),
	
		Input = Color3.fromRGB(110, 160, 160),
		InputFocused = Color3.fromRGB(20, 10, 30),
		InputIndicator = Color3.fromRGB(130, 170, 170),
	
		Dialog = Color3.fromRGB(40, 80, 80),
		DialogHolder = Color3.fromRGB(30, 60, 60),
		DialogHolderLine = Color3.fromRGB(25, 50, 50),
		DialogButton = Color3.fromRGB(40, 80, 80),
		DialogButtonBorder = Color3.fromRGB(80, 110, 110),
		DialogBorder = Color3.fromRGB(50, 100, 100),
		DialogInput = Color3.fromRGB(45, 90, 90),
		DialogInputLine = Color3.fromRGB(130, 170, 170),
	
		Text = Color3.fromRGB(240, 240, 240),
		SubText = Color3.fromRGB(170, 170, 170),
		Hover = Color3.fromRGB(110, 160, 160),
		HoverChange = 0.04,
	
		-- Phase 2: New UI properties
		SidebarDivider = Color3.fromRGB(40, 85, 85),
		StatusBar = Color3.fromRGB(25, 55, 55),
		StatusBarText = Color3.fromRGB(120, 170, 170),
		TabSectionHeader = Color3.fromRGB(100, 155, 155),
		SelectedTabIndicator = Color3.fromRGB(60, 165, 165),
		GlowColor = Color3.fromRGB(60, 165, 165),
	}
end

__modules["Themes.Dark"] = function()
	return {
		Name = "Dark",
		Accent = Color3.fromRGB(96, 205, 255),
	
		AcrylicMain = Color3.fromRGB(60, 60, 60),
		AcrylicBorder = Color3.fromRGB(90, 90, 90),
		AcrylicGradient = ColorSequence.new(Color3.fromRGB(40, 40, 40), Color3.fromRGB(40, 40, 40)),
		AcrylicNoise = 0.9,
	
		TitleBarLine = Color3.fromRGB(75, 75, 75),
		Tab = Color3.fromRGB(120, 120, 120),
	
		Element = Color3.fromRGB(120, 120, 120),
		ElementBorder = Color3.fromRGB(35, 35, 35),
		InElementBorder = Color3.fromRGB(90, 90, 90),
		ElementTransparency = 0.87,
	
		ToggleSlider = Color3.fromRGB(120, 120, 120),
		ToggleToggled = Color3.fromRGB(0, 0, 0),
	
		SliderRail = Color3.fromRGB(120, 120, 120),
	
		DropdownFrame = Color3.fromRGB(160, 160, 160),
		DropdownHolder = Color3.fromRGB(45, 45, 45),
		DropdownBorder = Color3.fromRGB(35, 35, 35),
		DropdownOption = Color3.fromRGB(120, 120, 120),
	
		Keybind = Color3.fromRGB(120, 120, 120),
	
		Input = Color3.fromRGB(160, 160, 160),
		InputFocused = Color3.fromRGB(10, 10, 10),
		InputIndicator = Color3.fromRGB(150, 150, 150),
	
		Dialog = Color3.fromRGB(45, 45, 45),
		DialogHolder = Color3.fromRGB(35, 35, 35),
		DialogHolderLine = Color3.fromRGB(30, 30, 30),
		DialogButton = Color3.fromRGB(45, 45, 45),
		DialogButtonBorder = Color3.fromRGB(80, 80, 80),
		DialogBorder = Color3.fromRGB(70, 70, 70),
		DialogInput = Color3.fromRGB(55, 55, 55),
		DialogInputLine = Color3.fromRGB(160, 160, 160),
	
		Text = Color3.fromRGB(240, 240, 240),
		SubText = Color3.fromRGB(170, 170, 170),
		Hover = Color3.fromRGB(120, 120, 120),
		HoverChange = 0.07,
	
		-- Phase 2: New UI properties
		SidebarDivider = Color3.fromRGB(55, 55, 55),
		StatusBar = Color3.fromRGB(35, 35, 35),
		StatusBarText = Color3.fromRGB(140, 140, 140),
		TabSectionHeader = Color3.fromRGB(130, 130, 130),
		SelectedTabIndicator = Color3.fromRGB(96, 205, 255),
		GlowColor = Color3.fromRGB(96, 205, 255),
	}
end

__modules["Themes.Darker"] = function()
	return {
		Name = "Darker",
		Accent = Color3.fromRGB(72, 138, 182),
	
		AcrylicMain = Color3.fromRGB(30, 30, 30),
		AcrylicBorder = Color3.fromRGB(60, 60, 60),
		AcrylicGradient = ColorSequence.new(Color3.fromRGB(25, 25, 25), Color3.fromRGB(15, 15, 15)),
		AcrylicNoise = 0.94,
	
		TitleBarLine = Color3.fromRGB(65, 65, 65),
		Tab = Color3.fromRGB(100, 100, 100),
	
		Element = Color3.fromRGB(70, 70, 70),
		ElementBorder = Color3.fromRGB(25, 25, 25),
		InElementBorder = Color3.fromRGB(55, 55, 55),
		ElementTransparency = 0.82,
	
		ToggleSlider = Color3.fromRGB(90, 90, 90),
		ToggleToggled = Color3.fromRGB(0, 0, 0),
	
		SliderRail = Color3.fromRGB(90, 90, 90),
	
		DropdownFrame = Color3.fromRGB(120, 120, 120),
		DropdownHolder = Color3.fromRGB(35, 35, 35),
		DropdownBorder = Color3.fromRGB(25, 25, 25),
		DropdownOption = Color3.fromRGB(90, 90, 90),
	
		Keybind = Color3.fromRGB(90, 90, 90),
	
		Input = Color3.fromRGB(120, 120, 120),
		InputFocused = Color3.fromRGB(8, 8, 8),
		InputIndicator = Color3.fromRGB(110, 110, 110),
	
		Dialog = Color3.fromRGB(35, 35, 35),
		DialogHolder = Color3.fromRGB(25, 25, 25),
		DialogHolderLine = Color3.fromRGB(20, 20, 20),
		DialogButton = Color3.fromRGB(35, 35, 35),
		DialogButtonBorder = Color3.fromRGB(55, 55, 55),
		DialogBorder = Color3.fromRGB(50, 50, 50),
		DialogInput = Color3.fromRGB(45, 45, 45),
		DialogInputLine = Color3.fromRGB(120, 120, 120),
	
		Text = Color3.fromRGB(230, 230, 230),
		SubText = Color3.fromRGB(150, 150, 150),
		Hover = Color3.fromRGB(90, 90, 90),
		HoverChange = 0.07,
	
		-- Phase 2: New UI properties
		SidebarDivider = Color3.fromRGB(40, 40, 40),
		StatusBar = Color3.fromRGB(22, 22, 22),
		StatusBarText = Color3.fromRGB(120, 120, 120),
		TabSectionHeader = Color3.fromRGB(110, 110, 110),
		SelectedTabIndicator = Color3.fromRGB(72, 138, 182),
		GlowColor = Color3.fromRGB(72, 138, 182),
	}
end

__modules["Themes.Light"] = function()
	return {
		Name = "Light",
		Accent = Color3.fromRGB(0, 103, 192),
	
		AcrylicMain = Color3.fromRGB(200, 200, 200),
		AcrylicBorder = Color3.fromRGB(120, 120, 120),
		AcrylicGradient = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255)),
		AcrylicNoise = 0.96,
	
		TitleBarLine = Color3.fromRGB(160, 160, 160),
		Tab = Color3.fromRGB(90, 90, 90),
	
		Element = Color3.fromRGB(255, 255, 255),
		ElementBorder = Color3.fromRGB(180, 180, 180),
		InElementBorder = Color3.fromRGB(150, 150, 150),
		ElementTransparency = 0.65,
	
		ToggleSlider = Color3.fromRGB(40, 40, 40),
		ToggleToggled = Color3.fromRGB(255, 255, 255),
	
		SliderRail = Color3.fromRGB(40, 40, 40),
	
		DropdownFrame = Color3.fromRGB(200, 200, 200),
		DropdownHolder = Color3.fromRGB(240, 240, 240),
		DropdownBorder = Color3.fromRGB(200, 200, 200),
		DropdownOption = Color3.fromRGB(150, 150, 150),
	
		Keybind = Color3.fromRGB(120, 120, 120),
	
		Input = Color3.fromRGB(200, 200, 200),
		InputFocused = Color3.fromRGB(100, 100, 100),
		InputIndicator = Color3.fromRGB(80, 80, 80),
	
		Dialog = Color3.fromRGB(255, 255, 255),
		DialogHolder = Color3.fromRGB(240, 240, 240),
		DialogHolderLine = Color3.fromRGB(228, 228, 228),
		DialogButton = Color3.fromRGB(255, 255, 255),
		DialogButtonBorder = Color3.fromRGB(190, 190, 190),
		DialogBorder = Color3.fromRGB(140, 140, 140),
		DialogInput = Color3.fromRGB(250, 250, 250),
		DialogInputLine = Color3.fromRGB(160, 160, 160),
	
		Text = Color3.fromRGB(0, 0, 0),
		SubText = Color3.fromRGB(40, 40, 40),
		Hover = Color3.fromRGB(50, 50, 50),
		HoverChange = 0.16,
	
		-- Phase 2: New UI properties
		SidebarDivider = Color3.fromRGB(200, 200, 200),
		StatusBar = Color3.fromRGB(235, 235, 235),
		StatusBarText = Color3.fromRGB(100, 100, 100),
		TabSectionHeader = Color3.fromRGB(80, 80, 80),
		SelectedTabIndicator = Color3.fromRGB(0, 103, 192),
		GlowColor = Color3.fromRGB(0, 103, 192),
	}
end

__modules["Themes.Rose"] = function()
	return {
		Name = "Rose",
		Accent = Color3.fromRGB(180, 55, 90),
	
		AcrylicMain = Color3.fromRGB(40, 40, 40),
		AcrylicBorder = Color3.fromRGB(130, 90, 110),
		AcrylicGradient = ColorSequence.new(Color3.fromRGB(190, 60, 135), Color3.fromRGB(165, 50, 70)),
		AcrylicNoise = 0.92,
	
		TitleBarLine = Color3.fromRGB(140, 85, 105),
		Tab = Color3.fromRGB(180, 140, 160),
	
		Element = Color3.fromRGB(200, 120, 170),
		ElementBorder = Color3.fromRGB(110, 70, 85),
		InElementBorder = Color3.fromRGB(120, 90, 90),
		ElementTransparency = 0.86,
	
		ToggleSlider = Color3.fromRGB(200, 120, 170),
		ToggleToggled = Color3.fromRGB(0, 0, 0),
	
		SliderRail = Color3.fromRGB(200, 120, 170),
	
		DropdownFrame = Color3.fromRGB(200, 160, 180),
		DropdownHolder = Color3.fromRGB(120, 50, 75),
		DropdownBorder = Color3.fromRGB(90, 40, 55),
		DropdownOption = Color3.fromRGB(200, 120, 170),
	
		Keybind = Color3.fromRGB(200, 120, 170),
	
		Input = Color3.fromRGB(200, 120, 170),
		InputFocused = Color3.fromRGB(20, 10, 30),
		InputIndicator = Color3.fromRGB(170, 150, 190),
	
		Dialog = Color3.fromRGB(120, 50, 75),
		DialogHolder = Color3.fromRGB(95, 40, 60),
		DialogHolderLine = Color3.fromRGB(90, 35, 55),
		DialogButton = Color3.fromRGB(120, 50, 75),
		DialogButtonBorder = Color3.fromRGB(155, 90, 115),
		DialogBorder = Color3.fromRGB(100, 70, 90),
		DialogInput = Color3.fromRGB(135, 55, 80),
		DialogInputLine = Color3.fromRGB(190, 160, 180),
	
		Text = Color3.fromRGB(240, 240, 240),
		SubText = Color3.fromRGB(170, 170, 170),
		Hover = Color3.fromRGB(200, 120, 170),
		HoverChange = 0.04,
	
		-- Phase 2: New UI properties
		SidebarDivider = Color3.fromRGB(120, 60, 80),
		StatusBar = Color3.fromRGB(80, 35, 55),
		StatusBarText = Color3.fromRGB(180, 130, 155),
		TabSectionHeader = Color3.fromRGB(170, 115, 145),
		SelectedTabIndicator = Color3.fromRGB(180, 55, 90),
		GlowColor = Color3.fromRGB(180, 55, 90),
	}
end

__modules["_ROOT_"] = function()
	local Lighting = game:GetService("Lighting")
	local RunService = game:GetService("RunService")
	local LocalPlayer = game:GetService("Players").LocalPlayer
	local UserInputService = game:GetService("UserInputService")
	local TweenService = game:GetService("TweenService")
	local Camera = game:GetService("Workspace").CurrentCamera
	local Mouse = LocalPlayer:GetMouse()
	
	local Root = __get_script_proxy("_ROOT_")
	local Creator = __require("Creator")
	local ElementsTable = __require("Elements")
	local Acrylic = __require("Acrylic")
	local Components = Root.Components
	local NotificationModule = require(Components.Notification)
	
	local New = Creator.New
	
	local ProtectGui = protectgui or (syn and syn.protect_gui) or function() end
	local GUI = New("ScreenGui", {
		Parent = RunService:IsStudio() and LocalPlayer.PlayerGui or game:GetService("CoreGui"),
	})
	ProtectGui(GUI)
	NotificationModule:Init(GUI)
	
	local Library = {
		Version = "1.1.0",
	
		OpenFrames = {},
		Options = {},
		Themes = __require("Themes").Names,
	
		Window = nil,
		WindowFrame = nil,
		Unloaded = false,
	
		Theme = "Dark",
		DialogOpen = false,
		UseAcrylic = true,
		Acrylic = true,
		Transparency = true,
		MinimizeKeybind = nil,
		MinimizeKey = Enum.KeyCode.LeftControl,
	
		GUI = GUI,
	}
	
	function Library:SafeCallback(Function, ...)
		if not Function then
			return
		end
	
		local Success, Event = pcall(Function, ...)
		if not Success then
			local _, i = Event:find(":%d+: ")
	
			if not i then
				return Library:Notify({
					Title = "Interface",
					Content = "Callback error",
					SubContent = Event,
					Duration = 5,
				})
			end
	
			return Library:Notify({
				Title = "Interface",
				Content = "Callback error",
				SubContent = Event:sub(i + 1),
				Duration = 5,
			})
		end
	end
	
	function Library:Round(Number, Factor)
		if Factor == 0 then
			return math.floor(Number)
		end
		Number = tostring(Number)
		return Number:find("%.") and tonumber(Number:sub(1, Number:find("%.") + Factor)) or Number
	end
	
	local Icons = __require("Icons").assets
	function Library:GetIcon(Name)
		if Name ~= nil and Icons["lucide-" .. Name] then
			return Icons["lucide-" .. Name]
		end
		return nil
	end
	
	local Elements = {}
	Elements.__index = Elements
	Elements.__namecall = function(Table, Key, ...)
		return Elements[Key](...)
	end
	
	for _, ElementComponent in ipairs(ElementsTable) do
		Elements["Add" .. ElementComponent.__type] = function(self, Idx, Config)
			ElementComponent.Container = self.Container
			ElementComponent.Type = self.Type
			ElementComponent.ScrollFrame = self.ScrollFrame
			ElementComponent.Library = Library
	
			return ElementComponent:New(Idx, Config)
		end
	end
	
	Library.Elements = Elements
	
	function Library:CreateWindow(Config)
		assert(Config.Title, "Toggle - Missing Title")
	
		Config.SubTitle = Config.SubTitle or ""
		Config.TabWidth = Config.TabWidth or 170
		Config.Size = Config.Size or UDim2.fromOffset(590, 470)
		Config.Acrylic = Config.Acrylic or true
		Config.Theme = Config.Theme or "Dark"
		Config.MinimizeKey = Config.MinimizeKey or Enum.KeyCode.LeftControl
	
		if Library.Window then
			print("You cannot create more than one window.")
			return
		end
	
		local Window = require(Components.Window)({
			Parent = GUI,
			Size = Config.Size,
			Title = Config.Title,
			SubTitle = Config.SubTitle,
			TabWidth = Config.TabWidth,
		})
	
		Library.MinimizeKey = Config.MinimizeKey
	
		Library.UseAcrylic = Config.Acrylic
		if Library.UseAcrylic then
			Acrylic.init()
		end
	
		Library.Window = Window
		Library:SetTheme(Config.Theme)
	
		return Window
	end
	
	function Library:SetTheme(Value)
		if Library.Window and table.find(Library.Themes, Value) then
			Library.Theme = Value
			Creator.UpdateTheme()
		end
	end
	
	function Library:Destroy()
		if Library.Window then
			Library.Unloaded = true
			if Library.UseAcrylic then
				Library.Window.AcrylicPaint.Model:Destroy()
			end
			Creator.Disconnect()
			Library.GUI:Destroy()
		end
	end
	
	function Library:ToggleAcrylic(Value)
		if Library.Window then
			if Library.UseAcrylic then
				Library.Acrylic = Value
				Library.Window.AcrylicPaint.Model.Transparency = Value and 0.98 or 1
				if Value then
					Acrylic.Enable()
				else
					Acrylic.Disable()
				end
			end
		end
	end
	
	function Library:ToggleTransparency(Value)
		if Library.Window then
			Library.Window.AcrylicPaint.Frame.Background.BackgroundTransparency = Value and 0.35 or 0
		end
	end
	
	function Library:Notify(Config)
		return NotificationModule:New(Config)
	end
	
	if getgenv then
		getgenv().Fluent = Library
	end
	
	return Library
end


return __require("_ROOT_")
