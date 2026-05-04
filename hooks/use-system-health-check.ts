"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import { authFetch } from "@/lib/auth-fetch";
import type {
  HealthCheckJob,
  RunResponse,
  TestOutputResponse,
  TestStatus,
} from "@/types/system-health-check";

const CGI_BASE = "/cgi-bin/quecmanager/system/health-check";
const POLL_INTERVAL_MS = 500;

export interface UseSystemHealthCheckReturn {
  job: HealthCheckJob | null;
  isRunning: boolean;
  isStarting: boolean;
  error: string | null;
  start: () => Promise<void>;
  refresh: () => Promise<void>;
  fetchTestOutput: (testId: string) => Promise<string>;
  downloadBundle: () => void;
}

export function useSystemHealthCheck(): UseSystemHealthCheckReturn {
  const [job, setJob] = useState<HealthCheckJob | null>(null);
  const [isStarting, setIsStarting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const pollTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const aborted = useRef(false);

  const fetchStatus = useCallback(async (): Promise<HealthCheckJob | null> => {
    const res = await authFetch(`${CGI_BASE}/status.sh`);
    if (!res.ok) throw new Error(`status ${res.status}`);
    const data = await res.json();
    if (data?.status === "none") return null;
    return data as HealthCheckJob;
  }, []);

  const refresh = useCallback(async () => {
    try {
      const next = await fetchStatus();
      setJob(next);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, [fetchStatus]);

  // Initial fetch on mount.
  useEffect(() => {
    aborted.current = false;
    void refresh();
    return () => {
      aborted.current = true;
      if (pollTimer.current) clearTimeout(pollTimer.current);
    };
  }, [refresh]);

  // Polling loop while job is running.
  useEffect(() => {
    if (pollTimer.current) {
      clearTimeout(pollTimer.current);
      pollTimer.current = null;
    }
    if (!job || job.status !== "running") return;
    pollTimer.current = setTimeout(async () => {
      if (aborted.current) return;
      await refresh();
    }, POLL_INTERVAL_MS);
    return () => {
      if (pollTimer.current) clearTimeout(pollTimer.current);
    };
  }, [job, refresh]);

  const start = useCallback(async () => {
    setIsStarting(true);
    setError(null);
    try {
      const res = await authFetch(`${CGI_BASE}/run.sh`, { method: "POST" });
      const data = (await res.json()) as RunResponse;
      if (!data.success) throw new Error(data.detail || data.error || "run failed");
      // Reset job to a fresh "running" placeholder so UI flips immediately.
      setJob((prev) => (prev ? { ...prev, status: "running" } : prev));
      await refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setIsStarting(false);
    }
  }, [refresh]);

  const fetchTestOutput = useCallback(async (testId: string): Promise<string> => {
    const res = await authFetch(
      `${CGI_BASE}/status.sh?test_id=${encodeURIComponent(testId)}`,
    );
    if (!res.ok) throw new Error(`status ${res.status}`);
    const data = (await res.json()) as TestOutputResponse;
    if (!data.success) throw new Error(data.error || "fetch failed");
    return data.output ?? "";
  }, []);

  const downloadBundle = useCallback(() => {
    if (!job?.job_id || !job.tarball_path) return;
    const url = `${CGI_BASE}/download.sh?job_id=${encodeURIComponent(job.job_id)}`;
    // Trigger native browser download — auth cookie is sent automatically.
    window.location.href = url;
  }, [job]);

  const isRunning = job?.status === "running";

  return {
    job,
    isRunning: !!isRunning,
    isStarting,
    error,
    start,
    refresh,
    fetchTestOutput,
    downloadBundle,
  };
}

// Helper for components: status → display label
export function testStatusLabel(s: TestStatus): string {
  switch (s) {
    case "pass": return "Pass";
    case "fail": return "Fail";
    case "warn": return "Warning";
    case "skip": return "Skipped";
    case "running": return "Running";
    case "pending": return "Pending";
  }
}
