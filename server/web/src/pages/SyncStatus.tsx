import { useState, useEffect } from 'react';
import { authHeaders, handleResponse } from '../api/client';

const API_BASE = '/v1';

interface BoundaryCountryStat {
  totalParks: number;
}

interface BoundaryStatus {
  totalParks: number;
  totalCached: number;
  unfetched: number;
  completionPercentage: number;
  byCountry: {
    us: BoundaryCountryStat;
    uk: BoundaryCountryStat;
    it: BoundaryCountryStat;
    pl: BoundaryCountryStat;
  };
  exactMatches: number;
  spatialMatches: number;
  manualMatches: number;
  oldestFetch: string | null;
  newestFetch: string | null;
}

interface TrailStatus {
  totalCatalog: number;
  totalCached: number;
  unfetched: number;
  completionPercentage: number;
  exactMatches: number;
  spatialMatches: number;
  manualMatches: number;
  oldestFetch: string | null;
  newestFetch: string | null;
}

async function getBoundaryStatus(): Promise<BoundaryStatus> {
  const response = await fetch(`${API_BASE}/parks/boundaries/status`, {
    headers: authHeaders(),
  });
  return handleResponse(response);
}

async function getTrailStatus(): Promise<TrailStatus> {
  const response = await fetch(`${API_BASE}/trails/status`, {
    headers: authHeaders(),
  });
  return handleResponse(response);
}

function formatDate(iso: string | null): string {
  if (!iso) return 'Never';
  return new Date(iso).toLocaleString();
}

function ProgressBar({ percentage }: { percentage: number }) {
  const color =
    percentage === 100
      ? 'bg-green-500'
      : percentage >= 75
        ? 'bg-blue-500'
        : percentage >= 50
          ? 'bg-yellow-500'
          : 'bg-red-500';

  return (
    <div className="w-full bg-gray-200 rounded-full h-4">
      <div
        className={`${color} h-4 rounded-full transition-all`}
        style={{ width: `${percentage}%` }}
      />
    </div>
  );
}

