"use client";

import { useEffect, useState } from "react";
import { CheckIcon } from "lucide-react";
import { Button } from "@/components/ui/button";

// =============================================================================
// StepDone — Onboarding step 6: completion screen
// =============================================================================

export function StepDone() {
  const [show, setShow] = useState(false);

  useEffect(() => {
    // Brief delay so the animation plays after the step transition
    const timer = setTimeout(() => setShow(true), 80);
    return () => clearTimeout(timer);
  }, []);

  const handleGoToDashboard = () => {
    window.location.href = "/dashboard/";
  };

  return (
    <div className="flex flex-col items-center gap-6 text-center py-2">
      {/* Animated checkmark */}
      <div
        className="flex size-16 items-center justify-center rounded-full bg-primary/10 transition-all duration-500"
        style={{
          opacity: show ? 1 : 0,
          transform: show ? "scale(1)" : "scale(0.6)",
        }}
      >
        <CheckIcon className="size-8 text-primary stroke-[2.5]" />
      </div>

      <div className="flex flex-col gap-2">
        <h2 className="text-2xl font-semibold tracking-tight">You&apos;re all set!</h2>
        <p className="text-sm text-muted-foreground max-w-xs leading-relaxed">
          QManager is ready. Everything you configured is active, and you can
          change any setting anytime from the sidebar.
        </p>
      </div>

      {/* Tip callout */}
      <div className="w-full rounded-xl bg-muted/60 border border-border px-4 py-3 text-left">
        <p className="text-xs text-muted-foreground leading-relaxed">
          <span className="font-medium text-foreground">Pro tip:</span> Visit{" "}
          <span className="font-medium">Cellular › Band Locking</span> to
          fine-tune signal strength, or{" "}
          <span className="font-medium">Monitoring › Watchdog</span> to set up
          automatic recovery.
        </p>
      </div>

      <Button onClick={handleGoToDashboard} className="w-full" size="lg">
        Go to Dashboard
      </Button>
    </div>
  );
}
