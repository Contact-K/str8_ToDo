# str(8) ToDo — 実装ロードマップ

> 基準文書: `~/Claude_WRKSPC/Obsidian/02-Projects/str(8)_ToDo/str(8) ToDo.md`(企画書、2026-07-02全面改訂版)
> 作成: 2026-07-03。既存コード棚卸しの結果を反映済み。
> 方針: 既存コードの使える部分は流用し、新仕様(2026-07-02改訂)とズレている部分だけ作り直す。

---

## 共通ルール(全フェーズ適用)

- **pbxproj**: 個別ファイル登録方式(objectVersion 77、filesystem-synchronized groupsではない)。**新規 .swift は必ず pbxproj に登録する**。
- **用途文字列**: `INFOPLIST_KEY_*` ビルド設定に書く(Calendars / Location の既存パターンに倣う)。例外: `NSBonjourServices`(配列型)のみ `Info.plist` 本体に書く。
- **スキーマ自由期間**: 未リリース・ユーザーなしなので、**P6(バックアップ)完成まで** @Model は自由に変更してよい(シミュレータのストア破棄で対応、マイグレーション不要)。P6 以降は加算的変更のみ、または .str8 フォーマットバージョンを上げる。
- **各フェーズの検証**: `xcodebuild build` → シミュレータで実行確認 → `PreviewData.swift` をそのフェーズのモデル/ビューに追随させる(プレビューを腐らせない)。実機必須フェーズは明記(モーション/UWB/Multipeer はシミュレータ不可)。
- **リーン原則**: 既存流用最優先。投機的抽象は作らない。集計キャッシュ Model は「計測して遅い」場合のみ追加(例: SubjectStat は最初はライブ集計)。

---

## フェーズ一覧と順序根拠

| # | フェーズ | 検証環境 | 企画書対応 |
|---|---------|---------|-----------|
| 0 | 基盤リファクタ(ステータス・Band・TaskItem拡張・ピンチ削除) | Sim | P0前提 |
| 1 | 日ビュー再構築(カード式アジェンダ+「今」中心) | Sim | P0 |
| 2 | 週=マイ時間割+横断キャプセル+Morph | Sim | P1 |
| 3 | 仕分けカード+ToDoリスト(日常ループ完成) | Sim | 柱③+⑤ |
| 4 | 砂時計タイマー(CoreMotion+AlarmKit+FocusSession) | **実機** | 柱② |
| 5 | 承認プロトコル(chop+ソロ確定キュー+MPC/NI) | **実機2台** | 柱④ |
| 6 | 暗号化バックアップ(.str8) | Sim | W0(前倒し) |
| 7 | 外部情報層(天気キャッシュ・日の出日の入り・出発逆算) | Sim | P2 |
| 8 | お金(金額付きイベント+MonthMoneyStat) | Sim | P3 |
| 9 | 年ビューDayStat化+枠エディタ磨き込み+アクセシビリティ | Sim | P4 |
| 10 | Study Hub(S0〜S3) | Sim | 追加① |
| 11 | ウィジェット+StandBy(App Groups) | 実機/Sim | W1 |
| 12 | 空きコマ自動提案 | Sim | W2 |
| 13 | 週次締めの儀式(週報) | 実機 | W3 |
| 14 | ローカルP2P集中ルーム | **実機2台+** | W4 |
| 15 | WH 7分類データモデル+概要タイル/フォーカス編集シート（E0+E1） | Sim | イベント作成シート |
| 16 | 自然文クイック追加パーサ（E2） | Sim | イベント作成シート |
| 17 | 辞書管理画面（E3） | Sim | イベント作成シート |
| 18 | 既存タスク編集の直接ジャンプ導線（E4） | Sim | イベント作成シート |

**順序根拠:**

- **P0 が先**: pending 廃止と Band 系モデルは TaskItem / TaskDetailView / DayView / WeekView / YearView / AddTaskSheet / PreviewData / スキーマ登録のほぼ全てに波及する。ビューを作り直す前に一度だけやらないと、全ビューを二度触ることになる。W2(自動提案)の学習データになる `actualDuration` と、DayStat 逐次更新を一元化する `approve()` チョークポイントという「早く植えるべき種」もここで植える。
- **日(P1)→週(P2)の順**: 日カードは Morph の対応先(週セル⇄日カード 1:1、キャプセル⇄時刻厳守カード)であり、仕分けカードとの共有コンポーネントでもある。先に本物のカードを作れば、P2 のキャプセル検証が本物相手にできる。
- **P3 で最小日常ループ完成**(朝の仕分け→日アジェンダ→done→翌日ソロ承認)。ここからドッグフーディング開始=データが実物になる。だから直後の P6 にバックアップを前倒し(企画書 W0「データを持ち始めた瞬間から必要。最優先」)。
- **タイマー(P4)が承認(P5)より先**: どちらも CoreMotion。タイマーで作るモーションデバッグ HUD とチューニング手順を chop 検出が流用する。P4 はカレンダー非依存なので、実機の都合次第で P3 と入れ替え可。
- **P7/P8/P9** は企画書 P2→P3→P4 の順のまま。既存ビューへの装飾で下流依存なし(移動セグメントは P7 までデータ空で非表示なだけ)。P9 の頃には DayStat に実データが数ヶ月分溜まっている。
- **P10(Study Hub)**は FocusSession(P4)必須。ヒートマップは P9 で部品化した YearView のものを流用。
- **第2弾の残り(P11〜P14)**は企画書 W1〜W4 の順。企画書が指定する2つの優先逆転(W0 前倒し / actualDuration 早期記録開始)は P6 / P0+P4 で消化済み。

---

## Phase 0 — 基盤リファクタ 〔Sim〕

多数のビューに波及するモデル変更を一度に済ませる。

1. **ステータス2層化**: `Enums.swift` の `TaskStatus` を `incomplete/pending/approved` → `active/done/approved` へ。`TaskItem.markPending(...)` → `markDone()`(`completedAt` + `unlockDate`=翌日0:00 を設定)。波及先を全部更新: `TaskDetailView` のアクションボタン、`DayView`/`WeekView` の打ち消し線条件(`done || approved`)、`AddTaskSheet`、`PreviewData`、`YearView`(stats は引き続き approved のみ)。
2. **Band 系モデル新設**: `Band` / `BandTemplate` / `BandAssignment` を新規 `BandModels.swift` に @Model で作成。**`FixedSchedule` は削除**(ルーティーンは「RRULE 付き枠スナップイベント」で表現)。初回起動時にデフォルトテンプレ(「平日」)を1つシード。`str_8__ToDoApp.swift` のスキーマ登録を更新。PreviewData に Band を追加。
3. **TaskItem 拡張+approve() チョークポイント**: `amount: Decimal?` / `paymentMethod: String?` / `actualDuration: TimeInterval?` を追加(推定所要は既存 `duration` を兼用、`estimatedDuration` は作らない)。承認処理を単一関数 `approve(by:context:)` に集約し、ステータス遷移**と同時に** `approvedAt` の日の `DayStat` を upsert する。再承認は no-op(二重カウント防止)。以後の全承認経路(ソロ chop・ペア chop・リスト・週報)はここを通す。
4. **ピンチ削除**: `MorphCalendar.swift` の `MagnifyGesture` ブロックと `.gesture(pinch)` を削除。ピル型セレクター+直接タップズームに一本化(企画書 2026-07-02 決定)。

