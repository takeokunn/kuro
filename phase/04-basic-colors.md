# フェーズ 04: 基本色（16色）

## 目的

`ls --color`がANSI 16色で色付き出力を表示する。SGRシーケンス解析、属性追跡、Elispフェイスマッピングを実装する。

**期間:** Week 4

## ドキュメントリンク

- [VTEパーサー仕様](../docs/reference/rust-core/parser.md) - SGRセクション
- [Elispレンダラー](../docs/reference/elisp/renderer.md) - フェイスマッピング

## 実装方針

### Rust実装

| コンポーネント | 説明 |
|---------------|------|
| SGR解析 | `CSI Pm m`シーケンスの解析 |
| CellAttr追跡 | 新しいセルの現在の属性を追跡 |
| 色型 | Named（16色）、Indexed（256）、Rgb（TrueColor） |

**主要関数:**
- `handle_sgr()` - SGRパラメータの処理
- `CellAttr`構造体 - 前景色、背景色、スタイル属性の追跡
- `Color`列挙型 - 全ての色型を表現

### Elisp実装

| コンポーネント | 説明 |
|---------------|------|
| フェイス作成 | `kuro--make-face`関数 |
| フェイス適用 | フェイスplist付きの`add-text-properties` |
| 色マッピング | Rustの色をEmacsフェイスに変換 |

**主要関数:**
- `kuro--make-face` - 色/属性データからフェイスplistを作成
- `kuro--apply-faces` - バッファ領域にフェイスを適用

### SGRパラメータ

| パラメータ | 効果 |
|-----------|------|
| `0` | 全属性をリセット |
| `1` | 太字 |
| `3` | イタリック |
| `4` | 下線 |
| `7` | 反転（前景/背景入れ替え） |
| `9` | 取り消し線 |
| `22` | 通常輝度（太字/暗調解除） |
| `23` | イタリック解除 |
| `24` | 下線解除 |
| `29` | 取り消し線解除 |

### ANSI 16色

| コード | 前景 | 背景 | 明るい前景 | 明るい背景 |
|-------|------|------|-----------|-----------|
| 黒 | `30` | `40` | `90` | `100` |
| 赤 | `31` | `41` | `91` | `101` |
| 緑 | `32` | `42` | `92` | `102` |
| 黄 | `33` | `43` | `93` | `103` |
| 青 | `34` | `44` | `94` | `104` |
| マゼンタ | `35` | `45` | `95` | `105` |
| シアン | `36` | `46` | `96` | `106` |
| 白 | `37` | `47` | `97` | `107` |

| デフォルト | `39` | `49` | - | - |

### CellAttr構造

```rust
struct CellAttr {
    fg: Color,
    bg: Color,
    bold: bool,
    italic: bool,
    underline: bool,
    strikethrough: bool,
    inverse: bool,
    dim: bool,
}
```

## タスク

- [ ] **SGRシーケンス解析の実装**
  - [ ] 単一および複数パラメータの解析
  - [ ] 属性コードの処理（0, 1, 3, 4, 7, 9等）
  - [ ] 色コードの処理（30-37, 40-47, 90-97, 100-107）
  - [ ] リセットコードの処理（22, 23, 24, 29, 39, 49）
  - [ ] `CellAttr`状態の更新

- [ ] **TerminalCoreでのCellAttr追跡の実装**
  - [ ] `current_attr: CellAttr`フィールドの追加
  - [ ] 新しいセル作成時にcurrent_attrを適用
  - [ ] SGRパラメータの組み合わせを処理

- [ ] **Elispフェイスマッピング関数の作成**
  - [ ] `kuro--make-face`関数
  - [ ] 色hexをEmacsフェイスプロパティに変換
  - [ ] 属性フラグをフェイスプロパティにマッピング
  - [ ] 反転モードの処理（前景/背景入れ替え）

- [ ] **レンダーループでのフェイス適用**
  - [ ] poll_updatesからフェイス範囲を解析
  - [ ] フェイス適用に`add-text-properties`を使用
  - [ ] 最適化: 変更のみを適用

## 受け入れ条件

### 手動テスト手順

#### テスト1: 色付きディレクトリ一覧

1. 実行: `ls --color=auto`
2. ディレクトリがある色で表示されることを確認
3. 実行可能ファイルが別の色で表示されることを確認
4. 通常ファイルがデフォルト色で表示されることを確認

**期待結果:** 異なるファイルタイプが異なる色で表示される。

#### テスト2: 基本前景色

1. 実行: `echo -e "\e[31mRED TEXT\e[0m"`
2. "RED TEXT"が赤色で表示されることを確認
3. `\e[0m`以降のテキストがデフォルト色であることを確認

**期待結果:** 赤色のテキスト、その後デフォルト色にリセット。

#### テスト3: 太字テキスト

1. 実行: `echo -e "\e[1;32mBOLD GREEN\e[0m"`
2. テキストが太字かつ緑色であることを確認

**期待結果:** 太字の緑色テキスト。

#### テスト4: 下線テキスト

1. 実行: `echo -e "\e[4mUNDERLINE\e[0m"`
2. テキストに下線があることを確認

**期待結果:** 下線付きテキスト。

#### テスト5: 複数属性

1. 実行: `echo -e "\e[1;3;4;35mBOLD ITALIC UNDERLINE MAGENTA\e[0m"`
2. 全ての属性が適用されていることを確認

**期待結果:** 太字、イタリック、下線、マゼンタのテキスト。

#### テスト6: 背景色

1. 実行: `echo -e "\e[41mRED BACKGROUND\e[0m"`
2. 背景が赤であることを確認

