// ULinkBridge.swift
// Helper types and the ULinkPendingQueue used by ULinkReactNativeModule.
//
// ULinkPendingQueue:
//   - Queues all JS-originated calls that arrive before initialize() resolves.
//   - markReady() drains the queue on the actor's executor (serialised, no races).
//   - Every pending item carries a typed continuation so the original Promise
//     settles correctly once the SDK is up.
//
// Note: link-delivery (AppDelegate universal-link / URL-scheme forwarding) is
// handled by a separate Expo AppDelegate subscriber (Task 6).  This file only
// owns the method/event surface.

import Foundation
import ULinkSDK
import Combine

// ---------------------------------------------------------------------------
// MARK: - SessionState → string
// ---------------------------------------------------------------------------

func sessionStateString(_ state: SessionState) -> String {
    switch state {
    case .idle:         return "idle"
    case .initializing: return "initializing"
    case .active:       return "active"
    case .ending:       return "ending"
    case .failed:       return "failed"
    }
}

// ---------------------------------------------------------------------------
// MARK: - Serialisation helpers
// ---------------------------------------------------------------------------

/// ULinkResolvedData → JS-safe [String: Any?]
func resolvedDataToMap(_ data: ULinkResolvedData) -> [String: Any?] {
    var socialMediaTagsMap: [String: Any?]? = nil
    if let tags = data.socialMediaTags {
        socialMediaTagsMap = [
            "ogTitle":       tags.ogTitle,
            "ogDescription": tags.ogDescription,
            "ogImage":       tags.ogImage,
        ]
    }

    return [
        "slug":                 data.slug,
        "iosFallbackUrl":       data.iosFallbackUrl,
        "androidFallbackUrl":   data.androidFallbackUrl,
        "fallbackUrl":          data.fallbackUrl,
        "parameters":           data.parameters,
        "socialMediaTags":      socialMediaTagsMap,
        "metadata":             data.metadata,
        "rawData":              data.rawData,
        "type":                 data.type,
        "isDeferred":           data.isDeferred,
        "matchType":            data.matchType,
        "resolvedAt":           data.resolvedAt.map { $0.timeIntervalSince1970 },
    ]
}

/// ULinkResponse → JS-safe [String: Any?]
func responseToMap(_ resp: ULinkResponse) -> [String: Any?] {
    return [
        "success": resp.success,
        "url":     resp.url,
        "error":   resp.error,
        "data":    resp.data,
    ]
}

/// ULinkInstallationInfo (struct, not class) → JS-safe [String: Any?]
func installationInfoToMap(_ info: ULinkInstallationInfo) -> [String: Any?] {
    return [
        "installationId":        info.installationId,
        "isReinstall":           info.isReinstall,
        "previousInstallationId": info.previousInstallationId,
        "reinstallDetectedAt":   info.reinstallDetectedAt,
        "persistentDeviceId":    info.persistentDeviceId,
    ]
}

/// Parses a JS config dict into ULinkConfig.
/// enableDeepLinkIntegration is always forced to false; link delivery is Task 6.
func parseConfig(_ map: [String: Any]) throws -> ULinkConfig {
    guard let apiKey = map["apiKey"] as? String, !apiKey.isEmpty else {
        throw NSError(
            domain: "ULinkReactNative",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "apiKey is required"]
        )
    }
    let baseUrl               = map["baseUrl"] as? String ?? "https://api.ulink.ly"
    let debug                 = map["debug"] as? Bool ?? false
    let persistLastLinkData   = map["persistLastLinkData"] as? Bool ?? false
    var lastLinkTTL: TimeInterval? = nil
    if let ms = map["lastLinkTimeToLiveSeconds"] as? Double {
        lastLinkTTL = ms          // JS passes seconds (see types.ts field name)
    }
    let clearLastLinkOnRead               = map["clearLastLinkOnRead"] as? Bool ?? false
    let redactAll                         = map["redactAllParametersInLastLink"] as? Bool ?? false
    let redactedKeys: [String]            = map["redactedParameterKeysInLastLink"] as? [String] ?? []
    let autoCheckDeferredLink             = map["autoCheckDeferredLink"] as? Bool ?? true

    return ULinkConfig(
        apiKey: apiKey,
        baseUrl: baseUrl,
        debug: debug,
        enableDeepLinkIntegration: false,   // module owns link delivery (Task 6)
        persistLastLinkData: persistLastLinkData,
        lastLinkTimeToLive: lastLinkTTL,
        clearLastLinkOnRead: clearLastLinkOnRead,
        redactAllParametersInLastLink: redactAll,
        redactedParameterKeysInLastLink: redactedKeys,
        autoCheckDeferredLink: autoCheckDeferredLink
    )
}

