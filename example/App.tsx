/**
 * ULink React Native SDK — E2E Verification Screen (Task 9)
 *
 * Runs the full verification matrix on mount (no button taps required).
 * All results are:
 *   • console.log'd with a [ULINK-E2E] prefix (greppable in Metro / logcat)
 *   • rendered to screen so screenshots provide backup evidence
 *
 * Key is read from EXPO_PUBLIC_ULINK_API_KEY (gitignored .env — never committed).
 */

import React, { useEffect, useRef, useState } from 'react';
import {
  Platform,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import ULink from '../src'; // local SDK (autolinking in example)
import type { ULinkResolvedData, ULinkInstallationInfo, ULinkLogEntry } from '../src';

// ─── types for screen state ───────────────────────────────────────────────────

interface ResultEntry {
  label: string;
  status: 'ok' | 'error' | 'info';
  detail: string;
}

interface EventEntry {
  name: string;
  data: string;
}

// ─── helpers ──────────────────────────────────────────────────────────────────

function log(tag: string, detail: string) {
  console.log(`[ULINK-E2E] ${tag} ${detail}`);
}

// ─── App ─────────────────────────────────────────────────────────────────────

export default function App() {
  const [results, setResults] = useState<ResultEntry[]>([]);
  const [lastEvent, setLastEvent] = useState<EventEntry | null>(null);
  const initialized = useRef(false);

  const addResult = (entry: ResultEntry) => {
    setResults((prev) => [...prev, entry]);
  };

  useEffect(() => {
    if (initialized.current) return;
    initialized.current = true;

    // ── 1. Subscribe to all 4 events (before init so we capture early events) ──

    const subDynamic = ULink.onDynamicLink((data: ULinkResolvedData) => {
      const json = JSON.stringify(data);
      log('event onDynamicLink', json);
      setLastEvent({ name: 'onDynamicLink', data: json });
    });

    const subUnified = ULink.onUnifiedLink((data: ULinkResolvedData) => {
      const json = JSON.stringify(data);
      log('event onUnifiedLink', json);
      setLastEvent({ name: 'onUnifiedLink', data: json });
    });

    const subReinstall = ULink.onReinstallDetected((info: ULinkInstallationInfo) => {
      const json = JSON.stringify(info);
      log('event onReinstallDetected', json);
      setLastEvent({ name: 'onReinstallDetected', data: json });
    });

    const subLog = ULink.onLog((entry: ULinkLogEntry) => {
      const json = JSON.stringify(entry);
      log('event onLog', json);
    });

    // ── 2. Async verification sequence ──────────────────────────────────────

    const apiKey = process.env.EXPO_PUBLIC_ULINK_API_KEY ?? '';

    (async () => {
      // 2a. initialize
      try {
        await ULink.initialize({ apiKey, debug: true });
        log('init ok', '');
        addResult({ label: 'initialize', status: 'ok', detail: 'init ok' });
      } catch (e: any) {
        log('initialize ERROR', e?.message ?? String(e));
        addResult({ label: 'initialize', status: 'error', detail: e?.message ?? String(e) });
        // if init fails, nothing else will work meaningfully
        return;
      }

      // 2b. getInstallationId
      try {
        const id = await ULink.getInstallationId();
        const detail = `installationId=${id ?? 'null'}`;
        log('getInstallationId', detail);
        addResult({
          label: 'getInstallationId',
          status: id != null ? 'ok' : 'error',
          detail,
        });
      } catch (e: any) {
        log('getInstallationId ERROR', e?.message ?? String(e));
        addResult({ label: 'getInstallationId', status: 'error', detail: e?.message ?? String(e) });
      }

      // 2c. getInstallationInfo
      try {
        const info = await ULink.getInstallationInfo();
        const detail = info
          ? `isReinstall=${info.isReinstall} persistentDeviceId=${info.persistentDeviceId ?? 'null'}`
          : 'null';
        log('getInstallationInfo', detail);
        addResult({ label: 'getInstallationInfo', status: 'ok', detail });
      } catch (e: any) {
        log('getInstallationInfo ERROR', e?.message ?? String(e));
        addResult({ label: 'getInstallationInfo', status: 'error', detail: e?.message ?? String(e) });
      }

      // 2d. createLink
      let createdUrl: string | undefined;
      try {
        // Use platform-specific slug so iOS and Android runs don't conflict
        const slug = Platform.OS === 'android' ? 'rn-e2e-android' : 'rn-e2e-ios';
        const resp = await ULink.createLink({
          domain: 'shadd.shared.ly',
          slug,
          fallbackUrl: 'https://ulink.ly',
          parameters: { foo: 'bar' },
        });
        createdUrl = resp.url;
        const detail = `success=${resp.success} url=${resp.url ?? 'undefined'} error=${resp.error ?? 'none'}`;
        log('createLink', detail);
        addResult({
          label: 'createLink',
          status: resp.success && resp.url ? 'ok' : 'error',
          detail,
        });
      } catch (e: any) {
        log('createLink ERROR', e?.message ?? String(e));
        addResult({ label: 'createLink', status: 'error', detail: e?.message ?? String(e) });
      }

      // 2e. resolveLink (using the url we just created)
      try {
        if (!createdUrl) throw new Error('no url to resolve (createLink failed)');
        const resp = await ULink.resolveLink(createdUrl);
        const detail = `success=${resp.success} data=${JSON.stringify(resp.data ?? null)}`;
        log('resolveLink', detail);
        addResult({
          label: 'resolveLink',
          status: resp.success ? 'ok' : 'error',
          detail,
        });
      } catch (e: any) {
        log('resolveLink ERROR', e?.message ?? String(e));
        addResult({ label: 'resolveLink', status: 'error', detail: e?.message ?? String(e) });
      }

      // 2f. getSessionState
      try {
        const state = await ULink.getSessionState();
        const detail = `sessionState=${state}`;
        log('getSessionState', detail);
        addResult({
          label: 'getSessionState',
          status: state === 'active' ? 'ok' : 'error',
          detail,
        });
      } catch (e: any) {
        log('getSessionState ERROR', e?.message ?? String(e));
        addResult({ label: 'getSessionState', status: 'error', detail: e?.message ?? String(e) });
      }

      // 2g. checkDeferredLink (must not throw)
      try {
        await ULink.checkDeferredLink();
        log('checkDeferredLink', 'no-throw');
        addResult({ label: 'checkDeferredLink', status: 'ok', detail: 'no-throw' });
      } catch (e: any) {
        log('checkDeferredLink ERROR', e?.message ?? String(e));
        addResult({ label: 'checkDeferredLink', status: 'error', detail: e?.message ?? String(e) });
      }
    })();

    return () => {
      subDynamic.remove();
      subUnified.remove();
      subReinstall.remove();
      subLog.remove();
    };
  }, []);

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.scroll} contentContainerStyle={styles.content}>
        <Text style={styles.header}>ULink E2E Verification</Text>

        {/* Verification sequence results */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Sequence Results</Text>
          {results.length === 0 && (
            <Text style={styles.info}>Running…</Text>
          )}
          {results.map((r, i) => (
            <View key={i} style={styles.row}>
              <Text style={[styles.badge, r.status === 'ok' ? styles.ok : styles.err]}>
                {r.status === 'ok' ? 'OK' : 'ERR'}
              </Text>
              <View style={styles.rowText}>
                <Text style={styles.label}>{r.label}</Text>
                <Text style={styles.detail} numberOfLines={3}>{r.detail}</Text>
              </View>
            </View>
          ))}
        </View>

        {/* Last event received */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Last Event</Text>
          {lastEvent ? (
            <>
              <Text style={styles.label}>{lastEvent.name}</Text>
              <Text style={styles.detail}>{lastEvent.data}</Text>
            </>
          ) : (
            <Text style={styles.info}>No events yet — send a deep link to trigger one.</Text>
          )}
        </View>

        <Text style={styles.hint}>
          Deep link test:{'\n'}
          ulinksdkexample://test?foo=bar
        </Text>
      </ScrollView>
    </SafeAreaView>
  );
}

// ─── Styles ──────────────────────────────────────────────────────────────────

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f0f4f8' },
  scroll: { flex: 1 },
  content: { padding: 16, paddingBottom: 40 },
  header: {
    fontSize: 22,
    fontWeight: '700',
    marginBottom: 16,
    color: '#1a202c',
  },
  section: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 14,
    marginBottom: 14,
    shadowColor: '#000',
    shadowOpacity: 0.06,
    shadowRadius: 4,
    elevation: 2,
  },
  sectionTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#718096',
    marginBottom: 10,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    marginBottom: 8,
    gap: 8,
  },
  rowText: { flex: 1 },
  badge: {
    fontSize: 11,
    fontWeight: '700',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    overflow: 'hidden',
    marginTop: 1,
  },
  ok: { backgroundColor: '#c6f6d5', color: '#22543d' },
  err: { backgroundColor: '#fed7d7', color: '#742a2a' },
  label: { fontSize: 13, fontWeight: '600', color: '#2d3748' },
  detail: { fontSize: 11, color: '#4a5568', marginTop: 2 },
  info: { fontSize: 13, color: '#718096', fontStyle: 'italic' },
  hint: {
    fontSize: 12,
    color: '#718096',
    marginTop: 8,
    textAlign: 'center',
    lineHeight: 18,
  },
});
