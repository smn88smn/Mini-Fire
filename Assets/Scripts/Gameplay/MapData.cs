using System;
using System.Collections.Generic;
using UnityEngine;

namespace MiniFire
{
    [Serializable]
    public class MapDef
    {
        public string name, theme;
        public float[] size;
        public float[][] rects;      // [x, y, w, h, style]
        public float[][] rooms;      // decorative
        public float[][] beams;
        public float[][] ground;     // terrain polyline
        public float[][] gunPos;     // [x, y]
        public string[] gunIds;
        public float[][] pickups;    // [x, y, kind] 0 medkit 1 ammo
        public float[][][] spawns;   // [side][i][x,y]
        public float W => size[0];
        public float H => size[1];
    }

    [Serializable]
    class MapsFile { public MapDef[] maps; }

    /// <summary>Map catalog + collision queries.</summary>
    public static class MapData
    {
        static MapDef[] all;
        public static MapDef[] All
        {
            get
            {
                if (all == null)
                {
                    var ta = Resources.Load<TextAsset>("Maps/maps");
                    all = JsonUtility.FromJson<MapsFile>(ta.text).maps;
                }
                return all;
            }
        }

        public static MapDef Get(int index) => All[Mathf.Clamp(index, 0, All.Length - 1)];

        public struct RectF { public float x, y, w, h; }

        public static List<RectF> Solids(MapDef m)
        {
            var list = new List<RectF>(m.rects.Length);
            foreach (var r in m.rects) list.Add(new RectF { x = r[0], y = r[1], w = r[2], h = r[3] });
            return list;
        }

        public static bool PointSolid(List<RectF> solids, float x, float y)
        {
            for (int i = 0; i < solids.Count; i++)
            {
                var r = solids[i];
                if (x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h) return true;
            }
            return false;
        }

        public static bool SegmentBlocked(List<RectF> solids, float x0, float y0, float x1, float y1)
        {
            float dx = x1 - x0, dy = y1 - y0;
            float dist = Mathf.Sqrt(dx * dx + dy * dy);
            int steps = Mathf.Max(1, Mathf.CeilToInt(dist / 0.25f));
            for (int i = 1; i <= steps; i++)
            {
                float t = (float)i / steps;
                if (PointSolid(solids, x0 + dx * t, y0 + dy * t)) return true;
            }
            return false;
        }
    }

    /// <summary>AABB character physics: gravity, jetpack, rect resolution (no engine physics).</summary>
    public class CharacterPhysics
    {
        public List<MapData.RectF> solids;
        public float x, y, vx, vy;
        public bool grounded;
        public float halfW = 0.28f, height = 1.04f;

        public void Teleport(float nx, float ny) { x = nx; y = ny; vx = vy = 0; grounded = false; }

        public void Step(float moveX, bool jet, float dt, float fuel, float fuelMult,
            out float fuelUsed)
        {
            float target = moveX * GameConfig.MoveSpeed;
            float accel = grounded ? GameConfig.GroundAccel : GameConfig.AirAccel;
            vx = Mathf.MoveTowards(vx, target, accel * dt);

            vy -= GameConfig.Gravity * dt;
            if (jet && fuel > 0f)
            {
                vy += GameConfig.JetAccel * dt;
                fuelUsed = GameConfig.FuelDrain * dt / Mathf.Max(0.1f, fuelMult);
            }
            else fuelUsed = 0f;
            vy = Mathf.Clamp(vy, GameConfig.JetMaxUp, GameConfig.MaxFall);

            x += vx * dt;
            ResolveAxis(true);
            y += vy * dt;
            grounded = false;
            ResolveAxis(false);
        }

        void ResolveAxis(bool horizontal)
        {
            float left = x - halfW, right = x + halfW, bottom = y, top = y + height;
            for (int i = 0; i < solids.Count; i++)
            {
                var r = solids[i];
                if (right <= r.x || left >= r.x + r.w || top <= r.y || bottom >= r.y + r.h) continue;
                if (horizontal)
                {
                    if (vx > 0) x = r.x - halfW;
                    else if (vx < 0) x = r.x + r.w + halfW;
                    else
                    {
                        float pr = (r.x + r.w) - left, pl = right - r.x;
                        if (pr < pl) x = r.x - halfW; else x = r.x + r.w + halfW;
                    }
                    vx = 0;
                    left = x - halfW; right = x + halfW;
                }
                else
                {
                    if (vy <= 0) { y = r.y + r.h; vy = 0; grounded = true; }
                    else { y = r.y - height; vy = 0; }
                    bottom = y; top = y + height;
                }
            }
        }

        public bool OverlapsCircle(float cx, float cy, float radius)
        {
            float nx = Mathf.Clamp(cx, x - halfW, x + halfW);
            float ny = Mathf.Clamp(cy, y, y + height);
            float dx = cx - nx, dy = cy - ny;
            return dx * dx + dy * dy <= radius * radius;
        }
    }
}
