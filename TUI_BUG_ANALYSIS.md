# Kuro TUI Rendering Bug Analysis

## 概要

KuroターミナルエミュレータのTUIレンダリング安定性に関する包括的なバグ分析レポート。

---

## 1. レンダリング関連のバグ

### 1.1 レースコンディション: PTY読み取りとレンダリングの競合

**場所**: `rust-core/src/pty/reader.rs` + `emacs-lisp/kuro-renderer.el`

**問題**:
- PTYリーダースレッドは別スレッドで動作し、`crossbeam_channel::Sender`経由でデータを送信
- Emacsのレンダリングループ(`kuro--render-cycle`)は60fpsでポーリング
- この間に適切な同期機構がない

**影響**:
- 高速出力時にフレーム間でデータが欠落する可能性
- 行の部分的な更新が表示される可能性

```rust
// pty/reader.rs:24-36
while !shutdown.load(Ordering::Relaxed) {
    match master.read(&mut buffer) {
        Ok(n) => {
            let data = Vec::from(&buffer[..n]);
            if sender.send(data).is_err() { ... }
        }
        ...
    }
}
```

### 1.2 タイマーベースのレンダリングの問題

**場所**: `emacs-lisp/kuro-renderer.el:60-75`

**問題**:
```elisp
(setq kuro-timer
      (run-with-timer
       0
       (/ 1.0 kuro-frame-rate)  ; 60fps = ~16ms間隔
       (lambda () ...)))
```

- 16ms間隔は保証されない（Emacsのイベントループ依存）
- 大量の出力時にバックログが蓄積
- ストリーミングアイドルタイマーと競合する可能性

### 1.3 col_to_bufマッピングの同期問題

**場所**: `emacs-lisp/kuro-renderer.el:221-222`

**問題**:
```elisp
(when (vectorp col-to-buf)
  (setq kuro--col-to-buf col-to-buf))
```

- このベクターは全行で共有されている
- 複数行更新時に前の行のマッピングが上書きされる
- カーソル位置計算で間違ったオフセットが使用される可能性

---

## 2. スクロール/リージョン関連のバグ

### 2.1 スクロールリージョン境界でのカーソル位置

**場所**: `rust-core/src/grid/screen.rs:232-242`

**問題**:
```rust
pub fn line_feed(&mut self) {
    let screen = self.active_screen_mut();
    let new_row = screen.cursor.row + 1;

    if new_row >= screen.scroll_region.bottom {
        screen.scroll_up(1);  // カーソル行は変わらない
    } else {
        screen.cursor.row = new_row;
    }
}
```

- スクロールリージョンbottomにいる時、LFでカーソルが動かない
- 一部のTUIアプリはこれを期待しない可能性

### 2.2 スクロールバックビューポートの同期

**場所**: `rust-core/src/grid/screen.rs:792-820`

**問題**:
```rust
pub fn viewport_scroll_up(&mut self, n: usize) {
    if self.is_alternate_active { return; }
    let new_offset = (self.scroll_offset + n).min(self.scrollback_line_count);
    ...
}
```

- ビューポートスクロール中に新しい出力があった場合の処理が不透明
- `scroll_dirty`フラグがEmacs側で適切に処理されていない可能性

### 2.3 代替スクリーンバッファ切り替え時の状態

**場所**: `rust-core/src/grid/screen.rs:596-617`

**問題**:
- 代替スクリーンへの切り替え時に保存されるのはカーソル位置とスクロールリージョンのみ
- SGR属性、タブストップ、DECモードの一部は保存されない
- vimなどを終了した時に元の状態が完全に復元されない可能性

---

## 3. Unicode/CJK関連のバグ

### 3.1 剛距離文字の折り返し

**場所**: `rust-core/src/grid/screen.rs:153-229`

**問題**:
```rust
// 文字が行に収まらない場合
} else {
    screen.cursor.col = 0;
    screen.line_feed();
    // 次の行に印刷
    ...
}
```

- 幅2文字が行末で折り返す時、正しく処理されないエッジケース
- 特にcol=cols-1にいる時に幅2文字を印刷しようとした場合

### 3.2 結合文字の処理

**場所**: `rust-core/src/parser/vte_handler.rs:13-31`

**問題**:
```rust
if UnicodeWidthChar::width(c) == Some(0) {
    let (row, col) = if cursor.col > 0 {
        (cursor.row, cursor.col - 1)
    } else if cursor.row > 0 {
        let prev_row = cursor.row - 1;
        let last_col = self.screen.cols().saturating_sub(1) as usize;
        (prev_row, last_col)
    } else {
        return;  // 捨てられる！
    };
    ...
}
```

- (0, 0)で結合文字が来た場合、破棄される
- 前の行にまたがる結合文字の処理が不完全

### 3.3 Wide Placeholderの整合性

**場所**: `rust-core/src/grid/screen.rs:178-184`

