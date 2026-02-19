"use client";

import React, { useState, useEffect } from "react";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { TbInfoCircleFilled } from "react-icons/tb";
import { Input } from "@/components/ui/input";
import { Loader2 } from "lucide-react";

import {
  Field,
  FieldGroup,
  FieldLabel,
  FieldSet,
} from "@/components/ui/field";

import type {
  TowerLockConfig,
  TowerModemState,
  NrSaLockCell,
} from "@/types/tower-locking";
import type { NetworkType } from "@/types/modem-status";
import { SCS_OPTIONS } from "@/types/tower-locking";

interface NRSALockingProps {
  config: TowerLockConfig | null;
  modemState: TowerModemState | null;
  networkType: NetworkType | string;
  isLocking: boolean;
  onLock: (cell: NrSaLockCell) => Promise<boolean>;
  onUnlock: () => Promise<boolean>;
}

const NRSALockingComponent = ({
  config,
  modemState,
  networkType,
  isLocking,
  onLock,
  onUnlock,
}: NRSALockingProps) => {
  // Local form state
  const [arfcn, setArfcn] = useState("");
  const [pci, setPci] = useState("");
  const [band, setBand] = useState("");
  const [scs, setScs] = useState("");

  // Sync form from config when data loads
  useEffect(() => {
    if (config?.nr_sa) {
      if (config.nr_sa.arfcn !== null) setArfcn(String(config.nr_sa.arfcn));
      if (config.nr_sa.pci !== null) setPci(String(config.nr_sa.pci));
      if (config.nr_sa.band !== null) setBand(String(config.nr_sa.band));
      if (config.nr_sa.scs !== null) setScs(String(config.nr_sa.scs));
    }
  }, [config?.nr_sa]);

  // Derive enabled state from modem state or config
  const isEnabled = modemState?.nr_locked ?? config?.nr_sa?.enabled ?? false;

  // NSA mode gating — NR-SA locking not available in NSA mode
  const isNsaMode = networkType === "5G-NSA";
  const isLteOnly = networkType === "LTE";
  const isDisabled = isNsaMode || isLteOnly || isLocking;

  const handleToggle = async (checked: boolean) => {
    if (checked) {
      const parsedArfcn = parseInt(arfcn, 10);
      const parsedPci = parseInt(pci, 10);
      const parsedBand = parseInt(band, 10);
      const parsedScs = parseInt(scs, 10);

      if (
        isNaN(parsedArfcn) ||
        isNaN(parsedPci) ||
        isNaN(parsedBand) ||
        isNaN(parsedScs)
      ) {
        return; // All fields required
      }

      await onLock({
        arfcn: parsedArfcn,
        pci: parsedPci,
        band: parsedBand,
        scs: parsedScs,
      });
    } else {
      await onUnlock();
    }
  };

  return (
    <Card className={`@container/card ${isDisabled && !isLocking ? "opacity-60" : ""}`}>
      <CardHeader>
        <CardTitle>NR-SA Tower Locking</CardTitle>
        <CardDescription>
          Manage NR-SA tower locking settings for your device.
          {isNsaMode && " Not compatible with NR5G-NSA mode."}
          {isLteOnly && " No NR connection available."}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <div className="grid gap-2">
          <Separator />
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-1.5">
              <TbInfoCircleFilled className="w-5 h-5 text-blue-500" />
              <p className="font-semibold text-muted-foreground text-sm">
                NR Tower Locking Enabled
              </p>
            </div>
            <div className="flex items-center space-x-2">
              {isLocking ? (
                <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
              ) : null}
              <Switch
                id="nr-sa-tower-locking"
                checked={isEnabled}
                onCheckedChange={handleToggle}
                disabled={isDisabled}
              />
              <Label htmlFor="nr-sa-tower-locking">
                {isEnabled ? "Enabled" : "Disabled"}
              </Label>
            </div>
          </div>
          <Separator />
          <form
            className="grid gap-4 mt-6"
            onSubmit={(e) => e.preventDefault()}
          >
            <div className="w-full">
              <FieldSet>
                <FieldGroup>
                  <div className="grid grid-cols-2 gap-4">
                    <Field>
                      <FieldLabel htmlFor="nrarfcn1">NR ARFCN</FieldLabel>
                      <Input
                        id="nrarfcn1"
                        type="text"
                        placeholder="Enter NR ARFCN"
                        value={arfcn}
                        onChange={(e) => setArfcn(e.target.value)}
                        disabled={isDisabled}
                      />
                    </Field>
                    <Field>
                      <FieldLabel htmlFor="nrpci">NR PCI</FieldLabel>
                      <Input
                        id="nrpci"
                        type="text"
                        placeholder="Enter NR PCI"
                        value={pci}
                        onChange={(e) => setPci(e.target.value)}
                        disabled={isDisabled}
                      />
                    </Field>
                  </div>
                  <div className="grid grid-cols-2 gap-4">
                    <Field>
                      <FieldLabel htmlFor="nr-band">NR Band</FieldLabel>
                      <Input
                        id="nr-band"
                        type="text"
                        placeholder="Enter NR Band"
                        value={band}
                        onChange={(e) => setBand(e.target.value)}
                        disabled={isDisabled}
                      />
                    </Field>
                    <Field>
                      <FieldLabel htmlFor="scs">SCS</FieldLabel>
                      <Select
                        value={scs}
                        onValueChange={setScs}
                        disabled={isDisabled}
                      >
                        <SelectTrigger>
                          <SelectValue placeholder="SCS" />
                        </SelectTrigger>
                        <SelectContent>
                          {SCS_OPTIONS.map((opt) => (
                            <SelectItem
                              key={opt.value}
                              value={String(opt.value)}
                            >
                              {opt.label}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </Field>
                  </div>
                </FieldGroup>
              </FieldSet>
            </div>
          </form>
        </div>
      </CardContent>
    </Card>
  );
};

export default NRSALockingComponent;
