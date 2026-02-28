# フェーズ 15: Kittyグラフィックスプロトコル

## 目的

ターミナル内に画像を表示する

**期間:** 19-20週目

## 関連ドキュメント

- [docs/reference/rust-core/kitty-graphics.md](../docs/reference/rust-core/kitty-graphics.md)
- [docs/reference/rust-core/parser.md](../docs/reference/rust-core/parser.md) (APC セクション)

## 実装方針

- APCシーケンス検出 (ESC _ ... ESC \)
- vte-graphicsクレートの使用またはカスタムAPCパーサーの実装
- サポート形式: PNG (100), RGB (24), RGBA (32)
- ペイロードのBase64デコード
- 画像管理用 GraphicsStore
- グリッド上への画像配置
- メモリ管理用 LRU削除
- 主要関数: `handle_apc_start/put/end()`, `KittyHandler`, `GraphicsStore`, Elisp `create-image`

### タスク

- [ ] vte-graphicsクレートを追加またはAPCパーサーを実装
- [ ] APCシーケンス用 KittyHandler を実装
- [ ] 画像保存用 GraphicsStore を実装
- [ ] グリッド上への画像配置を実装
- [ ] Elisp画像レンダリングを実装
- [ ] メモリ制限とLRU削除を実装

## 受け入れ条件

### 手動テスト手順

1. `kitty +kitten icat test.png` → 画像が表示される
2. 複数画像: 3枚の画像を表示、重なり問題がないことを確認
3. 大きな画像: メモリ制限が守られていることを確認
4. vim内の画像 (vim-kittyプラグイン使用): 動作することを確認
5. 画面クリア → 画像が削除される

**期待結果:** 画像が正しく表示され、メモリが管理される

## 依存関係

**依存:** フェーズ 14

**次のフェーズ:** フェーズ 16
