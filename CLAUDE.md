# プロジェクトルール（英単語パズルトレーナー）

このファイルは、Claude Codeがこのプロジェクトで作業する際に毎回参照する
ルールブックです。ここに書かれた決定事項は、特に指示がない限り変更しないでください。

## アプリ概要

- アプリ名（仮）：英単語パズルトレーナー
- コンセプト：接頭辞・語幹・接尾辞のジグソーパズルを組み合わせて英単語を完成させる学習アプリ
- 対象ユーザー：小学生〜中高生、英語初級〜中級者（英検3級〜2級程度）
- 詳細な仕様は `英単語パズルトレーナー_アプリ設計書(統合版).docx` を参照すること

## 技術スタック（決定事項）

- フレームワーク：**Flutter**（Dart言語）
- 第一弾：スマートフォンアプリ（iOS/Android）。将来的にFlutter Webでブラウザ版も展開予定
- ドラッグ＆ドロップ：Flutter標準の `Draggable` / `DragTarget` ウィジェットを使用
- Web版は**GitHub Pages**で公開している（2026年時点の決定）。`production`ブランチへの
  pushのたびに、GitHub Actions（`.github/workflows/deploy.yml`）が`flutter build web
  --release --base-href /eitango-puzzle-trainer/`でビルドし、自動デプロイする。公開URLは
  `https://teamtanaka7812.github.io/eitango-puzzle-trainer/`。（`main`ではなく
  `production`がトリガーになっている経緯は下記「Gitブランチ運用」を参照）
- 効果音・読み上げはWeb版のみ実装済み（2026年時点の決定）。`lib/services/sound_service.dart`
  が、条件付きエクスポート（`if (dart.library.js_interop)`）でWeb向け実装
  （`sound_service_web.dart`、Web Audio APIでファンファーレ・ブザー音をその場で合成、
  音声ファイルは使わない）と、それ以外向けの何もしないスタブ（`sound_service_stub.dart`）を
  切り替える。結果画面で、正解／不正解時にそれぞれの音を鳴らし、単語・例文をタップすると
  Web Speech API（`speechSynthesis`）で英語読み上げする（`_SpeakableText`、
  `lib/screens/result_screen.dart`）。スマホアプリ版（iOS/Android）をビルドしても
  コンパイルは壊れず、単に音が出ないだけになる。

## データ設計（決定事項）

- 出題英単語データ：アプリ本体に同梱（JSON形式、`assets/data/words.json`）。最大2,000語想定、初期は100語
- 学習履歴データ（進捗・正答率・反復学習の状態）：端末内ローカルDB（`sqflite`等）に保存
- サーバーは自前で構築しない。クラウド連携は端末OS標準のバックアップ機能
  （iCloud / Googleバックアップ）に任せる。ただし2026年時点で、アンケート・研究用の
  学習データ収集のためFirebase（Firestore）を導入した（下記「参加者ID・データ収集」
  参照）。これは「自前のサーバーを構築しない」方針とは別枠の、外部マネージドサービス
  としての利用。
- 音声再生：基本は端末OS標準のTTS。音声ファイルの同梱は主要単語のみ（詳細未定）
- `words.json`の全問題は`choices`（`{text, image}`の配列）を持つ
  （`PuzzleWord.presetChoices`、`lib/models/puzzle_word.dart`）。そこに列挙された選択肢
  （テキスト・使用画像とも）をそのまま使い、「おとりをランダム抽選」「画像を
  ランダム割り当て」は行わない（表示順のシャッフルのみ行う）。全参加者が同じ
  刺激（形・色・文字）を見るようにするため。以前あった`choices`なしの問題向けの
  ランダム生成（`kAffixPool`・`kBasicPieceAssets`・`_buildOptionsProcedurally()`）は
  2026年10月に削除した。選択肢の数は「正解2〜3個＋おとり3〜4個」。
  正解ピースの判定は、`parts`（接頭辞・語幹・接尾辞を空欄を除いてこの順につなげたもの）
  のテキストと一致する`choices`要素を正解として扱う。
