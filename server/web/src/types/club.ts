export interface Club {
  id: string;
  name: string;
  callsign?: string;
  description?: string;
  notesUrl?: string;
  notesTitle?: string;
  memberCount: number;
}

export interface ClubMember {
  callsign: string;
  role: string;
  joinedAt: string;
  lastSeenAt?: string;
  lastGrid?: string;
  isCarrierWaveUser: boolean;
}
