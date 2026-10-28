import CoreGraphics
import MystatCore

/// Mockup'taki `BM_FS` cam balon shader'ının Metal karşılığı ve uniform tamponunun düzeni.
///
/// Tampon `float4` dizisidir: 8 başlık vektörü, ardından `B[24]`, `W[24]`, `C[24]`, `I[96]`.
/// GLSL'deki `vec3 uC[24]` burada `float4` hizalamasıyla tutulur. Koordinatlar cihaz pikselidir.
enum BubbleShaderSource {
    static let headerCount = 8
    static let bOffset = 8, wOffset = 32, cOffset = 56, iOffset = 80
    static let uniformVectorCount = 176

    /// Mockup `KIND` (shader uzayında, 0–1).
    static func kindRGB(_ k: NodeKind) -> SIMD3<Float> {
        switch k {
        case .folder: SIMD3(0.404, 0.392, 0.961)
        case .regen: SIMD3(1.0, 0.639, 0.22)
        case .docker: SIMD3(0.161, 0.541, 1.0)
        case .file: SIMD3(0.722, 0.741, 0.839)
        case .other: SIMD3(0.62, 0.62, 0.68)
        }
    }

    private static func tintVector(_ t: BgTint) -> SIMD4<Float> {
        guard let k = t.kind else { return .zero }
        let c = kindRGB(k)
        return SIMD4(c, Float(t.amount))
    }

    /// Mockup `render()`'ın uniform yüklemesi: `size` nokta, `scale` cihaz pikseli oranı (mockup `dpr`), `mouse` nokta.
    static func pack(_ f: BubbleFrame, size: CGSize, scale: Double, time: Double, dark: Bool, mouse: CGPoint) -> [SIMD4<Float>] {
        func v(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> SIMD4<Float> { SIMD4(Float(a), Float(b), Float(c), Float(d)) }
        var u = [SIMD4<Float>](repeating: .zero, count: uniformVectorCount)
        let d = scale
        let n = min(24, f.mains.count), m = min(96, f.droplets.count)
        u[0] = v(Double(size.width) * d, Double(size.height) * d, d, time)
        u[1] = v(dark ? 1 : 0, f.zoomLog, Double(mouse.x) * d, Double(mouse.y) * d)
        u[2] = v(Double(n), Double(m), 0, 0)
        if let mem = f.membrane {
            u[3] = v(mem.x * d, mem.y * d, mem.r * d, mem.body)
            u[4] = v(mem.phase, mem.amp, mem.rim, 0)
            u[5] = SIMD4(kindRGB(mem.kind), 0)
        }
        if let r = f.ripple { u[6] = v(r.x * d, r.y * d, r.age, r.amp) }
        let t0 = tintVector(f.bgFrom), t1 = tintVector(f.bgTo), k = Float(f.bgT)
        u[7] = t0 + (t1 - t0) * k
        for i in 0..<n {
            let b = f.mains[i]
            u[bOffset + i] = v(b.x * d, b.y * d, b.r * d, b.selection)
            u[wOffset + i] = v(b.item.phase, b.amp, b.alpha, b.hover)
            u[cOffset + i] = SIMD4(kindRGB(b.item.kind), 0)
        }
        for j in 0..<m {
            let q = f.droplets[j]
            u[iOffset + j] = v(q.x * d, q.y * d, q.r * d, q.alpha)
        }
        return u
    }

    static let msl = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 res; float dpr; float t;
        float dark; float z; float2 mouse;
        float n; float m; float sel; float pad;
        float4 mem; float4 memW; float4 memC; float4 rip; float4 bgTint;
        float4 B[24]; float4 W[24]; float4 C[24]; float4 I[96];
    };

    struct VOut { float4 pos [[position]]; };