- Level 1の先頭10問（`illegal`〜`undependable`）は、以前手作業で作成されていた
  JavaScript版の問題データ（`window.q_list`）を移植したもの。**単語・正解（`parts`）・
  意味・例文などのデータ内容は変更しない**が、ピース画像の描き方は他の49問と
  統一した（2026年10月、ピース同士のつながりを改善するための決定。以前は「この10問の
  画像セットは変更しない」としていたが、これを撤回した。変更したのは画像・描画方式
  のみで、単語・正解・判定ロジックは変えていない）。旧画像セット（`02008green.png`
  等の28枚）は廃止し、`assets/puzzle_pieces_v2/`ごと削除した。
- 出題数は2026年時点で合計**59問**（Level 1: 19問、Level 2: 27問、Level 3: 13問）。
  上記の先頭10問はそのまま維持し、そこに49問を新規追加した
  （Level 1 +9、Level 2 +27、Level 3 +13）。追加元データは
  `assets/data/new_words_49.json`に残している（ピースの役割＝前置/語幹/後置の
  注釈`q_Prefixes`/`q_Stem`/`q_Suffix`を持つため、画像の割り当てにも使う）。
  - この拡張に伴い、以前Level 1に含まれていた4問（unhappy/rewrite/helpful/careless）は
    意図的に削除し、9つの新しい単語（admire/adventure/address/minute/adjust/achieve/
    capital/escape/accept）に置き換えた。
  - 以前は`illegal`・`development`・`uncomfortable`がLevel 3にも重複して存在し、
    Level 1側のIDには`_l1`を付けて区別していたが、この拡張に伴いLevel 3側の重複は
    意図的に削除した（2026年時点の決定）。現在はLevel 1側（`_l1`付きID）にのみ存在する。
- **3ピース→2ピース統合**（2026年9月、ユーザーからの指示）：3ピース
  （接頭辞＋語幹＋接尾辞）の単語のうち、以下2つの問題を抱えていた13問について、
  ピースを2つに統合した（正解の単語自体は変更していない。ピースの区切り方のみ変更）。
  - **複数正解問題**：2ピースの組み合わせだけで、それ自体が実在する別の英単語に
    見えてしまう（例：`unbelievable` = un+believe+able のうち、believe+ableだけで
    「believable」という完成した単語に見える）。
  - **綴り変化問題**：3ピースをそのまま連結した文字列が、正しい綴りと一致しない
    （例：believe+ableを連結すると"believeable"になり、正しい"unbelievable"と
    不一致）。
  - 対象13語とその新しいピース分割：`unfortunately`(unfortunate+ly)、
    `reappearance`(reappear+ance)、`independently`(independent+ly)、
    `reconsideration`(reconsider+ation)、`unbelievable`(un+believable)、
    `uncomfortable`(un+comfortable)、`disagreement`(disagree+ment)、
    `undependable`(un+dependable)、`adventure`(ad+venture)、`accurate`(ac+curate)、
    `unacceptable`(un+acceptable)、`exception`(except+ion)、`defensively`
    (defensive+ly)。統合後のピースの綴りは、連結すると`word`と完全一致することを
    確認済み（単純な文字列結合ではなく、正しい英単語の綴りをそのまま使っている。
    例：believe+ableではなく"believable"）。
  - この13問は、ピースの区切り方が変わったことに伴い、正解・おとりとも画像を
    作り直した（2026年10月に全問題の画像を新しい役割つきのピース画像へ
    割り当て直したため、現在の画像名は下記「素材について」の方式による）。
  - おとりピースは「正解＋3〜4個」に統一した。統合前に5〜6個あった6問
    （`unfortunately`・`independently`・`reconsideration`・`unbelievable`・
    `uncomfortable`・`undependable`）は、正解の判定に影響しない範囲でおとりを
    3〜4個に絞り込んだ（ユーザーの指示により、どれを残すかはClaude Codeの裁量）。
  - **今後、新しい単語をデータに追加する際の注意点**：3ピース（接頭辞＋語幹＋接尾辞）
    の単語を追加するときは、(1) 2ピースだけの組み合わせが別の実在単語に見えないか、
    (2) 3ピースをそのまま連結した文字列が正しい綴りと一致するか（`unbelievable`の
    ような綴り変化・二重母音の省略などに注意）、の2点を確認すること。問題があれば、
    上記のように2ピースへの統合を検討する。
  - この統合作業に伴い、`test/uncomfortable_word_test.dart`（3ピース単語の回帰
    テスト）が使っていた`uncomfortable`も2ピースになったため、同じく3ピースの
    ままの単語`advocate`に差し替えた。`test/level_play_screen_test.dart`の
    Level 1単語リスト（ハードコード）も新しいピース分割に合わせて更新した。

