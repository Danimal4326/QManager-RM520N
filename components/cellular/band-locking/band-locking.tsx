"use client";

import React from "react";
import BandCardsComponent from "./band-cards";
import BandSettingsComponent from "./band-settings";
import { useBandLocking } from "@/hooks/use-band-locking";
import { useModemStatus } from "@/hooks/use-modem-status";
import {
  parseBandString,
  getBandsForCategory,
  type BandCategory,
} from "@/types/band-locking";
import type { CarrierComponent } from "@/types/modem-status";

// =============================================================================
// BandLockingComponent — Page Coordinator
// =============================================================================
// Owns both hooks and distributes data to child components via props.
//
// Data sources:
//   useModemStatus()  → supported_*_bands (boot-only, from policy_band)
//                     → carrier_components (active bands, from QCAINFO Tier 2)
//   useBandLocking()  → currentBands (locked config from ue_capability_band)
//                     → failover state + lock/unlock/toggle actions
// =============================================================================

/** Band card configuration — static, one entry per card */
const BAND_CARDS: {
  category: BandCategory;
  title: string;
  description: string;
}[] = [
  {
    category: "lte",
    title: "LTE Band Locking",
    description: "Select the LTE bands to lock for your device.",
  },
  {
    category: "nsa_nr5g",
    title: "NSA Band Locking",
    description: "Select the NR5G NSA bands to lock for your device.",
  },
  {
    category: "sa_nr5g",
    title: "SA Band Locking",
    description: "Select the NR5G SA bands to lock for your device.",
  },
];

const BandLockingComponent = () => {
  const { data, isLoading: statusLoading } = useModemStatus();
  const {
    currentBands,
    failover,
    isLoading: bandsLoading,
    lockingCategory,
    error,
    lockBands,
    unlockAll,
    toggleFailover,
    refresh,
  } = useBandLocking();

  // --- Derive supported bands from poller boot data -------------------------
  const supportedBands = {
    lte: parseBandString(data?.device.supported_lte_bands),
    nsa_nr5g: parseBandString(data?.device.supported_nsa_nr5g_bands),
    sa_nr5g: parseBandString(data?.device.supported_sa_nr5g_bands),
  };

  // --- Derive active bands from carrier_components (QCAINFO) ----------------
  const carrierComponents = data?.network.carrier_components ?? [];

  // Overall loading: either poller hasn't loaded yet or bands haven't loaded
  const isPageLoading = statusLoading || bandsLoading;

  return (
    <div className="@container/main mx-auto p-2">
      <div className="mb-6">
        <h1 className="text-3xl font-bold mb-2">Band Locking</h1>
        <p className="text-muted-foreground max-w-5xl">
          Manage and configure band locking settings for your cellular device to
          optimize network performance and connectivity.
        </p>
      </div>
      <div className="grid grid-cols-1 @xl/main:grid-cols-2 @5xl/main:grid-cols-2 grid-flow-row gap-4 *:data-[slot=card]:from-primary/5 *:data-[slot=card]:to-card dark:*:data-[slot=card]:bg-card *:data-[slot=card]:bg-linear-to-t *:data-[slot=card]:shadow-xs">
        <BandSettingsComponent
          failover={failover}
          carrierComponents={carrierComponents}
          onToggleFailover={toggleFailover}
          isLoading={isPageLoading}
        />
        {BAND_CARDS.map(({ category, title, description }) => (
          <BandCardsComponent
            key={category}
            title={title}
            description={description}
            bandCategory={category}
            supportedBands={supportedBands[category]}
            currentLockedBands={
              currentBands
                ? parseBandString(getBandsForCategory(currentBands, category))
                : []
            }
            onLock={(bands) => lockBands(category, bands)}
            onUnlockAll={() => unlockAll(category, supportedBands[category])}
            isLocking={lockingCategory === category}
            isLoading={isPageLoading}
            error={error}
          />
        ))}
      </div>
    </div>
  );
};

export default BandLockingComponent;
