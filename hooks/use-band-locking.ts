"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import type {
  BandCategory,
  CurrentBands,
  FailoverState,
  BandCurrentResponse,
  BandLockResponse,
  FailoverToggleResponse,
} from "@/types/band-locking";
import { bandArrayToString } from "@/types/band-locking";

// =============================================================================
// useBandLocking — Band Lock State, Lock/Unlock, & Failover Hook
// =============================================================================
// Manages the band locking lifecycle: fetching current locked bands,
// applying per-category band locks, unlocking all bands, and toggling
// the failover safety mechanism.
//
// Supported bands and active bands are NOT managed here — they come from
// useModemStatus() (poller cache) and are passed in by the parent component.
//
// Backend endpoints:
//   GET  /cgi-bin/quecmanager/bands/current.sh         → locked bands + failover
//   POST /cgi-bin/quecmanager/bands/lock.sh             → apply band lock
//   POST /cgi-bin/quecmanager/bands/failover_toggle.sh  → enable/disable failover
// =============================================================================

const CGI_BASE = "/cgi-bin/quecmanager/bands";

export interface UseBandLockingReturn {
  /** Currently locked/configured bands from ue_capability_band */
  currentBands: CurrentBands | null;
  /** Failover safety mechanism state */
  failover: FailoverState;
  /** True during initial data fetch */
  isLoading: boolean;
  /** Which band category is currently being locked/unlocked (null = idle) */
  lockingCategory: BandCategory | null;
  /** Error message from the last operation */
  error: string | null;
  /**
   * Lock specific bands for one category.
   * Sends AT+QNWPREFCFG command for the specified band type.
   * Re-fetches current bands on success.
   * @returns success boolean
   */
  lockBands: (category: BandCategory, bands: number[]) => Promise<boolean>;
  /**
   * Unlock all bands for one category by setting to full supported list.
   * Requires the supported band list (from useModemStatus) to be passed in.
   * @returns success boolean
   */
  unlockAll: (category: BandCategory, supportedBands: number[]) => Promise<boolean>;
  /**
   * Toggle the failover safety mechanism on/off.
   * @returns success boolean
   */
  toggleFailover: (enabled: boolean) => Promise<boolean>;
  /** Manually refresh current bands + failover state */
  refresh: () => void;
}

export function useBandLocking(): UseBandLockingReturn {
  const [currentBands, setCurrentBands] = useState<CurrentBands | null>(null);
  const [failover, setFailover] = useState<FailoverState>({
    enabled: false,
    activated: false,
  });
  const [isLoading, setIsLoading] = useState(true);
  const [lockingCategory, setLockingCategory] = useState<BandCategory | null>(null);
  const [error, setError] = useState<string | null>(null);

  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  // ---------------------------------------------------------------------------
  // Fetch current locked bands + failover state
  // ---------------------------------------------------------------------------
  const fetchCurrent = useCallback(async () => {
    try {
      const resp = await fetch(`${CGI_BASE}/current.sh`);
      if (!resp.ok) {
        throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
      }

      const data: BandCurrentResponse = await resp.json();
      if (!mountedRef.current) return;

      if (!data.success) {
        setError(data.detail || data.error || "Failed to fetch band configuration");
        return;
      }

      setCurrentBands(data.current);
      setFailover(data.failover);
      setError(null);
    } catch (err) {
      if (!mountedRef.current) return;
      setError(
        err instanceof Error ? err.message : "Failed to fetch band configuration",
      );
    } finally {
      if (mountedRef.current) {
        setIsLoading(false);
      }
    }
  }, []);

  // Initial fetch
  useEffect(() => {
    fetchCurrent();
  }, [fetchCurrent]);

  // ---------------------------------------------------------------------------
  // Lock bands for one category
  // ---------------------------------------------------------------------------
  const lockBands = useCallback(
    async (category: BandCategory, bands: number[]): Promise<boolean> => {
      if (bands.length === 0) {
        setError("No bands selected");
        return false;
      }

      setError(null);
      setLockingCategory(category);

      try {
        const resp = await fetch(`${CGI_BASE}/lock.sh`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            band_type: category,
            bands: bandArrayToString(bands),
          }),
        });

        if (!resp.ok) {
          throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
        }

        const data: BandLockResponse = await resp.json();
        if (!mountedRef.current) return false;

        if (!data.success) {
          setError(data.detail || data.error || "Failed to apply band lock");
          return false;
        }

        // Re-fetch current state to confirm the lock took effect
        await fetchCurrent();
        return true;
      } catch (err) {
        if (!mountedRef.current) return false;
        setError(
          err instanceof Error ? err.message : "Failed to apply band lock",
        );
        return false;
      } finally {
        if (mountedRef.current) {
          setLockingCategory(null);
        }
      }
    },
    [fetchCurrent],
  );

  // ---------------------------------------------------------------------------
  // Unlock all bands for one category (set to full supported list)
  // ---------------------------------------------------------------------------
  const unlockAll = useCallback(
    async (category: BandCategory, supportedBands: number[]): Promise<boolean> => {
      if (supportedBands.length === 0) {
        setError("Supported bands not available");
        return false;
      }

      // Locking to ALL supported bands = unlock all
      return lockBands(category, supportedBands);
    },
    [lockBands],
  );

  // ---------------------------------------------------------------------------
  // Toggle failover
  // ---------------------------------------------------------------------------
  const toggleFailover = useCallback(
    async (enabled: boolean): Promise<boolean> => {
      setError(null);

      try {
        const resp = await fetch(`${CGI_BASE}/failover_toggle.sh`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ enabled }),
        });

        if (!resp.ok) {
          throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
        }

        const data: FailoverToggleResponse = await resp.json();
        if (!mountedRef.current) return false;

        if (!data.success) {
          setError(data.detail || data.error || "Failed to toggle failover");
          return false;
        }

        // Optimistic update
        setFailover((prev) => ({ ...prev, enabled: data.enabled ?? enabled }));
        return true;
      } catch (err) {
        if (!mountedRef.current) return false;
        setError(
          err instanceof Error ? err.message : "Failed to toggle failover",
        );
        return false;
      }
    },
    [],
  );

  // ---------------------------------------------------------------------------
  // Manual refresh
  // ---------------------------------------------------------------------------
  const refresh = useCallback(() => {
    setIsLoading(true);
    fetchCurrent();
  }, [fetchCurrent]);

  return {
    currentBands,
    failover,
    isLoading,
    lockingCategory,
    error,
    lockBands,
    unlockAll,
    toggleFailover,
    refresh,
  };
}