## 参加者ID・データ収集（決定事項）

- アンケート・研究用に学習データを収集するため、Firebaseプロジェクト
  `eitango-puzzle-trainer`のFirestore（Standardエディション、本番環境モード、
  asia-northeast1、データベースID `(default)`）に接続している（2026年時点の決定）。
  接続情報は`lib/firebase_options.dart`に直書きしている（この開発環境にFlutterFire
  CLIが入っていないため、`flutterfire configure`の自動生成ではなく手作業で用意した）。
  現時点ではWeb版のみ対応（`main.dart`で`kIsWeb`のときだけ`Firebase.initializeApp()`
  する）。
- アプリを初めて開いたとき、参加者ID（アンケートで割り振られた番号など）の入力を求める
  （`lib/screens/participant_id_screen.dart`）。入力されたIDは端末内
  （`shared_preferences`、`lib/services/participant_service.dart`）に保存し、次回以降は
  この画面を出さずそのままホーム画面へ進む（起動時の分岐は`main.dart`の
  `_StartupGate`が担う）。ホーム画面右上の歯車アイコンから、参加者IDの確認・変更が
  できる簡易設定画面（`lib/screens/settings_screen.dart`）を開ける。
- **匿名認証**（Firebase Anonymous Authentication、`lib/services/auth_service.dart`）を
  アプリ起動時に裏側で自動実行する（画面には一切出ない）。発行されたUID
  （`AuthService.currentUid`）は、ログイン機能なしで「本人の記録だけ」を区別するための
  識別子として使う。ブラウザに認証状態が保存されるため、2回目以降の起動では同じUIDが
  再利用される（毎回新しいUIDが発行されるわけではない）。
  - **Firebaseコンソール側で「匿名」サインインプロバイダを有効化する必要がある**
    （Authentication → ログイン方法 → 匿名 → 有効にして保存）。無効のままだと
    `signInAnonymously()`が`ADMIN_ONLY_OPERATION`エラーで失敗する（`AuthService`は
    この失敗を握りつぶすので、アプリ自体は起動するが学習記録は送信されなくなる）。
- 「Answer!」で正誤判定が行われるたびに、`participants/{参加者ID}/attempts/{記録ID}`に
  1件記録を書き込む（`lib/services/learning_record_service.dart`）。内容：
  `word`（単語）、`level`、`isCorrect`、`answeredAt`（`FieldValue.serverTimestamp()`）、
  `ownerUid`（匿名認証UID）。**この書き込みは「できれば行う」程度の扱い**：
  `game_screen.dart`の`_onAnswerPressed()`から`await`せずに呼び出し、内部の例外も
  すべて握りつぶす。通信状況やFirestore側の不調に関わらず、正誤判定・画面遷移という
  ゲーム本体の動作を止めたり遅らせたりしないことを優先している。
  - 2026年9月、試用者の取り組み方をより詳しく分析できるよう、以下の3項目を追加した
    （ユーザーからの指示）。**Firestoreに送る記録にのみ含め、端末内
    （`shared_preferences`）の保存方式は変更していない**（HISTORY画面用の集計値のみ
    という従来の設計を維持する、というユーザーの判断）。
    - `startedAt`：その問題の画面が表示され始めた日時。`GameScreen`は新しい問題に
      進む・再挑戦するたびに`LevelPlayScreen`側で新しいインスタンスとして作り直される
      （`key`にインデックス・挑戦回数を含めている）ため、`GameScreen.initState()`が
      呼ばれた時点を「開始時刻」として扱う（`_startedAt`、端末の時計。過去の一時点を
      記録するため`FieldValue.serverTimestamp()`ではなく`Timestamp.fromDate()`を使う）。
    - `durationSeconds`：`startedAt`から、「Answer!」を押して正誤判定されるまでの
      経過時間（秒）。
    - `dragCount`：その問題を解いている間に、ピースをドラッグしてどこかに離した回数。
      解答欄への設置・盤面内での置き直し・トレイへの取り出しのいずれであっても
      1回として数える（`Draggable.onDragEnd`は結果によらず必ず1回呼ばれるため、
      これをトレイ側・解答欄側どちらのピースの`Draggable`にも付けてカウントしている。
      `_SlotTarget`には`onDragCompleted`コールバックを追加し、`_GameScreenState`の
      `_dragCount`に集約している）。
    - 2026年9月、実機でLevel 1を1問解いて確認済み（`startedAt`〜`answeredAt`の差が
      `durationSeconds`とほぼ一致し、`dragCount`も操作回数と一致する整数値であることを、
      Firebaseコンソールで確認した）。
