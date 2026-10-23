// Test-only UIKit app. The proxy invokes the real local Swift HLSPlaylist package.
// Compile in Swift 5 language mode for the AVFoundation callback APIs.
import UIKit
import AVFoundation

final class Keys: NSObject, AVContentKeySessionDelegate {
    let session = AVContentKeySession(keySystem: .fairPlayStreaming)
    var certificates = 0
    var licenses = 0
    var cancellations = 0
    var errors: [String] = []
    private let traceLock = NSLock()
    private var traceEvents: [[String: Any]] = []
    private var preparedCertificate: Data?
    private let started = ProcessInfo.processInfo.systemUptime
    private let label: String
    var trace: [[String: Any]] {
        traceLock.lock()
        defer { traceLock.unlock() }
        return traceEvents
    }
    func event(_ stage: String, _ details: [String: Any] = [:]) {
        let row = details.merging(["stage": stage, "case": label,
                                   "elapsed": ProcessInfo.processInfo.systemUptime - started]) { _, new in new }
        traceLock.lock()
        traceEvents.append(row)
        traceLock.unlock()
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8899/trace")!)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        URLSession.shared.dataTask(with: request).resume()
    }
    func record(_ error: Error?, stage: String) {
        let nsError = error as NSError?
        event(stage + "-error", ["domain": nsError?.domain ?? "", "code": nsError?.code ?? 0,
                                 "description": nsError?.localizedDescription ?? "no error provided"])
        if let error = error as NSError?,
           error.domain == AVFoundationErrorDomain,
           error.code == AVError.Code.contentKeyRequestCancelled.rawValue {
            cancellations += 1
        } else {
            errors.append("\(stage): \(String(describing: error))")
        }
    }
    init(label: String) {
        self.label = label
        super.init()
        session.setDelegate(self, queue: .main)
        event("session-created")
    }
    private var certificateURL: URL {
        let delay = Bundle.main.object(forInfoDictionaryKey: "HLSVerificationCertificateDelay") as? Int ?? 0
        return URL(string: "http://127.0.0.1:8899/drm/cert?delay=\(delay)")!
    }
    func prepareCertificate() async -> Bool {
        event("certificate-prefetch-start")
        do {
            let request = URLRequest(url: certificateURL, timeoutInterval: 90)
            let (data, response) = try await URLSession.shared.data(for: request)
            event("certificate-prefetch-complete", ["http": (response as? HTTPURLResponse)?.statusCode ?? 0,
                                                    "bytes": data.count])
            guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
                throw URLError(.badServerResponse)
            }
            preparedCertificate = data
            certificates += 1
            return true
        } catch {
            await MainActor.run { self.record(error, stage: "certificate-prefetch") }
            return false
        }
    }
    func contentKeySession(_ session: AVContentKeySession, didProvide request: AVContentKeyRequest) {
        event("key-request", ["status": request.status.rawValue,
                              "identifierType": request.identifier.map { String(describing: type(of: $0)) } ?? "nil",
                              "identifierLength": String(describing: request.identifier!).utf8.count])
        if let certificate = preparedCertificate {
            provide(request, certificate: certificate)
            return
        }
        event("certificate-start")
        URLSession.shared.dataTask(with: certificateURL) { data, response, error in
            self.event("certificate-complete", ["http": (response as? HTTPURLResponse)?.statusCode ?? 0,
                                                "bytes": data?.count ?? 0, "requestStatus": request.status.rawValue])
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let certificate = data, !certificate.isEmpty else {
                DispatchQueue.main.async { self.record(error, stage: "certificate") }
                return
            }
            DispatchQueue.main.async { self.certificates += 1 }
            self.provide(request, certificate: certificate)
        }.resume()
    }
    private func provide(_ request: AVContentKeyRequest, certificate: Data) {
        let identifier = String(describing: request.identifier!)
        event("spc-start", ["requestStatus": request.status.rawValue])
        request.makeStreamingContentKeyRequestData(forApp: certificate, contentIdentifier: Data(identifier.utf8), options: nil) { spc, error in
            self.event("spc-complete", ["bytes": spc?.count ?? 0, "requestStatus": request.status.rawValue,
                                       "errorDomain": (error as NSError?)?.domain ?? "",
                                       "errorCode": (error as NSError?)?.code ?? 0])
            guard let spc = spc else {
                DispatchQueue.main.async { self.record(error, stage: "SPC") }
                return
            }
            var req = URLRequest(url: URL(string: "http://127.0.0.1:8899/drm/license")!)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let demo = Data(#"{"merchant":"six","userId":"purchase","sessionId":"session"}"#.utf8).base64EncodedString()
            req.setValue(demo, forHTTPHeaderField: "x-dt-custom-data")
            req.httpBody = Data(("spc=" + spc.base64EncodedString().addingPercentEncoding(withAllowedCharacters: .alphanumerics)!).utf8)
            self.event("license-start")
            URLSession.shared.dataTask(with: req) { data, response, error in
                self.event("license-complete", ["http": (response as? HTTPURLResponse)?.statusCode ?? 0,
                                                "bytes": data?.count ?? 0, "requestStatus": request.status.rawValue])
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let data = data, let text = String(data: data, encoding: .ascii),
                      let ckc = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    DispatchQueue.main.async { self.errors.append("CKC: \(String(describing: response)), \(String(describing: error))") }
                    return
                }
                DispatchQueue.main.async { self.licenses += 1 }
                request.processContentKeyResponse(AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckc))
                self.event("ckc-submitted", ["bytes": ckc.count, "requestStatus": request.status.rawValue])
            }.resume()
        }
    }
    func contentKeySession(_ session: AVContentKeySession, contentKeyRequest request: AVContentKeyRequest, didFailWithError error: Error) {
        record(error, stage: "key")
    }
    func contentKeySession(_ session: AVContentKeySession, contentKeyRequestDidSucceed request: AVContentKeyRequest) {
        event("key-succeeded", ["requestStatus": request.status.rawValue])
    }
}

