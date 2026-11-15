import { router } from "expo-router";
import { useEffect, useState } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import Buddy from "../../components/Buddy";
import RouteMap from "../../components/RouteMap";
import { Banner, Btn, Card, Heading, Page, Pill, TopBar, s } from "../../components/ui";
import { api, type Alert, type Feed, type Route } from "../../lib/api";
import { alarm, call, openMap, success } from "../../lib/safe";
import { usePoll } from "../../lib/usePoll";
import { C, F, STATE_COPY } from "../../lib/theme";

const ME = "maya";

const time = (iso: string | null) => (iso ? new Date(iso).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }) : "");

export default function Friend() {
  const { data: feed, error, refresh, setData } = usePoll<Feed>(() => api.feed(ME), 1500);
  const [routes, setRoutes] = useState<Route[]>([]);
  const [routeId, setRouteId] = useState("library-to-tooker");
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);

  useEffect(() => {
    api.routes().then(setRoutes).catch(() => {});
  }, []);

  const alert = feed?.open_alerts[0];
  const alertId = alert?.id;
  useEffect(() => {
    alarm(!!alertId);
    return () => alarm(false);
  }, [alertId]);

  const act = async (key: string, fn: () => Promise<unknown>) => {
    setBusy(key);
    setMsg(null);
    try {
      await fn();
      refresh();
    } catch (e) {
      setMsg((e as Error).message);
    }
    setBusy(null);
  };

  const close = async (a: Alert) => {
    await act("close", () => api.closeAlert(a.id, ME));
    success();
    if (feed) setData({ ...feed, open_alerts: feed.open_alerts.filter((x) => x.id !== a.id) });
  };

  const walk = feed?.walks[0];
  const route = routes.find((r) => r.id === walk?.route_id);
  const tone = walk ? stateTone(walk.engine.state) : "muted";

  return (
    <View style={{ flex: 1, backgroundColor: C.bg }}>
      <Page>
        <TopBar title="WalkBuddy" onBack={() => router.replace("/")} />
        <View style={{ gap: 4 }}>
          <Text style={s.h1}>Hi Maya</Text>
          <Text style={[s.body, { color: C.muted }]}>{"You'll hear from Levin if Jordan stops answering."}</Text>
        </View>
        {error && !feed && <Banner text="Can't reach the server. Check the address on the first screen." kind="alert" />}

        <Card style={{ gap: 14 }}>
          <Heading>Walking now</Heading>
          {!walk && (
            <View style={{ alignItems: "center", paddingVertical: 12, gap: 6 }}>
              <Buddy form="sprout" mood="calm" size={84} />
              <Text style={s.muted}>Nobody is walking right now.</Text>
            </View>
          )}
          {walk && (
            <>
              <View style={{ flexDirection: "row", alignItems: "center", gap: 12 }}>
                <Buddy form={walk.buddy.form} mood={STATE_COPY[walk.engine.state]?.mood ?? "calm"} size={68} />
                <View style={{ flex: 1, gap: 2 }}>
                  <Text style={s.h2}>{walk.walker_name}</Text>
                  <Text style={s.muted}>{route ? `${route.from} to ${route.to}` : "Walking"}</Text>
                </View>
                <Pill text={friendState(walk.engine.state, walk.walker_name)} tone={tone} />
              </View>
              <RouteMap route={route?.points} trail={walk.trail} pos={walk.pos} offRoute={walk.off_route}
                alert={walk.engine.state === "alert"} height={180} />
            </>
          )}
        </Card>

        <Card style={{ gap: 12 }}>
          <Heading sub="The sim walks at 2x and escalates at 4x. It never pets Levin: every pet comes from Jordan's phone.">
            Demo controls
          </Heading>
          <View style={{ flexDirection: "row", gap: 8, flexWrap: "wrap" }}>
            {routes.map((r) => {
              const on = routeId === r.id;
              return (
                <Pressable key={r.id} onPress={() => setRouteId(r.id)} accessibilityRole="button" accessibilityState={{ selected: on }}
                  style={{ paddingVertical: 8, paddingHorizontal: 13, borderRadius: 999, borderWidth: 1,
                    borderColor: on ? C.accent : C.line, backgroundColor: on ? C.accent + "1a" : "transparent" }}>
                  <Text style={{ color: on ? C.accent : C.muted, fontFamily: F.bodySemi, fontSize: 13 }}>{r.name}</Text>
                </Pressable>
              );
            })}
          </View>
          <View style={{ flexDirection: "row", gap: 10 }}>
            <Btn label="Reset demo" kind="ghost" busy={busy === "reset"} onPress={() => act("reset", api.demoReset)} style={{ flex: 1 }} />
            <Btn label="Start walk" busy={busy === "start"} onPress={() => act("start", () => api.demoStart(routeId))} style={{ flex: 1 }} />
          </View>
          <View style={{ flexDirection: "row", gap: 10 }}>
            <Btn label="Check in now" kind="ghost" disabled={!walk} busy={busy === "ci"} onPress={() => act("ci", api.demoCheckin)} style={{ flex: 1 }} />
            <Btn label="Stop answering" kind="danger" disabled={!walk} busy={busy === "stop"} onPress={() => act("stop", api.demoStop)} style={{ flex: 1 }} />
          </View>
          <View style={{ flexDirection: "row", gap: 10 }}>
            <Btn label="Walk off route" kind="ghost" disabled={!walk} busy={busy === "dev"} onPress={() => act("dev", api.demoDeviate)} style={{ flex: 1 }} />
            <Btn label={walk ? `Speed ${walk.speed}x` : "Speed"} kind="ghost" disabled={!walk}
              onPress={() => act("speed", () => api.demoSpeed(walk && walk.speed < 4 ? 4 : null))} style={{ flex: 1 }} />
          </View>
          {msg && <Banner text={msg} kind="alert" />}
        </Card>

        {feed && feed.recent_alerts.length > 0 && (
          <Card style={{ gap: 10 }}>
            <Heading>Recent alerts</Heading>
            {feed.recent_alerts.slice(0, 5).map((a) => (
              <View key={a.id} style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center" }}>
                <Text style={s.body}>
                  {KIND[a.kind].short} <Text style={s.muted}>{time(a.opened_at)}</Text>
                </Text>
                <Pill text={a.status === "closed" ? `Closed by ${cap(a.closed_by)}` : "Open"} tone={a.status === "closed" ? "muted" : "alert"} />
              </View>
            ))}
          </Card>
        )}
      </Page>
      {alert && <Takeover a={alert} onClose={() => close(alert)} closing={busy === "close"} />}
    </View>
  );
}

