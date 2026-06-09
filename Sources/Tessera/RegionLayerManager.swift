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

/// Manages `CAShapeLayer` instances for SVG regions — handles creation, transform, appearance, and hit-testing.
final class RegionLayerManager {

    private(set) var layerMap: [String: CAShapeLayer] = [:]
    private var regionFillColors: [String: UIColor] = [:]
    private weak var parentLayer: CALayer?

    init(parentLayer: CALayer) {
        self.parentLayer = parentLayer
    }

    /// Removes all existing layers and creates fresh `CAShapeLayer`s for the given regions.
    func buildLayers(for regions: [SVGRegion], configuration: TesseraConfiguration, opacity: Float = 1) {
        removeAll()
        addLayers(for: regions, configuration: configuration, opacity: opacity)
    }

    /// Creates and adds `CAShapeLayer`s for regions without removing existing layers.
    func addLayers(for regions: [SVGRegion], configuration: TesseraConfiguration, opacity: Float = 1, insertBelow: CALayer? = nil) {
        guard let parent = parentLayer else { return }

        for region in regions {
            let shapeLayer = CAShapeLayer()
            shapeLayer.path = region.path.cgPath

            if let svgColor = region.fillColor {
                regionFillColors[region.id] = svgColor
            }

            let fill: UIColor
            if configuration.preservesSVGColors, let svgColor = region.fillColor {
                fill = svgColor
            } else {
                fill = configuration.defaultColor
            }

            shapeLayer.fillColor = fill.cgColor
            shapeLayer.strokeColor = configuration.strokeColor.cgColor
            shapeLayer.lineWidth = configuration.strokeWidth
            shapeLayer.opacity = opacity
            if let below = insertBelow {
                parent.insertSublayer(shapeLayer, below: below)
            } else {
                parent.addSublayer(shapeLayer)
            }
            layerMap[region.id] = shapeLayer
        }
    }

    /// Applies an affine transform to each region's path and resizes the layer frame to `bounds`.
    func applyTransform(_ transform: CGAffineTransform, to regions: [SVGRegion], bounds: CGRect) {
        var t = transform
        for region in regions {
            guard let shapeLayer = layerMap[region.id] else { continue }
            guard let transformedPath = region.path.cgPath.copy(using: &t) else { continue }
            shapeLayer.path = transformedPath
            shapeLayer.frame = bounds
        }
    }

    /// Updates the fill color of a region's layer based on its current selection/highlight state.
    func updateAppearance(
        for regionId: String,
        selectedIds: Set<String>,
        highlightedId: String?,
        configuration: TesseraConfiguration
    ) {
        guard let layer = layerMap[regionId] else { return }

        let color: UIColor
        if selectedIds.contains(regionId) {
            color = configuration.selectedColor
        } else if highlightedId == regionId {
            color = configuration.highlightedColor
        } else if configuration.preservesSVGColors, let svgColor = regionFillColors[regionId] {
            color = svgColor
        } else {
            color = configuration.defaultColor
        }

        layer.fillColor = color.cgColor
    }

    /// Re-applies stroke color and width from the configuration to all layers.
    func updateStroke(configuration: TesseraConfiguration) {
        for (_, layer) in layerMap {
            layer.strokeColor = configuration.strokeColor.cgColor
            layer.lineWidth = configuration.strokeWidth
        }
    }

    /// Sets the opacity on all layers, or a subset identified by `layerIds`.
    func setOpacity(_ opacity: Float, for layerIds: Set<String>? = nil) {
        let targets = layerIds.map { ids in layerMap.filter { ids.contains($0.key) } } ?? layerMap
        for (_, layer) in targets {
            layer.opacity = opacity
        }
    }

    /// Removes all layers from the parent and clears internal state.
    func removeAll() {
        for (_, layer) in layerMap {
            layer.removeFromSuperlayer()
        }
        layerMap.removeAll()
        regionFillColors.removeAll()
    }

    /// Removes layers for the specified region ids only.
    func removeLayers(for ids: Set<String>) {
        for id in ids {
            layerMap[id]?.removeFromSuperlayer()
            layerMap[id] = nil
            regionFillColors[id] = nil
        }
    }

    /// Returns `true` if a layer exists for the given region id.
    func contains(_ id: String) -> Bool {
        layerMap[id] != nil
    }

    /// Returns the id of the topmost region whose transformed path contains `point`.
    func hitTest(point: CGPoint, regions: [SVGRegion]) -> String? {
        for region in regions.reversed() {
            guard let path = layerMap[region.id]?.path else { continue }
            if path.boundingBoxOfPath.contains(point) && path.contains(point) {
                return region.id
            }
        }
        return nil
    }
}
