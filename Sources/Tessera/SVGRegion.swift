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

/// A parsed SVG element ready for rendering as a `CAShapeLayer`.
public struct SVGRegion {
    /// Unique identifier from the SVG `id` attribute or a synthetic id for unnamed children.
    public let id: String
    /// The vector path in SVG coordinate space (pre-transform).
    public let path: UIBezierPath
    /// Bounding rect of `path` in SVG coordinate space.
    public let bounds: CGRect
    /// Whether this region is a group (`<g>`) whose path is a compound of its children.
    public let isGroup: Bool
    /// The id of the parent group, or `nil` for top-level elements.
    public let parentGroupId: String?
    /// The original fill color parsed from the SVG `fill` attribute.
    public let fillColor: UIColor?
    /// Position in the SVG source — used to maintain correct z-order when rendering layers.
    public let documentOrder: Int

    internal init(id: String, path: UIBezierPath, bounds: CGRect, isGroup: Bool = false, parentGroupId: String? = nil, fillColor: UIColor? = nil, documentOrder: Int = 0) {
        self.id = id
        self.path = path
        self.bounds = bounds
        self.isGroup = isGroup
        self.parentGroupId = parentGroupId
        self.fillColor = fillColor
        self.documentOrder = documentOrder
    }
}
