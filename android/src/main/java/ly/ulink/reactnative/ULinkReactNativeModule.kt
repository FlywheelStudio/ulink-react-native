package ly.ulink.reactnative

// ULinkReactNativeModule.kt
// Expo Module wrapping ly.ulink:ulink-sdk:1.1.0 for React Native / Expo.
//
// Design rules (global-constraints.md + task-7-brief.md):
//   - Name: "ULinkReactNative"
//   - initialize() is a suspend AsyncFunction; pre-init calls to other methods reject
//     with a clear error (requireSdk() throws). JS must await initialize() before other
//     calls — this is an intentional, documented Android/iOS behavioural difference.
//     iOS has a pendingCalls queue; Android does not (see Fix Report in task-7-report.md).
//   - enableDeepLinkIntegration is always forced false (ULinkBridge.config() enforces it).
//   - Cold-start links are buffered until BOTH: init complete AND first JS listener attached.
//   - Links are delivered via handleDeepLink(uri) → emits on SharedFlows → onDynamicLink /
//     onUnifiedLink events.  processULinkUri() is used only for the pull-method processULink().
//   - ALL mutations of pendingUris, initReady and observing are dispatched through `scope`
//     (Dispatchers.Main). This serialises them on a single thread — no locks needed, no race.
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
import kotlinx.coroutines.withContext
import ly.ulink.sdk.ULink

class ULinkReactNativeModule : Module() {

    // ── Coroutine scope ──────────────────────────────────────────────────────
    // All stream collectors and ALL mutations to the cold-start buffer run here.
    // Using Dispatchers.Main gives us a single-threaded serial executor for free —
    // no mutex / synchronized block needed for pendingUris, initReady, or observing.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // ── SDK reference (null until initialize() completes) ────────────────────
    // Written from scope (Main), read from Coroutine function bodies which may run
    // on the modulesQueue HandlerThread — @Volatile ensures cross-thread visibility.
    @Volatile private var sdk: ULink? = null

    // ── Two-gate cold-start buffer ───────────────────────────────────────────
    // A buffered link is only emitted once BOTH conditions hold:
    //   1. initReady  — ULink.initialize() has completed and streams are live.
    //   2. observing  — at least one JS event listener has attached (OnStartObserving).
    //
    // THREAD SAFETY: pendingUris, initReady and observing are accessed EXCLUSIVELY
    // through scope (Dispatchers.Main). Do NOT read or write them from any other
    // coroutine context or callback without dispatching through scope.launch { }.
    private var initReady = false
    private var observing = false
    private val pendingUris = mutableListOf<Uri>()

    // ── Module definition ────────────────────────────────────────────────────

    override fun definition() = ModuleDefinition {

        Name("ULinkReactNative")

        // ── Events ──────────────────────────────────────────────────────────
        Events("onDynamicLink", "onUnifiedLink", "onReinstallDetected", "onLog")

        // ── JS-listener gate ─────────────────────────────────────────────────
        // Fires on the Main thread when the first JS listener attaches.
        // Dispatched through scope to serialise with the buffer mutations in initialize().
        OnStartObserving {
            scope.launch {
                observing = true
                maybeFlush()
            }
        }

        // ── initialize ───────────────────────────────────────────────────────
        // Expo runs AsyncFunction Coroutine blocks on its modulesQueue HandlerThread,
        // NOT on the Main thread. ULink.initialize() is a suspend fun that blocks
        // until the SDK is ready — that is fine to run off Main.
        //
        // However, ALL mutations to pendingUris / initReady / observing must stay on
        // the Main thread. After the suspend call returns we hop back to scope (Main)
        // via withContext to do the launch-intent capture, set initReady, and flush.
        AsyncFunction("initialize") Coroutine { configMap: Map<String, Any?> ->
            // Idempotent: if already initialized return immediately.
            // sdk is @Volatile so this read is safe from any thread.
            if (sdk != null) return@Coroutine

            val ctx = appContext.reactContext?.applicationContext
                ?: throw IllegalStateException("Application context unavailable")

            val sdkConfig = ULinkBridge.config(configMap)

            // ULink.initialize() calls ProcessLifecycleOwner.get().lifecycle.addObserver()
            // which MUST run on the Main thread (Android lifecycle-2.x constraint).
            // Expo's AsyncFunction Coroutine runs on the modulesQueue (background thread),
            // so we must hop to Main for the entire ULink.initialize() call.
            val instance = withContext(Dispatchers.Main) { ULink.initialize(ctx, sdkConfig) }

            // Subscribe SharedFlows BEFORE setting initReady so collectors are live
            // when the first URI is flushed. subscribeStreams launches on scope (Main).
            subscribeStreams(instance)

            // Assign sdk before the Main-thread work so requireSdk() succeeds from
            // that point forward (visible cross-thread via @Volatile).
            sdk = instance

            // Hop to scope (Main) for ALL buffer/flag mutations and the flush.
            // withContext suspends the modulesQueue coroutine until this block finishes,
            // so initialize() doesn't return to the JS caller until the flush is done.
            withContext(scope.coroutineContext) {
                // Capture launch intent (cold-start deep link set before module existed).
                appContext.currentActivity?.intent?.data?.let { uri ->
                    bufferOrDeliver(uri)
                }
                // Open the init gate — maybeFlush() will fire if observing is already true.
                initReady = true
                maybeFlush()
            }
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
            // Hop to Main to clear buffer state in the same serialised context.
            withContext(Dispatchers.Main) {
                sdk = null
                initReady = false
                observing = false
                pendingUris.clear()
            }
        }

        // ── OnNewIntent — warm deep links ─────────────────────────────────────
        // Fired on the Main thread when the app is already running and a new intent
        // arrives (warm link). Dispatch through scope to serialise with the buffer.
        OnNewIntent { intent: Intent ->
            scope.launch {
                intent.data?.let { uri -> bufferOrDeliver(uri) }
            }
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
                        "timestamp" to entry.timestamp,  // Long → JS number
                        "tag" to entry.tag
                    )
                )
            }
            .launchIn(scope)
    }

    // ── Cold-start / warm link buffer ────────────────────────────────────────
    // All functions below MUST be called from within scope (Dispatchers.Main).

    // Buffer the URI if either gate is still closed; otherwise deliver immediately.
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

    // requireSdk() throws if called before initialize() completes. This is intentional:
    // Android requires JS to await initialize() before calling other methods.
    // Pre-init calls receive a clear rejection rather than silently queuing.
    // (iOS implements a pendingCalls queue; Android does not — see task-7-report.md Fix Report.)
    private fun requireSdk(): ULink =
        sdk ?: throw IllegalStateException(
            "ULink SDK not initialized. Call initialize() first and await it."
        )
}