    vertex VOut fullscreenVertex(uint vid [[vertex_id]]) {
        const float2 p[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        VOut o; o.pos = float4(p[vid], 0.0, 1.0); return o;
    }

    static float wob(constant Uniforms& u, float2 d, float r, float ph, float amp) {
        float a = atan2(d.y, d.x);
        float s = 0.55 * sin(3.0 * a + u.t * 0.85 + ph * 6.2832)
                + 0.30 * sin(5.0 * a - u.t * 1.20 + ph * 11.0)
                + 0.15 * sin(2.0 * a + u.t * 0.55 + ph * 17.0);
        return r * (1.0 + amp * s);
    }

    static float smin(float a, float b, float k) {
        float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
        return mix(b, a, h) - k * h * (1.0 - h);
    }

    // GLSL mod: x − y·floor(x/y) (fmod negatiflerde farklı davranır).
    static float2 gmod(float2 x, float y) { return x - y * floor(x / y); }

    static float3 background(constant Uniforms& u, float2 p) {
        float2 uv = p / u.res;
        float3 col = mix(mix(float3(0.972, 0.970, 0.990), float3(0.068, 0.072, 0.104), u.dark),
                         mix(float3(0.928, 0.924, 0.975), float3(0.094, 0.084, 0.146), u.dark), uv.y);
        float2 q1 = uv - float2(0.86, 0.14); float2 q2 = uv - float2(0.08, 0.92);
        col = mix(col, mix(float3(0.875, 0.845, 1.000), float3(0.230, 0.165, 0.480), u.dark), exp(-dot(q1, q1) * 6.5) * 0.6);
        col = mix(col, mix(float3(0.835, 0.940, 0.985), float3(0.030, 0.220, 0.310), u.dark), exp(-dot(q2, q2) * 7.5) * 0.5);
        float3 tb = mix(mix(float3(1.0), u.bgTint.rgb, 0.40), u.bgTint.rgb * 0.24, u.dark);
        col = mix(col, tb, u.bgTint.a * 0.30);
        float2 q = p - u.res * 0.5;
        float f = fract(u.z);
        float s1 = 28.0 * u.dpr * exp2(f);
        float s2 = s1 * 0.5;
        float r1 = 1.3 * u.dpr * exp2(f);
        float r2 = r1 * 0.5;
        float d1 = 1.0 - smoothstep(r1 - 0.8 * u.dpr, r1 + 0.4 * u.dpr, length(gmod(q, s1) - 0.5 * s1));
        float d2 = 1.0 - smoothstep(r2 - 0.8 * u.dpr, r2 + 0.4 * u.dpr, length(gmod(q, s2) - 0.5 * s2));
        float3 dc = mix(float3(0.40, 0.40, 0.58), float3(0.58, 0.60, 0.82), u.dark);
        col = mix(col, dc, clamp(d1 * (1.0 - f) + d2 * f, 0.0, 1.0) * mix(0.24, 0.32, u.dark));
        float2 vv = uv - 0.5;
        col *= 1.0 - dot(vv, vv) * mix(0.16, 0.55, u.dark);
        return col;
    }

    static float2 ripple(constant Uniforms& u, float2 p) {
        if (u.rip.w <= 0.001) return p;
        float2 d = p - u.rip.xy; float L = length(d) + 0.001;
        float x = (L - u.rip.z * 1500.0 * u.dpr) / (80.0 * u.dpr);
        float k = exp(-x * x) * u.rip.w;
        return p - (d / L) * sin(x * 2.4) * 24.0 * u.dpr * k;
    }

    static float bubbleSD(constant Uniforms& u, int i, float2 p) {
        float4 b = u.B[i]; float4 w = u.W[i];
        float2 d = p - b.xy; float L = length(d);
        float r = b.z * (1.0 + 0.035 * w.w);
        float sd = (L > r * 1.3 + 24.0 * u.dpr) ? L - r : L - wob(u, d, r, w.x, w.y);
        return sd + (1.0 - w.z) * r * 0.85;
    }

    static float fieldOnly(constant Uniforms& u, int N, float2 p) {
        float F = 1e5;
        for (int i = 0; i < N; i++) {
            if (u.W[i].z < 0.004) continue;
            F = smin(F, bubbleSD(u, i, p), 10.0 * u.dpr);
        }
        return F;
    }

    static float fieldX(constant Uniforms& u, int N, float2 p, thread int& bi, thread float3& tint, thread float& rr) {
        float F = 1e5, best = 1e5, ws = 0.0;
        bi = -1; tint = float3(0.0); rr = 1.0;
        for (int i = 0; i < N; i++) {
            float a = u.W[i].z;
            if (a < 0.004) continue;
            float sd = bubbleSD(u, i, p);
            F = smin(F, sd, 10.0 * u.dpr);
            float m = max(sd, 0.0) / (7.0 * u.dpr);
            float wt = a / (1.0 + m * m);
            tint += u.C[i].rgb * wt; ws += wt;
            if (sd < best) { best = sd; bi = i; rr = u.B[i].z; }
        }
        tint /= max(ws, 1e-4);
        return F;
    }

    static float3 glass(constant Uniforms& u, float2 p, float2 g, float nd, float r, float3 tint, float hov, float3 L, float2 Lxy) {
        float z = sqrt(max(0.0, 1.0 - nd * nd));
        float3 n = normalize(float3(g * nd, z));
        float rr = min(r, 240.0 * u.dpr);
        float2 off = -g * nd * rr * 0.5 * (1.0 - 0.5 * z);
        float3 refr = float3(background(u, p + off * 0.93).r, background(u, p + off).g, background(u, p + off * 1.08).b);
        float tw = mix(0.19, 0.22, u.dark) + mix(0.36, 0.34, u.dark) * nd * nd;
        float3 tcol = mix(tint, tint * tint * 1.15, 0.35);
        float3 col = mix(refr, tcol * mix(1.0, 0.85, u.dark), tw);
        col *= mix(1.0, mix(0.94, 0.86, u.dark), smoothstep(0.25, 1.0, nd));
        float fr = pow(nd, 3.2);
        float3 rimc = mix(float3(1.0), mix(float3(0.85), tint, 0.45) + 0.15, u.dark);
        col = mix(col, rimc, fr * mix(0.52, 0.42, u.dark));
        float3 irid = 0.5 + 0.5 * cos(6.2832 * (nd * 1.35 + dot(g, float2(0.6, 0.8)) * 0.22 + u.t * 0.03 + float3(0.0, 0.33, 0.67)));
        col = mix(col, irid, pow(nd, 5.0) * mix(0.16, 0.24, u.dark));
        float arc = pow(max(dot(g, Lxy), 0.0), 7.0) * smoothstep(0.80, 0.94, nd) * (1.0 - smoothstep(0.955, 1.0, nd));
        col += arc * mix(0.55, 0.45, u.dark);
        float3 R = reflect(-L, n);
        float sp = pow(max(R.z, 0.0), 80.0);
        float soft = pow(max(dot(n, normalize(L + float3(0.0, 0.0, 1.0))), 0.0), 12.0);
        col += sp * 0.95 + soft * mix(0.09, 0.11, u.dark) * (1.0 + 1.5 * hov);
        float cs = pow(max(dot(g, -Lxy), 0.0), 2.5) * smoothstep(0.55, 0.9, nd) * (1.0 - smoothstep(0.92, 1.0, nd));
        col += cs * mix(tint, float3(1.0), 0.4) * mix(0.28, 0.42, u.dark);
        return col;
    }

    fragment float4 bubbleFragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        int N = min(int(u.n), 24), M = min(int(u.m), 96);
        // Metal'de konum zaten sol üstten başlar: GLSL'deki (x, uRes.y − y) çevirmesinin karşılığı.
        float2 p0 = in.pos.xy;
        float2 p = ripple(u, p0);
        float3 col = background(u, p);
        float sh = 0.0; float3 glow = float3(0.0);
        for (int i = 0; i < N; i++) {
            float4 b = u.B[i]; float a = u.W[i].z;
            if (a < 0.004) continue;
            float Ls = length(p - b.xy - float2(0.0, b.z * 0.16));
            sh += (1.0 - smoothstep(b.z * 0.55, b.z * 1.30, Ls)) * a * 0.5;
            glow += u.C[i].rgb * (1.0 - smoothstep(b.z * 0.8, b.z * 1.6, length(p - b.xy))) * a;
        }
        col *= 1.0 - clamp(sh, 0.0, 1.0) * mix(0.14, 0.30, u.dark);
        col += glow * mix(0.0, 0.05, u.dark);
        float2 Lv = u.mouse - p;
        float2 Lxy = normalize(Lv + 0.001);
        float3 L = normalize(float3(Lv / (0.34 * u.res.y), 1.0));

        if (u.mem.z > 0.5) {
            float2 d = p - u.mem.xy; float Ld = length(d);
            float sd = Ld - wob(u, d, u.mem.z, u.memW.x, u.memW.y);
            if (sd < 2.0 * u.dpr) {
                float nd = clamp(Ld / u.mem.z, 0.0, 1.0);
                float3 gc = glass(u, p, d / (Ld + 0.001), nd, u.mem.z, u.memC.rgb, 0.0, L, Lxy);
                float a = 1.0 - smoothstep(-1.0 * u.dpr, 1.0 * u.dpr, sd);
                col = mix(col, gc, a * mix(u.mem.w, u.memW.z, smoothstep(0.78, 1.0, nd)));
            }
        }

        int bi; float3 tint; float rr;
        float F = fieldX(u, N, p, bi, tint, rr);
        if (bi >= 0 && F < 2.5 * u.dpr) {
            float e = 1.0 * u.dpr;
            float2 g = float2(fieldOnly(u, N, p + float2(e, 0.0)) - fieldOnly(u, N, p - float2(e, 0.0)),
                              fieldOnly(u, N, p + float2(0.0, e)) - fieldOnly(u, N, p - float2(0.0, e)));
            g = normalize(g + 1e-6);
            float nd = 1.0 - clamp(-F / rr, 0.0, 1.0);
            float3 gc = glass(u, p, g, nd, rr, tint, u.W[bi].w, L, Lxy);
            gc = mix(gc, float3(1.0), (1.0 - smoothstep(0.0, 1.4 * u.dpr, abs(F))) * mix(0.30, 0.22, u.dark));
            float a = (1.0 - smoothstep(-1.0 * u.dpr, 1.0 * u.dpr, F)) * u.W[bi].z;
            col = mix(col, gc, a);
        }

        for (int i = 0; i < N; i++) {
            float st = u.B[i].w;
            if (st < 0.01 || u.W[i].z < 0.01) continue;
            float4 b = u.B[i]; float2 d = p - b.xy;
            if (length(d) > b.z * 1.3 + 14.0 * u.dpr) continue;
            float sd = length(d) - wob(u, d, b.z * (1.0 + 0.035 * u.W[i].w), u.W[i].x, u.W[i].y);
            float3 acc = mix(float3(0.0, 0.44, 0.89), float3(0.04, 0.52, 1.0), u.dark);
            float ring = 1.0 - smoothstep(0.7 * u.dpr, 2.2 * u.dpr, abs(sd - 6.0 * u.dpr));
            float pulse = st > 0.75 ? (0.75 + 0.25 * sin(u.t * 3.2)) : 0.4;
            col = mix(col, acc, ring * pulse * u.W[i].z);
            col = mix(col, acc, (1.0 - smoothstep(-1.0 * u.dpr, 1.0 * u.dpr, sd)) * (st > 0.75 ? 0.10 : 0.05) * u.W[i].z);
        }

        for (int j = 0; j < M; j++) {
            float4 b = u.I[j];
            if (b.w < 0.004) continue;
            float2 d = p - b.xy; float Ld = length(d);
            if (Ld > b.z * 1.2 + 3.0 * u.dpr) continue;
            float sd = Ld - wob(u, d, b.z, float(j) * 0.137, 0.035);
            if (sd < 1.5 * u.dpr) {
                float nd = clamp(Ld / b.z, 0.0, 1.0);
                float z = sqrt(max(0.0, 1.0 - nd * nd));
                float2 g = d / (Ld + 0.001);
                float3 n = normalize(float3(g * nd, z));
                float3 lift = mix(mix(col, float3(1.0), 0.45), col * 1.35 + 0.035, u.dark);
                float3 c2 = mix(col, lift, 0.35 + 0.35 * nd * nd);
                c2 = mix(c2, float3(1.0), pow(nd, 3.0) * mix(0.40, 0.30, u.dark));
                float3 R = reflect(-L, n);
                c2 += pow(max(R.z, 0.0), 110.0) * 0.28;
                col = mix(col, c2, (1.0 - smoothstep(-1.0 * u.dpr, 1.0 * u.dpr, sd)) * b.w);
            }
        }
        return float4(col, 1.0);
    }
    """#
}
