import * as Location from "expo-location";
import { router } from "expo-router";
import { useEffect, useRef, useState } from "react";
import { Text, View } from "react-native";
import Buddy from "../../components/Buddy";
import RouteMap from "../../components/RouteMap";
import { Banner, Btn, Card, Heading, Page, Pill, TopBar, s } from "../../components/ui";
import { api, type Route, type Walk } from "../../lib/api";
import { success, tap } from "../../lib/safe";
import { usePoll } from "../../lib/usePoll";
import { C, F, STATE_COPY, type Mood } from "../../lib/theme";

const ME = "jordan";
const FORM_NAME: Record<string, string> = { sprout: "Sprout", strider: "Strider", guardian: "Guardian" };

export default function Walker() {
  const [routes, setRoutes] = useState<Route[]>([]);
  const { data: walk, error, setData } = usePoll<Walk | null>(() => api.active(ME), 1000);
  const { data: me } = usePoll(() => api.user(ME), 3000);
  const [happy, setHappy] = useState(false);
  const happyTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const beHappy = (ms: number) => {
    setHappy(true);
    if (happyTimer.current) clearTimeout(happyTimer.current);
    happyTimer.current = setTimeout(() => setHappy(false), ms);
  };
  const [evolved, setEvolved] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const lastState = useRef<string | null>(null);

  useEffect(() => {
    api.routes().then(setRoutes).catch(() => {});
  }, []);

  // Buzz when Levin starts asking or escalates.
  useEffect(() => {
    const st = walk?.engine.state ?? null;
    if (st && st !== lastState.current && st !== "calm") tap();
    lastState.current = st;
  }, [walk?.engine.state]);

  useRealWalkTicks(walk);

  const route = routes.find((r) => r.id === walk?.route_id);
  const state = walk?.engine.state ?? "calm";
  const copy = STATE_COPY[state] ?? STATE_COPY.calm;
  const mood: Mood = happy ? "happy" : walk ? copy.mood : "calm";
  const buddy = walk?.buddy ?? me?.buddy;

  const pet = async () => {
    if (!walk) {
      tap();
      beHappy(1200);
      return;
    }
    tap();
    try {
      const r = await api.pet(walk.id);
      setData(r.walk);
      const ok = r.events.find((e) => e.type === "pet_ok");
      if (ok) {
        success();
        beHappy(1800);
      }
      const evo = r.events.find((e) => e.evolved);
      if (evo?.evolved) {
        setEvolved(evo.evolved);
        setTimeout(() => setEvolved(null), 3200);
      }
    } catch {}
  };

  const duress = async () => {
    if (!walk) return;
    try {
      const r = await api.duress(walk.id);
      setData(r.walk); // the screen stays exactly as it was: the alert is silent
    } catch {}
  };

  const startReal = async (routeId: string) => {
    setBusy(true);
    try {
      setData(await api.startWalk(ME, routeId));
    } catch {}
    setBusy(false);
  };

  const secs = walk && state !== "calm" && walk.engine.seconds_left != null
    ? Math.ceil(walk.engine.seconds_left / (walk.speed || 1)) : null;
  const urgent = state === "final" || state === "countdown" || state === "alert";

  return (
    <Page>
      <TopBar title="WalkBuddy" onBack={() => router.replace("/")}
        right={walk?.demo ? <Pill text={`Demo ${walk.speed}x`} /> : undefined} />
      {error && !walk && <Banner text="Can't reach the server. Check the address on the first screen." kind="alert" />}

      <View style={{ flexDirection: "row", alignItems: "flex-end", gap: 12, marginTop: 4 }}>
        <View style={{ flex: 1, gap: 4 }}>
          <Text style={s.muted}>{walk ? (route ? `${route.from} to ${route.to}` : "Walking") : "Ready when you are"}</Text>
          <Text style={[s.h1, urgent && { color: C.alert }]}>{walk ? copy.title : "Hi Jordan"}</Text>
          <Text style={[s.body, { color: C.muted }]}>
            {walk ? copy.sub : `Start a walk and ${buddy?.name ?? "Levin"} comes with you.`}
          </Text>
        </View>
        {secs != null && state !== "alert" && (
          <View style={{ alignItems: "center", minWidth: 64 }}>
            <Text style={{ color: urgent ? C.alert : C.accent, fontFamily: F.display, fontSize: 44, lineHeight: 46,
              fontVariant: ["tabular-nums"] }}>{secs}</Text>
            <Text style={[s.muted, { fontSize: 12 }]}>seconds</Text>
          </View>
        )}
      </View>

      <View style={{ alignItems: "center", paddingTop: 8, gap: 10 }}>
        {buddy && <Buddy form={buddy.form} mood={mood} size={232} onPet={pet} onDuress={duress} />}
        {evolved && (
          <View style={{ position: "absolute", top: 0, backgroundColor: C.accent, borderRadius: 999, paddingVertical: 9, paddingHorizontal: 16 }}>
            <Text style={{ color: C.ink, fontFamily: F.bodyBold, fontSize: 15 }}>
              {buddy?.name} evolved into {FORM_NAME[evolved] ?? evolved}!
            </Text>
          </View>
        )}
        <Pill text={state === "calm" || !walk ? "Tap to pet" : `Tap ${buddy?.name ?? "Levin"} now`}
          tone={state === "calm" || !walk ? "muted" : urgent ? "alert" : "accent"} />
      </View>

      {buddy && <XpBar xp={buddy.xp} next={walk?.next_form_at ?? null} name={buddy.name} form={buddy.form} />}

      {walk && (
        <Card style={{ padding: 0, overflow: "hidden" }}>
          <RouteMap route={route?.points} trail={walk.trail} pos={walk.pos} offRoute={walk.off_route} alert={state === "alert"} height={200} />
          <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center", padding: 14 }}>
            <Text style={s.muted}>{route ? `${(route.length_m / 1000).toFixed(1)} km walk` : "Live location"}</Text>
            {walk.off_route ? <Pill text="Off route" tone="warn" /> : <Pill text="On route" tone="ok" />}
          </View>
        </Card>
      )}
      {walk && !walk.demo && <Btn label="I'm home, end walk" kind="ghost" onPress={() => api.end(walk.id).then(setData).catch(() => {})} />}

      {!walk && (
        <Card style={{ gap: 10 }}>
          <Heading sub="For the demo, start the walk from the friend phone instead.">Start a walk</Heading>
          {routes.map((r) => (
            <Btn key={r.id} label={`${r.from} to ${r.to}`} kind="ghost" busy={busy} onPress={() => startReal(r.id)} />
          ))}
        </Card>
      )}
    </Page>
  );
}

