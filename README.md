# Next Finance: Gemini Enterprise & Conversational Analytics Hands-on

Gemini Notebook、Gemini Enterprise（社内文書・GWS横断検索 / モデル：`gemini-3.8-flash`）、および 4種の部門別 BigQuery データ分析エージェント（Conversational Analytics A2A 連携）を一気通貫で体験するハンズオンワークショップ資材リポジトリです。

## 🔗 クイックリンク

* **ハンズオン Codelab Web ページ（GitHub Pages）**:
  * https://tichiba.github.io/next-finance-ge-handson/
* **環境構築バンドル ZIP 直リンク（`next-finance-ge-handson-qwiklab.zip`）**:
  * [GitHub Pages からダウンロード](https://tichiba.github.io/next-finance-ge-handson/files/next-finance-ge-handson-qwiklab.zip)
  * [GitHub Raw からダウンロード](https://raw.githubusercontent.com/tichiba/next-finance-ge-handson/main/docs/files/next-finance-ge-handson-qwiklab.zip)

---

## 🚀 講師・ファシリテーター用：Cloud Shell 自動構築ワンライナー

Qwiklabs（`User 1` / `user00`）または Argolis 検証環境の **Cloud Shell** を開き、以下のワンライナーを実行すると、本リポジトリから `next-finance-ge-handson-qwiklab.zip` を自動取得・展開して全環境（11アカウント権限、BigQuery 4データセット・計12テーブル、社内規程データストア、Gemini Enterprise アプリ、4部門 A2A データ分析エージェント）を一括構築します。

```bash
curl -fL -o next-finance-ge-handson-qwiklab.zip https://raw.githubusercontent.com/tichiba/next-finance-ge-handson/main/docs/files/next-finance-ge-handson-qwiklab.zip && unzip -q -o next-finance-ge-handson-qwiklab.zip -d handson && bash handson/tf/scripts/setup.sh
```

### 全リソース削除（クリーンアップ）コマンド

```bash
bash handson/tf/scripts/cleanup.sh
```
