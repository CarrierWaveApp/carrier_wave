import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { getProgram, createProgram, updateProgram } from '../api/client';
import type { Program } from '../types/program';

interface FormData {
  slug: string;
  name: string;
  shortName: string;
  icon: string;
  iconUrl: string;
  website: string;
  serverBaseUrl: string;
  referenceLabel: string;
  referenceFormat: string;
  referenceExample: string;
  multiRefAllowed: boolean;
  activationThreshold: string;
  supportsRove: boolean;
  capabilities: string;
  adifMySig: string;
  adifMySigInfo: string;
  adifSigField: string;
  adifSigInfoField: string;
  dataEntryLabel: string;
  dataEntryPlaceholder: string;
  dataEntryFormat: string;
  sortOrder: number;
  isActive: boolean;
}

const defaultValues: FormData = {
  slug: '',
  name: '',
  shortName: '',
  icon: '',
  iconUrl: '',
  website: '',
  serverBaseUrl: '',
  referenceLabel: '',
  referenceFormat: '',
  referenceExample: '',
  multiRefAllowed: false,
  activationThreshold: '',
  supportsRove: false,
  capabilities: '',
  adifMySig: '',
  adifMySigInfo: '',
  adifSigField: '',
  adifSigInfoField: '',
  dataEntryLabel: '',
  dataEntryPlaceholder: '',
  dataEntryFormat: '',
  sortOrder: 0,
  isActive: true,
};

function programToForm(program: Program): FormData {
  return {
    slug: program.slug,
    name: program.name,
    shortName: program.shortName,
    icon: program.icon,
    iconUrl: program.iconUrl || '',
    website: program.website || '',
    serverBaseUrl: program.serverBaseUrl || '',
    referenceLabel: program.referenceLabel,
    referenceFormat: program.referenceFormat || '',
    referenceExample: program.referenceExample || '',
    multiRefAllowed: program.multiRefAllowed,
    activationThreshold: program.activationThreshold?.toString() || '',
    supportsRove: program.supportsRove,
    capabilities: program.capabilities.join(', '),
    adifMySig: program.adifFields?.mySig || '',
    adifMySigInfo: program.adifFields?.mySigInfo || '',
    adifSigField: program.adifFields?.sigField || '',
    adifSigInfoField: program.adifFields?.sigInfoField || '',
    dataEntryLabel: program.dataEntry?.label || '',
    dataEntryPlaceholder: program.dataEntry?.placeholder || '',
    dataEntryFormat: program.dataEntry?.format || '',
    sortOrder: 0,
    isActive: program.isActive,
  };
}

