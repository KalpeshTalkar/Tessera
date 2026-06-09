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

// MARK: - Delegate Protocol

/// Delegate for receiving lifecycle, selection, and focus events from `TesseraView`.
public protocol TesseraViewDelegate: AnyObject {
    /// Called when SVG parsing begins (before any regions are available).
    /// - Parameter view: The tessera view that started loading.
    func tesseraViewDidBeginLoading(_ view: TesseraView)
    /// Called when parsing completes successfully.
    /// - Parameters:
    ///   - view: The tessera view that finished loading.
    ///   - regionIds: Identifiers of all rendered regions.
    func tesseraView(_ view: TesseraView, didFinishLoadingRegions regionIds: [String])
    /// Called when SVG loading fails (file not found, corrupt data, missing viewBox, etc.).
    /// - Parameters:
    ///   - view: The tessera view that encountered the error.
    ///   - error: The specific loading error.
    func tesseraView(_ view: TesseraView, didFailWithError error: TesseraError)
    /// Called for non-fatal parsing issues (duplicate ids, unsupported elements, empty paths).
    /// - Parameters:
    ///   - view: The tessera view that encountered the warning.
    ///   - warning: The non-fatal warning detail.
    func tesseraView(_ view: TesseraView, didEncounterWarning warning: TesseraWarning)
    /// Called when a region is selected via tap or programmatic `select(id:)`.
    /// - Parameters:
    ///   - view: The tessera view where selection occurred.
    ///   - regionId: The identifier of the selected region.
    func tesseraView(_ view: TesseraView, didSelect regionId: String)
    /// Called when a region is deselected via tap or programmatic `deselect(id:)`.
    /// - Parameters:
    ///   - view: The tessera view where deselection occurred.
    ///   - regionId: The identifier of the deselected region.
    func tesseraView(_ view: TesseraView, didDeselect regionId: String)
    /// Called when a region is highlighted during a pan/drag gesture.
    /// - Parameters:
    ///   - view: The tessera view where highlighting occurred.
    ///   - regionId: The identifier of the highlighted region.
    func tesseraView(_ view: TesseraView, didHighlight regionId: String)
    /// Called when a region's highlight is removed (finger leaves the region or gesture ends).
    /// - Parameters:
    ///   - view: The tessera view where unhighlighting occurred.
    ///   - regionId: The identifier of the unhighlighted region.
    func tesseraView(_ view: TesseraView, didUnhighlight regionId: String)
    /// Called when the view zooms into a group, showing its child regions.
    /// - Parameters:
    ///   - view: The tessera view that focused a group.
    ///   - groupId: The identifier of the focused group.
    ///   - childIds: Identifiers of the child regions now visible.
    func tesseraView(_ view: TesseraView, didFocusGroup groupId: String, childIds: [String])
    /// Called when the view animates back from a focused group to the full overview.
    /// - Parameter view: The tessera view that unfocused.
    func tesseraViewDidUnfocusGroup(_ view: TesseraView)
}

public extension TesseraViewDelegate {
    func tesseraViewDidBeginLoading(_ view: TesseraView) {}
    func tesseraView(_ view: TesseraView, didFinishLoadingRegions regionIds: [String]) {}
    func tesseraView(_ view: TesseraView, didFailWithError error: TesseraError) {}
    func tesseraView(_ view: TesseraView, didEncounterWarning warning: TesseraWarning) {}
    func tesseraView(_ view: TesseraView, didSelect regionId: String) {}
    func tesseraView(_ view: TesseraView, didDeselect regionId: String) {}
    func tesseraView(_ view: TesseraView, didHighlight regionId: String) {}
    func tesseraView(_ view: TesseraView, didUnhighlight regionId: String) {}
    func tesseraView(_ view: TesseraView, didFocusGroup groupId: String, childIds: [String]) {}
    func tesseraViewDidUnfocusGroup(_ view: TesseraView) {}
}

// MARK: - Loading State

/// Tracks the SVG loading lifecycle.
public enum TesseraLoadingState {
    case idle
    case loading
    case loaded
    case failed(TesseraError)
}

// MARK: - TesseraView

