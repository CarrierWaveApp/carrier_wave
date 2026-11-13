import { useState, useEffect } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { useForm } from "react-hook-form";
import { getChallenge, createChallenge, updateChallenge } from "../api/client";
import type {
  Challenge,
  ChallengeCategory,
  ChallengeType,
  Goal,
  Tier,
  ScoringMethod,
} from "../types/challenge";
import GoalEditor from "../components/challenge/GoalEditor";
import TierEditor from "../components/challenge/TierEditor";
import CriteriaEditor from "../components/challenge/CriteriaEditor";
import BadgeManager from "../components/challenge/BadgeManager";
import InviteManager from "../components/challenge/InviteManager";

type TabId =
  | "basic"
  | "goals"
  | "tiers"
  | "criteria"
  | "scoring"
  | "badges"
  | "invites";

// Convert ISO 8601 date (e.g. "2026-01-01T00:00:00Z") to datetime-local format ("2026-01-01T00:00")
function toDatetimeLocal(isoString: string | undefined): string {
  if (!isoString) return "";
  // Remove timezone suffix and truncate to minutes
  return isoString.replace(/:\d{2}(\.\d+)?Z?$/, "").replace(/Z$/, "");
}

// Convert datetime-local format back to ISO 8601
function toIsoString(datetimeLocal: string | undefined): string | undefined {
  if (!datetimeLocal) return undefined;
  // Add seconds and Z timezone if not present
  if (!datetimeLocal.includes("Z")) {
    return datetimeLocal + ":00Z";
  }
  return datetimeLocal;
}

const tabs: { id: TabId; name: string }[] = [
  { id: "basic", name: "Basic Info" },
  { id: "goals", name: "Goals" },
  { id: "tiers", name: "Tiers" },
  { id: "criteria", name: "Criteria" },
  { id: "scoring", name: "Scoring" },
  { id: "badges", name: "Badges" },
  { id: "invites", name: "Invites" },
];

interface FormData {
  name: string;
  description: string;
  author: string;
  category: ChallengeCategory;
  type: ChallengeType;
  isActive: boolean;
  goalsType: "collection" | "cumulative";
  goals: Goal[];
  cumulativeTarget: number;
  cumulativeUnit: string;
  tiers: Tier[];
  bands: string[];
  modes: string[];
  requiredFields: string[];
  matchRules: { qsoField: string; goalField: string }[];
  historicalQsosAllowed: boolean;
  scoringMethod: ScoringMethod;
  displayFormat: string;
  hasTimeConstraints: boolean;
  timeConstraintType: "calendar" | "relative";
  startDate: string;
  endDate: string;
  timezone: string;
}

const defaultValues: FormData = {
  name: "",
  description: "",
  author: "",
  category: "award",
  type: "collection",
  isActive: true,
  goalsType: "collection",
  goals: [],
  cumulativeTarget: 100,
  cumulativeUnit: "contacts",
  tiers: [],
  bands: [],
  modes: [],
  requiredFields: [],
  matchRules: [{ qsoField: "", goalField: "id" }],
  historicalQsosAllowed: true,
  scoringMethod: "count",
  displayFormat: "{value}",
  hasTimeConstraints: false,
  timeConstraintType: "calendar",
  startDate: "",
  endDate: "",
  timezone: "UTC",
};

