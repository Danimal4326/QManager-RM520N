"use client";

import React from "react";
import { motion } from "motion/react";
import { SignalIcon } from "lucide-react";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { useModemStatus } from "@/hooks/use-modem-status";
import {
  getSignalQuality,
  signalToProgress,
  RSRP_THRESHOLDS,
  RSRQ_THRESHOLDS,
  SINR_THRESHOLDS,
} from "@/types/modem-status";
import type { SignalPerAntenna } from "@/types/modem-status";

// =============================================================================
// Constants
// =============================================================================

const ANTENNA_LABELS = [
  { name: "Main", rx: "RX0" },
  { name: "Diversity", rx: "RX1" },
  { name: "MIMO 3", rx: "RX2" },
  { name: "MIMO 4", rx: "RX3" },
] as const;

const QUALITY_COLORS: Record<string, string> = {
  excellent: "text-success",
  good: "text-success",
  fair: "text-warning",
  poor: "text-destructive",
  none: "text-muted-foreground",
};

// =============================================================================
// Helpers
// =============================================================================

/** Check if a technology has any non-null antenna data */
function hasData(
  signal: SignalPerAntenna | undefined,
  prefix: "lte" | "nr"
): boolean {
  if (!signal) return false;
  const rsrp = signal[`${prefix}_rsrp`];
  const rsrq = signal[`${prefix}_rsrq`];
  const sinr = signal[`${prefix}_sinr`];
  return [...rsrp, ...rsrq, ...sinr].some((v) => v !== null);
}

/** Format a signal value with unit, or "—" for null */
function fmtSignal(value: number | null, unit: string): string {
  if (value === null || value === undefined) return "—";
  return `${value} ${unit}`;
}

// =============================================================================
// Sub-components
// =============================================================================

/** Animated progress bar (spring scaleX) — matches active-bands.tsx pattern */
function AnimatedProgress({ value }: { value: number }) {
  return (
    <div className="h-1.5 flex-1 min-w-0 overflow-hidden rounded-full bg-secondary">
      <motion.div
        className="h-full rounded-full bg-primary"
        initial={{ scaleX: 0 }}
        animate={{ scaleX: value / 100 }}
        style={{ originX: 0 }}
        transition={{ type: "spring", stiffness: 180, damping: 24 }}
      />
    </div>
  );
}

/** A single metric row: label → progress bar → colored value */
function MetricRow({
  label,
  value,
  unit,
  thresholds,
}: {
  label: string;
  value: number | null;
  unit: string;
  thresholds: { excellent: number; good: number; fair: number; poor: number };
}) {
  const quality = getSignalQuality(value, thresholds);
  const progress = signalToProgress(value, thresholds);

  return (
    <div className="flex items-center gap-2">
      <span className="text-[10px] uppercase tracking-wide text-muted-foreground w-9 shrink-0">
        {label}
      </span>
      <AnimatedProgress value={progress} />
      <span
        className={`text-xs font-semibold tabular-nums min-w-[60px] text-right shrink-0 ${QUALITY_COLORS[quality]}`}
      >
        {fmtSignal(value, unit)}
      </span>
    </div>
  );
}

/** A single antenna section with 3 stacked metric rows */
function AntennaSection({
  name,
  rx,
  rsrp,
  rsrq,
  sinr,
}: {
  name: string;
  rx: string;
  rsrp: number | null;
  rsrq: number | null;
  sinr: number | null;
}) {
  const isInactive = rsrp === null && rsrq === null && sinr === null;

  return (
    <div className={isInactive ? "opacity-25" : undefined}>
      <div className="flex items-baseline gap-1.5 mb-2">
        <span className="text-sm font-semibold">{name}</span>
        <span className="text-[10px] text-muted-foreground">{rx}</span>
      </div>
      <div className="grid gap-1.5">
        <MetricRow label="RSRP" value={rsrp} unit="dBm" thresholds={RSRP_THRESHOLDS} />
        <MetricRow label="RSRQ" value={rsrq} unit="dB" thresholds={RSRQ_THRESHOLDS} />
        <MetricRow label="SINR" value={sinr} unit="dB" thresholds={SINR_THRESHOLDS} />
      </div>
    </div>
  );
}

