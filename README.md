# Tessera

An iOS library for rendering interactive SVG image maps using `CAShapeLayer`. Load any SVG with paths and groups, then tap to select regions, drag to highlight, or zoom into groups — all with configurable appearance and haptic feedback.

## Requirements

- iOS 16.0+
- Swift 6.2+

## Installation

### Swift Package Manager

Add Tessera to your project via Xcode:

1. Go to **File → Add Package Dependencies...**
2. Enter the repository URL:
   ```
   https://github.com/KalpeshTalkar/Tessera.git
   ```
3. Select a version rule (e.g., **Up to Next Major**)

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/KalpeshTalkar/Tessera.git", from: "1.0.0")
]
```

## Quick Start

```swift
import Tessera

class MapViewController: UIViewController, TesseraViewDelegate {

    let tesseraView = TesseraView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(tesseraView)
        tesseraView.frame = view.bounds
        tesseraView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tesseraView.delegate = self

        // Load an SVG from your app bundle
        tesseraView.load(svgNamed: "world-map")
    }

    func tesseraView(_ view: TesseraView, didSelect regionId: String) {
        print("Selected: \(regionId)")
    }
}
```

## Usage with SwiftUI

Wrap `TesseraView` using `UIViewRepresentable`:

```swift
import SwiftUI
import Tessera

struct TesseraMapView: UIViewRepresentable {
    let svgName: String

    func makeUIView(context: Context) -> TesseraView {
        let view = TesseraView()
        view.delegate = context.coordinator
        view.load(svgNamed: svgName)
        return view
    }

    func updateUIView(_ uiView: TesseraView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, TesseraViewDelegate {
        func tesseraView(_ view: TesseraView, didSelect regionId: String) {
            print("Selected: \(regionId)")
        }
    }
}
```

## SVG Requirements

Tessera parses SVGs with these expectations:

- The root `<svg>` element must have a `viewBox` attribute
- Supported shape elements: `<path>`, `<circle>`, `<rect>`, `<ellipse>`, `<polygon>`
- Use `<g>` groups with `id` attributes for group selection and zoom-to-group features
- Each selectable element should have a unique `id` attribute

## API Reference

### TesseraView

The main view that renders and manages interactive SVG regions.

#### Loading

```swift
// Load from bundle
func load(svgNamed resource: String, in bundle: Bundle = .main)

// Load from raw SVG data
func load(svgData data: Data)
```

#### Selection

```swift
// Select/deselect a region programmatically
func select(id: String) throws
func deselect(id: String) throws

// Highlight/unhighlight (visual only, no selection)
func highlight(id: String) throws
func unhighlight(id: String) throws

// Clear all state
func clearSelection()
func resetInteractionState()
```

#### Group Focus

```swift
// Animate back from a focused group to the full overview
func unfocusGroup()
```

#### Properties

```swift
// Delegate for lifecycle, selection, and focus events
var delegate: TesseraViewDelegate?

// Appearance and behavior configuration
var configuration: TesseraConfiguration

// Current state (read-only)
var loadingState: TesseraLoadingState { get }
var selectedIds: Set<String> { get }
var focusedGroupId: String? { get }
```

### TesseraViewDelegate

All delegate methods are optional.

| Method | Description |
|--------|-------------|
| `tesseraViewDidBeginLoading(_:)` | SVG parsing started |
| `tesseraView(_:didFinishLoadingRegions:)` | Parsing complete, regions rendered |
| `tesseraView(_:didFailWithError:)` | Loading failed |
| `tesseraView(_:didEncounterWarning:)` | Non-fatal parsing issue |
| `tesseraView(_:didSelect:)` | Region selected |
| `tesseraView(_:didDeselect:)` | Region deselected |
| `tesseraView(_:didHighlight:)` | Region highlighted (drag gesture) |
| `tesseraView(_:didUnhighlight:)` | Region unhighlighted |
| `tesseraView(_:didFocusGroup:childIds:)` | Zoomed into a group |
| `tesseraViewDidUnfocusGroup(_:)` | Returned to full overview |

### TesseraConfiguration

Controls appearance, interaction, and haptics. Apply changes at any time — they take effect immediately.

```swift
var config = TesseraConfiguration()

// Appearance
config.preservesSVGColors = false       // Use original SVG fill colors
config.defaultColor = .systemGray5      // Fill for idle regions
config.selectedColor = .systemBlue      // Fill for selected regions
config.highlightedColor = .systemBlue.withAlphaComponent(0.3)
config.strokeColor = .darkGray
config.strokeWidth = 1.0

// Interaction
config.isMultiSelectEnabled = false     // Allow multiple selections
config.isGroupSelectionEnabled = true   // Treat <g> groups as selectable units
config.isZoomToGroupEnabled = false     // Tap a group to zoom into it
config.groupFocusTransition = .expand   // .fade or .expand
config.isDragToHighlightEnabled = false // Pan to highlight regions
config.selectsOnDragEnd = false         // Select on drag release

// Haptics
config.isHapticEnabled = true
config.selectionHapticStyle = .medium
config.deselectionHapticStyle = .light
config.highlightHapticStyle = .soft

tesseraView.configuration = config
```

### TesseraLoadingState

```swift
public enum TesseraLoadingState {
    case idle       // No SVG loaded
    case loading    // Parsing in progress
    case loaded     // Ready for interaction
    case failed(TesseraError)
}
```

### TesseraError

Errors thrown during loading or interaction:

| Case | Description |
|------|-------------|
| `fileNotFound(name:bundle:)` | SVG file not in bundle |
| `dataCorrupted` | Data is not valid UTF-8 |
| `invalidSVGStructure(reason:)` | Malformed SVG |
| `missingViewBox` | No `viewBox` attribute on root element |
| `invalidPathData(elementId:detail:)` | Unparseable path `d` attribute |
| `unsupportedElement(elementName:)` | Element type not supported |
| `regionNotFound(id:)` | No region with given id |
| `alreadyLoading` | Load called while another load is in progress |

### TesseraWarning

Non-fatal issues reported via delegate:

| Case | Description |
|------|-------------|
| `elementSkipped(elementId:reason:)` | Element was skipped during parsing |
| `duplicateId(_:)` | Duplicate `id` found, second element ignored |
| `emptyPath(elementId:)` | Element parsed but path is empty |

### SVGRegion

A parsed SVG element available after loading completes.

```swift
public struct SVGRegion {
    let id: String            // Element identifier
    let path: UIBezierPath    // Vector path in SVG coordinates
    let bounds: CGRect        // Bounding rect of the path
    let isGroup: Bool         // Whether this is a <g> group
    let parentGroupId: String? // Parent group id, if any
    let fillColor: UIColor?   // Original SVG fill color
    let documentOrder: Int    // Source order for z-ordering
}
```

## License

MIT License. See [LICENSE](LICENSE) for details.
