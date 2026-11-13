import { useMemo } from 'react';
import { MapContainer, TileLayer, CircleMarker, Popup } from 'react-leaflet';
import { tokens } from '../styles/tokens';
import { MapLegend } from './MapLegend';
import type { Activation } from '../hooks/useActivations';
import type { SdrInfo } from '../api/types';

interface ActivationMapProps {
  activations: Activation[];
  sdrs: SdrInfo[];
  onActivationClick: (id: string) => void;
}

interface MapActivation {
  activation: Activation;
  lat: number;
  lon: number;
}

interface MapSdr {
  sdr: SdrInfo;
  lat: number;
  lon: number;
}

function formatFrequency(hz: number): string {
  return (hz / 1000).toFixed(1);
}

export function ActivationMap({ activations, sdrs, onActivationClick }: ActivationMapProps) {
  // Build SDR coordinate index
  const sdrCoords = useMemo(() => {
    const map = new Map<string, { lat: number; lon: number }>();
    for (const sdr of sdrs) {
      const ks = sdr.kiwi_status;
      if (ks?.lat != null && ks?.lon != null) {
        map.set(sdr.id, { lat: ks.lat, lon: ks.lon });
      }
    }
    return map;
  }, [sdrs]);

  // Activations with coordinates (from their recording's SDR)
  const mapActivations: MapActivation[] = useMemo(() => {
    const result: MapActivation[] = [];
    for (const act of activations) {
      // Find first recording whose SDR has coordinates
      for (const rec of act.recordings) {
        const coords = sdrCoords.get(rec.sdr_id);
        if (coords) {
          result.push({ activation: act, ...coords });
          break;
        }
      }
    }
    return result;
  }, [activations, sdrCoords]);

  // SDRs with coordinates
  const mapSdrs: MapSdr[] = useMemo(() => {
    const result: MapSdr[] = [];
    for (const sdr of sdrs) {
      const coords = sdrCoords.get(sdr.id);
      if (coords) {
        result.push({ sdr, ...coords });
      }
    }
    return result;
  }, [sdrs, sdrCoords]);

  // Default center: US center, or first activation/SDR with coords
  const defaultCenter: [number, number] = useMemo(() => {
    if (mapActivations.length > 0) {
      return [mapActivations[0]!.lat, mapActivations[0]!.lon];
    }
    if (mapSdrs.length > 0) {
      return [mapSdrs[0]!.lat, mapSdrs[0]!.lon];
    }
    return [39.8, -98.5]; // Geographic center of US
  }, [mapActivations, mapSdrs]);

  return (
    <div className="map-container" style={{ position: 'relative', height: '500px', margin: '0 1.5rem', borderRadius: tokens.radius.md, overflow: 'hidden' }}>
      <MapContainer
        center={defaultCenter}
        zoom={4}
        style={{ height: '100%', width: '100%', background: tokens.color.surface }}
        scrollWheelZoom={true}
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png"
        />

        {/* SDR markers (gray diamonds -- rendered first so activations appear on top) */}
        {mapSdrs.map((ms) => (
          <CircleMarker
            key={`sdr-${ms.sdr.id}`}
            center={[ms.lat, ms.lon]}
            radius={5}
            pathOptions={{
              color: tokens.color.textTertiary,
              fillColor: tokens.color.textTertiary,
              fillOpacity: 0.6,
              weight: 1,
            }}
          >
            <Popup>
              <div style={{ fontFamily: tokens.font.sans, fontSize: '0.8125rem' }}>
                <strong>{ms.sdr.label || ms.sdr.id}</strong>
                <br />
                {ms.sdr.kiwi_status?.location ?? ms.sdr.driver}
              </div>
            </Popup>
          </CircleMarker>
        ))}

        {/* Activation markers (band-colored circles) */}
        {mapActivations.map((ma) => {
          const color = tokens.band[ma.activation.band] ?? tokens.color.accent;
          return (
            <CircleMarker
              key={`act-${ma.activation.id}`}
              center={[ma.lat, ma.lon]}
              radius={ma.activation.isLive ? 8 : 6}
              pathOptions={{
                color,
                fillColor: color,
                fillOpacity: 0.7,
                weight: ma.activation.isLive ? 2 : 1,
              }}
              eventHandlers={{
                click: () => onActivationClick(ma.activation.id),
              }}
            >
              <Popup>
                <div style={{ fontFamily: tokens.font.sans, fontSize: '0.8125rem' }}>
                  <strong>{ma.activation.callsign}</strong>{' '}
                  <span style={{ fontFamily: tokens.font.mono }}>
                    {formatFrequency(ma.activation.frequency)} kHz
                  </span>
                  <br />
                  {ma.activation.band}
                  {ma.activation.parkRef && ` — ${ma.activation.parkRef}`}
                </div>
              </Popup>
            </CircleMarker>
          );
        })}
      </MapContainer>

      <MapLegend />
    </div>
  );
}
