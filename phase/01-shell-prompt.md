# フェーズ 01: シェルプロンプト表示

## 目的

Emacsバッファにシェルプロンプトを表示する。これはコアアーキテクチャと基本I/O機能を確立する基盤となるフェーズである。

**期間:** Week 1

## ドキュメントリンク

- [Grid仕様](../docs/reference/rust-core/grid.md) - Screen, Cell, Cursor型
- [FFIインターフェース](../docs/reference/rust-core/ffi-interface.md) - Emacs動的モジュールインターフェース
- [データフロー](../docs/reference/data-flow.md) - エンドツーエンドのデータフロー

## 実装方針

### Rust実装

| コンポーネント | 説明 |
|---------------|------|
| PTY管理 | `nix`クレートを使用してシェルプロセスをfork/exec |
| Grid初期化 | デフォルト24x80サイズで`Screen`を作成 |
| FFIブリッジ | emacs-module-rs経由で`kuro_core_new()`関数をエクスポート |

**主要関数:**
- `TerminalCore::new(rows, cols)` - 端末状態の初期化
- `kuro_core_new()` - Elisp用FFIブリッジ関数

### Elisp実装

| コンポーネント | 説明 |
|---------------|------|
| バッファ設定 | 端末出力用の専用バッファを作成 |
| レンダーループ | 30fpsでのタイマーベースポーリング |
| キーマッピング | 基本的なキーボードからPTYバイトへの変換 |

**主要関数:**
- `kuro--render-loop` - タイマー駆動レンダーサイクル
- `kuro--start-render-loop` / `kuro--stop-render-loop` - ライフサイクル管理

## タスク

- [ ] **プロジェクト構造のセットアップ**
  - [ ] Cargoワークスペース設定
  - [ ] Elispパッケージ構造 (kuro.el, kuro-core.el)
  - [ ] ビルドシステム (Makefile)

- [ ] **Gridモジュール実装**
  - [ ] linesベクタを持つ`Screen`構造体
  - [ ] 文字と属性を持つ`Cell`構造体
  - [ ] 位置追跡を持つ`Cursor`構造体
  - [ ] 変更追跡用の`dirty_set`

- [ ] **PTY管理**
  - [ ] `nix::pty`を使用してシェルプロセスをfork
  - [ ] ノンブロッキング読み取りの設定
  - [ ] プロセスライフサイクルの処理

- [ ] **FFIブリッジ**
  - [ ] `kuro_core_new()` - TerminalCore作成
  - [ ] `kuro_core_poll_updates()` - ダーティ行の取得
  - [ ] `kuro_core_clear_dirty()` - ダーティフラグのクリア
  - [ ] `emacs::module`によるモジュール初期化

- [ ] **Elispレンダーループ**
  - [ ] タイマーベースポーリング (30fps)
  - [ ] ポーリング結果からのバッファ更新
  - [ ] PTYへの基本キー送信

## 受け入れ条件

### 手動テスト手順

#### テスト1: シェルプロンプトの可視性

1. Emacsを起動
2. `M-x kuro`を実行
3. バッファにシェルプロンプトが表示されることを確認

**期待結果:** バッファ作成後1秒以内にシェルプロンプトが表示される。

#### テスト2: 基本I/O

1. kuroバッファで`echo test`と入力
2. Enterを押す
3. 次の行に"test"が表示されることを確認
4. 出力後に新しいプロンプトが表示されることを確認

**期待結果:**
- コマンドが入力通りにエコーされる
- 出力"test"が正しく表示される
- 新しいプロンプトが表示される

#### テスト3: リサイズ処理

1. ウィンドウでkuroを起動
2. Emacsウィンドウをリサイズ
3. 端末コンテンツが調整されることを確認

**期待結果:** リサイズ後、端末コンテンツが保持され、適切に配置される。

## 依存関係

**なし** - これが最初のフェーズである。

## 次のフェーズ

完了後、以下が有効になる:
- フェーズ 02: 基本テキスト出力
- フェーズ 03: コマンドライン編集
- フェーズ 04: 基本色

## 技術ノート

### PTY Forkプロセス

```rust
use nix::pty::{forkpty, ForkptyResult};
use nix::unistd::{execvp, close};

fn spawn_shell() -> Result<ForkptyResult> {
    let result = forkpty(None, None)?;

    match result.forkpty_result {
        ForkptyResult::Parent { child, master } => {
            // 親: 読み取り用にmaster fdを返す
            Ok(result)
        }
        ForkptyResult::Child => {
            // 子: シェルを実行
            execvp("/bin/bash", &["bash"])?;
            unreachable!()
        }
    }
}
```

### Grid構造

```rust
struct Screen {
    lines: Vec<Line>,
    cursor: Cursor,
    dirty_set: HashSet<usize>,
    cols: usize,
    rows: usize,
}

struct Cell {
    c: char,
    fg: Color,
    bg: Color,
    // 属性...
}
```

### Elispレンダーループ

```elisp
(defvar kuro--render-timer nil)

(defun kuro--start-render-loop ()
  (setq kuro--render-timer
        (run-with-timer 0 (/ 1.0 30)  ; 30fps
                        #'kuro--render-cycle)))

(defun kuro--render-cycle ()
  (when-let ((updates (kuro-core-poll-updates kuro--core)))
    (kuro--apply-updates updates)
    (kuro-core-clear-dirty kuro--core)))
```
