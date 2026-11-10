import Foundation
import WebKit

/// 对齐 Android H5ApiBridge：sail-api XHR/fetch → 原生 URLSession → 回灌。
final class H5ApiBridge: NSObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?
    private let session: URLSession
    private let queue = DispatchQueue(label: "ibox.fire.h5.bridge", qos: .userInitiated)

    init(webView: WKWebView, session: URLSession = .shared) {
        self.webView = webView
        self.session = session
        super.init()
    }

    func attach(to controller: WKUserContentController) {
        controller.removeScriptMessageHandler(forName: "IboxFireNet")
        controller.add(self, name: "IboxFireNet")
    }

    func detach(from controller: WKUserContentController) {
        controller.removeScriptMessageHandler(forName: "IboxFireNet")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "IboxFireNet",
              let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let url = body["url"] as? String else { return }
        let method = (body["method"] as? String)?.uppercased() ?? "GET"
        let headersJson = body["headers"] as? String ?? "{}"
        let reqBody = body["body"] as? String ?? ""
        queue.async { [weak self] in
            self?.perform(id: id, method: method, url: url, headersJson: headersJson, body: reqBody)
        }
    }

    private func perform(id: String, method: String, url: String, headersJson: String, body: String) {
        var done: [String: Any] = ["id": id]
        defer {
            if let data = try? JSONSerialization.data(withJSONObject: done),
               let lit = String(data: data, encoding: .utf8) {
                let js = "window.__iboxFireNetDone&&window.__iboxFireNetDone(\(Self.jsQuote(lit)))"
                DispatchQueue.main.async { [weak self] in
                    self?.webView?.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }
        guard let u = URL(string: url) else {
            done["status"] = 0
            done["body"] = ""
            done["headers"] = [String: String]()
            done["err"] = "bad url"
            return
        }
        var req = URLRequest(url: u, timeoutInterval: 45)
        req.httpMethod = method
        if let hdrData = headersJson.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: hdrData) as? [String: Any] {
            for (k, v) in obj {
                let lk = k.lowercased()
                if lk == "host" || lk == "content-length" || lk == "accept-encoding" { continue }
                if let s = v as? String, !s.isEmpty { req.setValue(s, forHTTPHeaderField: k) }
            }
        }
        if req.value(forHTTPHeaderField: "Origin") == nil {
            req.setValue(SharedPrefsPack.h5Origin, forHTTPHeaderField: "Origin")
        }
        if req.value(forHTTPHeaderField: "Referer") == nil {
            req.setValue(SharedPrefsPack.h5Boot, forHTTPHeaderField: "Referer")
        }
        let hasBody = method != "GET" && method != "HEAD"
        if hasBody {
            let b64 = req.value(forHTTPHeaderField: "X-Ibox-Body-B64") == "1"
            req.setValue(nil, forHTTPHeaderField: "X-Ibox-Body-B64")
            if b64, let raw = Data(base64Encoded: body) {
                req.httpBody = raw
            } else {
                req.httpBody = body.data(using: .utf8)
            }
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                req.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            }
        }
        do {
            let (data, resp) = try session.syncData(for: req)
            let http = resp as? HTTPURLResponse
            var rh: [String: String] = [:]
            http?.allHeaderFields.forEach { k, v in
                rh["\(k)"] = "\(v)"
            }
            done["status"] = http?.statusCode ?? 0
            done["body"] = data.base64EncodedString()
            done["headers"] = rh
            done["err"] = ""
        } catch {
            done["status"] = 0
            done["body"] = ""
            done["headers"] = [String: String]()
            done["err"] = error.localizedDescription
        }
    }

    private static func jsQuote(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed])
        return String(data: data ?? Data("\"\"".utf8), encoding: .utf8) ?? "\"\""
    }

    /// WK：用 messageHandlers 代替 Android JavascriptInterface
    static func bootScript() -> String {
        """
        <script>
        (function(){
          if (window.__iboxFireNetPatched) return;
          window.__iboxFireNetPatched = true;
          window.IboxFireNet = {
            request: function(id, method, url, headersJson, body){
              try {
                window.webkit.messageHandlers.IboxFireNet.postMessage({
                  id: String(id||''),
                  method: String(method||'GET'),
                  url: String(url||''),
                  headers: String(headersJson||'{}'),
                  body: body == null ? '' : String(body)
                });
              } catch (e) {}
            }
          };
          var RE = /^https:\\/\\/(sail-api\\.ibox\\.art)(\\/|$)/i;
          var pending = {};
          window.__iboxFireNetDone = function(raw){
            try{
              var o = (typeof raw === 'string') ? JSON.parse(raw) : raw;
              var p = pending[o.id];
              if (!p) return;
              delete pending[o.id];
              if (o.err && !o.status) { p.reject(String(o.err)); return; }
              var bin = '';
              try { bin = atob(o.body || ''); } catch (e) { bin = ''; }
              p.resolve({ status: o.status|0, body: bin, headers: o.headers || {} });
            }catch(e){}
          };
          function bridge(method, url, headers, body){
            return new Promise(function(resolve, reject){
              if (!window.IboxFireNet || !window.IboxFireNet.request) {
                reject('IboxFireNet missing');
                return;
              }
              var id = 'n' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
              pending[id] = { resolve: resolve, reject: reject };
              var bodyStr = '';
              if (body != null && body !== undefined) {
                if (typeof body === 'string') bodyStr = body;
                else {
                  try { bodyStr = String(body); } catch (e2) { bodyStr = ''; }
                }
              }
              try {
                window.IboxFireNet.request(id, method || 'GET', url, JSON.stringify(headers || {}), bodyStr);
              } catch (e3) {
                delete pending[id];
                reject(String(e3 && e3.message ? e3.message : e3));
              }
            });
          }
          function applyXhrResult(xhr, r){
            var body = r.body || '';
            try {
              Object.defineProperty(xhr, 'readyState', { configurable: true, get: function(){ return 4; } });
              Object.defineProperty(xhr, 'status', { configurable: true, get: function(){ return r.status|0; } });
              Object.defineProperty(xhr, 'statusText', { configurable: true, get: function(){ return (r.status|0) ? 'OK' : 'error'; } });
              Object.defineProperty(xhr, 'responseText', { configurable: true, get: function(){ return body; } });
              Object.defineProperty(xhr, 'response', { configurable: true, get: function(){ return body; } });
              xhr.getAllResponseHeaders = function(){
                var h = r.headers || {}, out = [];
                for (var k in h) if (Object.prototype.hasOwnProperty.call(h, k)) out.push(k + ': ' + h[k]);
                return out.join('\\r\\n');
              };
              xhr.getResponseHeader = function(name){
                var h = r.headers || {}, l = String(name||'').toLowerCase();
                for (var k in h) if (String(k).toLowerCase() === l) return h[k];
                return null;
              };
            } catch (e) {}
            try { if (typeof xhr.onreadystatechange === 'function') xhr.onreadystatechange(); } catch (e1) {}
            try { if (typeof xhr.onload === 'function') xhr.onload(); } catch (e2) {}
          }
          var xo = XMLHttpRequest.prototype.open;
          var xs = XMLHttpRequest.prototype.send;
          var xh = XMLHttpRequest.prototype.setRequestHeader;
          XMLHttpRequest.prototype.open = function(method, url){
            this.__iboxUrl = String(url || '');
            this.__iboxMethod = String(method || 'GET');
            this.__iboxHeaders = {};
            this.__iboxProxy = RE.test(this.__iboxUrl);
            if (this.__iboxProxy) {
              return xo.call(this, method, 'https://h5.ibox.art/__ibox_net_stub__', arguments[2] !== false);
            }
            return xo.apply(this, arguments);
          };
          XMLHttpRequest.prototype.setRequestHeader = function(k, v){
            if (this.__iboxProxy) { this.__iboxHeaders[k] = v; return; }
            return xh.apply(this, arguments);
          };
          XMLHttpRequest.prototype.send = function(body){
            var self = this;
            if (!this.__iboxProxy) return xs.apply(this, arguments);
            bridge(this.__iboxMethod, this.__iboxUrl, this.__iboxHeaders, body).then(function(r){
              applyXhrResult(self, r);
            }).catch(function(){
              try {
                Object.defineProperty(self, 'readyState', { configurable: true, get: function(){ return 4; } });
                Object.defineProperty(self, 'status', { configurable: true, get: function(){ return 0; } });
              } catch (e) {}
              try { if (typeof self.onerror === 'function') self.onerror(); } catch (e1) {}
            });
          };
          if (window.fetch) {
            var ofetch = window.fetch.bind(window);
            window.fetch = function(input, init){
              init = init || {};
              var url = typeof input === 'string' ? input : (input && input.url) || '';
              if (!RE.test(url)) return ofetch(input, init);
              var method = (init.method || 'GET').toUpperCase();
              var headers = {};
              try {
                var h = init.headers;
                if (h && h.forEach) h.forEach(function(v, k){ headers[k] = v; });
                else if (h && typeof h === 'object') {
                  for (var k in h) if (Object.prototype.hasOwnProperty.call(h, k)) headers[k] = h[k];
                }
              } catch (e) {}
              return bridge(method, url, headers, init.body).then(function(r){
                var u8 = new Uint8Array(r.body.length);
                for (var i = 0; i < r.body.length; i++) u8[i] = r.body.charCodeAt(i) & 0xff;
                return new Response(u8, { status: r.status || 200, statusText: 'OK', headers: r.headers || {} });
              });
            };
          }
        })();
        </script>
        """
    }
}

private extension URLSession {
    func syncData(for request: URLRequest) throws -> (Data, URLResponse) {
        var outData: Data?
        var outResp: URLResponse?
        var outErr: Error?
        let sem = DispatchSemaphore(value: 0)
        let task = dataTask(with: request) { data, resp, err in
            outData = data
            outResp = resp
            outErr = err
            sem.signal()
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 50)
        if let outErr { throw outErr }
        guard let outData, let outResp else {
            throw NSError(domain: "h5", code: -1, userInfo: [NSLocalizedDescriptionKey: "empty response"])
        }
        return (outData, outResp)
    }
}