export default function ProgramEditor() {
  const { slug } = useParams<{ slug: string }>();
  const navigate = useNavigate();
  const [form, setForm] = useState<FormData>(defaultValues);
  const [loading, setLoading] = useState(!!slug);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const isEditing = !!slug;

  useEffect(() => {
    if (slug) {
      loadProgram(slug);
    }
  }, [slug]);

  const loadProgram = async (programSlug: string) => {
    try {
      setLoading(true);
      const program = await getProgram(programSlug);
      setForm(programToForm(program));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load program');
    } finally {
      setLoading(false);
    }
  };

  const handleChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>,
  ) => {
    const { name, value, type } = e.target;
    if (type === 'checkbox') {
      setForm((prev) => ({ ...prev, [name]: (e.target as HTMLInputElement).checked }));
    } else if (type === 'number') {
      setForm((prev) => ({ ...prev, [name]: Number(value) }));
    } else {
      setForm((prev) => ({ ...prev, [name]: value }));
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      setSaving(true);
      setError('');

      const capabilities = form.capabilities
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean);

      if (isEditing) {
        await updateProgram(slug!, {
          name: form.name,
          shortName: form.shortName,
          icon: form.icon,
          iconUrl: form.iconUrl || null,
          website: form.website || null,
          serverBaseUrl: form.serverBaseUrl || null,
          referenceLabel: form.referenceLabel,
          referenceFormat: form.referenceFormat || null,
          referenceExample: form.referenceExample || null,
          multiRefAllowed: form.multiRefAllowed,
          activationThreshold: form.activationThreshold ? Number(form.activationThreshold) : null,
          supportsRove: form.supportsRove,
          capabilities,
          adifMySig: form.adifMySig || null,
          adifMySigInfo: form.adifMySigInfo || null,
          adifSigField: form.adifSigField || null,
          adifSigInfoField: form.adifSigInfoField || null,
          dataEntryLabel: form.dataEntryLabel || null,
          dataEntryPlaceholder: form.dataEntryPlaceholder || null,
          dataEntryFormat: form.dataEntryFormat || null,
          sortOrder: form.sortOrder,
          isActive: form.isActive,
        });
      } else {
        await createProgram({
          slug: form.slug,
          name: form.name,
          shortName: form.shortName,
          icon: form.icon,
          iconUrl: form.iconUrl || undefined,
          website: form.website || undefined,
          serverBaseUrl: form.serverBaseUrl || undefined,
          referenceLabel: form.referenceLabel,
          referenceFormat: form.referenceFormat || undefined,
          referenceExample: form.referenceExample || undefined,
          multiRefAllowed: form.multiRefAllowed,
          activationThreshold: form.activationThreshold ? Number(form.activationThreshold) : undefined,
          supportsRove: form.supportsRove,
          capabilities,
          adifMySig: form.adifMySig || undefined,
          adifMySigInfo: form.adifMySigInfo || undefined,
          adifSigField: form.adifSigField || undefined,
          adifSigInfoField: form.adifSigInfoField || undefined,
          dataEntryLabel: form.dataEntryLabel || undefined,
          dataEntryPlaceholder: form.dataEntryPlaceholder || undefined,
          dataEntryFormat: form.dataEntryFormat || undefined,
          sortOrder: form.sortOrder,
        });
      }

      navigate('/programs');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save program');
    } finally {
      setSaving(false);
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
      <div className="sm:flex sm:items-center sm:justify-between">
        <h1 className="text-2xl font-semibold text-gray-900">
          {isEditing ? 'Edit Program' : 'New Program'}
        </h1>
        <button
          type="button"
          onClick={() => navigate('/programs')}
          className="mt-4 sm:mt-0 inline-flex items-center px-4 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
        >
          Cancel
        </button>
      </div>

      {error && (
        <div className="mt-4 rounded-md bg-red-50 p-4">
          <p className="text-sm text-red-800">{error}</p>
        </div>
      )}

      <form onSubmit={handleSubmit} className="mt-6 space-y-8">
        {/* Basic Info */}
        <div>
          <h3 className="text-lg font-medium text-gray-900 mb-4">Basic Info</h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700">Slug</label>
              <input
                type="text"
                name="slug"
                value={form.slug}
                onChange={handleChange}
                disabled={isEditing}
                placeholder="pota"
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm disabled:bg-gray-100"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">Name</label>
              <input
                type="text"
                name="name"
                value={form.name}
                onChange={handleChange}
                placeholder="Parks on the Air"
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">Short Name</label>
              <input
                type="text"
                name="shortName"
                value={form.shortName}
                onChange={handleChange}
                placeholder="POTA"
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">Icon (emoji)</label>
              <input
                type="text"
                name="icon"
                value={form.icon}
                onChange={handleChange}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">Icon URL</label>
              <input
                type="text"
                name="iconUrl"
                value={form.iconUrl}
                onChange={handleChange}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">Website</label>
              <input
                type="text"
                name="website"
                value={form.website}
                onChange={handleChange}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">Server Base URL</label>
              <input
                type="text"
                name="serverBaseUrl"
                value={form.serverBaseUrl}
                onChange={handleChange}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">Sort Order</label>
              <input
                type="number"
                name="sortOrder"
                value={form.sortOrder}
                onChange={handleChange}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
          </div>
        </div>

        {/* Reference Config */}
        <div>
          <h3 className="text-lg font-medium text-gray-900 mb-4">Reference Configuration</h3>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700">Reference Label</label>
              <input
                type="text"
                name="referenceLabel"
                value={form.referenceLabel}
                onChange={handleChange}
                placeholder="Park"
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">Reference Format</label>
              <input
                type="text"
                name="referenceFormat"
                value={form.referenceFormat}
                onChange={handleChange}
                placeholder="[A-Z]+-\\d{4}"
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">Reference Example</label>
              <input
                type="text"
                name="referenceExample"
                value={form.referenceExample}
                onChange={handleChange}
                placeholder="US-0001"
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
          </div>
        </div>

        {/* Capabilities & Flags */}
        <div>
          <h3 className="text-lg font-medium text-gray-900 mb-4">Capabilities & Flags</h3>
          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700">
                Capabilities (comma-separated)
              </label>
              <input
                type="text"
                name="capabilities"
                value={form.capabilities}
                onChange={handleChange}
                placeholder="spots, leaderboard, dataEntry"
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">
                Activation Threshold
              </label>
              <input
                type="text"
                name="activationThreshold"
                value={form.activationThreshold}
                onChange={handleChange}
                placeholder="10"
                className="mt-1 block w-48 rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
            <div className="flex gap-6">
              <label className="flex items-center gap-2 text-sm text-gray-900">
                <input
                  type="checkbox"
                  name="multiRefAllowed"
                  checked={form.multiRefAllowed}
                  onChange={handleChange}
                  className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
                />
                Multi-ref Allowed
              </label>
              <label className="flex items-center gap-2 text-sm text-gray-900">
                <input
                  type="checkbox"
                  name="supportsRove"
                  checked={form.supportsRove}
                  onChange={handleChange}
                  className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
                />
                Supports Rove
              </label>
              <label className="flex items-center gap-2 text-sm text-gray-900">
                <input
                  type="checkbox"
                  name="isActive"
                  checked={form.isActive}
                  onChange={handleChange}
                  className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
                />
                Active
              </label>
            </div>
          </div>
        </div>

        {/* ADIF Fields */}
        <div>
          <h3 className="text-lg font-medium text-gray-900 mb-4">ADIF Field Mapping</h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700">MY_SIG</label>
              <input
                type="text"
                name="adifMySig"
                value={form.adifMySig}
                onChange={handleChange}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">MY_SIG_INFO</label>
              <input
                type="text"
                name="adifMySigInfo"
                value={form.adifMySigInfo}
                onChange={handleChange}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">SIG Field</label>
              <input
                type="text"
                name="adifSigField"
                value={form.adifSigField}
                onChange={handleChange}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">SIG_INFO Field</label>
              <input
                type="text"
                name="adifSigInfoField"
                value={form.adifSigInfoField}
                onChange={handleChange}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
          </div>
        </div>

        {/* Data Entry */}
        <div>
          <h3 className="text-lg font-medium text-gray-900 mb-4">Data Entry Configuration</h3>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700">Label</label>
              <input
                type="text"
                name="dataEntryLabel"
                value={form.dataEntryLabel}
                onChange={handleChange}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">Placeholder</label>
              <input
                type="text"
                name="dataEntryPlaceholder"
                value={form.dataEntryPlaceholder}
                onChange={handleChange}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">Format</label>
              <input
                type="text"
                name="dataEntryFormat"
                value={form.dataEntryFormat}
                onChange={handleChange}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
          </div>
        </div>

        <div className="flex justify-end pt-6 border-t">
          <button
            type="submit"
            disabled={saving}
            className="inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50"
          >
            {saving ? 'Saving...' : isEditing ? 'Update Program' : 'Create Program'}
          </button>
        </div>
      </form>
    </div>
  );
}
