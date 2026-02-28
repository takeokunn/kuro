# フェーズ 6: vim基本表示

## 目的
`vim file.txt`が正しく開き表示される

## 期間
Week 6-7

## 関連ドキュメント
- [VTE Parser仕様](../docs/reference/rust-core/parser.md) - DEC Private modes, ESC sequences

## 実装方針
- DEC Private modes: DECCKM (?1), DECTCEM (?25), DECAWM (?7)
- 代替スクリーンバッファ (?1049) - smcup/rmcup
- ESCシーケンス: DECSC (7), DECRC (8), RIS (c)
- カーソル保存/復元状態
- 主要関数: `handle_set_mode()`, `handle_esc_dispatch()`, 代替バッファ切り替え

## タスク
- [x] DEC private modeハンドリング実装 (? プレフィックス)
- [x] 代替スクリーンバッファ実装
- [x] DECSC/DECRCカーソル保存/復元実装
- [x] カーソル表示切替実装 (DECTCEM)

## 手動テスト手順

### テスト1: 代替バッファでvimを開く
1. `vim test.txt`
**期待結果:** vimが代替バッファで開く

### テスト2: カーソル表示
1. `vim test.txt`
2. カーソル位置を確認
**期待結果:** カーソルが表示され正しく配置されている

### テスト3: テキスト表示
1. `vim test.txt`
2. テキストレンダリングを確認
**期待結果:** テキストが乱れずに表示される

### テスト4: vim終了とバッファ復元
1. `vim test.txt`
2. `:q`
**期待結果:** シェルに戻り、シェルバッファが復元される

### テスト5: 完全なvim編集サイクル
1. vimを再度開く
2. `i`を入力して挿入モードに入る
3. テキストを入力
4. `Esc`を押す
5. `:wq`を入力
**期待結果:** vimが正常に開き/閉じ、バッファが正しく切り替わる

## 受け入れ条件
- vimが正常に開き/閉じる
- バッファが正しく切り替わる
- シェル履歴が破損しない

## 依存関係
- フェーズ 05

## 後続フェーズ
- フェーズ 07-16