function XpBar({ xp, next, name, form }: { xp: number; next: number | null; name: string; form: string }) {
  const prev = form === "sprout" ? 0 : form === "strider" ? 100 : 250;
  const pct = next ? Math.max(0, Math.min(1, (xp - prev) / (next - prev))) : 1;
  return (
    <View style={{ gap: 6 }}>
      <View style={{ flexDirection: "row", justifyContent: "space-between" }}>
        <Text style={s.h3}>
          {name} <Text style={[s.muted, { fontFamily: F.bodySemi }]}>{FORM_NAME[form] ?? form}</Text>
        </Text>
        <Text style={[s.muted, { fontVariant: ["tabular-nums"] }]}>{next ? `${xp} / ${next} XP` : `${xp} XP`}</Text>
      </View>
      <View style={{ height: 10, borderRadius: 99, backgroundColor: C.card2, overflow: "hidden" }}>
        <View style={{ width: `${pct * 100}%`, height: "100%", backgroundColor: C.accent, borderRadius: 99 }} />
      </View>
    </View>
  );
}

/** Real (non-demo) walks: send GPS fixes, plus a heartbeat every 20 s even without a fix. */
function useRealWalkTicks(walk: Walk | null | undefined) {
  const id = walk && !walk.demo && walk.status === "active" ? walk.id : null;
  useEffect(() => {
    if (!id) return;
    let sub: Location.LocationSubscription | null = null;
    let stopped = false;
    (async () => {
      try {
        const { status } = await Location.requestForegroundPermissionsAsync();
        if (status !== "granted" || stopped) return;
        sub = await Location.watchPositionAsync(
          { accuracy: Location.Accuracy.High, timeInterval: 5000, distanceInterval: 5 },
          (loc) => {
            api.tick(id, loc.coords.latitude, loc.coords.longitude, loc.coords.accuracy ?? undefined).catch(() => {});
          },
        );
      } catch {}
    })();
    const hb = setInterval(() => api.tick(id).catch(() => {}), 20000);
    return () => {
      stopped = true;
      clearInterval(hb);
      try {
        sub?.remove();
      } catch {}
    };
  }, [id]);
}
