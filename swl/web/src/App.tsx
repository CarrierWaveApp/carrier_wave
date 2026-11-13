import { useState, useMemo } from 'react';
import { TopNav } from './components/TopNav';
import { PageHeader } from './components/PageHeader';
import { CardGrid } from './components/CardGrid';
import { SDRCard } from './components/SDRCard';
import { ActivationCard } from './components/ActivationCard';
import { FilterBar } from './components/FilterBar';
import { ViewToggle } from './components/ViewToggle';
import { ActivationMap } from './components/ActivationMap';
import { CardSkeleton } from './components/CardSkeleton';
import { DetailOverlay } from './components/DetailOverlay';
import { ActivationDetail } from './components/ActivationDetail';
import { SpotTable } from './components/SpotTable';
import { SDRDetail } from './components/SDRDetail';
import { useSdrs } from './hooks/useSdrs';
import { useActivations } from './hooks/useActivations';
import { useActivationDetail } from './hooks/useActivationDetail';
import { useSpots } from './hooks/useSpots';
import { tokens } from './styles/tokens';

export function App() {
  const [activeTab, setActiveTab] = useState<'air' | 'sdrs' | 'spots' | 'search'>('air');
  const [activeView, setActiveView] = useState<'list' | 'map'>('list');
  const { sdrs, loading: sdrsLoading, error: sdrsError } = useSdrs();
  const {
    activations,
    allActivations,
    loading: activationsLoading,
    error: activationsError,
    favoriteCallsigns,
    toggleFavorite,
    bandFilters,
    toggleBandFilter,
    rbnSpots,
  } = useActivations();

  const [selectedActivationId, setSelectedActivationId] = useState<string | null>(null);
  const [selectedSdrId, setSelectedSdrId] = useState<string | null>(null);
  const selectedSdr = useMemo(
    () => sdrs.find((s) => s.id === selectedSdrId) ?? null,
    [sdrs, selectedSdrId],
  );

  const selectedActivation = useMemo(
    () => allActivations.find((a) => a.id === selectedActivationId) ?? null,
    [allActivations, selectedActivationId],
  );

  const { spots, availableBands: spotBands } = useSpots();

  const {
    recordingDetail,
    matchingRbnSpots,
    loading: detailLoading,
    error: detailError,
  } = useActivationDetail(selectedActivation, rbnSpots);

  const hasLive =
    activations.some((a) => a.isLive) ||
    sdrs.some(
      (s) =>
        s.kiwi_status &&
        !s.kiwi_status.offline &&
        s.kiwi_status.users !== undefined &&
        s.kiwi_status.users > 0,
    );

  // Available bands from all activations (not filtered)
  const availableBands = [...new Set(allActivations.map((a) => a.band))];

  return (
    <div style={{ minHeight: '100vh', background: tokens.color.bg }}>
      <TopNav activeTab={activeTab} onTabChange={setActiveTab} hasLive={hasLive} />

      {activeTab === 'air' && (
        <>
          <PageHeader
            title="On the Air"
            subtitle={
              activationsLoading
                ? 'Loading...'
                : `${activations.length} activation${activations.length !== 1 ? 's' : ''}`
            }
          />
          <FilterBar
            availableBands={availableBands}
            activeBands={bandFilters}
            onBandToggle={toggleBandFilter}
          >
            <ViewToggle value={activeView} onChange={setActiveView} />
          </FilterBar>
          {activationsError && (
            <div style={{ padding: '0.75rem 1.5rem', color: '#f87171', fontSize: '0.875rem' }}>
              Failed to load activations: {activationsError}
            </div>
          )}
          {activeView === 'list' && (
            <>
              {activationsLoading && activations.length === 0 && (
                <CardGrid minWidth="340px">
                  {Array.from({ length: 6 }, (_, i) => (
                    <CardSkeleton key={i} lines={4} />
                  ))}
                </CardGrid>
              )}
              <CardGrid minWidth="340px">
                {activations.map((act, i) => (
                  <ActivationCard
                    key={act.id}
                    activation={act}
                    isFavorited={favoriteCallsigns.includes(act.callsign)}
                    onFavoriteToggle={() => toggleFavorite(act.callsign)}
                    onClick={() => setSelectedActivationId(act.id)}
                    index={i}
                  />
                ))}
              </CardGrid>
              {!activationsLoading && activations.length === 0 && (
                <div
                  style={{
                    textAlign: 'center',
                    padding: '3rem 1.5rem',
                    color: tokens.color.textTertiary,
                    fontSize: '0.875rem',
                  }}
                >
                  No activations found. Start a recording or wait for spot data.
                </div>
              )}
            </>
          )}
          {activeView === 'map' && (
            <ActivationMap
              activations={activations}
              sdrs={sdrs}
              onActivationClick={setSelectedActivationId}
            />
          )}
        </>
      )}

      {activeTab === 'sdrs' && (
        <>
          <PageHeader
            title="SDRs"
            subtitle={
              sdrsLoading
                ? 'Loading...'
                : `${sdrs.length} receiver${sdrs.length !== 1 ? 's' : ''}`
            }
          />
          {sdrsError && (
            <div style={{ padding: '0.75rem 1.5rem', color: '#f87171', fontSize: '0.875rem' }}>
              Failed to load SDRs: {sdrsError}
            </div>
          )}
          {sdrsLoading && sdrs.length === 0 && (
            <CardGrid>
              {Array.from({ length: 4 }, (_, i) => (
                <CardSkeleton key={i} lines={3} />
              ))}
            </CardGrid>
          )}
          <CardGrid>
            {sdrs.map((sdr) => (
              <SDRCard key={sdr.id} sdr={sdr} onClick={() => setSelectedSdrId(sdr.id)} />
            ))}
          </CardGrid>
        </>
      )}

      {activeTab === 'spots' && (
        <>
          <PageHeader
            title="Spots"
            subtitle={`${spots.length} CW spot${spots.length !== 1 ? 's' : ''}`}
          />
          <FilterBar
            availableBands={spotBands}
            activeBands={bandFilters}
            onBandToggle={toggleBandFilter}
          />
          <SpotTable spots={spots} />
        </>
      )}

      {activeTab === 'search' && (
        <>
          <PageHeader title="Search" subtitle="Find callsigns, parks, and frequencies" />
          <div
            style={{
              textAlign: 'center',
              padding: '3rem 1.5rem',
              color: tokens.color.textTertiary,
              fontSize: '0.875rem',
            }}
          >
            Search coming soon.
          </div>
        </>
      )}

      {/* Detail overlay */}
      <DetailOverlay
        isOpen={selectedActivation !== null}
        onClose={() => setSelectedActivationId(null)}
      >
        {selectedActivation && (
          <ActivationDetail
            activation={selectedActivation}
            recordingDetail={recordingDetail}
            matchingRbnSpots={matchingRbnSpots}
            loading={detailLoading}
            error={detailError}
          />
        )}
      </DetailOverlay>

      {/* SDR detail overlay */}
      <DetailOverlay
        isOpen={selectedSdr !== null}
        onClose={() => setSelectedSdrId(null)}
      >
        {selectedSdr && <SDRDetail sdr={selectedSdr} />}
      </DetailOverlay>
    </div>
  );
}
