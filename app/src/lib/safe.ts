// Every device feature is wrapped so a failure (web, Expo Go quirks, denied
// permission) can never crash the app.
import * as Haptics from "expo-haptics";
import * as Linking from "expo-linking";
import { Platform, Vibration } from "react-native";

export async function tap() {
  try {
    if (Platform.OS !== "web") await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
  } catch {}
}

export async function success() {
  try {
    if (Platform.OS !== "web") await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
  } catch {}
}

export function alarm(on: boolean) {
  try {
    if (Platform.OS === "web") {
      if (on && typeof navigator !== "undefined" && "vibrate" in navigator) navigator.vibrate([400, 200, 400]);
      return;
    }
    if (on) Vibration.vibrate([0, 500, 300, 500], true);
    else Vibration.cancel();
  } catch {}
}

export async function call(phone: string) {
  try {
    await Linking.openURL(`tel:${phone}`);
  } catch {}
}

export async function openMap(lat: number, lng: number) {
  try {
    await Linking.openURL(`https://maps.apple.com/?q=${lat},${lng}`);
  } catch {}
}
