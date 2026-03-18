"use client";

import { useCallback, useEffect, useState } from "react";
import { EyeIcon, EyeOffIcon } from "lucide-react";
import { setupPassword } from "@/hooks/use-auth";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Field, FieldDescription, FieldGroup, FieldLabel, FieldError } from "@/components/ui/field";

// =============================================================================
// StepPassword — Onboarding step 2: create password (required)
// =============================================================================

interface StepPasswordProps {
  /** Called when password is successfully created — wizard advances */
  onSuccess: () => void;
  /** Lifts isLoading state to the shell so the Continue button shows spinner */
  onLoadingChange: (loading: boolean) => void;
  /** Ref-like: shell calls this to trigger submit from its own Continue button */
  onSubmitRef: (fn: () => Promise<void>) => void;
}

export function StepPassword({ onSuccess, onLoadingChange, onSubmitRef }: StepPasswordProps) {
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [error, setError] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = useCallback(async () => {
    setError("");

    if (password.length < 6) {
      setError("Password must be at least 6 characters.");
      return;
    }
    if (password !== confirm) {
      setError("Passwords do not match.");
      return;
    }

    setIsSubmitting(true);
    onLoadingChange(true); // call directly so the shell disables Continue immediately
    try {
      const result = await setupPassword(password, confirm);
      if (result.success) {
        onSuccess();
      } else {
        setError(result.error || "Setup failed. Please try again.");
      }
    } finally {
      setIsSubmitting(false);
      onLoadingChange(false);
    }
  }, [password, confirm, onSuccess, onLoadingChange]);

  // Register the submit function so the shell's Continue button can trigger it
  useEffect(() => {
    onSubmitRef(handleSubmit);
  }, [handleSubmit, onSubmitRef]);

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1.5">
        <h2 className="text-2xl font-semibold tracking-tight">Secure your setup</h2>
        <p className="text-sm text-muted-foreground">
          Choose a password to protect access to your modem interface.
        </p>
      </div>

      <FieldGroup>
        <Field>
          <FieldLabel htmlFor="onboard-password">New Password</FieldLabel>
          <div className="relative">
            <Input
              id="onboard-password"
              type={showPassword ? "text" : "password"}
              placeholder="Create a password"
              autoComplete="new-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              disabled={isSubmitting}
              className="pr-10"
            />
            <Button
              type="button"
              variant="ghost"
              size="icon-sm"
              className="absolute right-1 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
              onClick={() => setShowPassword((v) => !v)}
              tabIndex={-1}
              aria-label={showPassword ? "Hide password" : "Show password"}
            >
              {showPassword ? <EyeOffIcon className="size-4" /> : <EyeIcon className="size-4" />}
            </Button>
          </div>
          <FieldDescription>Minimum 6 characters</FieldDescription>
        </Field>

        <Field>
          <FieldLabel htmlFor="onboard-confirm">Confirm Password</FieldLabel>
          <div className="relative">
            <Input
              id="onboard-confirm"
              type={showConfirm ? "text" : "password"}
              placeholder="Confirm your password"
              autoComplete="new-password"
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
              disabled={isSubmitting}
              className="pr-10"
            />
            <Button
              type="button"
              variant="ghost"
              size="icon-sm"
              className="absolute right-1 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
              onClick={() => setShowConfirm((v) => !v)}
              tabIndex={-1}
              aria-label={showConfirm ? "Hide password" : "Show password"}
            >
              {showConfirm ? <EyeOffIcon className="size-4" /> : <EyeIcon className="size-4" />}
            </Button>
          </div>
        </Field>

        {error && <FieldError>{error}</FieldError>}
      </FieldGroup>
    </div>
  );
}
