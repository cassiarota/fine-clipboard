# FineClipboard UI Refresh And Feature Simplification Design

Date: 2026-06-17

## Goal

Refresh FineClipboard on both Windows and macOS so the product feels like a polished, Apple-inspired utility rather than a default desktop app. The visual baseline is restrained Apple-style glass: translucent material, soft blur, quiet spacing, subtle blue accents, and minimal futuristic detail.

The feature changes must be consistent across both platforms:

- Remove paste stack functionality from user-facing surfaces.
- Simplify tray/menu-bar menus.
- Move cloud sync, pause recording, and password lock controls into Settings.
- Show screenshot results immediately after capture.
- Organize Settings into clear categories.
- Replace default app/window/taskbar/menu icons with a unified FineClipboard icon.

## Scope

### In Scope

- Windows WPF implementation under `src/FineClipboard`.
- macOS SwiftUI/AppKit implementation under `mac/Sources/FineClipboard`.
- README updates for removed paste stack behavior and moved settings.
- App icon resources and runtime tray/menu-bar icon generation or asset wiring.
- Build verification for Windows, and best-effort macOS verification from this Windows workspace.

### Out Of Scope

- Replacing the operating system's native screenshot selection overlay.
- Building a full image editor beyond the existing screenshot flow unless the codebase already contains an editable screenshot surface.
- Backend or sync protocol changes.
- Billing, VIP, account, or server behavior changes.

## Functional Design

### Paste Stack Removal

Remove the paste stack as a product feature.

Windows:

- Stop registering the paste-next hotkey.
- Remove `PasteStack` usage from `App.xaml.cs`.
- Remove tray menu items for stack count and clear-stack.
- Remove the popup item context menu entry `加入粘贴堆栈`.
- Remove dead event handlers and comments.

macOS:

- Stop registering the stack hotkey.
- Remove `PasteStack` usage from `AppDelegate.swift`.
- Remove menu-bar items for stack count and clear-stack.
- Remove the popup context menu entry `加入粘贴堆栈`.
- Remove unused protocol methods and comments.

Storage keys such as `hotkey_stack` may remain harmlessly unused to avoid risky migration churn.

### Tray And Menu-Bar Menus

The primary menu should become compact and low-noise.

Remove from top-level menu:

- `打开历史`
- `云同步`
- `暂停记录`
- `锁定密码`
- paste stack items

Keep top-level menu:

- `设置...`
- `截图` submenu
- `检查更新...`
- `退出`

History remains accessible by double-clicking the tray icon on Windows and via global hotkey on both platforms. macOS can keep click-to-open behavior if that is currently the app's main menu-bar interaction, but the explicit `打开历史` menu row should be removed.

### Settings Categorization

Settings becomes the control center for lower-frequency state and management actions.

Categories:

- `通用`: startup, sound.
- `历史与隐私`: pause recording, max items, expiry, exclusions.
- `外观`: theme, popup size.
- `快捷键`: history popup, plain-text paste, screenshot.
- `同步`: cloud sync entry point and current state.
- `密码`: master password, password manager, lock password.
- `维护`: history count, clear history buttons, update check if practical.

Pause recording should be a switch in `历史与隐私`. It must still update monitor state and tray/menu-bar title/status immediately.

Cloud sync should be opened from Settings with a button in `同步`.

Lock password should be a button in `密码`, disabled or visually quiet when no master password is configured.

### Screenshot Result Preview

After a screenshot is captured and appears in the clipboard/history, FineClipboard should immediately show the captured image rather than relying on the user to click a notification.

Windows:

- Add a capture-request marker when screenshot is launched from FineClipboard.
- When the next image item is captured by `ClipboardMonitor`, open a preview window for that image.
- Fullscreen capture should set the marker before directly writing the image to the clipboard.
- The preview window should use the new glass style and offer expected actions: close, copy remains implicit, save as file.

macOS:

- Add the same capture-request marker around `Screenshot.capture`.
- When the next image item enters the store, open a preview window.
- Preserve existing screenshot modes: region, window, fullscreen.

