# Next Finance: Gemini Enterprise & Conversational Analytics Hands-on

Gemini Notebook、Gemini Enterprise（社内文書・GWS横断検索 / モデル：`gemini-3.8-flash`）、および 4種の部門別 BigQuery データ分析エージェント（Conversational Analytics A2A 連携）を一気通貫で体験するハンズオンワークショップ資材リポジトリです。

## 🔗 クイックリンク

* **受講者用 Codelab Web ページ**:
  * **https://goo.gle/ntt-gemini** （実体： https://tichiba.github.io/next-finance-ge-handson/ ）
* **環境構築バンドル ZIP 直リンク（`next-finance-ge-handson-qwiklab.zip`）**:
  * [GitHub Pages からダウンロード](https://tichiba.github.io/next-finance-ge-handson/files/next-finance-ge-handson-qwiklab.zip)
  * [GitHub Raw からダウンロード](https://raw.githubusercontent.com/tichiba/next-finance-ge-handson/main/docs/files/next-finance-ge-handson-qwiklab.zip)

---

## 🚀 講師・ファシリテーター用：Cloud Shell 自動構築ワンライナー

Qwiklabs（`ユーザー名00` で発行された管理者用 `student-xx-...@qwiklabs.net`）または Argolis 検証環境の **Cloud Shell** を開き、以下のワンライナーを実行すると、本リポジトリから `next-finance-ge-handson-qwiklab.zip` を自動取得・展開して全環境を一括構築します：

* プロジェクト内の全 `student-xx-...@qwiklabs.net` アカウント自動検出＆IAM権限・ライセンス付与
* **Gmail / Google Chat 実データの自動配信**（初回1回の OAuth 認可により、全受講者アカウントの Gmail 受信トレイへ「東都ロジスティクス支払期日延長相談メール」を送信し、Google Chat スペース「【審査部×ビリング債権管理】与信・収納モニタリング連携」を作成して議論メッセージを投稿）
* **Gmail コネクタ（`google_mail`）・Google Chat コネクタ（`google_chat`）・社内規程 PDF データストア（`next-finance-internal-docs`）** の作成と Gemini Enterprise エンジンへの接続
  * ⚠️ Qwiklabs のユーザー（qwiklabs.net）間では Gmail が受信されないため、営業部の相談メールは **メール記録 PDF（`next_finance_sales_email_toto_logistics.pdf`）** として社内規程 PDF とあわせて `next-finance-internal-docs` に常に取り込みます。
* BigQuery 4データセット（計12テーブル）と 4部門 A2A データ分析エージェントの構築・登録

```bash
curl -fL -o next-finance-ge-handson-qwiklab.zip https://raw.githubusercontent.com/tichiba/next-finance-ge-handson/main/docs/files/next-finance-ge-handson-qwiklab.zip && unzip -q -o next-finance-ge-handson-qwiklab.zip -d handson && bash handson/tf/scripts/setup.sh
```

* **Gmail / Google Chat 実データのみを再投入したい場合**:
  ```bash
  python3 handson/tf/scripts/seed_gws_data.py --force
  ```
* **Google Chat メッセージのみを再投入・インプレース更新したい場合**:
  ```bash
  python3 handson/tf/scripts/seed_gws_data.py --chat-only --force
  ```

### 全リソース削除（クリーンアップ）コマンド

```bash
bash handson/tf/scripts/cleanup.sh
```