**受け入れ基準**: ビルド&起動OK。月/週/日が新 enum で描画される。`grep` で `pending` / `FixedSchedule` の参照ゼロ。TaskDetailView から承認すると DayStat が正確に1回だけ加算される。ピンチしても何も起きない。

---

## Phase 1 — 日ビュー再構築: カード式アジェンダ 〔Sim〕

24h 連続タイムラインを廃止し、カード式+「今」中心へ(企画書 2026-07-02 改訂)。

1. **`TaskCardView`(新規)**: 共有カードコンポーネント。タイトル・時刻範囲・カテゴリ色・「時刻厳守」バッジ(isTimePinned)・スター/場所アイコン・done 打ち消し線。日アジェンダと仕分けデッキの両方で使えるサイズ設計。「カード=タスク」の言語をアプリ全体で統一する要。
2. **`DayAgendaView`(新規、DayView の中身を置換)**: 行モデル `enum DayRow { bandHeading, task, gap, nowSeparator }`(travel ケースは P7 で追加)。枠見出しはその日の BandAssignment から解決。カードは時刻順。当日は「今」セパレータ常設+初期スクロール位置は常に「今」。「次の予定まであと◯分」を「今」直下に表示。
3. **過去の畳み+空きカード**: 過去カードは薄く畳む(タップで展開、済マーク付き)。空き時間は薄いカード(「空き2.5h ＋タスクを置く」)として挟み、タップで開始時刻・所要をプレフィルした `AddTaskSheet` を開く。
4. **`DayPane`(MorphCalendar.swift)への接続**: `dayKey` と `"evt-<uuid>"` の matchedGeometryEffect ID は維持。旧タイムラインコード(`DayTaskBlock` のオフセット計算)は削除。

**受け入れ基準**: 当日を開くと「今」中心で表示。過去は薄く畳まれタップで展開。空きカードタップで正しくプレフィルされたタスク作成。時刻固定カードにバッジ表示。当日以外は「今」セパレータなしの素のアジェンダ。

---

## Phase 2 — 週=マイ時間割+横断キャプセル+Morph 〔Sim〕

7列×連続時間軸を廃止し、枠グリッドへ(企画書 2026-07-02 改訂)。

1. **【スパイク・最優先検証】横断キャプセルの座標マッピング**: 企画書が「最優先検証」と明記した項目。高さの違う行をハードコードしたグリッドで、PreferenceKey で行フレームを収集→時刻→行フレーム補間で1本のキャプセルを配置。スクロール中・5/7日切替時の追随を検証。**マッピングヘルパーだけ残して捨てる前提のコード**。
2. **週グリッド再構築**(`WeekView.swift` の中身): 行=列(日)ごとに BandAssignment から解決した枠(曜日デフォルト+特定日差し替え)。行高は実時間でなく情報量基準(行内チップ数でクランプ)。平日5日/7日切替。日ヘッダは流用(天気アイコンは P7 までプレースホルダ)。
3. **枠スナップイベント**: RRULE イベントは開始時刻の包含判定で該当枠セルに着地。正確な時刻はセル内に小さく表示。タップで詳細へ。
4. **横断キャプセル**: 時刻固定イベント(isTimePinned)をスパイクのマッピングで枠の上に縦断オーバーレイ。枠線付きで「時刻厳守」を示す。移動セグメントのサブビューはデータがある時のみ描画(P7 で点灯)。
5. **Morph ペアリング**: 週チップ⇄日カードは同じ `"evt-<uuid>"` ID を共有。キャプセル⇄時刻厳守カードも接続。フォーカス日アンカー(切替前に見ていた日に着地)。スプリングをチューニング。**Morph 品質はこのフェーズの明示的な受け入れゲート**。
6. **枠テンプレートエディタ(最小版)**: `CalendarSettingsView` に枠(名前・時間帯)・テンプレ・曜日割当の編集を追加。`AppSettings.swift` の `weekStartMinutes`/`weekEndMinutes`/`weekBandIntervalHours` と `makeWeekBands` を削除。磨き込みは P9。

**受け入れ基準**: ユーザー定義の枠が行として描画される。時刻固定イベントが正しい行範囲をキャプセルとして縦断し、スクロールしてもズレない。週→日/日→週の Morph でカードが 1:1 で追随する(クロスフェード落ちしない)。特定日の差し替えでその列だけ枠構成が変わる。

---

## Phase 3 — 仕分けカード+ToDoリスト 〔Sim〕★ここからドッグフーディング開始

日常ループ(朝の仕分け→日アジェンダ→done→翌日ソロ承認)を完成させる。

1. **`TodoListView`(新規、リストタブ)**: `startDate == nil` の浮遊タスクを 今日/いつか セクションで表示。クイック追加(上部入力)。スワイプ=`markDone()`(打ち消し線→即リストから消える)。ドラッグ並べ替え(TaskItem に `sortIndex` 追加)。日時確定でカレンダーへ昇格(一方向)。
2. **仕分けデッキエンジン(`SortDeckView` 新規)**: デッキ=`lastSortedDay < today` の浮遊タスク(タスク単位のスタンプ=途中離脱の再開が無料で手に入る)。第1段=完了ゲート(右=やった→markDone / 左=まだ)、第2段=今日ゲート(右=今日 / 左=先送り、既定+1週間)。undo/redo スタック。カードは `TaskCardView` を流用。
3. **起動トリガー+アクセシビリティ**: その日初回のフォアグラウンドで `lastSortDate ≠ today` かつ未仕分けありならモーダル提示。画面下中央に巻き戻し/やり直し常設。スワイプの代替ボタン常設。VoiceOver で全操作可能に。

**受け入れ基準**: 日が変わって起動するとデッキが出る。仕分け結果がリストのバケツに反映される。途中で閉じて再起動すると続きから。undo で直前のスワイプが戻る。done はリストから打ち消し線付きで消える。VoiceOver だけでデッキを完走できる。

---

## Phase 4 — 砂時計タイマー 〔実機必須〕

1. **【スパイク】モーション HUD**: gravity.z / rotationRate.x のライブ表示+姿勢ステートマシン(portrait=setting → faceUp=armed → faceDown=running)。デバウンス0.3秒、ヒステリシス 入0.75/出0.6、gyro ピークで意図的フリップと置き直しを区別。実機でチューニング。**合格基準: 意図フリップ 10/10 検出、机バンプでの誤発火 0**。HUD は後の chop チューニング(P5)でも使う。
2. **タイマー本体+UI**(`HourglassMotion.swift` / `TimerView.swift` 新規): カウントダウン、タスク紐付け+ポモドーロプリセット(25/5/15分)、縦ドラッグで分増減+ハプティックティック、砂時計ビジュアル。完了で `FocusSession` @Model(start / end / taskID? / subjectID?=nil)を記録し、紐付けタスクの `actualDuration` に反映(W2 の学習データ蓄積がここから始まる)。
3. **AlarmKit + Live Activity**(`AlarmService.swift` 新規): 開始時に AlarmManager にスケジュール(サイレント/Focus 貫通)、早期停止でキャンセル。Widget Extension の Live Activity でロック画面/Dynamic Island にカウントダウン。`NSMotionUsageDescription` / `NSAlarmKitUsageDescription` を追加。

