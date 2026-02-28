# フェーズ 5: 拡張カラー (256/TrueColor)

## 目的
256色および24ビットTrueColor対応

## 期間
Week 5

## 関連ドキュメント
- [VTE Parser仕様](../docs/reference/rust-core/parser.md) - 拡張カーパース

## 実装方針
- SGR 38;5;n: 256色インデックス (n = 0-255)
- SGR 38;2;r;g;b: TrueColor RGB (24-bit)
- Color enum: Named, Indexed(u8), Rgb(u8, u8, u8)
- パフォーマンス向上のためのFaceキャッシュ
- 主要関数: `parse_extended_color()`, `Color` enumバリアント

## タスク
- [x] 256色パース実装 (38;5;n)
- [x] TrueColorパース実装 (38;2;r;g;b)
- [x] IndexedおよびRgbバリアントでColor enumを拡張
- [x] ElispでFaceキャッシュ実装

## 手動テスト手順

### テスト1: 256色インデックス前景色
```bash
echo -e "\e[38;5;196m256-COLOR RED\e[0m"
```
**期待結果:** インデックス赤色

### テスト2: 256色インデックス背景色
```bash
echo -e "\e[48;5;21m256-COLOR BLUE BG\e[0m"
```
**期待結果:** インデックス青色背景

### テスト3: TrueColor RGB赤色
```bash
echo -e "\e[38;2;255;0;0mTRUECOLOR RED\e[0m"
```
**期待結果:** RGB赤色

### テスト4: TrueColor RGB緑色
```bash
echo -e "\e[38;2;0;255;128mTRUECOLOR GREEN\e[0m"
```
**期待結果:** RGB緑色

## 受け入れ条件
- すべての色が正しい色相で表示される
- Faceキャッシュによりパフォーマンスが向上する

## 依存関係
- フェーズ 04

## 後続フェーズ
- フェーズ 06-16