If an existing screenshot editing surface exists, make the default shape selector persistently visible. If no such surface exists in the current codebase, the new screenshot preview should expose commonly used annotation shape choices as always-visible segmented controls rather than hiding them in a dropdown.

### Visual System

Use the restrained Apple-style glass direction selected by the user.

Core traits:

- Translucent, blurred panels.
- Soft shadow with low opacity.
- Thin semi-transparent borders.
- Neutral dark/light surface colors with blue accent.
- Rounded controls, but not oversized.
- Quiet hover and selected states.
- No decorative bokeh/orb backgrounds.
- No heavy neon, no game-like HUD density.

Windows:

- Move common brushes and control styles into app resources or a shared resource dictionary.
- Restyle popup, context menus, settings, and small management dialogs.
- Use custom WPF context menu styles for popup item menus.
- For WinForms tray context menu, use owner-draw or the closest reliable styling available without destabilizing tray behavior.

macOS:

- Use SwiftUI material backgrounds and consistent control styling.
- Update popover/popup rows, settings sections, context menus, and management windows.
- Keep native feel where AppKit menus cannot be fully customized, but simplify labels and grouping.

### Icon Design

Create a unified FineClipboard icon.

Direction:

- Rounded square or circular glass base.
- Clipboard/page motif with a small spark or layered clip mark.
- Blue/cyan accent on dark translucent base.
- Readable at tray/menu-bar sizes.

Windows:

- Provide an app icon for executable/taskbar/window chrome.
- Use the same identity for tray icon generation or a bundled `.ico`.
- Set settings and child windows to use the app icon.

macOS:

- Add app icon assets suitable for `.app`.
- Update menu-bar icon to match the new identity while remaining legible in light/dark menu bars.

## Data Flow

### Screenshot Preview Flow

1. User chooses a screenshot action from FineClipboard.
2. App sets `PendingScreenshotPreview = true`.
3. OS screenshot tool or direct capture writes image to clipboard.
4. Clipboard monitor captures an image item and stores it.
5. App sees the pending flag and image item, clears the flag, and opens preview.
6. OCR and history refresh continue as today.

The preview should only auto-open for screenshots initiated through FineClipboard, not for every image copied by the user.

### Settings Control Flow

Settings actions call existing services directly where possible:

- Pause recording updates monitor state.
- Cloud sync opens existing sync window/view.
- Lock password calls existing vault lock.
- Startup calls existing startup manager.
- Theme changes continue to apply live.

## Error Handling

- If screenshot preview cannot decode image data, skip preview and keep the image in history.
- If the OS screenshot tool fails to launch, preserve current best-effort behavior.
- If tray menu custom drawing fails or proves too brittle, fall back to simplified native menu labels rather than blocking the feature work.
- If icon resources are unavailable during development build, runtime generated icon remains a fallback.

## Testing And Verification

Windows:

- `dotnet build src/FineClipboard/FineClipboard.csproj`
- Run the app and inspect:
  - Popup glass style.
  - Popup context menu has no paste stack item.
  - Tray menu has no open-history, sync, pause, lock, or paste-stack rows.
  - Settings categories contain sync, pause, and lock controls.
  - Screenshot opens preview automatically after capture.
  - Taskbar/window/tray icons are not default.

macOS:

- Static review from Windows for Swift compile issues.
- If macOS toolchain is available, run `swift build -c release` in `mac`.
- Inspect equivalent menu/popup/settings changes when a macOS runtime is available.

Documentation:

- README no longer advertises paste stack.
- README describes moved sync/pause/lock settings.

## Risks

- WinForms tray menu styling is less flexible than WPF; exact glass styling may not be possible there without a larger tray replacement.
- Screenshot preview depends on OS screenshot behavior copying an image to the clipboard.
- Cross-platform visual parity is approximate because WPF and SwiftUI/AppKit have different material systems.
- macOS compilation may not be verifiable from this Windows environment.
