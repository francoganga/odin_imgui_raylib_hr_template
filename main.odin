package main


import "core:c/libc"
import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

import rl "lib/raylib"

lib_name :: "game.so"

GameAPI :: struct {
	init:         proc(),
	update:       proc() -> bool,
	shutdown:     proc(),
	memory:       proc() -> rawptr,
	hot_reloaded: proc(_: rawptr),
	lib:          dynlib.Library,
	dll_time:     os.File_Time,
	api_version:  int,
}

load_game_api :: proc(api_version: int) -> (GameAPI, bool) {
	dll_time, dll_time_err := os.last_write_time_by_name(lib_name)

	if dll_time_err != os.ERROR_NONE {
		fmt.println("Could not fetch last write date of game.dll")
		return {}, false
	}

	/* Can't load the game DLL directly. This
    would lock it and prevent hot reload since the
    compiler can no longer write to it. Instead,
    make a unique name based on api_version and
    copy the DLL to that location. */
	dll_name := fmt.tprintf("{0}_{1}.so", lib_name, api_version)

	/* Copy the DLL. Sometimes fails since our
  program tries to copy it before the compiler
  has finished writing it. In that case,
  try again next frame!

  Note: Here I use Windows copy command, there
  are better ways to copy a file. */
	copy_cmd := fmt.ctprintf("cp {0} {1}", lib_name, dll_name)
	if libc.system(copy_cmd) != 0 {
		fmt.println("Failed to copy {0} to {1}", lib_name, dll_name)
		return {}, false
	}
	// Load the newly copied game DLL
	path := strings.concatenate({"./", dll_name})

	lib, lib_ok := dynlib.load_library(path)

	if !lib_ok {
		fmt.printf("Failed loading game DLL name=%s\n", dll_name)

		error := os.dlerror()
		fmt.printf("Failed to load %s: %s\n", lib_name, error)

		return {}, false
	}

	/* Fetch all procedures marked with @(export)
  inside the game DLL. Note that we manually
  cast them to the correct signatures. */
	api := GameAPI {
		init         = cast(proc())(dynlib.symbol_address(lib, "game_init") or_else nil),
		update       = cast(proc() -> bool)(dynlib.symbol_address(lib, "game_update") or_else nil),
		shutdown     = cast(proc())(dynlib.symbol_address(lib, "game_shutdown") or_else nil),
		memory       = cast(proc(
		) -> rawptr)(dynlib.symbol_address(lib, "game_memory") or_else nil),
		hot_reloaded = cast(proc(
			_: rawptr,
		))(dynlib.symbol_address(lib, "game_hot_reloaded") or_else nil),
		lib          = lib,
		dll_time     = dll_time,
		api_version  = api_version,
	}
	if api.init == nil ||
	   api.update == nil ||
	   api.shutdown == nil ||
	   api.memory == nil ||
	   api.hot_reloaded == nil {
		dynlib.unload_library(api.lib)
		fmt.println("Game DLL missing required procedure")
		return {}, false
	}

	fmt.printf("Game API=%s loaded successfully\n", path)

	return api, true

}

unload_game_api :: proc(api: GameAPI) {
	if api.lib != nil {
		dynlib.unload_library(api.lib)
	}

	/* Delete the copied game DLL.

  Note: I use the windows del command, there are
  better ways to do this. */
	del_cmd := fmt.ctprintf("rm ui_{0}.so", api.api_version)
	if libc.system(del_cmd) != 0 {
		fmt.println("Failed to remove ui_{0}.so copy", api.api_version)
	}
}


main :: proc() {

	game_api_version := 0
	game_api, game_api_ok := load_game_api(game_api_version)

	if !game_api_ok {
		fmt.println("Failed to load Game API")
		return
	}

	game_api_version += 1
	game_api.init()
	//game_api.init_window()

	fmt.println("Game API loaded")

	rl.InitWindow(800, 600, "Raylib")

	for {
		if game_api.update() == false {
			break
		}

		/* Get the last write date of the game DLL
          and compare it to the date of the DLL used
          by the current game API. If different, then
          try to do a hot reload. */
		dll_time, dll_time_err := os.last_write_time_by_name(lib_name)

		reload := dll_time_err == os.ERROR_NONE && game_api.dll_time != dll_time

		if reload {
			/* Load a new game API. Might fail due to
            game.dll still being written by compiler.
            In that case it will try again next frame. */
			new_api, new_api_ok := load_game_api(game_api_version)

			if new_api_ok {
				/* Pointer to game memory used by OLD
                game DLL. */
				game_memory := game_api.memory()

				/* Unload the old game DLL. Note that
                the game memory survives, it will only
                be deallocated when explicitly freed. */
				unload_game_api(game_api)

				/* Replace game API with new one. Now
                any call such as game_api.update() will
                use the new code. */
				game_api = new_api

				/* Tell the new game API to use the old
                one's game memory. */
				game_api.hot_reloaded(game_memory)

				game_api_version += 1
			}
		}
	}

	game_api.shutdown()
	unload_game_api(game_api)
}
