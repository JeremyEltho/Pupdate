import AsyncStorage from "@react-native-async-storage/async-storage";
import { router } from "expo-router";
import { useEffect, useState } from "react";
import { Text, TextInput, View } from "react-native";
import Buddy from "../components/Buddy";
import { Btn, Card, Heading, Page, s } from "../components/ui";
import { api, getBase, loadBase, setBase } from "../lib/api";
import { C, F } from "../lib/theme";

export default function RolePick() {
  const [url, setUrl] = useState(getBase());
  const [status, setStatus] = useState<"idle" | "ok" | "bad" | "checking">("idle");

  const check = async () => {
    setStatus("checking");
    try {
      await api.health();
      setStatus("ok");
    } catch {
      setStatus("bad");
    }
  };

  useEffect(() => {
    loadBase().then((b) => {
      setUrl(b);
      check();
    });
  }, []);

  const go = async (role: "walker" | "friend") => {
    try {
      await AsyncStorage.setItem("wb.role", role);
    } catch {}
    router.push(`/${role}`);
  };

  return (
    <Page gap={20}>
      <View style={{ alignItems: "center", marginTop: 24, gap: 6 }}>
        <Buddy form="sprout" mood="happy" size={168} />
        <Text style={[s.h1, { marginTop: 10, fontSize: 40, lineHeight: 44 }]}>WalkBuddy</Text>
        <Text style={[s.body, { color: C.muted, textAlign: "center", maxWidth: 320 }]}>
          A little buddy walks home with you. If you stop answering, your friends find out.
        </Text>
      </View>
      <Card style={{ gap: 12 }}>
        <Heading>{"Who's holding this phone?"}</Heading>
        <Btn label="I'm walking home (Jordan)" onPress={() => go("walker")} />
        <Btn label="I'm the friend (Maya)" kind="ghost" onPress={() => go("friend")} />
      </Card>
      <Card style={{ gap: 12 }}>
        <Heading sub="Paste the tunnel address from the laptop.">Server</Heading>
        <TextInput
          value={url}
          onChangeText={setUrl}
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="url"
          placeholder="https://something.trycloudflare.com"
          placeholderTextColor={C.muted}
          selectionColor={C.accent}
          style={{ backgroundColor: C.card2, color: C.text, borderRadius: 14, paddingHorizontal: 14, minHeight: 50,
            fontSize: 15, fontFamily: F.body, borderWidth: 1, borderColor: C.line }}
        />
        <View style={{ flexDirection: "row", gap: 12, alignItems: "center" }}>
          <Btn label="Save and test" kind="ghost" onPress={async () => { await setBase(url); check(); }} style={{ flex: 1 }} />
          <Text style={{ color: status === "ok" ? C.ok : status === "bad" ? C.alert : C.muted, fontFamily: F.bodyBold, minWidth: 110 }}>
            {status === "ok" ? "Connected" : status === "bad" ? "Can't reach it" : status === "checking" ? "Checking" : ""}
          </Text>
        </View>
      </Card>
    </Page>
  );
}
