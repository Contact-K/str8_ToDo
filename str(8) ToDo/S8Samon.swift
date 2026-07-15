// S8Samon.swift — 枯山水 raked-sand ripple 背景（str8_Talk/iosApp/S8Aquarium.swift から移植）
//
// design/samon.js の SwiftUI 実装。主リップル + 副リップルのコヒーレントな場が
// 「石」のまわりでガウス押し出しで分かれる。位相だけがゆっくり流れるアンビエントアニメ。
// Reduce Motion 時は静止。
// ponytail: 移植元にあったショップ theme tint は本 repo に無いので撤去。
// 使う側は `S8SamonPaper()` を背景に敷くだけで OK。

import SwiftUI
import UIKit

/// samon.js の stones に対応（x/y/r は枠に対する割合、s は強さ）。
struct S8SamonStone {
    var x: CGFloat
    var y: CGFloat
    var r: CGFloat = 0.16
    var s: CGFloat = 1
}

struct S8Samon: View {
    // samon.js の既定値
    var gap: CGFloat = 11        // 線の間隔 px
    var amp: CGFloat = 16        // 主リップル振幅 px
    var wl: CGFloat = 560        // 主リップル波長 px
    var step: CGFloat = 11       // x サンプル間隔 px
    var stones: [S8SamonStone] = []
    var opacity: Double = 1      // 一覧タブでは控えめにする用
    /// 線色の上書き（nil = palette の line）。ショップの砂紋テーマ復活時はここに tint を挿す。
    var tint: Color? = nil
    var animated: Bool = true
    /// 初期位相（タブ切替ごとのランダム表情用）。
    var phaseOffset: CGFloat = 0

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if animated && !UIAccessibility.isReduceMotionEnabled {
            // 位相が流れて見える速さ（1周 ≈ 36 秒）+ 振幅がゆっくり呼吸（±12% / 9 秒）。
            TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                canvas(
                    phase: CGFloat(t.truncatingRemainder(dividingBy: 36) / 36) * 2 * .pi + phaseOffset,
                    breath: 1 + 0.12 * CGFloat(sin(t / 9 * 2 * .pi))
                )
            }
        } else {
            canvas(phase: phaseOffset, breath: 1)
        }
    }

    private func canvas(phase: CGFloat, breath: CGFloat) -> some View {
        let c = S8Palette.of(scheme)
        let lineColor = tint ?? c.line
        let strongColor = tint ?? c.lineStrong
        let a = amp * breath
        return Canvas { ctx, size in
            let W = size.width, H = size.height
            guard W > 0, H > 0 else { return }
            let minD = min(W, H)
            let tau: CGFloat = 2 * .pi

            var y0: CGFloat = -amp * 2
            while y0 <= H + amp * 2 {
                var path = Path()
                var first = true
                var x: CGFloat = 0
                while x <= W + step {
                    var y = y0
                    // 主 + 副リップル — コヒーレントに流れる場（samon.js と同式・位相だけ流す。
                    // 副リップルは逆方向にやや速く流し、干渉のゆらぎを見せる）
                    y += a * sin((x / wl) * tau + y0 * 0.012 + phase)
                    y += a * 0.34 * sin((x / (wl * 0.4)) * tau + y0 * 0.03 + 1.3 - phase * 1.6)
                    // 石 — 線が岩を避けて分かれる（ガウスの垂直押し出し）
                    for st in stones {
                        let sx = st.x * W, sy = st.y * H, sr = st.r * minD
                        let dx = x - sx, dy = y0 - sy
                        let dist2 = dx * dx + dy * dy
                        let f = exp(-dist2 / (2 * sr * sr))
                        y += (dy >= 0 ? 1 : -1) * f * sr * 0.72 * st.s
                    }
                    if first { path.move(to: CGPoint(x: x, y: y)); first = false }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                    x += step
                }
                ctx.stroke(path, with: .color(lineColor.opacity(opacity)), lineWidth: 1)
                y0 += gap
            }

            // 石そのものの輪郭（同心の楕円リング）。流線が分かれるだけだと
            // 「石がどこにあるか」分かりにくいため、中心に岩を描く。
            for st in stones {
                let sx = st.x * W, sy = st.y * H, sr = st.r * minD
                for k: CGFloat in [0.18, 0.30, 0.42] {
                    let rr = sr * k
                    let rect = CGRect(x: sx - rr, y: sy - rr * 0.66, width: rr * 2, height: rr * 1.32)
                    ctx.stroke(Path(ellipseIn: rect),
                               with: .color(strongColor.opacity(opacity * 0.9)),
                               lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 砂紋つき紙背景。View に敷くだけで開くたびに違う砂紋になる。
/// 使い方: `SomeView().background(S8SamonPaper())`
struct S8SamonPaper: View {
    var opacity: Double = 0.45
    var tint: Color? = nil
    @State private var phaseOffset = CGFloat.random(in: 0...(2 * .pi))
    @State private var stones: [S8SamonStone] = S8SamonPaper.randomStones()
    @Environment(\.colorScheme) private var scheme

    /// 0〜2 個の石をランダム配置（端に寄りすぎない範囲）。
    static func randomStones() -> [S8SamonStone] {
        (0..<Int.random(in: 0...2)).map { _ in
            S8SamonStone(
                x: .random(in: 0.18...0.82),
                y: .random(in: 0.2...0.8),
                r: .random(in: 0.10...0.22),
                s: .random(in: 0.5...0.9)
            )
        }
    }

    var body: some View {
        let c = S8Palette.of(scheme)
        ZStack {
            c.paper
            S8Samon(stones: stones, opacity: opacity, tint: tint, phaseOffset: phaseOffset)
        }
        .ignoresSafeArea()
    }
}