const cap = (x: string | null) => (x ? x[0].toUpperCase() + x.slice(1) : "");

const KIND: Record<Alert["kind"], { title: (n: string) => string; body: (n: string) => string; short: string }> = {
  no_answer: {
    title: (n) => `${n} stopped answering`,
    body: (n) => `${n} didn't pet their buddy through almost two minutes of check-ins. Call them now.`,
    short: "No answer",
  },
  duress: {
    title: (n) => `${n} sent a silent alert`,
    body: () => "Do not call first. A ringing phone could put them at risk. Text, or go to their location with someone.",
    short: "Silent alert",
  },
  lost_contact: {
    title: (n) => `Lost contact with ${n}`,
    body: (n) => `${n}'s phone stopped checking in 90 seconds ago. Their battery may have died, or something is wrong.`,
    short: "Lost contact",
  },
};

function Takeover({ a, onClose, closing }: { a: Alert; onClose: () => void; closing: boolean }) {
  const k = KIND[a.kind];
  const first = a.walker_name.split(" ")[0];
  const duress = a.kind === "duress";
  const bg = duress ? "#1f0b2b" : "#2c0a12";
  const soft = duress ? "#e7c9ff" : "#ffd4da";
  return (
    <View style={{ position: "absolute", top: 0, left: 0, right: 0, bottom: 0, backgroundColor: bg }} accessibilityViewIsModal>
      <SafeAreaView style={{ flex: 1 }}>
        <ScrollView contentContainerStyle={{ flexGrow: 1, alignItems: "center" }}>
          <View style={{ flex: 1, width: "100%", maxWidth: 480, padding: 22, gap: 18 }}>
            <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center" }}>
              <Pill text={k.short} tone={duress ? "muted" : "alert"} />
              <Text style={{ color: soft, fontFamily: F.bodySemi, fontSize: 14 }}>{time(a.opened_at)}</Text>
            </View>
            <View style={{ alignItems: "center", paddingVertical: 8 }}>
              {/* The duress screen stays calmer on purpose: it may be read over a shoulder. */}
              <Buddy form="strider" mood={duress ? "worried" : "alarmed"} size={150} />
            </View>
            <View style={{ gap: 10 }}>
              <Text style={{ color: "#fff", fontSize: 36, lineHeight: 40, fontFamily: F.display, letterSpacing: -0.6 }}>{k.title(first)}</Text>
              <Text style={{ color: soft, fontSize: 17, lineHeight: 25, fontFamily: F.body }}>{k.body(first)}</Text>
            </View>
            {a.petted_after && (
              <Banner text={`${first} petted their buddy at ${time(a.petted_after)}, after the alert. Still check on them.`} />
            )}
            {a.contact_restored && <Banner text={`${first}'s phone reconnected at ${time(a.contact_restored)}.`} />}
            {a.pos && (
              <Pressable onPress={() => openMap(a.pos![0], a.pos![1])} accessibilityRole="link"
                style={({ pressed }) => ({ backgroundColor: "rgba(255,255,255,0.07)", borderRadius: 18, padding: 16,
                  borderWidth: 1, borderColor: "rgba(255,255,255,0.1)", opacity: pressed ? 0.75 : 1 })}>
                <Text style={{ color: "#fff", fontFamily: F.bodyBold, fontSize: 16 }}>Last known location</Text>
                <Text style={{ color: soft, fontFamily: F.body, marginTop: 3, fontVariant: ["tabular-nums"] }}>
                  {a.pos[0].toFixed(5)}, {a.pos[1].toFixed(5)}
                </Text>
                <Text style={{ color: "#fff", fontFamily: F.bodySemi, marginTop: 8 }}>Open in Maps</Text>
              </Pressable>
            )}
            <View style={{ flex: 1 }} />
            <View style={{ gap: 12 }}>
              {!duress && <Btn label={`Call ${first}`} kind="ok" onPress={() => call(a.walker_phone)} />}
              <Btn label={`I've reached ${first}, close alert`} kind="ghost" busy={closing} onPress={onClose} />
            </View>
          </View>
        </ScrollView>
      </SafeAreaView>
    </View>
  );
}

function friendState(state: string, name: string) {
  const first = name.split(" ")[0];
  switch (state) {
    case "calm": return "All good";
    case "checkin": return "Checking in";
    case "nudge":
    case "final": return `${first} hasn't answered`;
    case "countdown": return "Alerting soon";
    case "alert": return "Alert sent";
    default: return state;
  }
}

function stateTone(state: string): "ok" | "warn" | "alert" {
  return state === "calm" ? "ok" : state === "alert" || state === "countdown" ? "alert" : "warn";
}