- **セキュリティルール**（`firestore.rules`、Firebaseコンソールの
  Firestore Database → ルール タブに貼り付けて反映済み）：送信・保存されているデータの
  `ownerUid`が、リクエスト元本人の匿名認証UIDと一致する場合のみ、書き込み（作成）・
  読み取りを許可する。更新・削除は常に不可（記録は書いたら変更しない前提）。
  それ以外のパスは念のためすべて拒否している。2026年9月に、REST API経由で
  「本人の書き込み／読み取りは成功」「他人になりすました書き込みは403」
  「他人の記録の読み取りは403」「未認証での読み取りは403」の4パターンを実際に
  確認済み。
  - なお、ログイン機能を持たないため「本当にその参加者ID本人からの書き込みか」を
    完全には検証できない（誰かが他人の参加者IDと自分のownerUidを組み合わせて
    書き込むこと自体は技術的に可能）。アンケート・研究用途の簡易的な仕組みとして
    割り切っている。
- **HISTORY画面**（`lib/screens/history_screen.dart`、ホーム画面の「HISTORY」から
  遷移）は、**端末内（`shared_preferences`）の集計値を主なデータ源とする**
  （`lib/services/local_history_service.dart`）。Firestoreには送信するが読み取りには
  使わない。理由：このアプリは「ネットワークが不安定でもゲーム自体は問題なく遊べる」
  設計を重視しており、HISTORY画面もオフラインで正しく表示できるようにするため
  （2026年9月時点の決定、ユーザーからの指示）。レベルごとの解答数・正解数のみを
  カウンターとして保持し（1件ずつの解答履歴は保存しない）、正誤判定のたびに加算する。

## ゲームロジック（決定事項）

- 出題方式：英単語を「接頭辞・語幹・接尾辞」の3ピースに分解し、ジグソーパズルとして出題する
  （例：combination → com + bina + tion）
- 語順並べ替え方式は不採用
- パズルピースは色分けし、ピース同士が直接つながるデザインを採用する（透明度は15%程度が候補、要調整）
- 正解時：「Correct!」＋「Good job!」等の励ましメッセージ、単語の意味・例文を表示
- 不正解時：「Incorrect!」＋「Keep going!」等の前向きなメッセージ、単語の意味・例文を表示
- 問題に1問正解するごとに背景の風景パズルが少しずつ完成し、全問正解で背景が完成する演出を入れる
- 解答欄（スロット）の枠数は、**その単語の正解ピース数と同じ**（2ピースなら2枠、
  3ピースなら3枠。`parts.length`、2026年10月の方針変更）。以前は初期開発時の決定で
  常に3枠固定にしていた（余った枠に何か置いたら不正解扱い）が、これを撤回した。
  正誤判定は「各枠に正解のピースが正しい順で入っているか」のままで、判定ロジックは
  変えていない。空欄が連続している区間では、枠の数が分かるよう枠の境目に仕切り線を引く。
  ドラッグ中のピースが近づいた空欄の枠は、濃いオレンジの塗り＋太い縁取り＋外側の光
  （`kDropHighlightColor`ほか、`game_screen.dart`）でハイライトする。ピースが置かれ済みの
  枠に近づけたときは、そのピースにオレンジを濃く重ねる（`puzzle_piece_shape.dart`）。
