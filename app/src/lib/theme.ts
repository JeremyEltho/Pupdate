export const C = {
  bg: "#0a0d1c", // night sky
  bg2: "#11163a",
  card: "#151a33",
  card2: "#1d2445",
  line: "#2a3260",
  text: "#f3f4ff",
  muted: "#9aa1c9",
  accent: "#ffbe3d", // XP gold, the one accent
  accentDeep: "#d98a00",
  ok: "#3ee0a1",
  okDeep: "#14a874",
  warn: "#ffc857",
  alert: "#ff4d6d",
  alertDeep: "#c41f42",
  ink: "#1a1300",
};

export const STATE_COPY: Record<string, { title: string; sub: string; mood: Mood }> = {
  calm: { title: "Walking together", sub: "Levin is keeping an eye out.", mood: "calm" },
  checkin: { title: "Still good?", sub: "Pet Levin to say you're OK.", mood: "asking" },
  nudge: { title: "Hey, you there?", sub: "Pet Levin now.", mood: "worried" },
  final: { title: "Last chance", sub: "Your friends get an alert soon.", mood: "worried" },
  countdown: { title: "Alerting friends", sub: "Pet Levin to cancel.", mood: "alarmed" },
  alert: { title: "Friends alerted", sub: "Pet Levin to tell them you're OK.", mood: "alarmed" },
};

export type Mood = "calm" | "asking" | "worried" | "alarmed" | "happy";

// Display: Bricolage Grotesque (warm, a little quirky, like the buddy). Body: Figtree.
export const F = {
  display: "BricolageGrotesque_800ExtraBold",
  displayBold: "BricolageGrotesque_700Bold",
  body: "Figtree_500Medium",
  bodySemi: "Figtree_600SemiBold",
  bodyBold: "Figtree_700Bold",
};

// One depth recipe: offset, soft blur.
export const SHADOW = {
  shadowColor: "#000",
  shadowOpacity: 0.35,
  shadowRadius: 18,
  shadowOffset: { width: 0, height: 8 },
  elevation: 6,
};
