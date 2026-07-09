//
//  SunCalc.swift
//  str8ToDo
//
//  NOAA Solar Calculator 標準式による日の出・日の入り計算。
//  Foundation のみ依存（SwiftUI/SwiftData 非依存）。p7-selfcheck.swift で検証する。
//

import Foundation

enum SunCalc {
    /// 指定日（現地 startOfDay）・緯度経度の日の出/日の入りを Date で返す。
    /// 「calendar のタイムゾーンでのその日」の日の出/日の入り（UTC 基準で計算）。
    /// 極夜/白夜（|cosH| > 1）は nil。
    static func sunTimes(
        on day: Date,
        latitude: Double,
        longitude: Double,
        calendar: Calendar = .current
    ) -> (sunrise: Date, sunset: Date)? {
        // 現地カレンダー日の UTC 0:00（東京の 1/1 現地 0:00 は UTC 12/31 15:00 → +TZ オフセットで UTC 1/1 0:00）
        let localMidnight = calendar.startOfDay(for: day)
        let utcMidnight = localMidnight.addingTimeInterval(
            TimeInterval(calendar.timeZone.secondsFromGMT(for: localMidnight))
        )

        // 1パス目: 正午（UTC 720分）推定 → 2パス目: 得られた時刻の T で再計算（±1分精度）
        guard let riseGuess = eventMinute(utcMidnight: utcMidnight, latitude: latitude, longitude: longitude,
                                          guessMinute: 720, isSunrise: true),
              let setGuess = eventMinute(utcMidnight: utcMidnight, latitude: latitude, longitude: longitude,
                                         guessMinute: 720, isSunrise: false),
              let rise = eventMinute(utcMidnight: utcMidnight, latitude: latitude, longitude: longitude,
                                     guessMinute: riseGuess, isSunrise: true),
              let set = eventMinute(utcMidnight: utcMidnight, latitude: latitude, longitude: longitude,
                                    guessMinute: setGuess, isSunrise: false)
        else { return nil }

        return (
            sunrise: utcMidnight.addingTimeInterval(rise * 60),
            sunset: utcMidnight.addingTimeInterval(set * 60)
        )
    }

    // MARK: - NOAA 標準式（角度は度、三角関数呼び出し時にラジアン変換）

    private static func deg2rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func rad2deg(_ r: Double) -> Double { r * 180 / .pi }

    /// UTC 0:00 起点の推定分 guessMinute の太陽位置で、日の出/日の入りの分（UTC）を返す。
    /// 白夜/極夜は nil。
    private static func eventMinute(
        utcMidnight: Date,
        latitude: Double,
        longitude: Double,
        guessMinute: Double,
        isSunrise: Bool
    ) -> Double? {
        // ユリウス日 → ユリウス世紀 T（推定時刻基準）
        let date = utcMidnight.addingTimeInterval(guessMinute * 60)
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let t = (jd - 2451545.0) / 36525

        // 幾何平均黄経 L0・平均近点角 M・離心率 e
        let l0 = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35999.05029 - t * 0.0001537)
        let e = 0.016708634 - t * (0.000042037 + t * 0.0000001267)

        // 中心差 C → 真黄経 → 見かけ黄経 λapp
        let mRad = deg2rad(m)
        let c = sin(mRad) * (1.914602 - t * (0.004817 + t * 0.000014))
            + sin(2 * mRad) * (0.019993 - t * 0.000101)
            + sin(3 * mRad) * 0.000289
        let trueLong = l0 + c
        let omega = 125.04 - 1934.136 * t
        let lambdaApp = trueLong - 0.00569 - 0.00478 * sin(deg2rad(omega))

        // 黄道傾斜（章動補正込み）→ 赤緯 δ
        let epsilon0 = 23.439291 - t * (0.0130042 + t * (0.00000016 - t * 0.000000504))
        let epsilon = epsilon0 + 0.00256 * cos(deg2rad(omega))
        let delta = asin(sin(deg2rad(epsilon)) * sin(deg2rad(lambdaApp)))

        // 均時差 EqT（分）= 4 × degrees(y·sin2L0 − 2e·sinM + 4e·y·sinM·cos2L0 − 0.5y²·sin4L0 − 1.25e²·sin2M)
        let y = pow(tan(deg2rad(epsilon / 2)), 2)
        let l0Rad = deg2rad(l0)
        let eqt = 4 * rad2deg(
            y * sin(2 * l0Rad) - 2 * e * sin(mRad)
            + 4 * e * y * sin(mRad) * cos(2 * l0Rad)
            - 0.5 * y * y * sin(4 * l0Rad)
            - 1.25 * e * e * sin(2 * mRad)
        )

        // 時角 H（大気屈折込みの天頂角 90.833°）。|cosH| > 1 は白夜/極夜。
        let latRad = deg2rad(latitude)
        let cosH = cos(deg2rad(90.833)) / (cos(latRad) * cos(delta)) - tan(latRad) * tan(delta)
        guard abs(cosH) <= 1 else { return nil }
        let h = rad2deg(acos(cosH))

        // 太陽正午（分, UTC）= 720 − 4×経度（東経が正）− EqT。日の出 = 正午 − 4H、日の入り = 正午 + 4H
        let solarNoon = 720 - 4 * longitude - eqt
        return isSunrise ? solarNoon - 4 * h : solarNoon + 4 * h
    }
}