- 選択肢のピースには、正解のピースに加えて**「おとり」ピースを3〜4個**混ぜて出題する。
  おとりは問題データ（`words.json`の`choices`）で固定されている（実行時に抽選しない）。
  ピースの色・形は**役割**（前置＝赤、語幹＝緑または黄、後置＝水色）で決まり、
  「表示順」や「正解かおとりか」では決まらない。ピースの形が答えのヒントに
  ならないよう、おとりにも役割を均等に割り当てている（下記「素材について」の
  割り当て規則）。

## 画面構成

- ホーム画面：START / HISTORY / WORD BOOK / ENCYCLOPEDIA ＋ 案内役の羊キャラクター。
  右上の歯車アイコンから設定画面（参加者IDの確認・変更）へ
- レベル選択画面：Level 1 / Level 2 / Level 3
- ゲーム画面：パズル操作、「?」（ヒント）／「Answer!」／「Menu」ボタン
- HISTORY画面（`lib/screens/history_screen.dart`）：解いた問題数・正解数・全体正答率、
  レベルごとの内訳（解答数・正解数・正答率）を表示。設計書「3.6 その他の画面」は
  見出しのみで具体的な記載がなかったため、上記の内容を最低限として実装した
  （2026年9月時点）
- 詳しい画面設計は設計書の「3. 画面設計」を参照

## チャットAI（方針）

- 初期リリースでは、決まった台詞のみのルールベースで実装する（外部APIは呼ばない）
- 本格的なチャットAI（外部API連携）は、運用実績を見てから改めて検討する
- 指示がない限り、外部AI APIへの接続コードを追加しないこと

## 素材について

- `assets/` フォルダ内の画像（backgrounds, characters, puzzle_pieces_v3, ui_elements, icons_misc）を使用する
- 素材はデザイン検討中のラフ画像を含むため、同じ種類の画像が複数ある場合は
  使用前に人間に確認すること（勝手に1つを選んで確定しない）
- `assets/puzzle_pieces`（旧素材、薄い単色ピース・背景演出用のジグソー状風景切り抜き・
  空白テンプレートのみ）と`assets/ui_elements/image6.png`は現在ピースの表示には使って
  いない。旧`assets/puzzle_pieces_v2/`（`01.png`〜`06.png`と`01001`〜`02014`）は
  2026年10月に廃止し、削除した。

### ピース画像（SVG原本から書き出す方式、2026年10月）

- ピースの原本は、ユーザーが用意したSVG（`puzzle_pieces.zip`）で、
  `tools/piece_exporter/svg/`に保管している（前置`pre_piece_1〜4`、語幹
  `g_stem_piece_1〜4`（緑）・`y_stem_piece_1〜4`（黄）、後置`suf_piece_1〜4`、
  元の3×4ジグソーのサンプル`puzzle_sumple_sheet1.svg`）。1〜4番は色違いではなく
  **別々のジグソーの形**で、同じ番号の 前置→語幹→後置 が互いにかみ合う
  （サンプルシートの1段ぶんを左・中・右に切り出したもの）。
