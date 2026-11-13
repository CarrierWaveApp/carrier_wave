import { useFieldArray, Control, UseFormRegister, UseFormWatch } from 'react-hook-form';
import { useState, useRef } from 'react';
import { US_STATES } from '../../data/us-states';
import { DXCC_ENTITIES } from '../../data/dxcc-entities';

interface GoalEditorProps {
  control: Control<any>;
  register: UseFormRegister<any>;
  watch: UseFormWatch<any>;
}

export default function GoalEditor({ control, register, watch }: GoalEditorProps) {
  const { fields, append, remove, replace } = useFieldArray({
    control,
    name: 'goals',
  });

  const goalsType = watch('goalsType');
  const [newGoalId, setNewGoalId] = useState('');
  const [newGoalName, setNewGoalName] = useState('');
  const fileInputRef = useRef<HTMLInputElement>(null);

  const addGoal = () => {
    if (newGoalId && newGoalName) {
      append({ id: newGoalId, name: newGoalName });
      setNewGoalId('');
      setNewGoalName('');
    }
  };

  const importPreset = (preset: 'us-states' | 'dxcc') => {
    const goals = preset === 'us-states' ? US_STATES : DXCC_ENTITIES;
    replace(goals);
  };

  const handleCsvImport = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (event) => {
      const text = event.target?.result as string;
      const lines = text.split('\n').filter(line => line.trim());

      // Skip header if it looks like one
      const startIndex = lines[0]?.toLowerCase().includes('id') ? 1 : 0;

      const goals = lines.slice(startIndex).map(line => {
        const [id, name, category] = line.split(',').map(s => s.trim().replace(/^"|"$/g, ''));
        return { id, name, category: category || undefined };
      }).filter(g => g.id && g.name);

      replace(goals);
    };
    reader.readAsText(file);

    // Reset input
    if (fileInputRef.current) {
      fileInputRef.current.value = '';
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <label className="block text-sm font-medium text-gray-700">Goals Type</label>
        <select
          {...register('goalsType')}
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
        >
          <option value="collection">Collection (work specific items)</option>
          <option value="cumulative">Cumulative (reach a target value)</option>
        </select>
      </div>

      {goalsType === 'cumulative' ? (
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700">Target Value</label>
            <input
              type="number"
              {...register('cumulativeTarget', { valueAsNumber: true })}
              className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700">Unit</label>
            <input
              type="text"
              {...register('cumulativeUnit')}
              placeholder="contacts"
              className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
            />
          </div>
        </div>
      ) : (
        <div className="space-y-4">
          <div className="flex items-center">
            <input
              type="checkbox"
              {...register('historicalQsosAllowed')}
              className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
            />
            <label className="ml-2 block text-sm text-gray-900">
              Allow historical QSOs (contacts made before joining)
            </label>
          </div>

          <div className="flex gap-2 flex-wrap">
            <button
              type="button"
              onClick={() => importPreset('us-states')}
              className="inline-flex items-center px-3 py-1.5 border border-gray-300 shadow-sm text-xs font-medium rounded text-gray-700 bg-white hover:bg-gray-50"
            >
              Import US States
            </button>
            <button
              type="button"
              onClick={() => importPreset('dxcc')}
              className="inline-flex items-center px-3 py-1.5 border border-gray-300 shadow-sm text-xs font-medium rounded text-gray-700 bg-white hover:bg-gray-50"
            >
              Import DXCC Entities
            </button>
            <label className="inline-flex items-center px-3 py-1.5 border border-gray-300 shadow-sm text-xs font-medium rounded text-gray-700 bg-white hover:bg-gray-50 cursor-pointer">
              Import CSV
              <input
                ref={fileInputRef}
                type="file"
                accept=".csv"
                onChange={handleCsvImport}
                className="hidden"
              />
            </label>
            {fields.length > 0 && (
              <button
                type="button"
                onClick={() => replace([])}
                className="inline-flex items-center px-3 py-1.5 border border-red-300 shadow-sm text-xs font-medium rounded text-red-700 bg-white hover:bg-red-50"
              >
                Clear All
              </button>
            )}
          </div>

          <div className="border rounded-md p-4">
            <div className="flex gap-2 mb-4">
              <input
                type="text"
                placeholder="ID (e.g., US-CA)"
                value={newGoalId}
                onChange={(e) => setNewGoalId(e.target.value)}
                className="flex-1 rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
              <input
                type="text"
                placeholder="Name (e.g., California)"
                value={newGoalName}
                onChange={(e) => setNewGoalName(e.target.value)}
                className="flex-1 rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
              <button
                type="button"
                onClick={addGoal}
                disabled={!newGoalId || !newGoalName}
                className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 disabled:opacity-50"
              >
                Add
              </button>
            </div>

            <div className="text-sm text-gray-500 mb-2">
              {fields.length} goal{fields.length !== 1 ? 's' : ''}
            </div>

            {fields.length > 0 && (
              <div className="max-h-64 overflow-y-auto border rounded">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50 sticky top-0">
                    <tr>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">ID</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Name</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Category</th>
                      <th className="px-3 py-2"></th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {fields.map((field, index) => (
                      <tr key={field.id}>
                        <td className="px-3 py-2 text-sm text-gray-900">
                          <input
                            {...register(`goals.${index}.id`)}
                            className="w-full border-0 p-0 focus:ring-0 text-sm"
                          />
                        </td>
                        <td className="px-3 py-2 text-sm text-gray-900">
                          <input
                            {...register(`goals.${index}.name`)}
                            className="w-full border-0 p-0 focus:ring-0 text-sm"
                          />
                        </td>
                        <td className="px-3 py-2 text-sm text-gray-500">
                          <input
                            {...register(`goals.${index}.category`)}
                            className="w-full border-0 p-0 focus:ring-0 text-sm"
                            placeholder="-"
                          />
                        </td>
                        <td className="px-3 py-2 text-right">
                          <button
                            type="button"
                            onClick={() => remove(index)}
                            className="text-red-600 hover:text-red-900 text-sm"
                          >
                            Remove
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
      )}
    </div>
  );
}
