# BallGesture

トラックボール／マウスを使って、特定のキーを押している間だけカーソル移動をスクロールやピンチズームに変換する、macOSのメニューバー常駐アプリ。

## 使い方

- **F15 を押しながらカーソルを動かす** → スクロール（カーソル自体は動かない）。トラックボールを弾くと（高速に動かした直後に入力が一瞬途切れると）、F15を押したままでも慣性スクロールが自動的に始まる。慣性中にボールを再度動かすと即座に通常スクロールへ戻り、F15を離しても慣性はそのまま続く。もう一度F15を押すか、クリックすると慣性は止まる
- **F16 を押しながらカーソルを動かす** → ピンチズーム（拡大・縮小）

トリガーキーはメニューバーの設定画面から変更できる。

## メニューバーの設定項目

メニューバーのアイコン（手のマーク）をクリックすると開く:

- **Enabled**: アプリ全体の有効/無効
- **Accessibility access**: 実際にイベントタップが動いているかの状態表示（緑=稼働中／黄=権限待ちで自動リトライ中／赤=未許可）。未許可なら「Open Accessibility Settings」ボタンから設定画面を開ける
- **Trigger Keys**: Scroll Mode / Zoom Mode それぞれのトリガーキーを「Set Key」ボタンで再割り当て可能（押したキーがそのまま登録される。片方に使用中のキーは選べない）
- **Scroll Mode**: 自然なスクロール方向のオン/オフ、感度調整、慣性スクロール（Momentum scrolling）のオン/オフと強さ調整
- **Zoom Mode**: ズーム方式（Pinch Gesture / Ctrl+Scroll / Cmd+Scroll）、感度調整
- **Quit BallGesture**: 終了

## 必要な権限

CGEventTap でキー・マウス入力を監視するため、**アクセシビリティ権限**が必須。初回はメニューバーの案内から System Settings → Privacy & Security → Accessibility で許可する。権限が有効になれば、アプリを再起動しなくても数秒以内に自動でイベントタップが起動する。

System Settings 側のスイッチがONに見えるのに反応しない場合（`install.sh` で毎回アプリを上書きインストールしていると起こりうる）は、メニューの「Copy 'Reset Permission' Command」でコピーされる `tccutil reset Accessibility com.noki.BallGesture` をTerminalで実行し、System Settingsで権限を許可し直してからBallGestureを再起動する。

反応しないときの切り分けには `log show --predicate 'process == "BallGesture"'` が使える。トリガーキーのkeyDown/keyUp、Scroll/Zoom Modeの開始終了、イベントタップの生成成否が常時ログに出る。

## インストール

プロジェクトルートで:

```
./install.sh
```

Release ビルドを作成し、`/Applications/BallGesture.app` に上書きインストールする。

## Ice（メニューバー管理アプリ）を使っている場合

Ice など、メニューバーの表示/非表示を管理するアプリと併用している場合、BallGestureのアイコンをメニューバー上で直接ドラッグして移動させると正しく反映されないことがある。Ice側の設定画面（メニューバーレイアウト）を開いて、そこから BallGesture の表示位置を設定すること。