export default function SyncStatus() {
  const [boundaryStatus, setBoundaryStatus] = useState<BoundaryStatus | null>(null);
  const [trailStatus, setTrailStatus] = useState<TrailStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    loadStatus();
  }, []);

  const loadStatus = async () => {
    try {
      setLoading(true);
      setError('');
      const [boundaries, trails] = await Promise.all([
        getBoundaryStatus(),
        getTrailStatus(),
      ]);
      setBoundaryStatus(boundaries);
      setTrailStatus(trails);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load status');
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="flex justify-center items-center h-64">
        <div className="text-gray-500">Loading...</div>
      </div>
    );
  }

  return (
    <div>
      <div className="sm:flex sm:items-center">
        <div className="sm:flex-auto">
          <h1 className="text-2xl font-semibold text-gray-900">Sync Status</h1>
          <p className="mt-2 text-sm text-gray-700">
            Park boundary and historic trail sync progress.
          </p>
        </div>
        <div className="mt-4 sm:mt-0 sm:ml-16 sm:flex-none">
          <button
            onClick={loadStatus}
            className="inline-flex items-center justify-center rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50"
          >
            Refresh
          </button>
        </div>
      </div>

      {error && (
        <div className="mt-4 rounded-md bg-red-50 p-4">
          <p className="text-sm text-red-800">{error}</p>
        </div>
      )}

      {boundaryStatus && (
        <div className="mt-8">
          <h2 className="text-lg font-medium text-gray-900">Park Boundaries</h2>
          <div className="mt-4 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard
              label="Total Parks"
              value={boundaryStatus.totalParks.toLocaleString()}
            />
            <StatCard
              label="Cached"
              value={boundaryStatus.totalCached.toLocaleString()}
            />
            <StatCard
              label="Unfetched"
              value={boundaryStatus.unfetched.toLocaleString()}
            />
            <StatCard
              label="Completion"
              value={`${boundaryStatus.completionPercentage}%`}
            />
          </div>

          <div className="mt-4">
            <ProgressBar percentage={boundaryStatus.completionPercentage} />
          </div>

          <h3 className="mt-6 text-sm font-medium text-gray-900">Parks by Country</h3>
          <div className="mt-2 overflow-hidden shadow ring-1 ring-black ring-opacity-5 md:rounded-lg">
            <table className="min-w-full divide-y divide-gray-300">
              <thead className="bg-gray-50">
                <tr>
                  <th className="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 sm:pl-6">Country</th>
                  <th className="px-3 py-3.5 text-right text-sm font-semibold text-gray-900">Total Parks</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200 bg-white">
                <CountryRow label="United States" value={boundaryStatus.byCountry.us.totalParks} />
                <CountryRow label="United Kingdom" value={boundaryStatus.byCountry.uk.totalParks} />
                <CountryRow label="Italy" value={boundaryStatus.byCountry.it.totalParks} />
                <CountryRow label="Poland" value={boundaryStatus.byCountry.pl.totalParks} />
              </tbody>
            </table>
          </div>

          <h3 className="mt-6 text-sm font-medium text-gray-900">Match Quality</h3>
          <div className="mt-2 grid grid-cols-1 gap-5 sm:grid-cols-3">
            <StatCard label="Exact" value={boundaryStatus.exactMatches.toLocaleString()} />
            <StatCard label="Spatial" value={boundaryStatus.spatialMatches.toLocaleString()} />
            <StatCard label="Manual" value={boundaryStatus.manualMatches.toLocaleString()} />
          </div>

          <div className="mt-4 text-sm text-gray-500">
            <span>Oldest fetch: {formatDate(boundaryStatus.oldestFetch)}</span>
            <span className="ml-6">Newest fetch: {formatDate(boundaryStatus.newestFetch)}</span>
          </div>
        </div>
      )}

      {trailStatus && (
        <div className="mt-10">
          <h2 className="text-lg font-medium text-gray-900">Historic Trails</h2>
          <div className="mt-4 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard
              label="Total Catalog"
              value={trailStatus.totalCatalog.toLocaleString()}
            />
            <StatCard
              label="Cached"
              value={trailStatus.totalCached.toLocaleString()}
            />
            <StatCard
              label="Unfetched"
              value={trailStatus.unfetched.toLocaleString()}
            />
            <StatCard
              label="Completion"
              value={`${trailStatus.completionPercentage}%`}
            />
          </div>

          <div className="mt-4">
            <ProgressBar percentage={trailStatus.completionPercentage} />
          </div>

          <h3 className="mt-6 text-sm font-medium text-gray-900">Match Quality</h3>
          <div className="mt-2 grid grid-cols-1 gap-5 sm:grid-cols-3">
            <StatCard label="Exact" value={trailStatus.exactMatches.toLocaleString()} />
            <StatCard label="Spatial" value={trailStatus.spatialMatches.toLocaleString()} />
            <StatCard label="Manual" value={trailStatus.manualMatches.toLocaleString()} />
          </div>

          <div className="mt-4 text-sm text-gray-500">
            <span>Oldest fetch: {formatDate(trailStatus.oldestFetch)}</span>
            <span className="ml-6">Newest fetch: {formatDate(trailStatus.newestFetch)}</span>
          </div>
        </div>
      )}
    </div>
  );
}

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="overflow-hidden rounded-lg bg-white px-4 py-5 shadow ring-1 ring-black ring-opacity-5">
      <dt className="truncate text-sm font-medium text-gray-500">{label}</dt>
      <dd className="mt-1 text-2xl font-semibold text-gray-900">{value}</dd>
    </div>
  );
}

function CountryRow({ label, value }: { label: string; value: number }) {
  return (
    <tr>
      <td className="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium text-gray-900 sm:pl-6">
        {label}
      </td>
      <td className="whitespace-nowrap px-3 py-4 text-sm text-gray-500 text-right">
        {value.toLocaleString()}
      </td>
    </tr>
  );
}
