import type { ReactNode } from "react";
import { ActivityIndicator, Image, type ImageSourcePropType, Pressable, ScrollView, StyleSheet, Text, View, type ViewStyle } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import Svg, { Circle, Defs, LinearGradient, Path, Rect, Stop } from "react-native-svg";
import { C, F, SHADOW } from "../lib/theme";

const STARS = Array.from({ length: 38 }, (_, i) => {
  const r = (n: number) => ((Math.sin(i * 12.9898 + n * 78.233) * 43758.5453) % 1 + 1) % 1;
  return { x: r(1) * 400, y: r(2) * 900, s: 0.6 + r(3) * 1.4, o: 0.15 + r(4) * 0.5 };
});

/** Night sky behind every screen: a soft vertical gradient and a few stars. */
export function Sky() {
  return (
    <View pointerEvents="none" style={StyleSheet.absoluteFill}>
      <Svg width="100%" height="100%" viewBox="0 0 400 900" preserveAspectRatio="xMidYMid slice">
        <Defs>
          <LinearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
            <Stop offset="0" stopColor={C.bg2} />
            <Stop offset="0.55" stopColor={C.bg} />
          </LinearGradient>
        </Defs>
        <Rect x="0" y="0" width="400" height="900" fill="url(#sky)" />
        {STARS.map((st, i) => <Circle key={i} cx={st.x} cy={st.y} r={st.s} fill="#fff" opacity={st.o} />)}
      </Svg>
    </View>
  );
}

/** Screen shell: sky, safe area, scroll, and a centered column that never stretches past phone width. */
export function Page({ children, gap = 16 }: { children: ReactNode; gap?: number }) {
  return (
    <View style={{ flex: 1, backgroundColor: C.bg }}>
      <Sky />
      <SafeAreaView style={{ flex: 1 }}>
        <ScrollView contentContainerStyle={{ flexGrow: 1, alignItems: "center" }}>
          <View style={{ width: "100%", maxWidth: 480, paddingHorizontal: 20, paddingTop: 8, paddingBottom: 40, gap }}>
            {children}
          </View>
        </ScrollView>
      </SafeAreaView>
    </View>
  );
}

/** HUD chip: a 3D icon and a number, like a game's currency counter. */
export function Stat({ icon, value, label, tone = C.text }: { icon: ImageSourcePropType; value: string | number; label?: string; tone?: string }) {
  return (
    <View accessibilityLabel={label ? `${value} ${label}` : String(value)}
      style={{ flexDirection: "row", alignItems: "center", gap: 6, backgroundColor: "rgba(255,255,255,0.06)",
        borderRadius: 999, paddingVertical: 5, paddingLeft: 6, paddingRight: 12, borderWidth: 1, borderColor: "rgba(255,255,255,0.08)" }}>
      <Image source={icon} style={{ width: 24, height: 24 }} />
      <Text style={{ color: tone, fontFamily: F.display, fontSize: 16, fontVariant: ["tabular-nums"] }}>{value}</Text>
    </View>
  );
}

export function TopBar({ title, onBack, right }: { title?: string; onBack?: () => void; right?: ReactNode }) {
  return (
    <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", minHeight: 44 }}>
      {onBack ? (
        <Pressable onPress={onBack} hitSlop={12} accessibilityLabel="Back"
          style={({ pressed }) => ({ flexDirection: "row", alignItems: "center", gap: 4, opacity: pressed ? 0.6 : 1 })}>
          <Svg width={20} height={20} viewBox="0 0 24 24">
            <Path d="M15 5l-7 7 7 7" stroke={C.muted} strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round" fill="none" />
          </Svg>
          <Text style={{ color: C.muted, fontFamily: F.bodySemi, fontSize: 15 }}>{title ?? "Back"}</Text>
        </Pressable>
      ) : (
        <View />
      )}
      {right}
    </View>
  );
}

