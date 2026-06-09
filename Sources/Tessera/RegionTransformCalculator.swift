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

import CoreGraphics

/// Computes an aspect-fit transform from SVG coordinate space to the view's bounds.
struct RegionTransformCalculator {

    let viewBox: CGRect
    let viewBounds: CGRect

    /// Computes a transform that aspect-fits the source rect (viewBox or a target region) into the view bounds.
    /// - Parameters:
    ///   - targetBounds: Optional sub-region to fit. Uses the full `viewBox` if `nil`.
    ///   - padding: Inset padding applied equally on all sides.
    /// - Returns: An affine transform that centers and scales the content.
    func aspectFitTransform(for targetBounds: CGRect? = nil, padding: CGFloat = 0) -> CGAffineTransform {
        let source = targetBounds ?? viewBox
        guard source.width > 0, source.height > 0,
              viewBounds.width > 0, viewBounds.height > 0 else {
            return .identity
        }

        let availableWidth = viewBounds.width - padding * 2
        let availableHeight = viewBounds.height - padding * 2

        let scaleX = availableWidth / source.width
        let scaleY = availableHeight / source.height
        let scale = min(scaleX, scaleY)

        let scaledWidth = source.width * scale
        let scaledHeight = source.height * scale
        let offsetX = (viewBounds.width - scaledWidth) / 2 - source.origin.x * scale
        let offsetY = (viewBounds.height - scaledHeight) / 2 - source.origin.y * scale

        return CGAffineTransform(translationX: offsetX, y: offsetY).scaledBy(x: scale, y: scale)
    }
}
