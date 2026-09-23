# BallGesture

> 日本語の説明は[こちら](#日本語)にあります。

Hold a key, move your trackball, and BallGesture turns that movement into scrolling, zooming, or gestures. Release the key and your pointer behaves normally again.

It was built for trackballs, where spinning the ball is comfortable but reaching for a scroll ring or a modifier chord is not. It works with any mouse or trackpad as well.

BallGesture lives in the menu bar and has no main window.

## Requirements

- macOS 13 or later. Developed and tested on macOS 26; earlier versions should work but have not been verified.
- Apple Silicon or Intel (the released build is universal)
- Accessibility permission (required — see below)

BallGesture watches keyboard and mouse events through a `CGEventTap`, which macOS only allows with Accessibility permission. On first launch, open the menu bar icon and use the **Open Accessibility Settings** button, then allow BallGesture under System Settings → Privacy & Security → Accessibility. Once permission is granted, the event tap starts within a few seconds — no restart needed.

## Installation

### Download the app

1. Download the `.zip` from the [Releases](https://github.com/noki1213/BallGesture/releases) page.
2. Unzip it and move `BallGesture.app` into your Applications folder.
3. Open it. **macOS will refuse the first time** — see below.

BallGesture is not notarized by Apple, because notarization requires a paid Apple Developer Program membership that I do not have. macOS therefore treats it as coming from an unidentified developer and blocks the first launch. This is expected, and you have two ways past it:

- Open System Settings → Privacy & Security, scroll to the bottom, and click **Open Anyway** next to the BallGesture message. Then open the app again.
- Or clear the quarantine flag from the terminal, then open it normally:

  ```sh
  xattr -cr /Applications/BallGesture.app
  ```

Only the first launch is affected. If you would rather not rely on a binary from a stranger, build it yourself instead — that is what the next section is for.

### Build from source

Requires Xcode. No Apple Developer account needed.

```sh
git clone https://github.com/noki1213/BallGesture.git
cd BallGesture
./install.sh
```

`install.sh` builds an unsigned Release build and installs it to `/Applications`. Because you built it locally, macOS does not quarantine it and there is no first-launch prompt.

To build from the Xcode GUI instead, open `BallGesture.xcodeproj` and build the BallGesture scheme. Signing is left unset in the project, so Xcode will sign it to run locally without asking for an account.

## Usage

Each mode is bound to a trigger key. Hold the key, move the ball, release. All three keys can be reassigned from the menu bar.

### Scroll Mode — hold F15

Moving the ball scrolls instead of moving the pointer. The pointer stays where it was.

Flick the ball — move it fast and then let go — and momentum scrolling takes over, the same feel as a trackpad flick. Momentum keeps running after you release F15. Moving the ball again during momentum returns you to normal scrolling; pressing F15 again or clicking stops it.

Apps listed under **Reverse direction in these apps** scroll the other way. This helps in 3D viewers such as CAD tools and slicers, where the scroll wheel zooms and the global direction can feel backwards. The app that is frontmost when you press F15 decides the direction.

### Zoom Mode — hold F16

Moving the ball zooms in and out. Three methods are available, because applications differ in what they accept:

| Method | Sends | Works well in |
| --- | --- | --- |
| Pinch Gesture | A synthesized trackpad pinch | Preview, Photos, Maps |
| Ctrl + Scroll | Ctrl held with scroll events | System zoom, many editors |
| Cmd + Scroll | Cmd held with scroll events | Browsers, text editors |

### Gesture Mode — hold F17

Move the ball past a threshold in one direction and release. The distance required is configurable (default 50 px). A swipe has to be clearly horizontal or vertical — one axis must dominate the other by 2× — so diagonal movement does not fire the wrong action.

| Direction | Action | Sends |
| --- | --- | --- |
| Left | Back | `Cmd + [` |
| Right | Forward | `Cmd + ]` |
| Up | Mission Control | Launches Mission Control directly |
| Down | Show Desktop | `Cmd + Option + Ctrl + D` |

Left and right send the standard back/forward shortcut, so what they do depends on the front application — browsers navigate history, Finder goes back a folder.

**The Down gesture needs one-time setup.** It sends `Cmd + Option + Ctrl + D` rather than F11, because F11 is frequently intercepted by macOS or by remapping tools. Assign that combination yourself under System Settings → Keyboard → Keyboard Shortcuts → Mission Control → Show Desktop. Without that assignment, the Down gesture does nothing.

## Settings

Click the menu bar icon to open the settings popover.

| Setting | Default | Range |
| --- | --- | --- |
| Enabled | On | — |
| Trigger keys | F15 / F16 / F17 | Any key; a key already in use cannot be reused |
| Scroll sensitivity | 1.0 | 0.1 – 5.0 |
| Natural scroll direction | On | — |
| Reverse direction in these apps | None | Apps chosen from /Applications |
| Momentum scrolling | On | — |
| Momentum strength | 0.5 | 0.0 – 1.0 |
| Zoom sensitivity | 1.0 | 0.1 – 5.0 |
| Zoom method | Pinch Gesture | Pinch / Ctrl+Scroll / Cmd+Scroll |
| Gesture distance | 50 px | 10 – 200 px |

The popover also shows live Accessibility status: green when the event tap is running, yellow while waiting for permission and retrying, red when permission is denied.

Settings are stored in `~/Library/Preferences/com.noki.BallGesture.plist`.

## Security and Privacy

BallGesture reads keyboard and mouse events, so it is worth being explicit about what it does with them.

- **No network access.** The app contains no networking code at all. Nothing is uploaded, and there is no telemetry, analytics, or crash reporting.
- **Nothing is recorded.** Events are inspected in memory to decide whether a trigger key is held, then discarded. No keystroke or pointer data is written to disk.
- **The only thing stored** is your settings, in the plist file listed above.
- **Accessibility permission** is required because macOS gates event taps behind it. This is the same permission used by tools like Karabiner-Elements and Mac Mouse Fix.

The source is here in full, so you can verify all of this rather than take my word for it.

## Known Limitations

- **Only tested on macOS 26.** The app is built for macOS 13 and later and uses nothing newer, but I have no older machines to test on, so behaviour there is unverified.
- **Not notarized.** See the installation section. Without a paid Apple Developer account the first launch has to be approved manually.
- **Mac Mouse Fix.** I use BallGesture alongside Mac Mouse Fix and have not run into problems, but the two have not been tested together exhaustively. Both apps intercept and re-emit mouse events, so conflicts are possible in configurations I have not tried. If the pointer behaves oddly during a mode, quit Mac Mouse Fix to check whether it is involved.
- **Zoom depends on the application.** No zoom method works everywhere. If one does nothing in a given app, try another.
- **Secure input fields.** While macOS secure input is active — a password field, for example — event taps are suppressed system-wide and the trigger keys will not respond. This affects all event-tap-based tools, not just this one.

## Troubleshooting

**The menu bar icon does not appear.** If you use a menu bar manager such as Ice or Bartender, a newly added icon is often placed in the hidden section, which looks identical to the app failing to launch. Open the manager's layout settings and move BallGesture to the visible section. Dragging the icon directly on the menu bar can fail with these tools, so use their own settings screen.

**The trigger keys do nothing even though Accessibility is switched on.** Rebuilding an unsigned app changes its signature, and macOS may keep the old, now-mismatched permission entry. Reset it and grant it again:

```sh
tccutil reset Accessibility com.noki.BallGesture
```

Then re-enable BallGesture in System Settings and restart it. The menu bar popover has a **Copy 'Reset Permission' Command** button that copies this line for you.

**Working out what is happening.** BallGesture logs trigger key presses, mode transitions, and event tap creation:

```sh
log show --predicate 'process == "BallGesture"' --last 5m
```

## License

MIT License. See [LICENSE](LICENSE).

---

<a id="日本語"></a>

# BallGesture（日本語）

キーを押している間だけ、トラックボールの動きをスクロール・ズーム・ジェスチャーに変換する macOS アプリです。キーを離せばポインタは元の動作に戻ります。

トラックボールのために作りました。ボールを回すのは快適なのに、スクロールリングに指を伸ばしたり修飾キーを押さえたりするのは快適ではない、という不満が出発点です。普通のマウスやトラックパッドでも動きます。

メニューバーに常駐し、メインウィンドウはありません。

## 動作環境

- macOS 13 以降。開発と動作確認は macOS 26 で行っています。それより古いバージョンでも動作するはずですが、検証はしていません。
- Apple Silicon / Intel（配布しているアプリは両対応）
- アクセシビリティ権限（必須）

BallGesture は `CGEventTap` でキーボードとマウスのイベントを監視しますが、macOS はこれをアクセシビリティ権限がある場合にしか許可しません。初回はメニューバーアイコンを開き **Open Accessibility Settings** ボタンから、システム設定 → プライバシーとセキュリティ → アクセシビリティ で BallGesture を許可してください。許可すれば数秒以内に自動でイベントタップが起動するので、アプリの再起動は不要です。

## インストール

### アプリをダウンロードする

1. [Releases](https://github.com/noki1213/BallGesture/releases) から `.zip` をダウンロードします。
2. 展開して、`BallGesture.app` をアプリケーションフォルダに入れます。
3. 開きます。**初回は macOS に拒否されます**（下記参照）。

BallGesture は Apple の公証（notarization）を受けていません。公証には有料の Apple Developer Program のメンバーシップが必要で、私が持っていないためです。そのため macOS は「開発元が未確認のアプリ」として初回起動をブロックします。これは想定どおりの動作で、通す方法が2つあります。

- システム設定 → プライバシーとセキュリティ を開き、一番下までスクロールして、BallGesture についてのメッセージの横にある **このまま開く** をクリックします。そのあともう一度アプリを開いてください。
- またはターミナルで隔離属性を外してから、普通に開きます。

  ```sh
  xattr -cr /Applications/BallGesture.app
  ```

影響があるのは初回だけです。知らない人が作ったバイナリを実行したくない場合は、次のセクションの方法で自分でビルドしてください。

### ソースからビルドする

Xcode が必要です。Apple Developer アカウントは不要です。

```sh
git clone https://github.com/noki1213/BallGesture.git
cd BallGesture
./install.sh
```

`install.sh` は未署名の Release ビルドを作成して `/Applications` にインストールします。自分でビルドしたアプリは macOS に隔離されないため、初回起動の確認は出ません。

Xcode の画面からビルドする場合は、`BallGesture.xcodeproj` を開いて BallGesture スキームをビルドしてください。プロジェクト側で署名の設定を空にしてあるので、アカウントを求められることなくローカル実行用の署名が付きます。

## 使い方

各モードにトリガーキーが割り当てられています。キーを押しながらボールを動かし、離す、という操作です。3つのキーはすべてメニューバーから変更できます。

### Scroll Mode — F15 を押しながら

ボールを動かすとポインタではなく画面がスクロールします。ポインタはその場に固定されます。

ボールを弾く（勢いよく動かしてすぐ放す）と慣性スクロールに移行します。トラックパッドでフリックしたときと同じ感触です。慣性は F15 を離した後も続きます。慣性中にボールを動かせば通常のスクロールに戻り、F15 をもう一度押すかクリックすれば止まります。

**Reverse direction in these apps** に登録したアプリでは、スクロールの向きが逆になります。CAD やスライサーなど、スクロールで拡大縮小する 3D 画面で向きが逆に感じるときに使います。F15 を押した瞬間に最前面にあるアプリで向きが決まります。

### Zoom Mode — F16 を押しながら

ボールを動かすと拡大・縮小します。アプリによって受け付ける方式が違うため、3種類から選べます。

| 方式 | 送るもの | 相性の良いアプリ |
| --- | --- | --- |
| Pinch Gesture | トラックパッドのピンチを合成 | プレビュー、写真、マップ |
| Ctrl + Scroll | Ctrl を押しながらのスクロール | システムズーム、多くのエディタ |
| Cmd + Scroll | Cmd を押しながらのスクロール | ブラウザ、テキストエディタ |

### Gesture Mode — F17 を押しながら

一定距離以上ボールを動かして離すと、その方向に応じた操作が実行されます。距離は変更できます（初期値 50 px）。斜めの動きで誤爆しないよう、片方の軸がもう片方の 2 倍以上動いていないと発動しません。

| 方向 | 動作 | 送るもの |
| --- | --- | --- |
| 左 | 戻る | `Cmd + [` |
| 右 | 進む | `Cmd + ]` |
| 上 | Mission Control | Mission Control を直接起動 |
| 下 | デスクトップを表示 | `Cmd + Option + Ctrl + D` |

左右は標準の「戻る／進む」ショートカットを送るので、実際の動作は最前面のアプリ次第です。ブラウザなら履歴を移動し、Finder なら1つ前のフォルダに戻ります。

**下方向だけは最初に設定が必要です。** F11 ではなく `Cmd + Option + Ctrl + D` を送っています。F11 は macOS 自体やキー変更ツールに横取りされることが多いためです。システム設定 → キーボード → キーボードショートカット → Mission Control → デスクトップを表示 に、この組み合わせを自分で割り当ててください。割り当てていない場合、下方向のジェスチャーは何も起こりません。

## 設定項目

メニューバーのアイコンをクリックすると設定画面が開きます。

| 設定 | 初期値 | 範囲 |
| --- | --- | --- |
| Enabled | オン | — |
| トリガーキー | F15 / F16 / F17 | 任意のキー。他のモードで使用中のキーは選択不可 |
| スクロール感度 | 1.0 | 0.1 – 5.0 |
| ナチュラルスクロール方向 | オン | — |
| 向きを逆にするアプリ | なし | /Applications から選択 |
| 慣性スクロール | オン | — |
| 慣性の強さ | 0.5 | 0.0 – 1.0 |
| ズーム感度 | 1.0 | 0.1 – 5.0 |
| ズーム方式 | Pinch Gesture | Pinch / Ctrl+Scroll / Cmd+Scroll |
| ジェスチャー距離 | 50 px | 10 – 200 px |

アクセシビリティの状態も表示されます。緑はイベントタップ稼働中、黄は権限待ちで自動リトライ中、赤は未許可です。

設定は `~/Library/Preferences/com.noki.BallGesture.plist` に保存されます。

## セキュリティとプライバシー

キーボードとマウスの入力を読むアプリなので、それをどう扱っているかを明示しておきます。

- **ネットワーク通信は一切しません。** ネットワーク関連のコードがそもそも含まれていません。送信されるものはなく、テレメトリも解析も、クラッシュレポートの送信もありません。
- **入力は記録しません。** イベントはトリガーキーが押されているかを判定するためだけにメモリ上で参照し、そのまま破棄します。キー入力やポインタの情報をディスクに書き出すことはありません。
- **保存しているのは設定だけ**で、上に書いた plist ファイルに入っています。
- **アクセシビリティ権限が必要な理由**は、macOS がイベントタップをこの権限の下に置いているためです。Karabiner-Elements や Mac Mouse Fix が要求するものと同じ権限です。

ソースコードは全て公開されているので、以上は実際に確認できます。

## 既知の制限

- **動作確認は macOS 26 でのみ行っています。** macOS 13 以降向けにビルドしており、それより新しい機能は使っていませんが、古い環境が手元にないため実際の挙動は未検証です。
- **公証を受けていません。** インストールの項を参照してください。有料の Apple Developer アカウントが無いため、初回起動を手動で許可する必要があります。
- **Mac Mouse Fix との併用。** 私自身が併用していて問題が出たことはありませんが、網羅的に検証はしていません。どちらもマウスイベントを横取りして再送出するアプリなので、試していない設定では衝突が起きる可能性があります。モード中にポインタの挙動がおかしいときは、Mac Mouse Fix を終了させて切り分けてみてください。
- **ズームはアプリに依存します。** どの方式でも全アプリで動くわけではありません。効かない場合は別の方式を試してください。
- **セキュア入力中は反応しません。** パスワード欄などで macOS のセキュア入力が有効になっている間は、イベントタップがシステム全体で抑制されるためトリガーキーが効きません。これはイベントタップを使うツール全般に共通の挙動です。

## うまくいかないとき

**メニューバーにアイコンが出ない。** Ice や Bartender などのメニューバー管理アプリを使っている場合、新しく増えたアイコンは隠し領域に入れられることが多く、起動に失敗したように見えます。管理アプリ側のレイアウト設定を開いて、BallGesture を表示領域に移動してください。メニューバー上でアイコンを直接ドラッグする操作はこれらのツールと相性が悪いため、設定画面から行うのが確実です。

**アクセシビリティがオンなのにトリガーキーが効かない。** 未署名アプリはビルドし直すたびに署名が変わるため、macOS が古い権限エントリを保持したままになることがあります。次のコマンドでリセットしてから許可し直してください。

```sh
tccutil reset Accessibility com.noki.BallGesture
```

その後システム設定で BallGesture を許可し直し、アプリを再起動します。メニューの **Copy 'Reset Permission' Command** ボタンでこの行をコピーできます。

**何が起きているか調べる。** トリガーキーの押下、モードの開始と終了、イベントタップの生成可否がログに出ます。

```sh
log show --predicate 'process == "BallGesture"' --last 5m
```

## ライセンス

MIT License です。[LICENSE](LICENSE) を参照してください。
