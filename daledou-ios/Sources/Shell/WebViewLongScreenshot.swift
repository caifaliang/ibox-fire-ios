import UIKit
import WebKit
import Photos

/// 真源：`WebViewLongScreenshot.kt` — 仅截 WebView 完整网页（不含壳顶栏/底栏）。
/// iOS：按 `scrollView` 滚屏 + `takeSnapshot` 拼接 → 存相册 / 系统分享。
enum WebViewLongScreenshot {
    private static let maxPixels: CGFloat = 48_000_000
    private static let jpegQuality: CGFloat = 0.90

    struct Result {
        let image: UIImage
        let fileURL: URL
    }

    @MainActor
    static func captureAndSave(webView: WKWebView) async throws -> Result {
        let image = try await capture(webView: webView)
        let url = try saveToTemp(image)
        try? await saveToPhotoLibrary(image)
        return Result(image: image, fileURL: url)
    }

    @MainActor
    static func presentShare(image: UIImage, from presenter: UIViewController) {
        let vc = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1, height: 1
            )
            pop.permittedArrowDirections = []
        }
        presenter.present(vc, animated: true)
    }

    // MARK: - capture

    @MainActor
    private static func capture(webView: WKWebView) async throws -> UIImage {
        let viewW = webView.bounds.width
        let viewH = webView.bounds.height
        guard viewW > 8, viewH > 8 else { throw ShotError.notReady }

        let sv = webView.scrollView
        let oldOffset = sv.contentOffset
        let oldBarV = sv.showsVerticalScrollIndicator
        let oldBarH = sv.showsHorizontalScrollIndicator
        sv.showsVerticalScrollIndicator = false
        sv.showsHorizontalScrollIndicator = false

        defer {
            sv.showsVerticalScrollIndicator = oldBarV
            sv.showsHorizontalScrollIndicator = oldBarH
            sv.setContentOffset(oldOffset, animated: false)
        }

        // 滚到顶并让内容尺寸稳定
        sv.setContentOffset(.zero, animated: false)
        _ = await evalJS("window.scrollTo(0,0);1;", in: webView)
        try await Task.sleep(nanoseconds: 100_000_000)

        // JS 高度作上限参考（部分页 contentSize 偏小）
        let jsH = await measureScrollHeightCss(webView)
        let fromJs = CGFloat(jsH) * (sv.zoomScale > 0.01 ? sv.zoomScale : 1)
        var totalH = max(sv.contentSize.height, fromJs, viewH)
        let maxH = maxPixels / viewW
        totalH = min(totalH, maxH)

        let viewWInt = Int(ceil(viewW))
        let viewHInt = Int(ceil(viewH))
        let totalHInt = Int(ceil(totalH))
        let scale = UIScreen.main.scale

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: Int(CGFloat(viewWInt) * scale),
            height: Int(CGFloat(totalHInt) * scale),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ShotError.stitchFailed }

        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        // 翻转为 UIKit 坐标（原点左上）
        ctx.translateBy(x: 0, y: CGFloat(ctx.height))
        ctx.scaleBy(x: scale, y: -scale)

        var drawn = 0
        while drawn < totalHInt {
            let maxScroll = max(0, totalHInt - viewHInt)
            let scrollTo = min(drawn, maxScroll)
            sv.setContentOffset(CGPoint(x: 0, y: scrollTo), animated: false)
            _ = await evalJS("window.scrollTo(0,\(scrollTo));1;", in: webView)
            try await Task.sleep(nanoseconds: 140_000_000)

            let slice = try await takeSnapshot(webView)
            guard let cg = slice.cgImage else {
                drawn += max(1, viewHInt / 2)
                continue
            }
            let srcTop = max(0, drawn - scrollTo)
            let copyH = min(viewHInt - srcTop, totalHInt - drawn)
            if copyH > 0 {
                let crop = CGRect(
                    x: 0,
                    y: CGFloat(srcTop) * slice.scale,
                    width: CGFloat(viewWInt) * slice.scale,
                    height: CGFloat(copyH) * slice.scale
                )
                if let piece = cg.cropping(to: crop) {
                    ctx.draw(piece, in: CGRect(x: 0, y: drawn, width: viewWInt, height: copyH))
                }
            }
            drawn += max(copyH, 1)
        }

        guard let cgOut = ctx.makeImage() else { throw ShotError.stitchFailed }
        return UIImage(cgImage: cgOut, scale: scale, orientation: .up)
    }

    @MainActor
    private static func takeSnapshot(_ webView: WKWebView) async throws -> UIImage {
        let cfg = WKSnapshotConfiguration()
        cfg.rect = CGRect(origin: .zero, size: webView.bounds.size)
        return try await withCheckedThrowingContinuation { cont in
            webView.takeSnapshot(with: cfg) { image, error in
                if let image { cont.resume(returning: image) }
                else { cont.resume(throwing: error ?? ShotError.snapshotFailed) }
            }
        }
    }

    @MainActor
    private static func measureScrollHeightCss(_ webView: WKWebView) async -> Int {
        let js = """
        (function(){
          var b=document.body,e=document.documentElement;
          if(!b&&!e) return 0;
          return Math.max(
            b?b.scrollHeight:0,e?e.scrollHeight:0,
            b?b.offsetHeight:0,e?e.offsetHeight:0
          );
        })();
        """
        let raw = await evalJS(js, in: webView)
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String { return Int(s) ?? 0 }
        return 0
    }

    @MainActor
    private static func evalJS(_ script: String, in webView: WKWebView) async -> Any? {
        await withCheckedContinuation { cont in
            webView.evaluateJavaScript(script) { result, _ in
                cont.resume(returning: result)
            }
        }
    }

    // MARK: - save

    private static func saveToTemp(_ image: UIImage) throws -> URL {
        let name = "daledou_" + stamp() + ".jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard let data = image.jpegData(compressionQuality: jpegQuality) else {
            throw ShotError.compressFailed
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func saveToPhotoLibrary(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    cont.resume(throwing: ShotError.noPhotoPermission)
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { ok, err in
                    if ok { cont.resume() }
                    else { cont.resume(throwing: err ?? ShotError.saveFailed) }
                }
            }
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }

    enum ShotError: LocalizedError {
        case notReady, snapshotFailed, stitchFailed, compressFailed, saveFailed, noPhotoPermission
        var errorDescription: String? {
            switch self {
            case .notReady: return "页面尚未就绪"
            case .snapshotFailed: return "截屏失败"
            case .stitchFailed: return "拼接失败"
            case .compressFailed: return "压缩失败"
            case .saveFailed: return "保存失败"
            case .noPhotoPermission: return "无相册权限"
            }
        }
    }
}
