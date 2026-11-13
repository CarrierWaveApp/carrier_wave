import { useEffect, useState } from 'react';
import { api } from '../api/client';
import type { RecordingResponse, RbnSpot } from '../api/types';
import type { Activation } from './useActivations';

interface ActivationDetailData {
  recordingDetail: RecordingResponse | null;
  matchingRbnSpots: RbnSpot[];
  loading: boolean;
  error: string | null;
}

export function useActivationDetail(
  activation: Activation | null,
  rbnSpots: RbnSpot[],
): ActivationDetailData {
  const [recordingDetail, setRecordingDetail] = useState<RecordingResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const recordingId = activation?.combinedRecordingId ?? activation?.recordings[0]?.id;

  useEffect(() => {
    if (!recordingId) {
      setRecordingDetail(null);
      return;
    }

    setLoading(true);
    setError(null);
    api
      .recording(recordingId)
      .then((data) => {
        setRecordingDetail(data);
        setLoading(false);
      })
      .catch((e) => {
        setError((e as Error).message);
        setLoading(false);
      });
  }, [recordingId]);

  const matchingRbnSpots = activation
    ? rbnSpots.filter(
        (s) =>
          s.callsign === activation.callsign &&
          Math.abs(s.frequency * 1000 - activation.frequency) <= 1000,
      )
    : [];

  return { recordingDetail, matchingRbnSpots, loading, error };
}
