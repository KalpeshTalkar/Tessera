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
import Foundation

/// Errors thrown by `TesseraView` during loading and interaction.
public enum TesseraError: LocalizedError {

    case fileNotFound(name: String, bundle: Bundle)
    case dataCorrupted
    case invalidSVGStructure(reason: String)
    case missingViewBox
    case invalidPathData(elementId: String?, detail: String)
    case unsupportedElement(elementName: String)
    case regionNotFound(id: String)
    case alreadyLoading

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let name, let bundle):
            "SVG file '\(name)' not found in bundle: \(bundle.bundlePath)"
        case .dataCorrupted:
            "SVG data could not be read as valid UTF-8"
        case .invalidSVGStructure(let reason):
            "SVG structure is invalid: \(reason)"
        case .missingViewBox:
            "SVG is missing a viewBox attribute — required for proper scaling"
        case .invalidPathData(let elementId, let detail):
            "Invalid path data in element '\(elementId ?? "unknown")': \(detail)"
        case .unsupportedElement(let name):
            "SVG element '\(name)' is not supported — use path, circle, rect, ellipse, or polygon"
        case .regionNotFound(let id):
            "No region with id '\(id)' exists in the loaded SVG"
        case .alreadyLoading:
            "An SVG is already being loaded — wait for completion or call reset() first"
        }
    }
}

/// Non-fatal issues encountered during SVG parsing, reported via the delegate.
public enum TesseraWarning {

    case elementSkipped(elementId: String?, reason: String)
    case duplicateId(String)
    case emptyPath(elementId: String)

    public var message: String {
        switch self {
        case .elementSkipped(let elementId, let reason):
            "Element '\(elementId ?? "unknown")' skipped: \(reason)"
        case .duplicateId(let id):
            "Duplicate id '\(id)' — second element ignored"
        case .emptyPath(let elementId):
            "Element '\(elementId)' parsed but resulted in an empty path"
        }
    }
}
