# フェーズ 02: 基本テキスト出力

## 目的

`echo`、`cat`が正しい出力を行い、行折り返しが機能する。C0制御文字処理とオートラップモードを含むコアテキスト出力機能を実装する。

**期間:** Week 2

## ドキュメントリンク

- [VTEパーサー仕様](../docs/reference/rust-core/parser.md) - `print`および`execute`セクション

## 実装方針

### Rust実装

| コンポーネント | 説明 |
|---------------|------|
| `Perform::print()` | グリッドセルへの文字出力 |
| C0制御文字処理 | CR, LF, BS, HT, BELの処理 |
| オートラップモード | DECAWMモード (?7h/l) サポート |

**主要関数:**
- `TerminalCore::print(c: char)` - カーソル位置に文字を書き込む
- `TerminalCore::execute(byte: u8)` - 制御文字を処理
- `Screen::update_cell(x, y, cell)` - グリッドセルを更新

### C0制御文字

| バイト | 名前 | 動作 |
|-------|------|------|
| `0x07` | BEL | ベル通知（視覚/音声） |
| `0x08` | BS | カーソル左（バックスペース） |
| `0x09` | HT | 水平タブ（次のタブストップ） |
| `0x0A` | LF | 改行（カーソル下、必要時にスクロール） |
| `0x0D` | CR | 復帰（カーソルを列0へ） |

### オートラップ (DECAWM)

- `CSI ?7h` - オートラップ有効（デフォルト）
- `CSI ?7l` - オートラップ無効
- 有効時、列境界でカーソルが次の行に折り返す

## タスク

- [ ] **`Perform::print()`トレイトメソッドの実装**
  - [ ] 現在のカーソル位置に文字を書き込む
  - [ ] 新しいセルに現在のCellAttrを適用
  - [ ] カーソルを右に進める
  - [ ] ワイド文字（CJK）を処理

- [ ] **C0制御文字処理の実装**
  - [ ] CR (0x0D) - カーソルを列0に移動
  - [ ] LF (0x0A) - カーソルを下に移動、最下部ならスクロール
  - [ ] BS (0x08) - カーソルを左に移動（列0以外）
  - [ ] HT (0x09) - 次のタブストップに移動（8列境界）
  - [ ] BEL (0x07) - Elisp通知用のベルフラグを設定

- [ ] **行末でのオートラップ実装**
  - [ ] DECAWMモード状態の追跡
  - [ ] 列制限超過時のカーソル折り返し
  - [ ] 最下行での折り返し時の画面スクロール

- [ ] **BEL通知の処理**
  - [ ] TerminalCoreに`bell_pending`フラグを設定
  - [ ] `poll_updates`でフラグを公開
  - [ ] Elisp: `ding`または視覚ベルを呼び出し

## 受け入れ条件

### 手動テスト手順

#### テスト1: 基本echo出力

1. kuroバッファで実行: `echo "Hello World"`
2. 行に"Hello World"が表示されることを確認

**期待結果:** 正確なテキスト"Hello World"が表示される。

#### テスト2: 複数行

1. 実行: `printf "line1\nline2\n"`
2. 2つの独立した行が表示されることを確認
3. "line1"が最初の行、"line2"が2番目の行にあることを確認

**期待結果:**
```
line1
line2
```

#### テスト3: タブ整列

1. 実行: `printf "\tindented"`
2. "indented"が列8（または次のタブストップ）から始まることを確認

**期待結果:** テキストがタブ境界に整列される。

#### テスト4: ベル通知

1. 実行: `echo -e "\a"`
2. ベル通知がトリガーされることを確認
3. 視覚/音声フィードバックを確認

**期待結果:** ベル通知が知覚可能（視覚フラッシュまたは音声）。

#### テスト5: 長い行の折り返し

1. 実行: `echo "This is a very long line that exceeds the terminal width and should wrap to the next line automatically"`
2. 端末境界でテキストが折り返されることを確認
3. 継続が次の行に表示されることを確認

**期待結果:** テキストが切り捨てられずに正しく折り返される。

## 依存関係

- **フェーズ 01:** シェルプロンプト表示（完了していること）

## 次のフェーズ

完了後、以下が有効になる:
- フェーズ 03: コマンドライン編集
- フェーズ 04: 基本色

## 技術ノート

### Print実装

```rust
impl vte::Perform for TerminalCore {
    fn print(&mut self, c: char) {
        let cell = Cell {
            c,
            fg: self.current_attr.fg,
            bg: self.current_attr.bg,
            bold: self.current_attr.bold,
            italic: self.current_attr.italic,
            underline: self.current_attr.underline,
            strikethrough: self.current_attr.strikethrough,
            image_id: None,
        };

        self.screen.update_cell(
            self.screen.cursor.x,
            self.screen.cursor.y,
            cell
        );

        // オートラップでカーソルを進める
        self.screen.cursor.x += 1;
        if self.screen.cursor.x >= self.screen.cols && self.decawm_enabled {
            self.screen.cursor.x = 0;
            self.move_cursor_down_with_scroll(1);
        }
    }
}
```

### Execute実装

```rust
fn execute(&mut self, byte: u8) {
    match byte {
        0x0A => {  // LF
            self.move_cursor_down_with_scroll(1);
        }
        0x0D => {  // CR
            self.screen.cursor.x = 0;
        }
        0x08 => {  // BS
            if self.screen.cursor.x > 0 {
                self.screen.cursor.x -= 1;
            }
        }
        0x07 => {  // BEL
            self.bell_pending = true;
        }
        0x09 => {  // HT
            let next_tab = (self.screen.cursor.x / 8 + 1) * 8;
            self.screen.cursor.x = next_tab.min(self.screen.cols - 1);
        }
        _ => {}
    }
}
```

### Elispでのベル処理

```elisp
(defun kuro--render-cycle ()
  (when-let ((updates (kuro-core-poll-updates kuro--core)))
    ;; ベルをチェック
    (when (kuro-core-bell-pending kuro--core)
      (ding)
      (kuro-core-clear-bell kuro--core))
    ;; 更新を適用
    (kuro--apply-updates updates)
    (kuro-core-clear-dirty kuro--core)))
```
