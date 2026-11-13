import type {
  SdrListResponse,
  HealthResponse,
  RecordingRow,
  RecordingResponse,
  TranscriptionResponse,
} from './types';

const BASE = '/api/v1';

async function get<T>(path: string): Promise<T> {
  const res = await fetch(`${BASE}${path}`);
  if (!res.ok) {
    throw new Error(`API ${res.status}: ${path}`);
  }
  return res.json() as Promise<T>;
}

export const api = {
  health: () => get<HealthResponse>('/health'),
  sdrs: () => get<SdrListResponse>('/sdrs'),
  recordings: () => get<RecordingRow[]>('/recordings'),
  recording: (id: string) => get<RecordingResponse>(`/recordings/${id}`),
  transcriptions: () => get<TranscriptionResponse[]>('/transcriptions'),
};
