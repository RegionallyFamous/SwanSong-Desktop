local output_path = os.getenv("WSCVN_SCREENSHOT") or "mesen-wscvn.png"
local capture_frame = tonumber(os.getenv("WSCVN_CAPTURE_FRAME") or "120")
local press_duration = tonumber(os.getenv("WSCVN_PRESS_DURATION") or "2")
local frame_count = 0
local input_frames = {
  a = {},
  b = {},
  up = {},
  down = {},
  left = {},
  right = {},
  up2 = {},
  down2 = {},
  left2 = {},
  right2 = {},
  start = {},
}

local function load_schedule(button, env_name)
  for frame_text in string.gmatch(os.getenv(env_name) or "", "[^,]+") do
    local start_frame = tonumber(frame_text)
    if start_frame ~= nil then
      for offset = 0, press_duration - 1 do
        input_frames[button][start_frame + offset] = true
      end
    end
  end
end

load_schedule("a", "WSCVN_PRESS_A_FRAMES")
load_schedule("b", "WSCVN_PRESS_B_FRAMES")
load_schedule("up", "WSCVN_PRESS_UP_FRAMES")
load_schedule("down", "WSCVN_PRESS_DOWN_FRAMES")
load_schedule("left", "WSCVN_PRESS_LEFT_FRAMES")
load_schedule("right", "WSCVN_PRESS_RIGHT_FRAMES")
load_schedule("up2", "WSCVN_PRESS_UP2_FRAMES")
load_schedule("down2", "WSCVN_PRESS_DOWN2_FRAMES")
load_schedule("left2", "WSCVN_PRESS_LEFT2_FRAMES")
load_schedule("right2", "WSCVN_PRESS_RIGHT2_FRAMES")
load_schedule("start", "WSCVN_PRESS_START_FRAMES")

local function apply_input()
  emu.setInput({
    a = input_frames.a[frame_count] == true,
    b = input_frames.b[frame_count] == true,
    up = input_frames.up[frame_count] == true,
    down = input_frames.down[frame_count] == true,
    left = input_frames.left[frame_count] == true,
    right = input_frames.right[frame_count] == true,
    up2 = input_frames.up2[frame_count] == true,
    down2 = input_frames.down2[frame_count] == true,
    left2 = input_frames.left2[frame_count] == true,
    right2 = input_frames.right2[frame_count] == true,
    start = input_frames.start[frame_count] == true,
  }, 0)
end

local function capture_framebuffer()
  frame_count = frame_count + 1
  if frame_count < capture_frame then
    return
  end

  local png = emu.takeScreenshot()
  local output = assert(io.open(output_path, "wb"))
  output:write(png)
  output:close()
  emu.stop(0)
end

emu.addEventCallback(apply_input, emu.eventType.inputPolled)
emu.addEventCallback(capture_framebuffer, emu.eventType.endFrame)
