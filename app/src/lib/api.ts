import AsyncStorage from "@react-native-async-storage/async-storage";
import { Platform } from "react-native";

// API base: saved override > EXPO_PUBLIC_API_URL > same origin on web (served at /app) > localhost.
let base: string =
  process.env.EXPO_PUBLIC_API_URL ||
  (Platform.OS === "web" && typeof window !== "undefined" && window.location.pathname.startsWith("/app")
    ? window.location.origin
    : "http://localhost:8100");

export const getBase = () => base;

export async function loadBase() {
  try {
    const saved = await AsyncStorage.getItem("wb.api");
    if (saved) base = saved;
  } catch {}
  return base;
}

export async function setBase(url: string) {
  base = url.trim().replace(/\/+$/, "");
  try {
    await AsyncStorage.setItem("wb.api", base);
  } catch {}
}

async function req<T>(path: string, body?: unknown): Promise<T> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 8000);
  try {
    const r = await fetch(base + path, {
      method: body === undefined ? "GET" : "POST",
      headers: body === undefined ? undefined : { "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: ctrl.signal,
    });
    if (!r.ok) {
      let msg = `${r.status}`;
      try {
        msg = (await r.json()).detail || msg;
      } catch {}
      throw new Error(msg);
    }
    return (await r.json()) as T;
  } finally {
    clearTimeout(timer);
  }
}

export type Pt = [number, number];
export interface Buddy { name: string; xp: number; form: "sprout" | "strider" | "guardian" }
export interface Alert {
  id: string; walk_id: string; walker_id: string; walker_name: string; walker_phone: string;
  kind: "no_answer" | "duress" | "lost_contact"; status: string; opened_at: string; pos: Pt | null;
  petted_after: string | null; contact_restored: string | null; closed_by: string | null;
}
export interface Walk {
  id: string; walker_id: string; walker_name: string; demo: boolean; streak: number; status: string; route_id: string | null;
  dest: Pt | null; engine: { state: string; seconds_left: number | null; reason: string | null; ignore_pets: boolean; lost_contact: boolean };
  escalating: boolean; speed: number; pos: Pt | null; trail: Pt[]; buddy: Buddy; next_form_at: number | null;
  alerts: Alert[]; events: { type: string; xp?: number; evolved?: string; kind?: string; reason?: string }[]; off_route: boolean;
}
export interface Route { id: string; name: string; from: string; to: string; points: Pt[]; length_m: number; source: string }
export interface Feed { walks: Walk[]; open_alerts: Alert[]; recent_alerts: Alert[] }

export const api = {
  health: () => req<{ ok: boolean }>("/health"),
  routes: () => req<Route[]>("/routes"),
  user: (id: string) => req<{ id: string; name: string; buddy: Buddy; streak: number; active_walk_id: string | null }>(`/users/${id}`),
  active: (id: string) => req<Walk | null>(`/users/${id}/active`),
  startWalk: (walker_id: string, route_id: string) => req<Walk>("/walks", { walker_id, route_id, demo: false }),
  tick: (wid: string, lat?: number, lng?: number, accuracy?: number) => req<unknown>(`/walks/${wid}/tick`, { lat, lng, accuracy }),
  pet: (wid: string) => req<{ events: Walk["events"]; walk: Walk }>(`/walks/${wid}/pet`, {}),
  duress: (wid: string) => req<{ ok: boolean; walk: Walk }>(`/walks/${wid}/duress`, {}),
  end: (wid: string) => req<Walk>(`/walks/${wid}/end`, {}),
  feed: (fid: string) => req<Feed>(`/friends/${fid}/feed`),
  closeAlert: (aid: string, friend_id: string) => req<Alert>(`/alerts/${aid}/close`, { friend_id }),
  demoReset: () => req<unknown>("/demo/reset", {}),
  demoStart: (route_id: string) => req<Walk>("/demo/start", { route_id }),
  demoStop: () => req<Walk>("/demo/stop-answering", {}),
  demoCheckin: () => req<Walk>("/demo/checkin", {}),
  demoDeviate: () => req<unknown>("/demo/deviate", {}),
  demoSpeed: (x: number | null) => req<unknown>("/demo/speed", { x }),
};
