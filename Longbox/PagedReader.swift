import SwiftUI
import UIKit

/// One screen at a time with swipe, tap-to-turn and pinch zoom.
/// A screen holds one page, or two side by side when `units` pairs them.
struct PagedReader: UIViewControllerRepresentable {
    let urls: [URL]
    /// Page indexes grouped per screen, in reading order.
    let units: [[Int]]
    let rightToLeft: Bool
    let trim: Bool
    /// Step through panels instead of whole pages.
    let guided: Bool
    @Binding var page: Int
    let onCenterTap: () -> Void
    let onPastEnd: () -> Void

    func unitIndex(for page: Int) -> Int {
        units.firstIndex { $0.contains(page) } ?? 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pager = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 12]
        )
        pager.view.backgroundColor = .black
        pager.dataSource = context.coordinator
        pager.delegate = context.coordinator
        context.coordinator.pager = pager

        let start = unitIndex(for: page)
        if let first = context.coordinator.controller(atUnit: start, atEnd: false) {
            pager.setViewControllers([first], direction: .forward, animated: false)
        }
        context.coordinator.shownUnit = start
        return pager
    }

    func updateUIViewController(_ pager: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        let old = coordinator.parent
        let changed = old.units != units
            || old.rightToLeft != rightToLeft
            || old.trim != trim
            || old.guided != guided
            || old.urls != urls
        coordinator.parent = self

        let target = unitIndex(for: page)
        let atEnd = coordinator.enterAtEnd
        coordinator.enterAtEnd = false
        guard target != coordinator.shownUnit || changed,
              let controller = coordinator.controller(atUnit: target, atEnd: atEnd)
        else { return }

        let movingForward = (target >= coordinator.shownUnit) != rightToLeft
        coordinator.shownUnit = target
        pager.setViewControllers([controller], direction: movingForward ? .forward : .reverse, animated: false)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PagedReader
        var shownUnit = 0
        /// Set just before stepping back a page, so the page opens on its last panel.
        var enterAtEnd = false
        weak var pager: UIPageViewController?

        init(_ parent: PagedReader) {
            self.parent = parent
        }

        func controller(atUnit unit: Int, atEnd: Bool) -> PageController? {
            guard parent.units.indices.contains(unit) else { return nil }
            let pages = parent.units[unit].filter { parent.urls.indices.contains($0) }
            guard !pages.isEmpty else { return nil }
            // Left-to-right on screen: manga puts the earlier page on the right.
            let visual = parent.rightToLeft ? Array(pages.reversed()) : pages
            let controller = PageController(
                urls: visual.map { parent.urls[$0] },
                unit: unit,
                trim: parent.trim,
                guided: parent.guided && pages.count == 1,
                rightToLeft: parent.rightToLeft,
                startAtEnd: atEnd
            )
            controller.onTap = { [weak self] zone in
                self?.handleTap(zone)
            }
            return controller
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let current = viewController as? PageController else { return nil }
            // "Before" is the screen to the left.
            if parent.rightToLeft {
                return controller(atUnit: current.unit + 1, atEnd: false)
            }
            return controller(atUnit: current.unit - 1, atEnd: true)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let current = viewController as? PageController else { return nil }
            if parent.rightToLeft {
                return controller(atUnit: current.unit - 1, atEnd: true)
            }
            return controller(atUnit: current.unit + 1, atEnd: false)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed,
                  let current = pageViewController.viewControllers?.first as? PageController,
                  parent.units.indices.contains(current.unit),
                  let firstPage = parent.units[current.unit].first
            else { return }
            shownUnit = current.unit
            parent.page = firstPage
        }

        /// zone: -1 is the left edge, 0 the middle, 1 the right edge.
        private func handleTap(_ zone: Int) {
            if zone == 0 {
                parent.onCenterTap()
                return
            }
            let step = parent.rightToLeft ? -zone : zone

            if parent.guided,
               let current = pager?.viewControllers?.first as? PageController,
               current.advancePanel(by: step) {
                return
            }

            let target = shownUnit + step
            if parent.units.indices.contains(target), let firstPage = parent.units[target].first {
                enterAtEnd = step < 0
                parent.page = firstPage
            } else if step > 0 {
                parent.onPastEnd()
            }
        }
    }
}

final class PageController: UIViewController, UIScrollViewDelegate {
    let urls: [URL]
    let unit: Int
    let trim: Bool
    let guided: Bool
    let rightToLeft: Bool
    var onTap: ((Int) -> Void)?

    private var startAtEnd: Bool
    private let scrollView = UIScrollView()
    private let container = UIView()
    private var imageViews: [UIImageView] = []
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var loadTask: Task<Void, Never>?
    private var lastLayoutSize: CGSize = .zero

    // Guided view
    private var panels: [CGRect] = []
    private var panelsReady = false
    private var panelIndex: Int?
    private var enteredPanels = false

    init(urls: [URL], unit: Int, trim: Bool, guided: Bool, rightToLeft: Bool, startAtEnd: Bool) {
        self.urls = urls
        self.unit = unit
        self.trim = trim
        self.guided = guided
        self.rightToLeft = rightToLeft
        self.startAtEnd = startAtEnd
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = guided ? 8 : 4
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)
        scrollView.addSubview(container)

