import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { WaveMark, Wordmark } from '../components/Brand';
import SpotsMap, { type MappedSpot } from '../components/SpotsMap';
import { bandColor } from '../logbook/bandColors';
import {
  bandFromKhz,
  fetchSpots,
  receiversForSpot,
  spotAge,
  spotCoords,
} from '../spots/spotsClient';
import { KiwiListener, type ListenPhase } from '../spots/kiwi';
import type { KiwiReceiver, Spot } from '../spots/types';

const REFRESH_MS = 60_000;
const VIEW_KEY = 'cw-spots-view';

type SpotsView = 'table' | 'map';

interface ListenSession {
  spot: Spot;
  receivers: KiwiReceiver[];
  selectedId: string | null;
  phase: ListenPhase | 'picking';
  detail?: string;
  sMeterDbm: number | null;
}

export default function SpotsPage() {
  const [spots, setSpots] = useState<Spot[] | null>(null);
  const [error, setError] = useState('');
  const [session, setSession] = useState<ListenSession | null>(null);
  const [view, setViewState] = useState<SpotsView>(() =>
    localStorage.getItem(VIEW_KEY) === 'map' ? 'map' : 'table',
  );
  const setView = useCallback((v: SpotsView) => {
    localStorage.setItem(VIEW_KEY, v);
    setViewState(v);
  }, []);

  // Spots we can place on the map (spotter grid → approximate coordinates).
  const mappedSpots = useMemo<MappedSpot[]>(
    () =>
      (spots ?? []).flatMap((spot) => {
        const coords = spotCoords(spot);
        return coords ? [{ spot, lat: coords[0], lon: coords[1] }] : [];
      }),
    [spots],
  );
  const listenerRef = useRef<KiwiListener | null>(null);
  // Bumped on every connect/stop so a slow in-flight connect (or its
  // callbacks) can't clobber a newer session.
  const generationRef = useRef(0);

  const refresh = useCallback(async () => {
    try {
      setSpots(await fetchSpots());
      setError('');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load spots');
    }
  }, []);

  // Initial load + 60 s auto-refresh.
  useEffect(() => {
    void refresh();
    const timer = window.setInterval(() => void refresh(), REFRESH_MS);
    return () => window.clearInterval(timer);
  }, [refresh]);

  // Only one active listen session — tear it down when the page unmounts.
  useEffect(
    () => () => {
      listenerRef.current?.stop();
      listenerRef.current = null;
    },
    [],
  );

  const stopListening = useCallback(() => {
    generationRef.current += 1;
    listenerRef.current?.stop();
    listenerRef.current = null;
  }, []);

  const connect = useCallback((spot: Spot, receiver: KiwiReceiver) => {
    stopListening();
    const generation = generationRef.current;
    const live = () => generationRef.current === generation;
    setSession((s) =>
      s
        ? { ...s, selectedId: receiver.id, phase: 'connecting', detail: undefined, sMeterDbm: null }
        : s,
    );
    void KiwiListener.start(receiver, spot.frequencyKhz, spot.mode, {
      onPhase: (phase, detail) => {
        if (!live()) return;
        setSession((s) => (s && s.spot.id === spot.id ? { ...s, phase, detail } : s));
      },
      onSMeter: (dbm) => {
        if (!live()) return;
        setSession((s) => (s && s.spot.id === spot.id ? { ...s, sMeterDbm: dbm } : s));
      },
    }).then(
      (listener) => {
        if (live()) {
          listenerRef.current = listener;
        } else {
          listener.stop(); // superseded while connecting
        }
      },
      (e) => {
        if (!live()) return;
        setSession((s) =>
          s && s.spot.id === spot.id
            ? { ...s, phase: 'error', detail: e instanceof Error ? e.message : 'connect failed' }
            : s,
        );
      },
    );
  }, [stopListening]);

  const openListenPanel = useCallback(
    async (spot: Spot) => {
      stopListening();
      setSession({
        spot,
        receivers: [],
        selectedId: null,
        phase: 'picking',
        sMeterDbm: null,
      });
      try {
        const receivers = await receiversForSpot(spot);
        setSession((s) => (s && s.spot.id === spot.id ? { ...s, receivers } : s));
        const best = receivers.find((r) => r.isAvailable) ?? receivers[0];
        if (best) connect(spot, best);
        else {
          setSession((s) =>
            s && s.spot.id === spot.id
              ? { ...s, phase: 'error', detail: 'No KiwiSDR receivers found for this spot' }
              : s,
          );
        }
      } catch (e) {
        setSession((s) =>
          s && s.spot.id === spot.id
            ? { ...s, phase: 'error', detail: e instanceof Error ? e.message : 'directory failed' }
            : s,
        );
      }
    },
    [connect, stopListening],
  );

  const closePanel = useCallback(() => {
    stopListening();
    setSession(null);
  }, [stopListening]);

  return (
    <div className="mx-auto max-w-7xl px-4 py-6 pb-44">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-4">
          <Wordmark />
          <span className="hidden text-sm text-cw-dim sm:inline">
            {spots ? (
              <>
                <span className="font-mono text-cw-text">{spots.length}</span> active spots
              </>
            ) : (
              'Loading spots…'
            )}
          </span>
        </div>
        <div className="flex items-center gap-3">
          <div className="flex rounded-lg border border-cw-border2 bg-cw-surface p-0.5">
            {(['table', 'map'] as const).map((v) => (
              <button
                key={v}
                onClick={() => setView(v)}
                className={`rounded-md px-3 py-1.5 text-xs font-medium transition-colors ${
                  view === v ? 'bg-cw-surface2 text-cw-white' : 'text-cw-dim hover:text-cw-text'
                }`}
              >
                {v === 'table' ? 'Table' : 'Map'}
              </button>
            ))}
          </div>
          <Link
            to="/"
            className="rounded-lg border border-cw-border2 bg-cw-surface px-4 py-2 text-sm font-medium text-cw-text transition-colors hover:border-cw-dim"
          >
            Logbook
          </Link>
        </div>
      </header>

      {error && (
        <p className="mt-4 rounded-lg border border-cw-red/40 bg-cw-red/10 p-3 text-sm text-cw-red">
          {error}
        </p>
      )}

      {spots === null && !error && (
        <div className="mt-16 flex flex-col items-center text-center">
          <WaveMark className="h-10 w-10" />
          <p className="cw-eyebrow mt-4 text-[0.62rem]">Fetching active spots…</p>
        </div>
      )}

      {spots !== null && view === 'map' && (
        <div className="mt-5">
          <SpotsMap
            spots={mappedSpots}
            activeSpot={
              session ? (mappedSpots.find((m) => m.spot.id === session.spot.id) ?? null) : null
            }
            receivers={session?.receivers ?? []}
            selectedReceiverId={session?.selectedId ?? null}
            onSpotClick={(spot) =>
              session?.spot.id === spot.id ? closePanel() : void openListenPanel(spot)
            }
            onReceiverClick={(receiver) => {
              if (session && receiver.id !== session.selectedId) connect(session.spot, receiver);
            }}
          />
          <p className="mt-2 text-xs text-cw-dim">
            {mappedSpots.length} of {spots.length} spots mappable. Tap a spot to listen — its
            ranked receivers appear on the map.
          </p>
        </div>
      )}

      {spots !== null && view === 'table' && (
        <div className="mt-5 overflow-x-auto rounded-xl border border-cw-border">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-cw-border bg-cw-surface">
                <Th>Age</Th>
                <Th>Call</Th>
                <Th>Freq (MHz)</Th>
                <Th>Band</Th>
                <Th>Mode</Th>
                <Th>Ref</Th>
                <Th>Source</Th>
                <Th>{''}</Th>
              </tr>
            </thead>
            <tbody>
              {spots.map((spot) => {
                const band = bandFromKhz(spot.frequencyKhz);
                const active = session?.spot.id === spot.id;
                return (
                  <tr
                    key={spot.id}
                    className="border-b border-cw-border/60 last:border-0 hover:bg-cw-surface/60"
                  >
                    <td className="whitespace-nowrap px-3 py-2 font-mono text-cw-dim">
                      {spotAge(spot.spottedAt)}
                    </td>
                    <td className="whitespace-nowrap px-3 py-2 font-mono font-medium text-cw-white">
                      {spot.callsign}
                    </td>
                    <td className="whitespace-nowrap px-3 py-2 font-mono tabular-nums text-cw-text">
                      {(spot.frequencyKhz / 1000).toFixed(3)}
                    </td>
                    <td className="whitespace-nowrap px-3 py-2">
                      {band && (
                        <span
                          className="rounded-full px-2 py-0.5 font-mono text-xs"
                          style={{ backgroundColor: `${bandColor(band)}26`, color: bandColor(band) }}
                        >
                          {band}
                        </span>
                      )}
                    </td>
                    <td className="whitespace-nowrap px-3 py-2">
                      <span className="rounded-full bg-cw-surface2 px-2 py-0.5 font-mono text-xs text-cw-dim">
                        {spot.mode}
                      </span>
                    </td>
                    <td className="max-w-56 truncate whitespace-nowrap px-3 py-2 font-mono text-cw-dim">
                      {spot.reference ?? ''}
                      {spot.referenceName && (
                        <span className="ml-1.5 font-sans text-xs text-cw-xdim">
                          {spot.referenceName}
                        </span>
                      )}
                    </td>
                    <td className="whitespace-nowrap px-3 py-2 text-xs text-cw-dim">
                      {spot.source.toUpperCase()}
                      {spot.spotter && <span className="ml-1 font-mono">· {spot.spotter}</span>}
                    </td>
                    <td className="whitespace-nowrap px-3 py-2 text-right">
                      <button
                        onClick={() => (active ? closePanel() : void openListenPanel(spot))}
                        className={`rounded-lg px-3 py-1.5 text-xs font-medium transition-colors ${
                          active
                            ? 'bg-cw-blue text-cw-bg'
                            : 'border border-cw-border2 bg-cw-surface text-cw-text hover:border-cw-dim'
                        }`}
                      >
                        {active ? 'Listening' : 'Listen'}
                      </button>
                    </td>
                  </tr>
                );
              })}
              {spots.length === 0 && (
                <tr>
                  <td colSpan={8} className="px-3 py-12 text-center text-cw-dim">
                    No active spots right now.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}

      {session && (
        <ListenPanel
          session={session}
          onPick={(receiver) => connect(session.spot, receiver)}
          onStop={stopListening}
          onClose={closePanel}
        />
      )}
    </div>
  );
}

function ListenPanel({
  session,
  onPick,
  onStop,
  onClose,
}: {
  session: ListenSession;
  onPick: (r: KiwiReceiver) => void;
  onStop: () => void;
  onClose: () => void;
}) {
  const { spot, receivers, selectedId, phase, detail, sMeterDbm } = session;
  const playing = phase === 'playing';
  const [pickerView, setPickerView] = useState<'chips' | 'map'>('chips');
  const mappedSpot = useMemo<MappedSpot | null>(() => {
    const coords = spotCoords(spot);
    return coords ? { spot, lat: coords[0], lon: coords[1] } : null;
  }, [spot]);

  return (
    <div className="fixed inset-x-0 bottom-0 z-20 border-t border-cw-border bg-cw-surface/95 backdrop-blur">
      <div className="mx-auto max-w-7xl px-4 py-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-baseline gap-3">
            <span className="font-mono text-base font-semibold text-cw-white">{spot.callsign}</span>
            <span className="font-mono text-sm text-cw-text">
              {(spot.frequencyKhz / 1000).toFixed(3)} MHz {spot.mode}
            </span>
            <PhaseBadge phase={phase} />
          </div>
          <div className="flex items-center gap-2">
            {(playing || phase === 'connecting' || phase === 'handshake') && (
              <button
                onClick={onStop}
                className="rounded-lg bg-cw-red/80 px-4 py-1.5 text-sm font-medium text-white hover:bg-cw-red"
              >
                Stop
              </button>
            )}
            <button
              onClick={onClose}
              className="rounded-lg border border-cw-border2 px-4 py-1.5 text-sm text-cw-text hover:border-cw-dim"
            >
              Close
            </button>
          </div>
        </div>

        {detail && phase === 'error' && (
          <p className="mt-2 text-sm text-cw-red">{detail}</p>
        )}

        {playing && (
          <div className="mt-3 flex items-center gap-3">
            <span className="cw-eyebrow text-[0.6rem]">S-meter</span>
            <div className="h-1.5 w-56 overflow-hidden rounded-full bg-cw-surface2">
              <div
                className="h-full rounded-full bg-cw-green transition-all"
                // Map roughly −127…−27 dBm onto 0…100 %.
                style={{
                  width: `${Math.max(0, Math.min(100, ((sMeterDbm ?? -127) + 127)))}%`,
                }}
              />
            </div>
            <span className="font-mono text-xs text-cw-dim">
              {sMeterDbm !== null ? `${sMeterDbm.toFixed(0)} dBm` : '—'}
            </span>
          </div>
        )}

        <div className="mt-3">
          <div className="flex items-center gap-3">
            <span className="cw-eyebrow text-[0.6rem]">
              {phase === 'picking' ? 'Finding nearby receivers…' : 'Receiver'}
            </span>
            {receivers.length > 0 && (
              <div className="flex rounded-md border border-cw-border2 p-0.5">
                {(['chips', 'map'] as const).map((v) => (
                  <button
                    key={v}
                    onClick={() => setPickerView(v)}
                    className={`rounded px-2 py-0.5 text-[0.65rem] font-medium transition-colors ${
                      pickerView === v
                        ? 'bg-cw-surface2 text-cw-white'
                        : 'text-cw-dim hover:text-cw-text'
                    }`}
                  >
                    {v === 'chips' ? 'Chips' : 'Map'}
                  </button>
                ))}
              </div>
            )}
          </div>
          {receivers.length > 0 && pickerView === 'map' && (
            <div className="mt-1.5">
              <SpotsMap
                compact
                spots={mappedSpot ? [mappedSpot] : []}
                activeSpot={mappedSpot}
                receivers={receivers}
                selectedReceiverId={selectedId}
                onReceiverClick={(r) => {
                  if (r.id !== selectedId) onPick(r);
                }}
              />
            </div>
          )}
          {receivers.length > 0 && pickerView === 'chips' && (
            <div className="mt-1.5 flex flex-wrap gap-2">
              {receivers.map((receiver) => {
                const active = receiver.id === selectedId;
                return (
                  <button
                    key={receiver.id}
                    onClick={() => onPick(receiver)}
                    disabled={active}
                    title={`${receiver.location} — ${receiver.antenna}`}
                    className={`rounded-full border px-3 py-1 text-xs transition-colors ${
                      active
                        ? 'border-cw-blue bg-cw-blue/15 text-cw-blue'
                        : 'border-cw-border2 text-cw-text hover:border-cw-dim'
                    } ${receiver.isAvailable ? '' : 'opacity-50'}`}
                  >
                    {receiver.name || receiver.host}
                    {receiver.distanceKm !== undefined && (
                      <span className="ml-1 text-cw-xdim">
                        {Math.round(receiver.distanceKm)} km
                      </span>
                    )}
                    {!receiver.isAvailable && <span className="ml-1 text-cw-red">full</span>}
                  </button>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function PhaseBadge({ phase }: { phase: ListenSession['phase'] }) {
  const styles: Record<string, string> = {
    picking: 'bg-cw-surface2 text-cw-dim',
    connecting: 'bg-cw-blue/15 text-cw-blue',
    handshake: 'bg-cw-blue/15 text-cw-blue',
    playing: 'bg-cw-green/15 text-cw-green',
    stopped: 'bg-cw-surface2 text-cw-dim',
    error: 'bg-cw-red/15 text-cw-red',
  };
  const labels: Record<string, string> = {
    picking: 'finding receivers',
    connecting: 'connecting',
    handshake: 'handshake',
    playing: 'live',
    stopped: 'stopped',
    error: 'error',
  };
  return (
    <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${styles[phase]}`}>
      {labels[phase]}
    </span>
  );
}

function Th({ children }: { children: React.ReactNode }) {
  return <th className="cw-eyebrow px-3 py-2.5 text-left text-[0.6rem]">{children}</th>;
}
