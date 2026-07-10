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

> **P8 実装後の改訂(2026-07-10、debate-review の結果)**: TaskDetailView は全フィールド表示専用の既存設計のため、金額の**編集**は将来のタスク編集機能と同時に実装する(その際 `MoneyStats.recompute` の呼び出しを忘れないこと)。recompute は現状「保存/削除時に該当1ヶ月+月ビュー表示時の自己修復」— P13(週報)は MonthMoneyStat を直接読むため、**P13 着手前に** 反復タスク変更時の複数月再計算へ発火戦略を見直す。タイムゾーン変更で月キー(Date)が重複しうる既知の天井あり(クラッシュせず表示が古くなるのみ)→同時に固定カレンダーの月キー化を検討。

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

---

## Phase 11 — ウィジェット+StandBy(W1) 〔実機/Sim〕

App Group 追加、SwiftData ストアをグループコンテナへ移動(起動時に一度だけコピー)。Widget Extension(次のカード/今日の枠と達成数/未確定件数)、ロック画面各種+StandBy ファミリ。予定の境界時刻にタイムラインエントリを事前生成。

**受け入れ基準**: データ変更後のタイムラインリロードでウィジェットに反映される。

## Phase 12 — 空きコマ自動提案(W2) 〔Sim〕

今日バケツの浮遊タスクを、`duration`(実績 `actualDuration` で補正——P0/P4 から蓄積済み)を使って枠の空きに「締切が近い順→重い順」の貪欲法でフィット。提案チップは P1 の空きカード内に表示、ワンタップ採用。**勝手に確定しない**。ML なし、完全ローカル。

**受け入れ基準**: 収まる空きにだけ提案が出る。採用でタスクがスケジュールされる。

## Phase 13 — 週次締めの儀式(W3) 〔実機〕

日曜夜(設定可)に通知→確定キュー一掃→週報(DayStat / FocusSession / MonthMoneyStat から読むだけ、新規集計なし)→来週プレビュー。締めの確定は ChopDetector 流用。小さな `WeekReview` 記録。共有は静止画エクスポートのみ。

**受け入れ基準**: 週報が一通り流れ、数字が各画面の値と一致する。

## Phase 14 — ローカルP2P集中ルーム(W4) 〔実機2台+〕

PeerSession(P5)流用。2〜7人、ホストが時間設定、全員の faceDown が揃って開始(クロックオフセット交換で同期)。途中離脱の表示。終了後は相互承認モードへ直結(approverID 記録)。FocusSession に roomID / participantCount 追加。フォアグラウンド限定。

**受け入れ基準**: 2台が1秒未満のズレで同時開始。切断時に破綻せず縮退する。

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
- 企画書明示の優先事項: 横断キャプセル最優先検証(P2-1)/W0前倒し(P6)/actualDuration 早期記録(P0+P4) ✅
- 旧仕様残存の解消: 24hタイムライン(P1)/ピンチ(P0)/pending(P0)/FixedSchedule・Band不在(P0)/チップ式週セル・キャプセル不在(P2)/お金不在(P8)/Morphクロスフェード(P2)/YearViewのDayStat未使用(P9)/天気キャッシュ不在(P7)/4タブプレースホルダ(P3,4,5,10)/仕分けUI不在(P3) ✅
