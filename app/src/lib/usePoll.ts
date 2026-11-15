import { useEffect, useRef, useState } from "react";

/** Poll fn every ms; keeps the last good value, exposes the last error. */
export function usePoll<T>(fn: () => Promise<T>, ms: number, deps: unknown[] = []) {
  const [data, setData] = useState<T | undefined>(undefined);
  const [error, setError] = useState<string | null>(null);
  const alive = useRef(true);
  const [nonce, setNonce] = useState(0);
  useEffect(() => {
    alive.current = true;
    let timer: ReturnType<typeof setTimeout>;
    const run = async () => {
      try {
        const v = await fn();
        if (alive.current) {
          setData(v);
          setError(null);
        }
      } catch (e) {
        if (alive.current) setError((e as Error).message || "network error");
      }
      if (alive.current) timer = setTimeout(run, ms);
    };
    run();
    return () => {
      alive.current = false;
      clearTimeout(timer);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, nonce]);
  return { data, error, refresh: () => setNonce((n) => n + 1), setData };
}
