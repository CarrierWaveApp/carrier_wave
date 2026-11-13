export interface Program {
  slug: string;
  name: string;
  shortName: string;
  icon: string;
  iconUrl?: string;
  website?: string;
  serverBaseUrl?: string;
  referenceLabel: string;
  referenceFormat?: string;
  referenceExample?: string;
  multiRefAllowed: boolean;
  activationThreshold?: number;
  supportsRove: boolean;
  capabilities: string[];
  adifFields?: {
    mySig?: string;
    mySigInfo?: string;
    sigField?: string;
    sigInfoField?: string;
  };
  dataEntry?: {
    label: string;
    placeholder?: string;
    format?: string;
  };
  isActive: boolean;
}

export interface CreateProgramRequest {
  slug: string;
  name: string;
  shortName: string;
  icon: string;
  iconUrl?: string;
  website?: string;
  serverBaseUrl?: string;
  referenceLabel: string;
  referenceFormat?: string;
  referenceExample?: string;
  multiRefAllowed: boolean;
  activationThreshold?: number;
  supportsRove: boolean;
  capabilities: string[];
  adifMySig?: string;
  adifMySigInfo?: string;
  adifSigField?: string;
  adifSigInfoField?: string;
  dataEntryLabel?: string;
  dataEntryPlaceholder?: string;
  dataEntryFormat?: string;
  sortOrder: number;
}

export interface UpdateProgramRequest {
  name?: string;
  shortName?: string;
  icon?: string;
  iconUrl?: string | null;
  website?: string | null;
  serverBaseUrl?: string | null;
  referenceLabel?: string;
  referenceFormat?: string | null;
  referenceExample?: string | null;
  multiRefAllowed?: boolean;
  activationThreshold?: number | null;
  supportsRove?: boolean;
  capabilities?: string[];
  adifMySig?: string | null;
  adifMySigInfo?: string | null;
  adifSigField?: string | null;
  adifSigInfoField?: string | null;
  dataEntryLabel?: string | null;
  dataEntryPlaceholder?: string | null;
  dataEntryFormat?: string | null;
  sortOrder?: number;
  isActive?: boolean;
}
