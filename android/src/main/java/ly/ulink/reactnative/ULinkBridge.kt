package ly.ulink.reactnative

// ULinkBridge.kt
// Conversion helpers between the native Android SDK types and JS-safe
// Map/List structures that Expo Modules serialises across the bridge.
//
// Rules (global-constraints.md + task-7-brief.md):
//   - config()  MUST force enableDeepLinkIntegration = false regardless of input.
//   - resolvedData() MUST include rawData (serialisation contract with types.ts).
//   - onLog timestamp MUST be a Long (epoch millis) — already a Long in ULinkLogEntry.
//   - sessionState → lowercase string ("IDLE" → "idle", etc.)
//   - JsonElement parameters/metadata/rawData → plain Map/List via recursive conversion.
//   - Do NOT emit iosUrl/androidUrl as resolvedData output keys (they are input-only
//     ULinkParameters fields, not present on ULinkResolvedData).

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import ly.ulink.sdk.models.SessionState
import ly.ulink.sdk.models.SocialMediaTags
import ly.ulink.sdk.models.ULinkConfig
import ly.ulink.sdk.models.ULinkInstallationInfo
import ly.ulink.sdk.models.ULinkParameters
import ly.ulink.sdk.models.ULinkResolvedData
import ly.ulink.sdk.models.ULinkResponse

object ULinkBridge {

    // -------------------------------------------------------------------------
    // config — parse JS Map → ULinkConfig, always forcing enableDeepLinkIntegration=false
    // -------------------------------------------------------------------------

    fun config(map: Map<String, Any?>): ULinkConfig {
        val apiKey = (map["apiKey"] as? String)
            ?: throw IllegalArgumentException("apiKey is required")
        val baseUrl = map["baseUrl"] as? String ?: "https://api.ulink.ly"
        val debug = map["debug"] as? Boolean ?: false
        val persistLastLinkData = map["persistLastLinkData"] as? Boolean ?: true
        val lastLinkTTLSeconds: Long = when (val ttl = map["lastLinkTimeToLiveSeconds"]) {
            is Number -> ttl.toLong()
            else -> 24 * 60 * 60L
        }
        val clearLastLinkOnRead = map["clearLastLinkOnRead"] as? Boolean ?: false
        val redactAll = map["redactAllParametersInLastLink"] as? Boolean ?: false
        @Suppress("UNCHECKED_CAST")
        val redactedKeys: List<String> =
            (map["redactedParameterKeysInLastLink"] as? List<*>)
                ?.filterIsInstance<String>() ?: emptyList()
        val autoCheckDeferredLink = map["autoCheckDeferredLink"] as? Boolean ?: true

        return ULinkConfig(
            apiKey = apiKey,
            baseUrl = baseUrl,
            debug = debug,
            // ALWAYS false — the module owns link delivery via handleDeepLink()
            enableDeepLinkIntegration = false,
            persistLastLinkData = persistLastLinkData,
            lastLinkTimeToLiveSeconds = lastLinkTTLSeconds,
            clearLastLinkOnRead = clearLastLinkOnRead,
            redactAllParametersInLastLink = redactAll,
            redactedParameterKeysInLastLink = redactedKeys,
            autoCheckDeferredLink = autoCheckDeferredLink
        )
    }

    // -------------------------------------------------------------------------
    // parameters — parse JS Map → ULinkParameters
    // -------------------------------------------------------------------------

    fun parameters(map: Map<String, Any?>): ULinkParameters {
        val domain = (map["domain"] as? String)
            ?: throw IllegalArgumentException("domain is required")
        val type = map["type"] as? String ?: "dynamic"

        // socialMediaTags sub-map
        @Suppress("UNCHECKED_CAST")
        val socialTagsMap = map["socialMediaTags"] as? Map<String, Any?>
        val socialTags = socialTagsMap?.let {
            SocialMediaTags(
                ogTitle = it["ogTitle"] as? String,
                ogDescription = it["ogDescription"] as? String,
                ogImage = it["ogImage"] as? String
            )
        }

        // parameters / metadata: JS sends plain Map → convert to JsonElement
        @Suppress("UNCHECKED_CAST")
        val paramsJsonEl = (map["parameters"] as? Map<String, Any?>)
            ?.let { mapToJsonObject(it) }

        @Suppress("UNCHECKED_CAST")
        val metaJsonEl = (map["metadata"] as? Map<String, Any?>)
            ?.let { mapToJsonObject(it) }

        return ULinkParameters(
            type = type,
            domain = domain,
            slug = map["slug"] as? String,
            name = map["name"] as? String,
            iosUrl = map["iosUrl"] as? String,
            androidUrl = map["androidUrl"] as? String,
            iosFallbackUrl = map["iosFallbackUrl"] as? String,
            androidFallbackUrl = map["androidFallbackUrl"] as? String,
            fallbackUrl = map["fallbackUrl"] as? String,
            parameters = paramsJsonEl,
            socialMediaTags = socialTags,
            metadata = metaJsonEl,
            externalId = map["externalId"] as? String
        )
    }