/// A UIView that renders interactive SVG image maps using `CAShapeLayer`s.
///
/// Load an SVG file, then interact via tap (select/deselect) and pan (highlight).
/// Groups can be focused to zoom into child regions with animated transitions.
public final class TesseraView: UIView {

    // MARK: Public

    public weak var delegate: TesseraViewDelegate?
    /// Configuration for colors, interaction, and haptics. Changes are applied immediately.
    public var configuration: TesseraConfiguration = .default { didSet { applyConfiguration() } }
    public private(set) var loadingState: TesseraLoadingState = .idle
    /// The set of currently selected region ids.
    public private(set) var selectedIds: Set<String> = []
    /// The id of the group currently focused (zoomed into), or `nil`.
    public var focusedGroupId: String? { focusState.groupId }

    // MARK: Private State

    private var groupRegions: [SVGRegion] = []
    private var childRegions: [SVGRegion] = []
    private var regions: [SVGRegion] = []
    private var focusState: FocusState = .idle
    private var highlightedId: String?
    private var currentDragRegionId: String?
    private var viewBox: CGRect = .zero
    private var loadTask: Task<Void, Never>?
    private var lastLayoutBounds: CGRect = .zero

    private lazy var layerManager = RegionLayerManager(parentLayer: layer)

    // MARK: Gesture Recognizers

    private lazy var tapGesture: UITapGestureRecognizer = {
        UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    }()

    private lazy var panGesture: UIPanGestureRecognizer = {
        UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    }()

    // MARK: Haptics

    private var selectionGenerator: UIImpactFeedbackGenerator?
    private var deselectionGenerator: UIImpactFeedbackGenerator?
    private var highlightGenerator: UIImpactFeedbackGenerator?

