// Shared Leaflet map for the Spots page: plots spots (band-colored circles,
// at spotter-grid centers) and a listen session's ranked receivers (squares
// colored by hearing likelihood). Used full-size as the table's map view and
// compact inside the listen panel's receiver picker.

import { useEffect } from 'react';
import L from 'leaflet';
import { MapContainer, Marker, TileLayer, Tooltip, useMap } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import { bandColor } from '../logbook/bandColors';
import { bandFromKhz } from '../spots/spotsClient';
import {
  BUCKET_COLORS,
  BUCKET_LABELS,
  likelihoodBucket,
  type LikelihoodBucket,
} from '../spots/likelihood';
import type { KiwiReceiver, Spot } from '../spots/types';

export interface MappedSpot {
  spot: Spot;
  lat: number;
  lon: number;
}

interface SpotsMapProps {
  spots?: MappedSpot[];
  /** Spot the open listen session belongs to (highlighted; receivers overlay it). */
  activeSpot?: MappedSpot | null;
  receivers?: KiwiReceiver[];
  selectedReceiverId?: string | null;
  onSpotClick?: (spot: Spot) => void;
  onReceiverClick?: (receiver: KiwiReceiver) => void;
  compact?: boolean;
}

const TILE_URL = 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
const TILE_ATTRIBUTION =
  '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/attributions">CARTO</a>';

export default function SpotsMap({
  spots = [],
  activeSpot = null,
  receivers = [],
  selectedReceiverId = null,
  onSpotClick,
  onReceiverClick,
  compact = false,
}: SpotsMapProps) {
  return (
    // z-0 pins Leaflet's internal panes (z-index up to ~700) under the
    // page's fixed listen panel.
    <div
      className={`relative z-0 overflow-hidden rounded-xl border border-cw-border ${
        compact ? 'h-56' : 'h-[32rem]'
      }`}
    >
      <MapContainer
        center={[30, 0]}
        zoom={2}
        minZoom={2}
        worldCopyJump
        className="h-full w-full bg-cw-bg"
        attributionControl={!compact}
      >
        <TileLayer url={TILE_URL} attribution={TILE_ATTRIBUTION} />
        <FitToContent spots={spots} activeSpot={activeSpot} receivers={receivers} />

        {spots.map(({ spot, lat, lon }) => (
          <Marker
            key={spot.id}
            position={[lat, lon]}
            icon={spotIcon(spot, spot.id === activeSpot?.spot.id)}
            eventHandlers={onSpotClick ? { click: () => onSpotClick(spot) } : undefined}
          >
            <Tooltip direction="top" offset={[0, -8]}>
              <span className="font-mono font-semibold">{spot.callsign}</span>{' '}
              {(spot.frequencyKhz / 1000).toFixed(3)} MHz {spot.mode}
              {spot.reference ? ` · ${spot.reference}` : ''}
            </Tooltip>
          </Marker>
        ))}

        {receivers.map((receiver) => {
          const bucket = likelihoodBucket(receiver);
          return (
            <Marker
              key={receiver.id}
              position={[receiver.latitude, receiver.longitude]}
              icon={receiverIcon(bucket, receiver.id === selectedReceiverId)}
              eventHandlers={
                onReceiverClick ? { click: () => onReceiverClick(receiver) } : undefined
              }
            >
              <Tooltip direction="top" offset={[0, -8]}>
                <span className="font-semibold">{receiver.name || receiver.host}</span>
                <br />
                {receiver.location}
                {receiver.distanceKm !== undefined &&
                  ` · ${Math.round(receiver.distanceKm)} km`}
                {receiver.snrHf !== undefined && ` · SNR ${receiver.snrHf} dB`}
                <br />
                {receiver.users}/{receiver.maxUsers} users · {BUCKET_LABELS[bucket]}
              </Tooltip>
            </Marker>
          );
        })}
      </MapContainer>

      {receivers.length > 0 && <ReceiverLegend />}
    </div>
  );
}

/**
 * Keeps the view framing its content: all spots when browsing, the active
 * spot plus its receivers once a listen session opens.
 */
function FitToContent({
  spots,
  activeSpot,
  receivers,
}: {
  spots: MappedSpot[];
  activeSpot: MappedSpot | null;
  receivers: KiwiReceiver[];
}) {
  const map = useMap();

  // Distinguishes "session receivers arrived/changed" from marker churn on
  // the 60 s spots refresh, so the refresh never yanks the view around.
  const sessionKey =
    activeSpot || receivers.length > 0
      ? `${activeSpot?.spot.id ?? 'none'}:${receivers.map((r) => r.id).join(',')}`
      : '';
  const browseKey = spots.length > 0 ? 'spots' : 'empty';

  useEffect(() => {
    const receiverPoints = receivers.map((r): [number, number] => [r.latitude, r.longitude]);
    const points: Array<[number, number]> = activeSpot
      ? [[activeSpot.lat, activeSpot.lon], ...receiverPoints]
      : receiverPoints.length > 0
        ? receiverPoints
        : spots.map(({ lat, lon }): [number, number] => [lat, lon]);
    if (points.length === 0) return;
    map.fitBounds(L.latLngBounds(points), { padding: [40, 40], maxZoom: 8 });
    // Refit only when the session or first spot load changes — not every render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [map, sessionKey, browseKey]);

  return null;
}

function spotIcon(spot: Spot, active: boolean): L.DivIcon {
  const band = bandFromKhz(spot.frequencyKhz);
  const color = band ? bandColor(band) : '#c9cdd6';
  const ring = active ? 'box-shadow: 0 0 0 3px #4a8cff;' : '';
  return L.divIcon({
    className: '',
    html: `<div style="width:14px;height:14px;border-radius:9999px;background:${color};border:2px solid #0e0f11;${ring}cursor:pointer;"></div>`,
    iconSize: [14, 14],
    iconAnchor: [7, 7],
  });
}

function receiverIcon(bucket: LikelihoodBucket, selected: boolean): L.DivIcon {
  const color = BUCKET_COLORS[bucket];
  const dim = bucket === 'unusable' ? 'opacity:0.65;' : '';
  const ring = selected ? 'box-shadow: 0 0 0 3px #4a8cff;' : '';
  return L.divIcon({
    className: '',
    html: `<div style="width:12px;height:12px;border-radius:3px;background:${color};border:2px solid #0e0f11;${dim}${ring}cursor:pointer;"></div>`,
    iconSize: [12, 12],
    iconAnchor: [6, 6],
  });
}

function ReceiverLegend() {
  const buckets: LikelihoodBucket[] = ['good', 'fair', 'weak', 'unusable'];
  return (
    <div className="pointer-events-none absolute bottom-2 left-2 z-10 rounded-lg border border-cw-border bg-cw-surface/90 px-2.5 py-1.5 backdrop-blur">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
        {buckets.map((bucket) => (
          <span key={bucket} className="flex items-center gap-1.5 text-[0.65rem] text-cw-dim">
            <span
              className="inline-block h-2 w-2 rounded-sm"
              style={{ backgroundColor: BUCKET_COLORS[bucket] }}
            />
            {BUCKET_LABELS[bucket]}
          </span>
        ))}
      </div>
    </div>
  );
}
