# フェーズ 16: テスト、セキュリティ & リリース

## 目的

vttest 80%以上、セキュリティ監査合格、v1.0.0 リリース

**期間:** 21-22週目

## 関連ドキュメント

- [docs/how-to/install.md](../docs/how-to/install.md)
- [docs/tutorials/getting-started.md](../docs/tutorials/getting-started.md)

## 実装方針

- Rustユニットテスト: 80%以上のカバレッジ
- proptestによるプロパティベーステスト
- パーサー用ファズテスト
- 依存関係の脆弱性検査に cargo-audit
- Elisp ERTテスト
- マルチプラットフォームテスト: Linux (glibc, musl), macOS (Intel, ARM)
- MELPA提出準備
- 主要関数: テストスイート, CI/CD, リリースアーティファクト

### タスク

- [ ] Rustユニットテストを80%以上のカバレッジに拡充
- [ ] proptestプロパティベーステストを追加
- [ ] パーサー用ファズテストを追加
- [ ] cargo-auditを実行して問題を修正
- [ ] Elisp ERTテストスイートを作成
- [ ] Linux と macOS でテスト
- [ ] リリースアーティファクト (.soファイル) を作成
- [ ] MELPAレシピを準備
- [ ] リリースノートを作成

## 受け入れ条件

### 手動テスト手順

1. `vttest` を実行 → 80%以上の合格率を確認
2. `docs/tutorials/getting-started.md` に従う → すべての手順が動作
3. クリーンなEmacsに新規インストール → 成功
4. `M-x kuro` → ターミナルが起動
5. 以前のすべてのフェーズのテストが依然として合格
6. `package.el` でパッケージ化 → 正しくインストール

**期待結果:** vttest 80%以上、すべてのテスト合格、リリース準備完了

## 依存関係

**依存:** フェーズ 15

**次のフェーズ:** v1.0.0 リリース
