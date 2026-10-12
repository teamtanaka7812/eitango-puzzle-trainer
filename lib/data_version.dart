/// 学習記録（Firestoreの`attempts`）に付ける、データの版。
///
/// 問題データや出題の仕様を変えたときに、この値を更新する（運用はCLAUDE.mdの
/// 「データの版」を参照）。分析のとき、版の違う記録を区別するために使う。
/// この項目が無い記録は、この仕組みを入れる前の旧版のもの。
///
/// - `2026-10`：「Answer」で解答欄に空きがあれば判定・記録をしない仕様と、
///   8語（unfortunately・reappearance・independently・reconsideration・
///   uncomfortable・disagreement・undependable・unacceptable）と adventure・
///   exception を3ピースに戻し、prejudice を2ピースにし、accurate・offense・
///   defense を出題から外した問題構成。
/// - `2026-10b`：adventure を ad + venture の2ピースにした（英語の専門家の判断）。
///   あわせて、禁止語（arity・inventful）が作れないよう、4問（development・
///   achieve・pretend の3問のおとりと、adventure の構成）を変えた。
///
/// 命名規則：`年-月`が基本。同じ月にまた構成を変えるときは、`2026-10c`・`2026-10d`
/// のように、英小文字を順に付けて続ける（最初の版の`2026-10`は、`a`を付けない）。
const String kDataVersion = '2026-10b';
