// =============================================================================
// sim-profile.ts — QManager Custom SIM Profile Types
// =============================================================================
// TypeScript interfaces for the SIM Profile CRUD, apply lifecycle, and
// current modem settings query.
//
// Backend contract:
//   Profile storage: /etc/qmanager/profiles/<id>.json
//   Apply state:     /tmp/qmanager_profile_state.json
//   Active profile:  /etc/qmanager/active_profile
//
// See: CUSTOM_SIM_PROFILE_ARCHITECTURE_v2.md
// =============================================================================

// --- Profile Data Model ------------------------------------------------------

/** A saved SIM profile with all modem/system settings */
export interface SimProfile {
  /** Unique ID: p_<unix_ts>_<3-char-hex> */
  id: string;
  /** User-defined profile name */
  name: string;
  /** Mobile Network Operator name (informational) */
  mno: string;
  /** SIM ICCID this profile was created for (informational, not enforced) */
  sim_iccid: string;
  /** Unix epoch (seconds) — when profile was first created */
  created_at: number;
  /** Unix epoch (seconds) — last update time */
  updated_at: number;
  /** All configurable modem/system settings */
  settings: ProfileSettings;
}

/** The configurable settings bundle within a profile */
export interface ProfileSettings {
  /** APN configuration */
  apn: ApnSettings;
  /** Preferred IMEI (15 digits). Empty string = don't change. */
  imei: string;
  /** IPv4 TTL value (0-255). 0 = don't set. */
  ttl: number;
  /** IPv6 Hop Limit value (0-255). 0 = don't set. */
  hl: number;
  /** Network mode preference */
  network_mode: NetworkModePreference;
  /** LTE bands, colon-delimited: "1:3:7:28". Empty = use all. */
  lte_bands: string;
  /** NSA NR5G bands, colon-delimited: "41:78". Empty = use all. */
  nsa_nr_bands: string;
  /** SA NR5G bands, colon-delimited: "41:78". Empty = use all. */
  sa_nr_bands: string;
  /** Whether band locking is enabled. false = unlock all bands. */
  band_lock_enabled: boolean;
}

/** APN connection settings */
export interface ApnSettings {
  /** PDP context ID (1-15), defaults to 1 for primary data */
  cid: number;
  /** APN name, e.g. "internet" */
  name: string;
  /** PDP type */
  pdp_type: PdpType;
}

export type PdpType = "IP" | "IPV6" | "IPV4V6";
export type NetworkModePreference = "AUTO" | "LTE_ONLY" | "NR_ONLY" | "LTE_NR";

// --- Profile List Response ---------------------------------------------------

/** Response from GET /cgi-bin/quecmanager/profiles/list.sh */
export interface ProfileListResponse {
  /** Array of profile summaries */
  profiles: ProfileSummary[];
  /** Currently active profile ID, or null if none */
  active_profile_id: string | null;
}

/** Profile summary (subset of full profile, used in list view) */
export interface ProfileSummary {
  id: string;
  name: string;
  mno: string;
  sim_iccid: string;
  created_at: number;
  updated_at: number;
}

// --- Profile Apply Lifecycle -------------------------------------------------

/** State of a profile application in progress */
export interface ProfileApplyState {
  /** Current apply status */
  status: ApplyStatus;
  /** Profile being applied */
  profile_id: string;
  /** Profile name (for display) */
  profile_name: string;
  /** Unix epoch when apply started */
  started_at: number;
  /** Current step number (1-indexed) */
  current_step: number;
  /** Total number of steps */
  total_steps: number;
  /** Per-step status details */
  steps: ApplyStep[];
  /** Whether the modem needs a reboot (IMEI change) */
  requires_reboot: boolean;
  /** Error message if status is "failed" */
  error: string | null;
}

export type ApplyStatus = "idle" | "applying" | "complete" | "partial" | "failed";

/** Status of a single step in the apply sequence */
export interface ApplyStep {
  /** Step name: apn, network_mode, lte_bands, nsa_nr_bands, sa_nr_bands, ttl_hl, imei */
  name: string;
  /** Current step status */
  status: ApplyStepStatus;
  /** Human-readable detail or progress message */
  detail: string;
}

export type ApplyStepStatus = "pending" | "running" | "done" | "failed" | "skipped";

// --- Current Modem Settings (for form pre-fill) ------------------------------

/** Response from GET /cgi-bin/quecmanager/profiles/current_settings.sh */
export interface CurrentModemSettings {
  /** All configured APN/CID pairs from AT+CGDCONT? */
  apn_profiles: CurrentApnProfile[];
  /** Current IMEI from AT+CGSN */
  imei: string;
  /** Current SIM ICCID from AT+QCCID */
  iccid: string;
  /** Current network mode from AT+QNWPREFCFG="mode_pref" */
  network_mode: string;
  /** Current LTE bands (colon-delimited) from AT+QNWPREFCFG="lte_band" */
  lte_bands: string;
  /** Current NSA NR bands (colon-delimited) */
  nsa_nr_bands: string;
  /** Current SA NR bands (colon-delimited) */
  sa_nr_bands: string;
  /** All hardware-supported LTE bands from policy_band (for band picker UI) */
  supported_lte_bands: string;
  /** All hardware-supported NSA NR bands */
  supported_nsa_nr_bands: string;
  /** All hardware-supported SA NR bands */
  supported_sa_nr_bands: string;
}

/** A single APN/CID pair from AT+CGDCONT? */
export interface CurrentApnProfile {
  /** PDP context ID */
  cid: number;
  /** PDP type (IP, IPV6, IPV4V6) */
  pdp_type: string;
  /** APN name */
  apn: string;
}

// --- API Response Types ------------------------------------------------------

/** Generic success response from save/delete operations */
export interface ProfileApiResponse {
  success: boolean;
  /** Profile ID (present on success) */
  id?: string;
  /** Error code (present on failure) */
  error?: string;
  /** Human-readable error detail */
  detail?: string;
}

// --- Display Helpers ---------------------------------------------------------

/** Human-readable labels for network mode preferences */
export const NETWORK_MODE_LABELS: Record<NetworkModePreference, string> = {
  AUTO: "Auto (LTE + NR)",
  LTE_ONLY: "LTE Only",
  NR_ONLY: "NR5G Only",
  LTE_NR: "LTE + NR5G",
};

/** Human-readable labels for PDP types */
export const PDP_TYPE_LABELS: Record<PdpType, string> = {
  IP: "IPv4 Only",
  IPV6: "IPv6 Only",
  IPV4V6: "IPv4 + IPv6 (Dual Stack)",
};

/** Human-readable labels for apply step statuses */
export const APPLY_STEP_STATUS_LABELS: Record<ApplyStepStatus, string> = {
  pending: "Pending",
  running: "In Progress",
  done: "Complete",
  failed: "Failed",
  skipped: "Skipped",
};

/**
 * Formats a band string for display.
 * "1:3:7:28" → "B1, B3, B7, B28"
 * "" → "All Bands"
 */
export function formatBandList(bands: string, prefix: string = "B"): string {
  if (!bands || bands.trim() === "") return "All Bands";
  return bands
    .split(":")
    .map((b) => `${prefix}${b}`)
    .join(", ");
}

/**
 * Formats a Unix timestamp into a locale-appropriate date string.
 */
export function formatProfileDate(timestamp: number): string {
  if (!timestamp) return "-";
  return new Date(timestamp * 1000).toLocaleDateString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}
