import { View } from "react-native";
import Svg, { Circle, G, Path, Rect } from "react-native-svg";
import type { Pt } from "../lib/api";
import { C } from "../lib/theme";

interface Props {
  route?: Pt[] | null;
  trail?: Pt[];
  pos?: Pt | null;
  offRoute?: boolean;
  alert?: boolean;
  height?: number;
}

/** A stylized map: the route, the walked trail and the walker's dot, fit to the box. */
export default function RouteMap({ route, trail = [], pos, offRoute, alert, height = 180 }: Props) {
  const pts: Pt[] = [...(route || []), ...trail, ...(pos ? [pos] : [])];
  const W = 340;
  const H = height;
  if (pts.length === 0) {
    return <View style={{ height, borderRadius: 18, backgroundColor: C.card }} />;
  }
  const lats = pts.map((p) => p[0]);
  const lngs = pts.map((p) => p[1]);
  const k = Math.cos((lats[0] * Math.PI) / 180);
  const minX = Math.min(...lngs) * k, maxX = Math.max(...lngs) * k;
  const minY = Math.min(...lats), maxY = Math.max(...lats);
  const pad = 26;
  const s = Math.min((W - 2 * pad) / Math.max(maxX - minX, 1e-6), (H - 2 * pad) / Math.max(maxY - minY, 1e-6));
  const ox = (W - (maxX - minX) * s) / 2, oy = (H - (maxY - minY) * s) / 2;
  const xy = (p: Pt) => [ox + (p[1] * k - minX) * s, H - (oy + (p[0] - minY) * s)];
  const line = (ps: Pt[]) => ps.map((p, i) => `${i ? "L" : "M"}${xy(p)[0].toFixed(1)} ${xy(p)[1].toFixed(1)}`).join(" ");
  const dot = pos ? xy(pos) : null;
  const end = route && route.length ? xy(route[route.length - 1]) : null;
  const start = route && route.length ? xy(route[0]) : null;
  const dotColor = alert ? C.alert : offRoute ? C.warn : C.accent;
  return (
    <View style={{ height, borderRadius: 18, overflow: "hidden", backgroundColor: C.card }}>
      <Svg width="100%" height="100%" viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="xMidYMid meet">
        <G opacity={0.35}>
          {Array.from({ length: 9 }).map((_, i) => (
            <Rect key={"v" + i} x={i * 42} y={0} width={1} height={H} fill={C.line} />
          ))}
          {Array.from({ length: 6 }).map((_, i) => (
            <Rect key={"h" + i} x={0} y={i * 42} width={W} height={1} fill={C.line} />
          ))}
        </G>
        {route && route.length > 1 && (
          <Path d={line(route)} stroke="#3a4152" strokeWidth={10} strokeLinecap="round" strokeLinejoin="round" fill="none" />
        )}
        {trail.length > 1 && (
          <Path d={line(trail)} stroke={offRoute ? C.warn : C.accent} strokeWidth={3} strokeDasharray="2 6"
            strokeLinecap="round" fill="none" opacity={0.9} />
        )}
        {start && <Circle cx={start[0]} cy={start[1]} r={5} fill={C.muted} />}
        {end && (
          <G>
            <Circle cx={end[0]} cy={end[1]} r={9} fill={C.ok} opacity={0.25} />
            <Circle cx={end[0]} cy={end[1]} r={5} fill={C.ok} />
          </G>
        )}
        {dot && (
          <G>
            <Circle cx={dot[0]} cy={dot[1]} r={16} fill={dotColor} opacity={0.22} />
            <Circle cx={dot[0]} cy={dot[1]} r={8} fill={dotColor} stroke="#fff" strokeWidth={2} />
          </G>
        )}
      </Svg>
    </View>
  );
}
