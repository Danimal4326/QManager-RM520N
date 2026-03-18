"use client";

// =============================================================================
// StepWelcome — Onboarding step 1: brand intro
// =============================================================================

export function StepWelcome() {
  return (
    <div className="flex flex-col items-center gap-5 text-center">
      {/* Logo */}
      <div className="flex size-16 items-center justify-center rounded-xl bg-primary/10 p-2">
        <img
          src="/qmanager-logo.svg"
          alt="QManager"
          className="size-full"
        />
      </div>

      <div className="flex flex-col gap-2">
        <h1 className="text-2xl font-semibold tracking-tight">
          Welcome to QManager
        </h1>
        <p className="text-sm text-muted-foreground">
          Your Quectel modem, intelligently managed.
        </p>
      </div>

      <p className="text-sm text-muted-foreground max-w-xs leading-relaxed">
        Let&apos;s get you set up in a few quick steps. Only your password is
        required — the rest is optional and can be changed anytime.
      </p>
    </div>
  );
}
