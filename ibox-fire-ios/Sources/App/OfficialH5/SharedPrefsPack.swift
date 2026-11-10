import Foundation

/// 对齐 Android SharedPrefsPack：localStorage `flutter.<key>` = Dart jsonEncode(value)
struct SharedPrefsPack {
    let encodedEntries: [String: String]
    let cookieToken: String
    let cookieExpiredAt: String

    static let h5Origin = "https://h5.ibox.art"
    static let h5Boot = "https://h5.ibox.art/"
    static let h5Launcher = "https://h5.ibox.art/#/launcher"

    /// 插入 &lt;head&gt;：禁 SW + 写票
    func toBootHeadScript() -> String {
        let body = toSyncInjectJs()
        return """
        <script>
        (function(){
          try{
            if(navigator.serviceWorker){
              navigator.serviceWorker.register=function(){
                return Promise.reject(new Error('ibox-fire: sw disabled'));
              };
            }
          }catch(e){}
          try{ \(body); }catch(e){}
        })();
        </script>
        """
    }

    func toSyncInjectJs() -> String {
        let mapLit = Self.jsStringLiteral(encodedEntries.jsonObjectString)
        let tokLit = Self.jsStringLiteral(cookieToken)
        let expLit = Self.jsStringLiteral(cookieExpiredAt)
        return """
        (function(){
          try {
            var enc = JSON.parse(\(mapLit));
            var PREFIX = 'flutter.';
            var del = [];
            for (var i = 0; i < localStorage.length; i++) {
              var k = localStorage.key(i);
              if (!k) continue;
              if (k.indexOf(PREFIX) === 0 || k.indexOf('FlutterSecureStorage') === 0) del.push(k);
            }
            for (var j = 0; j < del.length; j++) localStorage.removeItem(del[j]);
            var n = 0;
            for (var name in enc) {
              if (!Object.prototype.hasOwnProperty.call(enc, name)) continue;
              localStorage.setItem(PREFIX + name, enc[name]);
              n++;
            }
            if (!localStorage.getItem(PREFIX + 'access_token') || !localStorage.getItem(PREFIX + 'user_info')) {
              return 'error:missing';
            }
            var tok = \(tokLit);
            var exp = \(expLit);
            try {
              var base = '; path=/; domain=.ibox.art; Secure; SameSite=Lax';
              document.cookie = 'token=' + encodeURIComponent(tok) + base;
              if (exp) document.cookie = 'expiredAt=' + encodeURIComponent(exp) + base;
            } catch (ce) {}
            return 'ok:' + n;
          } catch (e) {
            return 'error:' + (e && e.message ? e.message : String(e));
          }
        })()
        """
    }

    static func build(
        accessToken: String,
        refreshToken: String,
        deviceId: String,
        uid: Int64,
        expMs: Int64
    ) -> SharedPrefsPack {
        var map: [String: String] = [:]
        map["access_token"] = encString(accessToken)
        if !refreshToken.isEmpty { map["refresh_token"] = encString(refreshToken) }
        let did = deviceId.isEmpty ? IboxClient.makeDeviceId(accessToken) : deviceId
        map["device_id"] = encString(did)
        if uid > 0 { map["user_id"] = encInt(uid) }
        if expMs > 0 { map["ibTokenExpiredAt"] = encInt(expMs) }
        let sso = JwtUtil.claimString(accessToken, "ssoUserId", "sub")
        let mobile = JwtUtil.claimString(accessToken, "preferred_username", "phone", "mobile")
        let wallet = JwtUtil.claimString(accessToken, "walletAddress", "wallet")
        if !sso.isEmpty { map["ssoUserId"] = encString(sso) }
        map["login_type"] = encInt(1)

        let info: [String: Any] = [
            "userId": uid,
            "walletAddress": wallet,
            "userName": mobile.isEmpty ? (uid > 0 ? "u\(uid)" : "ibox") : mobile,
            "avatar": "",
            "mobile": mobile,
            "ssoUserId": sso,
            "rwaQualityInspector": false,
        ]
        let infoData = (try? JSONSerialization.data(withJSONObject: info)) ?? Data()
        let infoStr = String(data: infoData, encoding: .utf8) ?? "{}"
        map["user_info"] = encString(infoStr)

        return SharedPrefsPack(
            encodedEntries: map,
            cookieToken: accessToken,
            cookieExpiredAt: expMs > 0 ? String(expMs) : ""
        )
    }

    /// Dart jsonEncode(String) → 带引号的 JSON 字符串字面量
    private static func encString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed])
        return String(data: data ?? Data("\"\"".utf8), encoding: .utf8) ?? "\"\""
    }

    private static func encInt(_ n: Int64) -> String { String(n) }

    private static func jsStringLiteral(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed])
        return String(data: data ?? Data("\"\"".utf8), encoding: .utf8) ?? "\"\""
    }
}

private extension Dictionary where Key == String, Value == String {
    var jsonObjectString: String {
        let data = (try? JSONSerialization.data(withJSONObject: self)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