/// Parses a JS parameters dict into ULinkParameters.
func parseParameters(_ map: [String: Any]) throws -> ULinkParameters {
    guard let domain = map["domain"] as? String, !domain.isEmpty else {
        throw NSError(
            domain: "ULinkReactNative",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "domain is required"]
        )
    }
    let type                 = map["type"] as? String ?? "dynamic"
    let slug                 = map["slug"] as? String
    let name                 = map["name"] as? String
    let iosFallbackUrl       = map["iosFallbackUrl"] as? String
    let androidFallbackUrl   = map["androidFallbackUrl"] as? String
    let fallbackUrl          = map["fallbackUrl"] as? String
    let iosUrl               = map["iosUrl"] as? String
    let androidUrl           = map["androidUrl"] as? String
    let parameters           = map["parameters"] as? [String: Any]
    let metadata             = map["metadata"] as? [String: Any]
    let externalId           = map["externalId"] as? String

    var socialTags: SocialMediaTags? = nil
    if let socialMap = map["socialMediaTags"] as? [String: Any] {
        socialTags = SocialMediaTags(
            ogTitle:       socialMap["ogTitle"] as? String,
            ogDescription: socialMap["ogDescription"] as? String,
            ogImage:       socialMap["ogImage"] as? String
        )
    }

    if type == "unified" {
        return ULinkParameters.unified(
            domain:         domain,
            slug:           slug,
            name:           name,
            iosUrl:         iosUrl ?? "",
            androidUrl:     androidUrl ?? "",
            fallbackUrl:    fallbackUrl ?? "",
            parameters:     parameters,
            socialMediaTags: socialTags,
            metadata:       metadata,
            externalId:     externalId
        )
    } else {
        return ULinkParameters.dynamic(
            domain:              domain,
            slug:                slug,
            name:                name,
            iosFallbackUrl:      iosFallbackUrl,
            androidFallbackUrl:  androidFallbackUrl,
            fallbackUrl:         fallbackUrl,
            parameters:          parameters,
            socialMediaTags:     socialTags,
            metadata:            metadata,
            externalId:          externalId
        )
    }
}

// ---------------------------------------------------------------------------
// MARK: - Pending-call infrastructure
// ---------------------------------------------------------------------------

/// A single queued call waiting for initialisation.
/// Each case captures a typed continuation so the original Promise is resolved
/// (or rejected) after markReady() drains the queue.
enum PendingCall {
    case initialize(
        config: [String: Any],
        resolve: (Void) -> Void,
        reject:  (String, String, Error?) -> Void
    )
    case createLink(
        params: [String: Any],
        resolve: ([String: Any?]) -> Void,
        reject:  (String, String, Error?) -> Void
    )
    case resolveLink(
        url: String,
        resolve: ([String: Any?]) -> Void,
        reject:  (String, String, Error?) -> Void
    )
    case processULink(
        url: String,
        resolve: ([String: Any?]?) -> Void,
        reject:  (String, String, Error?) -> Void
    )
    case checkDeferredLink(
        resolve: (Void) -> Void,
        reject:  (String, String, Error?) -> Void
    )
    case getInitialDeepLink(
        resolve: ([String: Any?]?) -> Void,
        reject:  (String, String, Error?) -> Void
    )
    case getInitialUri(
        resolve: (String?) -> Void,
        reject:  (String, String, Error?) -> Void
    )
    case setInitialUri(
        uri: String,
        resolve: (Void) -> Void,
        reject:  (String, String, Error?) -> Void
    )
    case getLastLinkData(
        resolve: ([String: Any?]?) -> Void,
        reject:  (String, String, Error?) -> Void
    )
    case getInstallationId(
        resolve: (String?) -> Void,
        reject:  (String, String, Error?) -> Void
    )
    case getInstallationInfo(
        resolve: ([String: Any?]?) -> Void,
        reject:  (String, String, Error?) -> Void
    )
    case isReinstall(
        resolve: (Bool) -> Void,
        reject:  (String, String, Error?) -> Void
    )
    case getCurrentSessionId(
        resolve: (String?) -> Void,
        reject:  (String, String, Error?) -> Void
    )
    case hasActiveSession(
        resolve: (Bool) -> Void,
        reject:  (String, String, Error?) -> Void
    )
    case getSessionState(
        resolve: (String) -> Void,
        reject:  (String, String, Error?) -> Void
    )
    case endSession(
        resolve: (Void) -> Void,
        reject:  (String, String, Error?) -> Void
    )
    case dispose(
        resolve: (Void) -> Void,
        reject:  (String, String, Error?) -> Void
    )
}