**受け入れ基準(実機)**: 伏せて開始・起こして終了。ロック+サイレントでもアラームが鳴る。Live Activity のカウントダウン表示は P11（Widget Extension）で実装。FocusSession が永続化され、actualDuration がタスクに載る。シミュレータでは UI と手動開始/停止のみ確認可。

---

## Phase 5 — 承認プロトコル 〔ペアは実機2台/ソロはSim可〕

1. **`ChopDetector`(新規・独立型)**: userAcceleration の下向きピーク>約2g→静止 で振り下ろし検出。P4 の HUD パターンで実機チューニング。W3(週報)でも流用するため独立させる。
2. **ソロ確定キュー(承認タブ)**: done タスクを一覧表示、`unlockDate` までカウントダウン付きロック。解除後は chop(または代替ボタン)で P0 の `approve()` チョークポイント経由で確定。stats 側に「未確定 ◯件」の控えめ表示+ここへの導線。
3. **MPC ラッパー(`PeerSession.swift` 新規)**: advertise/browse、ペア UI、承認ペイロード交換、フォアグラウンド限定のライフサイクル。W4(集中ルーム)で流用するため汎用に(ただし必要最小限)。
4. **近接ゲート(`ProximityGate.swift` 新規)**: NearbyInteraction で約10cm ゲート、UWB 非対応機は BLE RSSI フォールバック。`NSLocalNetworkUsageDescription`+NI 用途文(ビルド設定)、`NSBonjourServices`(Info.plist 本体)を追加。

**受け入れ基準**: Sim — unlockDate 注入でロック/解除境界が正しく動く。実機 — chop で確定。2台がペアリングし、近接時のみゲートが開き、承認が転送されて approverID が記録され、DayStat が正確に1回加算される。

---

## Phase 6 — 暗号化バックアップ(.str8) 〔Sim〕

企画書 W0。実データが溜まり始めた直後に前倒し。**これ以降はスキーマ変更に注意(加算的変更のみ、またはフォーマットバージョンを上げる)**。

1. **エクスポート(`BackupService.swift` 新規)**: 全モデルのバージョン付き JSON → パスフレーズ由来キー(注: CryptoKit に PBKDF2 はない。CommonCrypto の PBKDF2 か、ソルト付きダイジェスト+HKDF かをフェーズ内で決定)→ AES-GCM 暗号化 → fileExporter で `.str8` 書き出し(AirDrop/ファイルApp)。
2. **インポート**: fileImporter → 復号 → バージョン確認 → 確認ダイアログ → 全消去して復元。設定画面に最終エクスポート日時表示+月1の控えめリマインド。

**受け入れ基準**: エクスポート→ストア全消去→インポートでエンティティ数が完全一致。誤パスフレーズは明確なエラー。フォーマットにバージョンフィールドがあり、後続モデル(Subject / MonthMoneyStat / WeatherCache)を加算的に足せる。

> **メモ（2026-07-11）**: P6 以降は加算的変更のみが原則だが、P13 で `WeekReview` モデル廃止（オーナー判断、後述）のため例外的に非加算変更が発生した。未リリース・開発端末のみのライブストアなのでシミュレータ再起動（ストア破棄）で対応可能（マイグレーション不要）。

---

## Phase 7 — 外部情報層 〔Sim(+実機1台で挙動確認)〕

企画書 P2。「取得後キャッシュ+鮮度表示」でオフライン主義と両立。

1. **天気キャッシュ**: `WeatherCache` @Model 新設、`WeatherProvider` をキャッシュ経由に改修。「◯分前に更新」鮮度ラベル部品を作り、日ヘッダ・週の日ヘッダ(P2 のプレースホルダを置換)に接続。オフライン時はキャッシュ+鮮度表示。
2. **日の出日の入り(`SunCalc.swift` 新規)**: NOAA アルゴリズムの純関数で完全オフライン算出。既知の日付・地点との assert 自己チェック付き。日アジェンダの該当位置に細いライン表示。
3. **出発逆算(`DepartureService.swift` 新規)**: 場所座標を持つ直近(≤24h)の時刻固定イベントのみ MKDirections で ETA 算出→キャッシュ。DayRow に `.travel` ケース追加(移動カード)、週キャプセルに移動セグメント点灯、「今」中心表示に「出発は◯:◯」。

**受け入れ基準**: 機内モードで再起動しても天気がキャッシュ+古さラベルで出る。日の出日の入りが参照値と1分以内で一致。場所付き時刻固定イベントに移動カードと正しい出発時刻が出る。遠い将来のイベントにルート要求が飛ばない。

---

## Phase 8 — お金(金額付きイベント) 〔Sim〕

企画書 P3。専用モジュールは作らない。

1. **入力**: `AddTaskSheet` / `TaskDetailView` に折りたたみのお金セクション(amount / paymentMethod)。サブスク=カテゴリ「サブスク」+RRULE+amount(新モデルなし)。
2. **集計**: `MonthMoneyStat` @Model 新設。金額付きイベントの変更時に該当月を再計算(「インクリメンタル」はこのリーンな形で満たす)。月ビューヘッダ下に「今月のサブスク合計/支出」、支出のある日セルに小さく金額。カテゴリ別/支払方法別の内訳シート(月ビューから1タップ)。

**受け入れ基準**: 金額入力が月ヘッダに即反映。内訳の合計が一致。サブスクの発生が各月に計上される(月末開始は短い月では月末日にクランプ)。削除で整合が取れる。

> **P8 実装後の改訂(2026-07-10、debate-review の結果)**: TaskDetailView は全フィールド表示専用の既存設計のため、金額の**編集**は将来のタスク編集機能と同時に実装する(その際 `MoneyStats.recompute` の呼び出しを忘れないこと)。recompute は現状「保存/削除時に該当1ヶ月+月ビュー表示時の自己修復」— P13(週報)は MonthMoneyStat を直接読むため、**P13 着手前に** 反復タスク変更時の複数月再計算へ発火戦略を見直す。タイムゾーン変更で月キー(Date)が重複しうる既知の天井あり(クラッシュせず表示が古くなるのみ)→同時に固定カレンダーの月キー化を検討。**据え置き（2026-07-11 時点で未対応、天井として残置）**。

---

## Phase 9 — 年ビュー DayStat 化+磨き込み 〔Sim〕

企画書 P4。この頃には DayStat に実データが溜まっている。