- SVGからアプリ用PNGへの変換は`tools/piece_exporter`（独自の`pubspec.yaml`で
  `flutter_svg`を使う開発用ツール。本体のアプリ・`flutter analyze`・`flutter test`の
  対象外）。`cd tools/piece_exporter && flutter test`を実行すると、次を書き出す。
  - `assets/puzzle_pieces_v3/{pre,stem_g,stem_y,suf}_{1..4}.png`
    （SVGの1単位＝3px、外周の余白を切り詰めた高解像度PNG）
  - `lib/widgets/piece_geometry.g.dart`（各画像の形状データの定数表。**自動生成物
    なので手で編集しない**）
  - `tools/piece_exporter/preview/`（かみ合わせ・横伸ばしの目視確認用画像、git管理外）
  形状データは、本体（四角い部分）の矩形、横に伸ばしても絵が崩れない列
  （`stretchLeft`〜`stretchRight`）、文字を置けない左右の余白（凹みの深さ）、
  左右の継ぎ目の形（出っ張り/凹み/平ら）と上端・下端の高さ。SVGを差し替えたら
  このコマンドを再実行し、`preview/`の画像で目視確認する。
- **使う形は1番と3番だけ**。2番・4番の語幹は左右の両方が凹み、さらに上か下の中央に
  出っ張り/凹みがあるため、横に伸ばせる列がなく（伸ばすと凹みの間に筋が出る）、
  `stretchable: false`になる。単語ごとに1番と3番を交互に使う（`words.json`の並び順）。
  2番・4番を使いたい場合は、SVG側で語幹の形を見直す（または帯ごとに伸ばす位置を
  変える伸ばし方の拡張が必要）。
- **表示の仕組み**（`lib/widgets/puzzle_piece_shape.dart`、`piece_geometry.dart`）：
  - SVG1単位＝画面上`kUnitPx`（1.0）論理px。本体は約66×74px。
  - ラベルの文字は常に20px・太字（小学生の読みやすさを優先し、長い単語でも縮小
    しない）。文字が本体の文字領域（凹みの深さを除いた幅）に収まらないときは、
    ピースの**本体を横に引き伸ばす**（`PieceFit.extra`＝max(0, 文字幅＋左右の余白
    `kLabelPadding`×2 − 文字領域)）。伸ばすのは`stretchLeft`〜`stretchRight`の列
    だけで、出っ張り・凹み・縁は元の形のまま（`Canvas.drawImageNine`）。
  - 文字色は本体中央の色の明るさから自動判定（明るい色には濃い文字、暗い色には白）。
    背景色によらず読めるよう、反対色の縁取り風の影を8方向に重ねる。文字は本体の
    文字領域の中央に置く。
- **解答欄**（`game_screen.dart`の`_buildAnswerRow()`、`piece_row_layout.dart`）：
  - 隣り合うピースは、本体の左右の端を**ぴったり突き合わせて**並べる（出っ張りと
    凹みがかみ合う）。以前の「重なり幅を画像の余白から都度計算する」方式
    （`kExtraOverlap`・`_touchOverlapBetween()`等）は廃止した。ピースを置くと、
    文字の長さに応じて伸びた幅ぶん右隣以降が押し出される。
  - ドラッグの受け皿（当たり判定）は本体の矩形そのもの（高さは上下の出っ張りまで
    含む）で、スロット同士は重ならない。出っ張りが隣のスロットの範囲にかかる部分は
    見た目だけで、当たり判定は持たない。
  - 空欄のスロットは標準の大きさ（約66×74px）。正解ピースの長さを先に反映すると
    答えの長さがヒントになるため。
  - 縦は、隣り合うピースの継ぎ目の上端の角を同じ高さに合わせる。解答欄の高さは
    その問題の全ピースの形から1度だけ決める（ピースを置いても動かない）。
  - 継ぎ目で出っ張りを持つ側のピースを手前に描く（1番は左が手前、3番は右が手前）。
  - 解答欄の枠（灰色の角丸）は**空欄の区間だけ**に描く（ピースは半透明なので、
    下にも枠を描くと線が透けて見える）。
  - 3枠とも長いピースが入って画面幅を超えるときは、`FittedBox`で全体を縮小する。
- **選択肢エリア**：1マスの大きさはその問題で最大のピース（幅・高さとも最大値）に
  合わせる。列数は画面幅÷マス幅、縦に収まらなければ縦スクロール（ジッタード・
  グリッドの配置方式と、相対座標で保持する仕組みは従来どおり）。
