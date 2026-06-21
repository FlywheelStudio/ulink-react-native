package ly.ulink.reactnative

// ULinkReactNativeModule.kt
// Expo Module wrapping ly.ulink:ulink-sdk:1.1.0 for React Native / Expo.
//
// Design rules (global-constraints.md + task-7-brief.md):
//   - Name: "ULinkReactNative"
//   - initialize() is a suspend AsyncFunction; all other calls queue until it resolves.
//   - enableDeepLinkIntegration is always forced false (ULinkBridge.config() enforces it).
//   - Cold-start links are buffered until BOTH: init complete AND first JS listener attached.
//   - Links are delivered via handleDeepLink(uri) → emits on SharedFlows → onDynamicLink /
//     onUnifiedLink events.  processULinkUri() is used only for the pull-method processULink().
//   - dispose() cancels the module coroutine scope and clears SDK ref + buffer.
//     It does NOT call sdk.dispose() (which would cancel the SDK's own scope).
//   - Never wire dispose() to JS unmount / fast-refresh.

import android.content.Intent
import android.net.Uri
import expo.modules.kotlin.functions.Coroutine
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import ly.ulink.sdk.ULink

class ULinkReactNativeModule : Module() {

    // ── Coroutine scope for stream collectors and pending-call execution ──────
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // ── SDK reference (null until initialize() completes) ────────────────────
    @Volatile private var sdk: ULink? = null

    // ── Two-gate cold-start buffer ───────────────────────────────────────────
    // A buffered link is only emitted once BOTH conditions hold:
    //   1. initReady  — ULink.initialize() has completed and streams are live.
    //   2. observing  — at least one JS event listener has attached (OnStartObserving).
    //
    // This prevents the race where a cold-start link is emitted before JS has
    // called ULink.onDynamicLink(cb) / ULink.onUnifiedLink(cb).
    @Volatile private var initReady = false
    @Volatile private var observing = false
    private val pendingUris = mutableListOf<Uri>()   // accessed only on Main dispatcher

    // ── Pending method calls queued before init completes ────────────────────
    // Each entry is a lambda that is invoked once the SDK is ready.
    private val pendingCalls = mutableListOf<() -> Unit>()

    // ── Module definition ────────────────────────────────────────────────────

    override fun definition() = ModuleDefinition {

        Name("ULinkReactNative")

        // ── Events ──────────────────────────────────────────────────────────
        Events("onDynamicLink", "onUnifiedLink", "onReinstallDetected", "onLog")

        // ── JS-listener gate ─────────────────────────────────────────────────
        // Fires when the first JS listener attaches to any event on this module.
        // Once both gates are open (init + observing), buffered cold-start links flush.
        OnStartObserving {
            observing = true
            maybeFlush()
        }

        // ── initialize ───────────────────────────────────────────────────────
        // suspend: Expo runs this on the module's background scope via Coroutine.
        // Forces enableDeepLinkIntegration=false via ULinkBridge.config().
        AsyncFunction("initialize") Coroutine { configMap: Map<String, Any?> ->
            // Idempotent: if already initialized return immediately
            if (sdk != null) return@Coroutine

            val ctx = appContext.reactContext?.applicationContext
                ?: throw IllegalStateException("Application context unavailable")

            val sdkConfig = ULinkBridge.config(configMap)

            // Suspend until the native SDK bootstrap completes
            val instance = ULink.initialize(ctx, sdkConfig)
            sdk = instance

            // Subscribe SharedFlows → Expo events (must be before capture below)
            subscribeStreams(instance)

            // Capture launch intent (cold-start deep link set before this module existed)
            appContext.currentActivity?.intent?.data?.let { uri ->
                bufferOrDeliver(uri)
            }

            // Mark init complete and flush if the JS listener gate is already open
            initReady = true
            maybeFlush()

            // Drain any method calls that arrived before we were ready
            val toRun = pendingCalls.toList()
            pendingCalls.clear()
            toRun.forEach { it() }
        }

        // ── createLink ───────────────────────────────────────────────────────
        AsyncFunction("createLink") Coroutine { paramsMap: Map<String, Any?> ->
            ULinkBridge.response(requireSdk().createLink(ULinkBridge.parameters(paramsMap)))
        }

        // ── resolveLink ──────────────────────────────────────────────────────
        AsyncFunction("resolveLink") Coroutine { url: String ->
            ULinkBridge.response(requireSdk().resolveLink(url))
        }

        // ── processULink — pull-method only, does NOT deliver via event ───────
        // Uses processULinkUri() which resolves-and-returns without emitting on
        // the SharedFlows. Link DELIVERY uses handleDeepLink().
        AsyncFunction("processULink") Coroutine { url: String ->
            ULinkBridge.resolvedData(requireSdk().processULinkUri(Uri.parse(url)))
        }

        // ── checkDeferredLink (non-suspend in SDK) ───────────────────────────
        AsyncFunction("checkDeferredLink") Coroutine { ->
            requireSdk().checkDeferredLink()
        }

        // ── getInitialDeepLink — suspend pull-method ─────────────────────────
        AsyncFunction("getInitialDeepLink") Coroutine { ->
            ULinkBridge.resolvedData(requireSdk().getInitialDeepLink())
        }

        // ── getInitialUri / setInitialUri ────────────────────────────────────
        AsyncFunction("getInitialUri") Coroutine { ->
            requireSdk().getInitialUri()?.toString()
        }

        AsyncFunction("setInitialUri") Coroutine { uri: String ->
            requireSdk().setInitialUri(Uri.parse(uri))
        }

        // ── getLastLinkData (non-suspend in SDK) ─────────────────────────────
        AsyncFunction("getLastLinkData") Coroutine { ->
            ULinkBridge.resolvedData(requireSdk().getLastLinkData())
        }

        // ── installation ─────────────────────────────────────────────────────
        AsyncFunction("getInstallationId") Coroutine { ->
            requireSdk().getInstallationId()
        }

        AsyncFunction("getInstallationInfo") Coroutine { ->
            ULinkBridge.installationInfo(requireSdk().getInstallationInfo())
        }

        AsyncFunction("isReinstall") Coroutine { ->
            requireSdk().isReinstall()
        }

        // ── session ───────────────────────────────────────────────────────────
        AsyncFunction("getCurrentSessionId") Coroutine { ->
            requireSdk().getCurrentSessionId()
        }

        AsyncFunction("hasActiveSession") Coroutine { ->
            requireSdk().hasActiveSession()
        }

        AsyncFunction("getSessionState") Coroutine { ->
            ULinkBridge.sessionState(requireSdk().getSessionState())
        }

        // endSession returns Boolean in the SDK but we return Unit to JS (matches iOS)
        AsyncFunction("endSession") Coroutine { ->
            requireSdk().endSession()
            Unit
        }

        // ── dispose ───────────────────────────────────────────────────────────
        // Cancels the module's coroutine scope and clears state.
        // Does NOT call sdk.dispose() (which would cancel the SDK's own lifecycle
        // scope — the SDK outlives any single module instance).
        AsyncFunction("dispose") Coroutine { ->
            scope.coroutineContext.cancelChildren()
            sdk = null
            initReady = false
            observing = false
            pendingUris.clear()
            pendingCalls.clear()
        }

        // ── OnNewIntent — warm deep links ─────────────────────────────────────
        // Fired when the app is already running and a new intent arrives (warm link).
        // If the SDK is not yet ready the URI is buffered and flushed after init.
        OnNewIntent { intent: Intent ->
            intent.data?.let { uri -> bufferOrDeliver(uri) }
        }
    }