1. **YearView 改修**: ヒートマップ+ストリークを TaskItem 全走査から DayStat クエリに切替。設定/デバッグに一括再構築 `rebuildDayStats()`。カテゴリ積み上げバーは遅くなければタスク集計のまま(オーナー決定 #10)。
2. **枠テンプレートエディタ磨き込み+特定日差し替え UI+アクセシビリティパス**(Dynamic Type、カレンダー各ビューと AddTaskSheet の VoiceOver)。

**受け入れ基準**: 1年分の合成 DayStat で年ビューが一瞬で描画される。ヒートマップ=approved 数と一致。主要フローのアクセシビリティチェックリスト通過。

---

## Phase 10 — Study Hub(S0〜S3) 〔Sim〕

- **S0**: `Subject` @Model(色・週/日目標・ポモプリセット)。タイマーに科目ピッカー、FocusSession.subjectID 記録開始。タブのスケルトン+今日/今週合計。
- **S1**: 集中ヒートマップ(P9 で部品化した YearView ヒートマップを focusSeconds で流用)、週次バー、科目別積み上げ。
- **S2**: 目標・ストリーク(FocusSession からライブ集計。キャッシュは遅ければ)。
- **S3**: 科目別ポモプリセットの完全接続、勉強タスクビュー(リストの科目タグ絞り込み)、磨き込み。

**受け入れ基準**: タイマーのセッションが科目に紐付いて Hub に出る。目標進捗・ストリークが正しい。プリセットがタイマー既定値を変える。

> **debate-review 繰り越し(最終ブラッシュアップでまとめて対応、2026-07-10)**: P10 実装後の多角レビューで挙がった、実害は無いが将来負債になる項目。
> - **DayStat.focusSeconds の二重集計源**: Study Hub は FocusSession をライブ集計し、DayStat.focusSeconds(rebuildDayStats のみが書く)を誰も読まない死にフィールド化している。どちらかに寄せる(Hub を DayStat 経由にする / DayStat から focusSeconds を外す / 意図コメントで固定)。
> - **subjectID を生 UUID で保持**: `TaskItem.subjectID` / `FocusSession.subjectID` は既存の `@Relationship(deleteRule:.nullify)` パターン外。Subject 削除 UI を追加する際に nullify 戦略を用意するか、FocusSession.taskID と同様の意図コメントを付ける。
> - **復元値の範囲検証**: SubjectDTO の goal/pomodoro 分が復元時に無検証で、`totalDuration = selectedMinutes * 60` の乗算が極端値でオーバーフローし得る。復元値をクランプ。
> - **Subject の編集/削除 UI**: 現状 AddSubjectSheet は追加専用。目標・ストリークの訂正手段として編集/削除を追加。

---

## Phase 11 — ウィジェット+StandBy(W1) 〔実機/Sim〕

App Group 追加、SwiftData ストアをグループコンテナへ移動(起動時に一度だけコピー)。Widget Extension(次のカード/今日の枠と達成数/未確定件数)、ロック画面各種+StandBy ファミリ。予定の境界時刻にタイムラインエントリを事前生成。

**受け入れ基準**: データ変更後のタイムラインリロードでウィジェットに反映される。

> **P11 実装メモ（2026-07-11）**: 上記の「SwiftData ストアをグループコンテナへ移動」は**不採用**。代わりに **App Group 共有ファイルにアプリが表示用スナップショット JSON を書き出し、ウィジェットがそれを読む**方式で実装（オーナー決定：生ストア移行のデータ消失リスク回避・widget へのモデル共有不要）。共有型/IO は `WidgetShared.swift`（純 Foundation・両ターゲット所属）、生成は `WidgetSnapshotService.swift`。詳細は memory [[str8-todo-phase11-widget-decisions]]。

> **P11 debate-review 繰り越し（2026-07-11、最終ブラッシュアップでまとめて対応）**: 多角レビューで挙がった、実害は限定的だが将来負債になる項目。**#1・#2 は対応済み**（#1 DayStat fetch 失敗時の write スキップ、#2 `ModelContext.didSave` 購読で全ミューテーションから widget refresh 発火）。以下は繰り越し：
> - **#3 エラー握りつぶし＋テレメトリ皆無**（合意3ロール）: `WidgetSnapshotStore.write/read` の失敗が全経路で無言。App Group 誤設定・旧 JSON 残存などの本番障害が「ウィジェットが更新されない」としか観測できない。最低限の失敗ログ/カウンタを入れる。
> - **#4 RRULE 繰り返しの当日インスタンス非表示**（合意2ロール）: ウィジェット/日ビュー（DayAgendaView.dayTasks）は同日 startDate のみで `occurs(on:)` 未展開。WeekView だけ展開する既存の全体不整合を継承。**アプリ日ビューごと直すか容認かの方針判断が必要**。**P12（空きコマ提案）も同じ「今日のタスク」解決に依存するため、P12 着手前に方針決定すること**。**据え置き（2026-07-11 時点で方針未決定、P12 は既存の同日 startDate 判定のまま実装済み）**。
> - **#5 ウィジェット表示の不揃い＋アクセシビリティ**: ファミリ間で「空/古い/読めない」の区別が不揃い（systemSmall/Medium のみ「アプリで更新」）。`pin.fill` に accessibilityLabel 無し、Dynamic Type 非追従（固定10pt）、カテゴリがカード色のみでテキスト表現なし、`lineLimit(1)` で拡大時タイトル欠落。P9 のアクセシビリティ方針に合わせて補修。
> - **#6 systemSmall/Medium の約60行重複**: stat 表示の helper view 化で簡潔化。
> - **#7 平文個人情報のバックアップ露出**: 予定タイトル等が App Group に平文 JSON で保存され、NSFileProtection 未指定・iCloud/iTunes バックアップ対象・タスク削除時のパージ経路なし。「オフライン主義」との整合でファイル保護属性/削除方針を判断。
> - **#8 その他小**: upcoming 配列サイズ無上限（巨大 JSON でウィジェットのメモリ制約下デコード）、group ID の二重手管理（entitlements 2ファイル、片方更新漏れで無言失敗）、scenePhase active/background の並行 refresh 競合（atomic なので破損なし・鮮度が一時後退のみ）。

## Phase 12 — 空きコマ自動提案(W2) 〔Sim〕

今日バケツの浮遊タスクを、`duration`(実績 `actualDuration` で補正——P0/P4 から蓄積済み)を使って枠の空きに「締切が近い順→重い順」の貪欲法でフィット。提案チップは P1 の空きカード内に表示、ワンタップ採用。**勝手に確定しない**。ML なし、完全ローカル。

**受け入れ基準**: 収まる空きにだけ提案が出る。採用でタスクがスケジュールされる。

### P12 残タスク（debate-review 検出、別フェーズ回し）

Round 2 で合意した High/Medium/Low の未対応項目。Critical 3件（gap クランプ / snooze 除外 / scheduleAt での通知 reschedule + save エラー格上げ）は Phase 12 内で修正済み。

- [x] **`[Date: [SlotSuggestion]]` を `[[SlotSuggestion]]` に**: `gap.start` を辞書キーにしているため同一 start の複数 gap で後勝ち上書きが起きる。返り値を配列にして rows の gap を `enumerated()` で対応させる。実装済み（`FreeSlotSuggester.suggest` が `[[SlotSuggestion]]` を返す）。
- [x] **`duration=0` 実データ問題**: `AddTaskSheet` / `TodoListView.quickAdd` の浮遊タスクは `duration=0` が典型で、`effectiveDuration` fallback=1800秒に潰れ「重い順」が崩れる。**オーナー判断: 対処A（`duration=0` 候補を除外）で確定、実装済み**（`FreeSlotSuggester.suggest` の `validCandidates` フィルタ）。
- [Medium] **`gapSuggestions` の毎分再計算をキャッシュ**: `TimelineView(.everyMinute)` の中で `allTasks` 全走査 + `suggest` を無条件再実行している。`sunCache` / `travelData` と対称に、rows のシグネチャ変化検知で `@State` キャッシュ（~8行）。**未対応**。
- [x] **chip 表示の `allTasks.first(where:)` を Dictionary 化**: chip 個ずつ O(n) 走査＝O(n*k)。`body` 内で `tasksByID = Dictionary(uniqueKeysWithValues: ...)` を1行、`gapRow` に受け渡し。実装済み。
- [Low] **`SchedulePromoteSheet` の `@State startDate = .now` 陳腐化**: シート開いたまま数分経過→「決定」で過去時刻がコミットされる。ボタン押下時に再取得へ。**実装済み**（決定ボタン押下時に `max(startDate, .now)` へシフト）。
- [Low] **`FocusSession.actualDuration` の累積上限なし**: 長期繰り返しタスクで `effectiveDuration` が肥大化し優先チップを支配しうる。Phase 4 の記録側と合わせて別途検討。**未対応**。
- [x] **`SortPhase` を「締切近さ」の代理に使う設計**: 実 `dueDate` フィールドが無いため `.now`/`.today` を代理利用。将来 `.week` 拡張時は `phaseRank` の割り当てを見直す。コメント実装済み（`FreeSlotSuggester.swift` の `suggest` 直上）。

## Phase 13 — 週次締めの儀式(W3) 〔実機〕

日曜夜(設定可)に通知→確定キュー一掃→週報(DayStat / FocusSession / MonthMoneyStat から読むだけ、新規集計なし)→来週プレビュー。**締めの確定は明示ボタン**（ChopDetector 流用から変更。理由は下記残タスク参照）。小さな `WeekReview` 記録。共有は静止画エクスポートのみ。

**受け入れ基準**: 週報が一通り流れ、数字が各画面の値と一致する。

### P13 残タスク（debate-review 検出、別フェーズ回し）

Round 2 で合意した High/Medium/Low の未対応項目。Critical 4件（WeekReview 重複挿入防止 / 通知権限＆トグル連動 / BackupService への WeekReview 組み込み / fetch 失敗の可視化＋save 失敗時 dismiss 抑止）と既知 3件（save 失敗時 dismiss、scheduleWeeklyReview の os_log 統一、TaskItem.scheduleAt の @MainActor 対応）は Phase 13 内で修正済み。**以下の残タスクは 2026-07-11 の追加ワークで全て対応済み**。

- [x] **`WeekMath` と `WeekView` の週境界二重定義**: `WeekMath.firstWeekday(showSevenDays:)` を追加（7日=日曜起点/平日=月曜起点）。`WeekView.weekCalendar` を computed property化してこれを参照、`WeekReviewView.range`/`nextRange` も同じ helper 経由に統一。`WeekMath` は破棄せず、`weekStart`/`weekRange` に `firstWeekday` パラメータを追加（既定値2で既存呼び出し互換）。
- [x] **`doneCount` の基準を `approved` にする**: `WeekReportSource.doneCount` を `approvedCount` にリネームし、`status == .approved && approvedAt` の範囲判定に変更。
- [x] **「今週を締める」ボタンが `doneTasks` 空時に消える**: `ApprovalQueueView` の空状態（`ContentUnavailableView`）側にも同じボタンを toolbar に追加。
- [x] **通知タップ→WeekReviewView 自動遷移**: `NotificationDelegate`（`UNUserNotificationCenterDelegate` 実装）を追加、`weeklyReviewIdentifier` タップで `NotificationService.weeklyReviewTappedNotification` を発行。`ContentView` が `onReceive` で受けて `showWeekReview` を立てる。
- [x] **fetch 重複を `@State` キャッシュ**: `WeekReportSource.load(in:context:)` が `WeekReport`（focus/money/approvedCount）を1回で返す。`WeekReviewView` は `@State private var cachedReport` に載せて `reportSection`/`exportImage` で共有（`commitAndClose` は WeekReview 廃止により集計不要になったため参照しない）。
- [x] **`#Index` 不在**: `FocusSession.end`、`TaskItem.completedAt`/`startDate` に `#Index` を追加。
- [x] **`referenceDate` を `@State` 化**: `WeekReviewView.init(initialReferenceDate:onClose:)` で `@State` に固定。
- [x] **`exportImage` nil 時のフィードバック**: `renderer.uiImage` が nil の場合 `exportFailed` alert を表示。
- [x] **`moneyTotal` を新規集計にするか `MonthMoneyStat` 参照にするか**: **オーナー判断（2026-07-11）** — 都度計算のままで OK。週単位の按分ロジックを追加するコストに対してリターンが薄いため見送り。`WeekReportSource.moneyTotal` にコメントで明記。
- [x] **`WeekReview` の履歴閲覧画面 or モデル廃止**: **オーナー判断（2026-07-11）** — モデル廃止。閲覧 UI なし＋書き込み専用は不要のため、`WeekReview.swift` 削除、スキーマ登録から除去、`BackupService` の DTO/書き込み経路も削除。旧 `.str8` の `weekReviews` キーは `BackupPayload` が対応フィールドを持たないため JSONDecoder が無視して読み飛ぶ（互換維持）。**注**: スキーマから `@Model` を削除すると既存ライブストアとの互換が崩れるため、開発端末はシミュレータ再起動（ストア破棄）で対応すること（P6 メモ参照）。
- [x] `ShareSheet` ラッパを `ShareLink` に置換
- [x] `UserDefaults.register(defaults:)` で AppSettings の `??` フォールバックを削除（`str_8__ToDoApp.init()` で `AppSettingsKey.registerDefaults()` 実施。`CalendarSettingsView` 側の同パターンも合わせて簡素化）
- [x] `WeekReviewView.nextRange` の inline 計算を `WeekMath.weekRange` 再利用に
- [x] 両 `ToolbarItem` が `.primaryAction` になっている問題、エクスポート側を `.secondaryAction` に
- [x] 命名揺れ `doneCount` vs `completedCount` を `approvedCount` で統一
- [参考] ROADMAP の Phase 13 spec を実装に合わせて更新（本節冒頭で「明示ボタン」に反映済み。今後の実装変更に応じて更新継続）

## Phase 14 — ローカルP2P集中ルーム(W4) 〔実機2台+〕

`PeerRoomSession`（PeerSession とは別クラス、承認フロー無傷）を新設。2〜7人、ホストが時間設定、全員の faceDown が揃って開始（RTT/2 のクロックオフセット交換で同期）。途中離脱を検知して縮退。終了時に各端末が自身の `FocusSession` を保存（`roomID` / `participantCount` 付与）。フォアグラウンド限定（`.background` で退出）。

**受け入れ基準**: 2台が1秒未満のズレで同時開始。切断時に破綻せず縮退する。

### P14 残タスク（Wave3 レビューで検出・要オーナー判断も含む）

Wave1〜3 で以下は完了: FocusSession スキーマ拡張・BackupService 後方互換・FocusRoom 純粋モデル・p14-selfcheck 7 テスト・PeerRoomSession（送信者検証／unicast pong／`hostPeerID` once-only／`.leave` 送信者検証／`markEnded` 再入ガード）・roomID ホスト→ゲスト伝播・requestClockSync 自動発火・TimerView 二重稼働防止（`guard !showRoom`）・save 失敗 alert（Phase 13 教訓踏襲）・`.background` のみ判定・`hasFinished` フラグで二重 save 防止。

- [x] **統合テストの穴**: `p14-selfcheck` は `FocusRoom` 純粋関数と `RoomMessage` JSON 往復のみ。`markEnded` / `finishAndSave` / `PeerRoomSession.handle` の統合的な再入・二重呼びは未検証。軽量な統合チェック（onEnded 2 回発火で FocusSession が 1 件保存にとどまることの assert 等）を追加。実装済み（`p14-selfcheck` Test 8/9/10）。
- [x] **approverID の記録**: ROADMAP は「終了後は相互承認モードへ直結、approverID 記録」と明記だが、現状は FocusSession に approverID を格納しない（承認は既存 `ApprovalQueueView` の chop 承認に委ねる）。FocusSession に `approverID: String?` フィールド追加＋Wave3 の `finishAndSave` で peer.hostPeerID などを詰める設計判断が必要。実装済み（`FocusSession.approverID` + `PeerRoomSession.approverDisplayName`）。
- [x] **TOFU（Trust-On-First-Use）攻撃耐性**: `hostPeerID` の初回設定を初回のみに限定してあるが、メッシュトポロジー上、悪意ある peer が最初の `.hello` を騙る可能性は残る。`requestJoin(host:)` で選択した peer 由来で host を確定する強化が必要。実装済み（`requestJoin(host:)` でのみ `hostPeerID` を確定、`.hello` からは確定しない）。
- [x] **`.inactive` 継続監視**: 現状 `.inactive` を無視して `.background` のみで dismiss。長時間 `.inactive`（電話着信等）が続くケースを別途モニタして退出させる。実装済み（`inactiveWatchTask` で 10 秒監視）。
- [Medium] **クロック同期の実機検証**: p14-selfcheck の Test 6 は「対称ネットで RTT が真の片道と一致する」構成でオフセット誤差ゼロ。**非対称遅延の実機測定**（Wi-Fi 混雑時等）を実機 2 台で行い、1 秒未満の受け入れ基準を実証。**未対応（実機作業）**。
- [Medium/要判断] **`.inactive` を含む一時遷移中の退出方針**: 実機 2 台で権限ダイアログの挙動を観察してから最終判断。
- [Low] `discoveredHosts` の並び順を安定化（現状 append 順、UI で peer 名称でソートが望ましい）
- [Low] `HourglassMotionService` を FocusRoomView と TimerView で **別インスタンス** が生成される現状を、共有 service に統一（今は `guard !showRoom` で回避しているだけ）
- [参考] ROADMAP の Phase 14 spec を実装に合わせて更新済み（本節冒頭で「PeerRoomSession 新設」に反映）

### P14 debate-review 追加検出（Critical は修正済み）

Phase 14 完成後の debate-review（4 視点衝突）で追加検出。**Critical 4 件は Phase 14 内で修正済み**：Info.plist の `_str8-focusroom` 追加 / `.start` reject（`hasClockSynced` gate） / `isDeviceFaceDown` accessor + FocusRoomView 側で初期姿勢検出（共有 FSM は無傷） / `FocusSession.record()` 経由への一本化。以下は残タスク。

- [x] **`RoomMessage.hello` から `isHost` フラグ削除**: 現状は自己申告で複数人が isHost:true を名乗ることを participants 配列が防いでいない → UI 表示で「(ホスト)」がなりすまし可能。フラグを削除し、内部状態（`.startHosting()` を呼んだ側が host）で判定。実装済み（`RoomMessage.hello(participantID:)` に isHost 無し）。
- [x] **`participantID` を connectedPeer 実 ID に紐付け検証**: 詐称による架空参加者無制限注入で `participantCount` 改ざん・7 人上限誤誘発が可能。`.hello` 受信時に participantID と MCSession の実 peerID の対応を検証。実装済み（`.hello`/`.leave` は既存、`.faceDown` も 2026-07-11 に検証追加）。
- [x] **退出ボタン / scenePhase / save 失敗時の cleanup を一元化**: 現状 timer.invalidate/motion.stop/peer.stop の呼び忘れ経路が複数あり（安全性 #1/#7/extra 2）。defer 相当のヘルパで一元化。実装済み（`FocusRoomView.cleanup(reason:)` に集約、save 失敗経路も 2026-07-11 に追加）。
- [x] **`PeerRoomSession.end()` を実際に呼ぶ経路を実装**: 現状デッドコードで終了検知が 1Hz Timer の自己申告方式。ホスト側 Timer 満了で `broadcast(.end)`、全端末が受信時に `finishAndSave` → 1Hz ずれ解消。実装済み。
- [x] **受信レート制限**: `.leave` / `.hello` 高頻度連投で participants の連続 mutation → UI 遅延。デバウンス or 単位時間内の許容回数上限。実装済み、2026-07-11 に peer ごとの独立レート制限に強化（`helloTimestamps`/`leaveTimestamps` を `[String: [TimeInterval]]` 化）。
- [x] **満員判定と切断反映のシリアライズ**: `advertiser(_:didReceiveInvitation:)` と `session(_:peer:didChange:)` が nonisolated から独立 Task 生成 → MainActor 実行順が実イベント順と一致しない。単一シリアルキュー or MainActor 上での明示的順序管理。実装済み（`handlePeerStateChange`/`handleInvitation` を @MainActor に集約）。
- [x] **`ApprovalQueueView` への直行動線実装**: `endedSection` の「承認へ進みます」文言だけで実際の遷移が無い。sheet 閉じ後にタブ切替 or NavigationLink。ROADMAP の「終了後は相互承認モードへ直結」を満たすために必要。実装済み（`FocusRoomView.proceedToApprovalNotification` → `ContentView` がタブ切替）。
- [Medium/据え置き] **ホスト昇格 or 明示 abort UI**: ホストの一時 background で全ピアが `.aborted` 遷移 → 全滅（単一障害点）。残ピア最若をホスト昇格、または明示的「ホスト離脱、再開不能」表示。現状は `abortedSection` の明示メッセージのみ。ホスト昇格は据え置き。
- [Medium/据え置き] **複数サンプル ping-pong + 再送タイムアウト**: 現状は 1 発 RTT/2 で外れ値除去なし、輻輳時の悪サンプルがセッション全体を狂わせる。3-5 サンプル中央値 + 200ms 再送タイムアウト。据え置き。
- [Medium/据え置き] **`PeerSession` との接続層抽出**: `PeerRoomSession` は `PeerSession` を逐語コピーしている箇所が多い（MCSession 生成・delegate 配線・encoder/decoder）。共通 protocol / helper で集約。据え置き。
- [Low] `runningSection` の時刻フォーマット（`Int(remain/60)` + `String(format:...)`）を既存 `Formatting.swift` の helper に集約
- [Low] `FocusRoomView.setupCallbacks` を onAppear inline に（分離不要）
- [Low] `Participant.id: String`（MCPeerID.displayName）vs 他モデルの `id: UUID` の型混在整理
- [Low] `onStartScheduled` が host `announceStartIfReady` とゲスト `.start` 受信の両経路から発火。単一経路化 or 2 重発火防止 assert
- [参考] `p4-selfcheck.swift` は現状 TaskItem/NotificationService 依存でビルド不能（Sonnet 実測）。既存インフラの技術的負債、HourglassStateMachine 回帰防止網が機能していない。Phase 14 スコープ外だが要対処。

---

## Phase 15 — WH 7分類データモデル+概要タイル/フォーカス編集シート（E0+E1）〔Sim〕

企画書「イベント作成シート（2026-07-07 新設）」E0+E1 統合。既存 `AddTaskSheet.swift` の項目連続 Form を 7 分類のタイル＋フォーカス編集画面へ置き換える。連続テキスト行の情報過多を、視覚的操作（タイル・チップ・時刻バー）で解消する。

1. **WHCategory enum**: `what/when/where_/which/who/how/other` の 7 分類。`label` 計算プロパティで日本語ラベル。
2. **Profile @Model**（which）: `id: UUID / name: String / iconName: String`。会社/個人などの文脈タグ。スキーマ登録に追加。
3. **PhraseAlias @Model**（辞書。Phase 16/17 と共有）: `id / keyword / whCategory / replacement / isBuiltIn / isEnabled`。Phase 15 ではモデルだけ用意（UI は Phase 17）。
4. **TaskItem 拡張**: `profile: Profile?`（which）と `participantNames: [String] = []`（who、CNContactPicker 選択のみ、連携なし）を加算的に追加。
5. **`EventComposerView`（新規、AddTaskSheet 置き換え）**: 
   - タイトルは常時表示の固定入力欄（what）。
   - 残り 6 分類（when/where/which/who/how/other）を 2 列グリッドのアイコン付きタイルで表示、プレビュー付き（未設定は淡色）。
   - タイルタップで該当トピックのフォーカス編集画面へ。フォーカス内は他タイルへの直接ジャンプアイコン列を上部常設。
   - when は時間帯バー、where はサムネ＋最近使った場所チップ、who はイニシャル丸、which はカテゴリ/プロフィール併記チップ。
6. **既存呼び出し側の切替**: `TodoListView.quickAdd`（クイック追加は Phase 16 で改修、Phase 15 はまず「詳細を追加」経由）、`DayAgendaView` 空きカードタップ、`CalendarSettingsView` 等の `AddTaskSheet` 呼び出しを `EventComposerView` に差し替え。**旧 `AddTaskSheet.swift` は削除**（1 タイミングで置換、両立させない）。

**受け入れ基準**: タイル 7 枚（タイトル固定 + 6 タイル）が表示される。タップでフォーカス編集に遷移、他タイルへ横移動できる。when で時間帯バー・where でチップ・which でチップが選べる。既存の全 CRUD（新規作成・詳細編集導線）が回帰なしで動く。xcodebuild build 通過。

---

## Phase 16 — 自然文クイック追加パーサ（E2）〔Sim〕

企画書 E2。タイトル欄を「自然文 1 行入力」に置き換え、日時・場所・カテゴリ・所要時間を自動認識してチップ化。ML なし、完全ローカル。

1. **`PhraseParser.swift`（新規、純関数）**: 
   - ①自前の日時・相対日付の正規表現層（明日/来週/14:00 など）
   - ②`NLTokenizer` で残りを分かち書き
   - ③各トークンを `PhraseAlias`（isEnabled）と照合、ヒットしたら `replacement` を元の文に埋め戻して①からパース（再帰は 2 段まで）
   - ④どれにも当たらない単語はタイトルの残りとして保持（情報を握りつぶさない）
2. **クイック追加 UI**（`EventComposerView` のクイック追加モード or `TodoListView` の quickAdd 差し替え）:
   - ①入力フィールド ②自動認識フィールド（パース済みチップ） ③サジェストフィールド（未認識ワードの辞書登録候補、`AppSettings.enableDictionarySuggestions` で ON/OFF）④「詳細を追加」ボタン（パース結果でプリフィルした `EventComposerView` を開く）
3. **`AppSettings.enableDictionarySuggestions: Bool = true`** 追加。設定画面に ON/OFF トグル。
4. **オンデバイス LLM 不採用**の判断コメント: `PhraseParser.swift` のヘッダに「iOS26 Foundation Models framework は不採用（対応端末限定を避けるため）」を明記。

**受け入れ基準**: 「明日 14:00 大学図書館でレポート」入力で 日時/場所/タイトル が正しくチップ化。「詳細を追加」でプリフィルされた EventComposerView が開く。認識できない語はタイトル残りに保持。xcodebuild build 通過。

---

## Phase 17 — 辞書管理画面（E3）〔Sim〕

企画書 E3。認識精度の天井を「ユーザーが埋められる」仕組みにする。

1. **`DictionarySettingsView`（新規、`CalendarSettingsView` から遷移）**:
   - 既定表現（`isBuiltIn=true`）は ON/OFF のみ可能（削除不可）
   - ユーザー登録分は追加/編集/削除可能
   - カテゴリ/場所の別名もこの画面から追加（既存 `Category`/`PlaceTag` 名にチップで別名を紐付け、内部的には `PhraseAlias` として保存）
2. **サジェスト機能の受け口**: Phase 16 のサジェストフィールドでタップした未認識ワードを、この画面の「登録待ち」セクションに一時保存 → 分類選んで確定
3. **既定表現のシード**: 初回起動時に `PhraseAlias(isBuiltIn=true)` を挿入（例: "ポモ" → "25 分"、"今日" → 相対日付、"大学" → "大学図書館" 等）。シード集は最小限（10-20 件）
4. **`AppSettings.enableDictionarySuggestions`** の設定 UI もこの画面に配置

**受け入れ基準**: 既定表現の ON/OFF が効く。ユーザー登録分の CRUD が完動。カテゴリ別名を登録すると Phase 16 のパーサが認識する。xcodebuild build 通過。

---

## Phase 18 — 既存タスク編集の直接ジャンプ導線（E4）〔Sim〕

企画書 E4。既存タスクの編集は、概要タイルを介さず 1 トピックへ直行できるようにする。「サクッと直したい編集」と「新規のじっくり整理」を別哲学として扱う。

1. **`TaskDetailView` の再構成**: 
   - 現状の全フィールド表示専用を、各フィールド（title/when/where/who/which/how/other）の右にペン型アイコンボタンを配置。タップで `EventComposerView` の該当トピックだけをフォーカス画面で開く（他タイルへの横移動は Phase 15 と共通）
   - 削除ボタンは既存維持
2. **編集時の recompute**: 金額（how）の編集で `MoneyStats.recompute(for: task)` を呼ぶ（P8 debate-review 繰り越しで「編集時 recompute は将来のタスク編集機能と同時に」と保留していた項目の解消）
3. **通知の再スケジュール**: when の編集で `NotificationService.reschedule(for: task)` を呼ぶ
4. **仕分けデッキ・空きカード等の遷移経路の整合**: 全ての「編集」導線を新 API に統一

**受け入れ基準**: TaskDetail から 1 トピックだけを直接開いて編集できる。金額編集で MonthMoneyStat が更新される。when 編集で通知が再スケジュールされる。既存の他フローに回帰なし。xcodebuild build 通過。

---

## ファイル別 流用/改修/作り直しマップ

パスは `str(8) ToDo/` 配下。

**そのまま流用**: `EventKitService.swift`(仕様一致)、`MonthGrid`+`DayBlock`(MorphCalendar.swift 内)、`Color+Hex.swift`、`NotificationService.swift`、`CategoryPickerView.swift`、`LocationPickerView.swift`

**改修(フェーズ)**:
| ファイル | フェーズ |
|---|---|
| `Enums.swift` / `TaskItem.swift` | P0(ステータス・フィールド追加) |
| `SupportingModels.swift` | P0(FixedSchedule 削除、DayStat 維持) |
| `str_8__ToDoApp.swift` | P0/P4/P7/P8/P10 スキーマ登録、P11 ストア位置 |
| `PreviewData.swift` | 毎フェーズ |
| `ContentView.swift` | P3/P4/P5/P10 で ComingSoonView を実タブに差し替え |
| `MorphCalendar.swift`(CalendarRootView) | P0 ピンチ削除、P2 Morph チューニング |
| `TaskDetailView.swift` | P0 ステータス UI、P8 お金 |
| `AddTaskSheet.swift` | P1 空きプレフィル、P8 お金 |
| `YearView.swift` | P0 enum、P5 未確定表示、P9 DayStat 化+ヒートマップ部品化 |
| `CalendarSettingsView.swift` | P2 枠エディタ、P7 天気、P9 磨き込み |
| `AppSettings.swift` | P2(WeekBand/makeWeekBands/hhmm 削除) |
| `WeatherProvider.swift` | P7(キャッシュ+鮮度) |

**作り直し**: `DayView.swift` → カード式アジェンダ(P1、`DayTaskBlock` は廃棄)、`WeekView.swift` → 枠グリッド+キャプセル(P2、スクロール骨格とヘッダは概ね残る)

**新規(主要)**: `BandModels.swift`(P0)、`TaskCardView.swift`+`DayAgendaView.swift`(P1)、`CapsuleOverlay.swift`(P2)、`TodoListView.swift`+`SortDeckView.swift`(P3)、`HourglassMotion.swift`+`TimerView.swift`+`AlarmService.swift`+FocusSession(P4)、`ChopDetector.swift`+`ApprovalQueueView.swift`+`PeerSession.swift`+`ProximityGate.swift`(P5)、`BackupService.swift`(P6)、WeatherCache+`SunCalc.swift`+`DepartureService.swift`(P7)、MonthMoneyStat+内訳シート(P8)、Subject+Study Hub ビュー(P10)、Widget Extension ターゲット(P11)

---

## リスク検証(スパイク)の配置

1. **横断キャプセル×可変行高グリッド**(企画書「最優先検証」)→ P2 タスク1。依存(永続 Band)が揃う最速のスロット。さらに早めたければ P0 直後にハードコード枠で実施可(P1 不要)。
2. **砂時計ジェスチャーのステートマシン** → P4 タスク1(実機 HUD スパイク、数値合格基準付き)。
3. **Morph 品質** → P1 で安定 ID を維持して保護、P2 タスク5 の受け入れ基準で明示的にゲート。
4. **chop+近接ゲート** → P5 タスク1/4 を独立した実機スパイクに。
5. **所要時間の記録**(W2 前提)→ フィールドは P0、書き込みは P4。P12 までに数ヶ月分蓄積。

---

## フェーズ前オーナー決定チェックポイント

各フェーズ着手前に確認。**未確認ならリーン既定値で進めて `ponytail:` コメントを残す。**

| # | いつまでに | 論点 | リーン既定値 |
|---|---|---|---|
| 1 | P0/P3 前 | SortPhase の形(現 enum は 今すぐ/今日/今週/いつか、新仕様は 今日/いつか+先送り日付) | enum 維持、今週/いつかは「いつか」セクションに統合、先送りは snoozeUntil 日付で表現 |
| 2 | P1 前 | 日アジェンダに「今日バケツの浮遊タスク」を出すか | 出さない(リストが持つ)。空きカード経由で配置したものだけ表示 |
| 3 | P1 前 | 空きカードの操作 | タップ→プレフィル済み AddTaskSheet(リストからのドラッグは後回し) |
| 4 | P1 前 | done カードの扱い | 打ち消し線で残す(リストと違い、日の記録として見えていてよい) |
| 5 | P2 前 | ルーティーンの枠スナップ判定 | 開始時刻の包含判定(TaskItem に bandID は持たせない) |
| 6 | P2 前 | 行高の「情報量基準」の式 | 行内最大チップ数でクランプ(最小/最大高さ付き) |
| 7 | P4 前 | セッション中に起こした(faceUp に戻した)場合 | 一時停止(再度伏せて再開、長押しでキャンセル) |
| 8 | P5 前 | ペア承認は翌日ロックをバイパスするか / approverID の中身 | バイパスする(他人承認は即確定) / デバイス名 |
| 9 | P8 前 | 集計は予定額か approved のみか / 通貨 | 予定額(記録した瞬間に計上) / JPY 固定 |
| 10 | P9 前 | カテゴリ積み上げバーのデータ源 | タスクから集計のまま(遅ければ DayStat にカテゴリ内訳を追加) |
| 11 | P10 前 | 勉強ストリークの定義 | その日に1セッションでもあれば継続(目標達成基準は S2 で切替可能に) |
| 12 | P11 前 | ウィジェットの優先ファミリ | ロック画面インライン(次の予定/出発)から |
| 13 | P2 前 | EventKit 取り込みイベントを時刻厳守(isTimePinned)扱いにするか(P1 レビューで発覚: 現状は常に false でキャプセル対象外) | 全て true(カレンダー由来の予定は時刻固定が実態に近い) |
| 14 | P3 前 | 保存時の時間帯重複の警告の要否(P1 レビュー指摘) | 警告なしのまま(並行タスクは正当な使い方。ドッグフーディングで実害が出たら検討) |
| 15 | P3 前 | ルーティーン(RRULE)の occurrence 単位の完了状態モデル(P2 レビューで発覚: 現状は1タスク=1 status で全出現に打ち消し線が付く。日ビューへの RRULE 展開・週⇄日 Morph の非対称もこの決定に従属) | 未定(P3 着手前に要決定。候補: 出現日ごとの完了記録テーブル / lastDoneDay 方式) |

---

## 企画書との対応確認

- 5本柱: カレンダー(P0〜2,7〜9)/タイマー(P4)/仕分け(P3)/承認(P5)/リスト(P3) ✅
- 追加①リスト(P3)・②集中stats(P4+P10)・③Study Hub(P10) ✅
- お金(P8)、第2弾 W0(P6)/W1(P11)/W2(P12)/W3(P13)/W4(P14) ✅
- イベント作成シート（2026-07-07 新設）: E0+E1(P15)/E2(P16)/E3(P17)/E4(P18) ✅ Phase 15〜18 として組込済
- 企画書明示の優先事項: 横断キャプセル最優先検証(P2-1)/W0前倒し(P6)/actualDuration 早期記録(P0+P4) ✅
- 旧仕様残存の解消: 24hタイムライン(P1)/ピンチ(P0)/pending(P0)/FixedSchedule・Band不在(P0)/チップ式週セル・キャプセル不在(P2)/お金不在(P8)/Morphクロスフェード(P2)/YearViewのDayStat未使用(P9)/天気キャッシュ不在(P7)/4タブプレースホルダ(P3,4,5,10)/仕分けUI不在(P3) ✅