- **画像の割り当て**（`words.json`の`choices[].image`、`tools/assign_piece_images.py`
  で生成。リポジトリ直下で`python tools/assign_piece_images.py`。結果は決定論的）：
  - 画像名は`{pre,stem_g,stem_y,suf}_{1|3}.png`＝役割＋形の番号。1問の全ピースは
    同じ番号。語幹の色（緑/黄）はピースごとに決定論的に選ぶ。
  - 正解ピースの役割は注釈（`new_words_49.json`の`q_Prefixes`/`q_Stem`/`q_Suffix`、
    旧10問と`minor`はスクリプト内の`STRUCTURE_OVERRIDES`）から決める。2ピースは
    前置+語幹か語幹+後置、3ピースは前置+語幹+後置。
  - **おとりの役割の均等割り当て**：正解の各役割と同じ役割のおとりを必ず1個以上
    入れ、残りは合計が最も少ない役割に割り当てる。これで「前置の形は左端が平ら」
    などの形から、正解を絞り込めない（以前は正解とおとりで形の種類が違い、形が
    答えを漏らしていた）。同じ条件の割り当てが複数あるときは、おとり自身が本来使われる
    役割（例：`ly`は後置）に近い方を選ぶ。
  - **新しい単語を追加するとき**：`words.json`に`parts`と`choices`（`image`は仮でよい）
    を追加し、その単語の構造（`new_words_49.json`の注釈か`STRUCTURE_OVERRIDES`）を
    用意してスクリプトを再実行する。再実行すると全単語の画像が決定論的に
    再生成される（既存の単語は同じ結果になる）。
- テスト：`test/word_data_test.dart`（全問題の画像・役割・おとりの偏りの検査）、
  `test/piece_layout_test.dart`（本体の突き合わせ・伸び・角の高さ・描画順）、
  `test/all_words_solvable_test.dart`（全59問を実際にドラッグ操作で解く）。画面を
  使うテストの共通の問題データは`test/support/test_puzzles.dart`。
- 画面の見た目の確認：開発用ブラウザ（Browserツール）ではCanvasKitの描画が見られない
  ことがある。`flutter_test`で`matchesGoldenFile`（`--update-goldens`）を使うと
  実際の描画をPNGに書き出せる（Robotoフォントを`FontLoader`で読み込めば本物に近い
  文字幅になる。ピース画像の読み込みは実時間の待ちが必要で、複数のテストにまたがって
  キャッシュした画像は使えないため、1つの`testWidgets`の中で撮る）。

### その他の画面表示

- ゲーム画面下部の「?」「Answer!」「Menu」ボタン行は、3ボタン分の固定幅
  （64+140+96px）より画面が狭いと、通常の`Row`ではFlutterのオーバーフロー警告
  （黄黒の縞模様の帯）が表示されてしまう。`LayoutBuilder`で幅を見て、十分な幅が
  あるときは均等配置、収まらない狭い幅のときだけ横スクロール可能に切り替えている
  （2026年時点の決定、ブラウザ版でウィンドウ幅を狭めたときに再現）。
- レベルの進行演出（背景マスク、`_RevealMaskPainter`）は、未正解のマスをクリーム色の
  矩形で1マスずつ塗って隠しているが、マスのサイズ（画面幅÷列数）が割り切れない
  ときに隣接するマス同士の境界がピクセル単位でぴったり合わず、同じ色で塗っている
  にもかかわらず継ぎ目から下の風景画像が線状に透けて見えることがあった
  （ブラウザでウィンドウ幅を変えると出たり消えたりする形で再現）。各マスを隣と
  少し重ねて（上下左右1pxずつ大きく）描くことで解消した（2026年時点の決定）。
- 結果画面の羊キャラクター：正解時は `assets/characters/image20.png`（ガッツポーズ）、
  不正解時は `assets/characters/image21.png`（泣き顔＋卒業帽）を使用
- 結果画面の例文（英語・日本語訳）は、白いカード枠（背景色・角丸・影）で囲わず、
  クリーム色の背景に直接テキストを配置する（2026年時点の決定。カード枠が
  「余計な枠」に見えるという指摘を受けて廃止した）。
