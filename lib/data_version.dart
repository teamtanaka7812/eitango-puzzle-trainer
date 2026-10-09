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
const String kDataVersion = '2026-10';
