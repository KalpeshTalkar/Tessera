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

/// Parses SVG path `d` attribute strings into `UIBezierPath` objects.
///
/// Supports all SVG path commands: M, L, H, V, C, S, Q, T, A, Z (both absolute and relative).
/// Arc commands are converted to cubic bezier approximations.
nonisolated enum SVGPathParser {

    /// Parses an SVG path `d` attribute string into a `UIBezierPath`.
    /// - Parameter d: The raw path data string (e.g. `"M10 10 L90 90 Z"`).
    /// - Returns: A `UIBezierPath` representing the parsed path, or `nil` if parsing fails or the path is empty.
    static func parse(_ d: String) -> UIBezierPath? {
        let path = UIBezierPath()
        let scanner = Scanner(string: d)
        scanner.charactersToBeSkipped = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))

        var currentPoint = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControlPoint: CGPoint?
        var lastCommand: Character?

        while !scanner.isAtEnd {
            let savedIndex = scanner.currentIndex
            let command = scanCommand(scanner)
            guard let cmd = command ?? lastCommand else { break }

            let isRelative = cmd.isLowercase
            let baseCmd = Character(String(cmd).uppercased())

            switch baseCmd {
            case "M":
                guard let point = scanPoint(scanner) else { return nil }
                let resolved = resolve(point, relative: isRelative, current: currentPoint)
                path.move(to: resolved)
                currentPoint = resolved
                subpathStart = resolved
                lastControlPoint = nil
                while let next = scanPoint(scanner) {
                    let resolvedNext = resolve(next, relative: isRelative, current: currentPoint)
                    path.addLine(to: resolvedNext)
                    currentPoint = resolvedNext
                }

            case "L":
                while let point = scanPoint(scanner) {
                    let resolved = resolve(point, relative: isRelative, current: currentPoint)
                    path.addLine(to: resolved)
                    currentPoint = resolved
                }
                lastControlPoint = nil

            case "H":
                while let x = scanDouble(scanner) {
                    let resolvedX = isRelative ? currentPoint.x + x : x
                    let point = CGPoint(x: resolvedX, y: currentPoint.y)
                    path.addLine(to: point)
                    currentPoint = point
                }
                lastControlPoint = nil

            case "V":
                while let y = scanDouble(scanner) {
                    let resolvedY = isRelative ? currentPoint.y + y : y
                    let point = CGPoint(x: currentPoint.x, y: resolvedY)
                    path.addLine(to: point)
                    currentPoint = point
                }
                lastControlPoint = nil

            case "C":
                while let cp1 = scanPoint(scanner),
                      let cp2 = scanPoint(scanner),
                      let end = scanPoint(scanner) {
                    let rcp1 = resolve(cp1, relative: isRelative, current: currentPoint)
                    let rcp2 = resolve(cp2, relative: isRelative, current: currentPoint)
                    let rend = resolve(end, relative: isRelative, current: currentPoint)
                    path.addCurve(to: rend, controlPoint1: rcp1, controlPoint2: rcp2)
                    lastControlPoint = rcp2
                    currentPoint = rend
                }

            case "S":
                while let cp2 = scanPoint(scanner),
                      let end = scanPoint(scanner) {
                    let cp1 = reflectedControlPoint(lastControlPoint, current: currentPoint)
                    let rcp2 = resolve(cp2, relative: isRelative, current: currentPoint)
                    let rend = resolve(end, relative: isRelative, current: currentPoint)
                    path.addCurve(to: rend, controlPoint1: cp1, controlPoint2: rcp2)
                    lastControlPoint = rcp2
                    currentPoint = rend
                }

            case "Q":
                while let cp = scanPoint(scanner),
                      let end = scanPoint(scanner) {
                    let rcp = resolve(cp, relative: isRelative, current: currentPoint)
                    let rend = resolve(end, relative: isRelative, current: currentPoint)
                    path.addQuadCurve(to: rend, controlPoint: rcp)
                    lastControlPoint = rcp
                    currentPoint = rend
                }

            case "T":
                while let end = scanPoint(scanner) {
                    let cp = reflectedControlPoint(lastControlPoint, current: currentPoint)
                    let rend = resolve(end, relative: isRelative, current: currentPoint)
                    path.addQuadCurve(to: rend, controlPoint: cp)
                    lastControlPoint = cp
                    currentPoint = rend
                }

            case "A":
                while let arcParams = scanArc(scanner) {
                    let endPoint = resolve(arcParams.end, relative: isRelative, current: currentPoint)
                    addArc(to: path, from: currentPoint, to: endPoint,
                           rx: arcParams.rx, ry: arcParams.ry,
                           xRotation: arcParams.xRotation,
                           largeArc: arcParams.largeArc,
                           sweep: arcParams.sweep)
                    currentPoint = endPoint
                }
                lastControlPoint = nil

            case "Z":
                path.close()
                currentPoint = subpathStart
                lastControlPoint = nil

            default:
                return nil
            }

            if baseCmd != "C" && baseCmd != "S" && baseCmd != "Q" && baseCmd != "T" {
                if baseCmd != "M" && baseCmd != "L" && baseCmd != "H" && baseCmd != "V" && baseCmd != "A" && baseCmd != "Z" {
                    lastControlPoint = nil
                }
            }

            lastCommand = cmd

            if scanner.currentIndex == savedIndex {
                break
            }
        }

        return path.isEmpty ? nil : path
    }

    // MARK: - Scanning

    private static func scanCommand(_ scanner: Scanner) -> Character? {
        let commandChars: Set<Character> = Set("MmLlHhVvCcSsQqTtAaZz")
        let skip = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        while !scanner.isAtEnd {
            let idx = scanner.currentIndex
            if String(scanner.string[idx]).unicodeScalars.allSatisfy({ skip.contains($0) }) {
                scanner.currentIndex = scanner.string.index(after: idx)
            } else {
                break
            }
        }
        guard !scanner.isAtEnd else { return nil }
        let char = scanner.string[scanner.currentIndex]
        if commandChars.contains(char) {
            scanner.currentIndex = scanner.string.index(after: scanner.currentIndex)
            return char
        }
        return nil
    }

    private static func scanDouble(_ scanner: Scanner) -> CGFloat? {
        guard let value = scanner.scanDouble() else { return nil }
        return CGFloat(value)
    }

    private static func scanPoint(_ scanner: Scanner) -> CGPoint? {
        guard let x = scanDouble(scanner), let y = scanDouble(scanner) else { return nil }
        return CGPoint(x: x, y: y)
    }

    private struct ArcParameters {
        let rx: CGFloat
        let ry: CGFloat
        let xRotation: CGFloat
        let largeArc: Bool
        let sweep: Bool
        let end: CGPoint
    }

    private static func scanArc(_ scanner: Scanner) -> ArcParameters? {
        guard let rx = scanDouble(scanner),
              let ry = scanDouble(scanner),
              let xRotation = scanDouble(scanner),
              let largeArcFlag = scanFlag(scanner),
              let sweepFlag = scanFlag(scanner),
              let end = scanPoint(scanner) else { return nil }
        return ArcParameters(rx: rx, ry: ry, xRotation: xRotation,
                             largeArc: largeArcFlag, sweep: sweepFlag, end: end)
    }

    private static func scanFlag(_ scanner: Scanner) -> Bool? {
        scanner.charactersToBeSkipped = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        guard let value = scanner.scanInt() else { return nil }
        return value != 0
    }

    // MARK: - Helpers

    private static func resolve(_ point: CGPoint, relative: Bool, current: CGPoint) -> CGPoint {
        relative ? CGPoint(x: current.x + point.x, y: current.y + point.y) : point
    }

    private static func reflectedControlPoint(_ lastCP: CGPoint?, current: CGPoint) -> CGPoint {
        guard let cp = lastCP else { return current }
        return CGPoint(x: 2 * current.x - cp.x, y: 2 * current.y - cp.y)
    }

    // MARK: - Arc Conversion

    private static func addArc(to path: UIBezierPath, from p1: CGPoint, to p2: CGPoint,
                               rx: CGFloat, ry: CGFloat, xRotation: CGFloat,
                               largeArc: Bool, sweep: Bool) {
        guard rx != 0 && ry != 0 else {
            path.addLine(to: p2)
            return
        }

        if p1 == p2 { return }

        var rx = abs(rx)
        var ry = abs(ry)
        let phi = xRotation * .pi / 180

        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx = (p1.x - p2.x) / 2
        let dy = (p1.y - p2.y) / 2

        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let sqrtLambda = sqrt(lambda)
            rx *= sqrtLambda
            ry *= sqrtLambda
        }

        let rx2 = rx * rx
        let ry2 = ry * ry
        let x1p2 = x1p * x1p
        let y1p2 = y1p * y1p

        var sq = (rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2) / (rx2 * y1p2 + ry2 * x1p2)
        sq = max(sq, 0)
        let sign: CGFloat = (largeArc == sweep) ? -1 : 1
        let coeff = sign * sqrt(sq)

        let cxp = coeff * (rx * y1p / ry)
        let cyp = coeff * -(ry * x1p / rx)

        let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) / 2

        let theta1 = angle(ux: 1, uy: 0, vx: (x1p - cxp) / rx, vy: (y1p - cyp) / ry)
        var dTheta = angle(ux: (x1p - cxp) / rx, uy: (y1p - cyp) / ry,
                           vx: (-x1p - cxp) / rx, vy: (-y1p - cyp) / ry)

        if !sweep && dTheta > 0 {
            dTheta -= 2 * .pi
        } else if sweep && dTheta < 0 {
            dTheta += 2 * .pi
        }

        let segments = max(1, Int(ceil(abs(dTheta) / (.pi / 2))))
        let delta = dTheta / CGFloat(segments)

        for i in 0..<segments {
            let t1 = theta1 + CGFloat(i) * delta
            let t2 = t1 + delta
            appendArcSegment(to: path, cx: cx, cy: cy, rx: rx, ry: ry,
                             phi: phi, t1: t1, t2: t2)
        }
    }

    private static func appendArcSegment(to path: UIBezierPath, cx: CGFloat, cy: CGFloat,
                                         rx: CGFloat, ry: CGFloat, phi: CGFloat,
                                         t1: CGFloat, t2: CGFloat) {
        let alpha = sin(t2 - t1) * (sqrt(4 + 3 * pow(tan((t2 - t1) / 2), 2)) - 1) / 3

        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let cosT1 = cos(t1)
        let sinT1 = sin(t1)
        let cosT2 = cos(t2)
        let sinT2 = sin(t2)

        let x1 = cosPhi * rx * cosT1 - sinPhi * ry * sinT1 + cx
        let y1 = sinPhi * rx * cosT1 + cosPhi * ry * sinT1 + cy

        let dx1 = -cosPhi * rx * sinT1 - sinPhi * ry * cosT1
        let dy1 = -sinPhi * rx * sinT1 + cosPhi * ry * cosT1

        let x2 = cosPhi * rx * cosT2 - sinPhi * ry * sinT2 + cx
        let y2 = sinPhi * rx * cosT2 + cosPhi * ry * sinT2 + cy

        let dx2 = -cosPhi * rx * sinT2 - sinPhi * ry * cosT2
        let dy2 = -sinPhi * rx * sinT2 + cosPhi * ry * cosT2

        let cp1 = CGPoint(x: x1 + alpha * dx1, y: y1 + alpha * dy1)
        let cp2 = CGPoint(x: x2 - alpha * dx2, y: y2 - alpha * dy2)
        let end = CGPoint(x: x2, y: y2)

        path.addCurve(to: end, controlPoint1: cp1, controlPoint2: cp2)
    }

    private static func angle(ux: CGFloat, uy: CGFloat, vx: CGFloat, vy: CGFloat) -> CGFloat {
        let dot = ux * vx + uy * vy
        let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
        var ang = acos(max(-1, min(1, dot / len)))
        if ux * vy - uy * vx < 0 {
            ang = -ang
        }
        return ang
    }
}