        for _ in urls {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFit
            container.addSubview(imageView)
            imageViews.append(imageView)
        }

        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.startAnimating()
        view.addSubview(spinner)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        let pageURLs = urls
        let useTrim = trim
        let wantsPanels = guided
        let rtl = rightToLeft
        loadTask = Task { [weak self] in
            for (index, url) in pageURLs.enumerated() {
                let image = await PageImage.page(url, trim: useTrim)
                guard !Task.isCancelled, let self else { return }
                if index < self.imageViews.count {
                    self.imageViews[index].image = image
                }
                self.layoutImages(force: false)
            }
            guard let self else { return }
            self.spinner.stopAnimating()

            guard wantsPanels, let source = self.imageViews.first?.image?.cgImage else { return }
            let found = await Task.detached(priority: .userInitiated) {
                PanelDetector.panels(in: source, rightToLeft: rtl)
            }.value
            guard !Task.isCancelled else { return }
            self.panels = found
            self.panelsReady = true
            self.enterPanelsIfNeeded()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        spinner.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let size = scrollView.bounds.size
        if size != lastLayoutSize {
            // The screen changed shape: start again from the whole page.
            lastLayoutSize = size
            if scrollView.zoomScale != 1 {
                scrollView.setZoomScale(1, animated: false)
            }
            layoutImages(force: true)
            if let index = panelIndex {
                zoomToPanel(index, animated: false)
            } else {
                enterPanelsIfNeeded()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enterPanelsIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        scrollView.setZoomScale(1, animated: false)
        panelIndex = nil
        enteredPanels = false
        startAtEnd = false
    }

    // MARK: Layout

    private func fitted(_ imageSize: CGSize, in area: CGRect, pull: CGFloat) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, area.width > 0, area.height > 0 else { return area }
        let scale = min(area.width / imageSize.width, area.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let free = area.width - size.width
        // pull: 0 hugs the left edge, 0.5 centers, 1 hugs the right edge.
        return CGRect(x: area.minX + free * pull, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func layoutImages(force: Bool) {
        guard force || scrollView.zoomScale == 1 else { return }
        let bounds = scrollView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        container.frame = CGRect(origin: .zero, size: bounds.size)
        scrollView.contentSize = bounds.size
        let area = container.bounds

        if imageViews.count == 2 {
            // Two pages meet at the spine in the middle.
            let half = area.width / 2
            let leftArea = CGRect(x: 0, y: 0, width: half, height: area.height)
            let rightArea = CGRect(x: half, y: 0, width: half, height: area.height)
            imageViews[0].frame = fitted(imageViews[0].image?.size ?? .zero, in: leftArea, pull: 1)
            imageViews[1].frame = fitted(imageViews[1].image?.size ?? .zero, in: rightArea, pull: 0)
        } else if let only = imageViews.first {
            only.frame = fitted(only.image?.size ?? .zero, in: area, pull: 0.5)
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        container
    }

    // MARK: Guided view

    /// Zooms to the first panel (or the last, when arriving backwards) once everything is ready.
    private func enterPanelsIfNeeded() {
        guard guided, panelsReady, !enteredPanels, panels.count >= 2 else { return }
        guard scrollView.bounds.width > 0, imageViews.first?.image != nil else { return }
        enteredPanels = true
        let index = startAtEnd ? panels.count - 1 : 0
        panelIndex = index
        zoomToPanel(index, animated: false)
    }

    private func zoomToPanel(_ index: Int, animated: Bool) {
        guard panels.indices.contains(index), let imageView = imageViews.first else { return }
        let frame = imageView.frame
        guard frame.width > 0, frame.height > 0 else { return }
        let panel = panels[index]
        let pad = frame.width * 0.015
        var rect = CGRect(
            x: frame.minX + panel.minX * frame.width,
            y: frame.minY + panel.minY * frame.height,
            width: panel.width * frame.width,
            height: panel.height * frame.height
        ).insetBy(dx: -pad, dy: -pad)
        rect = rect.intersection(container.bounds)
        guard !rect.isNull, rect.width > 1, rect.height > 1 else { return }
        scrollView.zoom(to: rect, animated: animated)
    }

    /// Moves to the next or previous panel. Returns false when the page has no more in that direction.
    func advancePanel(by step: Int) -> Bool {
        guard guided, panelsReady, panels.count >= 2 else { return false }
        guard let current = panelIndex else {
            // Looking at the whole page: going forward starts the panels.
            if step > 0 {
                panelIndex = 0
                zoomToPanel(0, animated: true)
                return true
            }
            return false
        }
        let next = current + step
        guard panels.indices.contains(next) else { return false }
        panelIndex = next
        zoomToPanel(next, animated: true)
        return true
    }

    // MARK: Taps

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1.01 {
            // Also the way out of a panel, back to the whole page.
            panelIndex = nil
            scrollView.setZoomScale(1, animated: true)
            return
        }
        let point = gesture.location(in: container)
        let scale: CGFloat = 2.5
        let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        scrollView.zoom(to: rect, animated: true)
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        let inPanel = guided && panelIndex != nil
        if scrollView.zoomScale > 1.01 && !inPanel {
            onTap?(0)
            return
        }
        let x = gesture.location(in: view).x
        let width = max(view.bounds.width, 1)
        let fraction = x / width
        if fraction < 0.28 {
            onTap?(-1)
        } else if fraction > 0.72 {
            onTap?(1)
        } else {
            onTap?(0)
        }
    }
}
