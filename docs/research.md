# 実装前の調査

## 対象と方針

確認環境：Apple M4、32GB、macOS 15.8.1、Swift 6.2.4、Command Line Toolsのみ。
選定した暗いGlass案を基本とし、密集した3メーター、電池履歴、下の一時ターミナルを256pt幅に配置する。

## 調査結果

| 要素 | 採用経路 | 確認・限界 |
|---|---|---|
| メニューバー | AppKit `NSStatusItem` | Annoying Dogの白黒ドットを4フレーム切り替え。白い体と黒い輪郭 |
| 展開パネル | `NSPopover` | `contentSize`変更による下部端末の展開 |
| CPU | Mach `host_statistics` | 2つの累積値の差分。初回・カウンタ巻き戻りを未計測とする |
| メモリ | `host_statistics64`と`hw.memsize` | 回収可能キャッシュを差し引く推定 |
| プロセス | `proc_listallpids` / `proc_pid_rusage` | PID開始時刻も比較してPID再利用による誤差を防止。権限で読めない行を除外 |
| GPU全体 | IOKit / IOAccelerator / PerformanceStatistics | この実機で`Device Utilization %`取得成功。root不要。OS更新の互換性保証なし |
| 電池 | IOPowerSources | 残量と充電状態を取得。独自の履歴を保存 |
| ターミナル | SwiftTerm 1.20.0 / PTY / zsh | ANSI・対話入力を実装済みのライブラリを利用。版を固定 |
| 外観 | NSVisualEffectView / 不透明なMaterialテーマ | OS 15対応を優先。Liquid Glass専用APIとは区別 |

GPUの取得は独自実装であり、他の監視アプリのソースは複製していない。非公開IOReportフレームワーク・sudo・常駐特権ヘルパーは使わない。

プロセス別GPUの公開取得経路は今回のSDKで確立できていない。最新の要望でプロセス一覧の収集・表示は削除した。実測していないGPU値や「エネルギー影響」は表示しない。

## 一次資料

- [Apple: NSStatusBar](https://developer.apple.com/documentation/appkit/nsstatusbar)
- [Apple: NSPopover.contentSize](https://developer.apple.com/documentation/appkit/nspopover/contentsize)
- [Apple: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Google: Material 2 Elevation](https://m2.material.io/design/environment/elevation.html)
- [Apple: IOPowerSources](https://developer.apple.com/documentation/iokit/iopowersources_h)
- [Apple: kIOPSCurrentCapacityKey](https://developer.apple.com/documentation/iokit/kiopscurrentcapacitykey)
- [Apple OSS: libproc.h](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.h)
- [Apple: openpty / forkpty](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/openpty.3.html)
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm/tree/v1.20.0)
- [Stats開発者によるGPUドライバ報告値についての説明](https://github.com/exelban/stats/issues/2130)

## 最終UIへの反映

最新の指定に合わせ、プロセス欄は収集コードごと削除し、幅を256ptへ縮小。テーマ・明暗の操作は歯車メニューに集約した。Annoying Dogの参照先として[UNDERTALE公式ページ](https://undertale.com/alarmclock/)を確認し、メニューバー向けに白黒の走行フレームを描き起こした。

依存するSwiftTermはパッケージ済みアプリの`Contents/Resources/SwiftTerm_SwiftTerm.bundle`を明示的に探索する。リソースはこの正規の位置に同梱し、アプリのルートには置かない。再ビルド時は生成済みアプリのみ作り直し、依存側の読み取り専用ファイルに上書きしようとして失敗する問題を避ける。
