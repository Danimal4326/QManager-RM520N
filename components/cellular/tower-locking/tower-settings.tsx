"use client";

import React, { useState, useEffect, useCallback } from "react";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Tooltip,
  TooltipTrigger,
  TooltipContent,
} from "@/components/ui/tooltip";
import { Separator } from "@/components/ui/separator";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import {
  TbAlertTriangleFilled,
  TbInfoCircleFilled,
  TbSquareRoundedCheckFilled,
  TbClockFilled,
  TbCircleXFilled,
} from "react-icons/tb";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Loader2 } from "lucide-react";

import type { TowerLockConfig, TowerFailoverState } from "@/types/tower-locking";
import type { ModemStatus } from "@/types/modem-status";
import { rsrpToQualityPercent, qualityLevel } from "@/types/tower-locking";

interface TowerLockingSettingsProps {
  config: TowerLockConfig | null;
  failoverState: TowerFailoverState | null;
  modemData: ModemStatus | null;
  isLoading: boolean;
  onPersistChange: (persist: boolean) => void;
  onFailoverChange: (enabled: boolean) => void;
  onThresholdChange: (threshold: number) => void;
}

const TowerLockingSettingsComponent = ({
  config,
  failoverState,
  modemData,
  isLoading,
  onPersistChange,
  onFailoverChange,
  onThresholdChange,
}: TowerLockingSettingsProps) => {
  // Local state for threshold input (debounced save)
  const [thresholdInput, setThresholdInput] = useState<string>("");

  // Sync threshold from config
  useEffect(() => {
    if (config?.failover?.threshold !== undefined) {
      setThresholdInput(String(config.failover.threshold));
    }
  }, [config?.failover?.threshold]);

  // Debounced threshold save
  const handleThresholdBlur = useCallback(() => {
    const val = parseInt(thresholdInput, 10);
    if (!isNaN(val) && val >= 0 && val <= 100) {
      onThresholdChange(val);
    }
  }, [thresholdInput, onThresholdChange]);

  // --- Determine which RSRP to use based on network type ---
  const networkType = modemData?.network?.type ?? "";
  let activeRsrp: number | null = null;
  let activeEarfcn: number | string = "-";
  let activePci: number | string = "-";

  if (networkType === "5G-SA") {
    activeRsrp = modemData?.nr?.rsrp ?? null;
    activeEarfcn = modemData?.nr?.arfcn ?? "-";
    activePci = modemData?.nr?.pci ?? "-";
  } else {
    // LTE or 5G-NSA — use LTE PCell
    activeRsrp = modemData?.lte?.rsrp ?? null;
    activeEarfcn = modemData?.lte?.earfcn ?? "-";
    activePci = modemData?.lte?.pci ?? "-";
  }

  const signalQualityPct = rsrpToQualityPercent(activeRsrp);
  const qualityLvl = qualityLevel(signalQualityPct);

  // --- Signal quality badge styling ---
  const qualityBadgeStyles: Record<string, string> = {
    good: "bg-green-500/20 text-green-500 hover:bg-green-500/30 border border-green-300/50 backdrop-blur-sm",
    fair: "bg-yellow-500/20 text-yellow-500 hover:bg-yellow-500/30 border border-yellow-300/50 backdrop-blur-sm",
    poor: "bg-orange-500/20 text-orange-500 hover:bg-orange-500/30 border border-orange-300/50 backdrop-blur-sm",
    critical: "bg-red-500/20 text-red-500 hover:bg-red-500/30 border border-red-300/50 backdrop-blur-sm",
    none: "bg-muted text-muted-foreground border border-border backdrop-blur-sm",
  };

  const qualityIcons: Record<string, React.ReactNode> = {
    good: <TbSquareRoundedCheckFilled />,
    fair: <TbAlertTriangleFilled />,
    poor: <TbAlertTriangleFilled />,
    critical: <TbCircleXFilled />,
    none: null,
  };

  // --- Failover status badge ---
  const renderFailoverBadge = () => {
    if (!failoverState) {
      return (
        <Badge variant="outline" className="bg-muted text-muted-foreground border border-border backdrop-blur-sm">
          <Loader2 className="w-3 h-3 animate-spin" />
          Loading
        </Badge>
      );
    }

    if (failoverState.watcher_running) {
      return (
        <Badge variant="outline" className="bg-yellow-500/20 text-yellow-500 hover:bg-yellow-500/30 border border-yellow-300/50 backdrop-blur-sm">
          <TbClockFilled />
          Checking Signal...
        </Badge>
      );
    }

    if (failoverState.activated) {
      return (
        <Badge variant="outline" className="bg-orange-500/20 text-orange-500 hover:bg-orange-500/30 border border-orange-300/50 backdrop-blur-sm">
          <TbAlertTriangleFilled />
          Unlocked due to Poor Signal
        </Badge>
      );
    }

    if (!failoverState.enabled) {
      return (
        <Badge variant="outline" className="bg-muted text-muted-foreground border border-border backdrop-blur-sm">
          Disabled
        </Badge>
      );
    }

    return (
      <Badge variant="outline" className="bg-green-500/20 text-green-500 hover:bg-green-500/30 border border-green-300/50 backdrop-blur-sm">
        <TbSquareRoundedCheckFilled />
        Ready
      </Badge>
    );
  };

  // --- Schedule status badge ---
  const renderScheduleBadge = () => {
    if (!config) {
      return (
        <Badge variant="outline" className="bg-muted text-muted-foreground border border-border backdrop-blur-sm">
          <Loader2 className="w-3 h-3 animate-spin" />
          Loading
        </Badge>
      );
    }

    if (config.schedule.enabled) {
      return (
        <Badge variant="outline" className="bg-green-500/20 text-green-500 hover:bg-green-500/30 border border-green-300/50 backdrop-blur-sm">
          <TbSquareRoundedCheckFilled />
          Active
        </Badge>
      );
    }

    return (
      <Badge variant="outline" className="bg-muted text-muted-foreground border border-border backdrop-blur-sm">
        Inactive
      </Badge>
    );
  };

  if (isLoading) {
    return (
      <Card className="@container/card">
        <CardHeader>
          <CardTitle>Tower Locking Settings</CardTitle>
          <CardDescription>
            Configure cellular tower locking for the Primary Cell (PCell). Not
            compatible with NR5G-NSA.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="@container/card">
      <CardHeader>
        <CardTitle>Tower Locking Settings</CardTitle>
        <CardDescription>
          Configure cellular tower locking for the Primary Cell (PCell). Not
          compatible with NR5G-NSA.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <div className="grid gap-2">
          <Separator />
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-1.5">
              <Tooltip>
                <TooltipTrigger asChild>
                  <TbInfoCircleFilled className="w-5 h-5 text-blue-500" />
                </TooltipTrigger>
                <TooltipContent>
                  <p>
                    When enabled, the device will persist tower locking settings
                    across reboots.
                  </p>
                </TooltipContent>
              </Tooltip>
              <p className="font-semibold text-muted-foreground text-sm">
                Persist Locking
              </p>
            </div>
            <div className="flex items-center space-x-2">
              <Switch
                id="tower-persist"
                checked={config?.persist ?? false}
                onCheckedChange={onPersistChange}
              />
              <Label htmlFor="tower-persist">
                {config?.persist ? "Enabled" : "Disabled"}
              </Label>
            </div>
          </div>
          <Separator />
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-1.5">
              <Tooltip>
                <TooltipTrigger asChild>
                  <TbInfoCircleFilled className="w-5 h-5 text-blue-500" />
                </TooltipTrigger>
                <TooltipContent>
                  <p>
                    When enabled, the device will unlock from the tower if
                    signal quality degrades below a certain threshold or becomes
                    unavailable.
                  </p>
                </TooltipContent>
              </Tooltip>
              <p className="font-semibold text-muted-foreground text-sm">
                Failover
              </p>
            </div>
            <div className="flex items-center space-x-2">
              <Switch
                id="tower-failover"
                checked={config?.failover?.enabled ?? true}
                onCheckedChange={onFailoverChange}
              />
              <Label htmlFor="tower-failover">
                {config?.failover?.enabled ? "Enabled" : "Disabled"}
              </Label>
            </div>
          </div>
          <Separator />
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-1.5">
              <Tooltip>
                <TooltipTrigger asChild>
                  <TbInfoCircleFilled className="w-5 h-5 text-blue-500" />
                </TooltipTrigger>
                <TooltipContent>
                  <p>
                    This will only take effect if Failover is enabled. Set the
                    signal quality threshold below which the device will unlock
                    from the tower.
                  </p>
                </TooltipContent>
              </Tooltip>
              <p className="font-semibold text-muted-foreground text-sm">
                Failover Threshold
              </p>
            </div>
            <div className="flex items-center space-x-2">
              <Input
                type="text"
                placeholder="20%"
                className="w-16 h-8 text-center"
                value={thresholdInput}
                onChange={(e) => setThresholdInput(e.target.value)}
                onBlur={handleThresholdBlur}
                onKeyDown={(e) => {
                  if (e.key === "Enter") handleThresholdBlur();
                }}
              />
            </div>
          </div>
          <Separator />
          <div className="flex items-center justify-between">
            <p className="text-sm font-semibold text-muted-foreground ">
              Current Signal Quality
            </p>
            <div className="flex items-center gap-1.5">
              <p className="text-sm font-semibold ">
                <Badge
                  variant="outline"
                  className={qualityBadgeStyles[qualityLvl]}
                >
                  {qualityIcons[qualityLvl]}
                  {activeRsrp !== null ? `${signalQualityPct}%` : "N/A"}
                </Badge>
              </p>
            </div>
          </div>
          <Separator />
          <div className="flex items-center justify-between">
            <p className="text-sm font-semibold text-muted-foreground ">
              Failover Status
            </p>
            <div className="flex items-center gap-1.5">
              <p className="text-sm font-semibold ">
                {renderFailoverBadge()}
              </p>
            </div>
          </div>
          <Separator />
          <div className="flex items-center justify-between">
            <p className="text-sm font-semibold text-muted-foreground ">
              Schedule Locking Status
            </p>
            <div className="flex items-center gap-1.5">
              <p className="text-sm font-semibold ">
                {renderScheduleBadge()}
              </p>
            </div>
          </div>
          <Separator />
          <div className="flex items-center justify-between">
            <p className="text-sm font-semibold text-muted-foreground ">
              Active PCell E/AFRCN
            </p>
            <div className="flex items-center gap-1.5">
              <p className="text-sm font-semibold ">
                {activeEarfcn !== null ? String(activeEarfcn) : "-"}
              </p>
            </div>
          </div>
          <Separator />
          <div className="flex items-center justify-between">
            <p className="text-sm font-semibold text-muted-foreground ">
              Active PCell ID (PCI)
            </p>
            <div className="flex items-center gap-1.5">
              <p className="text-sm font-semibold ">
                {activePci !== null ? String(activePci) : "-"}
              </p>
            </div>
          </div>
          <Separator />
        </div>
      </CardContent>
    </Card>
  );
};

export default TowerLockingSettingsComponent;