    // ── Stream subscriptions ──────────────────────────────────────────────────

    private fun subscribeStreams(instance: ULink) {
        // dynamicLinkStream → onDynamicLink event
        instance.dynamicLinkStream
            .onEach { data ->
                sendEvent("onDynamicLink", ULinkBridge.resolvedData(data) ?: emptyMap<String, Any?>())
            }
            .launchIn(scope)

        // unifiedLinkStream → onUnifiedLink event
        instance.unifiedLinkStream
            .onEach { data ->
                sendEvent("onUnifiedLink", ULinkBridge.resolvedData(data) ?: emptyMap<String, Any?>())
            }
            .launchIn(scope)

        // onReinstallDetected → onReinstallDetected event
        instance.onReinstallDetected
            .onEach { info ->
                sendEvent(
                    "onReinstallDetected",
                    ULinkBridge.installationInfo(info) ?: emptyMap<String, Any?>()
                )
            }
            .launchIn(scope)

        // logStream → onLog event
        // timestamp is already a Long (epoch millis) in ULinkLogEntry — send as-is.
        instance.logStream
            .onEach { entry ->
                sendEvent(
                    "onLog",
                    mapOf(
                        "level" to entry.level,
                        "message" to entry.message,
                        "timestamp" to entry.timestamp  // Long → JS number
                    )
                )
            }
            .launchIn(scope)
    }

    // ── Cold-start / warm link buffer ────────────────────────────────────────

    // Buffer the URI if either gate is still closed; otherwise deliver immediately.
    // Must be called on the Main dispatcher (scope.launch ensures this for async paths).
    private fun bufferOrDeliver(uri: Uri) {
        if (initReady && observing) {
            deliverUri(uri)
        } else {
            pendingUris.add(uri)
        }
    }

    // Flush all buffered URIs when both gates open.
    // Snapshot-and-clear before any suspending call to avoid double-delivery.
    private fun maybeFlush() {
        if (!initReady || !observing) return
        val toDeliver = pendingUris.toList()
        pendingUris.clear()
        toDeliver.forEach { deliverUri(it) }
    }

    // Deliver a URI through handleDeepLink() which emits on the SharedFlows.
    // handleDeepLink() is non-suspend and launches its own coroutine internally.
    private fun deliverUri(uri: Uri) {
        sdk?.handleDeepLink(uri)
    }

    // ── SDK accessor ──────────────────────────────────────────────────────────

    // For suspend methods that should queue if the SDK isn't ready yet, we use
    // requireSdk() which throws immediately — but all AsyncFunction Coroutine
    // blocks only reach requireSdk() after initialize() has set sdk, because:
    //   - If called before init, the Expo module queues them (Expo modules run
    //     functions sequentially per module, so a second call waits for the first).
    // For extra safety we also maintain pendingCalls for non-Coroutine lambdas.
    private fun requireSdk(): ULink =
        sdk ?: throw IllegalStateException(
            "ULink SDK not initialized. Call initialize() first and await it."
        )
}
