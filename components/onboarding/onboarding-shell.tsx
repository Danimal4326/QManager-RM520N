"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { ArrowLeftIcon, ArrowRightIcon } from "lucide-react";

// =============================================================================
// OnboardingShell — Full-screen centered card wrapper for onboarding wizard
// =============================================================================
// Provides:
//   - Progress dot indicator (6 dots)
//   - Step content slot with fade + translate-y transition
//   - Back / Skip / Continue footer buttons
// =============================================================================

const TOTAL_STEPS = 6;

interface OnboardingShellProps {
  /** 1-based step index */
  currentStep: number;
  /** Called when "Continue" or "Get Started" is clicked */
  onNext: () => void;
  /** Called when "Back" is clicked */
  onBack: () => void;
  /** Called when "Skip" is clicked — undefined hides the Skip button */
  onSkip?: () => void;
  /** Whether the Continue button is in a loading state */
  isLoading?: boolean;
  /** Custom label for the Continue button */
  continueLabel?: string;
  /** Whether the Continue button is disabled */
  continueDisabled?: boolean;
  children: React.ReactNode;
}

export function OnboardingShell({
  currentStep,
  onNext,
  onBack,
  onSkip,
  isLoading = false,
  continueLabel,
  continueDisabled = false,
  children,
}: OnboardingShellProps) {
  // Track the previously rendered step so we can animate transitions
  const [visibleStep, setVisibleStep] = useState(currentStep);
  const [isVisible, setIsVisible] = useState(true);

  useEffect(() => {
    if (currentStep === visibleStep) return;
    // Fade out, swap content, fade in
    setIsVisible(false);
    const timer = setTimeout(() => {
      setVisibleStep(currentStep);
      setIsVisible(true);
    }, 150);
    return () => clearTimeout(timer);
  }, [currentStep, visibleStep]);

  const isFirstStep = currentStep === 1;
  const isLastStep = currentStep === TOTAL_STEPS;
  const showBack = !isFirstStep && !isLastStep;
  const showSkip = !!onSkip && !isFirstStep && !isLastStep;

  const defaultContinueLabel = isFirstStep
    ? "Get Started"
    : isLastStep
      ? "Go to Dashboard"
      : "Continue";

  return (
    <div className="flex min-h-svh items-center justify-center bg-background p-6">
      <div className="w-full max-w-md">
        {/* Card */}
        <div className="rounded-2xl border border-border bg-card shadow-2xl ring-1 ring-border/50 px-10 py-10 flex flex-col gap-8">
          {/* Progress dots */}
          <div className="flex items-center justify-center gap-2">
            {Array.from({ length: TOTAL_STEPS }, (_, i) => {
              const step = i + 1;
              const isPast = step < currentStep;
              const isCurrent = step === currentStep;
              return (
                <span
                  key={step}
                  className={cn(
                    "block rounded-full transition-all duration-300",
                    isPast && "h-2 w-2 bg-primary",
                    isCurrent &&
                      "h-2 w-2 bg-primary ring-2 ring-primary/30 ring-offset-1 ring-offset-card",
                    !isPast &&
                      !isCurrent &&
                      "h-2 w-2 bg-muted-foreground/25"
                  )}
                />
              );
            })}
          </div>

          {/* Step content with fade transition */}
          <div
            className={cn(
              "transition-all duration-150",
              isVisible ? "opacity-100 translate-y-0" : "opacity-0 translate-y-1"
            )}
          >
            {children}
          </div>

          {/* Footer buttons */}
          {!isLastStep && (
            <div className="flex items-center justify-between gap-3">
              {showBack ? (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={onBack}
                  disabled={isLoading}
                  className="gap-1.5 text-muted-foreground"
                >
                  <ArrowLeftIcon className="size-3.5" />
                  Back
                </Button>
              ) : (
                <div />
              )}

              <div className="flex items-center gap-2">
                {showSkip && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={onSkip}
                    disabled={isLoading}
                    className="text-muted-foreground"
                  >
                    Skip
                  </Button>
                )}
                <Button
                  onClick={onNext}
                  disabled={isLoading || continueDisabled}
                  size="sm"
                  className="gap-1.5 min-w-[100px]"
                >
                  {isLoading ? (
                    <span className="flex items-center gap-1.5">
                      <span className="size-3.5 animate-spin rounded-full border-2 border-current border-t-transparent" />
                      Working…
                    </span>
                  ) : (
                    <>
                      {continueLabel ?? defaultContinueLabel}
                      {!isFirstStep && (
                        <ArrowRightIcon className="size-3.5" />
                      )}
                    </>
                  )}
                </Button>
              </div>
            </div>
          )}
        </div>

        {/* Branding footer */}
        <p className="mt-4 text-center text-xs text-muted-foreground/60">
          QManager — Quectel Modem Management
        </p>
      </div>
    </div>
  );
}
