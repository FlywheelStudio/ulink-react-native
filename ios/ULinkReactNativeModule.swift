// ULinkReactNativeModule.swift
// Expo Module that wraps the ULink iOS SDK (ULinkSDK ~> 1.1.1).
//
// Design rules (from global-constraints.md):
//   - Module name: "ULinkReactNative"
//   - initialize() is async and idempotent; all calls queue until it resolves.
//   - Never wire dispose() to JS unmount / fast-refresh.
//   - Resolved cold-start/warm links reach JS via onDynamicLink / onUnifiedLink events,
//     not getInitialDeepLink().  Link delivery (AppDelegate forwarding) is Task 6.
//   - enableDeepLinkIntegration is always false on iOS (parseConfig enforces this).
//   - Client identity stays native sdk-ios — no SDK override needed.

import ExpoModulesCore
import ULinkSDK
import Combine

public class ULinkReactNativeModule: Module {

    // MARK: - State

    private var ulink: ULink?
    private var cancellables = Set<AnyCancellable>()
    private let queue = ULinkPendingQueue()
    private var initTask: Task<Void, Error>? = nil

    // MARK: - Module definition

    public func definition() -> ModuleDefinition {
        Name("ULinkReactNative")

        // ── Events ──────────────────────────────────────────────────────────
        Events("onDynamicLink", "onUnifiedLink", "onReinstallDetected", "onLog")

        // ── initialize ──────────────────────────────────────────────────────
        AsyncFunction("initialize") { (configMap: [String: Any], promise: Promise) in
            // If already initialised, resolve immediately (idempotent).
            if self.ulink != nil {
                promise.resolve()
                return
            }
            // If a concurrent init is in flight, queue behind it.
            if self.initTask != nil {
                let call = PendingCall.initialize(
                    config: configMap,
                    resolve: { promise.resolve() },
                    reject:  { code, msg, _ in promise.reject(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
                return
            }

            self.initTask = Task {
                do {
                    let config = try parseConfig(configMap)
                    let sdk = try await ULink.initialize(config: config)
                    self.ulink = sdk
                    self.subscribeStreams(sdk)
                    // Drain the method-call queue first so SDK event subscriptions
                    // are live before any buffered link is processed.
                    await self.queue.markReady(sdk, module: self)
                    // Drain any URLs buffered by the AppDelegate subscriber before
                    // this initialize() call completed (cold-start universal links,
                    // custom-scheme URLs).  processULinkUrl() emits on the Combine
                    // streams already wired above, so events reach JS correctly.
                    await ULinkIncomingLinkBuffer.shared.drain(sdk: sdk)
                    self.initTask = nil   // fix #6: clear task handle after successful init
                    promise.resolve()
                } catch {
                    self.initTask = nil
                    promise.reject("INITIALIZATION_ERROR", error.localizedDescription)
                }
            }
        }

        // ── createLink ──────────────────────────────────────────────────────
        AsyncFunction("createLink") { (paramsMap: [String: Any], promise: Promise) in
            if let sdk = self.ulink {
                Task {
                    do {
                        let p = try parseParameters(paramsMap)
                        let resp = try await sdk.createLink(parameters: p)
                        promise.resolve(responseToMap(resp))
                    } catch {
                        promise.reject("CREATE_LINK_ERROR", error.localizedDescription)
                    }
                }
            } else {
                let call = PendingCall.createLink(
                    params:  paramsMap,
                    resolve: { promise.resolve($0) },
                    reject:  { code, msg, _ in promise.reject(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
            }
        }

        // ── resolveLink ──────────────────────────────────────────────────────
        AsyncFunction("resolveLink") { (url: String, promise: Promise) in
            if let sdk = self.ulink {
                Task {
                    do {
                        let resp = try await sdk.resolveLink(url: url)
                        promise.resolve(responseToMap(resp))
                    } catch {
                        promise.reject("RESOLVE_LINK_ERROR", error.localizedDescription)
                    }
                }
            } else {
                let call = PendingCall.resolveLink(
                    url:     url,
                    resolve: { promise.resolve($0) },
                    reject:  { code, msg, _ in promise.reject(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
            }
        }

        // ── processULink ─────────────────────────────────────────────────────
        AsyncFunction("processULink") { (url: String, promise: Promise) in
            if let sdk = self.ulink {
                Task {
                    guard let linkUrl = URL(string: url) else {
                        promise.reject("INVALID_URL", "Invalid URL: \(url)")
                        return
                    }
                    do {
                        let data = try await sdk.processULinkUrlThrowing(linkUrl)
                        if let data = data {
                            promise.resolve(resolvedDataToMap(data))
                        } else {
                            promise.resolve(nil as [String: Any?]?)
                        }
                    } catch {
                        promise.reject("PROCESS_ULINK_ERROR", error.localizedDescription)
                    }
                }
            } else {
                let call = PendingCall.processULink(
                    url:     url,
                    resolve: { promise.resolve($0) },
                    reject:  { code, msg, _ in promise.reject(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
            }
        }

        // ── checkDeferredLink ────────────────────────────────────────────────
        AsyncFunction("checkDeferredLink") { (promise: Promise) in
            if let sdk = self.ulink {
                Task {
                    do {
                        try await sdk.checkDeferredLinkAsync()
                        promise.resolve()
                    } catch {
                        promise.reject("DEFERRED_LINK_ERROR", error.localizedDescription)
                    }
                }
            } else {
                let call = PendingCall.checkDeferredLink(
                    resolve: { promise.resolve() },
                    reject:  { code, msg, _ in promise.reject(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
            }
        }

        // ── getInitialDeepLink ───────────────────────────────────────────────
        AsyncFunction("getInitialDeepLink") { (promise: Promise) in
            if let sdk = self.ulink {
                Task {
                    let data = await sdk.getInitialDeepLink()
                    if let data = data {
                        promise.resolve(resolvedDataToMap(data))
                    } else {
                        promise.resolve(nil as [String: Any?]?)
                    }
                }
            } else {
                let call = PendingCall.getInitialDeepLink(
                    resolve: { promise.resolve($0) },
                    reject:  { code, msg, _ in promise.reject(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
            }
        }

        // ── getInitialUri ─────────────────────────────────────────────────────
        AsyncFunction("getInitialUri") { (promise: Promise) in
            if let sdk = self.ulink {
                promise.resolve(sdk.getInitialUrl()?.absoluteString)
            } else {
                let call = PendingCall.getInitialUri(
                    resolve: { promise.resolve($0) },
                    reject:  { code, msg, _ in promise.reject(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
            }
        }

        // ── setInitialUri ─────────────────────────────────────────────────────
        AsyncFunction("setInitialUri") { (uri: String, promise: Promise) in
            if let sdk = self.ulink {
                if let url = URL(string: uri) {
                    sdk.setInitialUrl(url)
                    promise.resolve()
                } else {
                    promise.reject("INVALID_URL", "Invalid URI: \(uri)")
                }
            } else {
                let call = PendingCall.setInitialUri(
                    uri:     uri,
                    resolve: { promise.resolve() },
                    reject:  { code, msg, _ in promise.reject(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
            }
        }

        // ── getLastLinkData ───────────────────────────────────────────────────
        AsyncFunction("getLastLinkData") { (promise: Promise) in
            if let sdk = self.ulink {
                let data = sdk.getLastLinkData()
                if let data = data {
                    promise.resolve(resolvedDataToMap(data))
                } else {
                    promise.resolve(nil as [String: Any?]?)
                }
            } else {
                let call = PendingCall.getLastLinkData(
                    resolve: { promise.resolve($0) },
                    reject:  { code, msg, _ in promise.reject(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
            }
        }

        // ── getInstallationId ─────────────────────────────────────────────────
        AsyncFunction("getInstallationId") { (promise: Promise) in
            if let sdk = self.ulink {
                promise.resolve(sdk.getInstallationId())
            } else {
                let call = PendingCall.getInstallationId(
                    resolve: { promise.resolve($0) },
                    reject:  { code, msg, _ in promise.reject(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
            }
        }

        // ── getInstallationInfo ───────────────────────────────────────────────
        AsyncFunction("getInstallationInfo") { (promise: Promise) in
            if let sdk = self.ulink {
                if let info = sdk.getInstallationInfo() {
                    promise.resolve(installationInfoToMap(info))
                } else {
                    promise.resolve(nil as [String: Any?]?)
                }
            } else {
                let call = PendingCall.getInstallationInfo(
                    resolve: { promise.resolve($0) },
                    reject:  { code, msg, _ in promise.reject(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
            }
        }

        // ── isReinstall ───────────────────────────────────────────────────────
        AsyncFunction("isReinstall") { (promise: Promise) in
            if let sdk = self.ulink {
                promise.resolve(sdk.isReinstall())
            } else {
                let call = PendingCall.isReinstall(
                    resolve: { promise.resolve($0) },
                    reject:  { code, msg, _ in promise.reject(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
            }
        }

        // ── getCurrentSessionId ───────────────────────────────────────────────
        AsyncFunction("getCurrentSessionId") { (promise: Promise) in
            if let sdk = self.ulink {
                promise.resolve(sdk.getCurrentSessionId())
            } else {
                let call = PendingCall.getCurrentSessionId(
                    resolve: { promise.resolve($0) },
                    reject:  { code, msg, _ in promise.reject(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
            }
        }

        // ── hasActiveSession ──────────────────────────────────────────────────
        AsyncFunction("hasActiveSession") { (promise: Promise) in
            if let sdk = self.ulink {
                promise.resolve(sdk.hasActiveSession())
            } else {
                let call = PendingCall.hasActiveSession(
                    resolve: { promise.resolve($0) },
                    reject:  { code, msg, _ in promise.reject(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
            }
        }

        // ── getSessionState ───────────────────────────────────────────────────
        AsyncFunction("getSessionState") { (promise: Promise) in
            if let sdk = self.ulink {
                promise.resolve(sessionStateString(sdk.getSessionState()))
            } else {
                let call = PendingCall.getSessionState(
                    resolve: { promise.resolve($0) },
                    reject:  { code, msg, _ in promise.reject(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
            }
        }

        // ── endSession ────────────────────────────────────────────────────────
        AsyncFunction("endSession") { (promise: Promise) in
            if let sdk = self.ulink {
                Task {
                    _ = await sdk.endSession()
                    promise.resolve()
                }
            } else {
                let call = PendingCall.endSession(
                    resolve: { promise.resolve() },
                    reject:  { code, msg, _ in promise.reject(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
            }
        }

        // ── dispose ───────────────────────────────────────────────────────────
        // Advanced teardown only — do NOT call on component unmount.
        AsyncFunction("dispose") { (promise: Promise) in
            if let sdk = self.ulink {
                sdk.dispose()
                self.didDispose()
                promise.resolve()
            } else {
                let call = PendingCall.dispose(
                    resolve: { promise.resolve() },
                    reject:  { code, msg, _ in promise.reject(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
            }
        }
    }

    // MARK: - Dispose state reset

    /// Resets all module-owned state after sdk.dispose() completes.
    /// Called from BOTH the direct dispose path and the queued dispose execution
    /// so a dispose-before-init can't leave stale state that collides with a
    /// later successful initialize().
    /// Internal (not private) so ULinkBridge.swift's queued .dispose execution can call it.
    func didDispose() {
        self.ulink = nil
        self.cancellables.removeAll()
        self.initTask = nil
    }

    // MARK: - Combine stream subscriptions

    private func subscribeStreams(_ sdk: ULink) {
        // Dynamic-link stream → onDynamicLink event
        sdk.dynamicLinkStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.sendEvent("onDynamicLink", resolvedDataToMap(data))
            }
            .store(in: &cancellables)

        // Unified-link stream → onUnifiedLink event
        sdk.unifiedLinkStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.sendEvent("onUnifiedLink", resolvedDataToMap(data))
            }
            .store(in: &cancellables)

        // Reinstall detection → onReinstallDetected event
        sdk.onReinstallDetected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                self?.sendEvent("onReinstallDetected", installationInfoToMap(info))
            }
            .store(in: &cancellables)

        // Log stream → onLog event
        sdk.logStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entry in
                self?.sendEvent("onLog", [
                    "level":     entry.level,
                    "tag":       entry.tag,
                    "message":   entry.message,
                    "timestamp": entry.timestamp,
                ])
            }
            .store(in: &cancellables)
    }
}