export function Pill({ text, tone = "accent" }: { text: string; tone?: "accent" | "ok" | "warn" | "alert" | "muted" }) {
  const fg = tone === "accent" ? C.accent : tone === "ok" ? C.ok : tone === "warn" ? C.warn : tone === "alert" ? C.alert : C.muted;
  return (
    <View style={{ borderRadius: 999, paddingVertical: 5, paddingHorizontal: 11, backgroundColor: fg + "1f" }}>
      <Text style={{ color: fg, fontFamily: F.bodyBold, fontSize: 12 }}>{text}</Text>
    </View>
  );
}

const BTN: Record<string, { bg: string; lip: string; fg: string }> = {
  primary: { bg: C.accent, lip: C.accentDeep, fg: C.ink },
  ok: { bg: C.ok, lip: C.okDeep, fg: "#032417" },
  danger: { bg: C.alert, lip: C.alertDeep, fg: "#fff" },
  ghost: { bg: C.card2, lip: "#0e1330", fg: C.text },
};

/** Chunky game button: a darker lip underneath that the face presses down into. */
export function Btn({ label, onPress, kind = "primary", disabled, busy, style }: {
  label: string; onPress: () => void; kind?: "primary" | "ghost" | "danger" | "ok"; disabled?: boolean; busy?: boolean; style?: ViewStyle;
}) {
  const k = BTN[kind];
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled || busy}
      accessibilityRole="button"
      accessibilityState={{ disabled: !!(disabled || busy), busy: !!busy }}
      style={[{ opacity: disabled ? 0.4 : 1 }, style]}
    >
      {({ pressed }) => (
        <View style={{ borderRadius: 18, backgroundColor: k.lip, paddingBottom: pressed ? 1 : 5, marginTop: pressed ? 4 : 0 }}>
          <View style={[s.btn, { backgroundColor: k.bg }]}>
            {busy ? <ActivityIndicator color={k.fg} /> : <Text style={[s.btnText, { color: k.fg }]}>{label}</Text>}
          </View>
        </View>
      )}
    </Pressable>
  );
}

export function Card({ children, style }: { children: ReactNode; style?: ViewStyle }) {
  return <View style={[s.card, style]}>{children}</View>;
}

/** Section heading: sentence case, carries its own weight. */
export function Heading({ children, sub }: { children: ReactNode; sub?: string }) {
  return (
    <View style={{ gap: 2, marginBottom: 4 }}>
      <Text style={s.h3}>{children}</Text>
      {sub ? <Text style={s.muted}>{sub}</Text> : null}
    </View>
  );
}

export function Banner({ text, kind = "warn" }: { text: string; kind?: "warn" | "alert" }) {
  return (
    <View style={[s.banner, { backgroundColor: kind === "alert" ? "#3a1620" : "#3a2f14" }]}>
      <Text style={{ color: kind === "alert" ? "#ffc2ca" : "#ffe1a0", fontFamily: F.bodySemi, fontSize: 15, lineHeight: 21 }}>{text}</Text>
    </View>
  );
}

export const s = StyleSheet.create({
  btn: { borderRadius: 18, minHeight: 52, paddingHorizontal: 18, alignItems: "center", justifyContent: "center" },
  btnText: { fontSize: 17, fontFamily: F.display, letterSpacing: 0.2 },
  card: { backgroundColor: C.card, borderRadius: 24, padding: 18, borderWidth: 1, borderColor: C.line, borderTopColor: "#3a4482", ...SHADOW },
  banner: { borderRadius: 14, padding: 14 },
  h1: { color: C.text, fontSize: 34, lineHeight: 38, fontFamily: F.display, letterSpacing: -0.6 },
  h2: { color: C.text, fontSize: 22, lineHeight: 27, fontFamily: F.displayBold },
  h3: { color: C.text, fontSize: 18, lineHeight: 23, fontFamily: F.displayBold },
  body: { color: C.text, fontSize: 16, lineHeight: 23, fontFamily: F.body },
  muted: { color: C.muted, fontSize: 14, lineHeight: 20, fontFamily: F.body },
});
