# フェーズ 03: コマンドライン編集

## 目的

Readlineスタイルのコマンドライン編集が動作する。CSIカーソル移動シーケンス、消去操作、キーボード入力処理を実装する。

**期間:** Week 3

## ドキュメントリンク

- [VTEパーサー仕様](../docs/reference/rust-core/parser.md) - CSIカーソルシーケンス
- [データフロー](../docs/reference/data-flow.md) - キー入力フロー

## 実装方針

### Rust実装

| コンポーネント | 説明 |
|---------------|------|
| CSIカーソル移動 | CUU, CUD, CUF, CUB, CUP, VPA, CHA |
| EDシーケンス | 消去表示 (0=カーソル以降, 1=カーソル以前, 2=全て) |
| ELシーケンス | 消去行 (0=カーソル以降, 1=カーソル以前, 2=全て) |
| キーボードマッピング | キーイベントからPTYバイトシーケンスへ |

**主要関数:**
- `handle_cup()` - カーソル位置 (CSI H/f)
- `handle_cursor_up/down/forward/backward()` - 相対移動
- `handle_erase_display()` - EDシーケンス (CSI J)
- `handle_erase_line()` - ELシーケンス (CSI K)

### CSIカーソルシーケンス

| シーケンス | 名前 | 説明 |
|-----------|------|------|
| `CSI n A` | CUU | カーソルをn行上へ |
| `CSI n B` | CUD | カーソルをn行下へ |
| `CSI n C` | CUF | カーソルをn列前へ |
| `CSI n D` | CUB | カーソルをn列後へ |
| `CSI row;col H` | CUP | カーソル位置 (1ベース) |
| `CSI row;col f` | HVP | 水平/垂直位置 |
| `CSI n d` | VPA | 垂直位置絶対 |
| `CSI n G` | CHA | カーソル水平絶対 |

### 消去シーケンス

| シーケンス | 名前 | 説明 |
|-----------|------|------|
| `CSI 0 J` | ED | カーソルから画面末尾まで消去 |
| `CSI 1 J` | ED | 画面先頭からカーソルまで消去 |
| `CSI 2 J` | ED | 画面全体を消去 |
| `CSI 0 K` | EL | カーソルから行末まで消去 |
| `CSI 1 K` | EL | 行先頭からカーソルまで消去 |
| `CSI 2 K` | EL | 行全体を消去 |

### キーボード入力マッピング

| Emacsキー | 送信バイト | 説明 |
|----------|-----------|------|
| 通常文字 | 文字のUTF-8 | 通常テキスト入力 |
| `RET` | `\r` (0x0D) | 復帰 |
| `DEL` | `\x7f` | バックスペース |
| `<up>` | `\e[A` | カーソル上 |
| `<down>` | `\e[B` | カーソル下 |
| `<right>` | `\e[C` | カーソル前 |
| `<left>` | `\e[D` | カーソル後 |

## タスク

- [ ] **CSIカーソル移動シーケンスの実装**
  - [ ] CUU (A) - カーソル上
  - [ ] CUD (B) - カーソル下
  - [ ] CUF (C) - カーソル前
  - [ ] CUB (D) - カーソル後
  - [ ] CUP (H/f) - カーソル位置（絶対）
  - [ ] VPA (d) - 垂直位置絶対
  - [ ] CHA (G) - カーソル水平絶対
  - [ ] 境界クランプ（カーソルは有効範囲内に留まる）

- [ ] **ED（消去表示）シーケンスの実装**
  - [ ] パラメータ0: カーソルから画面末尾まで消去
  - [ ] パラメータ1: 画面先頭からカーソルまで消去
  - [ ] パラメータ2: 画面全体を消去
  - [ ] 影響を受ける行をダーティとしてマーク

- [ ] **EL（消去行）シーケンスの実装**
  - [ ] パラメータ0: カーソルから行末まで消去
  - [ ] パラメータ1: 行先頭からカーソルまで消去
  - [ ] パラメータ2: 行全体を消去
  - [ ] 行をダーティとしてマーク

- [ ] **キーボードからPTYバイトへのマッピング実装**
  - [ ] 矢印キー（上/下/左/右）
  - [ ] 特殊キー（RET, DEL, TAB）
  - [ ] Controlキーの組み合わせ（C-c, C-d, C-z）
  - [ ] Alt/Meta修飾子の処理

## 受け入れ条件

### 手動テスト手順

#### テスト1: 水平カーソル移動

1. Enterを押さずにコマンドを入力
2. `<left>`矢印を押す
3. カーソルが左に移動することを確認
4. `<right>`矢印を押す
5. カーソルが右に移動することを確認

**期待結果:** テキストを変更せずにカーソルが水平に移動する。

#### テスト2: バックスペース削除

