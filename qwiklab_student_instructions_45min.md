# NTTファイナンス様向け Gemini Enterprise ハンズオン 環境セットアップ手順（講師用）

受講者向け Codelab： **https://goo.gle/ntt-gemini** （実体： https://tichiba.github.io/next-finance-ge-handson/ ）

---

## Step 1：Qwiklabs 起動と Cloud Shell ログイン

1. Qwiklabs で **［Start Lab］** をクリックし、左パネルに払い出された **「ユーザー名00」**（講師用）の ID と共通パスワードを確認します。
   - `ユーザー名00`：講師専用（環境構築用・配布禁止）
   - `ユーザー名01〜09`：受講者 9名へ配布（Chromebook 1〜9号機）
   - `ユーザー名10`：予備 1名分
2. **［Open Google Cloud Console］** をシークレットウィンドウで開き、**ユーザー名00** でログインして右上の **［`>_`］（Cloud Shell）** を起動します。

---

## Step 2：環境構築スクリプトの実行（約3〜5分）

1. Cloud Shell で以下のワンライナーを実行します。

```bash
curl -fL -o next-finance-ge-handson-qwiklab.zip https://raw.githubusercontent.com/tichiba/next-finance-ge-handson/main/docs/files/next-finance-ge-handson-qwiklab.zip && unzip -q -o next-finance-ge-handson-qwiklab.zip -d handson && bash handson/tf/scripts/setup.sh
```

2. **途中 `[2/6]` の OAuth 認可（Gmail / Chat 実データ投入）**：
   - `Do you want to continue (Y/n)?` に `y` を入力 → 表示された URL を開いて **ユーザー名00** で承認 → コードを Cloud Shell に貼り付けます。
3. **途中 `[2/6]` の Google Chat API 初回構成**：
   - 別タブで一度 **https://chat.google.com** を開きます（アカウントの Chat プロファイル初回有効化のため、開くだけでOKです）。
   - ターミナルに表示された直リンク URL（`https://console.cloud.google.com/apis/api/chat.googleapis.com/hangouts-chat?project=...`）を開き、以下の4項目を入力して **［保存］** をクリックします（保存するとスクリプトが自動検知して再開します）。
     - **アプリ名**：`Next Finance Bot`
     - **アバターのURL**：`https://developers.google.com/chat/images/quickstart-app-avatar.png`
     - **説明**：`Next Finance Hands-on Helper`
     - **インタラクティブ機能**：オフ（チェックを外す）

※チャットのみ後から再投入・上書きしたい場合：

```bash
python3 handson/tf/scripts/seed_gws_data.py --project-id "$(gcloud config get-value project)" --chat-only --force
```

---

## Step 3：Gemini Enterprise 確認と Codelab の URL 差し替え【必須】

1. `setup.sh` 完了時に出力される管理コンソール URL（または Cloud Console で「Gemini Enterprise」を検索 → `next-finance-ge-app`）を開きます。
2. 左メニュー **［Settings］** で Identity Provider が **「Google Identity」** になっていることを確認します（`setup.sh` の `[1/6]` で自動設定済み。Gmail / Google Chat コネクタは Identity Provider 設定が前提のため、スクリプトはコネクタ作成前に設定します）。
   - 左メニュー **［Connected data stores（接続されたデータストア）］** に **社内規程（GCS）・Gmail・Google Chat の3つ** が表示されていることを確認します。
   - Gmail / Google Chat が無い場合は、`setup.sh` ログの `[3/6]` に出力された `[ERROR] ...` の内容を確認し、Identity Provider を「Google Identity」に設定したうえで、`SKIP_GWS_OAUTH=1 bash handson/tf/scripts/finish_setup.sh` を再実行します（作成済みのリソースはスキップされ、不足分だけが追加・接続されます）。
3. 左メニュー **［Configurations（構成）］→［Feature management（機能管理）］** で、以下の4項目が **オン** になっていることを確認します（スクリプトで自動有効化済みですが、オフの場合はオンにして保存）。
   - **Gemini 4 Argon**（モデル設定）
   - **音声入力**（Speech-to-text）
   - **キャンバス**（Canvas）
   - **モデルセレクタ**（Model selector）
4. 左メニュー **［Integration］** を開き、**「Web アプリへのリンク（Web App URL）」**（`https://vertexaisearch.cloud.google.com/home/cid/...`）をコピーします。
5. **【重要】Codelab（`docs/index.html`）のボタン URL を差し替えて GitHub へ push します**：
   - リポジトリの `docs/index.html`（808行目 `id="btn-open-ge-primary"` の `href`）を、コピーした新しい Web App URL に差し替えて GitHub へ push し、受講者用 Codelab（ https://goo.gle/ntt-gemini ）の **［Gemini Enterprise Web アプリを開く］** ボタンの飛び先を更新します。
   - ローカル（または Jetski）で差し替えて push するワンライナー：

```bash
NEW_URL="ここにコピーしたWeb_App_URLを貼る"
sed -i -E "s|(id=\"btn-open-ge-primary\" href=\")[^\"]+(\")|\1${NEW_URL}\2|" docs/index.html
git commit -am "Update Gemini Enterprise Web App URL in Codelab" && git push origin main
```

---

## Step 4：会場 Chromebook（1〜9号機）の事前セット

1. 貸出 Chromebook を「ゲストとしてブラウジング」で起動し、受講者用 Codelab（ **https://goo.gle/ntt-gemini** ）を開きます。
2. Codelab 内の **［Gemini Enterprise Web アプリを開く］** ボタンをクリックし、各席用の ID（`ユーザー名01`〜`09`）と共通パスワードで事前ログインしておきます。