**問題**:
- 幅2文字の印刷時にplaceholderを作成するが、削除/挿入操作で整合性が壊れる可能性
- `delete_chars`と`insert_chars`には修正ロジックがあるが、他の操作（erase等）にはない

---

## 4. エスケープシーケンス関連のバグ

### 4.1 SGR属性のリセット問題

**場所**: `rust-core/src/parser/sgr.rs` + `rust-core/src/parser/erase.rs`

**問題**:
```rust
// erase.rs:41-44
for c in col..line.cells.len() {
    line.cells[c] = Default::default();  // SGR背景色を使わない
}
```

- ED/ELで消去する際、現在のSGR背景色を使わずデフォルト色で消去
- BCE (Background Color Erase) が実装されていない
- 多くのターミナルアプリは背景色を維持したまま消去する

### 4.2 不完全なシーケンスの処理

**場所**: `rust-core/src/parser/vte_handler.rs`

**問題**:
- VTEクレートが不完全なシーケンスをどのように処理するか不明確
- PTYからバイト列が分割されて届いた場合の動作

### 4.3 DSR (Device Status Report) の非同期性

**場所**: `rust-core/src/parser/csi.rs:99-115`

**問題**:
```rust
fn csi_dsr(term: &mut crate::TerminalCore, params: &vte::Params) {
    if code == 6 {
        let response = format!("\x1b[{};{}R", row, col);
        term.pending_responses.push(response.into_bytes());
    }
}
```

- `pending_responses`に溜まったレスポンスがいつPTYに書き込まれるか
- 複数のDSRが連続した場合の処理

---

## 5. Emacs Lisp側のバグ

### 5.1 行更新時のバッファライン数同期

**場所**: `emacs-lisp/kuro-renderer.el:240-268`

**問題**:
```elisp
(defun kuro--update-line (row text)
  (let ((not-moved (forward-line row)))
    (when (> not-moved 0)
      ;; バッファに行が足りない場合、追加
      ...
    )))
```

- `forward-line`が失敗した時、追加の改行を挿入
- この間に他の更新が入ると不整合が起きる可能性

### 5.2 ウィンドウリサイズのレースコンディション

**場所**: `emacs-lisp/kuro.el:49-87` + `emacs-lisp/kuro-renderer.el:101-132`

**問題**:
- `window-size-change-functions`フックとレンダーサイクルの両方でリサイズ処理
- 競合して二重リサイズやサイズ不整合が起きる可能性

### 5.3 カーソル位置更新の競合

**場所**: `emacs-lisp/kuro-renderer.el:271-332`

**問題**:
```elisp
(defun kuro--update-cursor ()
  (unless (> kuro--scroll-offset 0)
    (let ((cursor-pos (kuro--get-cursor)))
      ...
      (set-window-point win target-pos))))
```

- 複数のウィンドウで同じバッファを表示している場合の動作
- `set-window-start`と`set-window-point`の順序依存

---

## 6. テストパターン

### 6.1 高速出力テスト
```bash
# 大量の出力を素早く生成
yes "test line" | head -1000
for i in {1..100}; do echo "line $i"; done
```

### 6.2 スクロールリージョンテスト
```bash
# スクロールリージョンを設定して出力
printf '\e[5;10r'  # リージョン設定
for i in {1..20}; do echo "line $i"; done
printf '\e[r'      # リセット
```

### 6.3 幅広文字テスト
```bash
# CJK文字の折り返し
echo "日本語テスト日本語テスト日本語テスト日本語テスト"
echo "🎉🎊🎁🎉🎊🎁🎉🎊🎁🎉🎊🎁"
```

### 6.4 エスケープシーケンスストレステスト
```bash
# 色変更を高速で繰り返す
for i in {0..255}; do printf "\e[38;5;${i}mColor $i\e[0m\n"; done
```

### 6.5 カーソル位置ストレステスト
```bash
# 高速でカーソル位置を変更
for i in {1..100}; do
  printf "\e[${i};${i}H"
  echo "pos $i"
done
```

---

## 7. 推奨されるテスト環境

### Emacs Daemon起動
```bash
# Emacs daemonを起動
emacs --daemon=kuro-test

# emacsclientで接続してテスト
emacsclient -s kuro-test --eval '(message "connected")'
```

### テスト実行コマンド
```elisp
;; kuro-test.el に追加すべきテストパターン
(ert-deftest kuro-test-fast-output ()
  "高速出力テスト"
  (with-temp-buffer
    (kuro-mode)
    (kuro--send-key "for i in {1..100}; do echo \"line $i\"; done\n")
    (sit-for 1)
    (should (> (count-lines (point-min) (point-max)) 50))))

(ert-deftest kuro-test-scroll-region ()
  "スクロールリージョンテスト"
  ...)
```

---

## 8. 優先度別バグ一覧

### Critical（即座に修正すべき）
1. レースコンディション: PTY読み取りとレンダリング
2. BCE未実装による表示崩れ

