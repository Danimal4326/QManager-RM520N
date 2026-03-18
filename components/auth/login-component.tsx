"use client";

import { useCallback, useEffect, useState } from "react";
import { useLogin } from "@/hooks/use-auth";
import { Button } from "@/components/ui/button";
import {
  Field,
  FieldDescription,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Spinner } from "@/components/ui/spinner";

export default function LoginComponent() {
  const { status, login, setup } = useLogin();

  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [retryAfter, setRetryAfter] = useState(0);

  // Redirect to dedicated onboarding wizard when this is a fresh install
  useEffect(() => {
    if (status === "setup_required") {
      window.location.href = "/setup/";
    }
  }, [status]);

  const isSetup = status === "setup_required";

  // Rate limit countdown timer
  useEffect(() => {
    if (retryAfter <= 0) return;

    const id = setInterval(() => {
      setRetryAfter((prev) => (prev <= 1 ? 0 : prev - 1));
    }, 1000);

    return () => clearInterval(id);
  }, [retryAfter]);

  const handleSubmit = useCallback(
    async (e: React.FormEvent) => {
      e.preventDefault();
      setError("");
      setIsSubmitting(true);

      try {
        if (isSetup) {
          if (password.length < 6) {
            setError("Password must be at least 6 characters.");
            return;
          }
          if (password !== confirm) {
            setError("Passwords do not match.");
            return;
          }
          const result = await setup(password, confirm);
          if (!result.success) {
            setError(result.error || "Setup failed.");
          }
        } else {
          const result = await login(password);
          if (!result.success) {
            if (result.retry_after) {
              setRetryAfter(result.retry_after);
              setError(
                `Too many failed attempts. Try again in ${result.retry_after} seconds.`
              );
            } else {
              setError(result.error || "Invalid password.");
            }
          }
        }
      } finally {
        setIsSubmitting(false);
      }
    },
    [isSetup, password, confirm, login, setup]
  );

  // Show loading only for the brief setup detection check
  if (status === "loading") {
    return (
      <div className="flex flex-col items-center gap-4 py-12">
        <Spinner className="size-6" />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <form onSubmit={handleSubmit}>
        <FieldGroup>
          <div className="flex flex-col items-center gap-2 text-center">
            <div className="flex size-16 p-1 items-center justify-center rounded-md">
              <img
                src="/qmanager-logo.svg"
                alt="QManager Logo"
                className="size-full"
              />
            </div>
            <h1 className="text-xl font-bold">
              {isSetup ? "Set Up QManager" : "Welcome to QManager"}
            </h1>
            <FieldDescription>
              {isSetup
                ? "Create a password to secure your QManager interface."
                : "Enter your QManager password to continue."}
            </FieldDescription>
          </div>

          <Field>
            <FieldLabel htmlFor="password">
              {isSetup ? "New Password" : "Password"}
            </FieldLabel>
            <Input
              id="password"
              type="password"
              placeholder={isSetup ? "Create a password" : "Enter your password"}
              autoComplete={isSetup ? "new-password" : "current-password"}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              disabled={isSubmitting}
            />
          </Field>

          {isSetup && (
            <Field>
              <FieldLabel htmlFor="confirm">Confirm Password</FieldLabel>
              <Input
                id="confirm"
                type="password"
                placeholder="Confirm your password"
                autoComplete="new-password"
                value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
                required
                disabled={isSubmitting}
              />
            </Field>
          )}

          {error && (
            <p role="alert" className="text-sm text-destructive">
              {error}
            </p>
          )}

          <Field>
            <Button
              type="submit"
              className="w-full"
              disabled={isSubmitting || retryAfter > 0}
            >
              {isSubmitting ? (
                <>
                  <Spinner className="mr-2" />
                  {isSetup ? "Setting up..." : "Logging in..."}
                </>
              ) : retryAfter > 0 ? (
                `Locked (${retryAfter}s)`
              ) : isSetup ? (
                "Create Password"
              ) : (
                "Login"
              )}
            </Button>
          </Field>
        </FieldGroup>
      </form>
      <FieldDescription className="px-6 text-center">
        QManager — Quectel Modem Management
      </FieldDescription>
    </div>
  );
}