export default function ChallengeEditor() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState<TabId>("basic");
  const [loading, setLoading] = useState(!!id);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  const { register, control, handleSubmit, watch, setValue, reset } =
    useForm<FormData>({
      defaultValues,
    });

  const hasTimeConstraints = watch("hasTimeConstraints");

  useEffect(() => {
    if (id) {
      loadChallenge(id);
    }
  }, [id]);

  const loadChallenge = async (challengeId: string) => {
    try {
      setLoading(true);
      const challenge = await getChallenge(challengeId);

      // Map challenge to form data
      const formData: Partial<FormData> = {
        name: challenge.name,
        description: challenge.description,
        author: challenge.author || "",
        category: challenge.category,
        type: challenge.type,
        isActive: challenge.isActive ?? true,
        goalsType: challenge.configuration.goals.type,
        goals: challenge.configuration.goals.items || [],
        cumulativeTarget: challenge.configuration.goals.targetValue || 100,
        cumulativeUnit: challenge.configuration.goals.unit || "contacts",
        tiers: challenge.configuration.tiers || [],
        bands: challenge.configuration.qualificationCriteria.bands || [],
        modes: challenge.configuration.qualificationCriteria.modes || [],
        requiredFields:
          challenge.configuration.qualificationCriteria.requiredFields || [],
        matchRules:
          challenge.configuration.qualificationCriteria.matchRules.length > 0
            ? challenge.configuration.qualificationCriteria.matchRules
            : [{ qsoField: "", goalField: "id" }],
        historicalQsosAllowed: challenge.configuration.historicalQsosAllowed,
        scoringMethod: challenge.configuration.scoring.method,
        displayFormat: challenge.configuration.scoring.displayFormat,
        hasTimeConstraints: !!challenge.configuration.timeConstraints,
        timeConstraintType:
          challenge.configuration.timeConstraints?.type || "calendar",
        startDate: toDatetimeLocal(
          challenge.configuration.timeConstraints?.startDate,
        ),
        endDate: toDatetimeLocal(
          challenge.configuration.timeConstraints?.endDate,
        ),
        timezone: challenge.configuration.timeConstraints?.timezone || "UTC",
      };

      reset(formData as FormData);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load challenge");
    } finally {
      setLoading(false);
    }
  };

  const onSubmit = async (data: FormData) => {
    try {
      setSaving(true);
      setError("");

      const challenge: Omit<
        Challenge,
        "id" | "version" | "createdAt" | "updatedAt"
      > = {
        name: data.name,
        description: data.description,
        author: data.author || undefined,
        category: data.category,
        type: data.type,
        isActive: data.isActive,
        configuration: {
          goals:
            data.goalsType === "collection"
              ? { type: "collection", items: data.goals }
              : {
                  type: "cumulative",
                  targetValue: data.cumulativeTarget,
                  unit: data.cumulativeUnit,
                },
          tiers: data.tiers.length > 0 ? data.tiers : undefined,
          qualificationCriteria: {
            bands: data.bands.length > 0 ? data.bands : undefined,
            modes: data.modes.length > 0 ? data.modes : undefined,
            requiredFields:
              data.requiredFields.length > 0 ? data.requiredFields : undefined,
            matchRules: data.matchRules.filter((r) => r.qsoField),
          },
          scoring: {
            method: data.scoringMethod,
            displayFormat: data.displayFormat,
          },
          timeConstraints: data.hasTimeConstraints
            ? {
                type: data.timeConstraintType,
                startDate: toIsoString(data.startDate),
                endDate: toIsoString(data.endDate),
                timezone: data.timezone,
              }
            : undefined,
          historicalQsosAllowed: data.historicalQsosAllowed,
        },
      };

      if (id) {
        await updateChallenge(id, challenge);
      } else {
        await createChallenge(challenge);
      }

      navigate("/");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to save challenge");
    } finally {
      setSaving(false);
    }
  };

  const exportJson = () => {
    const formData = watch();
    const challenge = {
      name: formData.name,
      description: formData.description,
      author: formData.author || undefined,
      category: formData.category,
      type: formData.type,
      configuration: {
        goals:
          formData.goalsType === "collection"
            ? { type: "collection", items: formData.goals }
            : {
                type: "cumulative",
                targetValue: formData.cumulativeTarget,
                unit: formData.cumulativeUnit,
              },
        tiers: formData.tiers.length > 0 ? formData.tiers : undefined,
        qualificationCriteria: {
          bands: formData.bands.length > 0 ? formData.bands : undefined,
          modes: formData.modes.length > 0 ? formData.modes : undefined,
          matchRules: formData.matchRules.filter((r) => r.qsoField),
        },
        scoring: {
          method: formData.scoringMethod,
          displayFormat: formData.displayFormat,
        },
        historicalQsosAllowed: formData.historicalQsosAllowed,
      },
    };

    const blob = new Blob([JSON.stringify(challenge, null, 2)], {
      type: "application/json",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${formData.name || "challenge"}.json`;
    a.click();
    URL.revokeObjectURL(url);
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
          {id ? "Edit Challenge" : "New Challenge"}
        </h1>
        <div className="mt-4 sm:mt-0 flex gap-2">
          <button
            type="button"
            onClick={exportJson}
            className="inline-flex items-center px-4 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
          >
            Export JSON
          </button>
          <button
            type="button"
            onClick={() => navigate("/")}
            className="inline-flex items-center px-4 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
          >
            Cancel
          </button>
        </div>
      </div>

      {error && (
        <div className="mt-4 rounded-md bg-red-50 p-4">
          <p className="text-sm text-red-800">{error}</p>
        </div>
      )}

      <div className="mt-6">
        <div className="border-b border-gray-200">
          <nav className="-mb-px flex space-x-8" aria-label="Tabs">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`${
                  activeTab === tab.id
                    ? "border-blue-500 text-blue-600"
                    : "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
                } whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm`}
              >
                {tab.name}
              </button>
            ))}
          </nav>
        </div>

        <form onSubmit={handleSubmit(onSubmit)} className="mt-6 space-y-6">
          {activeTab === "basic" && (
            <div className="space-y-6">
              <div>
                <label className="block text-sm font-medium text-gray-700">
                  Name
                </label>
                <input
                  type="text"
                  {...register("name", { required: true })}
                  className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700">
                  Description
                </label>
                <textarea
                  {...register("description")}
                  rows={3}
                  className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700">
                  Author
                </label>
                <input
                  type="text"
                  {...register("author")}
                  className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700">
                    Category
                  </label>
                  <select
                    {...register("category")}
                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  >
                    <option value="award">Award</option>
                    <option value="event">Event</option>
                    <option value="club">Club</option>
                    <option value="personal">Personal</option>
                    <option value="other">Other</option>
                  </select>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700">
                    Type
                  </label>
                  <select
                    {...register("type")}
                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  >
                    <option value="collection">Collection</option>
                    <option value="cumulative">Cumulative</option>
                    <option value="timeBounded">Time-Bounded</option>
                  </select>
                </div>
              </div>

              <div className="flex items-center">
                <input
                  type="checkbox"
                  {...register("isActive")}
                  className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
                />
                <label className="ml-2 block text-sm text-gray-900">
                  Active
                </label>
              </div>
            </div>
          )}

          {activeTab === "goals" && (
            <GoalEditor control={control} register={register} watch={watch} />
          )}

          {activeTab === "tiers" && (
            <TierEditor control={control} register={register} />
          )}

          {activeTab === "criteria" && (
            <CriteriaEditor
              control={control}
              register={register}
              watch={watch}
              setValue={setValue}
            />
          )}

          {activeTab === "scoring" && (
            <div className="space-y-6">
              <div>
                <label className="block text-sm font-medium text-gray-700">
                  Scoring Method
                </label>
                <select
                  {...register("scoringMethod")}
                  className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                >
                  <option value="count">Count</option>
                  <option value="percentage">Percentage</option>
                  <option value="points">Points</option>
                  <option value="weighted">Weighted</option>
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700">
                  Display Format
                </label>
                <input
                  type="text"
                  {...register("displayFormat")}
                  placeholder="{value}/50 states"
                  className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                />
                <p className="mt-1 text-sm text-gray-500">
                  Use {"{value}"} as placeholder for the score
                </p>
              </div>

              <div className="flex items-center">
                <input
                  type="checkbox"
                  {...register("hasTimeConstraints")}
                  className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
                />
                <label className="ml-2 block text-sm text-gray-900">
                  Has Time Constraints
                </label>
              </div>

              {hasTimeConstraints && (
                <div className="space-y-4 ml-6">
                  <div>
                    <label className="block text-sm font-medium text-gray-700">
                      Type
                    </label>
                    <select
                      {...register("timeConstraintType")}
                      className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                    >
                      <option value="calendar">Calendar (fixed dates)</option>
                      <option value="relative">
                        Relative (from join date)
                      </option>
                    </select>
                  </div>

                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <label className="block text-sm font-medium text-gray-700">
                        Start Date
                      </label>
                      <input
                        type="datetime-local"
                        {...register("startDate")}
                        className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                      />
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-gray-700">
                        End Date
                      </label>
                      <input
                        type="datetime-local"
                        {...register("endDate")}
                        className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                      />
                    </div>
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-gray-700">
                      Timezone
                    </label>
                    <input
                      type="text"
                      {...register("timezone")}
                      placeholder="UTC"
                      className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                    />
                  </div>
                </div>
              )}
            </div>
          )}

          {activeTab === "badges" && id && <BadgeManager challengeId={id} />}
          {activeTab === "badges" && !id && (
            <p className="text-gray-500">
              Save the challenge first to manage badges.
            </p>
          )}

          {activeTab === "invites" && id && <InviteManager challengeId={id} />}
          {activeTab === "invites" && !id && (
            <p className="text-gray-500">
              Save the challenge first to manage invites.
            </p>
          )}

          <div className="flex justify-end pt-6 border-t">
            <button
              type="submit"
              disabled={saving}
              className="inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50"
            >
              {saving
                ? "Saving..."
                : id
                  ? "Update Challenge"
                  : "Create Challenge"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
