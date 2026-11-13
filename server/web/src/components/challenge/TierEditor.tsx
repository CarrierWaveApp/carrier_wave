import { useFieldArray, Control, UseFormRegister } from 'react-hook-form';

interface TierEditorProps {
  control: Control<any>;
  register: UseFormRegister<any>;
}

export default function TierEditor({ control, register }: TierEditorProps) {
  const { fields, append, remove, move } = useFieldArray({
    control,
    name: 'tiers',
  });

  const addTier = () => {
    append({
      id: `tier-${Date.now()}`,
      name: '',
      threshold: 0,
      order: fields.length,
    });
  };

  return (
    <div className="space-y-4">
      <p className="text-sm text-gray-500">
        Define progression tiers for your challenge. Users earn badges and recognition as they reach each tier.
      </p>

      <div className="space-y-4">
        {fields.map((field, index) => (
          <div key={field.id} className="border rounded-md p-4 bg-gray-50">
            <div className="flex justify-between items-start mb-4">
              <span className="text-sm font-medium text-gray-700">Tier {index + 1}</span>
              <div className="flex gap-2">
                {index > 0 && (
                  <button
                    type="button"
                    onClick={() => move(index, index - 1)}
                    className="text-gray-400 hover:text-gray-600"
                  >
                    Move Up
                  </button>
                )}
                {index < fields.length - 1 && (
                  <button
                    type="button"
                    onClick={() => move(index, index + 1)}
                    className="text-gray-400 hover:text-gray-600"
                  >
                    Move Down
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => remove(index)}
                  className="text-red-600 hover:text-red-900"
                >
                  Remove
                </button>
              </div>
            </div>

            <div className="grid grid-cols-3 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700">ID</label>
                <input
                  {...register(`tiers.${index}.id`)}
                  className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  placeholder="tier-25"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700">Name</label>
                <input
                  {...register(`tiers.${index}.name`)}
                  className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  placeholder="25 States"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700">Threshold</label>
                <input
                  type="number"
                  {...register(`tiers.${index}.threshold`, { valueAsNumber: true })}
                  className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  placeholder="25"
                />
              </div>
            </div>

            <input type="hidden" {...register(`tiers.${index}.order`)} value={index} />
          </div>
        ))}
      </div>

      <button
        type="button"
        onClick={addTier}
        className="inline-flex items-center px-4 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
      >
        Add Tier
      </button>

      {fields.length === 0 && (
        <p className="text-sm text-gray-500 italic">
          No tiers defined. Challenge will have a single completion state.
        </p>
      )}
    </div>
  );
}
