import { useFieldArray, Control, UseFormRegister, UseFormWatch, UseFormSetValue } from 'react-hook-form';

interface CriteriaEditorProps {
  control: Control<any>;
  register: UseFormRegister<any>;
  watch: UseFormWatch<any>;
  setValue: UseFormSetValue<any>;
}

const COMMON_BANDS = ['160m', '80m', '60m', '40m', '30m', '20m', '17m', '15m', '12m', '10m', '6m', '2m', '70cm'];
const COMMON_MODES = ['SSB', 'CW', 'FT8', 'FT4', 'RTTY', 'PSK31', 'JS8', 'FM', 'AM', 'DSTAR', 'DMR', 'C4FM'];
const COMMON_QSO_FIELDS = ['state', 'dxcc', 'country', 'grid', 'parkReference', 'sotaReference', 'cqZone', 'ituZone'];

export default function CriteriaEditor({ control, register, watch, setValue }: CriteriaEditorProps) {
  const bands = watch('bands') || [];
  const modes = watch('modes') || [];

  const { fields: matchRuleFields, append: appendMatchRule, remove: removeMatchRule } = useFieldArray({
    control,
    name: 'matchRules',
  });

  const toggleBand = (band: string) => {
    if (bands.includes(band)) {
      setValue('bands', bands.filter((b: string) => b !== band));
    } else {
      setValue('bands', [...bands, band]);
    }
  };

  const toggleMode = (mode: string) => {
    if (modes.includes(mode)) {
      setValue('modes', modes.filter((m: string) => m !== mode));
    } else {
      setValue('modes', [...modes, mode]);
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-2">Allowed Bands</label>
        <p className="text-sm text-gray-500 mb-2">Leave empty to allow all bands</p>
        <div className="flex flex-wrap gap-2">
          {COMMON_BANDS.map((band) => (
            <button
              key={band}
              type="button"
              onClick={() => toggleBand(band)}
              className={`px-3 py-1 rounded-full text-sm ${
                bands.includes(band)
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              {band}
            </button>
          ))}
        </div>
        {bands.length > 0 && (
          <button
            type="button"
            onClick={() => setValue('bands', [])}
            className="mt-2 text-sm text-gray-500 hover:text-gray-700"
          >
            Clear all
          </button>
        )}
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-2">Allowed Modes</label>
        <p className="text-sm text-gray-500 mb-2">Leave empty to allow all modes</p>
        <div className="flex flex-wrap gap-2">
          {COMMON_MODES.map((mode) => (
            <button
              key={mode}
              type="button"
              onClick={() => toggleMode(mode)}
              className={`px-3 py-1 rounded-full text-sm ${
                modes.includes(mode)
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              {mode}
            </button>
          ))}
        </div>
        {modes.length > 0 && (
          <button
            type="button"
            onClick={() => setValue('modes', [])}
            className="mt-2 text-sm text-gray-500 hover:text-gray-700"
          >
            Clear all
          </button>
        )}
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-2">Match Rules</label>
        <p className="text-sm text-gray-500 mb-2">
          Define how QSO fields map to challenge goals
        </p>

        <div className="space-y-3">
          {matchRuleFields.map((field, index) => (
            <div key={field.id} className="flex gap-2 items-center">
              <select
                {...register(`matchRules.${index}.qsoField`)}
                className="flex-1 rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              >
                <option value="">Select QSO field...</option>
                {COMMON_QSO_FIELDS.map((f) => (
                  <option key={f} value={f}>{f}</option>
                ))}
              </select>
              <span className="text-gray-500">maps to</span>
              <input
                {...register(`matchRules.${index}.goalField`)}
                placeholder="id"
                className="flex-1 rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
              {matchRuleFields.length > 1 && (
                <button
                  type="button"
                  onClick={() => removeMatchRule(index)}
                  className="text-red-600 hover:text-red-900"
                >
                  Remove
                </button>
              )}
            </div>
          ))}
        </div>

        <button
          type="button"
          onClick={() => appendMatchRule({ qsoField: '', goalField: 'id' })}
          className="mt-2 text-sm text-blue-600 hover:text-blue-800"
        >
          + Add match rule
        </button>
      </div>

      <div className="flex items-center">
        <input
          type="checkbox"
          {...register('historicalQsosAllowed')}
          className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
        />
        <label className="ml-2 block text-sm text-gray-900">
          Allow historical QSOs (contacts made before joining the challenge)
        </label>
      </div>
    </div>
  );
}
