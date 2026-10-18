# CLAUDE.md

## Running the app during development

- Launch it with the Dart MCP server (`dart-flutter` plugin): `launch_app` on `windows` from the repository root, so the app finds `runtime/runtime.txt` (ONNX Runtime 1.31 CUDA 12, cuDNN and CUDA library directories of this machine; not in git).
- The main window is the caption bar; settings open in a sub window. Development hooks: `FL_CAPTION_LIVE_FILE=<wav>` plays a file into the live pipeline instead of capturing, `FL_CAPTION_OPEN_SETTINGS=<page>` opens the settings window on that page at start.
- Hot reload/restart only cover Dart. After changing `rust/`, run `flutter_rust_bridge_codegen generate` if `rust/src/api` changed, then stop and launch the app again (cargokit rebuilds the library).
- Real-model checks without Flutter: `rust/examples/bench.rs` (`file`, `live`, `translate`, `download`, `models`).

## Proactive Flutter hot reload (from flutter/agent-plugins rules/flutter-hot-reload.md)

Whenever you edit or modify any `.dart` file under `lib/` in this project:

1. **When to skip**:
   - **Files outside `lib/`**: only trigger hot reload or hot restart for edits under `lib/`. Do not trigger when modifying files in other directories (e.g. `test/**`, `integration_test/**`, `benchmark/**`, `test_driver/**` or `example/**`).
   - **Comments and documentation**: do not trigger hot reload or hot restart when changes only affect comments, docstrings or whitespace.

2. **Discover and connect**: discover active running application instances using the `dtd` MCP tool (or `list_running_apps` / `vm_service`) from the Dart MCP server.

3. **Trigger hot reload / hot restart**:
   - Execute the `hot_reload` MCP tool immediately after making changes to UI widgets (including `build` methods of stateful widgets) or simple methods.
   - Execute the `hot_restart` MCP tool if fundamental logic, state initialization (e.g. `initState`), global/static state, or `main()` was modified.
