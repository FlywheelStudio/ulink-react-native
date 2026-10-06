// ULinkReactNativeModule.swift
// Expo Module that wraps the ULink iOS SDK (ULinkSDK ~> 1.2.3).
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

        // ── Listener gate for cold-start buffer ─────────────────────────────
        // Fires when the FIRST JS listener attaches to any event on this module.
        // At this point it is safe to flush buffered cold-start links because JS
        // has called addListener, which means the onDynamicLink/onUnifiedLink
        // callbacks are registered.
        OnStartObserving {
            Task { await ULinkIncomingLinkBuffer.shared.setObserving() }
        }

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
                    reject:  { code, msg, _ in promise.rejectWithMessage(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
                return
            }

            self.initTask = Task {
                await self.queue.clearFailure()
                do {
                    let config = try parseConfig(configMap)
                    let sdk: ULink
                    do {
                        sdk = try await ULink.initialize(config: config)
                    } catch where ULink.isInitialized {
                        // The native iOS SDK throws when bootstrap fails (non-2xx
                        // such as a 503 under load shedding or a 403 at the plan's
                        // MAU cap, or no network), but the instance exists and
                        // retries bootstrap on the next foreground and before any
                        // link resolution or API call, as the Android SDK does. Continue in
                        // that degraded state so the app is not blocked and
                        // queued calls and links are not parked forever.
                        NSLog("[ULink] Initialization degraded, bootstrap will be retried: %@", error.localizedDescription)
                        sdk = ULink.shared
                    }
                    self.ulink = sdk
                    self.subscribeStreams(sdk)
                    // Drain the method-call queue first so SDK event subscriptions
                    // are live before any buffered link is processed.
                    await self.queue.markReady(sdk, module: self)
                    // Mark the buffer as SDK-ready.  Buffered cold-start URLs are
                    // flushed via handleDeepLinkAsync (emits on Combine streams) once
                    // BOTH this gate AND the JS-listener gate (setObserving) are open.
                    await ULinkIncomingLinkBuffer.shared.setReady(sdk)
                    self.initTask = nil   // fix #6: clear task handle after successful init
                    promise.resolve()
                } catch {
                    // Reject queued calls before clearing initTask. A new
                    // initialize() starts only once initTask is nil; its
                    // clearFailure() must not run ahead of this markFailed().
                    await self.queue.markFailed(code: "INITIALIZATION_ERROR", message: error.localizedDescription)
                    self.initTask = nil
                    promise.rejectWithMessage("INITIALIZATION_ERROR", error.localizedDescription)
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
                        promise.rejectWithMessage("CREATE_LINK_ERROR", error.localizedDescription)
                    }
                }
            } else {
                let call = PendingCall.createLink(
                    params:  paramsMap,
                    resolve: { promise.resolve($0) },
                    reject:  { code, msg, _ in promise.rejectWithMessage(code, msg) }
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
                        promise.rejectWithMessage("RESOLVE_LINK_ERROR", error.localizedDescription)
                    }
                }
            } else {
                let call = PendingCall.resolveLink(
                    url:     url,
                    resolve: { promise.resolve($0) },
                    reject:  { code, msg, _ in promise.rejectWithMessage(code, msg) }
                )
                Task { await self.queue.enqueue(call, module: self) }
            }
        }

        // ── processULink ─────────────────────────────────────────────────────
        AsyncFunction("processULink") { (url: String, promise: Promise) in
            if let sdk = self.ulink {
                Task {
                    guard let linkUrl = URL(string: url) else {
                        promise.rejectWithMessage("INVALID_URL", "Invalid URL: \(url)")
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
                        promise.rejectWithMessage("PROCESS_ULINK_ERROR", error.localizedDescription)
                    }
                }
            } else {
                let call = PendingCall.processULink(
                    url:     url,
                    resolve: { promise.resolve($0) },
                    reject:  { code, msg, _ in promise.rejectWithMessage(code, msg) }
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
                        promise.rejectWithMessage("DEFERRED_LINK_ERROR", error.localizedDescription)
                    }
                }
            } else {
                let call = PendingCall.checkDeferredLink(
                    resolve: { promise.resolve() },
                    reject:  { code, msg, _ in promise.rejectWithMessage(code, msg) }
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
                    reject:  { code, msg, _ in promise.rejectWithMessage(code, msg) }
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
                    reject:  { code, msg, _ in promise.rejectWithMessage(code, msg) }
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
                    promise.rejectWithMessage("INVALID_URL", "Invalid URI: \(uri)")
                }
            } else {
                let call = PendingCall.setInitialUri(
                    uri:     uri,
                    resolve: { promise.resolve() },
                    reject:  { code, msg, _ in promise.rejectWithMessage(code, msg) }
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
                    reject:  { code, msg, _ in promise.rejectWithMessage(code, msg) }
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
                    reject:  { code, msg, _ in promise.rejectWithMessage(code, msg) }
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
                    reject:  { code, msg, _ in promise.rejectWithMessage(code, msg) }
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
                    reject:  { code, msg, _ in promise.rejectWithMessage(code, msg) }
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
                    reject:  { code, msg, _ in promise.rejectWithMessage(code, msg) }
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
                    reject:  { code, msg, _ in promise.rejectWithMessage(code, msg) }
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
                    reject:  { code, msg, _ in promise.rejectWithMessage(code, msg) }
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
                    reject:  { code, msg, _ in promise.rejectWithMessage(code, msg) }
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
                    reject:  { code, msg, _ in promise.rejectWithMessage(code, msg) }
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
        // Reset the link buffer so stale SDK reference can't be used after dispose.
        Task { await ULinkIncomingLinkBuffer.shared.reset() }
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

// MARK: - Rejections

/// Expo builds the JS error message from `Exception.reason`, but
/// `Promise.reject(_:_:)` only sets `description`, so every rejection reached
/// JS as "undefined reason". This exception reports its message as the reason.
final class ULinkRejection: Exception, @unchecked Sendable {
    private let message: String

    init(code: String, message: String) {
        self.message = message
        super.init(name: code, description: message, code: code)
    }

    override var reason: String {
        message
    }
}

extension Promise {
    func rejectWithMessage(_ code: String, _ message: String) {
        reject(ULinkRejection(code: code, message: message))
    }
}
