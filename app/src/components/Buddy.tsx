import { useEffect, useState } from "react";
import { Animated, Easing, Image, Pressable, View } from "react-native";
import Svg, { Defs, Ellipse, RadialGradient, Stop } from "react-native-svg";
import type { Buddy as BuddyT } from "../lib/api";
import { C, type Mood } from "../lib/theme";

// 3D sprites: Microsoft Fluent Emoji (MIT), see assets/fluent/LICENSE.txt
export const FORM_SPRITE = {
  sprout: require("../../assets/fluent/hatching_chick.png"),
  strider: require("../../assets/fluent/front-facing_baby_chick.png"),
  guardian: require("../../assets/fluent/owl.png"),
} as const;
export const FORM_NAME: Record<BuddyT["form"], string> = { sprout: "Hatchling", strider: "Chick", guardian: "Night Owl" };

const BADGE: Partial<Record<Mood, number>> = {
  asking: require("../../assets/fluent/red_question_mark.png"),
  worried: require("../../assets/fluent/sweat_droplets.png"),
  alarmed: require("../../assets/fluent/red_exclamation_mark.png"),
  happy: require("../../assets/fluent/sparkles.png"),
};

const GLOW: Record<Mood, string> = {
  calm: C.accent,
  happy: C.accent,
  asking: "#7aa2ff",
  worried: C.warn,
  alarmed: C.alert,
};

interface Props {
  form: BuddyT["form"];
  mood: Mood;
  size?: number;
  onPet?: () => void;
  onDuress?: () => void; // 2 s long-press, silent
  pedestal?: boolean;
}

export default function Buddy({ form, mood, size = 220, onPet, onDuress, pedestal = true }: Props) {
  const [bob] = useState(() => new Animated.Value(0));
  const [squish] = useState(() => new Animated.Value(1));
  const [shake] = useState(() => new Animated.Value(0));
  const [badgePop] = useState(() => new Animated.Value(0));

  useEffect(() => {
    const speed = mood === "alarmed" ? 280 : mood === "worried" ? 480 : 1300;
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(bob, { toValue: 1, duration: speed, easing: Easing.inOut(Easing.sin), useNativeDriver: false }),
        Animated.timing(bob, { toValue: 0, duration: speed, easing: Easing.inOut(Easing.sin), useNativeDriver: false }),
      ]),
    );
    loop.start();
    let shaker: Animated.CompositeAnimation | null = null;
    if (mood === "alarmed" || mood === "worried") {
      shaker = Animated.loop(
        Animated.sequence([
          Animated.timing(shake, { toValue: 1, duration: 70, useNativeDriver: false }),
          Animated.timing(shake, { toValue: -1, duration: 140, useNativeDriver: false }),
          Animated.timing(shake, { toValue: 0, duration: 70, useNativeDriver: false }),
          Animated.delay(mood === "alarmed" ? 250 : 1100),
        ]),
      );
      shaker.start();
    } else {
      shake.setValue(0);
    }
    badgePop.setValue(0);
    Animated.spring(badgePop, { toValue: 1, friction: 4, tension: 120, useNativeDriver: false }).start();
    return () => {
      loop.stop();
      shaker?.stop();
    };
  }, [mood, bob, shake, badgePop]);

  const pet = () => {
    Animated.sequence([
      Animated.timing(squish, { toValue: 0.84, duration: 90, useNativeDriver: false }),
      Animated.spring(squish, { toValue: 1, friction: 3, tension: 160, useNativeDriver: false }),
    ]).start();
    onPet?.();
  };

  const ty = bob.interpolate({ inputRange: [0, 1], outputRange: [0, mood === "alarmed" ? -5 : -14] });
  const rot = shake.interpolate({ inputRange: [-1, 1], outputRange: ["-7deg", "7deg"] });
  const shadowScale = bob.interpolate({ inputRange: [0, 1], outputRange: [1, 0.82] });
  const badge = BADGE[mood];
  const sprite = size * 0.78;
  const glow = GLOW[mood];

  return (
    <Pressable onPress={pet} onLongPress={onDuress} delayLongPress={2000} accessibilityRole="button"
      accessibilityLabel="Pet your buddy">
      <View style={{ width: size, height: size, alignItems: "center", justifyContent: "flex-end" }}>
        {pedestal && (
          <View style={{ position: "absolute", bottom: 0, width: size, height: size * 0.5 }}>
            <Svg width="100%" height="100%" viewBox="0 0 200 100">
              <Defs>
                <RadialGradient id="glow" cx="50%" cy="70%" rx="50%" ry="40%">
                  <Stop offset="0" stopColor={glow} stopOpacity={0.55} />
                  <Stop offset="1" stopColor={glow} stopOpacity={0} />
                </RadialGradient>
                <RadialGradient id="disc" cx="50%" cy="40%" rx="50%" ry="60%">
                  <Stop offset="0" stopColor="#2c3670" />
                  <Stop offset="1" stopColor="#161c40" />
                </RadialGradient>
              </Defs>
              <Ellipse cx="100" cy="70" rx="100" ry="30" fill="url(#glow)" />
              <Ellipse cx="100" cy="80" rx="62" ry="13" fill="#0b0f26" />
              <Ellipse cx="100" cy="76" rx="62" ry="13" fill="url(#disc)" />
              <Ellipse cx="100" cy="73" rx="48" ry="7" fill="#ffffff" opacity={0.06} />
            </Svg>
          </View>
        )}
        <Animated.View style={{ position: "absolute", bottom: size * 0.08, width: sprite * 0.6, height: sprite * 0.1,
          borderRadius: 999, backgroundColor: "#000", opacity: 0.35, transform: [{ scaleX: shadowScale }] }} />
        <Animated.View style={{ marginBottom: size * 0.11, transform: [{ translateY: ty }, { scale: squish }, { rotate: rot }] }}>
          <Image source={FORM_SPRITE[form]} style={{ width: sprite, height: sprite }} resizeMode="contain" />
        </Animated.View>
        {badge && (
          <Animated.Image source={badge} resizeMode="contain"
            style={{ position: "absolute", top: size * 0.02, right: size * 0.08, width: size * 0.26, height: size * 0.26,
              transform: [{ scale: badgePop }, { rotate: "12deg" }] }} />
        )}
      </View>
    </Pressable>
  );
}
