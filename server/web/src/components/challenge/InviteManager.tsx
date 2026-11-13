import { useState, useEffect } from 'react';
import { listInvites, generateInvite, revokeInvite } from '../../api/client';
import type { Invite } from '../../types/challenge';

interface InviteManagerProps {
  challengeId: string;
}

export default function InviteManager({ challengeId }: InviteManagerProps) {
  const [invites, setInvites] = useState<Invite[]>([]);
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState(false);
  const [error, setError] = useState('');

  const [maxUses, setMaxUses] = useState<string>('');
  const [expiresAt, setExpiresAt] = useState('');

  useEffect(() => {
    loadInvites();
  }, [challengeId]);

  const loadInvites = async () => {
    try {
      setLoading(true);
      const data = await listInvites(challengeId);
      setInvites(data.invites);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load invites');
    } finally {
      setLoading(false);
    }
  };

  const handleGenerate = async () => {
    try {
      setGenerating(true);
      setError('');
      const invite = await generateInvite(
        challengeId,
        maxUses ? parseInt(maxUses) : undefined,
        expiresAt || undefined
      );
      setInvites([invite, ...invites]);
      setMaxUses('');
      setExpiresAt('');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to generate invite');
    } finally {
      setGenerating(false);
    }
  };

  const handleRevoke = async (invite: Invite) => {
    if (!confirm('Revoke this invite? It will no longer be usable.')) return;

    try {
      await revokeInvite(invite.token);
      setInvites(invites.filter((i) => i.token !== invite.token));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to revoke invite');
    }
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
  };

  const formatDate = (dateStr: string) => {
    return new Date(dateStr).toLocaleString();
  };

  if (loading) {
    return <div className="text-gray-500">Loading invites...</div>;
  }

  return (
    <div className="space-y-6">
      {error && (
        <div className="rounded-md bg-red-50 p-4">
          <p className="text-sm text-red-800">{error}</p>
        </div>
      )}

      <div className="border rounded-md p-4">
        <h3 className="text-sm font-medium text-gray-900 mb-4">Generate New Invite</h3>
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700">Max Uses (optional)</label>
              <input
                type="number"
                value={maxUses}
                onChange={(e) => setMaxUses(e.target.value)}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                placeholder="Unlimited"
                min="1"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700">Expires At (optional)</label>
              <input
                type="datetime-local"
                value={expiresAt}
                onChange={(e) => setExpiresAt(e.target.value)}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
          </div>

          <button
            type="button"
            onClick={handleGenerate}
            disabled={generating}
            className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 disabled:opacity-50"
          >
            {generating ? 'Generating...' : 'Generate Invite'}
          </button>
        </div>
      </div>

      <div>
        <h3 className="text-sm font-medium text-gray-900 mb-4">Existing Invites</h3>
        {invites.length === 0 ? (
          <p className="text-sm text-gray-500 italic">No invites created yet.</p>
        ) : (
          <div className="overflow-hidden shadow ring-1 ring-black ring-opacity-5 rounded-lg">
            <table className="min-w-full divide-y divide-gray-300">
              <thead className="bg-gray-50">
                <tr>
                  <th className="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900">Token</th>
                  <th className="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Uses</th>
                  <th className="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Expires</th>
                  <th className="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Created</th>
                  <th className="relative py-3.5 pl-3 pr-4"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200 bg-white">
                {invites.map((invite) => (
                  <tr key={invite.token}>
                    <td className="whitespace-nowrap py-4 pl-4 pr-3 text-sm">
                      <div className="flex items-center gap-2">
                        <code className="text-xs bg-gray-100 px-2 py-1 rounded">
                          {invite.token.slice(0, 20)}...
                        </code>
                        <button
                          type="button"
                          onClick={() => copyToClipboard(invite.url || invite.token)}
                          className="text-blue-600 hover:text-blue-800 text-xs"
                        >
                          Copy
                        </button>
                      </div>
                    </td>
                    <td className="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                      {invite.useCount} / {invite.maxUses ?? '∞'}
                    </td>
                    <td className="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                      {invite.expiresAt ? formatDate(invite.expiresAt) : 'Never'}
                    </td>
                    <td className="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                      {formatDate(invite.createdAt)}
                    </td>
                    <td className="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium">
                      <button
                        type="button"
                        onClick={() => handleRevoke(invite)}
                        className="text-red-600 hover:text-red-900"
                      >
                        Revoke
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