- レベルごとの進行演出（背景）：`assets/backgrounds/`のうち
  Level1=`image31.png`（タージマハル）、Level2=`image33.png`（雪の村）、
  Level3=`image35.png`（モアイ像）を割り当てている（他の画像は未使用のまま）

## 開発環境・パス運用ルール（決定事項）

- このプロジェクト本体は `C:\Dev\eitango-puzzle-trainer` に置かれている（2026年時点の決定）。
  データはこの場所が正であり、以後の作業もここで行う。
- 以前は `C:\Users\t-tanaka\OneDrive - 九州ルーテル学院大学\ドキュメント\アプリ開発\V0001\project`
  （日本語・スペースを含むOneDrive配下のパス）に置かれていた。このパスは日本語・スペースを含むため、
  `flutter analyze`など一部のFlutterツール（LSPベースの解析サーバー）がパスのURLエンコード処理で
  クラッシュする既知の不具合があり、`C:\dev\wpt`へのディレクトリジャンクションを作って回避していた。
  現在地（`C:\Dev\eitango-puzzle-trainer`）は日本語・スペースを含まないため、この問題自体が再発せず
  （`flutter analyze`が問題なく動作することを移動後に確認済み）、**ジャンクションによる回避は不要になった
  ため撤去した。** flutter/dartのコマンドライン操作は、このパスから直接実行してよい。
  この移動に伴い、OneDrive側の旧フォルダは削除済み（データは実体としてこの1か所のみ）。
- 開発環境本体（Flutter SDK / JDK / Android SDK）は `C:\Users\t-tanaka\dev\` 配下に個別インストール済み
  （`flutter`, `jdk-17.0.19+10`, `android-sdk`）。Android Studio（GUI）は未導入で、
  コマンドラインツール（`sdkmanager`）のみで運用している。
- **ブラウザ操作ツールでのテキスト入力に関する既知の制約**（2026年9月確認）：
  Claude Codeのブラウザ操作ツールで`TextField`にクリック＋キー入力すると、裏側の
  隠しinput要素には正しく文字が入る（`document.activeElement.value`で確認できる）が、
  Flutter側の描画（キャンバス上の表示）には反映されないことがある。ドラッグ操作や
  ボタンクリックは問題なく動作する。この制約に当たった場合は、無理に自動確認を
  続けず、代わりに（a）Flutterの`flutter_test`（`enterText`は正しく動作する）で
  該当ロジックを検証する、（b）Firestoreなどネットワーク越しの処理はブラウザの
  JavaScript実行機能から直接REST APIを叩いて検証する、（c）ユーザー本人に手動確認を
  依頼する、のいずれかで代替すること。

## Gitブランチ運用（決定事項）

- **`production`ブランチ＝アンケート・発表で公開している版。直接変更しないこと。**
  GitHub Pagesへの自動デプロイ（上記「技術スタック」参照）は、このブランチへのpushで
  実行される。
- **`main`ブランチ＝今後の開発を続ける場所。** 普段の開発作業（コミット・push）は
  すべて`main`に対して行う。`main`にpushしても、`production`および公開中のアプリには
  一切影響しない。
- 新しいバージョンを公開したくなったときは、`main`の内容を`production`に反映する
  （例：`git checkout production && git merge main && git push origin production`）、
  という手順を踏む。`production`ブランチを普段の開発作業で直接操作しないこと。
- 2026年時点で、`production`は「59問への拡張・効果音/読み上げ機能・GitHub Pages自動
  デプロイ設定」までを含むmainの状態から分岐した（アンケート公開中のスナップショット）。

## 開発の進め方

- 一度にアプリ全体を実装しようとせず、画面単位・機能単位の小さな作業に区切って進めること
- まだ設計書に明記されていない仕様（ヒント機能の中身、反復学習の間隔など）に当たった場合は、
  仮実装をして進めるのではなく、必ず人間に確認すること
- 大きな設計判断（データ構造の変更、フォルダ構成の変更など）を行う前に、必ず確認を取ること
