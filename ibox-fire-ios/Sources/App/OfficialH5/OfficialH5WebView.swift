import SwiftUI
import WebKit

/// 嵌入 `OfficialH5Session` 保活中的 WKWebView（不新建、不销毁）。
struct OfficialH5WebView: UIViewRepresentable {
    @ObservedObject var session: OfficialH5Session = .shared

    func makeUIView(context: Context) -> UIView {
        let box = UIView()
        box.backgroundColor = .black
        attach(to: box)
        return box
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        attach(to: uiView)
    }

    private func attach(to box: UIView) {
        guard let wv = session.webView else { return }
        if wv.superview !== box {
            wv.removeFromSuperview()
            wv.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(wv)
            NSLayoutConstraint.activate([
                wv.topAnchor.constraint(equalTo: box.topAnchor),
                wv.bottomAnchor.constraint(equalTo: box.bottomAnchor),
                wv.leadingAnchor.constraint(equalTo: box.leadingAnchor),
                wv.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            ])
        }
    }
}
