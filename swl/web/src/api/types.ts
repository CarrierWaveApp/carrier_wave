export interface SdrCapabilities {
  sample_rates: number[];
  freq_range: [number, number];
  max_bandwidth: number;
  antennas: string[];
  has_agc: boolean;
}

export interface KiwiStatus {
  users?: number;
  users_max?: number;
  grid?: string;
  snr?: string;
  antenna?: string;
  location?: string;
  lat?: number;
  lon?: number;
  offline?: boolean;
}

export interface SdrInfo {
  id: string;
  driver: string;
  label?: string;
  serial?: string;
  capabilities: SdrCapabilities;
  kiwi_status?: KiwiStatus;
}

export interface SdrListResponse {
  sdrs: SdrInfo[];
}

export interface HealthResponse {
  status: string;
  version: string;
}

export interface RecordingRow {
  id: string;
  capture_id: string | null;
  sdr_id: string;
  frequency: number;
  bandwidth: number;
  mode: string;
  status: string;           // "recording" | "stopped" | "combined"
  started_at: string;
  stopped_at: string | null;
  retention_days: number;
  created_at: string;
}

export interface TranscriptionResponse {
  id: string;
  recording_id: string;
  text: string;
  status: string;           // "completed" | "failed"
  wpm_estimate: number | null;
  char_count: number;
  error_message: string | null;
}

export interface SegmentRow {
  id: string;
  recording_id: string;
  segment_number: number;
  file_path: string;
  duration_secs: number;
  file_size_bytes: number;
  sample_rate: number;
  started_at: string;
  ended_at: string;
  created_at: string;
}

export interface RecordingResponse {
  id: string;
  capture_id: string | null;
  sdr_id: string;
  frequency: number;
  bandwidth: number;
  mode: string;
  status: string;
  started_at: string;
  stopped_at: string | null;
  retention_days: number;
  created_at: string;
  segments: SegmentRow[];
}

export interface PotaSpot {
  activator: string;          // callsign, e.g., "WA9AGG"
  frequency: string;          // e.g., "7030.0"
  mode: string;               // e.g., "CW"
  reference: string;          // park ref, e.g., "K-1234"
  parkName: string | null;    // e.g., "Yellowstone NP"; null on the rebuilt POTA API (2026-10)
  name?: string | null;       // park name as served by the rebuilt POTA API
  spotTime: string;           // ISO timestamp
  spotter: string;
  comments: string;
}

export interface RbnSpot {
  callsign: string;
  frequency: number;          // kHz
  snr: number;
  wpm: number;
  mode: string;
  spotter_callsign: string;
  timestamp: string;
}
