import SwiftUI
import UIKit

/// Continuous top-to-bottom reading with pinch and double-tap zoom.
struct StripReader: UIViewRepresentable {
    let urls: [URL]
    let aspects: [CGFloat]
    @Binding var page: Int
    let onTap: () -> Void

    func makeUIView(context: Context) -> StripView {
        let view = StripView()
        view.configure(urls: urls, aspects: aspects, startPage: page)
        wire(view)
        return view
    }

    func updateUIView(_ view: StripView, context: Context) {
        wire(view)
        if page != view.currentPage {
            view.scroll(to: page)
        }
    }

    private func wire(_ view: StripView) {
        let binding = $page
        view.onPage = { newPage in
            if binding.wrappedValue != newPage {
                binding.wrappedValue = newPage
            }
        }
        view.onTap = onTap
    }
}

/// A zoomable scroll view that lays every page out in one tall column and only
/// keeps image views alive for the pages near the screen.
final class StripView: UIScrollView, UIScrollViewDelegate {
    var onPage: ((Int) -> Void)?
    var onTap: (() -> Void)?
    private(set) var currentPage = 0

    private var urls: [URL] = []
    private var aspects: [CGFloat] = []
    /// Top edge of each page in unzoomed points, plus one final entry for the bottom.
    private var tops: [CGFloat] = [0]
    private let content = UIView()
    private var live: [Int: UIImageView] = [:]
    private var loads: [Int: Task<Void, Never>] = [:]
    private var laidOutWidth: CGFloat = 0
    private var silent = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        addSubview(content)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(urls: [URL], aspects: [CGFloat], startPage: Int) {
        self.urls = urls
        self.aspects = aspects
        currentPage = min(max(startPage, 0), max(urls.count - 1, 0))
        laidOutWidth = 0
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        if width > 0 && abs(width - laidOutWidth) > 0.5 {
            rebuild(width: width)
        }
    }

    /// Lays the column out again for a new width, keeping the current page in place.
    private func rebuild(width: CGFloat) {
        silent = true
        laidOutWidth = width
        if zoomScale != 1 {
            setZoomScale(1, animated: false)
        }

        var running: CGFloat = 0
        var newTops: [CGFloat] = [0]
        newTops.reserveCapacity(urls.count + 1)
        for index in urls.indices {
            let aspect = index < aspects.count && aspects[index] > 0.01 ? aspects[index] : 0.66
            running += (width / aspect).rounded()
            newTops.append(running)
        }
        tops = newTops

        for (_, view) in live { view.removeFromSuperview() }
        live.removeAll()
        for (_, task) in loads { task.cancel() }
        loads.removeAll()

        content.frame = CGRect(x: 0, y: 0, width: width, height: max(running, 1))
        contentSize = content.frame.size
        silent = false
        scroll(to: currentPage)
    }

    func scroll(to page: Int) {
        guard !urls.isEmpty else { return }
        let target = min(max(page, 0), urls.count - 1)
        currentPage = target
        guard tops.count == urls.count + 1, laidOutWidth > 0 else { return }
        silent = true
        let maxY = max(contentSize.height - bounds.height, 0)
        let y = min(tops[target] * zoomScale, maxY)
        setContentOffset(CGPoint(x: contentOffset.x, y: y), animated: false)
        silent = false
        tile()
    }

    // MARK: Tiling

    private func index(atY y: CGFloat) -> Int {
        guard !urls.isEmpty else { return 0 }
        var low = 0
        var high = urls.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if tops[mid] <= y {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    private func tile() {
        guard !urls.isEmpty, tops.count == urls.count + 1, laidOutWidth > 0 else { return }
        let visible = content.convert(bounds, from: self)
        let margin = visible.height * 0.75
        let first = index(atY: visible.minY - margin)
        let last = index(atY: visible.maxY + margin)

        for index in first...last where live[index] == nil {
            addPage(index)
        }
        for index in Array(live.keys) where index < first || index > last {
            live[index]?.removeFromSuperview()
            live[index] = nil
            loads[index]?.cancel()
            loads[index] = nil
        }
    }

    private func addPage(_ index: Int) {
        let frame = CGRect(x: 0, y: tops[index], width: laidOutWidth, height: tops[index + 1] - tops[index])
        let imageView = UIImageView(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        content.addSubview(imageView)
        live[index] = imageView

        let url = urls[index]
        loads[index] = Task { [weak self, weak imageView] in
            let image = await PageImage.page(url)
            guard !Task.isCancelled, let self, let imageView else { return }
            if self.live[index] === imageView {
                imageView.image = image
            }
        }
    }

    private func reportPage() {
        guard !silent, !urls.isEmpty, tops.count == urls.count + 1 else { return }
        let visible = content.convert(bounds, from: self)
        let page = index(atY: max(visible.minY + visible.height * 0.3, 0))
        if page != currentPage {
            currentPage = page
            onPage?(page)
        }
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        content
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard laidOutWidth > 0 else { return }
        tile()
        reportPage()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard laidOutWidth > 0 else { return }
        tile()
    }

    // MARK: Taps

    @objc private func handleSingleTap() {
        onTap?()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1.01 {
            setZoomScale(1, animated: true)
            return
        }
        let point = gesture.location(in: content)
        let scale: CGFloat = 2
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        zoom(to: rect, animated: true)
    }
}
