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

/// Parses SVG files into `SVGRegion` arrays suitable for `TesseraView` rendering.
///
/// Supports: `<path>`, `<circle>`, `<rect>`, `<ellipse>`, `<polygon>`, `<polyline>`.
/// Groups (`<g>`) with an `id` attribute become compound-path regions with child regions stored separately.
nonisolated enum SVGDocument {

    /// The result of a successful SVG parse, containing all renderable regions and any warnings.
    struct ParseResult {
        /// The SVG's `viewBox` rect defining the coordinate space.
        let viewBox: CGRect
        /// Top-level regions (individual shapes and group compound paths).
        let regions: [SVGRegion]
        /// Child regions belonging to groups (used for zoom-to-group focus).
        let childRegions: [SVGRegion]
        /// Non-fatal issues encountered during parsing.
        let warnings: [TesseraWarning]
    }

    /// Parses an SVG file from the app bundle.
    /// - Parameters:
    ///   - resource: The SVG filename without extension.
    ///   - bundle: The bundle to search. Defaults to `.main`.
    /// - Returns: A `ParseResult` with regions ready for rendering.
    /// - Throws: `TesseraError` if the file is missing, corrupt, or structurally invalid.
    static func parse(named resource: String, in bundle: Bundle = .main) throws -> ParseResult {
        guard let url = bundle.url(forResource: resource, withExtension: "svg") else {
            throw TesseraError.fileNotFound(name: resource, bundle: bundle)
        }
        let data = try loadData(from: url)
        return try parseData(data)
    }

    /// Parses an SVG from raw `Data` (e.g. downloaded from a network or read from documents).
    /// - Parameter data: UTF-8 encoded SVG content.
    /// - Returns: A `ParseResult` with regions ready for rendering.
    /// - Throws: `TesseraError` if the data is corrupt or structurally invalid.
    static func parse(data: Data) throws -> ParseResult {
        try parseData(data)
    }

    // MARK: - Private

    private static func loadData(from url: URL) throws -> Data {
        guard let data = try? Data(contentsOf: url) else {
            throw TesseraError.dataCorrupted
        }
        return data
    }

    private static func parseData(_ data: Data) throws -> ParseResult {
        guard String(data: data, encoding: .utf8) != nil else {
            throw TesseraError.dataCorrupted
        }

        let delegate = SVGParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        if let error = delegate.error {
            throw error
        }

        guard let viewBox = delegate.viewBox else {
            throw TesseraError.missingViewBox
        }

        if delegate.regions.isEmpty && delegate.childRegions.isEmpty {
            throw TesseraError.invalidSVGStructure(reason: "No elements with id attributes found")
        }

        return ParseResult(
            viewBox: viewBox,
            regions: delegate.regions,
            childRegions: delegate.childRegions,
            warnings: delegate.warnings
        )
    }
}

// MARK: - XML Parser Delegate

