"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import { authFetch } from "@/lib/auth-fetch";

interface InstallResult {
  success: boolean;
  status: "idle" | "running" | "complete" | "error";
  message?: string;
  detail?: string;
}

// =============================================================================
// useEmailAlerts — Fetch & Save Hook for Email Alert Settings
// =============================================================================
// Fetches current email alert configuration on mount.
// Provides saveSettings for persisting changes and sendTestEmail for testing.
//
// Backend: GET/POST /cgi-bin/quecmanager/monitoring/email_alerts.sh
// =============================================================================

const CGI_ENDPOINT = "/cgi-bin/quecmanager/monitoring/email_alerts.sh";

// ─── Types ─────────────────────────────────────────────────────────────────

export interface EmailAlertsSettings {
  enabled: boolean;
  sender_email: string;
  recipient_email: string;
  /** Stored app password (empty string if not set) */
  app_password: string;
  threshold_minutes: number;
}

export interface EmailAlertsSavePayload {
  action: "save_settings";
  enabled: boolean;
  sender_email: string;
  recipient_email: string;
  /** Only included when user has typed a new password */
  app_password?: string;
  threshold_minutes: number;
}

export interface UseEmailAlertsReturn {
  settings: EmailAlertsSettings | null;
  msmtpInstalled: boolean;
  isLoading: boolean;
  isSaving: boolean;
  isSendingTest: boolean;
  isUninstalling: boolean;
  installResult: InstallResult;
  error: string | null;
  saveSettings: (payload: EmailAlertsSavePayload) => Promise<boolean>;
  sendTestEmail: () => Promise<boolean>;
  uninstall: () => Promise<boolean>;
  runInstall: () => Promise<void>;
  refresh: () => void;
}

// ─── Hook ──────────────────────────────────────────────────────────────────

export function useEmailAlerts(): UseEmailAlertsReturn {
  const [settings, setSettings] = useState<EmailAlertsSettings | null>(null);
  const [msmtpInstalled, setMsmtpInstalled] = useState(true);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isSendingTest, setIsSendingTest] = useState(false);
  const [isUninstalling, setIsUninstalling] = useState(false);
  const [installResult, setInstallResult] = useState<InstallResult>({
    success: true,
    status: "idle",
  });
  const installPollRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const [error, setError] = useState<string | null>(null);

  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      if (installPollRef.current) clearInterval(installPollRef.current);
    };
  }, []);

  // ---------------------------------------------------------------------------
  // Fetch current settings
  // ---------------------------------------------------------------------------
  const fetchSettings = useCallback(async (silent = false) => {
    if (!silent) setIsLoading(true);
    setError(null);

    try {
      const resp = await authFetch(CGI_ENDPOINT);
      if (!resp.ok) {
        throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
      }

      const json = await resp.json();
      if (!mountedRef.current) return;

      if (!json.success) {
        setError(json.error || "Failed to fetch email alert settings");
        return;
      }

      setMsmtpInstalled(json.msmtp_installed !== false);
      setSettings(json.settings);
    } catch (err) {
      if (!mountedRef.current) return;
      setError(
        err instanceof Error
          ? err.message
          : "Failed to fetch email alert settings",
      );
    } finally {
      if (mountedRef.current && !silent) {
        setIsLoading(false);
      }
    }
  }, []);

  // Fetch on mount
  useEffect(() => {
    fetchSettings();
  }, [fetchSettings]);

  // ---------------------------------------------------------------------------
  // Save settings
  // ---------------------------------------------------------------------------
  const saveSettings = useCallback(
    async (payload: EmailAlertsSavePayload): Promise<boolean> => {
      setError(null);
      setIsSaving(true);

      try {
        const resp = await authFetch(CGI_ENDPOINT, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });

        if (!resp.ok) {
          throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
        }

        const json = await resp.json();
        if (!mountedRef.current) return false;

        if (!json.success) {
          setError(json.detail || json.error || "Failed to save settings");
          return false;
        }

        // Silent re-fetch to sync app_password_set
        await fetchSettings(true);
        return true;
      } catch (err) {
        if (!mountedRef.current) return false;
        setError(
          err instanceof Error ? err.message : "Failed to save settings",
        );
        return false;
      } finally {
        if (mountedRef.current) {
          setIsSaving(false);
        }
      }
    },
    [fetchSettings],
  );

  // ---------------------------------------------------------------------------
  // Send test email
  // ---------------------------------------------------------------------------
  const sendTestEmail = useCallback(async (): Promise<boolean> => {
    setIsSendingTest(true);

    try {
      const resp = await authFetch(CGI_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "send_test" }),
      });

      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);

      const json = await resp.json();
      if (!mountedRef.current) return false;
      return json.success;
    } catch {
      return false;
    } finally {
      if (mountedRef.current) {
        setIsSendingTest(false);
      }
    }
  }, []);

  // ---------------------------------------------------------------------------
  // Install via opkg
  // ---------------------------------------------------------------------------
  const stopInstallPolling = useCallback(() => {
    if (installPollRef.current) {
      clearInterval(installPollRef.current);
      installPollRef.current = null;
    }
  }, []);

  const pollInstallStatus = useCallback(async () => {
    try {
      const resp = await authFetch(CGI_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "install_status" }),
      });
      if (!resp.ok) return;
      const data: InstallResult = await resp.json();
      if (!mountedRef.current) return;
      setInstallResult(data);
      if (data.status === "complete" || data.status === "error") {
        stopInstallPolling();
        await fetchSettings(true);
      }
    } catch {
      // Silently retry on next poll
    }
  }, [stopInstallPolling, fetchSettings]);

  const runInstall = useCallback(async () => {
    setInstallResult({ success: true, status: "running", message: "Starting installation..." });
    try {
      await authFetch(CGI_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "install" }),
      });
      installPollRef.current = setInterval(pollInstallStatus, 2000);
    } catch (err) {
      if (mountedRef.current) {
        setInstallResult({
          success: false,
          status: "error",
          message: err instanceof Error ? err.message : "Failed to start installation",
        });
      }
    }
  }, [pollInstallStatus]);

  const uninstall = useCallback(async (): Promise<boolean> => {
    setIsUninstalling(true);
    try {
      const resp = await authFetch(CGI_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "uninstall" }),
      });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const json = await resp.json();
      if (!json.success) {
        setError(json.detail || "Failed to uninstall");
        return false;
      }
      await fetchSettings(true);
      return true;
    } catch (err) {
      if (mountedRef.current) {
        setError(err instanceof Error ? err.message : "Failed to uninstall");
      }
      return false;
    } finally {
      if (mountedRef.current) setIsUninstalling(false);
    }
  }, [fetchSettings]);

  return {
    settings,
    msmtpInstalled,
    isLoading,
    isSaving,
    isSendingTest,
    isUninstalling,
    installResult,
    error,
    saveSettings,
    sendTestEmail,
    uninstall,
    runInstall,
    refresh: fetchSettings,
  };
}
