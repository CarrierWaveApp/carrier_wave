import { tokens } from '../styles/tokens';
import { BandBadge } from './BandBadge';
import { LiveDot } from './LiveDot';
import { SectionTitle } from './SectionTitle';
import { AudioPlayer } from './AudioPlayer';
import { TranscriptView } from './TranscriptView';
import { SpotContext } from './SpotContext';
import { SourceRecordingList } from './SourceRecordingList';
import type { Activation } from '../hooks/useActivations';
import type { RecordingResponse, RbnSpot } from '../api/types';

interface ActivationDetailProps {
  activation: Activation;
  recordingDetail: RecordingResponse | null;
  matchingRbnSpots: RbnSpot[];
  loading: boolean;
  error: string | null;
}

function formatFrequency(hz: number): string {
  return (hz / 1000).toFixed(1);
}

export function ActivationDetail({
  activation,
  recordingDetail,
  matchingRbnSpots,
  loading,
  error,
}: ActivationDetailProps) {
  const {
    callsign,
    frequency,
    band,
    parkRef,
    parkName,
    isLive,
    transcription,
    wpm,
    sdrCount,
    recordings,
    spot,
  } = activation;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
      {/* Header */}
      <div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.25rem' }}>
          {isLive && <LiveDot />}
          <span style={{ fontWeight: 700, fontSize: '1.5rem', color: tokens.color.textPrimary }}>
            {callsign}
          </span>
          <BandBadge band={band} size="md" />
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', fontSize: '0.875rem' }}>
          <span style={{ fontFamily: tokens.font.mono, color: tokens.color.textSecondary }}>
            {formatFrequency(frequency)} kHz
          </span>
          {parkRef && (
            <span style={{ color: tokens.color.accent }}>
              {parkRef}{parkName ? ` \u2014 ${parkName}` : ''}
            </span>
          )}
          <span style={{ color: tokens.color.textTertiary }}>
            {sdrCount} SDR{sdrCount !== 1 ? 's' : ''}
          </span>
        </div>
      </div>

      {/* Spectrogram placeholder */}
      <div
        style={{
          height: '80px',
          borderRadius: tokens.radius.sm,
          background: `linear-gradient(180deg, ${tokens.color.surface} 0%, rgba(111,177,247,0.08) 100%)`,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: '0.75rem',
          color: tokens.color.textTertiary,
        }}
      >
        Spectrogram — coming soon
      </div>

      {/* Audio */}
      {loading && (
        <div style={{ fontSize: '0.8125rem', color: tokens.color.textTertiary }}>
          Loading audio...
        </div>
      )}
      {error && (
        <div style={{ fontSize: '0.8125rem', color: '#f87171' }}>
          Failed to load recording: {error}
        </div>
      )}
      {recordingDetail && recordingDetail.segments.length > 0 && (
        <>
          <SectionTitle>Audio</SectionTitle>
          <AudioPlayer
            recordingId={recordingDetail.id}
            segments={recordingDetail.segments}
          />
        </>
      )}

      {/* Transcript */}
      {transcription && (
        <>
          <SectionTitle>Transcript</SectionTitle>
          <TranscriptView text={transcription.text} wpm={wpm ?? undefined} />
        </>
      )}

      {/* Spot context */}
      {(spot || matchingRbnSpots.length > 0) && (
        <>
          <SectionTitle>Spots</SectionTitle>
          <SpotContext potaSpot={spot} rbnSpots={matchingRbnSpots} />
        </>
      )}

      {/* Source recordings */}
      {recordings.length > 1 && (
        <>
          <SectionTitle>Source Recordings</SectionTitle>
          <SourceRecordingList recordings={recordings} />
        </>
      )}
    </div>
  );
}