**期待結果:** 赤い背景のテキスト。

#### テスト7: 明るい色

1. 実行: `echo -e "\e[91mBRIGHT RED\e[0m"`
2. 明るい赤色を確認

**期待結果:** 通常の赤（31）より明るい赤色のシェード。

#### テスト8: 反転表示

1. 実行: `echo -e "\e[7mINVERSE\e[0m"`
2. 前景と背景が入れ替わっていることを確認

**期待結果:** 色が反転（背景が前景色に、前景が背景色になる）。

## 依存関係

- **フェーズ 03:** コマンドライン編集（完了していること）

## 次のフェーズ

- [フェーズ 05: 拡張色](./05-extended-colors.md) - 256色およびTrueColor対応

## 技術ノート

### SGR実装

```rust
fn handle_sgr(&mut self, params: &vte::Params) {
    let mut iter = params.iter();

    while let Some(param) = iter.next() {
        match param[0] {
            0 => self.current_attr = CellAttr::default(),
            1 => self.current_attr.bold = true,
            2 => self.current_attr.dim = true,
            3 => self.current_attr.italic = true,
            4 => self.current_attr.underline = true,
            7 => self.current_attr.inverse = true,
            9 => self.current_attr.strikethrough = true,
            22 => { self.current_attr.bold = false; self.current_attr.dim = false; }
            23 => self.current_attr.italic = false,
            24 => self.current_attr.underline = false,
            27 => self.current_attr.inverse = false,
            29 => self.current_attr.strikethrough = false,
            30..=37 => self.current_attr.fg = Color::Named(NamedColor::from_ansi(param[0] - 30)),
            39 => self.current_attr.fg = Color::Default,
            40..=47 => self.current_attr.bg = Color::Named(NamedColor::from_ansi(param[0] - 40)),
            49 => self.current_attr.bg = Color::Default,
            90..=97 => self.current_attr.fg = Color::Named(NamedColor::from_ansi_bright(param[0] - 90)),
            100..=107 => self.current_attr.bg = Color::Named(NamedColor::from_ansi_bright(param[0] - 100)),
            _ => {}
        }
    }
}
```

### 色からRGBへのマッピング

```rust
impl NamedColor {
    fn to_rgb(&self) -> (u8, u8, u8) {
        match self {
            NamedColor::Black => (0, 0, 0),
            NamedColor::Red => (205, 0, 0),
            NamedColor::Green => (0, 205, 0),
            NamedColor::Yellow => (205, 205, 0),
            NamedColor::Blue => (0, 0, 238),
            NamedColor::Magenta => (205, 0, 205),
            NamedColor::Cyan => (0, 205, 205),
            NamedColor::White => (229, 229, 229),
            NamedColor::BrightBlack => (127, 127, 127),
            NamedColor::BrightRed => (255, 0, 0),
            NamedColor::BrightGreen => (0, 255, 0),
            NamedColor::BrightYellow => (255, 255, 0),
            NamedColor::BrightBlue => (92, 92, 255),
            NamedColor::BrightMagenta => (255, 0, 255),
            NamedColor::BrightCyan => (0, 255, 255),
            NamedColor::BrightWhite => (255, 255, 255),
        }
    }
}
```

### Elispでのフェイスマッピング

```elisp
(defun kuro--make-face (fg bg attrs)
  "FG, BG色とATTRSフラグからフェイスplistを作成する。
FG, BGはnilまたは\"#RRGGBB\"文字列。
ATTRSはビットマスク整数。"
  (let ((face nil)
        (actual-fg fg)
        (actual-bg bg))
    ;; 反転 (0x10): fgとbgを入れ替え
    (when (/= 0 (logand attrs #x10))
      (setq actual-fg bg
            actual-bg fg))
    (when actual-fg
      (setq face (plist-put face :foreground actual-fg)))
    (when actual-bg
      (setq face (plist-put face :background actual-bg)))
    (when (/= 0 (logand attrs #x01))
      (setq face (plist-put face :weight 'bold)))
    (when (/= 0 (logand attrs #x02))
      (setq face (plist-put face :slant 'italic)))
    (when (/= 0 (logand attrs #x04))
      (setq face (plist-put face :underline t)))
    (when (/= 0 (logand attrs #x08))
      (setq face (plist-put face :strike-through t)))
    (when (/= 0 (logand attrs #x20))
      (setq face (plist-put face :weight 'semi-light)))
    face))
```

### フェイス適用

```elisp
(defun kuro--apply-faces (base-pos face-ranges)
  "BASE-POSから始まるバッファにFACE-RANGESを適用する。
FACE-RANGESは[[start end fg bg attrs] ...]ベクター。"
  (cl-loop for range across face-ranges do
           (let* ((start (+ base-pos (aref range 0)))
                  (end   (+ base-pos (aref range 1)))
                  (fg    (aref range 2))
                  (bg    (aref range 3))
                  (attrs (aref range 4))
                  (face  (kuro--make-face fg bg attrs)))
             (when face
               (add-text-properties start end (list 'face face))))))
```

## フェーズ1完了

このフェーズ完了後、フェーズ1（基盤）が完了する。端末は以下をサポートする:

- シェルプロンプト表示
- 制御文字を含む基本テキスト出力
- カーソル移動を伴うコマンドライン編集
- 16色ANSI対応

次のフェーズ（フェーズ2: VTE準拠）では以下を追加:
- 拡張CSIシーケンス
- 256色およびTrueColor対応
- OSCシーケンス（ウィンドウタイトル、ハイパーリンク）
- スクロール領域および高度な機能