    // -------------------------------------------------------------------------
    // response — ULinkResponse → JS-safe Map
    // -------------------------------------------------------------------------

    fun response(r: ULinkResponse): Map<String, Any?> = mapOf(
        "success" to r.success,
        "url" to r.url,
        "error" to r.error,
        "data" to r.data?.let { jsonObjectToMap(it) }
    )

    // -------------------------------------------------------------------------
    // resolvedData — ULinkResolvedData? → JS-safe Map? (null-safe)
    // Contract with types.ts: must include rawData; must NOT include iosUrl/androidUrl.
    // -------------------------------------------------------------------------

    fun resolvedData(d: ULinkResolvedData?): Map<String, Any?>? {
        d ?: return null
        val socialTagsMap: Map<String, Any?>? = d.socialMediaTags?.let {
            mapOf(
                "ogTitle" to it.ogTitle,
                "ogDescription" to it.ogDescription,
                "ogImage" to it.ogImage
            )
        }
        return mapOf(
            "slug" to d.slug,
            "iosFallbackUrl" to d.iosFallbackUrl,
            "androidFallbackUrl" to d.androidFallbackUrl,
            "fallbackUrl" to d.fallbackUrl,
            "parameters" to d.parameters?.let { jsonElementToAny(it) },
            "socialMediaTags" to socialTagsMap,
            "metadata" to d.metadata?.let { jsonElementToAny(it) },
            "type" to d.type,
            "isDeferred" to d.isDeferred,
            "matchType" to d.matchType,
            // rawData is required per serialisation contract (iOS parity + types.ts)
            "rawData" to d.rawData?.let { jsonObjectToMap(it) }
        )
    }

    // -------------------------------------------------------------------------
    // installationInfo — ULinkInstallationInfo? → JS-safe Map?
    // -------------------------------------------------------------------------

    fun installationInfo(info: ULinkInstallationInfo?): Map<String, Any?>? {
        info ?: return null
        return mapOf(
            "installationId" to info.installationId,
            "isReinstall" to info.isReinstall,
            "previousInstallationId" to info.previousInstallationId,
            "reinstallDetectedAt" to info.reinstallDetectedAt,
            "persistentDeviceId" to info.persistentDeviceId
        )
    }

    // -------------------------------------------------------------------------
    // sessionState — SessionState enum → lowercase string (matches types.ts enum values)
    // -------------------------------------------------------------------------

    fun sessionState(s: SessionState): String = when (s) {
        SessionState.IDLE -> "idle"
        SessionState.INITIALIZING -> "initializing"
        SessionState.ACTIVE -> "active"
        SessionState.ENDING -> "ending"
        SessionState.FAILED -> "failed"
    }

    // -------------------------------------------------------------------------
    // Private: recursive JsonElement → plain JVM types (Map/List/primitives)
    // The Expo bridge can serialise these to JS without extra work.
    // -------------------------------------------------------------------------

    internal fun jsonElementToAny(el: JsonElement): Any? = when {
        el is JsonNull -> null
        el is JsonArray -> el.map { jsonElementToAny(it) }
        el is JsonObject -> jsonObjectToMap(el)
        el is JsonPrimitive && el.isString -> el.content
        el is JsonPrimitive && el.content == "true" -> true
        el is JsonPrimitive && el.content == "false" -> false
        el is JsonPrimitive && el.content.toLongOrNull() != null -> el.content.toLong()
        el is JsonPrimitive && el.content.toDoubleOrNull() != null -> el.content.toDouble()
        else -> (el as? JsonPrimitive)?.content
    }

    internal fun jsonObjectToMap(obj: JsonObject): Map<String, Any?> =
        obj.entries.associate { (k, v) -> k to jsonElementToAny(v) }

    // Convert a plain Map<String, Any?> to a JsonObject for ULinkParameters fields
    private fun mapToJsonObject(map: Map<String, Any?>): JsonObject = buildJsonObject {
        map.forEach { (key, value) ->
            when (value) {
                null -> put(key, JsonNull)
                is String -> put(key, JsonPrimitive(value))
                is Boolean -> put(key, JsonPrimitive(value))
                is Number -> put(key, JsonPrimitive(value.toDouble()))
                else -> put(key, JsonPrimitive(value.toString()))
            }
        }
    }
}
