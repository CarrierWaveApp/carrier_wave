import { useState, useEffect, useRef } from 'react';
import { listBadges, uploadBadge, deleteBadge } from '../../api/client';
import type { Badge } from '../../types/challenge';

interface BadgeManagerProps {
  challengeId: string;
}

export default function BadgeManager({ challengeId }: BadgeManagerProps) {
  const [badges, setBadges] = useState<Badge[]>([]);
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState('');

  const [newBadgeName, setNewBadgeName] = useState('');
  const [newBadgeTierId, setNewBadgeTierId] = useState('');
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    loadBadges();
  }, [challengeId]);

  const loadBadges = async () => {
    try {
      setLoading(true);
      const data = await listBadges(challengeId);
      setBadges(data.badges);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load badges');
    } finally {
      setLoading(false);
    }
  };

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setSelectedFile(file);
    }
  };

  const handleUpload = async () => {
    if (!selectedFile || !newBadgeName) return;

    try {
      setUploading(true);
      setError('');
      const badge = await uploadBadge(
        challengeId,
        selectedFile,
        newBadgeName,
        newBadgeTierId || undefined
      );
      setBadges([...badges, badge]);
      setNewBadgeName('');
      setNewBadgeTierId('');
      setSelectedFile(null);
      if (fileInputRef.current) {
        fileInputRef.current.value = '';
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to upload badge');
    } finally {
      setUploading(false);
    }
  };

  const handleDelete = async (badge: Badge) => {
    if (!confirm(`Delete badge "${badge.name}"?`)) return;

    try {
      await deleteBadge(badge.id);
      setBadges(badges.filter((b) => b.id !== badge.id));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to delete badge');
    }
  };

  if (loading) {
    return <div className="text-gray-500">Loading badges...</div>;
  }

  return (
    <div className="space-y-6">
      {error && (
        <div className="rounded-md bg-red-50 p-4">
          <p className="text-sm text-red-800">{error}</p>
        </div>
      )}

      <div className="border rounded-md p-4">
        <h3 className="text-sm font-medium text-gray-900 mb-4">Upload New Badge</h3>
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700">Badge Name</label>
            <input
              type="text"
              value={newBadgeName}
              onChange={(e) => setNewBadgeName(e.target.value)}
              className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              placeholder="WAS Complete"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700">Tier ID (optional)</label>
            <input
              type="text"
              value={newBadgeTierId}
              onChange={(e) => setNewBadgeTierId(e.target.value)}
              className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              placeholder="tier-50"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700">Image</label>
            <input
              ref={fileInputRef}
              type="file"
              accept="image/png,image/jpeg,image/svg+xml"
              onChange={handleFileSelect}
              className="mt-1 block w-full text-sm text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded-md file:border-0 file:text-sm file:font-semibold file:bg-blue-50 file:text-blue-700 hover:file:bg-blue-100"
            />
            <p className="mt-1 text-xs text-gray-500">PNG, JPEG, or SVG. Max 1MB.</p>
          </div>

          {selectedFile && (
            <div className="flex items-center gap-4">
              <img
                src={URL.createObjectURL(selectedFile)}
                alt="Preview"
                className="w-16 h-16 object-contain border rounded"
              />
              <span className="text-sm text-gray-500">{selectedFile.name}</span>
            </div>
          )}

          <button
            type="button"
            onClick={handleUpload}
            disabled={!selectedFile || !newBadgeName || uploading}
            className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 disabled:opacity-50"
          >
            {uploading ? 'Uploading...' : 'Upload Badge'}
          </button>
        </div>
      </div>

      <div>
        <h3 className="text-sm font-medium text-gray-900 mb-4">Existing Badges</h3>
        {badges.length === 0 ? (
          <p className="text-sm text-gray-500 italic">No badges uploaded yet.</p>
        ) : (
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
            {badges.map((badge) => (
              <div key={badge.id} className="border rounded-md p-4 text-center">
                <img
                  src={badge.imageUrl || `/v1/badges/${badge.id}/image`}
                  alt={badge.name}
                  className="w-20 h-20 object-contain mx-auto mb-2"
                />
                <div className="font-medium text-sm">{badge.name}</div>
                {badge.tierId && (
                  <div className="text-xs text-gray-500">Tier: {badge.tierId}</div>
                )}
                <button
                  type="button"
                  onClick={() => handleDelete(badge)}
                  className="mt-2 text-xs text-red-600 hover:text-red-900"
                >
                  Delete
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