### High（次のリリースで修正すべき）
1. col_to_bufマッピングの同期問題
2. スクロールリージョン境界での挙動
3. 幅広文字の折り返し処理

### Medium（改善すべき）
1. 結合文字の(0,0)での破棄
2. タイマーベースのレンダリング精度
3. 代替スクリーン切り替え時の状態保存

### Low（将来的な改善）
1. DSRの非同期処理
2. 複数ウィンドウ表示への対応

---

## 9. 実テストで発見したバグ（2024-03-18）

emacsclient経由でkuroをテストした際に発見したバグ。

### 9.1 Critical: Unknown message type handling

**現象**:
```
*ERROR*: Unknown message: -
*ERROR*: Unknown message: print-nonl &_&_&_&_&_&_&_&_&_&_&_&_&_&_&_&_...
*ERROR*: Unknown message: -p
*ERROR*: Unknown message: rint-nonl &_&_&_&_&_&_&_&_&_&_&_&_&_&_&_&_...
```

**原因推定**:
- `rust-core/src/ffi/bridge/render.rs`の`kuro_render_get_pending_output`が返すメッセージ形式
- Emacs側が未知のメッセージタイプを受信
- `print-nonl`メッセージタイプがEmacs側で定義されていない

**影響**:
- ほぼ全てのコマンド出力でエラーが発生
- 画面に`&`文字が大量に表示される
- ターミナルとして実用にならない

**修正場所**:
- `emacs-lisp/kuro-renderer.el`: `kuro--process-message`関数
- `rust-core/src/ffi/bridge/render.rs`: メッセージシリアライズ

### 9.2 Critical: ANSI Color sequences not parsed

**現象**:
```
printf '\033[31mRed\033[0m \033[32mGreen\033[0m'
# 期待: Red Green (色付き)
# 実際: mRedm mGreenm (色なし、ゴミ付き)
```

**原因推定**:
- CSI SGRシーケンスがパーサーを通っていない
- またはEmacs側で正しくデシリアライズされていない

**影響**:
- 全ての色付き出力が正しく表示されない
- ls --color、grep --color等が使えない

**修正場所**:
- `rust-core/src/parser/sgr.rs`: SGRパース検証
- `rust-core/src/parser/vte_handler.rs`: Perform trait実装

### 9.3 High: Cursor positioning ignored

**現象**:
```
tput cup 5 10 && echo 'Positioned'
# 期待: 行5列10に"Positioned"と表示
# 実際: 行5列10に表示されるが、カーソル位置が更新されない可能性
```

**原因推定**:
- `rust-core/src/parser/csi.rs`のCUP (CSI n;m H)ハンドラー
- Emacs側の`kuro--update-cursor`との同期

### 9.4 High: Long line wrapping artifacts

**現象**:
```
printf '%200s\n' | tr ' ' 'x'
# 200文字のxが表示されるはずだが、&文字が混入
```

**原因推定**:
- 長い行の折り返し時にレンダリングメッセージが壊れる
- `kuro--update-line`の行追加ロジック

### 9.5 Medium: Tab handling issues

**現象**:
```
printf '\tindented'
# 期待: タブ幅分インデントされて"indented"
# 実際: "indented"のみ表示（タブが処理されていない可能性）
```

**原因推定**:
- `rust-core/src/grid/screen.rs`の`print_char`でのタブ処理
- またはEmacs側でのタブ展開

---

## 10. デバッグ手順

### 10.1 Emacs daemonでテスト

```bash
# Daemon起動
emacs --daemon=kuro-test --eval "(setq server-socket-dir \"~/.emacs.d/server\")"

# kuroロード
emacsclient -s ~/.emacs.d/server/kuro-test --eval "
(progn
  (add-to-list 'load-path \"/path/to/kuro/emacs-lisp\")
  (setenv \"KURO_MODULE_PATH\" \"/path/to/kuro/target/release\")
  (require 'kuro)
  (kuro-create \"/bin/bash\"))"

# テスト実行
emacsclient -s ~/.emacs.d/server/kuro-test --eval "
(progn
  (set-buffer \"*kuro*\")
  (kuro-send-string \"echo test\n\")
  (sit-for 0.5)
  (buffer-substring-no-properties (point-min) (point-max)))"
```

### 10.2 Rust側のデバッグ

```bash
# デバッグビルド
RUST_LOG=debug cargo build

# ログ出力を確認
RUST_LOG=kuro=debug emacs -Q --eval "(require 'kuro) (kuro-create \"/bin/bash\")"
```

### 10.3 FFIトレース

```elisp
;; emacs-lisp/kuro-renderer.el に追加
(defadvice kuro--render-cycle (before trace-ffi activate)
  (let ((output (kuro-render-get-pending-output kuro--handle)))
    (when (> (length output) 0)
      (message "FFI output: %S" (substring output 0 (min 100 (length output)))))))
```
