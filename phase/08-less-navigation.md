# フェーズ 8: lessナビゲーション

## 目的
`less large_file.txt`のナビゲーションが動作する

## 期間
Week 10

## 関連ドキュメント
- [VTE Parser仕様](../docs/reference/rust-core/parser.md) - スクロール操作

## 実装方針
- スクロール領域操作 (DECSTBMは既に実装済み)
- VPA (d): 行位置絶対指定
- CHA (G): カーソル文字位置絶対指定
- HVP (f): 水平・垂直位置
- 画面消去の最適化
- 主要関数: `handle_line_position_absolute()`, `handle_cursor_character_absolute()`

## タスク
- [ ] lessでスクロール領域が動作することを確認
- [ ] VPA (d) を未実装なら実装
- [ ] HVP (f) を未実装なら実装
- [ ] less向け画面消去を最適化

## 手動テスト手順

### テスト1: 大きなファイルを開く
1. `less /usr/share/dict/words`
**期待結果:** 大きなファイルが開く

### テスト2: ページダウン
1. `less /usr/share/dict/words`
2. `Space` または `PageDown`
**期待結果:** 1ページ下にスクロール

### テスト3: ページアップ
1. `less /usr/share/dict/words`
2. 最初に下に移動
3. `b` または `PageUp`
**期待結果:** 1ページ上にスクロール

### テスト4: 行単位スクロール
1. `less /usr/share/dict/words`
2. `矢印キー` (上/下)
**期待結果:** 行単位でスクロール

### テスト5: 先頭に移動
1. `less /usr/share/dict/words`
2. 中央に移動
3. `g`
**期待結果:** 先頭に移動

### テスト6: 末尾に移動
1. `less /usr/share/dict/words`
2. `G`
**期待結果:** 末尾に移動

### テスト7: 検索
1. `less /usr/share/dict/words`
2. `/pattern`
**期待結果:** 前方検索

### テスト8: lessを終了
1. `less /usr/share/dict/words`
2. `q`
**期待結果:** lessを終了

## 受け入れ条件
- すべてのナビゲーションがスムーズに動作する
- スクロール中に表示アーティファクトがない

## 依存関係
- フェーズ 07

## 後続フェーズ
- フェーズ 09-16