// ---------------------------------------------------------------------------
// MARK: - ULinkPendingQueue actor
// ---------------------------------------------------------------------------

/// Thread-safe queue that buffers JS calls arriving before `initialize()` resolves.
///
/// Usage pattern:
///   1. Module methods call `queue.enqueue(.someCase(...))` when the SDK is not yet ready.
///   2. After `ULink.initialize(config:)` succeeds the module calls `queue.markReady(ulink:)`.
///   3. `markReady` drains the queue, executing each pending call against the live SDK.
actor ULinkPendingQueue {

    private var pending: [PendingCall] = []
    private var ready = false
    private var ulink: ULink? = nil

    /// Called by the module after `ULink.initialize(config:)` returns successfully.
    func markReady(_ sdk: ULink, module: ULinkReactNativeModule) async {
        self.ulink = sdk
        self.ready = true
        let calls = pending
        pending.removeAll()
        for call in calls {
            await execute(call, module: module)
        }
    }

    /// Enqueue a call.  If already ready, execute immediately (no queue).
    func enqueue(_ call: PendingCall, module: ULinkReactNativeModule) async {
        if ready, let sdk = ulink {
            await execute(call, module: module)
        } else {
            pending.append(call)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func execute(_ call: PendingCall, module: ULinkReactNativeModule) async {
        guard let sdk = ulink else { return }

        switch call {

        case .initialize(_, let resolve, _):
            // Already initialised — idempotent, resolve immediately.
            resolve(())

        case .createLink(let params, let resolve, let reject):
            do {
                let p = try parseParameters(params)
                let resp = try await sdk.createLink(parameters: p)
                resolve(responseToMap(resp) as [String: Any?])
            } catch {
                reject("CREATE_LINK_ERROR", error.localizedDescription, error)
            }

        case .resolveLink(let url, let resolve, let reject):
            do {
                let resp = try await sdk.resolveLink(url: url)
                resolve(responseToMap(resp) as [String: Any?])
            } catch {
                reject("RESOLVE_LINK_ERROR", error.localizedDescription, error)
            }

        case .processULink(let url, let resolve, let reject):
            guard let linkUrl = URL(string: url) else {
                reject("INVALID_URL", "Invalid URL: \(url)", nil)
                return
            }
            do {
                let data = try await sdk.processULinkUrlThrowing(linkUrl)
                resolve(data.map { resolvedDataToMap($0) as [String: Any?] })
            } catch {
                reject("PROCESS_ULINK_ERROR", error.localizedDescription, error)
            }

        case .checkDeferredLink(let resolve, let reject):
            do {
                try await sdk.checkDeferredLinkAsync()
                resolve(())
            } catch {
                reject("DEFERRED_LINK_ERROR", error.localizedDescription, error)
            }

        case .getInitialDeepLink(let resolve, _):
            let data = await sdk.getInitialDeepLink()
            resolve(data.map { resolvedDataToMap($0) as [String: Any?] })

        case .getInitialUri(let resolve, _):
            resolve(sdk.getInitialUrl()?.absoluteString)

        case .setInitialUri(let uri, let resolve, let reject):
            guard let url = URL(string: uri) else {
                reject("INVALID_URL", "Invalid URI: \(uri)", nil)
                return
            }
            sdk.setInitialUrl(url)
            resolve(())

        case .getLastLinkData(let resolve, _):
            let data = sdk.getLastLinkData()
            resolve(data.map { resolvedDataToMap($0) as [String: Any?] })

        case .getInstallationId(let resolve, _):
            resolve(sdk.getInstallationId())

        case .getInstallationInfo(let resolve, _):
            let info = sdk.getInstallationInfo()
            resolve(info.map { installationInfoToMap($0) as [String: Any?] })

        case .isReinstall(let resolve, _):
            resolve(sdk.isReinstall())

        case .getCurrentSessionId(let resolve, _):
            resolve(sdk.getCurrentSessionId())

        case .hasActiveSession(let resolve, _):
            resolve(sdk.hasActiveSession())

        case .getSessionState(let resolve, _):
            resolve(sessionStateString(sdk.getSessionState()))

        case .endSession(let resolve, _):
            _ = await sdk.endSession()
            resolve(())

        case .dispose(let resolve, _):
            sdk.dispose()
            module.didDispose()
            resolve(())
        }
    }
}
