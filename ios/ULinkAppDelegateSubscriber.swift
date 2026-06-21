// ULinkAppDelegateSubscriber.swift
// Expo AppDelegate subscriber that forwards incoming URLs into the ULink SDK.
//
// Warm links (app already running):
//   application(_:continue:restorationHandler:)  — universal links (https)
//   application(_:open:options:)                 — custom-scheme URLs
//
// Cold-start links (app not running, link opened it):
//   application(_:didFinishLaunchingWithOptions:) — captures the launch URL from
//   launchOptions and buffers it via ULinkIncomingLinkBuffer.shared.
//
// All URLs are forwarded to ULinkIncomingLinkBuffer.shared.buffer(_:).
// The buffer holds URLs until BOTH gates are open:
//   1. SDK ready  — ULinkReactNativeModule calls setReady() after initialize()
//   2. JS observing — OnStartObserving fires when the first JS listener attaches
// When both gates are open, buffered URLs are flushed via handleDeepLinkAsync()
// which emits on the SDK's Combine streams → onDynamicLink / onUnifiedLink events.

import ExpoModulesCore
import UIKit

public class ULinkAppDelegateSubscriber: ExpoAppDelegateSubscriber {

    // MARK: - Universal links (https / associated-domains)

    public func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return false }
        Task { await ULinkIncomingLinkBuffer.shared.buffer(url) }
        return true
    }

    // MARK: - Custom-scheme URLs

    public func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        Task { await ULinkIncomingLinkBuffer.shared.buffer(url) }
        return true
    }

    // MARK: - Cold-start link capture

    /// Captures a link delivered via launchOptions when the app was not running.
    /// Universal links arrive in the `.userActivityDictionary` key; custom-scheme
    /// URLs arrive in the `.url` key.  Both are buffered before JS has a chance to
    /// call `initialize()`.
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Universal link cold-start
        if let activityDict = launchOptions?[.userActivityDictionary] as? [String: Any] {
            for value in activityDict.values {
                if let activity = value as? NSUserActivity,
                   activity.activityType == NSUserActivityTypeBrowsingWeb,
                   let url = activity.webpageURL {
                    Task { await ULinkIncomingLinkBuffer.shared.buffer(url) }
                }
            }
        }

        // Custom-scheme cold-start
        if let url = launchOptions?[.url] as? URL {
            Task { await ULinkIncomingLinkBuffer.shared.buffer(url) }
        }

        return true
    }
}