/** Technology signal card (LTE or NR5G) */
function TechCard({
  title,
  description,
  signal,
  prefix,
}: {
  title: string;
  description: string;
  signal: SignalPerAntenna | undefined;
  prefix: "lte" | "nr";
}) {
  const active = hasData(signal, prefix);

  if (!active) {
    return (
      <Card className="opacity-60">
        <CardHeader>
          <CardTitle>{title}</CardTitle>
          <CardDescription>{description}</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex flex-col items-center justify-center py-8 text-center">
            <SignalIcon className="size-8 text-muted-foreground/15 mb-2" />
            <p className="text-sm text-muted-foreground/60">
              No {title.split(" ")[0]} signal detected
            </p>
            <p className="text-xs text-muted-foreground/40 mt-1">
              Antenna metrics appear when {prefix === "lte" ? "4G" : "NR"} is active
            </p>
          </div>
        </CardContent>
      </Card>
    );
  }

  const rsrp = signal![`${prefix}_rsrp`];
  const rsrq = signal![`${prefix}_rsrq`];
  const sinr = signal![`${prefix}_sinr`];

  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent>
        <motion.div
          className="divide-y divide-border"
          initial="hidden"
          animate="visible"
          variants={{
            hidden: {},
            visible: { transition: { staggerChildren: 0.05 } },
          }}
        >
          {ANTENNA_LABELS.map((ant, i) => (
            <motion.div
              key={ant.rx}
              className={i === 0 ? "pb-3" : "py-3"}
              variants={{
                hidden: { opacity: 0, y: 6 },
                visible: { opacity: 1, y: 0 },
              }}
              transition={{ duration: 0.2, ease: "easeOut" }}
            >
              <AntennaSection
                name={ant.name}
                rx={ant.rx}
                rsrp={rsrp[i] ?? null}
                rsrq={rsrq[i] ?? null}
                sinr={sinr[i] ?? null}
              />
            </motion.div>
          ))}
        </motion.div>
      </CardContent>
    </Card>
  );
}

// =============================================================================
// Loading Skeleton
// =============================================================================

function AntennaStatsSkeleton() {
  return (
    <div className="grid grid-cols-1 @3xl/main:grid-cols-2 gap-4">
      {[0, 1].map((i) => (
        <Card key={i}>
          <CardHeader>
            <Skeleton className="h-5 w-28" />
            <Skeleton className="h-4 w-48 mt-1" />
          </CardHeader>
          <CardContent>
            <div className="divide-y divide-border">
              {[0, 1, 2, 3].map((j) => (
                <div key={j} className={j === 0 ? "pb-3" : "py-3"}>
                  <Skeleton className="h-4 w-24 mb-2" />
                  <div className="grid gap-1.5">
                    {[0, 1, 2].map((k) => (
                      <div key={k} className="flex items-center gap-2">
                        <Skeleton className="h-3 w-9" />
                        <Skeleton className="h-1.5 flex-1" />
                        <Skeleton className="h-3 w-[60px]" />
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}

// =============================================================================
// Main Component
// =============================================================================

export default function AntennaStatistics() {
  const { data, isLoading } = useModemStatus();
  const signal = data?.signal_per_antenna;

  const lteHasData = hasData(signal, "lte");
  const nrHasData = hasData(signal, "nr");

  // Dynamic ordering: active tech first. Default LTE first.
  const nrFirst = nrHasData && !lteHasData;

  const lteCard = (
    <TechCard
      title="LTE Signal"
      description="Per-antenna metrics for 4G LTE"
      signal={signal}
      prefix="lte"
    />
  );

  const nrCard = (
    <TechCard
      title="NR5G Signal"
      description="Per-antenna metrics for 5G NR"
      signal={signal}
      prefix="nr"
    />
  );

  return (
    <div className="@container/main mx-auto p-2">
      <div className="mb-6">
        <h1 className="text-3xl font-bold mb-2">Antenna Statistics</h1>
        <p className="text-muted-foreground">
          Per-antenna signal metrics for each receiver chain. Compare signal
          quality across Main, Diversity, and MIMO antenna ports.
        </p>
      </div>
      {isLoading ? (
        <AntennaStatsSkeleton />
      ) : (
        <div className="grid grid-cols-1 @3xl/main:grid-cols-2 gap-4">
          {nrFirst ? nrCard : lteCard}
          {nrFirst ? lteCard : nrCard}
        </div>
      )}
    </div>
  );
}
