# Appearance settings

The Settings window uses AppKit controls and `UserDefaults`. No web view, global cursor preference change, Accessibility permission, or capture stream is involved.

| Control | Native API | Application behavior |
| --- | --- | --- |
| Crosshair size and thickness | [`NSCursor(image:hotSpot:)`](https://developer.apple.com/documentation/appkit/nscursor/init(image:hotspot:)), [`NSImage` drawing handler](https://developer.apple.com/documentation/appkit/nsimage/init(size:flipped:drawinghandler:)), `NSBezierPath` | Create a centered white crosshair with a black outline. Retain it until size or thickness changes. |
| Numeric settings | [`NSSlider`](https://developer.apple.com/documentation/appkit/nsslider) | Size ranges from 12 to 96 points, thickness from 0.5 to 8 points, and coordinate font size from 9 to 32 points. |
| Coordinate display | [`NSTextField`](https://developer.apple.com/documentation/appkit/nstextfield), [`NSFont.monospacedSystemFont`](https://developer.apple.com/documentation/appkit/nsfont/monospacedsystemfont(ofsize:weight:)) | Show two coordinate values in a native two-line label. |
| Position | [`NSPopUpButton`](https://developer.apple.com/documentation/appkit/nspopupbutton), native `CGRect` geometry | Place the label in the chosen quadrant. Flip at screen edges, then clamp inside the screen. |
| Menu-bar visibility | [`NSStatusItem.isVisible`](https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible) | Hide the retained icon without unregistering the capture shortcut. |
| Recovery | [`applicationShouldHandleReopen`](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldhandlereopen(_:hasvisiblewindows:)) | Reopening the app shows Settings so the icon can be restored. |
| Persistence | [`UserDefaults`](https://developer.apple.com/documentation/foundation/userdefaults) | Save on a control change; validate stored numbers and quadrant identifiers when loading. |

All these APIs are available on macOS 13. AppKit's shared system crosshair is immutable and has no application-level size or stroke setting. A custom cursor is therefore necessary for these controls. Apple's image drawing handler adapts to destination resolution. Exact cursor rasterization and global accessibility cursor scaling remain under macOS control.

Quadrant selection, screen-edge adjustment, and supported settings ranges are application policy. AppKit supplies the drawing, text measurement, controls, cursor installation, and window lifecycle. Coordinate changes do not create a new cursor. Pointer movement does not redraw the cursor image.

Settings includes a live preview, shortcut and Screen Recording actions, and Quit. Hiding the menu icon also works across restarts. Opening Settings does not request Screen Recording access.
