import SwiftUI
import UIKit

/// One page per screen with swipe, tap-to-turn and pinch zoom.
struct PagedReader: UIViewControllerRepresentable {
    let urls: [URL]
    let rightToLeft: Bool
    @Binding var page: Int
    let onCenterTap: () -> Void

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
        if let first = context.coordinator.controller(at: page) {
            pager.setViewControllers([first], direction: .forward, animated: false)
        }
        context.coordinator.shown = page
        return pager
    }

    func updateUIViewController(_ pager: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        let directionChanged = coordinator.parent.rightToLeft != rightToLeft
        coordinator.parent = self

        guard page != coordinator.shown || directionChanged,
              let target = coordinator.controller(at: page)
        else { return }

        let movingForward = (page >= coordinator.shown) != rightToLeft
        coordinator.shown = page
        pager.setViewControllers([target], direction: movingForward ? .forward : .reverse, animated: false)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PagedReader
        var shown = 0

        init(_ parent: PagedReader) {
            self.parent = parent
        }

        func controller(at index: Int) -> PageController? {
            guard parent.urls.indices.contains(index) else { return nil }
            let controller = PageController(url: parent.urls[index], index: index)
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
            return controller(at: parent.rightToLeft ? current.index + 1 : current.index - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let current = viewController as? PageController else { return nil }
            return controller(at: parent.rightToLeft ? current.index - 1 : current.index + 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed,
                  let current = pageViewController.viewControllers?.first as? PageController
            else { return }
            shown = current.index
            parent.page = current.index
        }

        /// zone: -1 is the left edge, 0 the middle, 1 the right edge.
        private func handleTap(_ zone: Int) {
            if zone == 0 {
                parent.onCenterTap()
                return
            }
            let step = parent.rightToLeft ? -zone : zone
            let target = shown + step
            if parent.urls.indices.contains(target) {
                parent.page = target
            }
        }
    }
}

final class PageController: UIViewController, UIScrollViewDelegate {
    let url: URL
    let index: Int
    var onTap: ((Int) -> Void)?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var loadTask: Task<Void, Never>?

    init(url: URL, index: Int) {
        self.url = url
        self.index = index
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
        scrollView.maximumZoomScale = 4
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)

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

        let pageURL = url
        loadTask = Task { [weak self] in
            let image = await PageImage.page(pageURL)
            guard !Task.isCancelled, let self else { return }
            self.imageView.image = image
            self.spinner.stopAnimating()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        spinner.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        if scrollView.zoomScale == 1 {
            imageView.frame = scrollView.bounds
            scrollView.contentSize = scrollView.bounds.size
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        scrollView.setZoomScale(1, animated: false)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1 {
            scrollView.setZoomScale(1, animated: true)
            return
        }
        let point = gesture.location(in: imageView)
        let scale: CGFloat = 2.5
        let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        scrollView.zoom(to: rect, animated: true)
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        guard scrollView.zoomScale == 1 else {
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
