import { useState, useEffect } from 'react';
import { tokens } from '../styles/tokens';
import { StatusDot } from './StatusDot';
import { SectionTitle } from './SectionTitle';
import { BandBadge } from './BandBadge';
import { api } from '../api/client';
import { frequencyToBand } from '../utils/bands';
import type { SdrInfo, RecordingRow } from '../api/types';

interface SDRDetailProps {
  sdr: SdrInfo;
}

function getSdrStatus(sdr: SdrInfo): 'online' | 'active' | 'offline' {
  const ks = sdr.kiwi_status;
  if (!ks || ks.offline) return 'offline';
  if (ks.users && ks.users > 0) return 'active';
  return 'online';
}

function formatFreqRange(range: [number, number]): string {
  const lo = range[0] / 1e6;
  const hi = range[1] / 1e6;
  return `${lo.toFixed(1)} – ${hi.toFixed(1)} MHz`;
}

function formatBandwidth(bw: number): string {
  if (bw >= 1e6) return `${(bw / 1e6).toFixed(1)} MHz`;
  return `${(bw / 1e3).toFixed(0)} kHz`;
}

function formatTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function formatFrequency(hz: number): string {
  return (hz / 1000).toFixed(1);
}

const statusLabel: Record<string, string> = {
  online: 'Online',
  active: 'Active',
  offline: 'Offline',
};

export function SDRDetail({ sdr }: SDRDetailProps) {
  const ks = sdr.kiwi_status;
  const status = getSdrStatus(sdr);
  const caps = sdr.capabilities;

  const [recordings, setRecordings] = useState<RecordingRow[]>([]);
  const [loadingRecs, setLoadingRecs] = useState(true);

  useEffect(() => {
    let cancelled = false;
    setLoadingRecs(true);
    api.recordings().then((all) => {
      if (cancelled) return;
      const mine = all
        .filter((r) => r.sdr_id === sdr.id)
        .sort((a, b) => new Date(b.started_at).getTime() - new Date(a.started_at).getTime())
        .slice(0, 20);
      setRecordings(mine);
      setLoadingRecs(false);
    }).catch(() => {
      if (!cancelled) setLoadingRecs(false);
    });
    return () => { cancelled = true; };
  }, [sdr.id]);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
      {/* Header */}
      <div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.25rem' }}>
          <StatusDot status={status} />
          <span style={{ fontWeight: 700, fontSize: '1.5rem', color: tokens.color.textPrimary }}>
            {sdr.label || sdr.id}
          </span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', fontSize: '0.875rem' }}>
          <span style={{ fontFamily: tokens.font.mono, color: tokens.color.textSecondary }}>
            {sdr.driver}
          </span>
          <span style={{ color: statusLabel[status] === 'Active' ? tokens.color.liveGreen : tokens.color.textTertiary }}>
            {statusLabel[status]}
          </span>
        </div>
      </div>

      {/* Info rows */}
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'auto 1fr',
          gap: '0.375rem 1rem',
          fontSize: '0.8125rem',
        }}
      >
        {ks?.location && (
          <>
            <span style={{ color: tokens.color.textTertiary }}>Location</span>
            <span style={{ color: tokens.color.textSecondary }}>{ks.location}</span>
          </>
        )}
        {ks?.grid && (
          <>
            <span style={{ color: tokens.color.textTertiary }}>Grid</span>
            <span style={{ fontFamily: tokens.font.mono, color: tokens.color.textSecondary }}>{ks.grid}</span>
          </>
        )}
        {ks?.antenna && (
          <>
            <span style={{ color: tokens.color.textTertiary }}>Antenna</span>
            <span style={{ color: tokens.color.textSecondary }}>{ks.antenna}</span>
          </>
        )}
        {ks?.snr && (
          <>
            <span style={{ color: tokens.color.textTertiary }}>SNR</span>
            <span style={{ fontFamily: tokens.font.mono, color: tokens.color.textSecondary }}>{ks.snr}</span>
          </>
        )}
        {ks?.users !== undefined && ks?.users_max !== undefined && (
          <>
            <span style={{ color: tokens.color.textTertiary }}>Slots</span>
            <span style={{ fontFamily: tokens.font.mono, color: tokens.color.textSecondary }}>
              {ks.users} / {ks.users_max}
            </span>
          </>
        )}
      </div>

      {/* Capabilities */}
      <SectionTitle>Capabilities</SectionTitle>
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'auto 1fr',
          gap: '0.375rem 1rem',
          fontSize: '0.8125rem',
        }}
      >
        <span style={{ color: tokens.color.textTertiary }}>Frequency</span>
        <span style={{ fontFamily: tokens.font.mono, color: tokens.color.textSecondary }}>
          {formatFreqRange(caps.freq_range)}
        </span>
        <span style={{ color: tokens.color.textTertiary }}>Max BW</span>
        <span style={{ fontFamily: tokens.font.mono, color: tokens.color.textSecondary }}>
          {formatBandwidth(caps.max_bandwidth)}
        </span>
        {caps.sample_rates.length > 0 && (
          <>
            <span style={{ color: tokens.color.textTertiary }}>Sample rates</span>
            <span style={{ fontFamily: tokens.font.mono, color: tokens.color.textSecondary }}>
              {caps.sample_rates.map((r) => `${(r / 1e3).toFixed(0)}k`).join(', ')}
            </span>
          </>
        )}
        {caps.antennas.length > 0 && (
          <>
            <span style={{ color: tokens.color.textTertiary }}>Antennas</span>
            <span style={{ color: tokens.color.textSecondary }}>
              {caps.antennas.join(', ')}
            </span>
          </>
        )}
      </div>

      {/* Recordings */}
      <SectionTitle>Recent Recordings</SectionTitle>
      {loadingRecs && (
        <div style={{ fontSize: '0.8125rem', color: tokens.color.textTertiary }}>
          Loading recordings...
        </div>
      )}
      {!loadingRecs && recordings.length === 0 && (
        <div style={{ fontSize: '0.8125rem', color: tokens.color.textTertiary }}>
          No recordings from this SDR.
        </div>
      )}
      {recordings.length > 0 && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.375rem' }}>
          {recordings.map((rec) => {
            const band = frequencyToBand(rec.frequency);
            const isLive = rec.status === 'recording';
            return (
              <div
                key={rec.id}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '0.625rem',
                  padding: '0.5rem 0.625rem',
                  background: tokens.color.surface,
                  borderRadius: tokens.radius.sm,
                  fontSize: '0.8125rem',
                }}
              >
                {band && <BandBadge band={band} />}
                <span style={{ fontFamily: tokens.font.mono, color: tokens.color.textSecondary }}>
                  {formatFrequency(rec.frequency)} kHz
                </span>
                <span style={{ color: tokens.color.textTertiary, textTransform: 'uppercase', fontSize: '0.6875rem' }}>
                  {rec.mode}
                </span>
                <span style={{ marginLeft: 'auto', color: tokens.color.textTertiary, fontSize: '0.75rem' }}>
                  {isLive ? (
                    <span style={{ color: tokens.color.liveGreen, fontWeight: 600 }}>LIVE</span>
                  ) : (
                    formatTime(rec.started_at)
                  )}
                </span>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
