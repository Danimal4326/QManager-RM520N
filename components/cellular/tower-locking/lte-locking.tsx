"use client";

import React, { useState, useEffect } from "react";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
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

import type { TowerLockConfig, TowerModemState, LteLockCell } from "@/types/tower-locking";

interface LTELockingProps {
  config: TowerLockConfig | null;
  modemState: TowerModemState | null;
  isLocking: boolean;
  onLock: (cells: LteLockCell[]) => Promise<boolean>;
  onUnlock: () => Promise<boolean>;
}

const LTELockingComponent = ({
  config,
  modemState,
  isLocking,
  onLock,
  onUnlock,
}: LTELockingProps) => {
  // Local form state for the 3 input pairs
  const [earfcn1, setEarfcn1] = useState("");
  const [pci1, setPci1] = useState("");
  const [earfcn2, setEarfcn2] = useState("");
  const [pci2, setPci2] = useState("");
  const [earfcn3, setEarfcn3] = useState("");
  const [pci3, setPci3] = useState("");

  // Sync form from config when data loads
  useEffect(() => {
    if (config?.lte?.cells) {
      const cells = config.lte.cells;
      if (cells[0]) {
        setEarfcn1(String(cells[0].earfcn));
        setPci1(String(cells[0].pci));
      }
      if (cells[1]) {
        setEarfcn2(String(cells[1].earfcn));
        setPci2(String(cells[1].pci));
      }
      if (cells[2]) {
        setEarfcn3(String(cells[2].earfcn));
        setPci3(String(cells[2].pci));
      }
    }
  }, [config?.lte?.cells]);

  // Derive enabled state from modem state (actual lock) or config
  const isEnabled = modemState?.lte_locked ?? config?.lte?.enabled ?? false;

  // Build cells array from form inputs
  const buildCells = (): LteLockCell[] => {
    const cells: LteLockCell[] = [];
    const e1 = parseInt(earfcn1, 10);
    const p1 = parseInt(pci1, 10);
    if (!isNaN(e1) && !isNaN(p1)) cells.push({ earfcn: e1, pci: p1 });

    const e2 = parseInt(earfcn2, 10);
    const p2 = parseInt(pci2, 10);
    if (!isNaN(e2) && !isNaN(p2)) cells.push({ earfcn: e2, pci: p2 });

    const e3 = parseInt(earfcn3, 10);
    const p3 = parseInt(pci3, 10);
    if (!isNaN(e3) && !isNaN(p3)) cells.push({ earfcn: e3, pci: p3 });

    return cells;
  };

  const handleToggle = async (checked: boolean) => {
    if (checked) {
      const cells = buildCells();
      if (cells.length === 0) return;
      await onLock(cells);
    } else {
      await onUnlock();
    }
  };

  return (
    <Card className="@container/card">
      <CardHeader>
        <CardTitle>LTE Tower Locking</CardTitle>
        <CardDescription>
          Manage LTE tower locking settings for your device.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <div className="grid gap-2">
          <Separator />
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-1.5">
              <TbInfoCircleFilled className="w-5 h-5 text-blue-500" />
              <p className="font-semibold text-muted-foreground text-sm">
                LTE Tower Locking Enabled
              </p>
            </div>
            <div className="flex items-center space-x-2">
              {isLocking ? (
                <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
              ) : null}
              <Switch
                id="lte-tower-locking"
                checked={isEnabled}
                onCheckedChange={handleToggle}
                disabled={isLocking}
              />
              <Label htmlFor="lte-tower-locking">
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
                      <FieldLabel htmlFor="earfcn1">E/ARFCN</FieldLabel>
                      <Input
                        id="earfcn1"
                        type="text"
                        placeholder="Enter E/ARFCN"
                        value={earfcn1}
                        onChange={(e) => setEarfcn1(e.target.value)}
                        disabled={isLocking}
                      />
                    </Field>
                    <Field>
                      <FieldLabel htmlFor="pci1">PCI</FieldLabel>
                      <Input
                        id="pci1"
                        type="text"
                        placeholder="Enter PCI"
                        value={pci1}
                        onChange={(e) => setPci1(e.target.value)}
                        disabled={isLocking}
                      />
                    </Field>
                  </div>
                  {/* Optional locking entry 2 */}
                  <div className="grid grid-cols-2 gap-4">
                    <Field>
                      <FieldLabel htmlFor="earfcn2">E/ARFCN 2</FieldLabel>
                      <Input
                        id="earfcn2"
                        type="text"
                        placeholder="Enter E/ARFCN 2"
                        value={earfcn2}
                        onChange={(e) => setEarfcn2(e.target.value)}
                        disabled={isLocking}
                      />
                    </Field>
                    <Field>
                      <FieldLabel htmlFor="pci2">PCI 2</FieldLabel>
                      <Input
                        id="pci2"
                        type="text"
                        placeholder="Enter PCI 2"
                        value={pci2}
                        onChange={(e) => setPci2(e.target.value)}
                        disabled={isLocking}
                      />
                    </Field>
                  </div>
                  {/* Optional locking entry 3 */}
                  <div className="grid grid-cols-2 gap-4">
                    <Field>
                      <FieldLabel htmlFor="earfcn3">E/ARFCN 3</FieldLabel>
                      <Input
                        id="earfcn3"
                        type="text"
                        placeholder="Enter E/ARFCN 3"
                        value={earfcn3}
                        onChange={(e) => setEarfcn3(e.target.value)}
                        disabled={isLocking}
                      />
                    </Field>
                    <Field>
                      <FieldLabel htmlFor="pci3">PCI 3</FieldLabel>
                      <Input
                        id="pci3"
                        type="text"
                        placeholder="Enter PCI 3"
                        value={pci3}
                        onChange={(e) => setPci3(e.target.value)}
                        disabled={isLocking}
                      />
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

export default LTELockingComponent;
