package game
import rl "../lib/raylib"

import imgui "../lib/imgui_raylib/odin-imgui"
import imgui_rl "../lib/imgui_raylib"
import "core:fmt"



ImguiMemory :: struct {
    ctx: ^imgui.Context,
    mem_alloc: ^imgui.MemAllocFunc,
    mem_free: ^imgui.MemFreeFunc,
    user_data: rawptr
}

GameMemory :: struct {
    imgui: ^ImguiMemory,
    count: int
}

g_mem: ^GameMemory

@(export)
game_init :: proc() {
    g_mem = new(GameMemory)
    g_mem.imgui = new(ImguiMemory)
}

@(export)
game_imgui_reload :: proc(mem_alloc: ^imgui.MemAllocFunc, mem_free: ^imgui.MemFreeFunc, user_data: rawptr, ctx: ^imgui.Context) {
    g_mem.imgui.mem_alloc = mem_alloc
    g_mem.imgui.mem_free = mem_free
    g_mem.imgui.user_data = user_data
    imgui.SetCurrentContext(ctx)
}

@(export)
game_update :: proc(ctx: ^imgui.Context) -> bool {

    if rl.WindowShouldClose() {
        return false
    }

    imgui.SetCurrentContext(ctx)
    imgui_rl.process_events()
	imgui_rl.new_frame()
	imgui.NewFrame()
	rl.BeginDrawing()
    text := fmt.ctprintf("Count: {0}", g_mem.count)
	rl.DrawText(text, 100, 100, 20, rl.RED)
	rl.ClearBackground(rl.BLACK)
	//imgui.ShowDemoWindow(nil)
    text2 := fmt.ctprintf("Debug: {0}", g_mem.count)
    if imgui.Button(text2, {80, 40}) {
        g_mem.count += 1
    }
    imgui.SameLine()
    if imgui.Button("Reset", {110, 40}) {
        g_mem.count = 0
    }


	imgui.Render()
	imgui_rl.render_draw_data(imgui.GetDrawData())
	rl.EndDrawing()

    return true
}

@(export)
game_shutdown :: proc() {
    free(g_mem)
}

@(export)
game_memory :: proc() -> rawptr {
    return g_mem
}

@(export)
game_hot_reloaded :: proc(mem: ^GameMemory) {
  g_mem = mem
}