@main final class App: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var layer = AVPlayerLayer()
    var results: [[String: Any]] = []
    var plannedCases: [String] = []
    var runName = "main"
    let label = UILabel()
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let controller = UIViewController()
        controller.view.backgroundColor = .black
        layer.frame = CGRect(x: 0, y: 80, width: 390, height: 260)
        controller.view.layer.addSublayer(layer)
        label.frame = CGRect(x: 12, y: 360, width: 360, height: 400)
        label.numberOfLines = 0
        label.textColor = .white
        controller.view.addSubview(label)
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = controller
        window?.makeKeyAndVisible()
        UIApplication.shared.isIdleTimerDisabled = true
        Task { @MainActor in await self.run() }
        return true
    }
    @MainActor func delay(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    @MainActor func wait(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            await delay(0.25)
        }
        return condition()
    }
    @MainActor func run() async {
        let origins = [
            "ts": "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8",
            "fmp4": "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8",
            "ll": "https://demo.gvideo.io/cmaf/2675_19146/master.m3u8",
            "fairplay": "https://demo.cf.castlabs.com/media/fps/index.m3u8",
            "tracks": "https://storage.googleapis.com/shaka-demo-assets/angel-one-hls/hls.m3u8",
            "aes": "http://127.0.0.1:8899/fixture/aes.m3u8",
            "range": "http://127.0.0.1:8899/fixture/range.m3u8",
            "live": "http://127.0.0.1:8899/fixture/live.m3u8",
        ]
        var cases: [(String, String)] = []
        for kind in ["ts", "fmp4", "aes", "range", "live", "ll", "fairplay", "tracks"] {
            for candidate in (["ts", "fmp4"].contains(kind) ? ["original", "render", "rewrite"] : ["original", "rewrite"]) {
                cases.append((kind, candidate))
            }
        }
        cases.append(("recovery", "recovery"))
        var selection = Bundle.main.object(forInfoDictionaryKey: "HLSVerificationCases") as? String
        runName = Bundle.main.object(forInfoDictionaryKey: "HLSVerificationRun") as? String ?? "main"
        for argument in ProcessInfo.processInfo.arguments {
            if argument.hasPrefix("--cases=") {
                selection = String(argument.dropFirst("--cases=".count))
            }
            if argument.hasPrefix("--run=") {
                runName = String(argument.dropFirst("--run=".count))
            }
        }
        if let selection = selection {
            let selected = Set(selection.split(separator: ",").map(String.init))
            cases = cases.filter { selected.contains($0.0 + "/" + $0.1) }
        }
        let repetitions = Bundle.main.object(forInfoDictionaryKey: "HLSVerificationRepeat") as? Int ?? 1
        cases = Array(repeating: cases, count: repetitions).flatMap { $0 }
        plannedCases = cases.map { $0.0 + "/" + $0.1 }
        for (index, entry) in cases.enumerated() {
            let (kind, candidate) = entry
            label.text = "\(kind) / \(candidate)\n\(results.count) completed"
            let address: String
            if ["original", "render"].contains(candidate), let origin = origins[kind] {
                if origin.hasPrefix("https://") {
                    address = "http://127.0.0.1:8899/\(candidate == "original" ? "raw" : "render")/https/" +
                        origin.dropFirst("https://".count)
                } else {
                    address = origin
                }
            } else {
                address = "http://127.0.0.1:8899/start/\(kind)/\(candidate)"
            }
            let url = URL(string: address)!
            let asset = AVURLAsset(url: url)
            let keys: Keys? = kind == "fairplay" ? Keys(label: runName + "/\(index)/" + kind + "/" + candidate) : nil
            var row: [String: Any] = ["kind": kind, "candidate": candidate, "url": url.absoluteString, "caseIndex": index]
            if let keys, Bundle.main.object(forInfoDictionaryKey: "HLSVerificationCertificatePrefetch") as? Bool ?? true {
                guard await keys.prepareCertificate() else {
                    row["firstFrame"] = false
                    row["certificates"] = keys.certificates
                    row["licenses"] = keys.licenses
                    row["keyErrors"] = keys.errors
                    row["keyTrace"] = keys.trace
                    results.append(row)
                    await save()
                    continue
                }
            }
            keys?.session.addContentKeyRecipient(asset)
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            layer.player = player
            player.play()
            let ready = await wait(40) { item.status == .failed || self.layer.isReadyForDisplay }
            row["firstFrame"] = ready && layer.isReadyForDisplay && item.status != .failed
            keys?.event("first-frame-wait-complete", ["firstFrame": row["firstFrame"]!, "itemStatus": item.status.rawValue])
            if row["firstFrame"] as? Bool == true {
                let start = player.currentTime().seconds
                let progress = await wait(20) { player.currentTime().seconds > start + 10 }
                row["progress10s"] = progress
                player.pause()
                await delay(0.5)
                let paused = player.currentTime().seconds
                await delay(1)
                row["pause"] = abs(player.currentTime().seconds - paused) < 0.2
                player.play()
                row["resume"] = await wait(10) { player.currentTime().seconds > paused + 1 }
                if !["live", "ll"].contains(kind) {
                    let target = max(0, player.currentTime().seconds - 4)
                    let seekOK = await withCheckedContinuation { continuation in
                        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) {
                            continuation.resume(returning: $0)
                        }
                    }
                    row["seek"] = seekOK && abs(player.currentTime().seconds - target) < 1
                }
                if ["fmp4", "tracks"].contains(kind) {
                    for (name, characteristic) in [("audio", AVMediaCharacteristic.audible), ("subtitle", .legible)] {
                        if let group = asset.mediaSelectionGroup(forMediaCharacteristic: characteristic) {
                            row[name + "Options"] = group.options.map(\.displayName)
                            var selected: [String] = []
                            var matches = true
                            for option in group.options.prefix(2) {
                                item.select(option, in: group)
                                await delay(0.5)
                                matches = matches && item.currentMediaSelection.selectedMediaOption(in: group) == option
                                selected.append(option.displayName)
                            }
                            row[name + "Selection"] = matches
                            row[name + "SelectedOptions"] = selected
                            row[name + "SwitchCovered"] = Set(selected).count >= 2
                        }
                    }
                    let before = player.currentTime().seconds
                    row["afterTrackSwitch"] = await wait(10) { player.currentTime().seconds > before + 1 }
                }
            }
            row["itemStatus"] = item.status.rawValue
            if let error = item.error { row["error"] = String(describing: error) }
            row["errorLogs"] = item.errorLog()?.events.map {
                ["status": $0.errorStatusCode, "domain": $0.errorDomain,
                 "comment": $0.errorComment ?? ""] as [String: Any]
            } ?? []
            if let keys = keys {
                row["certificates"] = keys.certificates
                row["licenses"] = keys.licenses
                row["keyCancellations"] = keys.cancellations
                row["keyErrors"] = keys.errors
                row["keyTrace"] = keys.trace
                keys.event("removing-recipient")
                keys.session.removeContentKeyRecipient(asset)
            }
            row["accessLogs"] = item.accessLog()?.events.map {
                ["stalls": $0.numberOfStalls, "segments": $0.numberOfMediaRequests, "bytes": $0.numberOfBytesTransferred] as [String: Any]
            } ?? []
            player.pause()
            player.replaceCurrentItem(with: nil)
            layer.player = nil
            results.append(row)
            await save()
            await delay(0.5)
        }
        label.text = "Done: \(results.count) cases\nResults sent to Mac"
        UIApplication.shared.isIdleTimerDisabled = false
    }
    @MainActor func save() async {
        #if targetEnvironment(simulator)
        let simulated = true
        #else
        let simulated = false
        #endif
        let data = try! JSONSerialization.data(withJSONObject: ["device": UIDevice.current.model,
                                                              "os": UIDevice.current.systemVersion,
                                                              "simulator": simulated,
                                                              "run": runName,
                                                              "plannedCases": plannedCases,
                                                              "complete": results.count == plannedCases.count,
                                                              "results": results], options: [.sortedKeys, .prettyPrinted])
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8899/done")!)
        request.httpMethod = "POST"
        request.httpBody = data
        _ = try? await URLSession.shared.data(for: request)
    }
}
