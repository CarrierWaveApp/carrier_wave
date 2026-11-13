import { useEffect, useState } from 'react';
import {
  AchievementCatalogEntry,
  UserAchievementAward,
  listAchievements,
  listUserAchievements,
  awardAchievement,
  revokeAchievement,
  batchAwardAchievement,
  backfillAchievements,
} from '../api/client';

export default function AchievementsAdmin() {
  const [catalog, setCatalog] = useState<AchievementCatalogEntry[]>([]);
  const [selectedID, setSelectedID] = useState<string>('');
  const [callsign, setCallsign] = useState<string>('');
  const [callsignAwards, setCallsignAwards] = useState<UserAchievementAward[] | null>(null);
  const [batchInput, setBatchInput] = useState<string>('');
  const [batchAchievement, setBatchAchievement] = useState<string>('beta-tester');
  const [statusMessage, setStatusMessage] = useState<string>('');
  const [error, setError] = useState<string>('');

  useEffect(() => {
    listAchievements()
      .then((res) => {
        setCatalog(res.achievements);
        if (res.achievements.length > 0) {
          setSelectedID(res.achievements[0].id);
        }
      })
      .catch((err) => setError(err.message));
  }, []);

  async function refreshAwards(call: string) {
    if (!call.trim()) {
      setCallsignAwards(null);
      return;
    }
    try {
      const res = await listUserAchievements(call.trim().toUpperCase());
      setCallsignAwards(res.awards);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  async function handleAward() {
    setError('');
    if (!callsign.trim() || !selectedID) {
      return;
    }
    try {
      await awardAchievement(selectedID, callsign.trim().toUpperCase());
      setStatusMessage(`Awarded ${selectedID} to ${callsign.toUpperCase()}`);
      await refreshAwards(callsign);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  async function handleRevoke(achievementId: string) {
    setError('');
    if (!callsign.trim()) {
      return;
    }
    try {
      await revokeAchievement(achievementId, callsign.trim().toUpperCase());
      setStatusMessage(`Revoked ${achievementId} from ${callsign.toUpperCase()}`);
      await refreshAwards(callsign);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  async function handleBatch() {
    setError('');
    const callsigns = batchInput
      .split(/[\s,]+/)
      .map((cs) => cs.trim().toUpperCase())
      .filter(Boolean);
    if (!callsigns.length) {
      return;
    }
    try {
      const res = await batchAwardAchievement(batchAchievement, callsigns, 'admin-batch');
      setStatusMessage(`Awarded ${res.awarded} (skipped ${res.skipped.length})`);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  async function handleBackfill() {
    setError('');
    setStatusMessage('Running backfill...');
    try {
      const res = await backfillAchievements();
      setStatusMessage(`Backfill processed ${res.callsignsProcessed} callsigns`);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  return (
    <div className="px-4 sm:px-0">
      <h1 className="text-2xl font-bold mb-4">Achievements</h1>

      {statusMessage && (
        <div className="mb-4 px-3 py-2 bg-green-50 text-green-700 rounded">{statusMessage}</div>
      )}
      {error && (
        <div className="mb-4 px-3 py-2 bg-red-50 text-red-700 rounded">{error}</div>
      )}

      <section className="mb-8 bg-white shadow rounded p-4">
        <h2 className="text-lg font-semibold mb-3">Catalog</h2>
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b">
                <th className="text-left py-2 pr-4">ID</th>
                <th className="text-left py-2 pr-4">Name</th>
                <th className="text-left py-2 pr-4">Category</th>
                <th className="text-left py-2 pr-4">Tier</th>
                <th className="text-left py-2 pr-4">Method</th>
                <th className="text-left py-2 pr-4">Secret</th>
              </tr>
            </thead>
            <tbody>
              {catalog.map((entry) => (
                <tr key={entry.id} className="border-b">
                  <td className="py-2 pr-4 font-mono">{entry.id}</td>
                  <td className="py-2 pr-4">{entry.name}</td>
                  <td className="py-2 pr-4">{entry.category}</td>
                  <td className="py-2 pr-4">{entry.tier ?? '—'}</td>
                  <td className="py-2 pr-4">{entry.awardMethod}</td>
                  <td className="py-2 pr-4">{entry.secret ? 'yes' : 'no'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="mb-8 bg-white shadow rounded p-4">
        <h2 className="text-lg font-semibold mb-3">Award / revoke</h2>
        <div className="flex gap-2 items-end mb-3">
          <div>
            <label className="block text-xs text-gray-500">Callsign</label>
            <input
              type="text"
              className="border rounded px-2 py-1"
              value={callsign}
              onChange={(event) => setCallsign(event.target.value.toUpperCase())}
              onBlur={() => refreshAwards(callsign)}
              placeholder="W6JY"
            />
          </div>
          <div>
            <label className="block text-xs text-gray-500">Achievement</label>
            <select
              className="border rounded px-2 py-1"
              value={selectedID}
              onChange={(event) => setSelectedID(event.target.value)}
            >
              {catalog.map((entry) => (
                <option key={entry.id} value={entry.id}>
                  {entry.name} ({entry.id})
                </option>
              ))}
            </select>
          </div>
          <button
            onClick={handleAward}
            className="bg-blue-600 text-white px-3 py-1 rounded hover:bg-blue-700"
          >
            Award
          </button>
        </div>

        {callsignAwards && (
          <div>
            <h3 className="text-sm font-semibold mb-2">Current awards for {callsign.toUpperCase()}</h3>
            {callsignAwards.length === 0 ? (
              <p className="text-sm text-gray-500">No awards.</p>
            ) : (
              <ul className="text-sm space-y-1">
                {callsignAwards.map((award) => (
                  <li key={award.id} className="flex items-center gap-2">
                    <span className="font-mono">{award.achievementId}</span>
                    <span className="text-gray-500">{award.awardedAt}</span>
                    <button
                      onClick={() => handleRevoke(award.achievementId)}
                      className="text-red-600 hover:underline"
                    >
                      revoke
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}
      </section>

      <section className="mb-8 bg-white shadow rounded p-4">
        <h2 className="text-lg font-semibold mb-3">Batch award</h2>
        <div className="flex flex-col gap-2">
          <select
            className="border rounded px-2 py-1 w-64"
            value={batchAchievement}
            onChange={(event) => setBatchAchievement(event.target.value)}
          >
            {catalog.map((entry) => (
              <option key={entry.id} value={entry.id}>
                {entry.name} ({entry.id})
              </option>
            ))}
          </select>
          <textarea
            className="border rounded px-2 py-1 font-mono text-sm h-32"
            placeholder="W6JY, N9HO, AB1CDE …"
            value={batchInput}
            onChange={(event) => setBatchInput(event.target.value)}
          />
          <button
            onClick={handleBatch}
            className="bg-blue-600 text-white px-3 py-1 rounded hover:bg-blue-700 self-start"
          >
            Award batch
          </button>
        </div>
      </section>

      <section className="bg-white shadow rounded p-4">
        <h2 className="text-lg font-semibold mb-3">Maintenance</h2>
        <p className="text-sm text-gray-500 mb-2">
          Re-runs every batch evaluator against every callsign with activity. Idempotent.
        </p>
        <button
          onClick={handleBackfill}
          className="bg-gray-700 text-white px-3 py-1 rounded hover:bg-gray-800"
        >
          Run backfill
        </button>
      </section>
    </div>
  );
}
