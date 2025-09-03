# Mastodonローカル検証環境構築スクリプト
Mastodon Botの検証などの目的で、自身のPC(ローカル)になんちゃってMastodonサーバーを構築するためのシェルスクリプトです。
皆大好き[某記事](https://compositecomputer.club/blog/78X77BgSPkxeEkcD9eewjX)を参考に、Mastodon等のアップデートに伴う変更や、ほんの少しの僕の主観を加えました。
**多分Ubuntuでしか動きません**。WSLでもOK。

## 使い方
1. [シェルスクリプト本体](./mastodon_testenv_build.sh)を、コピペなりダウンロードなりお好きな方法で良い感じの場所に置きます。
2. 以下のコマンドで実行します。ファイル名を変更した場合は読み替えて下さい。
  ```bash
  $ bash mastodon_testenv_build.sh
  ```
3. [記事](https://compositecomputer.club/blog/78X77BgSPkxeEkcD9eewjX)を参考にしたりしながら、表示される指示に従って下さい。WSLの場合はWindows側で行う作業もあるので注意。

## 注意事項
- なるべく気を付けてはいますが、1回目に失敗したなどの理由で2回以上実行すると意図しない動作をする可能性があります。
- 途中で全く動かない画面を数分～数十分見詰める必要があります。改善したい。
- **使用は自己責任でお願いします**。なるべく安全なように気を付けてはいますが、作者はアホです。

## 連絡先
不具合や機能提案などのご連絡は[Twitter(現X)](https://x.com/boku_renraku)やその他までお気軽に。
