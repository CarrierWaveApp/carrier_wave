export type ChallengeCategory = 'award' | 'event' | 'club' | 'personal' | 'other';
export type ChallengeType = 'collection' | 'cumulative' | 'timeBounded';
export type ScoringMethod = 'count' | 'percentage' | 'points' | 'weighted';

export interface Goal {
  id: string;
  name: string;
  category?: string;
  metadata?: Record<string, string>;
}

export interface CumulativeGoal {
  targetValue: number;
  unit: string;
  calculationRule?: string;
}

export interface Tier {
  id: string;
  name: string;
  threshold: number;
  order: number;
  badgeId?: string;
}

export interface MatchRule {
  qsoField: string;
  goalField: string;
  transformation?: string;
  validationRegex?: string;
}

export interface QualificationCriteria {
  bands?: string[];
  modes?: string[];
  requiredFields?: string[];
  dateRange?: {
    start?: string;
    end?: string;
  };
  matchRules: MatchRule[];
}

export interface ScoringConfig {
  method: ScoringMethod;
  weights?: { rule: string; weight: number }[];
  tiebreaker?: string;
  displayFormat: string;
}

export interface TimeConstraints {
  type: 'calendar' | 'relative';
  startDate?: string;
  endDate?: string;
  duration?: string;
  timezone: string;
}

export interface GoalsConfig {
  type: 'collection' | 'cumulative';
  items?: Goal[];
  targetValue?: number;
  unit?: string;
}

export interface ChallengeConfiguration {
  goals: GoalsConfig;
  tiers?: Tier[];
  qualificationCriteria: QualificationCriteria;
  scoring: ScoringConfig;
  timeConstraints?: TimeConstraints;
  historicalQsosAllowed: boolean;
}

export interface Challenge {
  id?: string;
  version?: number;
  name: string;
  description: string;
  author?: string;
  category: ChallengeCategory;
  type: ChallengeType;
  configuration: ChallengeConfiguration;
  inviteConfig?: {
    maxParticipants?: number;
    expiresAt?: string;
  };
  hamalertConfig?: {
    enabled: boolean;
    alertType: string;
    spotSources: string[];
    autoManage: boolean;
  };
  isActive?: boolean;
  createdAt?: string;
  updatedAt?: string;
}

export interface ChallengeListItem {
  id: string;
  name: string;
  description: string;
  category: ChallengeCategory;
  type: ChallengeType;
  participantCount: number;
  isActive: boolean;
}

export interface Badge {
  id: string;
  name: string;
  tierId?: string;
  imageUrl: string;
  contentType: string;
  createdAt: string;
}

export interface Invite {
  token: string;
  url: string;
  maxUses?: number;
  useCount: number;
  expiresAt?: string;
  createdAt: string;
}