    // MARK: Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        addGestureRecognizer(tapGesture)
        tapGesture.isEnabled = false
    }

    // MARK: Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard !regions.isEmpty, viewBox != .zero else { return }
        guard focusState.allowsLayoutUpdate else { return }
        guard bounds != lastLayoutBounds else { return }
        lastLayoutBounds = bounds

        let calculator = makeTransformCalculator()
        switch focusState {
        case .focused(let groupId):
            if let groupRegion = groupRegions.first(where: { $0.id == groupId }) {
                let transform = calculator.aspectFitTransform(for: groupRegion.bounds, padding: 20)
                layerManager.applyTransform(transform, to: regions, bounds: bounds)
            }
        default:
            let transform = calculator.aspectFitTransform()
            layerManager.applyTransform(transform, to: regions, bounds: bounds)
        }
    }

    // MARK: - Public API: Loading

    /// Loads and renders an SVG from the app bundle.
    /// - Parameters:
    ///   - resource: The SVG filename without extension.
    ///   - bundle: The bundle containing the SVG file.
    public func load(svgNamed resource: String, in bundle: Bundle = .main) {
        if case .loading = loadingState {
            delegate?.tesseraView(self, didFailWithError: .alreadyLoading)
            return
        }

        startLoading()

        loadTask = Task.detached { [weak self] in
            do {
                let result = try SVGDocument.parse(named: resource, in: bundle)
                await self?.didFinishParsing(result)
            } catch let error as TesseraError {
                await self?.didFailLoading(error)
            } catch {
                await self?.didFailLoading(.invalidSVGStructure(reason: error.localizedDescription))
            }
        }
    }

    /// Loads and renders an SVG from raw data.
    /// - Parameter data: Raw SVG file data encoded as UTF-8.
    public func load(svgData data: Data) {
        if case .loading = loadingState {
            delegate?.tesseraView(self, didFailWithError: .alreadyLoading)
            return
        }

        startLoading()

        loadTask = Task.detached { [weak self] in
            do {
                let result = try SVGDocument.parse(data: data)
                await self?.didFinishParsing(result)
            } catch let error as TesseraError {
                await self?.didFailLoading(error)
            } catch {
                await self?.didFailLoading(.invalidSVGStructure(reason: error.localizedDescription))
            }
        }
    }

    // MARK: - Public API: Selection

    /// Programmatically selects a region. Does not fire haptics (haptics are gesture-driven only).
    /// - Parameter id: The identifier of the region to select.
    /// - Throws: `TesseraError.regionNotFound` if no region with the given id exists.
    public func select(id: String) throws {
        guard layerManager.contains(id) else { throw TesseraError.regionNotFound(id: id) }

        if !configuration.isMultiSelectEnabled {
            clearSelectionSilently()
        }

        selectedIds.insert(id)
        updateLayerAppearance(id: id)
        delegate?.tesseraView(self, didSelect: id)
    }

    /// Programmatically deselects a region.
    /// - Parameter id: The identifier of the region to deselect.
    /// - Throws: `TesseraError.regionNotFound` if no region with the given id exists.
    public func deselect(id: String) throws {
        guard layerManager.contains(id) else { throw TesseraError.regionNotFound(id: id) }
        guard selectedIds.remove(id) != nil else { return }

        updateLayerAppearance(id: id)
        delegate?.tesseraView(self, didDeselect: id)
    }

    /// Programmatically highlights a region (visual only, no selection).
    /// - Parameter id: The identifier of the region to highlight.
    /// - Throws: `TesseraError.regionNotFound` if no region with the given id exists.
    public func highlight(id: String) throws {
        guard layerManager.contains(id) else { throw TesseraError.regionNotFound(id: id) }

        if let previousId = highlightedId, previousId != id {
            unhighlightSilently(previousId)
        }

        highlightedId = id
        updateLayerAppearance(id: id)
        delegate?.tesseraView(self, didHighlight: id)
    }

    /// Removes the highlight from a region.
    /// - Parameter id: The identifier of the region to unhighlight.
    /// - Throws: `TesseraError.regionNotFound` if no region with the given id exists.
    public func unhighlight(id: String) throws {
        guard layerManager.contains(id) else { throw TesseraError.regionNotFound(id: id) }
        guard highlightedId == id else { return }

        highlightedId = nil
        updateLayerAppearance(id: id)
        delegate?.tesseraView(self, didUnhighlight: id)
    }

    /// Deselects all currently selected regions.
    public func clearSelection() {
        let previousIds = selectedIds
        selectedIds.removeAll()
        for id in previousIds {
            updateLayerAppearance(id: id)
            delegate?.tesseraView(self, didDeselect: id)
        }
    }

    /// Clears both selection and highlight state.
    public func resetInteractionState() {
        if let hId = highlightedId {
            highlightedId = nil
            updateLayerAppearance(id: hId)
        }
        clearSelection()
    }

    // MARK: - Public API: Group Focus

    /// Animates back from a focused group to the full overview.
    public func unfocusGroup() {
        guard case .focused(let groupId) = focusState else { return }
        focusState = .unfocusing(groupId: groupId)
        resetInteractionState()
        animateToFullView()
    }

    // MARK: - Private: Loading

    private func startLoading() {
        loadTask?.cancel()
        loadingState = .loading
        tapGesture.isEnabled = false
        panGesture.isEnabled = false
        delegate?.tesseraViewDidBeginLoading(self)
    }

    @MainActor
    private func didFinishParsing(_ result: SVGDocument.ParseResult) {
        for warning in result.warnings {
            delegate?.tesseraView(self, didEncounterWarning: warning)
        }

        self.viewBox = result.viewBox
        self.groupRegions = result.regions
        self.childRegions = result.childRegions
        self.regions = activeRegions()

        layerManager.buildLayers(for: regions, configuration: configuration)
        applyCurrentTransform()

        loadingState = .loaded
        tapGesture.isEnabled = true
        configurePanGesture()
        configureHaptics()

        delegate?.tesseraView(self, didFinishLoadingRegions: regions.map(\.id))
    }

    @MainActor
    private func didFailLoading(_ error: TesseraError) {
        loadingState = .failed(error)
        delegate?.tesseraView(self, didFailWithError: error)
    }

    // MARK: - Private: Configuration

    private func activeRegions() -> [SVGRegion] {
        if configuration.isGroupSelectionEnabled && !configuration.preservesSVGColors {
            return groupRegions.sorted { $0.documentOrder < $1.documentOrder }
        }
        var result: [SVGRegion] = []
        for region in groupRegions {
            if region.isGroup {
                let children = childRegions.filter { $0.parentGroupId == region.id }
                result.append(contentsOf: children)
            } else {
                result.append(region)
            }
        }
        return result.sorted { $0.documentOrder < $1.documentOrder }
    }

    private func applyConfiguration() {
        if focusState.allowsConfigUpdate {
            let newRegions = activeRegions()
            if newRegions.map(\.id) != regions.map(\.id) {
                resetInteractionState()
                regions = newRegions
                layerManager.buildLayers(for: regions, configuration: configuration)
                applyCurrentTransform()
                delegate?.tesseraView(self, didFinishLoadingRegions: regions.map(\.id))
            }
        }

        configurePanGesture()
        configureHaptics()
        layerManager.updateStroke(configuration: configuration)

        for region in regions {
            updateLayerAppearance(id: region.id)
        }
    }

    private func configurePanGesture() {
        if configuration.isDragToHighlightEnabled {
            if panGesture.view == nil {
                addGestureRecognizer(panGesture)
            }
            panGesture.isEnabled = true
        } else {
            panGesture.isEnabled = false
        }
    }

    private func configureHaptics() {
        if configuration.isHapticEnabled {
            selectionGenerator = UIImpactFeedbackGenerator(style: configuration.selectionHapticStyle)
            deselectionGenerator = UIImpactFeedbackGenerator(style: configuration.deselectionHapticStyle)
            highlightGenerator = UIImpactFeedbackGenerator(style: configuration.highlightHapticStyle)
        } else {
            selectionGenerator = nil
            deselectionGenerator = nil
            highlightGenerator = nil
        }
    }

    // MARK: - Private: Group Focus

    private func focusOnGroup(_ groupId: String) {
        guard focusState == .idle else { return }
        let children = childRegions.filter { $0.parentGroupId == groupId }
        guard !children.isEmpty else { return }
        guard let groupRegion = groupRegions.first(where: { $0.id == groupId }) else { return }

        focusState = .focusing(groupId: groupId)
        resetInteractionState()

        switch configuration.groupFocusTransition {
        case .fade:
            focusWithFade(children: children, groupRegion: groupRegion)
        case .expand:
            focusWithExpand(children: children, groupRegion: groupRegion)
        }

        let childIds = children.map(\.id)
        delegate?.tesseraView(self, didFocusGroup: groupId, childIds: childIds)
    }

    private func didCompleteFocus(groupId: String) {
        focusState = .focused(groupId: groupId)
    }

    private func animateToFullView() {
        switch configuration.groupFocusTransition {
        case .fade:
            unfocusWithFade()
        case .expand:
            unfocusWithExpand()
        }
    }

    private func didCompleteUnfocus() {
        focusState = .idle
        delegate?.tesseraViewDidUnfocusGroup(self)
    }

    // MARK: Fade Transition

    private func focusWithFade(children: [SVGRegion], groupRegion: SVGRegion) {
        let oldLayerMap = layerManager.layerMap
        let groupId = groupRegion.id
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(timing)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            for (_, layer) in oldLayerMap {
                layer.removeFromSuperlayer()
            }

            self.regions = children
            self.layerManager.buildLayers(for: self.regions, configuration: self.configuration, opacity: 0)
            let calculator = self.makeTransformCalculator()
            let transform = calculator.aspectFitTransform(for: groupRegion.bounds, padding: 20)
            self.layerManager.applyTransform(transform, to: self.regions, bounds: self.bounds)

            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            CATransaction.setAnimationTimingFunction(timing)
            CATransaction.setCompletionBlock { [weak self] in
                self?.didCompleteFocus(groupId: groupId)
            }
            self.layerManager.setOpacity(1)
            CATransaction.commit()
        }
        for (_, layer) in oldLayerMap {
            layer.opacity = 0
        }
        CATransaction.commit()
    }

    private func unfocusWithFade() {
        let oldLayerMap = layerManager.layerMap
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(timing)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            for (_, layer) in oldLayerMap {
                layer.removeFromSuperlayer()
            }

            self.regions = self.activeRegions()
            self.layerManager.buildLayers(for: self.regions, configuration: self.configuration, opacity: 0)
            self.applyCurrentTransform()

            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            CATransaction.setAnimationTimingFunction(timing)
            CATransaction.setCompletionBlock { [weak self] in
                self?.didCompleteUnfocus()
            }
            self.layerManager.setOpacity(1)
            CATransaction.commit()
        }
        for (_, layer) in oldLayerMap {
            layer.opacity = 0
        }
        CATransaction.commit()
    }

    // MARK: Expand Transition

    private func focusWithExpand(children: [SVGRegion], groupRegion: SVGRegion) {
        let oldLayerMap = layerManager.layerMap
        let groupId = groupRegion.id

        regions = children
        layerManager.buildLayers(for: regions, configuration: configuration)

        let calculator = makeTransformCalculator()
        let fullTransform = calculator.aspectFitTransform()
        layerManager.applyTransform(fullTransform, to: regions, bounds: bounds)

        oldLayerMap[groupRegion.id]?.removeFromSuperlayer()

        let targetTransform = calculator.aspectFitTransform(for: groupRegion.bounds, padding: 20)
        let duration: CFTimeInterval = 0.4
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(timing)
        CATransaction.setCompletionBlock { [weak self] in
            for (id, layer) in oldLayerMap where id != groupRegion.id {
                layer.removeFromSuperlayer()
            }
            self?.didCompleteFocus(groupId: groupId)
        }

        for (id, layer) in oldLayerMap where id != groupRegion.id {
            layer.opacity = 0
        }

        var t = targetTransform
        for region in regions {
            guard let shapeLayer = layerManager.layerMap[region.id] else { continue }
            guard let expandedPath = region.path.cgPath.copy(using: &t) else { continue }

            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = shapeLayer.path
            animation.toValue = expandedPath
            animation.duration = duration
            animation.timingFunction = timing

            shapeLayer.path = expandedPath
            shapeLayer.frame = bounds
            shapeLayer.add(animation, forKey: "expand")
        }

        CATransaction.commit()
    }

    private func unfocusWithExpand() {
        guard case .unfocusing(let groupId) = focusState else {
            unfocusWithFade()
            return
        }
        guard groupRegions.contains(where: { $0.id == groupId }) else {
            unfocusWithFade()
            return
        }

        let calculator = makeTransformCalculator()
        let fullTransform = calculator.aspectFitTransform()
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)
        let childLayerMap = layerManager.layerMap

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.4)
        CATransaction.setAnimationTimingFunction(timing)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            for (_, l) in childLayerMap {
                l.removeFromSuperlayer()
            }

            self.regions = self.activeRegions()
            self.layerManager.buildLayers(for: self.regions, configuration: self.configuration, opacity: 0)
            self.applyCurrentTransform()

            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            CATransaction.setAnimationTimingFunction(timing)
            CATransaction.setCompletionBlock { [weak self] in
                self?.didCompleteUnfocus()
            }
            self.layerManager.setOpacity(1)
            CATransaction.commit()
        }

        var ft = fullTransform
        for (id, shapeLayer) in childLayerMap {
            guard let region = childRegions.first(where: { $0.id == id }) else { continue }
            guard let targetPath = region.path.cgPath.copy(using: &ft) else { continue }

            let anim = CABasicAnimation(keyPath: "path")
            anim.fromValue = shapeLayer.path
            anim.toValue = targetPath
            anim.duration = 0.4
            anim.timingFunction = timing

            shapeLayer.path = targetPath
            shapeLayer.add(anim, forKey: "shrink")
        }

        CATransaction.commit()
    }

    // MARK: - Private: Transform

    private func makeTransformCalculator() -> RegionTransformCalculator {
        RegionTransformCalculator(viewBox: viewBox, viewBounds: bounds)
    }

    private func applyCurrentTransform() {
        guard viewBox.width > 0, viewBox.height > 0 else { return }
        let calculator = makeTransformCalculator()

        switch focusState {
        case .focused(let groupId):
            if let groupRegion = groupRegions.first(where: { $0.id == groupId }) {
                let transform = calculator.aspectFitTransform(for: groupRegion.bounds, padding: 20)
                layerManager.applyTransform(transform, to: regions, bounds: bounds)
            }
        default:
            let transform = calculator.aspectFitTransform()
            layerManager.applyTransform(transform, to: regions, bounds: bounds)
        }
    }

    // MARK: - Private: Gesture Handling

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard focusState.allowsInteraction else { return }
        let point = gesture.location(in: self)
        guard let regionId = layerManager.hitTest(point: point, regions: regions) else { return }

        if configuration.isGroupSelectionEnabled, configuration.preservesSVGColors, focusState == .idle {
            if let groupId = resolveGroupId(for: regionId) {
                if configuration.isZoomToGroupEnabled {
                    focusOnGroup(groupId)
                } else {
                    selectGroup(groupId)
                }
                return
            }
        }

        if configuration.isZoomToGroupEnabled,
           configuration.isGroupSelectionEnabled,
           focusState == .idle,
           let region = regions.first(where: { $0.id == regionId }),
           region.isGroup {
            focusOnGroup(regionId)
            return
        }

        if selectedIds.contains(regionId) {
            try? deselect(id: regionId)
            fireHaptic(deselectionGenerator)
        } else {
            try? select(id: regionId)
            fireHaptic(selectionGenerator)
        }
    }

    private func resolveGroupId(for regionId: String) -> String? {
        if let region = groupRegions.first(where: { $0.id == regionId }), region.isGroup {
            return regionId
        }
        if let child = childRegions.first(where: { $0.id == regionId }) {
            return child.parentGroupId
        }
        return nil
    }

    private func selectGroup(_ groupId: String) {
        let childIds = childRegions.filter { $0.parentGroupId == groupId }.map(\.id)
        let targetIds: [String] = configuration.preservesSVGColors ? childIds : [groupId]

        let allSelected = targetIds.allSatisfy { selectedIds.contains($0) }
        if allSelected {
            for id in targetIds { try? deselect(id: id) }
            fireHaptic(deselectionGenerator)
        } else {
            if !configuration.isMultiSelectEnabled {
                clearSelectionSilently()
            }
            for id in targetIds {
                guard layerManager.contains(id) else { continue }
                selectedIds.insert(id)
                updateLayerAppearance(id: id)
            }
            fireHaptic(selectionGenerator)
            delegate?.tesseraView(self, didSelect: groupId)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard focusState.allowsInteraction else { return }
        let point = gesture.location(in: self)

        switch gesture.state {
        case .began:
            highlightGenerator?.prepare()
            let regionId = layerManager.hitTest(point: point, regions: regions)
            dragDidEnterRegion(regionId)

        case .changed:
            let regionId = layerManager.hitTest(point: point, regions: regions)
            if regionId != currentDragRegionId {
                dragDidExitCurrentRegion()
                dragDidEnterRegion(regionId)
            }

        case .ended:
            if configuration.selectsOnDragEnd, let regionId = currentDragRegionId {
                try? select(id: regionId)
            }
            dragDidExitCurrentRegion()

        case .cancelled, .failed:
            dragDidExitCurrentRegion()

        default:
            break
        }
    }

    private func dragDidEnterRegion(_ regionId: String?) {
        currentDragRegionId = regionId
        guard let regionId else { return }
        highlightedId = regionId
        updateLayerAppearance(id: regionId)
        fireHaptic(highlightGenerator)
        delegate?.tesseraView(self, didHighlight: regionId)
    }

    private func dragDidExitCurrentRegion() {
        guard let regionId = currentDragRegionId else { return }
        currentDragRegionId = nil
        highlightedId = nil
        updateLayerAppearance(id: regionId)
        delegate?.tesseraView(self, didUnhighlight: regionId)
    }

    // MARK: - Private: Helpers

    private func updateLayerAppearance(id: String) {
        layerManager.updateAppearance(
            for: id,
            selectedIds: selectedIds,
            highlightedId: highlightedId,
            configuration: configuration
        )
    }

    private func clearSelectionSilently() {
        let previousIds = selectedIds
        selectedIds.removeAll()
        for id in previousIds {
            updateLayerAppearance(id: id)
        }
    }

    private func unhighlightSilently(_ id: String) {
        highlightedId = nil
        updateLayerAppearance(id: id)
        delegate?.tesseraView(self, didUnhighlight: id)
    }

    private func fireHaptic(_ generator: UIImpactFeedbackGenerator?) {
        generator?.impactOccurred()
    }
}
