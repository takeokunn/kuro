# フェーズ 13: キーボード入力完了

## 目的

すべてのキーの組み合わせが正しく動作する

**期間:** 17週目

## 関連ドキュメント

- [docs/reference/data-flow.md](../docs/reference/data-flow.md) (キー入力フロー)
- [docs/reference/elisp/renderer.md](../docs/reference/elisp/renderer.md)

## 実装方針

- 完全なキーマッピングテーブル (Emacsキー → PTYバイト列)
- ファンクションキー: F1-F12
- 修飾キー: Ctrl, Alt/Meta, Shift, Super
- アプリケーションカーソルキーモード (DECCKM)
- キーパッドモード (DECKPAM/DECKPNM)
- 主要関数: `kuro-core-send-key()`, キー → バイト列マッピング

### タスク

- [ ] 完全なキーマッピングテーブルを実装
- [ ] ファンクションキー F1-F12 を処理
- [ ] 修飾キーの組み合わせ (Ctrl+key, Alt+key 等) を処理
- [ ] アプリケーションカーソルキーの切り替えを実装
- [ ] キーパッドモードの切り替えを実装

## 受け入れ条件

### 手動テスト手順

1. `F1` → アプリケーションのヘルプを起動 (サポートされている場合)
2. `Ctrl+c` → SIGINT (割り込み) を送信
3. `Ctrl+d` → EOF を送信
4. `Ctrl+z` → SIGTSTP (一時停止) を送信
5. `Alt+f` → 単語単位で前方へ移動 (bash/zsh)
6. `Alt+b` → 単語単位で後方へ移動 (bash/zsh)
7. 矢印キー → 通常モードとアプリケーションモードの両方で動作
8. Home/End/PageUp/PageDown → 正しく動作

**期待結果:** すべてのキーの組み合わせが正しいバイト列を生成

## 依存関係

**依存:** フェーズ 12

**次のフェーズ:** フェーズ 14-16
