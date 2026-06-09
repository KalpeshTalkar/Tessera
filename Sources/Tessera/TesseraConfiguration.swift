//
// MIT License
//
// Copyright (c) 2026 Kalpesh Talkar
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

import UIKit

/// Animation style when transitioning into a focused group.
public enum GroupFocusTransition: Int, CaseIterable, Sendable {
    /// Cross-fade between the overview and focused views.
    case fade
    /// Animate paths expanding from the group's bounds to fill the view.
    case expand
}

/// Configuration for `TesseraView` appearance and behavior.
public struct TesseraConfiguration {

    // MARK: Appearance

    /// When `true`, regions render with their original SVG fill colors instead of `defaultColor`.
    public var preservesSVGColors: Bool = false
    /// Fill color for unselected, unhighlighted regions (ignored when `preservesSVGColors` is on).
    public var defaultColor: UIColor = .systemGray5
    /// Fill color applied when a region is selected.
    public var selectedColor: UIColor = .systemBlue
    /// Fill color applied while a region is highlighted (drag hover).
    public var highlightedColor: UIColor = .systemBlue.withAlphaComponent(0.3)
    /// Stroke color drawn around each region's path.
    public var strokeColor: UIColor = .darkGray
    /// Stroke line width for region borders.
    public var strokeWidth: CGFloat = 1.0

    // MARK: Interaction

    /// Allow selecting multiple regions simultaneously.
    public var isMultiSelectEnabled: Bool = false
    /// Treat `<g>` groups as single selectable units.
    public var isGroupSelectionEnabled: Bool = true
    /// Tapping a group zooms into it, showing child regions.
    public var isZoomToGroupEnabled: Bool = false
    /// Animation style for zoom-to-group transitions.
    public var groupFocusTransition: GroupFocusTransition = .expand
    /// Enable pan gesture to highlight regions as the finger moves over them.
    public var isDragToHighlightEnabled: Bool = false
    /// Automatically select the region under the finger when a drag gesture ends.
    public var selectsOnDragEnd: Bool = false

    // MARK: Haptics

    /// Master toggle for all haptic feedback.
    public var isHapticEnabled: Bool = true
    /// Impact style fired once per selection tap.
    public var selectionHapticStyle: UIImpactFeedbackGenerator.FeedbackStyle = .medium
    /// Impact style fired once per deselection tap.
    public var deselectionHapticStyle: UIImpactFeedbackGenerator.FeedbackStyle = .light
    /// Impact style fired each time the drag gesture enters a new region.
    public var highlightHapticStyle: UIImpactFeedbackGenerator.FeedbackStyle = .soft

    public init() {}

    public static var `default`: TesseraConfiguration { TesseraConfiguration() }
}