1. `abc`と入力
2. Backspaceを押す
3. `c`が削除されることを確認
4. カーソルが`b`の位置にあることを確認

**期待結果:** 最後の文字が削除され、カーソルが再配置される。

#### テスト3: 行先頭/行末（シェルが対応している場合）

1. `echo hello`と入力
2. `C-a`（Ctrl+a）を押す
3. カーソルが先頭に移動することを確認
4. `C-e`（Ctrl+e）を押す
5. カーソルが末尾に移動することを確認

**期待結果:** カーソルが行の境界にジャンプする。（シェルのreadline対応に依存）

#### テスト4: 画面クリア

1. 実行: `clear`
2. 画面がクリアされることを確認
3. プロンプトが先頭に表示されることを確認

**期待結果:** 全コンテンツがクリアされ、プロンプトが行0に表示される。

#### テスト5: 履歴ナビゲーション

1. `<up>`矢印を押す
2. 前のコマンドが表示されることを確認
3. `<down>`矢印を押す
4. 空行または次のコマンドに戻ることを確認

**期待結果:** コマンド履歴のナビゲーションが動作する。

## 依存関係

- **フェーズ 02:** 基本テキスト出力（完了していること）

## 次のフェーズ

完了後、以下が有効になる:
- フェーズ 04: 基本色

## 技術ノート

### カーソル移動実装

```rust
fn handle_cursor_up(&mut self, params: &vte::Params) {
    let n = params.iter().next().map(|p| p[0] as usize).unwrap_or(1);
    let top = self.scroll_region_start.unwrap_or(0);
    self.screen.cursor.y = self.screen.cursor.y.saturating_sub(n).max(top);
}

fn handle_cursor_down(&mut self, params: &vte::Params) {
    let n = params.iter().next().map(|p| p[0] as usize).unwrap_or(1);
    let bottom = self.scroll_region_end.unwrap_or(self.screen.rows - 1);
    self.screen.cursor.y = (self.screen.cursor.y + n).min(bottom);
}

fn handle_cup(&mut self, params: &vte::Params) {
    let mut iter = params.iter();
    let row = iter.next().map(|p| p[0] as usize).unwrap_or(1);
    let col = iter.next().map(|p| p[0] as usize).unwrap_or(1);
    // ANSIは1ベース、0ベースに変換
    self.screen.cursor.y = (row.saturating_sub(1)).min(self.screen.rows - 1);
    self.screen.cursor.x = (col.saturating_sub(1)).min(self.screen.cols - 1);
}
```

### 消去表示実装

```rust
fn handle_erase_display(&mut self, params: &vte::Params) {
    let mode = params.iter().next().map(|p| p[0]).unwrap_or(0);

    match mode {
        0 => {
            // カーソルから末尾まで消去
            self.erase_line_from_cursor();
            for y in (self.screen.cursor.y + 1)..self.screen.rows {
                self.clear_line(y);
            }
        }
        1 => {
            // 先頭からカーソルまで消去
            for y in 0..self.screen.cursor.y {
                self.clear_line(y);
            }
            self.erase_line_to_cursor();
        }
        2 => {
            // 全て消去
            for y in 0..self.screen.rows {
                self.clear_line(y);
            }
        }
        _ => {}
    }
}
```

### 消去行実装

```rust
fn handle_erase_line(&mut self, params: &vte::Params) {
    let mode = params.iter().next().map(|p| p[0]).unwrap_or(0);
    let y = self.screen.cursor.y;

    match mode {
        0 => {
            // カーソルから行末まで消去
            for x in self.screen.cursor.x..self.screen.cols {
                self.screen.lines[y].cells[x] = Cell::default();
            }
        }
        1 => {
            // 行先頭からカーソルまで消去
            for x in 0..=self.screen.cursor.x {
                self.screen.lines[y].cells[x] = Cell::default();
            }
        }
        2 => {
            // 行全体を消去
            self.clear_line(y);
        }
        _ => {}
    }
    self.screen.lines[y].is_dirty = true;
    self.screen.dirty_set.insert(y);
}
```

### Elispでのキーボードマッピング

```elisp
(defvar kuro--key-map
  '(("<up>" . "\e[A")
    ("<down>" . "\e[B")
    ("<right>" . "\e[C")
    ("<left>" . "\e[D")
    ("RET" . "\r")
    ("DEL" . "\x7f")
    ("TAB" . "\t")
    ("C-c" . "\x03")
    ("C-d" . "\x04")
    ("C-z" . "\x1a")))

(defun kuro--send-key (key)
  "KEYをPTYに送信する。"
  (let ((bytes (cdr (assoc key kuro--key-map))))
    (if bytes
        (kuro-core-send-key kuro--core bytes)
      ;; 通常文字
      (kuro-core-send-key kuro--core key))))
```