nonisolated private final class SVGParserDelegate: NSObject, XMLParserDelegate {

    private(set) var viewBox: CGRect?
    private(set) var regions: [SVGRegion] = []
    private(set) var childRegions: [SVGRegion] = []
    private(set) var warnings: [TesseraWarning] = []
    private(set) var error: TesseraError?

    private var seenIds: Set<String> = []
    private var childCounter: Int = 0
    private var orderCounter: Int = 0
    private let supportedElements: Set<String> = ["path", "circle", "rect", "ellipse", "polygon", "polyline"]

    private struct GroupContext {
        let id: String
        let compoundPath: UIBezierPath
        let fillColor: UIColor?
        let documentOrder: Int
    }

    private var groupStack: [GroupContext] = []
    private var unnamedGroupDepth: Int = 0
    private var activeGroupId: String? { groupStack.last?.id }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        if elementName == "svg" {
            viewBox = parseViewBox(attributes["viewBox"])
            return
        }

        if elementName == "g" {
            if let id = attributes["id"] {
                if seenIds.contains(id) {
                    warnings.append(.duplicateId(id))
                    unnamedGroupDepth += 1
                } else {
                    seenIds.insert(id)
                    let groupFill = parseColor(attributes["fill"])
                    let order = orderCounter
                    orderCounter += 1
                    groupStack.append(GroupContext(id: id, compoundPath: UIBezierPath(), fillColor: groupFill, documentOrder: order))
                }
            } else {
                unnamedGroupDepth += 1
            }
            return
        }

        if let group = groupStack.last {
            if supportedElements.contains(elementName) {
                let childId = attributes["id"] ?? "\(group.id)_\(childCounter)"
                childCounter += 1
                if let path = buildPath(element: elementName, attributes: attributes, id: childId) {
                    group.compoundPath.append(path)

                    let childFill = parseColor(attributes["fill"]) ?? group.fillColor
                    let bounds = path.bounds
                    let order = orderCounter
                    orderCounter += 1
                    childRegions.append(SVGRegion(id: childId, path: path, bounds: bounds, parentGroupId: group.id, fillColor: childFill, documentOrder: order))
                }
            }
            return
        }

        guard let id = attributes["id"] else { return }

        if seenIds.contains(id) {
            warnings.append(.duplicateId(id))
            return
        }
        seenIds.insert(id)

        guard supportedElements.contains(elementName) else {
            warnings.append(.elementSkipped(elementId: id, reason: "Unsupported element '\(elementName)'"))
            return
        }

        guard let path = buildPath(element: elementName, attributes: attributes, id: id) else {
            return
        }

        if path.isEmpty {
            warnings.append(.emptyPath(elementId: id))
            return
        }

        let fillColor = parseColor(attributes["fill"])
        let bounds = path.bounds
        let order = orderCounter
        orderCounter += 1
        regions.append(SVGRegion(id: id, path: path, bounds: bounds, fillColor: fillColor, documentOrder: order))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        guard elementName == "g" else { return }

        if unnamedGroupDepth > 0 {
            unnamedGroupDepth -= 1
            return
        }

        guard let group = groupStack.last else { return }
        groupStack.removeLast()

        if group.compoundPath.isEmpty {
            warnings.append(.emptyPath(elementId: group.id))
            return
        }

        let bounds = group.compoundPath.bounds
        regions.append(SVGRegion(id: group.id, path: group.compoundPath, bounds: bounds, isGroup: true, fillColor: group.fillColor, documentOrder: group.documentOrder))
    }

    // MARK: - Path Building

    private func buildPath(element: String, attributes: [String: String], id: String) -> UIBezierPath? {
        switch element {
        case "path":
            guard let d = attributes["d"] else {
                warnings.append(.elementSkipped(elementId: id, reason: "Missing 'd' attribute"))
                return nil
            }
            guard let path = SVGPathParser.parse(d) else {
                warnings.append(.elementSkipped(elementId: id, reason: "Invalid path data"))
                return nil
            }
            return path

        case "circle":
            guard let cx = cgFloat(attributes["cx"]),
                  let cy = cgFloat(attributes["cy"]),
                  let r = cgFloat(attributes["r"]) else {
                warnings.append(.elementSkipped(elementId: id, reason: "Missing circle attributes"))
                return nil
            }
            return UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: r,
                                startAngle: 0, endAngle: .pi * 2, clockwise: true)

        case "ellipse":
            guard let cx = cgFloat(attributes["cx"]),
                  let cy = cgFloat(attributes["cy"]),
                  let rx = cgFloat(attributes["rx"]),
                  let ry = cgFloat(attributes["ry"]) else {
                warnings.append(.elementSkipped(elementId: id, reason: "Missing ellipse attributes"))
                return nil
            }
            return UIBezierPath(ovalIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))

        case "rect":
            guard let x = cgFloat(attributes["x"]),
                  let y = cgFloat(attributes["y"]),
                  let w = cgFloat(attributes["width"]),
                  let h = cgFloat(attributes["height"]) else {
                warnings.append(.elementSkipped(elementId: id, reason: "Missing rect attributes"))
                return nil
            }
            let cornerRadius = cgFloat(attributes["rx"]) ?? 0
            return UIBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
                                cornerRadius: cornerRadius)

        case "polygon", "polyline":
            guard let points = attributes["points"] else {
                warnings.append(.elementSkipped(elementId: id, reason: "Missing 'points' attribute"))
                return nil
            }
            return parsePolygon(points: points, closed: element == "polygon")

        default:
            return nil
        }
    }

    // MARK: - Polygon Parsing

    private func parsePolygon(points: String, closed: Bool) -> UIBezierPath? {
        let scanner = Scanner(string: points)
        scanner.charactersToBeSkipped = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))

        let path = UIBezierPath()
        var first = true

        while !scanner.isAtEnd {
            guard let x = scanner.scanDouble(), let y = scanner.scanDouble() else { break }
            let point = CGPoint(x: x, y: y)
            if first {
                path.move(to: point)
                first = false
            } else {
                path.addLine(to: point)
            }
        }

        if closed { path.close() }
        return path.isEmpty ? nil : path
    }

    // MARK: - ViewBox Parsing

    private func parseViewBox(_ value: String?) -> CGRect? {
        guard let value else { return nil }
        let scanner = Scanner(string: value)
        scanner.charactersToBeSkipped = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))

        guard let x = scanner.scanDouble(),
              let y = scanner.scanDouble(),
              let w = scanner.scanDouble(),
              let h = scanner.scanDouble() else { return nil }

        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Helpers

    private func cgFloat(_ string: String?) -> CGFloat? {
        guard let string, let value = Double(string) else { return nil }
        return CGFloat(value)
    }

    private func parseColor(_ value: String?) -> UIColor? {
        guard let value, !value.isEmpty, value != "none" else { return nil }

        if value.hasPrefix("#") {
            let hex = String(value.dropFirst())
            guard let int = UInt64(hex, radix: 16) else { return nil }

            let r, g, b, a: CGFloat
            switch hex.count {
            case 3:
                r = CGFloat((int >> 8) & 0xF) / 15
                g = CGFloat((int >> 4) & 0xF) / 15
                b = CGFloat(int & 0xF) / 15
                a = 1
            case 6:
                r = CGFloat((int >> 16) & 0xFF) / 255
                g = CGFloat((int >> 8) & 0xFF) / 255
                b = CGFloat(int & 0xFF) / 255
                a = 1
            case 8:
                r = CGFloat((int >> 24) & 0xFF) / 255
                g = CGFloat((int >> 16) & 0xFF) / 255
                b = CGFloat((int >> 8) & 0xFF) / 255
                a = CGFloat(int & 0xFF) / 255
            default:
                return nil
            }
            return UIColor(red: r, green: g, blue: b, alpha: a)
        }

        return nil
    }
}
